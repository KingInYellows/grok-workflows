#!/usr/bin/env bash
# Copy workflows, skill trees, and runtime helpers into explicitly selected Grok homes.
# Usage: ./sync-workflows.sh [--dry-run] [--prune] [--prune-skills] [--destination GROK_HOME]
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./sync-workflows.sh [--dry-run] [--prune] [--prune-skills] [--destination GROK_HOME]

Copy every *.rhai, each skills/<name>/ tree, and bundled runtime helpers into
Grok config dirs (real files).

Destinations:
  ${GROK_HOME:-$HOME/.grok}/{workflows,skills,workflow-support}
  Additional Grok homes only when explicitly named with --destination

Options:
  --dry-run   Print actions without writing
  --prune     Delete destination *.rhai files that are not in this repo
  --prune-skills
              Delete destination skill directories that this repo does not ship.
              Requires a skills/ directory in this clone. Absent skills/ copies
              nothing and deletes nothing. This removes personal skills that
              were never imported, including every directory under
              <Grok home>/skills that has no skills/<name>/SKILL.md here.
  --destination PATH  Also install into this Grok home (repeatable; WSL paths for Windows)
  -h, --help  Show this help
EOF
}

DRY=0
PRUNE=0
PRUNE_SKILLS=0
EXTRA_DESTS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --prune) PRUNE=1 ;;
    --prune-skills) PRUNE_SKILLS=1 ;;
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
for extra in "${EXTRA_DESTS[@]+"${EXTRA_DESTS[@]}"}"; do
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

sync_skills() {
  local home="$1"
  local src_root="$REPO/skills"
  local dest_root="$home/skills"
  local added=0 updated=0 skipped=0 pruned=0

  if [[ ! -d "$src_root" ]]; then
    echo "-> $dest_root  added=0 updated=0 unchanged=0 pruned=0"
    return 0
  fi
  if [[ -L "$src_root" ]]; then
    echo "refusing symlink: $src_root" >&2
    exit 1
  fi

  local link skill name src rel target dest_skill base extra rel_extra
  while IFS= read -r -d '' link; do
    echo "refusing symlink: $link" >&2
    exit 1
  done < <(find "$src_root" -type l -print0)

  while IFS= read -r -d '' skill; do
    name="$(basename "$skill")"
    case "$name" in
      node_modules|.git) continue ;;
    esac
    if [[ ! -f "$skill/SKILL.md" ]]; then
      echo "skip    $skill (no SKILL.md)" >&2
      continue
    fi
    while IFS= read -r -d '' src; do
      rel="${src#"$skill/"}"
      case "/$rel/" in
        */node_modules/*|*/.git/*) continue ;;
      esac
      target="$dest_root/$name/$rel"
      if [[ -L "$target" ]]; then
        echo "refusing symlink: $target" >&2
        exit 1
      fi
      if [[ -f "$target" ]] && cmp -s "$src" "$target"; then
        skipped=$((skipped + 1))
        continue
      fi
      if [[ -e "$target" ]]; then
        updated=$((updated + 1))
        echo "update  $target"
      else
        added=$((added + 1))
        echo "add     $target"
      fi
      run mkdir -p "$(dirname "$target")"
      run cp -f "$src" "$target"
    done < <(find "$skill" -type f -print0)
  done < <(find "$src_root" -mindepth 1 -maxdepth 1 -type d -print0)

  if [[ "$PRUNE_SKILLS" -eq 1 && -d "$dest_root" && ! -L "$dest_root" ]]; then
    while IFS= read -r -d '' dest_skill; do
      if [[ -L "$dest_skill" ]]; then
        echo "refusing symlink: $dest_skill" >&2
        exit 1
      fi
      base="$(basename "$dest_skill")"
      if [[ ! -f "$src_root/$base/SKILL.md" ]]; then
        pruned=$((pruned + 1))
        echo "prune   $dest_skill"
        run rm -rf -- "$dest_skill"
        continue
      fi
      while IFS= read -r -d '' extra; do
        if [[ -L "$extra" ]]; then
          echo "refusing symlink: $extra" >&2
          exit 1
        fi
        rel_extra="${extra#"$dest_skill/"}"
        if [[ ! -f "$src_root/$base/$rel_extra" ]]; then
          pruned=$((pruned + 1))
          echo "prune   $extra"
          run rm -f -- "$extra"
        fi
      done < <(find "$dest_skill" -type f -print0)
    done < <(find "$dest_root" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) -print0)
  fi

  echo "-> $dest_root  added=$added updated=$updated unchanged=$skipped pruned=$pruned"
}

echo "source  $REPO (${#SOURCES[@]} workflows)"
for dest in "${DESTS[@]}"; do
  sync_one "$dest/workflows"
  sync_support "$dest"
  sync_skills "$dest"
done
