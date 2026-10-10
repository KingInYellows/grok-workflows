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
  --dry-run   Fetch and show git/sync actions without changing files.
              If the remote is ahead, copy actions are previewed from that
              revision instead of the current checkout.
  --no-pull   Skip git fetch/pull; only copy the current tree
  -h, --help  Show this help

Exits non-zero if the clone is not on main, is dirty, cannot fast-forward,
or git fetch exceeds the timeout. A fetch that ignores SIGTERM is killed
after UPDATE_WORKFLOWS_FETCH_KILL_AFTER seconds (default 10).
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
# Scheduled runs must fail instead of waiting on a prompt or inherited askpass.
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=""

ROOT="${UPDATE_WORKFLOWS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REMOTE="${UPDATE_WORKFLOWS_REMOTE:-origin}"
BRANCH="${UPDATE_WORKFLOWS_BRANCH:-main}"
FETCH_TIMEOUT="${UPDATE_WORKFLOWS_FETCH_TIMEOUT:-120}"
FETCH_KILL_AFTER="${UPDATE_WORKFLOWS_FETCH_KILL_AFTER:-10}"

log() {
  printf '%s %s\n' "$(date -Is)" "$*"
}

die() {
  log "error: $*" >&2
  exit 1
}

# Owned by this user and not writable by group or other, so nobody else can
# plant a lock symlink in the directory.
private_dir() {
  local d="$1"
  local mode perm
  [[ -n "$d" && -d "$d" && ! -L "$d" && -O "$d" ]] || return 1
  mode="$(stat -c '%a' "$d")"
  perm=$((8#$mode))
  [[ $((perm & 022)) -eq 0 ]]
}

if [[ -n "${XDG_RUNTIME_DIR:-}" ]] && private_dir "$XDG_RUNTIME_DIR"; then
  LOCK="${XDG_RUNTIME_DIR}/grok-update-workflows.lock"
else
  lock_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/grok-workflows"
  mkdir -p -- "$lock_dir"
  chmod 700 -- "$lock_dir"
  LOCK="${lock_dir}/update-workflows.${EUID}.lock"
fi

if [[ -L "$LOCK" ]]; then
  die "refusing to follow lock symlink: $LOCK"
fi
exec 9>"$LOCK"
chmod 600 /dev/fd/9 2>/dev/null || true
if ! flock -n 9; then
  die "another update is already running ($LOCK)"
fi

cd "$ROOT"

[[ -d "$ROOT/.git" ]] || die "not a git clone: $ROOT"
[[ -x "$ROOT/sync-workflows.sh" ]] || die "missing $ROOT/sync-workflows.sh"
[[ "$FETCH_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || die "UPDATE_WORKFLOWS_FETCH_TIMEOUT must be a positive number of seconds"
[[ "$FETCH_KILL_AFTER" =~ ^[1-9][0-9]*$ ]] || die "UPDATE_WORKFLOWS_FETCH_KILL_AFTER must be a positive number of seconds"
command -v timeout >/dev/null 2>&1 || die "timeout(1) is required so git fetch cannot hold the lock"

current="$(git symbolic-ref --quiet --short HEAD || true)"
[[ "$current" == "$BRANCH" ]] || die "clone is on '${current:-DETACHED}', expected $BRANCH"

dirty="$(git status --porcelain --untracked-files=normal)"
if [[ -n "$dirty" ]]; then
  printf '%s\n' "$dirty" >&2
  die "source clone is dirty; refusing to pull or overwrite local work"
fi

before="$(git rev-parse --short HEAD)"
preview_rev=""
preview_parent=""

cleanup_preview() {
  if [[ -z "${preview_parent:-}" ]]; then
    return 0
  fi
  if [[ -d "$preview_parent/tree" ]]; then
    git -C "$ROOT" worktree remove --force "$preview_parent/tree" >/dev/null 2>&1 || true
  fi
  rm -rf -- "$preview_parent"
  preview_parent=""
}

run_sync() {
  local sync_root="$1"
  local sync_script="$sync_root/sync-workflows.sh"
  [[ -x "$sync_script" ]] || die "missing $sync_script"
  if [[ ${#sync_args[@]} -gt 0 ]]; then
    log "sync   $sync_script ${sync_args[*]}"
    "$sync_script" "${sync_args[@]}"
  else
    log "sync   $sync_script"
    "$sync_script"
  fi
}

# True when a fetch child still shares our process group.
# timeout(1) joins this group, and ps/awk appear in their own snapshot.
group_has_others() {
  local pgid snapshot
  pgid="$(ps -o pgid= -p "$$" | tr -d " ")"
  snapshot="$(ps -eo pid=,pgid=,comm=)"
  awk -v pgid="$pgid" -v self="$$" '
    $2 == pgid && $1 != self && $3 != "ps" && $3 != "awk" && $3 != "timeout" { found = 1 }
    END { exit found ? 0 : 1 }
  ' <<<"$snapshot"
}

# root plus every process whose parent chain still reaches it.
descendant_pids() {
  ps -eo pid=,ppid= | awk -v root="$1" '
    { pp[$1] = $2 }
    END {
      for (pid in pp) {
        p = pid
        seen = 0
        while (p && p != root && seen < 30) {
          p = pp[p]
          seen++
        }
        if (pid == root || p == root) print pid
      }
    }
  '
}

# Child of timeout(1). TERM is the first signal. A transport that ignores it,
# even from another process group, is killed after the grace period.
fetch_in_timeout() {
  local remote="$1"
  local grace="$2"
  local pid="" status="" timed_out=0 state=""
  local -a tree=()
  local -a alive=()
  local p
  trap 'timed_out=1' TERM
  git fetch --prune --quiet "$remote" &
  pid=$!
  while true; do
    if [[ -z "$status" ]]; then
      state="$(ps -o stat= -p "$pid" 2>/dev/null | awk '{print substr($1,1,1)}')"
      # A zombie still passes kill -0. Reap it before the tree check.
      if [[ -z "$state" || "$state" == "Z" ]]; then
        wait "$pid" && status=0 || status=$?
      else
        tree=()
        while read -r p; do
          [[ -n "$p" ]] && tree+=("$p")
        done < <(descendant_pids "$pid")
      fi
    fi
    alive=()
    for p in "${tree[@]}"; do
      if kill -0 "$p" 2>/dev/null; then
        alive+=("$p")
      fi
    done
    if [[ "$timed_out" -eq 1 || ( -n "$status" && ${#alive[@]} -gt 0 ) ]]; then
      for p in "${alive[@]}"; do
        kill -TERM "$p" 2>/dev/null || true
      done
      # New session: timeout's later KILL does not cancel this deadline.
      # Close the lock fd so the killer itself does not hold the flock.
      # shellcheck disable=SC2016 # inner shell expands $1 and $@
      setsid -f bash -c 'exec 9>&-; sleep "$1"; shift; for p in "$@"; do kill -KILL "$p" 2>/dev/null || true; done' \
        bash "$grace" "${alive[@]}" </dev/null >/dev/null 2>&1 || true
      exit 124
    fi
    if [[ -n "$status" && ${#alive[@]} -eq 0 ]] && ! group_has_others; then
      exit "$status"
    fi
    sleep 0.2
  done
}

if [[ "$NO_PULL" -eq 0 ]]; then
  log "fetch  $REMOTE (timeout ${FETCH_TIMEOUT}s, kill after ${FETCH_KILL_AFTER}s)"
  # TERM first. If fetch or a transport child ignores it, KILL follows so the
  # lock cannot be held past the grace period. KILL exits 137; TERM exits 124.
  export -f group_has_others descendant_pids fetch_in_timeout
  fetch_err="$(mktemp)"
  (
    timeout --kill-after="$FETCH_KILL_AFTER" "$FETCH_TIMEOUT" \
      bash -c 'fetch_in_timeout "$@"' bash "$REMOTE" "$FETCH_KILL_AFTER"
  ) 2>"$fetch_err" && fetch_status=0 || fetch_status=$?
  # Bash reports SIGKILL of timeout(1) as "Killed"; the die below is the log line.
  if [[ -s "$fetch_err" ]]; then
    grep -Ev 'Killed[[:space:]]+timeout --kill-after=|^Terminated$|^Killed$' "$fetch_err" >&2 || true
  fi
  rm -f "$fetch_err"
  if [[ "$fetch_status" -ne 0 ]]; then
    if [[ "$fetch_status" -eq 124 || "$fetch_status" -eq 137 ]]; then
      die "git fetch timed out after ${FETCH_TIMEOUT}s (kill-after ${FETCH_KILL_AFTER}s)"
    fi
    die "git fetch failed (exit $fetch_status)"
  fi

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
      preview_rev="$REMOTE/$BRANCH"
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

if [[ -n "$preview_rev" ]]; then
  preview_parent="$(mktemp -d "${TMPDIR:-/tmp}/grok-update-workflows.XXXXXX")"
  trap cleanup_preview EXIT
  log "dry-run: preview sync from $preview_rev"
  git -C "$ROOT" worktree add --detach --quiet "$preview_parent/tree" "$preview_rev"
  run_sync "$preview_parent/tree"
  cleanup_preview
  trap - EXIT
else
  run_sync "$ROOT"
fi
log "done"
