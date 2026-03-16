# Workspace Backup Installer

A small systemd-based auto-backup system for OpenClaw `workspace*` directories.

It watches each matching workspace, creates debounced Git snapshots in a hidden repo stored at `.auto_git_repo`, and automatically starts watching newly created workspaces.

## Repository layout

```text
.
├── install.sh
├── uninstall.sh
├── README.md
└── Skills/
    └── git_state_guardian/
        ├── SKILL.md
        ├── LICENSE
        ├── references/
        │   └── usage-patterns.md
        └── scripts/
            ├── README.md
            └── git_state_guardian.sh
```

## What the installer does

For each directory matching `workspace*` under the selected OpenClaw base directory, the installer:

- creates and maintains a hidden Git repo at `.auto_git_repo`
- starts a per-workspace watcher service
- debounces file events so frequent writes do not create excessive commits
- auto-discovers new `workspace*` directories and starts watchers for them
- compacts history when the configured commit limit is exceeded

## What it does not do

This version does **not** create rsync snapshots or `.backup_snapshots` directories.
It only keeps Git history in `.auto_git_repo`.

## Requirements

- Linux with `systemd`
- `git`
- `inotifywait` from `inotify-tools`
- `flock` and `runuser` from `util-linux`

On Debian/Ubuntu systems, missing packages are installed automatically.

## Install

Run as root or with `sudo`.

Default target:

- user: detected from `SUDO_USER`
- base dir: `/home/<user>/.openclaw`

```bash
sudo bash install.sh
```

Custom base directory and user:

```bash
sudo bash install.sh /path/to/.openclaw username
```

Override settings during install:

```bash
sudo DEBOUNCE_SECONDS=10 GIT_MAX_COMMITS=500 \
  bash install.sh /path/to/.openclaw username
```

## Configuration

The installer writes active settings to:

```bash
/etc/default/workspace-backup.conf
```

Supported settings:

- `BASE_DIR`
- `RUN_AS_USER`
- `RUN_AS_GROUP`
- `DEBOUNCE_SECONDS` (default `20`)
- `GIT_MAX_COMMITS` (default `200`)

To change settings later, rerun `install.sh` with new values.

## Installed components

The installer creates:

- `/usr/local/lib/workspace-backup/common.sh`
- `/usr/local/bin/workspace_init_one.sh`
- `/usr/local/bin/workspace_backup_one.sh`
- `/usr/local/bin/workspace_watch_debounced_one.sh`
- `/usr/local/bin/workspace_discovery_daemon.sh`
- `/etc/systemd/system/workspace-watch@.service`
- `/etc/systemd/system/workspace-discovery.service`

## Useful commands

Check discovery service:

```bash
systemctl status workspace-discovery.service
```

Follow discovery logs:

```bash
journalctl -u workspace-discovery.service -f
```

List watcher services:

```bash
systemctl list-units 'workspace-watch@*'
```

## Inspecting and restoring workspace state

View history:

```bash
git --git-dir=/path/to/workspace/.auto_git_repo \
    --work-tree=/path/to/workspace \
    log --oneline --decorate
```

Restore a file or directory from an older commit:

```bash
git --git-dir=/path/to/workspace/.auto_git_repo \
    --work-tree=/path/to/workspace \
    checkout HEAD~1 -- AGENTS.md
```

Or use the included skill helper:

```bash
Skills/git_state_guardian/scripts/git_state_guardian.sh inspect /path/to/workspace
Skills/git_state_guardian/scripts/git_state_guardian.sh history /path/to/workspace 20
Skills/git_state_guardian/scripts/git_state_guardian.sh restore /path/to/workspace HEAD~1 -- skills/
```

## Uninstall

Remove services and installed scripts:

```bash
sudo bash uninstall.sh
```

By default, uninstall keeps `.auto_git_repo` inside each workspace.

To remove those repos too:

```bash
sudo REMOVE_WORKSPACE_DATA=1 bash uninstall.sh /path/to/.openclaw username
```

## Notes

- Only directories named `workspace*` are managed.
- Backup metadata is stored inside each workspace and excluded from auto-commit staging.
- The installer is designed to be rerun safely to update configuration values.
