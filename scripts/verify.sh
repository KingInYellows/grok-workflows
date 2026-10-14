#!/usr/bin/env bash
# Safe local tests only: no Grok workflow, gt, gh, or external repository mutation.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/workflow-support/graphite-stack-review/cli.mjs"
[[ -f "$CLI" && ! -L "$CLI" ]] || { echo 'support CLI must be a regular file' >&2; exit 1; }
grep -q 'poll: cmdPoll' "$CLI"
cd "$ROOT"
for script in sync-workflows.sh scripts/update-workflows.sh; do
  bash -n "$script"
done
node --check workflow-support/graphite-stack-review/cli.mjs
node --test workflow-support/graphite-stack-review/parse.test.mjs scripts/portability.test.mjs
