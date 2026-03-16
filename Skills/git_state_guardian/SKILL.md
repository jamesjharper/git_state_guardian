---
name: git-state-guardian
description: Create checkpoints, inspect changes, compare states, and safely undo or restore edits in a Git-backed workspace. Use this before risky edits, when asked what changed, or when you need to revert part of a workspace.
compatibility:
  tools: Bash, Git
---

# Git State Guardian

Use this skill with OpenClaw workspaces that store their local history in `.auto_git_repo`.
The workspace itself is used as the Git worktree.

## Use when

- You are about to make broad or risky edits
- The user asks to undo, revert, restore, or roll back changes
- The user asks what changed
- You need to compare current work against an earlier checkpoint

## Safety guidance

- Create a checkpoint before large multi-file edits
- Prefer restoring specific files or directories before restoring the whole workspace
- Summarize destructive restores before you run them
- Inspect the diff after restore if the change is broad

## Commands

### Create a checkpoint

```bash
./scripts/git_state_guardian.sh checkpoint "$WORKSPACE" "before: <description>"
```

### Inspect current changes

```bash
./scripts/git_state_guardian.sh inspect "$WORKSPACE"
```

### Show history

```bash
./scripts/git_state_guardian.sh history "$WORKSPACE" 20
```

### Compare two refs

```bash
./scripts/git_state_guardian.sh compare "$WORKSPACE" <from> <to>
```

### Restore specific paths from a ref

```bash
./scripts/git_state_guardian.sh restore "$WORKSPACE" HEAD~1 -- skills/
```

### Create a tag

```bash
./scripts/git_state_guardian.sh tag "$WORKSPACE" known-good/<name>
```

## Notes

- The helper expects a Git repo at `$WORKSPACE/.auto_git_repo`
- Tags should be descriptive and safe to read later
- Checkpoints create a commit when there are staged changes; otherwise they create a timestamped tag on `HEAD`
