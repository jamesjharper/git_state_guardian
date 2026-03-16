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

DEBOUNCE_SECONDS="${DEBOUNCE_SECONDS:-20}"
GIT_MAX_COMMITS="${GIT_MAX_COMMITS:-200}"

CONFIG_FILE="/etc/default/workspace-backup.conf"
LIB_DIR="/usr/local/lib/workspace-backup"
BIN_DIR="/usr/local/bin"

# Tunables are read from environment at install time and written to CONFIG_FILE.

if [[ -z "$RUN_AS_USER" ]]; then
  echo "Could not determine target user."
  exit 1
fi

if ! id "$RUN_AS_USER" >/dev/null 2>&1; then
  echo "User does not exist: $RUN_AS_USER"
  exit 1
fi

RUN_AS_GROUP="$(id -gn "$RUN_AS_USER")"

if [[ -z "$BASE_DIR" || ! -d "$BASE_DIR" ]]; then
  echo "Base directory does not exist: $BASE_DIR"
  echo "Usage:"
  echo "  sudo bash $0 /path/to/base_dir username"
  exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
  echo "systemctl not found; this installer expects a systemd-based Linux system."
  exit 1
fi

echo "Installing workspace git backup system"
echo "Base dir:          $BASE_DIR"
echo "Run as user:       $RUN_AS_USER"
echo "Run as group:      $RUN_AS_GROUP"
echo "Debounce seconds:  $DEBOUNCE_SECONDS"
echo "Git max commits:   $GIT_MAX_COMMITS"
echo

MISSING_PKGS=()
command -v inotifywait >/dev/null 2>&1 || MISSING_PKGS+=("inotify-tools")
command -v git >/dev/null 2>&1 || MISSING_PKGS+=("git")
command -v flock >/dev/null 2>&1 || MISSING_PKGS+=("util-linux")
command -v runuser >/dev/null 2>&1 || MISSING_PKGS+=("util-linux")
command -v systemd-escape >/dev/null 2>&1 || MISSING_PKGS+=("systemd")

if [[ "${#MISSING_PKGS[@]}" -gt 0 ]]; then
  echo "Installing missing packages: ${MISSING_PKGS[*]}"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y "${MISSING_PKGS[@]}"
  else
    echo "Please install these packages manually: ${MISSING_PKGS[*]}"
    exit 1
  fi
fi

# Install directories
mkdir -p "$LIB_DIR" "$BIN_DIR"

cat >"$CONFIG_FILE" <<EOF
BASE_DIR="$BASE_DIR"
RUN_AS_USER="$RUN_AS_USER"
RUN_AS_GROUP="$RUN_AS_GROUP"
DEBOUNCE_SECONDS="$DEBOUNCE_SECONDS"
GIT_MAX_COMMITS="$GIT_MAX_COMMITS"
EOF

chmod 0644 "$CONFIG_FILE"

# Shared runtime library
cat >"$LIB_DIR/common.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/default/workspace-backup.conf"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1091
  source "$CONFIG_FILE"
else
  echo "Missing config file: $CONFIG_FILE" >&2
  exit 1
fi

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

workspace_name_matches() {
  local name="$1"
  [[ "$name" == workspace* ]]
}

list_workspaces() {
  find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d | sort | while read -r dir; do
    local name
    name="$(basename "$dir")"
    if workspace_name_matches "$name"; then
      echo "$dir"
    fi
  done
}

ensure_workspace_dirs() {
  local ws="$1"
  mkdir -p "$ws/.auto_git_repo"
}

write_excludes() {
  local ws="$1"
  local git_dir="$ws/.auto_git_repo"

  mkdir -p "$git_dir/info"
  cat >"$git_dir/info/exclude" <<'EXCL'
.auto_git_repo/
.git/
skills/
memory/
EXCL
}

git_add_workspace_content() {
  local ws="$1"
  local git_dir="$ws/.auto_git_repo"

  # Rely on info/exclude. Do not pass ignored paths explicitly, otherwise git add
  # can return non-zero under set -e even when the staging itself succeeds.
  git --git-dir="$git_dir" --work-tree="$ws" add -A -- .
}

ensure_workspace_repo() {
  local ws="$1"
  local git_dir="$ws/.auto_git_repo"

  ensure_workspace_dirs "$ws"

  if [[ ! -f "$git_dir/HEAD" || ! -d "$git_dir/objects" ]]; then
    rm -rf "$git_dir"
    git init --bare --quiet "$git_dir"
  fi

  git --git-dir="$git_dir" rev-parse --git-dir >/dev/null 2>&1

  git --git-dir="$git_dir" config user.name "Workspace Auto Backup"
  git --git-dir="$git_dir" config user.email "workspace-backup@localhost"
  git --git-dir="$git_dir" config advice.addIgnoredFile false

  write_excludes "$ws"

  if ! git --git-dir="$git_dir" rev-parse --verify HEAD >/dev/null 2>&1; then
    git_add_workspace_content "$ws"
    if ! git --git-dir="$git_dir" --work-tree="$ws" diff --cached --quiet; then
      git --git-dir="$git_dir" --work-tree="$ws" commit --quiet -m "Initial snapshot"
    fi
  fi
}

compact_git_history_if_needed() {
  local ws="$1"
  local git_dir="$ws/.auto_git_repo"

  local commit_count
  commit_count="$(git --git-dir="$git_dir" rev-list --count HEAD 2>/dev/null || echo 0)"

  if [[ "$commit_count" -le "$GIT_MAX_COMMITS" ]]; then
    return 0
  fi

  log "Compacting git history for $ws (commit count: $commit_count)"

  local current_branch
  current_branch="$(git --git-dir="$git_dir" symbolic-ref --short HEAD 2>/dev/null || echo master)"

  local temp_branch="history-compaction-tmp"
  local ts
  ts="$(date +"%Y-%m-%d_%H-%M-%S")"

  git --git-dir="$git_dir" --work-tree="$ws" checkout --orphan "$temp_branch" >/dev/null 2>&1 || true
  git_add_workspace_content "$ws"
  if ! git --git-dir="$git_dir" --work-tree="$ws" diff --cached --quiet; then
    git --git-dir="$git_dir" --work-tree="$ws" commit --quiet -m "History compacted at $ts"
  fi

  if git --git-dir="$git_dir" show-ref --verify --quiet "refs/heads/$current_branch"; then
    git --git-dir="$git_dir" branch -D "$current_branch" >/dev/null 2>&1 || true
  fi

  git --git-dir="$git_dir" branch -m "$current_branch" >/dev/null 2>&1 || true
  git --git-dir="$git_dir" reflog expire --expire=now --all || true
  git --git-dir="$git_dir" gc --prune=now >/dev/null 2>&1 || true

  log "Git history compacted for $ws"
}

backup_workspace() {
  local ws="$1"
  local git_dir="$ws/.auto_git_repo"

  ensure_workspace_repo "$ws"

  local timestamp
  timestamp="$(date +"%Y-%m-%d_%H-%M-%S")"

  git_add_workspace_content "$ws"

  if ! git --git-dir="$git_dir" diff --cached --quiet; then
    git --git-dir="$git_dir" --work-tree="$ws" commit --quiet -m "Auto snapshot $timestamp"
  fi

  compact_git_history_if_needed "$ws"
}

ensure_workspace_owned_by_target_user() {
  local ws="$1"
  mkdir -p "$ws/.auto_git_repo"
  chown -R "$RUN_AS_USER:$RUN_AS_GROUP" "$ws/.auto_git_repo"
}

start_workspace_service_if_needed() {
  local ws="$1"
  local escaped
  escaped="$(systemd-escape --path "$ws")"

  systemctl enable "workspace-watch@${escaped}.service" >/dev/null 2>&1 || true
  systemctl restart "workspace-watch@${escaped}.service" >/dev/null 2>&1 || true
}
EOF

chmod 0755 "$LIB_DIR/common.sh"

# Per-workspace helper commands
cat >"$BIN_DIR/workspace_init_one.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /usr/local/lib/workspace-backup/common.sh

WORKSPACE="${1:-}"

if [[ -z "$WORKSPACE" || ! -d "$WORKSPACE" ]]; then
  echo "Usage: $0 /path/to/workspace"
  exit 1
fi

ensure_workspace_dirs "$WORKSPACE"
ensure_workspace_repo "$WORKSPACE"
EOF

chmod 0755 "$BIN_DIR/workspace_init_one.sh"

cat >"$BIN_DIR/workspace_backup_one.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /usr/local/lib/workspace-backup/common.sh

WORKSPACE="${1:-}"

if [[ -z "$WORKSPACE" || ! -d "$WORKSPACE" ]]; then
  echo "Usage: $0 /path/to/workspace"
  exit 1
fi

backup_workspace "$WORKSPACE"
EOF

chmod 0755 "$BIN_DIR/workspace_backup_one.sh"

cat >"$BIN_DIR/workspace_watch_debounced_one.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /usr/local/lib/workspace-backup/common.sh

WORKSPACE="${1:-}"

if [[ -z "$WORKSPACE" || ! -d "$WORKSPACE" ]]; then
  echo "Usage: $0 /path/to/workspace"
  exit 1
fi

command -v inotifywait >/dev/null 2>&1 || {
  echo "inotifywait not found"
  exit 1
}

ensure_workspace_repo "$WORKSPACE"

INOTIFY_EXCLUDES='(^|/)(\.auto_git_repo|\.git|node_modules|__pycache__|\.pytest_cache)(/|$)'

HASH="$(echo -n "$WORKSPACE" | sha256sum | awk '{print $1}')"
PIPE="/tmp/workspace-watch-${HASH}.pipe"
LOCK="/tmp/workspace-backup-${HASH}.lock"

rm -f "$PIPE" 2>/dev/null || true
mkfifo "$PIPE"

cleanup() {
  rm -f "$PIPE" 2>/dev/null || true
  if [[ -n "${INOTIFY_PID:-}" ]]; then
    kill "$INOTIFY_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

LAST_EVENT_EPOCH=0
PENDING=0

inotifywait -m -r \
  --exclude "$INOTIFY_EXCLUDES" \
  -e close_write -e moved_to -e delete -e move -e create \
  --format '%T %w%f %e' \
  --timefmt '%s' \
  "$WORKSPACE" >"$PIPE" 2>/dev/null &

INOTIFY_PID=$!

log "Watching $WORKSPACE with debounce ${DEBOUNCE_SECONDS}s"

while true; do
  if read -r -t 1 line <"$PIPE"; then
    LAST_EVENT_EPOCH="${line%% *}"
    PENDING=1
  fi

  if [[ "$PENDING" -eq 1 ]]; then
    NOW="$(date +%s)"
    QUIET_FOR=$(( NOW - LAST_EVENT_EPOCH ))

    if [[ "$QUIET_FOR" -ge "$DEBOUNCE_SECONDS" ]]; then
      if flock -n "$LOCK" /usr/local/bin/workspace_backup_one.sh "$WORKSPACE"; then
        log "Backup complete for $WORKSPACE"
      else
        log "Backup already running for $WORKSPACE; skipping overlap"
      fi
      PENDING=0
    fi
  fi
done
EOF

chmod 0755 "$BIN_DIR/workspace_watch_debounced_one.sh"

cat >"$BIN_DIR/workspace_discovery_daemon.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /usr/local/lib/workspace-backup/common.sh

command -v inotifywait >/dev/null 2>&1 || {
  echo "inotifywait not found"
  exit 1
}

process_workspace() {
  local ws="$1"
  [[ -d "$ws" ]] || return 0

  local name
  name="$(basename "$ws")"

  if ! workspace_name_matches "$name"; then
    return 0
  fi

  log "Discovered workspace: $ws"

  ensure_workspace_owned_by_target_user "$ws"
  runuser -u "$RUN_AS_USER" -- /usr/local/bin/workspace_init_one.sh "$ws"
  start_workspace_service_if_needed "$ws"
}

log "Initial scan for existing workspaces in $BASE_DIR"
list_workspaces | while read -r ws; do
  process_workspace "$ws"
done

log "Watching $BASE_DIR for new workspace* directories"

inotifywait -m "$BASE_DIR" -e create -e moved_to --format '%w%f' | while read -r path; do
  if [[ -d "$path" ]]; then
    process_workspace "$path"
  fi
done
EOF

chmod 0755 "$BIN_DIR/workspace_discovery_daemon.sh"

# systemd units
cat >/etc/systemd/system/workspace-watch@.service <<EOF
[Unit]
Description=Debounced workspace git backup watcher for %I
After=network.target

[Service]
Type=simple
User=$RUN_AS_USER
Group=$RUN_AS_GROUP
ExecStart=/usr/local/bin/workspace_watch_debounced_one.sh %I
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/workspace-discovery.service <<'EOF'
[Unit]
Description=Auto-discover workspace* directories and start git backup watchers
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/workspace_discovery_daemon.sh
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d -name 'workspace*' | while read -r ws; do
  mkdir -p "$ws/.auto_git_repo"
  chown -R "$RUN_AS_USER:$RUN_AS_GROUP" "$ws/.auto_git_repo"
done

systemctl daemon-reload
systemctl enable workspace-discovery.service >/dev/null 2>&1 || true
systemctl restart workspace-discovery.service

systemctl list-unit-files 'workspace-watch@*' --no-legend 2>/dev/null | awk '{print $1}' | while read -r unit; do
  [[ -n "$unit" ]] || continue
  systemctl restart "$unit" >/dev/null 2>&1 || true
done

echo
echo "Install complete."
echo
echo "Configuration written to:"
echo "  $CONFIG_FILE"
echo
echo "Useful commands:"
echo "  systemctl status workspace-discovery.service"
echo "  journalctl -u workspace-discovery.service -f"
echo "  systemctl list-units 'workspace-watch@*'"
echo
echo "Current settings:"
echo "  BASE_DIR=$BASE_DIR"
echo "  RUN_AS_USER=$RUN_AS_USER"
echo "  DEBOUNCE_SECONDS=$DEBOUNCE_SECONDS"
echo "  GIT_MAX_COMMITS=$GIT_MAX_COMMITS"
echo
echo "To change settings later, rerun:"
echo "  sudo DEBOUNCE_SECONDS=10 GIT_MAX_COMMITS=500 bash $0 $BASE_DIR $RUN_AS_USER"
echo
echo "Restore examples:"
echo "  git --git-dir=/path/to/workspace/.auto_git_repo --work-tree=/path/to/workspace log"
echo "  git --git-dir=/path/to/workspace/.auto_git_repo --work-tree=/path/to/workspace checkout HEAD~1 -- AGENTS.md"
