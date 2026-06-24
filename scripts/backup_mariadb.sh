#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_DIR/backups}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

DATABASES=(
  "cycling_platform_admin"
  "cycling_platform_raw"
)

timestamp() {
  date +"%Y-%m-%d_%H%M%S"
}

log() {
  printf '[%s] %s\n' "$(date +"%Y-%m-%d %H:%M:%S")" "$*"
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

load_renviron

require_command mysqldump
require_command gzip
require_command find

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

log "Starting MariaDB backup into $BACKUP_DIR"

for database in "${DATABASES[@]}"; do
  output_file="$BACKUP_DIR/${RUN_TIMESTAMP}_${database}.sql.gz"

  log "Backing up $database"

  MYSQL_PWD="$MARIADB_PASSWORD" mysqldump \
    --host="$MARIADB_HOST" \
    --port="$MARIADB_PORT" \
    --user="$MARIADB_USER" \
    --single-transaction \
    --quick \
    --routines \
    --triggers \
    "$database" | gzip > "$output_file"

  log "Wrote $output_file"
done

log "Removing backups older than $RETENTION_DAYS days"

find "$BACKUP_DIR" \
  -type f \
  -name "*.sql.gz" \
  -mtime "+$RETENTION_DAYS" \
  -print \
  -delete

log "MariaDB backup complete"
