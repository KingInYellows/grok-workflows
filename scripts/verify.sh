#!/usr/bin/env bash
# Command: ./scripts/verify.sh
# Fails when support_cli() points only at ~/.grok/workflow-support, or when
# the poll CLI is not a regular file in this repo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REL="workflow-support/graphite-stack-review/cli.mjs"
CLI="$ROOT/$REL"
HOME_CLI='$HOME/.grok/workflow-support/graphite-stack-review/cli.mjs'
REPO_CLI='$HOME/projects/grok-workflows/workflow-support/graphite-stack-review/cli.mjs'

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

if [[ -L "$CLI" ]]; then
  fail "poll command is a symlink, not a regular file in this repo: $REL"
fi
if [[ ! -f "$CLI" ]]; then
  fail "poll command is not a file in this repo: $REL"
fi
case "$CLI" in
  "$ROOT"/*) ;;
  *) fail "poll command is outside this repo: $CLI" ;;
esac
if ! grep -q 'poll: cmdPoll' "$CLI"; then
  fail "cli.mjs does not define the poll command"
fi

files=(
  graphite-stack-review.rhai
  graphite-pr-review.rhai
  linear-cycle-deliver.rhai
  ship-next-issue.rhai
)
for name in "${files[@]}"; do
  path="$ROOT/$name"
  if grep -F "$HOME_CLI" "$path" >/dev/null; then
    fail "$name support_cli() still points only at the home path"
  fi
  body="$(awk '
    /fn support_cli\(\)/ { grab = 1; next }
    grab && /^}/ { exit }
    grab { print }
  ' "$path")"
  case "$body" in
    *"$REPO_CLI"*) ;;
    *) fail "$name support_cli() does not return the in-repo CLI" ;;
  esac
done

if ! grep -F "support_cli: \"$REPO_CLI\"" "$ROOT/graphite-stack-review.rhai" >/dev/null; then
  fail "graphite-stack-review.rhai support_cli map field is not the in-repo CLI"
fi

cd "$ROOT"
node --test workflow-support/graphite-stack-review/parse.test.mjs
