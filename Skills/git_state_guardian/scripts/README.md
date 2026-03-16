# git_state_guardian.sh

Helper for inspecting and restoring local workspace Git history.

## Examples

```bash
./scripts/git_state_guardian.sh checkpoint /workspace "before refactor"
./scripts/git_state_guardian.sh inspect /workspace
./scripts/git_state_guardian.sh history /workspace 10
./scripts/git_state_guardian.sh compare /workspace HEAD~3 HEAD
./scripts/git_state_guardian.sh restore /workspace HEAD~1 -- skills/
./scripts/git_state_guardian.sh tag /workspace known-good/pre-migration
```

## Assumptions

- The workspace has a hidden Git repo at `/workspace/.auto_git_repo`
- Commands are run from the skill directory or with an explicit path to the script
