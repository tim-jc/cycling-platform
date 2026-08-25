#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SUPPORT_ROOT="${BACKUP_INSTALL_ROOT:-$HOME/Library/Application Support/cycling-platform/backup}"
RUNTIME_DIR="${BACKUP_RUNTIME_DIR:-$APP_SUPPORT_ROOT/runtime}"
CONFIG_DIR="${BACKUP_CONFIG_DIR:-$APP_SUPPORT_ROOT/config}"
CONFIG_FILE="${BACKUP_CONFIG_FILE:-$CONFIG_DIR/backup.env}"
DATA_DIR="${BACKUP_DATA_DIR:-$APP_SUPPORT_ROOT/data}"
LEGACY_DATA_DIR="${BACKUP_LEGACY_DATA_DIR:-$PROJECT_DIR/backups}"
LOG_DIR="${BACKUP_LOG_DIR:-$HOME/Library/Logs/cycling-platform}"
AGENT_DIR="${BACKUP_LAUNCHD_AGENT_DIR:-$HOME/Library/LaunchAgents}"
SOURCE_PLIST_DIR="$PROJECT_DIR/config/launchd"
MODE="${1:-install}"
RENDER_TARGET="${2:-}"
CAFFEINATE_BIN="${CAFFEINATE_BIN:-/usr/bin/caffeinate}"
LABELS=(
  com.tim-jc.cycling-platform-backup
  com.tim-jc.cycling-platform-backup-health
)
RUNTIME_FILES=(
  scripts/run_backup_workflow.sh
  scripts/backup_mariadb.sh
  scripts/check_backup_physical_health.R
  scripts/finalize_backup_observability.R
  scripts/plan_backup_retention.R
  scripts/report_backup_runtime_health.R
  R/backup/bootstrap_backup_runtime.R
  R/config/platform_database_inventory.R
  R/database/get_connection.R
  R/database/execute_sql_file.R
  R/utils/backup_observability.R
  sql/admin/080_create_backup_run.sql
  sql/admin/081_create_backup_run_file.sql
  sql/admin/082_create_backup_reconciliation_run.sql
  config/platform_databases.tsv
)
SECRET_KEYS=(
  MARIADB_HOST
  MARIADB_PORT
  MARIADB_USER
  MARIADB_PASSWORD
  NTFY_TOPIC
  NTFY_BASE_URL
  BACKUP_RETENTION_DAYS
  BACKUP_TEMPORARY_FILE_RETENTION_DAYS
  BACKUP_FRESHNESS_STALE_HOURS
  BACKUP_FRESHNESS_CRITICAL_HOURS
  BACKUP_DUMP_MAX_ATTEMPTS
  BACKUP_DUMP_RETRY_SLEEP_SECONDS
)

log() {
  printf '[backup-launchd] %s\n' "$*"
}

usage() {
  cat <<EOF
Usage: $0 install|render [directory]|verify|status|health|uninstall
EOF
}

require_macos_command() {
  command -v "$1" >/dev/null 2>&1 || {
    log "Required command not found: $1"
    exit 1
  }
}

source_commit() {
  git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || printf 'unknown\n'
}

render_backup_platform_config() {
  local target="$1"
  awk '
    $0 == "backups:" { in_backups = 1 }
    in_backups && NR > 1 && $0 ~ /^[^ ]/ && $0 != "backups:" { exit }
    in_backups { print }
  ' "$PROJECT_DIR/config/platform.yml" > "$target"
  [[ -s "$target" ]] || {
    log "Unable to render backup configuration from config/platform.yml."
    return 1
  }
}

write_runtime_manifest() {
  local root="$1"
  local hashes="$root/runtime-manifest.sha256"
  local manifest="$root/runtime-manifest.json"
  local installed_at commit file hash separator

  : > "$hashes"
  for file in "${RUNTIME_FILES[@]}" config/platform.yml; do
    (
      cd "$root"
      shasum -a 256 "$file"
    ) >> "$hashes"
  done

  installed_at="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  commit="$(source_commit)"
  {
    printf '{\n'
    printf '  "runtime_schema_version": 1,\n'
    printf '  "source_commit": "%s",\n' "$commit"
    printf '  "installed_at": "%s",\n' "$installed_at"
    printf '  "files": [\n'
    separator=""
    while read -r hash file; do
      printf '%s    {"path": "%s", "sha256": "%s"}' \
        "$separator" "$file" "$hash"
      separator=$',\n'
    done < "$hashes"
    printf '\n  ]\n}\n'
  } > "$manifest"
}

render_runtime() {
  local target="$1"
  local file source target_file

  [[ -n "$target" && "$target" != "/" ]] || {
    log "Refusing to render to an unsafe target."
    return 1
  }

  mkdir -p "$target"
  for file in "${RUNTIME_FILES[@]}"; do
    source="$PROJECT_DIR/$file"
    target_file="$target/$file"
    [[ -f "$source" ]] || {
      log "Runtime source is missing: $file"
      return 1
    }
    mkdir -p "$(dirname "$target_file")"
    cp -p "$source" "$target_file"
  done
  mkdir -p "$target/config"
  render_backup_platform_config "$target/config/platform.yml"
  chmod 0755 "$target/scripts/"*.sh "$target/scripts/"*.R
  write_runtime_manifest "$target"
}

render_plist() {
  local label="$1"
  sed \
    -e "s|__RUNTIME_DIR__|$RUNTIME_DIR|g" \
    -e "s|__CONFIG_FILE__|$CONFIG_FILE|g" \
    -e "s|__DATA_DIR__|$DATA_DIR|g" \
    -e "s|__LOG_DIR__|$LOG_DIR|g" \
    "$SOURCE_PLIST_DIR/$label.plist"
}

extract_backup_config() {
  local source_file="$PROJECT_DIR/.Renviron"
  local temporary="$CONFIG_FILE.tmp"
  local key line

  if [[ -f "$CONFIG_FILE" ]]; then
    chmod 0600 "$CONFIG_FILE"
    return
  fi
  [[ -f "$source_file" ]] || {
    log "Cannot create backup.env: repository .Renviron is unavailable."
    return 1
  }

  umask 077
  : > "$temporary"
  for key in "${SECRET_KEYS[@]}"; do
    line="$(grep -E "^[[:space:]]*(export[[:space:]]+)?${key}=" "$source_file" | tail -1 || true)"
    if [[ -n "$line" ]]; then
      line="${line#export }"
      printf '%s\n' "$line" >> "$temporary"
    fi
  done
  mv "$temporary" "$CONFIG_FILE"
  chmod 0600 "$CONFIG_FILE"
}

validate_config() {
  local permissions missing key value
  [[ -f "$CONFIG_FILE" ]] || {
    log "Backup config is missing: $CONFIG_FILE"
    return 1
  }
  permissions="$(stat -f '%Lp' "$CONFIG_FILE" 2>/dev/null || stat -c '%a' "$CONFIG_FILE")"
  [[ "$permissions" == "600" ]] || {
    log "Backup config permissions must be 0600; found $permissions."
    return 1
  }
  missing=()
  set -a
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  set +a
  for key in MARIADB_HOST MARIADB_PORT MARIADB_USER MARIADB_PASSWORD; do
    value="${!key:-}"
    [[ -n "${value//[[:space:]]/}" ]] || missing+=("$key")
  done
  if ((${#missing[@]} > 0)); then
    log "Backup config is missing required keys: ${missing[*]}"
    return 1
  fi
  [[ "$MARIADB_PORT" =~ ^[0-9]+$ ]] &&
    ((MARIADB_PORT >= 1 && MARIADB_PORT <= 65535)) || {
      log "Backup config MARIADB_PORT must be an integer between 1 and 65535."
      return 1
    }
}

migrate_backup_data() {
  local old_data="$LEGACY_DATA_DIR"
  local old_count new_count source_file relative source_hash destination_hash
  [[ -d "$old_data" ]] || return 0
  mkdir -p "$DATA_DIR"
  old_count="$(find "$old_data" -maxdepth 1 -type f \( -name '*.sql.gz' -o -name 'latest_success.json' \) | wc -l | tr -d ' ')"
  rsync -a --ignore-existing "$old_data/" "$DATA_DIR/"
  new_count="$(find "$DATA_DIR" -maxdepth 1 -type f \( -name '*.sql.gz' -o -name 'latest_success.json' \) | wc -l | tr -d ' ')"
  ((new_count >= old_count)) || {
    log "Backup data migration verification failed ($old_count source, $new_count destination)."
    return 1
  }
  while IFS= read -r -d '' source_file; do
    relative="${source_file#"$old_data"/}"
    [[ -f "$DATA_DIR/$relative" ]] || {
      log "Backup data migration omitted: $relative"
      return 1
    }
    source_hash="$(shasum -a 256 "$source_file" | awk '{print $1}')"
    destination_hash="$(shasum -a 256 "$DATA_DIR/$relative" | awk '{print $1}')"
    [[ "$source_hash" == "$destination_hash" ]] || {
      log "Backup data migration hash mismatch: $relative"
      return 1
    }
  done < <(
    find "$old_data" -maxdepth 1 -type f \
      -name '*.sql.gz' -print0
  )
  log "Preserved $old_count existing backup archive/state files in the new data directory."
}

install_plists() {
  local label target temporary
  mkdir -p "$AGENT_DIR" "$LOG_DIR"
  for label in "${LABELS[@]}"; do
    target="$AGENT_DIR/$label.plist"
    temporary="$target.tmp"
    render_plist "$label" > "$temporary"
    plutil -lint "$temporary" >/dev/null
    mv "$temporary" "$target"
    launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$(id -u)" "$target"
  done
}

remove_legacy_backup_cron() {
  [[ "${BACKUP_SKIP_CRON_MIGRATION:-0}" != "1" ]] || return 0
  command -v crontab >/dev/null 2>&1 || return 0
  local current filtered
  current="$(mktemp)"
  filtered="$(mktemp)"
  crontab -l > "$current" 2>/dev/null || : > "$current"
  grep -Ev 'cycling-platform/(scripts/)?(backup_mariadb|run_backup_workflow)[.]sh' \
    "$current" > "$filtered" || true
  if ! cmp -s "$current" "$filtered"; then
    crontab "$filtered"
    log "Removed superseded cycling-platform backup cron entry."
  fi
  rm -f "$current" "$filtered"
}

verify_runtime() {
  local label plist permissions direct_paths expected_backup_root
  [[ -d "$RUNTIME_DIR" ]] || { log "Runtime is not installed: $RUNTIME_DIR"; return 1; }
  [[ -x "$CAFFEINATE_BIN" ]] || { log "Required sleep-prevention command is unavailable: $CAFFEINATE_BIN"; return 1; }
  [[ -f "$RUNTIME_DIR/runtime-manifest.json" ]] || { log "Runtime manifest is missing."; return 1; }
  [[ -f "$RUNTIME_DIR/runtime-manifest.sha256" ]] || { log "Runtime hash manifest is missing."; return 1; }
  (cd "$RUNTIME_DIR" && shasum -a 256 -c runtime-manifest.sha256 >/dev/null) || {
    log "Runtime drift detected."
    return 1
  }
  validate_config
  permissions="$(stat -f '%Lp' "$CONFIG_DIR" 2>/dev/null || stat -c '%a' "$CONFIG_DIR")"
  [[ "$permissions" == "700" ]] || { log "Config directory permissions must be 0700; found $permissions."; return 1; }
  [[ -w "$DATA_DIR" && -w "$LOG_DIR" ]] || { log "Backup data or log directory is not writable."; return 1; }
  for label in "${LABELS[@]}"; do
    plist="$AGENT_DIR/$label.plist"
    [[ -f "$plist" ]] || { log "LaunchAgent is missing: $plist"; return 1; }
    plutil -lint "$plist" >/dev/null
    if grep -q '/Documents/' "$plist"; then
      log "LaunchAgent contains a forbidden Documents path: $plist"
      return 1
    fi
  done
  if grep -R -q '/Documents/' "$RUNTIME_DIR"; then
    log "Installed runtime contains a forbidden Documents path."
    return 1
  fi
  if grep -R -F -q "$PROJECT_DIR" "$RUNTIME_DIR"; then
    log "Installed runtime contains a source-checkout path."
    return 1
  fi
  grep -Fq 'CYCLING_PLATFORM_BACKUP_SLEEP_PROTECTED' \
    "$RUNTIME_DIR/scripts/run_backup_workflow.sh" &&
    grep -Fq '"$CAFFEINATE_BIN" -s -i -- "$0" "$@"' \
      "$RUNTIME_DIR/scripts/run_backup_workflow.sh" || {
    log "Installed backup workflow does not contain the required process-bound sleep assertion."
    return 1
  }
  [[ ! -e "$RUNTIME_DIR/backup.env" && ! -e "$RUNTIME_DIR/backups" && ! -e "$RUNTIME_DIR/data" ]] || {
    log "Mutable backup config/data was found beneath the runtime directory."
    return 1
  }
  expected_backup_root="$(dirname "$RUNTIME_DIR")"
  direct_paths="$(
    env -i HOME="$HOME" PATH="$PATH" \
      "$RUNTIME_DIR/scripts/run_backup_workflow.sh" paths
  )"
  grep -Fqx $'runtime\t'"$RUNTIME_DIR" <<< "$direct_paths" &&
    grep -Fqx $'backup_root\t'"$expected_backup_root" <<< "$direct_paths" &&
    grep -Fqx $'config\t'"$expected_backup_root/config/backup.env" <<< "$direct_paths" &&
    grep -Fqx $'data\t'"$expected_backup_root/data" <<< "$direct_paths" &&
    grep -Fqx $'logs\t'"$HOME/Library/Logs/cycling-platform" <<< "$direct_paths" || {
      log "Direct runtime path resolution is not canonical."
      return 1
    }
  (
    cd "$RUNTIME_DIR"
    Rscript --vanilla -e '
      required <- c("DBI", "RMariaDB", "jsonlite", "purrr")
      missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
      if (length(missing)) stop("Missing backup R packages: ", paste(missing, collapse = ", "))
    '
  ) >/dev/null
  log "Verification passed; runtime hashes, config permissions, paths, and plists are valid."
}

install_runtime() {
  local parent staging previous label rendered_plist
  parent="$(dirname "$RUNTIME_DIR")"
  staging="$parent/.runtime-staging-$$"
  previous="$parent/runtime.previous"
  mkdir -p "$parent" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR" "$AGENT_DIR"
  chmod 0700 "$CONFIG_DIR"
  extract_backup_config
  validate_config
  migrate_backup_data
  render_runtime "$staging"
  (cd "$staging" && shasum -a 256 -c runtime-manifest.sha256 >/dev/null)
  ! grep -R -q '/Documents/' "$staging" || {
    log "Rendered runtime contains a forbidden Documents path."
    return 1
  }
  ! grep -R -F -q "$PROJECT_DIR" "$staging" || {
    log "Rendered runtime contains a source-checkout path."
    return 1
  }
  for label in "${LABELS[@]}"; do
    rendered_plist="$staging/$label.plist.check"
    render_plist "$label" > "$rendered_plist"
    plutil -lint "$rendered_plist" >/dev/null
    rm -f "$rendered_plist"
  done
  (
    cd "$staging"
    Rscript --vanilla -e '
      required <- c("DBI", "RMariaDB", "jsonlite", "purrr")
      stopifnot(all(vapply(required, requireNamespace, logical(1), quietly = TRUE)))
    '
  )
  [[ "${BACKUP_INSTALL_FAIL_AFTER_RENDER:-0}" != "1" ]] || {
    log "Injected install failure after render; active runtime was not changed."
    return 1
  }
  if [[ -d "$RUNTIME_DIR" ]]; then
    rm -rf "$previous"
    mv "$RUNTIME_DIR" "$previous"
  fi
  if ! mv "$staging" "$RUNTIME_DIR"; then
    [[ ! -d "$previous" ]] || mv "$previous" "$RUNTIME_DIR"
    return 1
  fi
  if ! install_plists; then
    rm -rf "$RUNTIME_DIR"
    [[ ! -d "$previous" ]] || mv "$previous" "$RUNTIME_DIR"
    log "LaunchAgent loading failed; the preceding runtime was restored."
    return 1
  fi
  remove_legacy_backup_cron
  verify_runtime
  log "Installed self-contained backup runtime. Previous runtime retained at $previous when present."
}

show_status() {
  local commit installed latest="missing" label state health
  if [[ -f "$RUNTIME_DIR/runtime-manifest.json" ]]; then
    commit="$(sed -n 's/.*"source_commit": "\([^"]*\)".*/\1/p' "$RUNTIME_DIR/runtime-manifest.json")"
    installed="$(sed -n 's/.*"installed_at": "\([^"]*\)".*/\1/p' "$RUNTIME_DIR/runtime-manifest.json")"
  else
    commit="not-installed"
    installed="not-installed"
  fi
  if [[ -f "$DATA_DIR/latest_success.json" ]]; then
    latest="$(sed -n 's/.*"completed_at": "\([^"]*\)".*/\1/p' "$DATA_DIR/latest_success.json" | head -1)"
  fi
  printf 'Runtime: %s\nSource commit: %s\nInstalled at: %s\nLatest successful backup: %s\n' \
    "$RUNTIME_DIR" "$commit" "$installed" "${latest:-unknown}"
  for label in "${LABELS[@]}"; do
    if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then state="loaded"; else state="not loaded"; fi
    printf '%s: %s\n' "$label" "$state"
  done
  if [[ -d "$RUNTIME_DIR" && -f "$CONFIG_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    set +a
    health="$(
      cd "$RUNTIME_DIR" &&
        Rscript --vanilla scripts/report_backup_runtime_health.R \
          "$DATA_DIR/latest_success.json" \
          "${BACKUP_FRESHNESS_STALE_HOURS:-30}" \
          "${BACKUP_FRESHNESS_CRITICAL_HOURS:-48}"
    )" || health=$'UNAVAILABLE\tNA\tnone\tUNAVAILABLE\tUNAVAILABLE'
    IFS=$'\t' read -r physical age prefix admin retention <<< "$health"
    printf 'Physical health: %s (age hours: %s, prefix: %s)\n' "$physical" "$age" "$prefix"
    printf 'Admin freshness: %s\nRetention: %s\n' "$admin" "$retention"
  fi
  if verify_runtime >/dev/null 2>&1; then printf 'Drift: none\n'; else printf 'Drift: detected or installation incomplete\n'; fi
}

case "$MODE" in
  render)
    if [[ -z "$RENDER_TARGET" ]]; then
      RENDER_TARGET="$(mktemp -d -t cycling-platform-backup-render.XXXXXX)"
    fi
    render_runtime "$RENDER_TARGET"
    for label in "${LABELS[@]}"; do render_plist "$label" > "$RENDER_TARGET/$label.plist"; done
    log "Rendered runtime and plists at $RENDER_TARGET"
    ;;
  install)
    require_macos_command plutil
    require_macos_command launchctl
    require_macos_command rsync
    install_runtime
    ;;
  verify)
    verify_runtime
    ;;
  status)
    show_status
    ;;
  health)
    verify_runtime
    BACKUP_CONFIG_FILE="$CONFIG_FILE" BACKUP_DIR="$DATA_DIR" \
      "$RUNTIME_DIR/scripts/run_backup_workflow.sh" check
    set -a
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    set +a
    (
      cd "$RUNTIME_DIR"
      Rscript --vanilla scripts/report_backup_runtime_health.R \
        "$DATA_DIR/latest_success.json" \
        "${BACKUP_FRESHNESS_STALE_HOURS:-30}" \
        "${BACKUP_FRESHNESS_CRITICAL_HOURS:-48}"
    )
    ;;
  uninstall)
    for label in "${LABELS[@]}"; do
      launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
      rm -f "$AGENT_DIR/$label.plist"
    done
    rm -rf "$RUNTIME_DIR"
    log "LaunchAgents and runtime code removed. Config, backup data, logs, and previous runtime were preserved."
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
