#!/usr/bin/env node
/**
 * graphite-stack-review support CLI.
 *
 * Deterministic Graphite/GitHub snapshot, poll, lock, checkpoint, and
 * narrowly scoped mutation helpers. Agents call this; the workflow
 * orchestrator does not parse CLI output itself.
 *
 * Usage:
 *   node cli.mjs <command> [flags]
 *
 * Commands:
 *   discover          Enumerate the current Graphite stack bottom-up
 *   pr-state          Fetch GitHub review + CI + mergeability state
 *   poll              Poll one PR head until an event or timeout
 *   checkpoint-get    Load the stack checkpoint
 *   checkpoint-put    Merge and save checkpoint fields
 *   reply             Reply to a pull-request review comment
 *   resolve-thread    Resolve a review thread by GraphQL id
 *   rerun-run         Rerun a GitHub Actions run (failed jobs)
 *   lock-acquire      Acquire the per-repo lock (--owner TOKEN)
 *   lock-release      Release the per-repo lock (--owner TOKEN, or --force)
 *   restore           Checkout the original branch recorded at discover
 *   checkout          Checkout a named branch without fetching pr/<N>
 *   review-diff       Incremental git diff vs immediate parent
 *   smoke             Non-mutating self-check
 */

import fs from "node:fs";
import path from "node:path";
import {
  SUPPORT_DIR,
  acquireLock,
  asBool,
  checkpointPath,
  classifyCheck,
  clampInt,
  mergeStateBlocksReady,
  initialPollShortcut,
  needsWorkFromLite,
  currentBranch,
  decodeJson,
  failJson,
  fingerprint,
  gh,
  git,
  gitRoot,
  gt,
  isBotAuthor,
  lockPath,
  nowMs,
  parseFlags,
  parseGtLogShort,
  parseOwnerRepo,
  partitionUnresolvedThreads,
  reviewThreadPage,
  porcelainIsDirty,
  pickStartBranch,
  printJson,
  summarizePorcelain,
  checkoutNamedBranch,
  readJsonFile,
  releaseLock,
  remoteOriginUrl,
  repoKey,
  stateDir,
  sleepSeconds,
  threadHasReply,
  walkStackFromState,
  wallClockFromCheckpoint,
  which,
  writeJsonFile,
  prNumberInRange,
} from "./lib.mjs";

const THREADS_QUERY = `
query($owner: String!, $name: String!, $number: Int!, $cursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 50, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          isOutdated
          path
          comments(first: 40) {
            nodes {
              databaseId
              url
              body
              createdAt
              author { __typename login }
              path
              originalLine
              line
            }
          }
        }
      }
    }
  }
}
`.trim();

const RESOLVE_MUTATION = `
mutation($id: ID!) {
  resolveReviewThread(input: { threadId: $id }) {
    thread { id isResolved }
  }
}
`.trim();

const THREADS_LITE_QUERY = `
query($owner: String!, $name: String!, $number: Int!, $cursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 50, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          comments { totalCount }
        }
      }
    }
  }
}
`.trim();

function usage() {
  return `graphite-stack-review support CLI
Usage: node cli.mjs <command> [flags]

Commands:
  discover          Enumerate the Graphite stack bottom-up (read-only unless --checkout)
  pr-state          Fetch GitHub review/CI/mergeability JSON for one PR
  poll              Poll one PR head until event or timeout
  checkpoint-get    Print the stack checkpoint
  checkpoint-put    Merge JSON fields into the checkpoint (--stdin-json)
  reply             Reply to a review comment (--comment-id --body)
  resolve-thread    Resolve a review thread (--thread-id)
  rerun-run         Rerun a GitHub Actions run (--run-id [--failed])
  lock-acquire      Acquire the per-repo lock (--owner TOKEN)
  lock-release      Release the per-repo lock (--owner TOKEN, or --force)
  restore           Checkout the original branch recorded at discover
  checkout          Checkout a named branch without fetching pr/<N>
  review-diff       Incremental git diff vs immediate parent (read-only)
  smoke             Non-mutating self-check

Shared flags:
  --dry-run
  --repo OWNER/NAME
  --start-branch NAME
  --max-prs N
  --resume / --no-resume
  --pr N
  --from-pr N
  --to-pr N
  --cwd PATH
`;
}

function die(error, extra = {}) {
  failJson(error, extra);
  process.exit(2);
}

function requireBins() {
  const missing = [];
  for (const bin of ["gt", "gh", "git"]) {
    if (!which(bin)) missing.push(bin);
  }
  return missing;
}

function repoInfo(cwd) {
  const viewed = gh(
    ["repo", "view", "--json", "nameWithOwner,defaultBranchRef,url", "-q", "{nameWithOwner,defaultBranch:.defaultBranchRef.name,url}"],
    { cwd },
  );
  let nameWithOwner = "";
  let defaultBranch = "";
  let url = "";
  const parsed = decodeJson(viewed.stdout, null);
  if (parsed && parsed.nameWithOwner) {
    nameWithOwner = parsed.nameWithOwner;
    defaultBranch = parsed.defaultBranch || "";
    url = parsed.url || "";
  } else {
    nameWithOwner = parseOwnerRepo(remoteOriginUrl(cwd));
  }
  const trunk = gt(["trunk"], { cwd });
  const trunkName = trunk.status === 0 ? trunk.stdout.trim().split(/\s+/)[0] : defaultBranch;
  const porcelain = git(["status", "--porcelain"], { cwd }).stdout;
  const dirtyInfo = summarizePorcelain(porcelain);
  return {
    repo: nameWithOwner,
    default_branch: defaultBranch,
    trunk: trunkName || defaultBranch || "main",
    url,
    git_root: gitRoot(cwd),
    current_branch: currentBranch(cwd),
    dirty: dirtyInfo.total > 0,
    dirty_summary: dirtyInfo.summary,
    dirty_samples: dirtyInfo.samples,
  };
}

function resolvePrHeadBranch(cwd, prNumber) {
  const viewed = gh(
    ["pr", "view", String(prNumber), "--json", "headRefName,state,number"],
    { cwd },
  );
  const parsed = decodeJson(viewed.stdout, null);
  if (!parsed || !parsed.headRefName) {
    return { branch: "", error: (viewed.stderr || viewed.stdout || "gh pr view failed").trim() };
  }
  return { branch: parsed.headRefName, state: parsed.state || "", error: "" };
}

function loadCheckpoint(repo, startBranch) {
  const filePath = checkpointPath(repo, startBranch);
  return { path: filePath, data: readJsonFile(filePath, null) };
}

function saveCheckpoint(repo, startBranch, data) {
  const filePath = checkpointPath(repo, startBranch);
  writeJsonFile(filePath, data);
  return filePath;
}

function deadlineOf(checkpoint, maxWallClockMinutes) {
  const started = Number(checkpoint && checkpoint.started_at_ms ? checkpoint.started_at_ms : nowMs());
  const minutes = clampInt(maxWallClockMinutes, 480, 1, 24 * 60);
  return started + minutes * 60 * 1000;
}

function listOpenPrs(cwd) {
  const result = gh(
    [
      "pr",
      "list",
      "--state",
      "open",
      "--limit",
      "1000",
      "--json",
      "number,title,state,headRefName,baseRefName,url,isDraft,headRefOid,reviewDecision,mergeable,mergeStateStatus",
    ],
    { cwd, timeoutMs: 180000 },
  );
  if (result.status !== 0) {
    return { ok: false, error: result.stderr || result.stdout || "gh pr list failed", prs: [] };
  }
  const prs = decodeJson(result.stdout, []);
  return { ok: true, prs: Array.isArray(prs) ? prs : [] };
}

function stackBranches(cwd, startBranch, trunk, dryRun) {
  const log = gt(["log", "short", "--stack", "--reverse"], { cwd });
  let branches = [];
  if (log.status === 0) {
    branches = parseGtLogShort(log.stdout).filter((name) => name && name !== trunk);
  }
  if (startBranch && branches.includes(startBranch)) {
    return { method: "gt-log-stack", branches };
  }
  const state = gt(["state"], { cwd });
  const parsed = decodeJson(state.stdout, null);
  if (parsed && startBranch) {
    const walked = walkStackFromState(parsed, startBranch, trunk);
    if (walked.length) return { method: "gt-state-walk", branches: walked };
  }
  if (branches.length) return { method: "gt-log-stack-unverified", branches };
  return { method: "empty", branches: [] };
}

function cmdDiscover(flags) {
  const cwd = flags.cwd || process.cwd();
  const missing = requireBins();
  if (missing.length) {
    return {
      ok: false,
      error: `missing required binaries: ${missing.join(", ")}`,
      prs: [],
    };
  }
  const dryRun = asBool(flags.dry_run, false);
  const resume = asBool(flags.resume, true);
  const maxPrs = clampInt(flags.max_prs, 100, 1, 100);
  const maxWall = clampInt(flags.max_wall_clock_minutes, 720, 1, 24 * 60);
  const fromPr = clampInt(flags.from_pr, 0, 0, 1_000_000_000);
  const toPr = clampInt(flags.to_pr, 0, 0, 1_000_000_000);
  const info = repoInfo(cwd);
  if (!info.repo) {
    return { ok: false, error: "could not resolve owner/repo from gh or git remote", prs: [] };
  }
  const originalBranch = info.current_branch;
  let fromPrHead = "";
  if (!flags.start_branch && fromPr > 0) {
    const resolved = resolvePrHeadBranch(cwd, fromPr);
    fromPrHead = resolved.branch || "";
  }
  const picked = pickStartBranch({
    explicitStart: flags.start_branch || "",
    currentBranch: originalBranch,
    fromPrHead,
  });
  const startBranch = picked.branch;
  if (!startBranch) {
    return { ok: false, error: "no current branch and no --start-branch", prs: [] };
  }

  if (!dryRun && startBranch && startBranch !== originalBranch && !info.dirty) {
    const co = checkoutNamedBranch(cwd, startBranch, { fromPr });
    if (!co.ok) {
      return {
        ok: false,
        error: `checkout ${startBranch} failed: ${co.error || "unknown checkout error"}`,
        dirty: info.dirty,
        dirty_summary: info.dirty_summary || "",
        prs: [],
      };
    }
    info.current_branch = currentBranch(cwd);
  }

  const lockFile = lockPath(info.repo);
  let lock = { ok: true, skipped: true };
  if (!dryRun && flags.lock !== false) {
    lock = acquireLock(lockFile, undefined, lockOwner(flags));
    if (!lock.ok) {
      return {
        ok: false,
        error: lock.error || "could not acquire repo lock",
        lock,
        prs: [],
      };
    }
  }

  const ck = loadCheckpoint(info.repo, startBranch);
  const existing = resume && ck.data && ck.data.repo === info.repo ? ck.data : null;
  const clock = wallClockFromCheckpoint(existing, nowMs(), maxWall);
  const startedAt = clock.startedAt;
  const deadlineMs = clock.deadlineMs;
  const deadlineExceeded = nowMs() > deadlineMs;

  const stacked = stackBranches(cwd, startBranch, info.trunk, dryRun);
  const open = listOpenPrs(cwd);
  if (!open.ok) {
    return { ok: false, error: open.error, prs: [], repo: info.repo };
  }
  const byHead = new Map();
  for (const pr of open.prs) {
    if (pr && pr.headRefName) byHead.set(pr.headRefName, pr);
  }

  const dropped = [];
  const prs = [];
  let workCount = 0;
  let parentBranch = info.trunk;
  for (const branch of stacked.branches) {
    const pr = byHead.get(branch);
    if (!pr) {
      dropped.push({ branch, reason: "no open pull request" });
      parentBranch = branch;
      continue;
    }
    if (!prNumberInRange(pr.number, fromPr, toPr)) {
      const reason = fromPr > 0 && pr.number < fromPr ? "below from_pr" : "above to_pr";
      dropped.push({ branch, reason, pr_number: pr.number });
      parentBranch = branch;
      continue;
    }
    const row = {
      index: prs.length,
      branch,
      parent_branch: parentBranch,
      pr_number: pr.number,
      pr_url: pr.url,
      title: pr.title,
      state: pr.state,
      is_draft: Boolean(pr.isDraft),
      head_sha: pr.headRefOid || "",
      base_ref: pr.baseRefName || parentBranch,
      review_decision: pr.reviewDecision || "",
      mergeable: pr.mergeable || "",
      merge_state_status: pr.mergeStateStatus || "",
      needs_work: true,
      merge_ready: false,
      unresolved_count: -1,
    };
    const lite = cmdPrState({ cwd, pr: row.pr_number, lite: true });
    if (lite.ok) {
      row.merge_ready = Boolean(lite.merge_ready);
      row.unresolved_count = Number(
        lite.actionable_unresolved_count ?? (lite.actionable_unresolved_threads || []).length,
      );
      row.awaiting_human_close_count = Number(lite.awaiting_human_close_count || 0);
      row.ci = lite.ci || {};
      row.review_decision = lite.review_decision || row.review_decision;
      row.mergeable = lite.mergeable || row.mergeable;
      row.merge_state_status = lite.merge_state_status || row.merge_state_status;
      row.head_sha = lite.head_sha || row.head_sha;
      row.needs_work = Boolean(lite.needs_work);
    } else {
      row.triage_error = lite.error || "lite pr-state failed";
      row.needs_work = true;
    }
    if (row.needs_work && workCount >= maxPrs) {
      dropped.push({ branch, reason: "over max_prs" });
      parentBranch = branch;
      continue;
    }
    row.index = prs.length;
    prs.push(row);
    if (row.needs_work) workCount += 1;
    parentBranch = branch;
  }

  const checkpoint = {
    version: 1,
    repo: info.repo,
    trunk: info.trunk,
    start_branch: startBranch,
    original_branch: originalBranch,
    started_at_ms: startedAt,
    deadline_ms: deadlineMs,
    pass: existing && existing.pass ? existing.pass : 0,
    prs: existing && existing.prs ? existing.prs : {},
    last_discover_ms: nowMs(),
    dry_run: dryRun,
  };
  if (!dryRun) {
    saveCheckpoint(info.repo, startBranch, checkpoint);
    writeJsonFile(path.join(stateDir(info.repo), "original.json"), {
      branch: originalBranch,
      git_root: info.git_root,
      saved_at_ms: nowMs(),
    });
  }

  return {
    ok: true,
    error: "",
    dry_run: dryRun,
    repo: info.repo,
    git_root: info.git_root,
    trunk: info.trunk,
    current_branch: info.current_branch,
    original_branch: originalBranch,
    start_branch: startBranch,
    start_branch_resolved_from_pr: Boolean(picked.resolved_from_pr),
    from_pr: fromPr,
    to_pr: toPr,
    dirty: info.dirty,
    dirty_summary: info.dirty_summary || "",
    dirty_samples: info.dirty_samples || [],
    started_at_ms: startedAt,
    deadline_ms: deadlineMs,
    deadline_exceeded: deadlineExceeded,
    method: stacked.method,
    support_dir: SUPPORT_DIR,
    checkpoint_path: checkpointPath(info.repo, startBranch),
    lock_path: lockFile,
    lock_acquired: Boolean(lock.ok) && !lock.skipped,
    resumed: Boolean(existing),
    deadline_refreshed: Boolean(clock.refreshed && existing),
    prs,
    dropped,
    dropped_count: dropped.length,
    truncated: dropped.some((row) => row.reason === "over max_prs"),
  };
}

function graphql(cwd, query, vars) {
  const args = ["api", "graphql", "-f", `query=${query}`];
  for (const [key, value] of Object.entries(vars || {})) {
    if (value === undefined || value === null || value === "") continue;
    if (typeof value === "number") args.push("-F", `${key}=${value}`);
    else args.push("-f", `${key}=${value}`);
  }
  return gh(args, { cwd, timeoutMs: 180000 });
}

function fetchThreads(cwd, owner, name, number) {
  const threads = [];
  let cursor = "";
  for (let page = 0; page < 20; page += 1) {
    const vars = { owner, name, number };
    if (cursor) vars.cursor = cursor;
    const result = graphql(cwd, THREADS_QUERY, vars);
    if (result.status !== 0) {
      return { ok: false, error: result.stderr || result.stdout || "graphql reviewThreads failed", threads };
    }
    const page = reviewThreadPage(result.stdout);
    if (!page.ok) {
      return { ok: false, error: page.error || "could not parse reviewThreads", threads };
    }
    for (const node of page.nodes) threads.push(node);
    if (!(page.pageInfo && page.pageInfo.hasNextPage)) break;
    cursor = page.pageInfo.endCursor || "";
    if (!cursor) break;
  }
  return { ok: true, threads };
}

function fetchUnresolvedCount(cwd, owner, name, number) {
  const unresolved = [];
  let cursor = "";
  let total = 0;
  for (let page = 0; page < 20; page += 1) {
    const vars = { owner, name, number };
    if (cursor) vars.cursor = cursor;
    const result = graphql(cwd, THREADS_LITE_QUERY, vars);
    if (result.status !== 0) {
      return {
        ok: false,
        error: result.stderr || result.stdout || "lite reviewThreads failed",
        total,
        unresolved,
        actionable: [],
        awaiting_human_close: [],
      };
    }
    const page = reviewThreadPage(result.stdout);
    if (!page.ok) {
      return {
        ok: false,
        error: page.error || "could not parse reviewThreads",
        total,
        unresolved,
        actionable: [],
        awaiting_human_close: [],
      };
    }
    for (const node of page.nodes) {
      total += 1;
      if (node && node.isResolved === false) {
        const commentCount =
          node.comments && typeof node.comments.totalCount === "number" ? node.comments.totalCount : 0;
        unresolved.push({
          id: node.id,
          is_resolved: false,
          comment_count: commentCount,
          has_reply: commentCount > 1,
        });
      }
    }
    if (!(page.pageInfo && page.pageInfo.hasNextPage)) break;
    cursor = page.pageInfo.endCursor || "";
    if (!cursor) break;
  }
  const parts = partitionUnresolvedThreads(unresolved);
  return {
    ok: true,
    total,
    unresolved: parts.unresolved,
    actionable: parts.actionable,
    awaiting_human_close: parts.awaitingHumanClose,
  };
}

function fetchIssueComments(cwd, number) {
  const result = gh(
    ["api", `repos/{owner}/{repo}/issues/${number}/comments`, "--paginate"],
    { cwd, timeoutMs: 180000 },
  );
  if (result.status !== 0) return { ok: false, error: result.stderr || result.stdout, comments: [] };
  const comments = decodeJson(result.stdout, []);
  return { ok: true, comments: Array.isArray(comments) ? comments : [] };
}

function fetchReviewComments(cwd, number) {
  const result = gh(
    ["api", `repos/{owner}/{repo}/pulls/${number}/comments`, "--paginate"],
    { cwd, timeoutMs: 180000 },
  );
  if (result.status !== 0) return { ok: false, error: result.stderr || result.stdout, comments: [] };
  const comments = decodeJson(result.stdout, []);
  return { ok: true, comments: Array.isArray(comments) ? comments : [] };
}

function normalizeThread(thread) {
  const comments = (((thread || {}).comments || {}).nodes || []).map((c) => ({
    database_id: c.databaseId,
    url: c.url || "",
    body: c.body || "",
    created_at: c.createdAt || "",
    path: c.path || thread.path || "",
    line: c.line || c.originalLine || null,
    author: c.author && c.author.login ? c.author.login : "",
    author_typename: c.author && c.author.__typename ? c.author.__typename : "",
    is_bot: isBotAuthor(c.author),
  }));
  const last = comments[comments.length - 1] || {};
  const authors = comments.map((c) => c.author).filter(Boolean);
  const botAuthored = comments.some((c) => c.is_bot);
  const humanAuthored = comments.some((c) => !c.is_bot);
  return {
    id: thread.id,
    is_resolved: Boolean(thread.isResolved),
    is_outdated: Boolean(thread.isOutdated),
    path: thread.path || last.path || "",
    comments,
    bot_authored: botAuthored,
    human_authored: humanAuthored,
    last_author: last.author || "",
    last_is_bot: Boolean(last.is_bot),
    authors,
  };
}

function summarizeChecks(rollup) {
  const checks = (rollup || []).map((c) => {
    const row = {
      name: c.name || c.context || "",
      state: c.state || "",
      status: c.status || "",
      bucket: c.bucket || "",
      conclusion: c.conclusion || "",
      link: c.link || c.detailsUrl || c.targetUrl || "",
      workflow: c.workflow || c.workflowName || "",
    };
    row.kind = classifyCheck(row);
    return row;
  });
  const ci = { pass: 0, fail: 0, pending: 0, transient: 0, unknown: 0, ignored: 0 };
  for (const check of checks) ci[check.kind] = (ci[check.kind] || 0) + 1;
  return { checks, ci };
}

function mergeReadyFromParts({
  state,
  mergeable,
  mergeStateStatus,
  isDraft,
  ci,
  requestedChanges,
  unresolvedCount,
  actionableUnresolvedCount,
  reviewDecision,
}) {
  const blockingThreads =
    actionableUnresolvedCount === undefined || actionableUnresolvedCount === null
      ? Number(unresolvedCount || 0)
      : Number(actionableUnresolvedCount);
  return (
    String(state) === "OPEN" &&
    !mergeStateBlocksReady(mergeStateStatus, isDraft === true) &&
    String(mergeable) === "MERGEABLE" &&
    Number(ci.fail || 0) === 0 &&
    Number(ci.pending || 0) === 0 &&
    Number(requestedChanges || 0) === 0 &&
    blockingThreads === 0 &&
    String(reviewDecision || "") !== "CHANGES_REQUESTED"
  );
}

function cmdPrState(flags) {
  const cwd = flags.cwd || process.cwd();
  const info = repoInfo(cwd);
  const lite = asBool(flags.lite, false);
  const number = clampInt(flags.pr || flags.number, 0, 0, 1_000_000_000);
  const selector = number > 0 ? String(number) : flags.branch || "";
  if (!selector) return { ok: false, error: "pass --pr N or --branch NAME" };
  const jsonFields = lite
    ? "number,title,state,url,isDraft,headRefName,headRefOid,baseRefName,reviewDecision,mergeable,mergeStateStatus,latestReviews,statusCheckRollup"
    : "number,title,state,url,isDraft,headRefName,headRefOid,baseRefName,reviewDecision,mergeable,mergeStateStatus,reviews,latestReviews,comments,statusCheckRollup,author";
  const viewed = gh(
    [
      "pr",
      "view",
      selector,
      "--json",
      jsonFields,
    ],
    { cwd, timeoutMs: 180000 },
  );
  if (viewed.status !== 0) {
    return { ok: false, error: viewed.stderr || viewed.stdout || "gh pr view failed" };
  }
  const pr = decodeJson(viewed.stdout, null);
  if (!pr) return { ok: false, error: "could not parse gh pr view JSON" };
  const [owner, name] = String(info.repo || "").split("/");
  const { checks, ci } = summarizeChecks(pr.statusCheckRollup);
  const latest = pr.latestReviews || pr.reviews || [];
  const requestedChanges = latest.filter((r) => r && r.state === "CHANGES_REQUESTED");

  if (lite) {
    const liteThreads = owner && name
      ? fetchUnresolvedCount(cwd, owner, name, pr.number)
      : { ok: false, error: "no repo", unresolved: [], actionable: [], awaiting_human_close: [] };
    if (!liteThreads.ok) {
      const threadError = liteThreads.error || "lite reviewThreads failed";
      return {
        ok: false,
        lite: true,
        error: threadError,
        repo: info.repo,
        pr_number: pr.number,
        head_sha: pr.headRefOid,
        state: pr.state,
        errors: { threads: threadError },
      };
    }
    const unresolved = liteThreads.unresolved || [];
    const actionable = liteThreads.actionable || [];
    const awaitingHumanClose = liteThreads.awaiting_human_close || [];
    const mergeReady = mergeReadyFromParts({
      state: pr.state,
      mergeable: pr.mergeable,
      mergeStateStatus: pr.mergeStateStatus,
      isDraft: pr.isDraft === true,
      ci,
      requestedChanges: requestedChanges.length,
      unresolvedCount: unresolved.length,
      actionableUnresolvedCount: actionable.length,
      reviewDecision: pr.reviewDecision,
    });
    const needsWork = needsWorkFromLite({
      actionableUnresolvedCount: actionable.length,
      unresolvedCount: unresolved.length,
      reviewDecision: pr.reviewDecision,
      mergeable: pr.mergeable,
      ciFail: ci.fail || 0,
    });
    return {
      ok: true,
      lite: true,
      repo: info.repo,
      pr_number: pr.number,
      title: pr.title,
      state: pr.state,
      url: pr.url,
      is_draft: Boolean(pr.isDraft),
      branch: pr.headRefName,
      parent_branch: pr.baseRefName,
      head_sha: pr.headRefOid,
      review_decision: pr.reviewDecision || "",
      mergeable: pr.mergeable || "",
      merge_state_status: pr.mergeStateStatus || "",
      merge_ready: mergeReady,
      needs_work: needsWork,
      requested_changes: requestedChanges.map((r) => ({
        author: r.author && r.author.login ? r.author.login : "",
        state: r.state || "",
      })),
      unresolved_threads: unresolved,
      unresolved_count: unresolved.length,
      actionable_unresolved_threads: actionable,
      actionable_unresolved_count: actionable.length,
      awaiting_human_close_threads: awaitingHumanClose,
      awaiting_human_close_count: awaitingHumanClose.length,
      checks,
      ci,
      errors: { threads: liteThreads.ok ? "" : liteThreads.error },
      fingerprint: fingerprint({
        head: pr.headRefOid,
        review_decision: pr.reviewDecision,
        mergeable: pr.mergeable,
        ci,
        unresolved: actionable.length,
      }),
    };
  }

  const threadsRes = owner && name ? fetchThreads(cwd, owner, name, pr.number) : { ok: false, error: "no repo", threads: [] };
  if (!threadsRes.ok) {
    const threadError = threadsRes.error || "graphql reviewThreads failed";
    return {
      ok: false,
      lite: false,
      error: threadError,
      repo: info.repo,
      pr_number: pr.number,
      head_sha: pr.headRefOid,
      state: pr.state,
      errors: { threads: threadError },
    };
  }
  const issueRes = fetchIssueComments(cwd, pr.number);
  const reviewRes = fetchReviewComments(cwd, pr.number);
  const threads = (threadsRes.threads || []).map(normalizeThread);
  const reviews = (pr.reviews || []).map((r) => ({
    id: r.id,
    author: r.author && r.author.login ? r.author.login : "",
    is_bot: isBotAuthor(r.author),
    state: r.state || "",
    body: r.body || "",
    submitted_at: r.submittedAt || "",
    url: r.url || "",
  }));
  const issueComments = (issueRes.comments || []).map((c) => ({
    id: c.id,
    author: c.user && c.user.login ? c.user.login : "",
    is_bot: isBotAuthor(c.user),
    body: c.body || "",
    created_at: c.created_at || "",
    url: c.html_url || "",
    kind: "issue_comment",
  }));
  const inlineComments = (reviewRes.comments || []).map((c) => ({
    id: c.id,
    author: c.user && c.user.login ? c.user.login : "",
    is_bot: isBotAuthor(c.user),
    body: c.body || "",
    created_at: c.created_at || "",
    path: c.path || "",
    line: c.line || c.original_line || null,
    url: c.html_url || "",
    kind: "review_comment",
    in_reply_to_id: c.in_reply_to_id || null,
  }));
  const parts = partitionUnresolvedThreads(threads);
  const unresolved = parts.unresolved;
  const actionable = parts.actionable;
  const awaitingHumanClose = parts.awaitingHumanClose;
  const unresolvedBot = actionable.filter((t) => t.bot_authored && !t.human_authored);
  const unresolvedHuman = actionable.filter((t) => t.human_authored);
  const fp = fingerprint({
    head: pr.headRefOid,
    review_decision: pr.reviewDecision,
    mergeable: pr.mergeable,
    merge_state_status: pr.mergeStateStatus,
    ci,
    unresolved: actionable.map((t) => t.id),
    issue_count: issueComments.length,
    review_count: reviews.length,
  });
  const mergeReady = mergeReadyFromParts({
    state: pr.state,
    mergeable: pr.mergeable,
    mergeStateStatus: pr.mergeStateStatus,
    isDraft: pr.isDraft === true,
    ci,
    requestedChanges: requestedChanges.length,
    unresolvedCount: unresolved.length,
    actionableUnresolvedCount: actionable.length,
    reviewDecision: pr.reviewDecision,
  });
  const needsWork = needsWorkFromLite({
    actionableUnresolvedCount: actionable.length,
    unresolvedCount: unresolved.length,
    reviewDecision: pr.reviewDecision,
    mergeable: pr.mergeable,
    ciFail: ci.fail || 0,
  });

  return {
    ok: true,
    lite: false,
    repo: info.repo,
    pr_number: pr.number,
    title: pr.title,
    state: pr.state,
    url: pr.url,
    is_draft: Boolean(pr.isDraft),
    branch: pr.headRefName,
    parent_branch: pr.baseRefName,
    head_sha: pr.headRefOid,
    review_decision: pr.reviewDecision || "",
    mergeable: pr.mergeable || "",
    merge_state_status: pr.mergeStateStatus || "",
    merge_ready: mergeReady,
    needs_work: needsWork,
    reviews,
    requested_changes: requestedChanges,
    issue_comments: issueComments,
    review_comments: inlineComments,
    threads,
    unresolved_threads: unresolved,
    unresolved_count: unresolved.length,
    actionable_unresolved_threads: actionable,
    actionable_unresolved_count: actionable.length,
    awaiting_human_close_threads: awaitingHumanClose,
    awaiting_human_close_count: awaitingHumanClose.length,
    unresolved_bot_threads: unresolvedBot,
    unresolved_human_threads: unresolvedHuman,
    checks,
    ci,
    errors: {
      threads: threadsRes.ok ? "" : threadsRes.error,
      issue_comments: issueRes.ok ? "" : issueRes.error,
      review_comments: reviewRes.ok ? "" : reviewRes.error,
    },
    fingerprint: fp,
  };
}

function cmdPoll(flags) {
  const timeoutSeconds = clampInt(flags.timeout_seconds, flags.stable_poll_seconds || 180, 0, 3600);
  const pollSeconds = clampInt(flags.poll_seconds || flags.monitor_poll_seconds, 60, 5, 600);
  const requestedSettle = clampInt(flags.settle_seconds, (flags.settle_window_minutes || 5) * 60, 0, 3600);
  const settleSeconds = Math.min(requestedSettle, timeoutSeconds);
  const expectedHead = flags.head_sha || flags.head || "";
  const dryRun = asBool(flags.dry_run, false);
  const pollFlags = { ...flags, lite: flags.lite !== false };
  const started = nowMs();
  const deadline = started + timeoutSeconds * 1000;
  let baseline = null;
  let stableSince = 0;
  let last = null;
  const maxIters = dryRun || timeoutSeconds === 0 ? 1 : Math.max(1, Math.ceil(timeoutSeconds / pollSeconds) + 2);
  for (let i = 0; i < maxIters; i += 1) {
    last = cmdPrState(pollFlags);
    if (!last.ok) return { ...last, event: "error" };
    if (!baseline) baseline = last;
    if (i === 0) {
      const shortcut = initialPollShortcut(
        pollEvent(last, last, expectedHead),
        last.merge_ready,
        last.needs_work,
      );
      if (shortcut) {
        return {
          ...last,
          event: shortcut,
          waited_ms: shortcut === "stable" ? 0 : nowMs() - started,
        };
      }
    }
    const event = pollEvent(baseline, last, expectedHead);
    if (event === "stable") {
      if (!stableSince) stableSince = nowMs();
      if (nowMs() - stableSince >= settleSeconds * 1000 || settleSeconds === 0 || dryRun) {
        return { ...last, event: "stable", waited_ms: nowMs() - started };
      }
    } else {
      stableSince = 0;
      if (event !== "pending") {
        return { ...last, event, waited_ms: nowMs() - started };
      }
    }
    if (dryRun || timeoutSeconds === 0 || nowMs() >= deadline) break;
    sleepSeconds(pollSeconds);
  }
  return { ...last, event: last && last.ci && last.ci.pending ? "timeout_pending" : "timeout", waited_ms: timeoutSeconds * 1000 };
}

function pollEvent(baseline, current, expectedHead) {
  if (current.state === "MERGED" || current.state === "CLOSED") return "closed";
  if (expectedHead && current.head_sha && current.head_sha !== expectedHead) return "head_changed";
  if (current.ci && current.ci.fail > 0) return "ci_failed";
  if (current.merge_ready) return "stable";
  if (!current.needs_work && current.ci && current.ci.pending === 0) return "stable";
  if (current.ci && current.ci.transient > 0 && current.ci.fail === 0 && current.ci.pending === 0) {
    return "ci_transient";
  }
  const newIssue = (current.issue_comments || []).length > (baseline.issue_comments || []).length;
  const newThreads =
    (current.actionable_unresolved_count ?? (current.actionable_unresolved_threads || []).length) >
    (baseline.actionable_unresolved_count ?? (baseline.actionable_unresolved_threads || []).length);
  const fpChanged = current.fingerprint !== baseline.fingerprint && newIssue;
  if (newIssue || newThreads || fpChanged) {
    if (newIssue || newThreads) return "new_comments";
  }
  if (current.ci && current.ci.pending > 0) return "pending";
  if (current.merge_ready) return "stable";
  if (current.ci && current.ci.fail === 0 && current.ci.pending === 0) return "stable";
  return "pending";
}

function cmdCheckpointGet(flags) {
  const cwd = flags.cwd || process.cwd();
  const info = repoInfo(cwd);
  const startBranch = flags.start_branch || info.current_branch;
  const ck = loadCheckpoint(info.repo, startBranch);
  return { ok: true, path: ck.path, checkpoint: ck.data };
}

function cmdCheckpointPut(flags) {
  const cwd = flags.cwd || process.cwd();
  const info = repoInfo(cwd);
  const startBranch = flags.start_branch || info.current_branch;
  const incoming = flags.stdin_json
    ? decodeJson(fs.readFileSync(0, "utf8"), {})
    : decodeJson(flags.json || "{}", {});
  const ck = loadCheckpoint(info.repo, startBranch);
  const merged = { ...(ck.data || {}), ...incoming, repo: info.repo, start_branch: startBranch, updated_at_ms: nowMs() };
  const saved = saveCheckpoint(info.repo, startBranch, merged);
  return { ok: true, path: saved, checkpoint: merged };
}

function cmdReply(flags) {
  if (asBool(flags.dry_run, false)) {
    return { ok: true, dry_run: true, skipped: true, action: "reply" };
  }
  const cwd = flags.cwd || process.cwd();
  const number = clampInt(flags.pr, 0, 1, 1_000_000_000);
  const commentId = flags.comment_id || flags.database_id;
  const body = flags.body || "";
  if (!number || !commentId || !body) {
    return { ok: false, error: "reply requires --pr, --comment-id, and --body" };
  }
  const result = gh(
    ["api", `repos/{owner}/{repo}/pulls/${number}/comments/${commentId}/replies`, "-X", "POST", "-f", `body=${body}`],
    { cwd },
  );
  if (result.status !== 0) return { ok: false, error: result.stderr || result.stdout || "reply failed" };
  return { ok: true, action: "reply", result: decodeJson(result.stdout, { raw: result.stdout }) };
}

function cmdResolveThread(flags) {
  if (asBool(flags.dry_run, false)) {
    return { ok: true, dry_run: true, skipped: true, action: "resolve-thread" };
  }
  const cwd = flags.cwd || process.cwd();
  const threadId = flags.thread_id || flags.id;
  if (!threadId) return { ok: false, error: "resolve-thread requires --thread-id" };
  const result = graphql(cwd, RESOLVE_MUTATION, { id: threadId });
  if (result.status !== 0) return { ok: false, error: result.stderr || result.stdout || "resolve failed" };
  return { ok: true, action: "resolve-thread", result: decodeJson(result.stdout, { raw: result.stdout }) };
}

function cmdRerunRun(flags) {
  if (asBool(flags.dry_run, false)) {
    return { ok: true, dry_run: true, skipped: true, action: "rerun-run" };
  }
  const cwd = flags.cwd || process.cwd();
  const runId = flags.run_id || flags.id;
  if (!runId) return { ok: false, error: "rerun-run requires --run-id" };
  const args = ["run", "rerun", String(runId)];
  if (asBool(flags.failed, true)) args.push("--failed");
  const result = gh(args, { cwd });
  if (result.status !== 0) return { ok: false, error: result.stderr || result.stdout || "gh run rerun failed" };
  return { ok: true, action: "rerun-run", run_id: runId };
}

function lockOwner(flags) {
  const raw = flags && flags.owner;
  if (raw !== undefined && raw !== null && raw !== true && raw !== false) return String(raw);
  return process.env.GRAPHITE_STACK_REVIEW_OWNER || "";
}

function cmdLockAcquire(flags) {
  const cwd = flags.cwd || process.cwd();
  const info = repoInfo(cwd);
  const filePath = lockPath(info.repo);
  const owner = lockOwner(flags);
  const lock = acquireLock(filePath, undefined, owner);
  return { ...lock, path: filePath, repo: info.repo, owner };
}

function cmdLockRelease(flags) {
  const cwd = flags.cwd || process.cwd();
  const info = repoInfo(cwd);
  const filePath = lockPath(info.repo);
  const owner = lockOwner(flags);
  const force = asBool(flags.force, false);
  return { ok: releaseLock(filePath, owner, force), path: filePath, repo: info.repo, owner, force };
}

function cmdRestore(flags) {
  const cwd = flags.cwd || process.cwd();
  const info = repoInfo(cwd);
  const startBranch = flags.start_branch || info.current_branch;
  const ck = loadCheckpoint(info.repo, startBranch);
  const saved = readJsonFile(path.join(stateDir(info.repo), "original.json"), {});
  const branch =
    flags.branch ||
    saved.branch ||
    (ck.data && ck.data.original_branch) ||
    "";
  if (!branch) return { ok: false, error: "no original branch recorded; pass --branch" };
  if (asBool(flags.dry_run, false)) {
    return { ok: true, dry_run: true, skipped: true, action: "restore", branch, current_branch: info.current_branch };
  }
  if (info.current_branch === branch) {
    return { ok: true, action: "restore", skipped: true, branch, current_branch: info.current_branch };
  }
  const result = checkoutNamedBranch(cwd, branch, { fromPr: clampInt(flags.pr, 0, 0, 1_000_000_000) });
  const now = currentBranch(cwd);
  if (!result.ok || now !== branch) {
    return {
      ok: false,
      action: "restore",
      branch,
      current_branch: now,
      error: result.error || "checkout did not land on original branch",
    };
  }
  return { ok: true, action: "restore", method: result.method, branch, current_branch: now };
}

function cmdCheckout(flags) {
  const cwd = flags.cwd || process.cwd();
  const branch = String(flags.branch || flags.start_branch || "").trim();
  const fromPr = clampInt(flags.pr || flags.from_pr, 0, 0, 1_000_000_000);
  if (!branch) return { ok: false, error: "need --branch", action: "checkout" };
  if (asBool(flags.dry_run, false)) {
    return { ok: true, dry_run: true, skipped: true, action: "checkout", branch };
  }
  const result = checkoutNamedBranch(cwd, branch, { fromPr });
  return { action: "checkout", ...result };
}

function cmdReviewDiff(flags) {
  const cwd = flags.cwd || process.cwd();
  const parent = String(flags.parent || flags.parent_branch || "").trim();
  const branch = String(flags.branch || "").trim();
  if (!parent || !branch) {
    return { ok: false, error: "need --parent and --branch", inspected: false, findings: [] };
  }
  const range = `${parent}...${branch}`;
  const stat = git(["diff", "--stat", range], { cwd });
  const names = git(["diff", "--name-only", range], { cwd });
  const diff = git(["diff", range], { cwd });
  if (stat.status !== 0 || names.status !== 0 || diff.status !== 0) {
    const err = (stat.stderr || names.stderr || diff.stderr || stat.stdout || names.stdout || diff.stdout || "git diff failed").trim();
    return {
      ok: false,
      error: err.slice(0, 2000),
      inspected: false,
      branch,
      parent_branch: parent,
      files: [],
      file_count: 0,
      stat: "",
      diff: "",
      truncated: false,
      findings: [],
    };
  }
  const files = names.stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .slice(0, 40);
  const maxChars = 60000;
  let diffText = diff.stdout || "";
  const truncated = diffText.length > maxChars;
  if (truncated) diffText = diffText.slice(0, maxChars);
  return {
    ok: true,
    error: "",
    inspected: true,
    branch,
    parent_branch: parent,
    files,
    file_count: files.length,
    stat: (stat.stdout || "").trim().slice(0, 8000),
    diff: diffText,
    truncated,
    findings: [],
  };
}

function cmdSmoke(flags) {
  const cwd = flags.cwd || process.cwd();
  const missing = requireBins();
  const sampleLog = [
    "◯  main",
    "◉  feat/one (needs restack)",
    "◯  feat/two",
  ].join("\n");
  const parsed = parseGtLogShort(sampleLog);
  const state = {
    main: { trunk: true, parents: [] },
    "feat/one": { trunk: false, parents: [{ ref: "main", sha: "aaa" }] },
    "feat/two": { trunk: false, parents: [{ ref: "feat/one", sha: "bbb" }] },
  };
  const walked = walkStackFromState(state, "feat/two", "main");
  const discover = cmdDiscover({ ...flags, dry_run: true, lock: false, max_prs: flags.max_prs || 3, resume: false });
  return {
    ok:
      missing.length === 0 &&
      parsed.includes("feat/one") &&
      walked[0] === "feat/one" &&
      porcelainIsDirty("?? plans/handoff/note.md\n") === false &&
      porcelainIsDirty("?? plans/fix-note.md\n") === false &&
      porcelainIsDirty(" M backend/src/foo.ts\n") === true &&
      threadHasReply({ comments: { totalCount: 2 } }) === true &&
      needsWorkFromLite({
        unresolvedCount: 3,
        actionableUnresolvedCount: 0,
        reviewDecision: "",
        mergeable: "MERGEABLE",
        ciFail: 0,
      }) === false,
    missing_binaries: missing,
    parse_gt_log_short: parsed,
    walk_stack_from_state: walked,
    is_bot_graphite: isBotAuthor({ login: "graphite-app[bot]", __typename: "Bot" }),
    is_bot_human: isBotAuthor({ login: "octocat", __typename: "User" }),
    porcelain_ignores_handoff: porcelainIsDirty("?? plans/handoff/note.md\n") === false,
    porcelain_ignores_plans: porcelainIsDirty("?? plans/fix-note.md\n") === false,
    porcelain_flags_tracked: porcelainIsDirty(" M backend/src/foo.ts\n") === true,
    thread_has_reply: threadHasReply({ comments: { totalCount: 2 } }) === true,
    thread_no_reply: threadHasReply({ comments: { totalCount: 1 } }) === false,
    needs_work_ignores_replied_threads:
      needsWorkFromLite({
        unresolvedCount: 3,
        actionableUnresolvedCount: 0,
        reviewDecision: "",
        mergeable: "MERGEABLE",
        ciFail: 0,
      }) === false,
    support_dir: SUPPORT_DIR,
    repo_key: repoKey(discover.repo || "owner/name"),
    discover_ok: Boolean(discover.ok),
    discover_prs: (discover.prs || []).length,
    discover_method: discover.method || "",
    discover_error: discover.error || "",
    dry_run: true,
    mutated: false,
  };
}

const COMMANDS = {
  discover: cmdDiscover,
  "pr-state": cmdPrState,
  poll: cmdPoll,
  "checkpoint-get": cmdCheckpointGet,
  "checkpoint-put": cmdCheckpointPut,
  reply: cmdReply,
  "resolve-thread": cmdResolveThread,
  "rerun-run": cmdRerunRun,
  "lock-acquire": cmdLockAcquire,
  "lock-release": cmdLockRelease,
  restore: cmdRestore,
  checkout: cmdCheckout,
  "review-diff": cmdReviewDiff,
  smoke: cmdSmoke,
  help: () => ({ ok: true, usage: usage() }),
};

const argv = process.argv.slice(2);
const command = argv[0] || "help";
const flags = parseFlags(argv.slice(1));
const impl = COMMANDS[command];
if (!impl) {
  die(`unknown command: ${command}`, { usage: usage() });
}
try {
  const result = impl(flags);
  printJson(result);
  if (result && result.ok === false) process.exit(1);
} catch (err) {
  die(err && err.stack ? err.stack : err);
}
