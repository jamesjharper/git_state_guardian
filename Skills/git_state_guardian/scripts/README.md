# git_state_guardian.sh

Helper for local workspace Git history.

Examples:

```bash
scripts/git_state_guardian.sh checkpoint /workspace "before change"
scripts/git_state_guardian.sh inspect /workspace
scripts/git_state_guardian.sh restore /workspace HEAD~1 -- skills/
```
