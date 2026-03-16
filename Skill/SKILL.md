---
name: git-state-guardian
description: Create checkpoints, inspect changes, compare states, and safely undo or restore edits in a Git-backed workspace. Use this when asked to undo/revert/rollback/restore, to explain what changed, or before risky multi-file edits (skills, prompts, configs, codegen).
compatibility:
  tools: Bash, Git
---

# Git State Guardian

Works with a local repo at `.auto_git_repo` using the workspace as the worktree.

## Use when
- Undo / revert / rollback / restore
- “What changed?”
- Before large edits (create a checkpoint)

## Safety
- Create a checkpoint before risky edits
- Prefer restoring specific paths before whole workspace
- Summarize destructive restores

## Commands

### Checkpoint
```bash
scripts/git_state_guardian.sh checkpoint "$WORKSPACE" "before: <desc>"
```

### Inspect changes
```bash
scripts/git_state_guardian.sh inspect "$WORKSPACE"
```

### History
```bash
scripts/git_state_guardian.sh history "$WORKSPACE"
```

### Compare
```bash
scripts/git_state_guardian.sh compare "$WORKSPACE" <from> <to>
```

### Restore (file/dir)
```bash
scripts/git_state_guardian.sh restore "$WORKSPACE" HEAD~1 -- skills/
```

### Tag
```bash
scripts/git_state_guardian.sh tag "$WORKSPACE" known-good/<name>
```
