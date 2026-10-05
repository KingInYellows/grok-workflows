#!/usr/bin/env bash
# Copy *.rhai from this repo into Grok's real config directories.
# Usage: ./sync-workflows.sh [--dry-run] [--prune]
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./sync-workflows.sh [--dry-run] [--prune]

Copy every *.rhai in this repo into Grok config dirs (real files, not a symlink).

Destinations:
  ~/.grok/workflows
  /mnt/c/Users/<you>/.grok/workflows   (WSL only, if that Windows grok home exists)

Options:
  --dry-run   Print actions without writing
  --prune     Delete destination *.rhai files that are not in this repo
  -h, --help  Show this help
EOF
}

DRY=0
PRUNE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --prune) PRUNE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
shopt -s nullglob
SOURCES=("$REPO"/*.rhai)
if [[ ${#SOURCES[@]} -eq 0 ]]; then
  echo "no *.rhai files in $REPO" >&2
  exit 1
fi

run() {
  if [[ "$DRY" -eq 1 ]]; then
    printf 'dry-run: '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

sync_one() {
  local dest="$1"
  local added=0 updated=0 skipped=0 pruned=0

  run mkdir -p "$dest"

  local src base target
  for src in "${SOURCES[@]}"; do
    base="$(basename "$src")"
    target="$dest/$base"
    if [[ -f "$target" ]] && cmp -s "$src" "$target"; then
      skipped=$((skipped + 1))
      continue
    fi
    if [[ -f "$target" ]]; then
      updated=$((updated + 1))
      echo "update  $target"
    else
      added=$((added + 1))
      echo "add     $target"
    fi
    run cp -f "$src" "$target"
  done

  if [[ "$PRUNE" -eq 1 ]]; then
    local extra
    for extra in "$dest"/*.rhai; do
      [[ -e "$extra" ]] || continue
      base="$(basename "$extra")"
      if [[ ! -f "$REPO/$base" ]]; then
        pruned=$((pruned + 1))
        echo "prune   $extra"
        run rm -f "$extra"
      fi
    done
  fi

  echo "-> $dest  added=$added updated=$updated unchanged=$skipped pruned=$pruned"
}

declare -a DESTS=()
add_dest() {
  local d="$1"
  local x
  for x in "${DESTS[@]+"${DESTS[@]}"}"; do
    [[ "$x" == "$d" ]] && return
  done
  DESTS+=("$d")
}

add_dest "$HOME/.grok/workflows"

# Windows grok home, visible from WSL.
if [[ -d /mnt/c/Users ]]; then
  for grok_home in /mnt/c/Users/*/.grok; do
    [[ -d "$grok_home" ]] || continue
    user_dir="$(basename "$(dirname "$grok_home")")"
    case "$user_dir" in
      Default|Default\ User|Public|'All Users'|WDAGUtilityAccount) continue ;;
    esac
    add_dest "$grok_home/workflows"
  done
fi

echo "source  $REPO (${#SOURCES[@]} workflows)"
for dest in "${DESTS[@]}"; do
  sync_one "$dest"
done
