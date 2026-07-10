#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RSCRIPT="${RSCRIPT:-}"
LOG_DIR="${LOG_DIR:-}"
DAILY_LOCK="${DAILY_LOCK:-}"
VALIDATION_LOCK="${VALIDATION_LOCK:-}"
LOCK_MAX_AGE_SECONDS="${LOCK_MAX_AGE_SECONDS:-}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-}"
RSCRIPT_CANDIDATES=()

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export LANG="${LANG:-en_GB.UTF-8}"
export LC_ALL="${LC_ALL:-en_GB.UTF-8}"

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

  if [[ -z "${DAILY_LOCK}" ]]; then
    DAILY_LOCK="$(
      read_config_value "automation" "daily_lock_dir" "/tmp/cycling-platform-daily.lock"
    )"
  fi

  if [[ -z "${VALIDATION_LOCK}" ]]; then
    VALIDATION_LOCK="$(
      read_config_value "automation" "validation_lock_dir" "/tmp/cycling-platform-validation.lock"
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

  log "Validation failed: Rscript not found."
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
  local lock_dir="$1"
  local lock_pid_file="${lock_dir}/pid"
  local lock_started_file="${lock_dir}/started_at"
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

acquire_validation_lock() {
  if mkdir "${VALIDATION_LOCK}" 2>/dev/null; then
    echo "$$" > "${VALIDATION_LOCK}/pid"
    date +%s > "${VALIDATION_LOCK}/started_at"
    return
  fi

  if lock_is_stale "${VALIDATION_LOCK}"; then
    log "Validation stale lock removed: ${VALIDATION_LOCK}"
    rm -rf "${VALIDATION_LOCK}"

    if mkdir "${VALIDATION_LOCK}" 2>/dev/null; then
      echo "$$" > "${VALIDATION_LOCK}/pid"
      date +%s > "${VALIDATION_LOCK}/started_at"
      return
    fi
  fi

  log "Validation skipped: another validation run is active."
  exit 0
}

release_validation_lock() {
  rm -rf "${VALIDATION_LOCK}"
}

cd "${PROJECT_DIR}"

load_script_config
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/platform_validation.log"

resolve_rscript

if [[ ! -x "${RSCRIPT}" ]]; then
  log "Validation failed: Rscript is not executable: ${RSCRIPT}"
  exit 1
fi

cleanup_old_logs

if [[ -d "${DAILY_LOCK}" ]]; then
  if lock_is_stale "${DAILY_LOCK}"; then
    log "Validation removed stale daily lock: ${DAILY_LOCK}"
    rm -rf "${DAILY_LOCK}"
  else
    log "Validation skipped: daily platform run is still active."
    exit 0
  fi
fi

acquire_validation_lock

trap release_validation_lock EXIT

echo "==================================================" >> "${LOG_FILE}"
log "Starting platform validation."
log "Using Rscript: ${RSCRIPT}"
log "Log retention days: ${LOG_RETENTION_DAYS}; lock max age seconds: ${LOCK_MAX_AGE_SECONDS}"

set +e
"${RSCRIPT}" run_platform_validation.R \
  >> "${LOG_FILE}" 2>&1

STATUS=$?
set -e

log "Platform validation finished with status ${STATUS}."

exit "${STATUS}"
