#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_SCRIPT="${PROJECT_DIR}/run_daily_platform.R"
PROJECT_RENVIRON="${PROJECT_DIR}/.Renviron"
RUNTIME_PROJECT_DIR=""
RUNTIME_RUN_SCRIPT=""
RUNTIME_RENVIRON=""
RSCRIPT="${RSCRIPT:-}"
LOG_DIR="${LOG_DIR:-}"
LOCK_DIR="${LOCK_DIR:-}"
LOCK_MAX_AGE_SECONDS="${LOCK_MAX_AGE_SECONDS:-}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-}"
RSCRIPT_CANDIDATES=()

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export LANG="${LANG:-en_GB.UTF-8}"
export LC_ALL="${LC_ALL:-en_GB.UTF-8}"
export RENV_PROJECT="${RENV_PROJECT:-${PROJECT_DIR}}"

LOG_FILE=""

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log() {
  printf '%s %s\n' "$(timestamp)" "$*" >> "${LOG_FILE}"
}

read_config_value() {
  local section="$1"
  local key="$2"
  local default_value="$3"

  awk -v section="${section}" -v key="${key}" -v default_value="${default_value}" '
    $0 == section ":" {
      in_section = 1
      next
    }
    in_section && $0 ~ /^[^ ]/ {
      in_section = 0
    }
    in_section {
      pattern = "^  " key ":"
      if ($0 ~ pattern) {
        sub(pattern, "", $0)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
        print $0
        found = 1
        exit
      }
    }
    END {
      if (!found) {
        print default_value
      }
    }
  ' config/platform.yml
}

read_config_list() {
  local section="$1"
  local key="$2"

  awk -v section="${section}" -v key="${key}" '
    $0 == section ":" {
      in_section = 1
      next
    }
    in_section && $0 ~ /^[^ ]/ {
      exit
    }
    in_section && $0 ~ "^  " key ":" {
      in_list = 1
      next
    }
    in_list && $0 ~ /^    - / {
      sub(/^    - /, "", $0)
      print $0
      next
    }
    in_list && $0 !~ /^    - / {
      exit
    }
  ' config/platform.yml
}

positive_integer_or_default() {
  local value="$1"
  local default_value="$2"

  if [[ "${value}" =~ ^[0-9]+$ ]] && ((value > 0)); then
    printf '%s' "${value}"
  else
    printf '%s' "${default_value}"
  fi
}

load_script_config() {
  local configured_log_dir
  local configured_candidates

  if [[ -z "${LOG_DIR}" ]]; then
    configured_log_dir="$(
      read_config_value "logging" "directory" "logs"
    )"

    if [[ "${configured_log_dir}" = /* ]]; then
      LOG_DIR="${configured_log_dir}"
    else
      LOG_DIR="${PROJECT_DIR}/${configured_log_dir}"
    fi
  fi

  if [[ -z "${LOCK_DIR}" ]]; then
    LOCK_DIR="$(
      read_config_value "automation" "daily_lock_dir" "/tmp/cycling-platform-daily.lock"
    )"
  fi

  if [[ -z "${LOG_RETENTION_DAYS}" ]]; then
    LOG_RETENTION_DAYS="$(
      read_config_value "logging" "retention_days" "30"
    )"
  fi
  LOG_RETENTION_DAYS="$(
    positive_integer_or_default "${LOG_RETENTION_DAYS}" "30"
  )"

  if [[ -z "${LOCK_MAX_AGE_SECONDS}" ]]; then
    LOCK_MAX_AGE_SECONDS="$(
      read_config_value "automation" "lock_max_age_seconds" "21600"
    )"
  fi
  LOCK_MAX_AGE_SECONDS="$(
    positive_integer_or_default "${LOCK_MAX_AGE_SECONDS}" "21600"
  )"

  configured_candidates="$(
    read_config_list "automation" "rscript_candidates"
  )"

  if [[ -n "${configured_candidates}" ]]; then
    while IFS= read -r candidate; do
      RSCRIPT_CANDIDATES+=("${candidate}")
    done <<< "${configured_candidates}"
  else
    RSCRIPT_CANDIDATES=(
      "/usr/local/bin/Rscript"
      "/opt/homebrew/bin/Rscript"
      "/usr/bin/Rscript"
    )
  fi
}

resolve_rscript() {
  if [[ -n "${RSCRIPT}" ]]; then
    return
  fi

  for candidate in "${RSCRIPT_CANDIDATES[@]}"; do
    if [[ -x "${candidate}" ]]; then
      RSCRIPT="${candidate}"
      return
    fi
  done

  if command -v Rscript >/dev/null 2>&1; then
    RSCRIPT="$(command -v Rscript)"
    return
  fi

  log "Daily platform run failed: Rscript not found."
  exit 1
}

cleanup_old_logs() {
  find "${LOG_DIR}" \
    -type f \
    -name "*.log" \
    ! -name "$(basename "${LOG_FILE}")" \
    -mtime "+${LOG_RETENTION_DAYS}" \
    -print \
    -delete >> "${LOG_FILE}" 2>&1 || true
}

lock_is_stale() {
  local lock_pid_file="${LOCK_DIR}/pid"
  local lock_started_file="${LOCK_DIR}/started_at"
  local lock_age_seconds
  local lock_pid
  local now
  local started_at

  if [[ -f "${lock_pid_file}" ]]; then
    lock_pid="$(cat "${lock_pid_file}")"

    if [[ -n "${lock_pid}" ]] && ! kill -0 "${lock_pid}" 2>/dev/null; then
      return 0
    fi
  fi

  if [[ -f "${lock_started_file}" ]]; then
    now="$(date +%s)"
    started_at="$(cat "${lock_started_file}")"

    if [[ ! "${started_at}" =~ ^[0-9]+$ ]]; then
      return 0
    fi

    lock_age_seconds=$((now - started_at))

    if ((lock_age_seconds > LOCK_MAX_AGE_SECONDS)); then
      return 0
    fi
  fi

  return 1
}

acquire_lock() {
  if mkdir "${LOCK_DIR}" 2>/dev/null; then
    echo "$$" > "${LOCK_DIR}/pid"
    date +%s > "${LOCK_DIR}/started_at"
    return
  fi

  if lock_is_stale; then
    log "Daily platform stale lock removed: ${LOCK_DIR}"
    rm -rf "${LOCK_DIR}"

    if mkdir "${LOCK_DIR}" 2>/dev/null; then
      echo "$$" > "${LOCK_DIR}/pid"
      date +%s > "${LOCK_DIR}/started_at"
      return
    fi
  fi

  log "Daily platform run skipped: another run is active."
  exit 0
}

release_lock() {
  rm -rf "${LOCK_DIR}"
}

cleanup_runtime_project() {
  if [[ -n "${RUNTIME_PROJECT_DIR}" && -d "${RUNTIME_PROJECT_DIR}" ]]; then
    rm -rf "${RUNTIME_PROJECT_DIR}"
  fi
}

persist_runtime_renviron() {
  if [[ -z "${RUNTIME_RENVIRON}" || ! -f "${RUNTIME_RENVIRON}" ]]; then
    return
  fi

  if [[ ! -f "${PROJECT_RENVIRON}" ]] || ! cmp -s "${RUNTIME_RENVIRON}" "${PROJECT_RENVIRON}"; then
    cp "${RUNTIME_RENVIRON}" "${PROJECT_RENVIRON}"
    chmod 600 "${PROJECT_RENVIRON}" || true
    log "Runtime .Renviron changes persisted to project .Renviron."
  fi
}

cleanup_on_exit() {
  release_lock
  persist_runtime_renviron
  cleanup_runtime_project
}

prepare_runtime_project() {
  RUNTIME_PROJECT_DIR="/tmp/cycling-platform-daily-runtime-$$"
  RUNTIME_RUN_SCRIPT="${RUNTIME_PROJECT_DIR}/run_daily_platform.R"
  RUNTIME_RENVIRON="${RUNTIME_PROJECT_DIR}/.Renviron"

  rm -rf "${RUNTIME_PROJECT_DIR}"
  mkdir -p "${RUNTIME_PROJECT_DIR}"
  chmod 700 "${RUNTIME_PROJECT_DIR}"

  rsync -a \
    --exclude ".git" \
    --exclude ".Renviron" \
    --exclude "logs" \
    --exclude "backups" \
    "${PROJECT_DIR}/" \
    "${RUNTIME_PROJECT_DIR}/"

  if [[ -r "${PROJECT_RENVIRON}" ]]; then
    cp "${PROJECT_RENVIRON}" "${RUNTIME_RENVIRON}"
    chmod 600 "${RUNTIME_RENVIRON}" || true
  else
    log "Warning: project .Renviron is not readable by the wrapper: ${PROJECT_RENVIRON}"
  fi

  export RENV_PROJECT="${RUNTIME_PROJECT_DIR}"
  export CYCLING_PLATFORM_RENVIRON_PATH="${RUNTIME_RENVIRON}"
  export R_ENVIRON_USER="${RUNTIME_RENVIRON}"
}

cd "${PROJECT_DIR}"

load_script_config
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/daily_platform.log"

resolve_rscript

if [[ ! -x "${RSCRIPT}" ]]; then
  log "Daily platform run failed: Rscript is not executable: ${RSCRIPT}"
  exit 1
fi

cleanup_old_logs
acquire_lock

trap cleanup_on_exit EXIT

prepare_runtime_project

echo "==================================================" >> "${LOG_FILE}"
log "Starting daily platform run."
log "Using Rscript: ${RSCRIPT}"
log "Using project dir: ${PROJECT_DIR}"
log "Using runtime project dir: ${RUNTIME_PROJECT_DIR}"
log "Using RENV_PROJECT: ${RENV_PROJECT}"
log "Using R_ENVIRON_USER: ${R_ENVIRON_USER}"
log "Using runtime .Renviron: ${RUNTIME_RENVIRON}"
log "Using run script: ${RUNTIME_RUN_SCRIPT}"
log "Using Rscript input mode: stdin"
log "Log retention days: ${LOG_RETENTION_DAYS}; lock max age seconds: ${LOCK_MAX_AGE_SECONDS}"

if [[ ! -r "${RUNTIME_RUN_SCRIPT}" ]]; then
  log "Daily platform run failed: run script is not readable: ${RUNTIME_RUN_SCRIPT}"
  exit 1
fi

set +e
cd "${RUNTIME_PROJECT_DIR}"
"${RSCRIPT}" - \
  < "${RUNTIME_RUN_SCRIPT}" \
  >> "${LOG_FILE}" 2>&1

STATUS=$?
set -e

log "Daily platform run finished with status ${STATUS}."

exit "${STATUS}"
