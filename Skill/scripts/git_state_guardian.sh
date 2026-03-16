#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage:"
  echo "  checkpoint <workspace> <msg>"
  echo "  tag <workspace> <tag> [ref]"
  echo "  history <workspace> [n]"
  echo "  inspect <workspace>"
  echo "  compare <workspace> <from> <to>"
  echo "  restore <workspace> <ref> -- <paths...>"
}

if [[ $# -lt 2 ]]; then usage; exit 1; fi

CMD="$1"
WS="$2"
shift 2

GIT_DIR="$WS/.auto_git_repo"

gitw() {
  git --git-dir="$GIT_DIR" --work-tree="$WS" "$@"
}

case "$CMD" in
  checkpoint)
    MSG="$*"
    gitw add -A
    if gitw diff --cached --quiet; then
      gitw tag "checkpoint/manual"
    else
      gitw commit -m "checkpoint: $MSG"
    fi
    ;;
  tag)
    gitw tag "$1" "${2:-HEAD}"
    ;;
  history)
    gitw log --oneline --decorate -n "${1:-20}"
    ;;
  inspect)
    gitw status --short
    echo
    gitw diff --stat || true
    ;;
  compare)
    gitw diff --stat "$1" "$2"
    ;;
  restore)
    REF="$1"
    shift
    [[ "$1" == "--" ]] || { echo "Missing --"; exit 1; }
    shift
    gitw checkout "$REF" -- "$@"
    ;;
  *)
    usage; exit 1
    ;;
esac
