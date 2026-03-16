---
name: git-state-guardian
description: Create explicit checkpoints, tag stable states, inspect diffs, summarize workspace changes, and safely restore files or tracked workspace state in a Git-backed OpenClaw workspace.
compatibility:
  tools: Bash, Git
---

# Git State Guardian

Use this skill with OpenClaw workspaces that store local history in `.auto_git_repo`.
The workspace directory is the Git worktree and `.auto_git_repo` is the hidden bare repo.

This skill is for **agent-safe development**.
Treat it as a guardrail around risky edits, not just a generic Git helper.

## Use this skill when

- You are about to make broad or risky edits across multiple files.
- You want to mark the current state as stable or user-approved.
- The user asks what changed.
- You need to undo part of a change or roll back tracked workspace content.
- You want to compare the current state with an earlier checkpoint or tag.

## Agent workflow

### Before risky work

Inspect the workspace, then create a checkpoint.

```bash
./scripts/git_state_guardian.sh inspect "$WORKSPACE"
./scripts/git_state_guardian.sh checkpoint "$WORKSPACE" "before: <task description>"
```

Use this before refactors, code generation, installer changes, broad search/replace, or any edit that could damage multiple files.

### After completing a meaningful improvement

Compare the new state against the earlier point, summarize the change, then tag it if it is stable.

```bash
./scripts/git_state_guardian.sh compare "$WORKSPACE" <from> HEAD
./scripts/git_state_guardian.sh changed-files "$WORKSPACE" <from> HEAD
./scripts/git_state_guardian.sh tag "$WORKSPACE" known-good/<name>
```

### When the user asks “what changed?”

Start with summary-level output, then inspect the patch only if needed.

```bash
./scripts/git_state_guardian.sh summary "$WORKSPACE"
./scripts/git_state_guardian.sh compare "$WORKSPACE" <from> <to>
./scripts/git_state_guardian.sh changed-files "$WORKSPACE" <from> <to>
./scripts/git_state_guardian.sh compare-patch "$WORKSPACE" <from> <to>
```

### When you need to undo

Prefer the smallest safe restore first.

- First choice: restore specific files or directories.
- Second choice: restore the tracked workspace state with `restore-all`.

```bash
./scripts/git_state_guardian.sh restore "$WORKSPACE" <ref> -- path/to/file path/to/dir
./scripts/git_state_guardian.sh restore-all "$WORKSPACE" <ref> "undo failed refactor"
```

## Safety guidance

- Always checkpoint before broad or risky changes.
- Prefer `restore` before `restore-all`.
- Summarize broad rollback actions before running them.
- Use `compare`, `changed-files`, or `compare-patch` after a restore if the rollback was large.
- Use tags such as `known-good/<name>` for states you may want to revisit later.
- Do not rely on background auto snapshots alone for intentional rollback points. Create explicit checkpoints.

## Commands

### Save points

```bash
./scripts/git_state_guardian.sh checkpoint "$WORKSPACE" "before: <description>"
./scripts/git_state_guardian.sh tag "$WORKSPACE" known-good/<name>
./scripts/git_state_guardian.sh checkpoint-list "$WORKSPACE" 20
```

### Inspect and summarize

```bash
./scripts/git_state_guardian.sh inspect "$WORKSPACE"
./scripts/git_state_guardian.sh summary "$WORKSPACE"
./scripts/git_state_guardian.sh summary "$WORKSPACE" <ref>
./scripts/git_state_guardian.sh history "$WORKSPACE" 20
./scripts/git_state_guardian.sh compare "$WORKSPACE" <from> <to>
./scripts/git_state_guardian.sh changed-files "$WORKSPACE" <from> <to>
./scripts/git_state_guardian.sh compare-patch "$WORKSPACE" <from> <to>
./scripts/git_state_guardian.sh diff "$WORKSPACE"
./scripts/git_state_guardian.sh diff "$WORKSPACE" <ref>
./scripts/git_state_guardian.sh show "$WORKSPACE" <ref>
```

### Restore

```bash
./scripts/git_state_guardian.sh restore "$WORKSPACE" <ref> -- path/to/file path/to/dir
./scripts/git_state_guardian.sh restore-all "$WORKSPACE" <ref> "restore tracked state"
```

## Notes

- The helper expects a Git repo at `$WORKSPACE/.auto_git_repo`.
- `checkpoint` creates a commit when there are changes; otherwise it creates a timestamped tag under `checkpoint/manual/...`.
- `restore-all` preserves history by creating a new commit instead of moving `HEAD` backwards.
- `restore-all` is intended to align tracked files with a previous ref; ignored and unrelated untracked files are left alone.
