#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$PROJECT_DIR/config/launchd"
AGENT_DIR="${BACKUP_LAUNCHD_AGENT_DIR:-$HOME/Library/LaunchAgents}"
LOG_DIR="${BACKUP_LAUNCHD_LOG_DIR:-$PROJECT_DIR/logs}"
MODE="${1:-install}"
LABELS=(
  com.tim-jc.cycling-platform-backup
  com.tim-jc.cycling-platform-backup-health
)

usage() {
  printf 'Usage: %s [install|uninstall|status|render]\n' "$0"
}

render() {
  local label="$1"
  sed \
    -e "s|__PROJECT_DIR__|$PROJECT_DIR|g" \
    -e "s|__LOG_DIR__|$LOG_DIR|g" \
    "$SOURCE_DIR/$label.plist"
}

remove_legacy_backup_cron() {
  command -v crontab >/dev/null 2>&1 || return 0
  local current filtered
  current="$(mktemp)"
  filtered="$(mktemp)"
  crontab -l > "$current" 2>/dev/null || : > "$current"
  grep -Ev 'cycling-platform/(scripts/)?(backup_mariadb|run_backup_workflow)[.]sh' \
    "$current" > "$filtered" || true
  if ! cmp -s "$current" "$filtered"; then
    crontab "$filtered"
    printf '[backup-launchd] Removed superseded cycling-platform backup cron entry.\n'
  fi
  rm -f "$current" "$filtered"
}

case "$MODE" in
  render)
    for label in "${LABELS[@]}"; do render "$label"; done
    ;;
  install)
    mkdir -p "$AGENT_DIR" "$LOG_DIR"
    chmod +x "$PROJECT_DIR/scripts/run_backup_workflow.sh"
    for label in "${LABELS[@]}"; do
      target="$AGENT_DIR/$label.plist"
      temporary="$target.tmp"
      render "$label" > "$temporary"
      plutil -lint "$temporary" >/dev/null
      mv "$temporary" "$target"
      launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
      launchctl bootstrap "gui/$(id -u)" "$target"
    done
    remove_legacy_backup_cron
    printf '[backup-launchd] Installed backup and hourly freshness agents.\n'
    ;;
  uninstall)
    for label in "${LABELS[@]}"; do
      launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
      rm -f "$AGENT_DIR/$label.plist"
    done
    printf '[backup-launchd] Agents disabled and removed; cron was not restored.\n'
    ;;
  status)
    for label in "${LABELS[@]}"; do
      launchctl print "gui/$(id -u)/$label"
    done
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
