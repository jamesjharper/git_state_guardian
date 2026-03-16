#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "This uninstaller must be run with sudo or as root."
  echo "Example:"
  echo "  sudo bash $0"
  exit 1
fi

RUN_AS_USER="${2:-${SUDO_USER:-$(whoami)}}"
BASE_DIR="${1:-/home/${RUN_AS_USER}/.openclaw}"
REMOVE_WORKSPACE_DATA="${REMOVE_WORKSPACE_DATA:-0}"

if [[ -z "$BASE_DIR" || ! -d "$BASE_DIR" ]]; then
  echo "Usage: sudo bash $0 /path/to/parent-containing-workspaces [username]"
  echo
  echo "Optional:"
  echo "  REMOVE_WORKSPACE_DATA=1   Also delete .auto_git_repo inside each workspace*"
  exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
  echo "systemctl not found; this script expects a systemd-based Linux system."
  exit 1
fi

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

workspace_name_matches() {
  local name="$1"
  [[ "$name" == workspace* ]]
}

discover_existing_workspaces() {
  local base_dir="$1"
  find "$base_dir" -mindepth 1 -maxdepth 1 -type d | while read -r dir; do
    local name
    name="$(basename "$dir")"
    if workspace_name_matches "$name"; then
      echo "$dir"
    fi
  done
}

stop_disable_workspace_service() {
  local ws="$1"
  local escaped
  escaped="$(systemd-escape --path "$ws")"
  local unit="workspace-watch@${escaped}.service"

  systemctl stop "$unit" >/dev/null 2>&1 || true
  systemctl disable "$unit" >/dev/null 2>&1 || true
}

log "Uninstalling workspace backup system"
log "Base dir: $BASE_DIR"
log "Remove workspace data: $REMOVE_WORKSPACE_DATA"
echo

systemctl stop workspace-discovery.service >/dev/null 2>&1 || true
systemctl disable workspace-discovery.service >/dev/null 2>&1 || true

discover_existing_workspaces "$BASE_DIR" | while read -r ws; do
  stop_disable_workspace_service "$ws"
done

systemctl list-units --full --all 'workspace-watch@*' --no-legend 2>/dev/null | awk '{print $1}' | while read -r unit; do
  [[ -n "$unit" ]] || continue
  systemctl stop "$unit" >/dev/null 2>&1 || true
done

systemctl list-unit-files 'workspace-watch@*' --no-legend 2>/dev/null | awk '{print $1}' | while read -r unit; do
  [[ -n "$unit" ]] || continue
  systemctl disable "$unit" >/dev/null 2>&1 || true
done

FILES_TO_REMOVE=(
  /usr/local/bin/workspace_init_one.sh
  /usr/local/bin/workspace_backup_one.sh
  /usr/local/bin/workspace_watch_debounced_one.sh
  /usr/local/bin/workspace_discovery_daemon.sh
  /usr/local/lib/workspace-backup/common.sh
  /etc/systemd/system/workspace-watch@.service
  /etc/systemd/system/workspace-discovery.service
  /etc/default/workspace-backup.conf
)

for f in "${FILES_TO_REMOVE[@]}"; do
  if [[ -e "$f" ]]; then
    rm -f "$f"
  fi
done

if [[ -d /usr/local/lib/workspace-backup ]]; then
  rmdir /usr/local/lib/workspace-backup 2>/dev/null || true
fi

if [[ "$REMOVE_WORKSPACE_DATA" == "1" ]]; then
  discover_existing_workspaces "$BASE_DIR" | while read -r ws; do
    rm -rf "$ws/.auto_git_repo"
  done
fi

systemctl daemon-reload
systemctl reset-failed >/dev/null 2>&1 || true

echo
echo "Uninstall complete."
