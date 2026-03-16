#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  checkpoint <workspace> <message>
  tag <workspace> <tag> [ref]
  history <workspace> [count]
  inspect <workspace>
  compare <workspace> <from> <to>
  restore <workspace> <ref> -- <paths...>
USAGE
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

[[ $# -ge 2 ]] || {
  usage
  exit 1
}

CMD="$1"
WS="$2"
shift 2

[[ -d "$WS" ]] || fail "workspace does not exist: $WS"
GIT_DIR="$WS/.auto_git_repo"
[[ -d "$GIT_DIR" ]] || fail "missing git dir: $GIT_DIR"
[[ -f "$GIT_DIR/HEAD" ]] || fail "invalid git dir: $GIT_DIR"

gitw() {
  git --git-dir="$GIT_DIR" --work-tree="$WS" "$@"
}

case "$CMD" in
  checkpoint)
    [[ $# -ge 1 ]] || fail "checkpoint requires a message"
    MSG="$*"
    gitw add -A -- .
    if gitw diff --cached --quiet; then
      TS="$(date +%Y%m%d-%H%M%S)"
      gitw tag "checkpoint/manual-$TS" HEAD
      echo "Created tag checkpoint/manual-$TS"
    else
      gitw commit -m "checkpoint: $MSG"
    fi
    ;;
  tag)
    [[ $# -ge 1 ]] || fail "tag requires a tag name"
    gitw tag "$1" "${2:-HEAD}"
    ;;
  history)
    gitw log --oneline --decorate -n "${1:-20}"
    ;;
  inspect)
    gitw status --short
    echo
    echo "Unstaged changes:"
    gitw diff --stat || true
    echo
    echo "Staged changes:"
    gitw diff --cached --stat || true
    ;;
  compare)
    [[ $# -eq 2 ]] || fail "compare requires <from> and <to>"
    gitw diff --stat "$1" "$2"
    ;;
  restore)
    [[ $# -ge 3 ]] || fail "restore requires <ref> -- <paths...>"
    REF="$1"
    shift
    [[ "$1" == "--" ]] || fail "restore requires -- before the path list"
    shift
    [[ $# -ge 1 ]] || fail "restore requires at least one path"
    gitw checkout "$REF" -- "$@"
    ;;
  *)
    usage
    exit 1
    ;;
esac
