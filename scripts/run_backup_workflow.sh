#!/usr/bin/env bash
set -uo pipefail

RUNTIME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_ROOT="${BACKUP_ROOT:-$(dirname "$RUNTIME_DIR")}"
BACKUP_LOG_DIR="${BACKUP_LOG_DIR:-$HOME/Library/Logs/cycling-platform}"
MODE="${1:-backup}"
CAFFEINATE_BIN="${CAFFEINATE_BIN:-/usr/bin/caffeinate}"
SLEEP_PROTECTION_ACTIVE="${CYCLING_PLATFORM_BACKUP_SLEEP_PROTECTED:-0}"
BACKUP_CONFIG_FILE="${BACKUP_CONFIG_FILE:-$BACKUP_ROOT/config/backup.env}"
BACKUP_DIR="${BACKUP_DIR:-$BACKUP_ROOT/data}"
BACKUP_STATUS_FILE="${BACKUP_STATUS_FILE:-$BACKUP_DIR/latest_success.json}"
ALERT_STATE_DIR="${BACKUP_ALERT_STATE_DIR:-$BACKUP_DIR/.alert-state}"
STALE_HOURS="${BACKUP_FRESHNESS_STALE_HOURS:-}"
CRITICAL_HOURS="${BACKUP_FRESHNESS_CRITICAL_HOURS:-}"
NTFY_BASE_URL="${NTFY_BASE_URL:-https://ntfy.sh}"
DEFAULT_BACKUP_COMMAND="$RUNTIME_DIR/scripts/backup_mariadb.sh"
BACKUP_COMMAND="${BACKUP_COMMAND:-$DEFAULT_BACKUP_COMMAND}"
CURL_BIN="${CURL_BIN:-curl}"
PHYSICAL_MARKER=""
FAILURE_CONTEXT=""

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

log() {
  printf '[backup-workflow] %s\n' "$*"
}

if [[ "$MODE" == "backup" && "$SLEEP_PROTECTION_ACTIVE" != "1" ]]; then
  if [[ ! -x "$CAFFEINATE_BIN" ]]; then
    log "Backup cannot start: required sleep-prevention command is unavailable: $CAFFEINATE_BIN"
    exit 69
  fi

  log "Sleep prevention active for complete physical backup (-s -i)."
  exec env CYCLING_PLATFORM_BACKUP_SLEEP_PROTECTED=1 \
    "$CAFFEINATE_BIN" -s -i -- "$0" "$@"
fi

PHYSICAL_MARKER="$(mktemp -t cycling-platform-backup-physical.XXXXXX)"
FAILURE_CONTEXT="$(mktemp -t cycling-platform-backup-failure.XXXXXX)"

read_backup_config() {
  local key="$1"
  local fallback="$2"
  awk -v key="$key" -v fallback="$fallback" '
    $0 == "backups:" { in_backups = 1; next }
    in_backups && $0 ~ /^[^ ]/ { in_backups = 0 }
    in_backups && $0 ~ "^  " key ":" {
      sub("^  " key ":[[:space:]]*", "", $0)
      print $0
      found = 1
      exit
    }
    END { if (!found) print fallback }
  ' "$RUNTIME_DIR/config/platform.yml"
}

# shellcheck disable=SC2329 # Invoked by the EXIT trap.
cleanup() {
  rm -f -- "$PHYSICAL_MARKER" "$FAILURE_CONTEXT"
}
trap cleanup EXIT

if [[ "$MODE" == "paths" ]]; then
  printf 'runtime\t%s\nbackup_root\t%s\nconfig\t%s\ndata\t%s\nlogs\t%s\n' \
    "$RUNTIME_DIR" "$BACKUP_ROOT" "$BACKUP_CONFIG_FILE" "$BACKUP_DIR" "$BACKUP_LOG_DIR"
  exit 0
fi

if [[ -f "$BACKUP_CONFIG_FILE" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$BACKUP_CONFIG_FILE"
  set +a
fi

if [[ "$MODE" == "backup" && ! -f "$BACKUP_CONFIG_FILE" && "$BACKUP_COMMAND" == "$DEFAULT_BACKUP_COMMAND" ]]; then
  printf 'Backup configuration not found:\n%s\n' "$BACKUP_CONFIG_FILE" >&2
  exit 1
fi

STALE_HOURS="${STALE_HOURS:-$(read_backup_config freshness_stale_hours 30)}"
CRITICAL_HOURS="${CRITICAL_HOURS:-$(read_backup_config freshness_critical_hours 48)}"

mkdir -p "$ALERT_STATE_DIR"

send_alert_once() {
  local alert_name="$1"
  local fingerprint="$2"
  local title="$3"
  local body="$4"
  local state_file="$ALERT_STATE_DIR/$alert_name"

  if [[ -f "$state_file" ]] && [[ "$(<"$state_file")" == "$fingerprint" ]]; then
    log "Suppressing duplicate alert: $alert_name"
    return 0
  fi
  if [[ -z "${NTFY_TOPIC:-}" ]]; then
    log "NTFY_TOPIC is unavailable; alert not sent: $alert_name"
    return 1
  fi
  if "$CURL_BIN" --fail --silent --show-error \
    -H "Title: $title" \
    -H "Priority: high" \
    -H "Tags: warning" \
    --data-binary "$body" \
    "$NTFY_BASE_URL/$NTFY_TOPIC" >/dev/null; then
    printf '%s\n' "$fingerprint" > "$state_file"
    return 0
  fi
  log "ntfy delivery failed for $alert_name"
  return 1
}

failure_context_value() {
  local key="$1"
  awk -F '\t' -v key="$key" '$1 == key { sub(/^[^\t]*\t/, ""); print; exit }' \
    "$FAILURE_CONTEXT" 2>/dev/null || true
}

backup_status=0
if [[ "$MODE" == "backup" ]]; then
  log "Starting physical off-host backup."
  BACKUP_PHYSICAL_SUCCESS_MARKER="$PHYSICAL_MARKER" \
    BACKUP_FAILURE_CONTEXT_FILE="$FAILURE_CONTEXT" \
    BACKUP_ROOT="$BACKUP_ROOT" \
    BACKUP_CONFIG_FILE="$BACKUP_CONFIG_FILE" \
    BACKUP_DIR="$BACKUP_DIR" \
    "$BACKUP_COMMAND" || backup_status=$?

  if ((backup_status != 0)); then
    if [[ -s "$PHYSICAL_MARKER" ]]; then
      failure_class="observability/finalizer"
    else
      failure_class="$(failure_context_value failure_class)"
      failure_class="${failure_class:-unknown_physical_failure}"
    fi
    latest_prefix="$(sed -n '1p' "$PHYSICAL_MARKER" 2>/dev/null || true)"
    failed_database="$(failure_context_value database_name)"
    failed_operation="$(failure_context_value operation)"
    failed_attempt="$(failure_context_value attempt)"
    max_attempts="$(failure_context_value max_attempts)"
    error_summary="$(failure_context_value error_summary)"
    verified_count="$(failure_context_value verified_database_count)"
    expected_count="$(failure_context_value expected_database_count)"
    failure_details="Failure class: $failure_class
Complete verified set: ${latest_prefix:-none}"
    if [[ -n "$failed_database" ]]; then
      failure_details="$failure_details
Database: $failed_database"
    fi
    if [[ -n "$failed_operation" ]]; then
      failure_details="$failure_details
Operation: $failed_operation"
    fi
    if [[ -n "$failed_attempt" && -n "$max_attempts" ]]; then
      failure_details="$failure_details
Attempts: $failed_attempt/$max_attempts"
    fi
    if [[ -n "$verified_count" && -n "$expected_count" ]]; then
      failure_details="$failure_details
Partial verified files: $verified_count/$expected_count"
    fi
    if [[ -n "$error_summary" ]]; then
      failure_details="$failure_details
Error: $error_summary"
    fi
    send_alert_once \
      "backup-failure" \
      "failure:$failure_class:${failed_database:-none}:${latest_prefix:-none}" \
      "cycling-platform backup FAILED" \
      "Host: $(hostname -s)
Status: FAILED
$failure_details
See: backup-launchd.log" || true
  else
    rm -f -- "$ALERT_STATE_DIR/backup-failure"
  fi
elif [[ "$MODE" != "check" && "$MODE" != "health" ]]; then
  printf 'Usage: %s [backup|check|health]\n' "$0" >&2
  exit 2
fi

health="$(
  cd "$RUNTIME_DIR" &&
    Rscript --vanilla \
      scripts/check_backup_physical_health.R \
      "$BACKUP_STATUS_FILE" \
      "$STALE_HOURS" \
      "$CRITICAL_HOURS"
)" || health="MALFORMED	NA	none"

IFS=$'\t' read -r freshness age_hours run_prefix <<< "$health"

if [[ "$MODE" == "backup" ]] && ((backup_status == 0)); then
  attempted_prefix="$(sed -n '1p' "$PHYSICAL_MARKER" 2>/dev/null || true)"
  if [[ -z "$attempted_prefix" ]] || [[ "$run_prefix" != "$attempted_prefix" ]]; then
    backup_status=1
    send_alert_once \
      "backup-failure" \
      "failure:observability/latest-success-not-advanced:${attempted_prefix:-none}" \
      "cycling-platform backup FAILED" \
      "Host: $(hostname -s)
Status: FAILED
Failure class: observability/latest-success-not-advanced
Complete verified set: ${attempted_prefix:-none}
Published complete set: ${run_prefix:-none}" || true
  fi
fi

case "$freshness" in
  HEALTHY)
    rm -f -- "$ALERT_STATE_DIR/backup-stale"
    ;;
  STALE|CRITICAL|MISSING|MALFORMED|INCOMPLETE)
    send_alert_once \
      "backup-stale" \
      "freshness:$freshness:$run_prefix" \
      "cycling-platform backup $freshness" \
      "Host: $(hostname -s)
Physical recovery status: $freshness
Age hours: $age_hours
Latest verified prefix: $run_prefix
Authority: Mac latest_success.json" || true
    ;;
esac

exit "$backup_status"
