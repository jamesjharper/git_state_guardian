# Workspace Backup Installer

This provides a simple auto-backup system for `workspace*` directories inside an OpenClaw base directory.

It installs a small systemd-based watcher that:

- automatically discovers folders named `workspace*`
- watches them for file changes
- creates filesystem snapshots using `rsync`
- keeps a lightweight Git history in a separate hidden repo

This is useful for recovering from bad changes, reviewing what changed over time, and restoring older workspace states.

---

## What it does

For each directory matching `workspace*` under the chosen base directory, the installer creates:

- `.auto_git_repo` — a hidden Git repo used for automatic commits
- `.backup_snapshots` — timestamped file snapshots of the workspace contents

The watcher listens for file changes and waits for a quiet period before backing up, so it does not create a backup for every single file write.

It also automatically starts watching newly created `workspace*` folders.

---

## Install

Run as root or with `sudo`.

Default install target:

- user: detected from `SUDO_USER`
- base dir: `/home/<user>/.openclaw`

Example:

```bash
sudo bash install.sh
```

Custom base dir and user:

```bash
sudo bash install.sh /path/to/.openclaw username
```

You can also override the backup settings when installing:

```bash
sudo SNAPSHOT_KEEP=40 DEBOUNCE_SECONDS=10 GIT_MAX_COMMITS=500 \
  bash install.sh /path/to/.openclaw username
```

---

## Settings

These values can be overridden at install time with environment variables:

- `DEBOUNCE_SECONDS`  
  How long the watcher waits after file changes stop before creating a backup.  
  Default: `20`

- `SNAPSHOT_KEEP`  
  How many snapshot folders to keep in `.backup_snapshots`.  
  Default: `20`

- `GIT_MAX_COMMITS`  
  Maximum number of auto-commits to keep before compacting history.  
  Default: `200`

The active config is written to:

```bash
/etc/default/workspace-backup.conf
```

To change settings later, just rerun the installer with new values.

---

## Useful commands

Check the discovery service:

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

---

## Restoring data

### View Git history

```bash
git --git-dir=/path/to/workspace/.auto_git_repo --work-tree=/path/to/workspace log
```

### Restore a file or folder from an older Git commit

Example restoring `skills/` from the previous commit:

```bash
git --git-dir=/path/to/workspace/.auto_git_repo \
    --work-tree=/path/to/workspace \
    checkout HEAD~1 -- skills/
```

### Restore from a snapshot folder

```bash
cp -a /path/to/workspace/.backup_snapshots/<timestamp>/* /path/to/workspace/
```

---

## Uninstall

Remove the services and installed scripts:

```bash
sudo bash uninstall.sh
```

By default, uninstall keeps the per-workspace backup data:

- `.auto_git_repo`
- `.backup_snapshots`

To remove those as well:

```bash
sudo REMOVE_WORKSPACE_DATA=1 bash uninstall.sh /path/to/.openclaw username
```

---

## Notes

- This expects a **systemd-based Linux system**
- It installs missing dependencies automatically on `apt`-based systems
- Only directories named `workspace*` are managed
- Backup metadata is stored inside each workspace and excluded from the backup process itself
