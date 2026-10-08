import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  acquireLock,
  classifyCheck,
  initialPollShortcut,
  isBotAuthor,
  isIgnorableCheck,
  isIgnorableDirtyPath,
  isPrSlashRef,
  mergeStateBlocksReady,
  nonIgnorablePorcelainPaths,
  needsWorkFromLite,
  parseGtLogShort,
  parseOwnerRepo,
  partitionUnresolvedThreads,
  pickStartBranch,
  porcelainIsDirty,
  prNumberInRange,
  releaseLock,
  summarizePorcelain,
  threadHasReply,
  walkStackFromState,
  wallClockFromCheckpoint,
  checkoutNamedBranch,
  reviewThreadPage,
  writeJsonFile,
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

test("queued and running CheckRuns are pending until they have a conclusion", () => {
  for (const status of ["QUEUED", "IN_PROGRESS", "WAITING", "PENDING", "REQUESTED"]) {
    assert.equal(classifyCheck({ name: "build", status }), "pending");
  }
  assert.equal(
    classifyCheck({ name: "build", status: "COMPLETED", conclusion: "SUCCESS" }),
    "pass",
  );
  assert.equal(
    classifyCheck({ name: "build", status: "IN_PROGRESS", conclusion: "FAILURE" }),
    "fail",
  );
  assert.equal(
    classifyCheck({ name: "build", status: "COMPLETED", conclusion: "CANCELLED" }),
    "transient",
  );
  assert.equal(isIgnorableCheck({ context: "Graphite / mergeability_check" }), true);
  assert.equal(
    classifyCheck({ context: "Graphite / mergeability_check", status: "IN_PROGRESS" }),
    "ignored",
  );
});

test("draft and blocked merge states are not merge-ready", () => {
  assert.equal(mergeStateBlocksReady("BLOCKED", false), true);
  assert.equal(mergeStateBlocksReady("DRAFT", false), true);
  assert.equal(mergeStateBlocksReady("CLEAN", true), true);
  assert.equal(mergeStateBlocksReady("CLEAN", false), false);
  assert.equal(mergeStateBlocksReady("BEHIND", false), false);
  assert.equal(mergeStateBlocksReady("", false), false);
});

test("first poll snapshot does not treat pending CI or a moved head as stable", () => {
  assert.equal(initialPollShortcut("stable", true, false), "stable");
  assert.equal(initialPollShortcut("stable", false, false), "stable");
  assert.equal(initialPollShortcut("pending", false, false), "");
  assert.equal(initialPollShortcut("head_changed", false, false), "head_changed");
  assert.equal(initialPollShortcut("closed", true, false), "closed");
  assert.equal(initialPollShortcut("stable", false, true), "");
  assert.equal(initialPollShortcut("pending", false, true), "");
});

test("repo lock follows the owner token, not a dead CLI pid", () => {
  const file = path.join(os.tmpdir(), `gsr-lock-${process.pid}-${Date.now()}.lock`);
  fs.rmSync(file, { force: true });
  try {
    const first = acquireLock(file, 60_000, "run-a");
    assert.equal(first.ok, true);
    const again = acquireLock(file, 60_000, "run-a");
    assert.equal(again.ok, true);
    writeJsonFile(file, {
      pid: 2147483646,
      owner: "run-a",
      started_at_ms: Date.now(),
      host: "test",
    });
    const other = acquireLock(file, 60_000, "run-b");
    assert.equal(other.ok, false);
    assert.equal(releaseLock(file, "run-b", false), false);
    assert.equal(fs.existsSync(file), true);
    assert.equal(releaseLock(file, "run-a", false), true);
    assert.equal(fs.existsSync(file), false);

    writeJsonFile(file, {
      pid: 2147483646,
      owner: "run-a",
      started_at_ms: Date.now() - 120_000,
      host: "test",
    });
    const stale = acquireLock(file, 1_000, "run-b");
    assert.equal(stale.ok, true);
    assert.equal(releaseLock(file, "run-a", false), false);
    assert.equal(releaseLock(file, "run-b", true), true);
    assert.equal(fs.existsSync(file), false);
  } finally {
    fs.rmSync(file, { force: true });
  }
});
