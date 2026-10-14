# Workflow readiness repairs (2026-10-14)

Target inspected: Grok Build **1.0.52** (`0920c8169e27`). These changes target
that runtime's documented host APIs; they are not a blanket certification of
all Grok versions or every workflow.

Run the offline regression checks from this repository:

```sh
node --test tests/*.test.mjs tests/*.test.cjs
./scripts/verify.sh
```

The readiness tests evaluate small boolean predicates extracted from the actual
Rhai source with mocked outcomes, and assert the control-flow callsites keep
using those decisions. They cover conflicting repair outputs, failed tests,
missing commit identity, incomplete review evidence, and invalidation/rerun of
the shared pipeline after a visual/performance writer. They do **not** execute
Rhai in Grok, execute shipping workflows, call GitHub/Graphite/Linear, or prove
model obedience, full runtime parsing, native Windows execution, or live agent
permissions. The source-derived predicate evaluator accepts only its tiny shared
boolean syntax; do not extend it into a general Rhai interpreter.

The original failure cases are:

- A committed repair with `tests_passed=false` or `ok=false` could submit anyway.
- A visual/performance repair could edit source after the last full pipeline
  pass, then complete using the stale green result.
- Truncated diff/policy evidence could be reported as an apparently clean review.
- Review/verification failures or omitted candidates could hide behind empty
  finding lists.
- `git_diff_since("origin/main")` is not a triple-dot branch collector: the
  inspected host rejects slash-containing arguments and uses `git diff <ref>`.
- Shellless read-only/explore children cannot independently run Git commands.

A bounded incomplete review must remain explicitly incomplete. A passing
regression check does not authorize merging, deploying, or executing the
consequential workflow. Use a disposable repository and an explicitly approved
runtime smoke test before adopting changed shipping workflows.

## Source evidence

- [Official Build release notes](https://x.ai/changelog/build)
- [Official subagent capabilities](https://docs.x.ai/build/features/subagents)
- [Pinned host diff implementation](https://github.com/xai-org/grok-build/blob/2bdd1d6a6369de0e8c68132ea4539e9abd9e14a8/crates/codegen/xai-grok-shell/src/session/workflow/host_service.rs#L931-L967)
- [Original submission readiness branch](https://github.com/KingInYellows/grok-workflows/blob/d9c1e0bb63aabf7f620ea4f628750eceda34217d/graphite-pr-review.rhai#L1254-L1277)
- [Original post-pipeline visual repair](https://github.com/KingInYellows/grok-workflows/blob/d9c1e0bb63aabf7f620ea4f628750eceda34217d/multi-track-ship.rhai#L908-L970)
