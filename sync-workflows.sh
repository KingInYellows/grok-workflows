#!/usr/bin/env bash
# Copy workflows and runtime helpers into explicitly selected Grok homes.
# Usage: ./sync-workflows.sh [--dry-run] [--prune] [--destination GROK_HOME]
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./sync-workflows.sh [--dry-run] [--prune] [--destination GROK_HOME]

Copy every *.rhai and bundled runtime helper into Grok config dirs (real files).

Destinations:
  ${GROK_HOME:-$HOME/.grok}/{workflows,workflow-support}
  Additional Grok homes only when explicitly named with --destination

Options:
  --dry-run   Print actions without writing
  --prune     Delete destination *.rhai files that are not in this repo
  --destination PATH  Also install into this Grok home (repeatable; WSL paths for Windows)
  -h, --help  Show this help
EOF
}

DRY=0
PRUNE=0
EXTRA_DESTS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --prune) PRUNE=1 ;;
    --destination)
      [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || { echo "--destination requires a Grok home" >&2; exit 2; }
      EXTRA_DESTS+=("$2"); shift ;;
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

add_dest "${GROK_HOME:-$HOME/.grok}"
for extra in "${EXTRA_DESTS[@]}"; do
  add_dest "$extra"
done

sync_support() {
  local home="$1" src rel target
  while IFS= read -r -d '' src; do
    rel="${src#"$REPO/"}"
    target="$home/$rel"
    if [[ -f "$target" ]] && cmp -s "$src" "$target"; then continue; fi
    run mkdir -p "$(dirname "$target")"
    run cp -f "$src" "$target"
  done < <(find "$REPO/workflow-support" -type f -name '*.mjs' ! -name '*.test.mjs' -print0)
}

echo "source  $REPO (${#SOURCES[@]} workflows)"
for dest in "${DESTS[@]}"; do
  sync_one "$dest/workflows"
  sync_support "$dest"
done
