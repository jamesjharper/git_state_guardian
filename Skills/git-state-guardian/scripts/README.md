# git_state_guardian.sh

Git helper for OpenClaw workspaces that keep local history in `.auto_git_repo`.
It is designed for agent workflows where you need deliberate save points, readable
change summaries, and safe recovery during iterative edits.

## Recommended workflow

1. Inspect the current workspace state.
2. Create a checkpoint before risky multi-file edits.
3. Make changes.
4. Compare or summarize what changed.
5. Either tag the result as known-good or restore targeted files or the whole tracked workspace.

## Command overview

### Save points

```bash
./scripts/git_state_guardian.sh checkpoint /workspace "before auth refactor"
./scripts/git_state_guardian.sh tag /workspace known-good/auth-cleanup
./scripts/git_state_guardian.sh checkpoint-list /workspace 20
```

### Inspect and summarize

```bash
./scripts/git_state_guardian.sh inspect /workspace
./scripts/git_state_guardian.sh summary /workspace
./scripts/git_state_guardian.sh compare /workspace HEAD~3 HEAD
./scripts/git_state_guardian.sh changed-files /workspace HEAD~3 HEAD
./scripts/git_state_guardian.sh compare-patch /workspace HEAD~1 HEAD
./scripts/git_state_guardian.sh show /workspace HEAD~1
```

### Restore

```bash
./scripts/git_state_guardian.sh restore /workspace HEAD~1 -- skills/ install.sh
./scripts/git_state_guardian.sh restore-all /workspace checkpoint/manual/before-auth-refactor-20260316-120000
```

## Important behavior

- `checkpoint` stages all tracked workspace content and creates a commit when there are changes.
- If there are no staged changes, `checkpoint` creates a timestamped tag under `checkpoint/manual/...`.
- `restore` is a surgical recovery command for specific files or directories.
- `restore-all` creates a new commit that makes tracked files match the chosen ref. It does not move `HEAD` backwards.
- Ignored or untracked files that are not part of Git tracking are left alone by `restore-all`.

## Assumptions

- The workspace has a hidden bare Git repo at `/workspace/.auto_git_repo`.
- Commands are run from the skill directory or with an explicit path to the script.
