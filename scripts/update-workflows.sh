#!/usr/bin/env bash
# Pull this repo fast-forward only, then copy *.rhai into Grok config dirs.
# Never prunes. Safe for cron / systemd timers.
#
# Usage: ./scripts/update-workflows.sh [--dry-run] [--no-pull]
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/update-workflows.sh [--dry-run] [--no-pull]

Fast-forward this clone from origin/main, then copy *.rhai into Grok config
dirs via ./sync-workflows.sh. Local-only workflows are never deleted.

This script updates the source clone (~/projects/grok-workflows) and copies
files into Grok config dirs. It does not git-pull ~/.grok/workflows.

Options:
  --dry-run   Fetch and show git/sync actions without changing files
  --no-pull   Skip git fetch/pull; only copy the current tree
  -h, --help  Show this help

Exits non-zero if the clone is not on main, is dirty, or cannot fast-forward.
EOF
}

DRY=0
NO_PULL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --no-pull) NO_PULL=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

PATH="/usr/local/bin:/usr/bin:/bin:${HOME}/.local/bin${PATH:+:$PATH}"
export PATH
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}"

ROOT="${UPDATE_WORKFLOWS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REMOTE="${UPDATE_WORKFLOWS_REMOTE:-origin}"
BRANCH="${UPDATE_WORKFLOWS_BRANCH:-main}"
LOCK="${XDG_RUNTIME_DIR:-/tmp}/grok-update-workflows.lock"

log() {
  printf '%s %s\n' "$(date -Is)" "$*"
}

die() {
  log "error: $*" >&2
  exit 1
}

exec 9>"$LOCK"
if ! flock -n 9; then
  die "another update is already running ($LOCK)"
fi

cd "$ROOT"

[[ -d "$ROOT/.git" ]] || die "not a git clone: $ROOT"
[[ -x "$ROOT/sync-workflows.sh" ]] || die "missing $ROOT/sync-workflows.sh"

current="$(git symbolic-ref --quiet --short HEAD || true)"
[[ "$current" == "$BRANCH" ]] || die "clone is on '${current:-DETACHED}', expected $BRANCH"

dirty="$(git status --porcelain --untracked-files=normal)"
if [[ -n "$dirty" ]]; then
  printf '%s\n' "$dirty" >&2
  die "source clone is dirty; refusing to pull or overwrite local work"
fi

before="$(git rev-parse --short HEAD)"

if [[ "$NO_PULL" -eq 0 ]]; then
  log "fetch  $REMOTE"
  git fetch --prune --quiet "$REMOTE"

  if ! git rev-parse --verify --quiet "$REMOTE/$BRANCH" >/dev/null; then
    die "missing $REMOTE/$BRANCH"
  fi

  behind="$(git rev-list --count HEAD.."$REMOTE/$BRANCH")"
  ahead="$(git rev-list --count "$REMOTE/$BRANCH"..HEAD)"

  if [[ "$ahead" -gt 0 ]]; then
    die "clone is $ahead commit(s) ahead of $REMOTE/$BRANCH; refusing to diverge"
  fi

  if [[ "$behind" -eq 0 ]]; then
    log "git    already up to date ($before)"
  else
    log "git    $behind commit(s) behind $REMOTE/$BRANCH"
    git --no-pager log --oneline "HEAD..$REMOTE/$BRANCH"
    if [[ "$DRY" -eq 1 ]]; then
      log "dry-run: skip git merge --ff-only $REMOTE/$BRANCH"
    else
      git merge --ff-only --quiet "$REMOTE/$BRANCH"
    fi
  fi
else
  log "git    skipped (--no-pull)"
fi

after="$(git rev-parse --short HEAD)"
log "head   $before -> $after"

sync_args=()
if [[ "$DRY" -eq 1 ]]; then
  sync_args+=(--dry-run)
fi

if [[ ${#sync_args[@]} -gt 0 ]]; then
  log "sync   $ROOT/sync-workflows.sh ${sync_args[*]}"
  "$ROOT/sync-workflows.sh" "${sync_args[@]}"
else
  log "sync   $ROOT/sync-workflows.sh"
  "$ROOT/sync-workflows.sh"
fi
log "done"
