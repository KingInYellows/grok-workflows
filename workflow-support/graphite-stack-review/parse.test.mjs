import test from "node:test";
import assert from "node:assert/strict";
import {
  classifyCheck,
  isBotAuthor,
  isIgnorableCheck,
  isIgnorableDirtyPath,
  isPrSlashRef,
  nonIgnorablePorcelainPaths,
  needsWorkFromLite,
  parseGtLogShort,
  parseOwnerRepo,
  partitionUnresolvedThreads,
  pickStartBranch,
  porcelainIsDirty,
  prNumberInRange,
  summarizePorcelain,
  threadHasReply,
  walkStackFromState,
  wallClockFromCheckpoint,
  checkoutNamedBranch,
  reviewThreadPage,
} from "./lib.mjs";

test("parseGtLogShort strips graph glyphs and restack annotations", () => {
  const text = [
    "◯  main",
    "◉  feat/one (needs restack)",
    "◯  feat/two",
    "│",
    "",
  ].join("\n");
  assert.deepEqual(parseGtLogShort(text), ["main", "feat/one", "feat/two"]);
});

test("walkStackFromState returns bottom-up order from a mid-stack branch", () => {
  const state = {
    main: { trunk: true, parents: [] },
    "feat/one": { trunk: false, parents: [{ ref: "main", sha: "aaa" }] },
    "feat/two": { trunk: false, parents: [{ ref: "feat/one", sha: "bbb" }] },
    "feat/three": { trunk: false, parents: [{ ref: "feat/two", sha: "ccc" }] },
  };
  assert.deepEqual(walkStackFromState(state, "feat/two", "main"), [
    "feat/one",
    "feat/two",
    "feat/three",
  ]);
});

test("isBotAuthor detects GitHub Apps and humans", () => {
  assert.equal(isBotAuthor({ login: "graphite-app[bot]", __typename: "Bot" }), true);
  assert.equal(isBotAuthor({ login: "codecov", type: "Bot" }), true);
  assert.equal(isBotAuthor({ login: "octocat", __typename: "User" }), false);
  assert.equal(isBotAuthor("dependabot[bot]"), true);
});

test("Graphite mergeability checks are ignored and do not create work", () => {
  assert.equal(isIgnorableCheck({ name: "Graphite / mergeability_check" }), true);
  assert.equal(classifyCheck({ name: "Graphite / mergeability_check", state: "UNKNOWN" }), "ignored");
  assert.equal(classifyCheck({ name: "build", state: "failure" }), "fail");
  assert.equal(
    needsWorkFromLite({
      unresolvedCount: 0,
      reviewDecision: "",
      mergeable: "MERGEABLE",
      ciFail: 0,
    }),
    false,
  );
  assert.equal(
    needsWorkFromLite({
      unresolvedCount: 2,
      reviewDecision: "",
      mergeable: "MERGEABLE",
      ciFail: 0,
    }),
    true,
  );
  assert.equal(
    needsWorkFromLite({
      unresolvedCount: 2,
      actionableUnresolvedCount: 0,
      reviewDecision: "",
      mergeable: "MERGEABLE",
      ciFail: 0,
    }),
    false,
  );
  assert.equal(
    needsWorkFromLite({
      unresolvedCount: 2,
      actionableUnresolvedCount: 1,
      reviewDecision: "",
      mergeable: "MERGEABLE",
      ciFail: 0,
    }),
    true,
  );
});

test("expired checkpoint wall clock is refreshed, live clock is kept", () => {
  const now = 1_000_000;
  const live = wallClockFromCheckpoint(
    { started_at_ms: now - 60_000, deadline_ms: now + 60_000 },
    now,
    720,
  );
  assert.equal(live.refreshed, false);
  assert.equal(live.startedAt, now - 60_000);
  const expired = wallClockFromCheckpoint(
    { started_at_ms: now - 13 * 60 * 60 * 1000, deadline_ms: now - 1000 },
    now,
    720,
  );
  assert.equal(expired.refreshed, true);
  assert.equal(expired.startedAt, now);
  assert.equal(expired.deadlineMs, now + 720 * 60 * 1000);
});

test("replied unresolved threads are awaiting human close, not needs_work", () => {
  assert.equal(threadHasReply({ comments: { totalCount: 1 } }), false);
  assert.equal(threadHasReply({ comments: { totalCount: 2 } }), true);
  assert.equal(threadHasReply({ comment_count: 2 }), true);
  assert.equal(threadHasReply({ comments: [{ id: 1 }] }), false);
  assert.equal(threadHasReply({ comments: [{ id: 1 }, { id: 2 }] }), true);
  const parts = partitionUnresolvedThreads([
    { id: "a", isResolved: false, comments: { totalCount: 1 } },
    { id: "b", isResolved: false, comments: { totalCount: 2 } },
    { id: "c", is_resolved: true, comments: { totalCount: 1 } },
  ]);
  assert.deepEqual(parts.actionable.map((t) => t.id), ["a"]);
  assert.deepEqual(parts.awaitingHumanClose.map((t) => t.id), ["b"]);
  assert.deepEqual(parts.unresolved.map((t) => t.id), ["a", "b"]);
});

test("porcelainIsDirty ignores untracked session artifacts only", () => {
  assert.equal(isIgnorableDirtyPath("plans/handoff/2026-09-09.md"), true);
  assert.equal(isIgnorableDirtyPath("plans/handoff/"), true);
  assert.equal(isIgnorableDirtyPath("plans/fix-worktree.md"), true);
  assert.equal(isIgnorableDirtyPath(".grok/workflows/x.rhai"), true);
  assert.equal(isIgnorableDirtyPath("backend/src/foo.ts"), false);
  assert.equal(porcelainIsDirty(""), false);
  assert.equal(porcelainIsDirty("?? plans/handoff/note.md\n?? .grok/tmp\n"), false);
  assert.equal(porcelainIsDirty("?? plans/handoff/\n"), false);
  assert.equal(porcelainIsDirty("?? plans/fix-worktree.md\n"), false);
  assert.equal(porcelainIsDirty(" M backend/src/foo.ts\n"), true);
  assert.equal(porcelainIsDirty("?? plans/handoff/note.md\n M backend/src/foo.ts\n"), true);
  assert.equal(porcelainIsDirty("?? leftover.txt\n"), true);
  assert.equal(
    porcelainIsDirty("?? docs/analysis/JWT_SERVICES_CONSOLIDATION_ANALYSIS.md\n"),
    true,
  );
  assert.equal(isPrSlashRef("pr/2107"), true);
  assert.equal(isPrSlashRef("agent/fix/request-logger-correlation"), false);
  assert.deepEqual(
    nonIgnorablePorcelainPaths("?? .grok/\n?? docs/analysis/JWT_SERVICES_CONSOLIDATION_ANALYSIS.md\n"),
    ["docs/analysis/JWT_SERVICES_CONSOLIDATION_ANALYSIS.md"],
  );
});

test("checkoutNamedBranch refuses pr slash refs before any git fetch", () => {
  const result = checkoutNamedBranch("/tmp", "pr/2107");
  assert.equal(result.ok, false);
  assert.equal(result.branch, "pr/2107");
  assert.match(result.error, /pr\/<N>/);
});

test("summarizePorcelain counts non-ignorable rows", () => {
  const porcelain = [
    " D backend/allure-results/a.json",
    " D tests/docs-qa/x.md",
    " M .github/workflows/ci-active-development.yml",
    "?? plans/fix-worktree.md",
  ].join("\n");
  const summary = summarizePorcelain(porcelain);
  assert.equal(summary.total, 3);
  assert.equal(summary.counts.deleted, 2);
  assert.equal(summary.counts.modified, 1);
  assert.equal(summary.counts.untracked, 0);
  assert.equal(summary.summary, "2 deleted, 1 modified");
});

test("pickStartBranch prefers explicit start, then from_pr head", () => {
  assert.deepEqual(
    pickStartBranch({
      explicitStart: "feat/explicit",
      currentBranch: "feat/current",
      fromPrHead: "feat/from-pr",
    }),
    { branch: "feat/explicit", resolved_from_pr: false },
  );
  assert.deepEqual(
    pickStartBranch({
      explicitStart: "",
      currentBranch: "feat/current",
      fromPrHead: "feat/from-pr",
    }),
    { branch: "feat/from-pr", resolved_from_pr: true },
  );
  assert.deepEqual(
    pickStartBranch({
      explicitStart: "",
      currentBranch: "feat/current",
      fromPrHead: "",
    }),
    { branch: "feat/current", resolved_from_pr: false },
  );
});

test("prNumberInRange filters inclusive bounds and ignores unset bounds", () => {
  assert.equal(prNumberInRange(2086, 0, 0), true);
  assert.equal(prNumberInRange(2086, 2086, 2185), true);
  assert.equal(prNumberInRange(2185, 2086, 2185), true);
  assert.equal(prNumberInRange(2085, 2086, 2185), false);
  assert.equal(prNumberInRange(2186, 2086, 2185), false);
  assert.equal(prNumberInRange(2094, 2094, 0), true);
  assert.equal(prNumberInRange(2093, 2094, 0), false);
  assert.equal(prNumberInRange(0, 2086, 2185), true);
});

test("reviewThreadPage rejects a missing connection, GraphQL errors, and non-JSON", () => {
  const empty = reviewThreadPage({});
  assert.equal(empty.ok, false);
  assert.equal(empty.nodes.length, 0);

  const failed = reviewThreadPage({ errors: [{ message: "boom" }] });
  assert.equal(failed.ok, false);
  assert.equal(failed.error, "boom");

  const junk = reviewThreadPage("not json");
  assert.equal(junk.ok, false);
  assert.equal(junk.error, "could not parse reviewThreads");

  const none = reviewThreadPage({
    data: {
      repository: {
        pullRequest: {
          reviewThreads: { nodes: [], pageInfo: { hasNextPage: false } },
        },
      },
    },
  });
  assert.equal(none.ok, true);
  assert.deepEqual(none.nodes, []);
});

test("parseOwnerRepo accepts ssh and https remotes", () => {
  assert.equal(
    parseOwnerRepo("git@github.com:Acme/widgets.git"),
    "Acme/widgets",
  );
  assert.equal(
    parseOwnerRepo("https://github.com/Acme/widgets.git"),
    "Acme/widgets",
  );
});
