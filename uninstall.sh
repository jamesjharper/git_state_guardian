#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "This installer must be run with sudo or as root."
  echo "Example:"
  echo "  sudo bash $0"
  exit 1
fi

RUN_AS_USER="${2:-${SUDO_USER:-$(whoami)}}"
BASE_DIR="${1:-/home/${RUN_AS_USER}/.openclaw}"

REMOVE_WORKSPACE_DATA="${REMOVE_WORKSPACE_DATA:-0}"

if [[ -z "$BASE_DIR" || ! -d "$BASE_DIR" ]]; then
  echo "Usage: sudo bash $0 /path/to/parent-containing-workspaces"
  echo
  echo "Optional:"
  echo "  REMOVE_WORKSPACE_DATA=1   Also delete .auto_git_repo and .backup_snapshots inside each workspace*"
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

  if systemctl list-unit-files | grep -q "^${unit}"; then
    log "Stopping $unit"
    systemctl stop "$unit" >/dev/null 2>&1 || true
    log "Disabling $unit"
    systemctl disable "$unit" >/dev/null 2>&1 || true
  else
    # still try in case it exists only in runtime
    systemctl stop "$unit" >/dev/null 2>&1 || true
    systemctl disable "$unit" >/dev/null 2>&1 || true
  fi
}

log "Uninstalling workspace backup system"
log "Base dir: $BASE_DIR"
log "Remove workspace data: $REMOVE_WORKSPACE_DATA"
echo

###############################################################################
# Stop discovery service first
###############################################################################
log "Stopping workspace-discovery.service"
systemctl stop workspace-discovery.service >/dev/null 2>&1 || true

log "Disabling workspace-discovery.service"
systemctl disable workspace-discovery.service >/dev/null 2>&1 || true

###############################################################################
# Stop/disable watcher services for known workspaces
###############################################################################
discover_existing_workspaces "$BASE_DIR" | while read -r ws; do
  stop_disable_workspace_service "$ws"
done

###############################################################################
# Also stop any remaining watcher services, even for workspaces no longer present
###############################################################################
systemctl list-units --full --all 'workspace-watch@*' --no-legend 2>/dev/null | awk '{print $1}' | while read -r unit; do
  [[ -n "$unit" ]] || continue
  log "Stopping leftover unit $unit"
  systemctl stop "$unit" >/dev/null 2>&1 || true
done

systemctl list-unit-files 'workspace-watch@*' --no-legend 2>/dev/null | awk '{print $1}' | while read -r unit; do
  [[ -n "$unit" ]] || continue
  log "Disabling leftover unit $unit"
  systemctl disable "$unit" >/dev/null 2>&1 || true
done

###############################################################################
# Remove installed files
###############################################################################
FILES_TO_REMOVE=(
  /usr/local/bin/workspace_init_one.sh
  /usr/local/bin/workspace_backup_one.sh
  /usr/local/bin/workspace_watch_debounced_one.sh
  /usr/local/bin/workspace_discovery_daemon.sh
  /usr/local/lib/workspace-backup/common.sh
  /etc/systemd/system/workspace-watch@.service
  /etc/systemd/system/workspace-discovery.service
)

for f in "${FILES_TO_REMOVE[@]}"; do
  if [[ -e "$f" ]]; then
    log "Removing $f"
    rm -f "$f"
  fi
done

if [[ -d /usr/local/lib/workspace-backup ]]; then
  rmdir /usr/local/lib/workspace-backup 2>/dev/null || true
fi

###############################################################################
# Remove per-workspace backup data if requested
###############################################################################
if [[ "$REMOVE_WORKSPACE_DATA" == "1" ]]; then
  log "Removing per-workspace backup data"

  discover_existing_workspaces "$BASE_DIR" | while read -r ws; do
    if [[ -d "$ws/.auto_git_repo" ]]; then
      log "Removing $ws/.auto_git_repo"
      rm -rf "$ws/.auto_git_repo"
    fi

    if [[ -d "$ws/.backup_snapshots" ]]; then
      log "Removing $ws/.backup_snapshots"
      rm -rf "$ws/.backup_snapshots"
    fi
  done
else
  log "Keeping per-workspace backup data"
fi

###############################################################################
# Reload systemd
###############################################################################
log "Reloading systemd"
systemctl daemon-reload

log "Resetting failed systemd state"
systemctl reset-failed >/dev/null 2>&1 || true

echo
echo "Uninstall complete."
echo
if [[ "$REMOVE_WORKSPACE_DATA" != "1" ]]; then
  echo "Per-workspace backup data was kept."
  echo "These directories may still exist inside each workspace*:"
  echo "  .auto_git_repo"
  echo "  .backup_snapshots"
  echo
  echo "To remove them too:"
  echo "  sudo REMOVE_WORKSPACE_DATA=1 bash $0 $BASE_DIR"
fi