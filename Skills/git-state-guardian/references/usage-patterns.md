# Usage Patterns

## Standard agent loop

1. `inspect`
2. `checkpoint`
3. make changes
4. `compare` or `summary`
5. `tag` if stable
6. `restore` or `restore-all` if recovery is needed

## Prefer targeted recovery

Use `restore` first for one or a few files.
Use `restore-all` only when the entire tracked workspace needs to be rolled back.

## Change explanation flow

For user-facing summaries:

1. `compare` for scope
2. `changed-files` for file list
3. `compare-patch` only for important files or deeper inspection
