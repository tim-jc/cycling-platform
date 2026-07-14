#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="${BACKUP_DIR:-}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-}"
TEMPORARY_FILE_RETENTION_DAYS="${BACKUP_TEMPORARY_FILE_RETENTION_DAYS:-}"
LOCK_DIR="${BACKUP_LOCK_DIR:-}"
LOCK_MAX_AGE_SECONDS="${BACKUP_LOCK_MAX_AGE_SECONDS:-}"
MYSQLDUMP="${MYSQLDUMP:-}"
MYSQLDUMP_CANDIDATES=()
MYSQLDUMP_EXTRA_ARGS=()
DATABASES=()

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export LANG="${LANG:-en_GB.UTF-8}"
export LC_ALL="${LC_ALL:-en_GB.UTF-8}"

timestamp() {
  date +"%Y-%m-%d_%H%M%S"
}

log() {
  printf '[%s] %s\n' "$(date +"%Y-%m-%d %H:%M:%S")" "$*"
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
  ' "$PROJECT_DIR/config/platform.yml"
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
  ' "$PROJECT_DIR/config/platform.yml"
}

positive_integer_or_default() {
  local value="$1"
  local default_value="$2"

  if [[ "$value" =~ ^[0-9]+$ ]] && ((value > 0)); then
    printf '%s' "$value"
  else
    printf '%s' "$default_value"
  fi
}

load_script_config() {
  local configured_backup_dir
  local configured_databases
  local configured_dump_candidates

  if [[ -z "$BACKUP_DIR" ]]; then
    configured_backup_dir="$(
      read_config_value "backups" "directory" "backups"
    )"

    if [[ "$configured_backup_dir" = /* ]]; then
      BACKUP_DIR="$configured_backup_dir"
    else
      BACKUP_DIR="$PROJECT_DIR/$configured_backup_dir"
    fi
  fi

  if [[ -z "$RETENTION_DAYS" ]]; then
    RETENTION_DAYS="$(
      read_config_value "backups" "retention_days" "30"
    )"
  fi
  RETENTION_DAYS="$(
    positive_integer_or_default "$RETENTION_DAYS" "30"
  )"

  if [[ -z "$TEMPORARY_FILE_RETENTION_DAYS" ]]; then
    TEMPORARY_FILE_RETENTION_DAYS="$(
      read_config_value "backups" "temporary_file_retention_days" "1"
    )"
  fi
  TEMPORARY_FILE_RETENTION_DAYS="$(
    positive_integer_or_default "$TEMPORARY_FILE_RETENTION_DAYS" "1"
  )"

  if [[ -z "$LOCK_DIR" ]]; then
    LOCK_DIR="$(
      read_config_value "backups" "lock_dir" "/tmp/cycling-platform-backup.lock"
    )"
  fi

  if [[ -z "$LOCK_MAX_AGE_SECONDS" ]]; then
    LOCK_MAX_AGE_SECONDS="$(
      read_config_value "backups" "lock_max_age_seconds" "21600"
    )"
  fi
  LOCK_MAX_AGE_SECONDS="$(
    positive_integer_or_default "$LOCK_MAX_AGE_SECONDS" "21600"
  )"

  configured_databases="$(
    read_config_list "backups" "databases"
  )"

  if [[ -n "$configured_databases" ]]; then
    while IFS= read -r database; do
      DATABASES+=("$database")
    done <<< "$configured_databases"
  else
    DATABASES=(
      "cycling_platform_admin"
      "cycling_platform_raw"
      "cycling_platform_silver"
      "cycling_platform_gold"
    )
  fi

  configured_dump_candidates="$(
    read_config_list "backups" "dump_command_candidates"
  )"

  if [[ -n "$configured_dump_candidates" ]]; then
    while IFS= read -r candidate; do
      MYSQLDUMP_CANDIDATES+=("$candidate")
    done <<< "$configured_dump_candidates"
  else
    MYSQLDUMP_CANDIDATES=(
      "/opt/homebrew/bin/mysqldump"
      "/opt/homebrew/bin/mariadb-dump"
      "/usr/local/bin/mysqldump"
      "/usr/local/bin/mariadb-dump"
      "/usr/bin/mysqldump"
      "/usr/bin/mariadb-dump"
    )
  fi
}

lock_is_stale() {
  local lock_pid_file="$LOCK_DIR/pid"
  local lock_started_file="$LOCK_DIR/started_at"
  local lock_age_seconds
  local lock_pid
  local now
  local started_at

  if [[ -f "$lock_pid_file" ]]; then
    lock_pid="$(cat "$lock_pid_file")"

    if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
      return 0
    fi
  fi

  if [[ -f "$lock_started_file" ]]; then
    now="$(date +%s)"
    started_at="$(cat "$lock_started_file")"

    if [[ ! "$started_at" =~ ^[0-9]+$ ]]; then
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
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "$$" > "$LOCK_DIR/pid"
    date +%s > "$LOCK_DIR/started_at"
    return
  fi

  if lock_is_stale; then
    log "Backup stale lock removed: $LOCK_DIR"
    rm -rf "$LOCK_DIR"

    if mkdir "$LOCK_DIR" 2>/dev/null; then
      echo "$$" > "$LOCK_DIR/pid"
      date +%s > "$LOCK_DIR/started_at"
      return
    fi
  fi

  log "Backup skipped: another backup run is active."
  exit 0
}

release_lock() {
  rm -rf "$LOCK_DIR"
}

load_renviron() {
  local renviron_file="$PROJECT_DIR/.Renviron"

  if [[ -f "$renviron_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$renviron_file"
    set +a
  fi
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "Required command not found: $1"
    exit 1
  fi
}

resolve_mysqldump() {
  if [[ -n "$MYSQLDUMP" ]]; then
    if [[ -x "$MYSQLDUMP" ]]; then
      return
    fi

    log "Configured MYSQLDUMP is not executable: $MYSQLDUMP"
    exit 1
  fi

  for candidate in "${MYSQLDUMP_CANDIDATES[@]}"; do
    if [[ -x "$candidate" ]]; then
      MYSQLDUMP="$candidate"
      return
    fi
  done

  if command -v mysqldump >/dev/null 2>&1; then
    MYSQLDUMP="$(command -v mysqldump)"
    return
  fi

  if command -v mariadb-dump >/dev/null 2>&1; then
    MYSQLDUMP="$(command -v mariadb-dump)"
    return
  fi

  log "Required command not found: mysqldump or mariadb-dump"
  log "Install MariaDB/MySQL client tools or set MYSQLDUMP to the dump binary path."
  exit 1
}

configure_mysqldump_extra_args() {
  local help_output

  help_output="$("$MYSQLDUMP" --help 2>/dev/null || true)"

  if grep -q -- "--column-statistics" <<< "$help_output"; then
    MYSQLDUMP_EXTRA_ARGS+=("--skip-column-statistics")
  fi
}

load_script_config

resolve_mysqldump
configure_mysqldump_extra_args
require_command gzip
require_command find

load_renviron

mkdir -p "$BACKUP_DIR"

if [[ -z "${MARIADB_HOST:-}" ]]; then
  log "MARIADB_HOST is not set."
  exit 1
fi

if [[ -z "${MARIADB_PORT:-}" ]]; then
  log "MARIADB_PORT is not set."
  exit 1
fi

if [[ -z "${MARIADB_USER:-}" ]]; then
  log "MARIADB_USER is not set."
  exit 1
fi

if [[ -z "${MARIADB_PASSWORD:-}" ]]; then
  log "MARIADB_PASSWORD is not set."
  exit 1
fi

RUN_TIMESTAMP="$(timestamp)"

acquire_lock

trap release_lock EXIT

log "Starting MariaDB backup into $BACKUP_DIR"
log "Using dump command: $MYSQLDUMP"
if [[ "${#MYSQLDUMP_EXTRA_ARGS[@]}" -gt 0 ]]; then
  log "Using dump options: ${MYSQLDUMP_EXTRA_ARGS[*]}"
fi
log "Databases: ${DATABASES[*]}"
log "Retention days: $RETENTION_DAYS; temporary file retention days: $TEMPORARY_FILE_RETENTION_DAYS; lock max age seconds: $LOCK_MAX_AGE_SECONDS"

for database in "${DATABASES[@]}"; do
  output_file="$BACKUP_DIR/${RUN_TIMESTAMP}_${database}.sql.gz"
  temporary_output_file="${output_file}.tmp"

  log "Backing up $database"

  if MYSQL_PWD="$MARIADB_PASSWORD" "$MYSQLDUMP" \
    --host="$MARIADB_HOST" \
    --port="$MARIADB_PORT" \
    --user="$MARIADB_USER" \
    --single-transaction \
    --quick \
    --routines \
    --triggers \
    "${MYSQLDUMP_EXTRA_ARGS[@]}" \
    "$database" | gzip > "$temporary_output_file"; then
    :
  else
    rm -f "$temporary_output_file"
    log "Backup failed for $database"
    exit 1
  fi

  if [[ ! -s "$temporary_output_file" ]]; then
    rm -f "$temporary_output_file"
    log "Backup verification failed for $database: dump file is empty."
    exit 1
  fi

  if ! gzip -t "$temporary_output_file"; then
    rm -f "$temporary_output_file"
    log "Backup verification failed for $database: gzip integrity check failed."
    exit 1
  fi

  mv "$temporary_output_file" "$output_file"

  log "Wrote and verified $output_file"
done

log "Removing backups older than $RETENTION_DAYS days"

find "$BACKUP_DIR" \
  -type f \
  -name "*.sql.gz" \
  -mtime "+$RETENTION_DAYS" \
  -print \
  -delete

log "Removing stale temporary backup files older than $TEMPORARY_FILE_RETENTION_DAYS days"

find "$BACKUP_DIR" \
  -type f \
  -name "*.sql.gz.tmp" \
  -mtime "+$TEMPORARY_FILE_RETENTION_DAYS" \
  -print \
  -delete

log "MariaDB backup complete"
