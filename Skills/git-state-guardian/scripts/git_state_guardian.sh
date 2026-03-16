#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  checkpoint <workspace> <message>
  tag <workspace> <tag> [ref]
  history <workspace> [count]
  checkpoint-list <workspace> [count]
  inspect <workspace>
  summary <workspace> [ref]
  changed-files <workspace> <from> <to>
  compare <workspace> <from> <to>
  compare-patch <workspace> <from> <to>
  diff <workspace> [ref]
  show <workspace> <ref>
  restore <workspace> <ref> -- <paths...>
  restore-all <workspace> <ref> [message]

Notes:
  - <workspace> must contain a bare Git repo at .auto_git_repo
  - restore is for targeted file or directory recovery
  - restore-all creates a new checkpoint-style commit that makes tracked files
    match <ref>; it does not move HEAD backwards and does not delete ignored or
    untracked files outside Git tracking
USAGE
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

note() {
  echo "$*"
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

require_ref() {
  local ref="$1"
  gitw rev-parse --verify --quiet "$ref^{commit}" >/dev/null || fail "unknown ref: $ref"
}

require_clean_refname() {
  local tag="$1"
  git check-ref-format "refs/tags/$tag" >/dev/null 2>&1 || fail "invalid tag name: $tag"
}

sanitize_for_tag_fragment() {
  local raw="$1"
  local cleaned
  cleaned="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  [[ -n "$cleaned" ]] || cleaned="manual"
  printf '%s' "$cleaned"
}

print_shortstat() {
  gitw diff --shortstat "$@" || true
}

print_stat() {
  gitw diff --stat "$@" || true
}

print_name_status() {
  gitw diff --name-status "$@" || true
}

case "$CMD" in
  checkpoint)
    [[ $# -ge 1 ]] || fail "checkpoint requires a message"
    MSG="$*"
    gitw add -A -- .
    if gitw diff --cached --quiet; then
      TS="$(date +%Y%m%d-%H%M%S)"
      SLUG="$(sanitize_for_tag_fragment "$MSG")"
      TAG="checkpoint/manual/${SLUG}-${TS}"
      require_clean_refname "$TAG"
      gitw tag "$TAG" HEAD
      note "Created tag $TAG"
    else
      gitw commit -m "checkpoint: $MSG"
    fi
    ;;
  tag)
    [[ $# -ge 1 ]] || fail "tag requires a tag name"
    TAG="$1"
    REF="${2:-HEAD}"
    require_clean_refname "$TAG"
    require_ref "$REF"
    gitw tag "$TAG" "$REF"
    note "Created tag $TAG -> $REF"
    ;;
  history)
    gitw log --oneline --decorate -n "${1:-20}"
    ;;
  checkpoint-list)
    COUNT="${1:-30}"
    gitw for-each-ref \
      --sort=-creatordate \
      --format='%(creatordate:short) %(refname:short) -> %(objectname:short) %(subject)' \
      refs/tags/checkpoint refs/tags/known-good | head -n "$COUNT"
    ;;
  inspect)
    echo "Status:"
    gitw status --short || true
    echo
    echo "Working tree summary:"
    print_shortstat
    print_stat
    echo
    echo "Staged summary:"
    print_shortstat --cached
    print_stat --cached
    ;;
  summary)
    if [[ $# -eq 0 ]]; then
      echo "Summary for working tree vs HEAD:"
      print_shortstat
      print_name_status
    elif [[ $# -eq 1 ]]; then
      REF="$1"
      require_ref "$REF"
      echo "Summary for working tree vs $REF:"
      print_shortstat "$REF"
      print_name_status "$REF"
    else
      fail "summary accepts zero or one ref"
    fi
    ;;
  changed-files)
    [[ $# -eq 2 ]] || fail "changed-files requires <from> and <to>"
    require_ref "$1"
    require_ref "$2"
    print_name_status "$1" "$2"
    ;;
  compare)
    [[ $# -eq 2 ]] || fail "compare requires <from> and <to>"
    require_ref "$1"
    require_ref "$2"
    print_shortstat "$1" "$2"
    print_stat "$1" "$2"
    ;;
  compare-patch)
    [[ $# -eq 2 ]] || fail "compare-patch requires <from> and <to>"
    require_ref "$1"
    require_ref "$2"
    gitw diff "$1" "$2"
    ;;
  diff)
    if [[ $# -eq 0 ]]; then
      gitw diff
    elif [[ $# -eq 1 ]]; then
      require_ref "$1"
      gitw diff "$1"
    else
      fail "diff accepts zero or one ref"
    fi
    ;;
  show)
    [[ $# -eq 1 ]] || fail "show requires a ref"
    require_ref "$1"
    gitw show --stat --patch "$1"
    ;;
  restore)
    [[ $# -ge 3 ]] || fail "restore requires <ref> -- <paths...>"
    REF="$1"
    require_ref "$REF"
    shift
    [[ "$1" == "--" ]] || fail "restore requires -- before the path list"
    shift
    [[ $# -ge 1 ]] || fail "restore requires at least one path"
    gitw checkout "$REF" -- "$@"
    note "Restored paths from $REF"
    ;;
  restore-all)
    [[ $# -ge 1 ]] || fail "restore-all requires <ref> [message]"
    REF="$1"
    require_ref "$REF"
    shift
    MSG="${*:-restore workspace to $REF}"

    mapfile -t EXTRA_TRACKED < <(gitw diff --name-only --diff-filter=A "$REF" HEAD || true)

    gitw checkout "$REF" -- .

    if [[ ${#EXTRA_TRACKED[@]} -gt 0 ]]; then
      rm -rf -- "${EXTRA_TRACKED[@]}"
    fi

    gitw add -A -- .
    if gitw diff --cached --quiet; then
      note "Workspace already matches tracked content from $REF"
    else
      gitw commit -m "restore-all: $MSG"
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac
