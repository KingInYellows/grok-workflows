#!/usr/bin/env node
/**
 * Shared helpers for graphite-stack-review support scripts.
 * Node.js built-ins only. No package.json / npm deps.
 */

import { spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const SUPPORT_DIR =
  process.env.GRAPHITE_STACK_REVIEW_HOME ||
  path.join(os.homedir(), ".grok", "workflow-support", "graphite-stack-review");

export const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));

export function nowMs() {
  return Date.now();
}

export function parseFlags(argv) {
  const flags = { _: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === "--") {
      flags._.push(...argv.slice(i + 1));
      break;
    }
    if (tok.startsWith("--no-") && tok.length > 5) {
      flags[toKey(tok.slice(5))] = false;
      continue;
    }
    if (tok.startsWith("--") && tok.length > 2) {
      const eq = tok.indexOf("=");
      if (eq !== -1) {
        flags[toKey(tok.slice(2, eq))] = coerce(tok.slice(eq + 1));
        continue;
      }
      const key = toKey(tok.slice(2));
      const next = argv[i + 1];
      if (next === undefined || next.startsWith("--")) {
        flags[key] = true;
      } else {
        flags[key] = coerce(next);
        i += 1;
      }
      continue;
    }
    flags._.push(tok);
  }
  return flags;
}

function toKey(name) {
  return name.replace(/-/g, "_");
}

function coerce(value) {
  if (value === "true") return true;
  if (value === "false") return false;
  if (value === "null") return null;
  if (/^-?\d+$/.test(value)) return Number(value);
  return value;
}

export function run(command, args, opts = {}) {
  const env = { ...process.env, NO_COLOR: "1", ...(opts.env || {}) };
  const result = spawnSync(command, args, {
    encoding: "utf8",
    cwd: opts.cwd,
    env,
    timeout: opts.timeoutMs ?? 120000,
    maxBuffer: opts.maxBuffer ?? 20 * 1024 * 1024,
  });
  return {
    status: result.status === null ? 1 : result.status,
    stdout: stripAnsi(result.stdout || ""),
    stderr: stripAnsi(result.stderr || ""),
    error: result.error ? String(result.error.message || result.error) : "",
    signal: result.signal || "",
  };
}

export function stripAnsi(text) {
  return String(text || "").replace(/\x1b\[[0-9;]*[A-Za-z]/g, "");
}

export function which(bin) {
  const result = run("bash", ["-lc", `command -v ${shellQuote(bin)} || true`]);
  const loc = result.stdout.trim();
  return loc || "";
}

export function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

export function gt(args, opts = {}) {
  const prefixed = ["--no-interactive", ...args];
  return run("gt", prefixed, opts);
}

export function gh(args, opts = {}) {
  return run("gh", args, { ...opts, env: { ...process.env, NO_COLOR: "1", ...(opts.env || {}) } });
}

export function git(args, opts = {}) {
  return run("git", args, opts);
}

export function decodeJson(text, fallback = null) {
  const raw = String(text || "").trim();
  if (!raw) return fallback;
  try {
    return JSON.parse(raw);
  } catch (err) {
    console.error(`decodeJson: ${err && err.message ? err.message : "invalid JSON"}`);
    return fallback;
  }
}

export function reviewThreadPage(payload) {
  let value = payload;
  if (typeof value === "string" || value == null) {
    const raw = String(value || "").trim();
    if (!raw) {
      return { ok: false, error: "could not parse reviewThreads", nodes: [], pageInfo: null };
    }
    try {
      value = JSON.parse(raw);
    } catch (err) {
      console.error(`reviewThreadPage: ${err && err.message ? err.message : "invalid JSON"}`);
      return { ok: false, error: "could not parse reviewThreads", nodes: [], pageInfo: null };
    }
  }
  if (typeof value !== "object" || Array.isArray(value)) {
    return { ok: false, error: "could not parse reviewThreads", nodes: [], pageInfo: null };
  }
  const conn =
    value.data &&
    value.data.repository &&
    value.data.repository.pullRequest &&
    value.data.repository.pullRequest.reviewThreads;
  if (!conn || typeof conn !== "object" || Array.isArray(conn)) {
    const errors = Array.isArray(value.errors) ? value.errors : [];
    const message = errors
      .map((entry) => (entry && entry.message ? String(entry.message) : ""))
      .filter(Boolean)
      .join("; ");
    return {
      ok: false,
      error: message || "could not parse reviewThreads",
      nodes: [],
      pageInfo: null,
    };
  }
  return {
    ok: true,
    error: "",
    nodes: Array.isArray(conn.nodes) ? conn.nodes : [],
    pageInfo: conn.pageInfo && typeof conn.pageInfo === "object" ? conn.pageInfo : null,
  };
}

export function printJson(value) {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

export function failJson(error, extra = {}) {
  printJson({ ok: false, error: String(error), ...extra });
}

export function parseGtLogShort(text) {
  const branches = [];
  const seen = new Set();
  for (const line of String(text || "").split(/\r?\n/)) {
    if (!line.trim()) continue;
    const stripped = line.replace(/^[^\w./@~+-]+/, "").trim();
    if (!stripped) continue;
    const name = stripped.replace(/\s+\([^)]*\)\s*$/, "").trim();
    if (!name || name === "..." || seen.has(name)) continue;
    if (/\s/.test(name)) continue;
    seen.add(name);
    branches.push(name);
  }
  return branches;
}

export function isBotAuthor(author) {
  if (!author) return false;
  if (typeof author === "string") {
    const login = author.toLowerCase();
    return login.endsWith("[bot]") || login.includes("[bot]") || login.endsWith("-bot");
  }
  const login = String(author.login || author.name || author.slug || "").toLowerCase();
  const typename = String(author.__typename || author.type || "");
  if (typename === "Bot" || author.type === "Bot") return true;
  if (author.is_bot === true) return true;
  if (login.endsWith("[bot]") || login.includes("[bot]")) return true;
  if (login.endsWith("-bot")) return true;
  return false;
}

export function walkStackFromState(state, startBranch, trunk) {
  if (!state || typeof state !== "object" || !startBranch) return [];
  const children = new Map();
  for (const [name, info] of Object.entries(state)) {
    const parents = (info && info.parents) || [];
    for (const parent of parents) {
      const ref = parent && parent.ref;
      if (!ref) continue;
      if (!children.has(ref)) children.set(ref, []);
      children.get(ref).push(name);
    }
  }
  const down = [];
  const seenDown = new Set();
  let cur = startBranch;
  while (cur && cur !== trunk && !seenDown.has(cur)) {
    seenDown.add(cur);
    down.push(cur);
    const info = state[cur];
    const parent = info && info.parents && info.parents[0] && info.parents[0].ref;
    if (!parent || parent === trunk) break;
    cur = parent;
  }
  down.reverse();
  const up = [];
  const seenUp = new Set([startBranch]);
  const queue = [...(children.get(startBranch) || [])];
  while (queue.length) {
    const branch = queue.shift();
    if (!branch || seenUp.has(branch) || branch === trunk) continue;
    seenUp.add(branch);
    up.push(branch);
    for (const child of children.get(branch) || []) queue.push(child);
  }
  const ordered = [];
  const seen = new Set();
  for (const branch of [...down, ...up]) {
    if (seen.has(branch) || branch === trunk) continue;
    seen.add(branch);
    ordered.push(branch);
  }
  return ordered;
}

export function repoKey(nameWithOwner) {
  return crypto.createHash("sha256").update(String(nameWithOwner || "unknown")).digest("hex").slice(0, 16);
}

export function stackKey(repo, startBranch) {
  return crypto
    .createHash("sha256")
    .update(`${repo || "unknown"}::${startBranch || "current"}`)
    .digest("hex")
    .slice(0, 16);
}

export function stateDir(repo) {
  return path.join(SUPPORT_DIR, "state", repoKey(repo));
}

export function checkpointPath(repo, startBranch) {
  return path.join(stateDir(repo), `${stackKey(repo, startBranch)}.json`);
}

export function lockPath(repo) {
  return path.join(SUPPORT_DIR, "locks", `${repoKey(repo)}.lock`);
}

export function readJsonFile(filePath, fallback = null) {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return fallback;
  }
}

export function writeJsonFile(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const tmp = `${filePath}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, `${JSON.stringify(value, null, 2)}\n`);
  fs.renameSync(tmp, filePath);
}

export function acquireLock(filePath, staleMs = 6 * 60 * 60 * 1000) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const payload = {
    pid: process.pid,
    started_at_ms: nowMs(),
    host: os.hostname(),
  };
  try {
    const fd = fs.openSync(filePath, "wx");
    fs.writeFileSync(fd, `${JSON.stringify(payload)}\n`);
    fs.closeSync(fd);
    return { ok: true, stale: false };
  } catch (err) {
    if (!err || err.code !== "EEXIST") {
      return { ok: false, error: String(err && err.message ? err.message : err) };
    }
    const existing = readJsonFile(filePath, {});
    const age = nowMs() - Number(existing.started_at_ms || 0);
    const pid = Number(existing.pid || 0);
    const alive = pid > 0 && isPidAlive(pid);
    if (!alive || age > staleMs) {
      try {
        fs.unlinkSync(filePath);
      } catch {
        // ignore
      }
      return acquireLock(filePath, staleMs);
    }
    return {
      ok: false,
      locked: true,
      error: `lock held by pid ${pid}`,
      pid,
      age_ms: age,
    };
  }
}

export function releaseLock(filePath) {
  try {
    const existing = readJsonFile(filePath, {});
    if (existing.pid && Number(existing.pid) !== process.pid) return false;
    fs.unlinkSync(filePath);
    return true;
  } catch {
    return false;
  }
}

function isPidAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

export function fingerprint(value) {
  const text = typeof value === "string" ? value : JSON.stringify(value);
  return crypto.createHash("sha256").update(text).digest("hex");
}

export function prNumberInRange(prNumber, fromPr, toPr) {
  const n = Number(prNumber);
  if (!Number.isFinite(n) || n <= 0) return true;
  if (fromPr > 0 && n < fromPr) return false;
  if (toPr > 0 && n > toPr) return false;
  return true;
}

export function clampInt(value, fallback, lo, hi) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  if (n < lo) return lo;
  if (n > hi) return hi;
  return Math.trunc(n);
}

export function asBool(value, fallback) {
  if (value === undefined || value === null) return fallback;
  if (typeof value === "boolean") return value;
  if (value === "true" || value === 1 || value === "1") return true;
  if (value === "false" || value === 0 || value === "0") return false;
  return fallback;
}

export const IGNORABLE_DIRTY_PREFIXES = ["plans/", ".grok/"];

export function isIgnorableDirtyPath(filePath) {
  const p = String(filePath || "")
    .replace(/\\/g, "/")
    .replace(/^\.\//, "")
    .replace(/\/+$/, "");
  if (p === "plans" || p === ".grok") return true;
  for (const prefix of IGNORABLE_DIRTY_PREFIXES) {
    const dir = prefix.replace(/\/+$/, "");
    if (p === dir || p.startsWith(`${dir}/`)) return true;
  }
  return false;
}

export function isPrSlashRef(name) {
  return /^pr\/\d+$/i.test(String(name || "").trim());
}

function porcelainPath(line) {
  const rest = line.length > 3 ? line.slice(3) : "";
  const arrow = rest.indexOf(" -> ");
  return arrow !== -1 ? rest.slice(arrow + 4) : rest;
}

export function nonIgnorablePorcelainPaths(text) {
  const paths = [];
  const seen = new Set();
  for (const line of String(text || "").split(/\r?\n/)) {
    if (!line.trim()) continue;
    const xy = line.slice(0, 2);
    const filePath = porcelainPath(line);
    if (!filePath) continue;
    if (xy === "??" && isIgnorableDirtyPath(filePath)) continue;
    if (seen.has(filePath)) continue;
    seen.add(filePath);
    paths.push(filePath);
  }
  return paths;
}

export function restoreLeftoverCheckoutPaths(cwd, beforePorcelain, afterPorcelain) {
  const before = new Set(nonIgnorablePorcelainPaths(beforePorcelain));
  const extra = nonIgnorablePorcelainPaths(afterPorcelain).filter((p) => !before.has(p));
  if (!extra.length) return { restored: [], skipped: true };
  const result = git(["restore", "--staged", "--worktree", "--", ...extra], { cwd });
  return {
    restored: extra,
    skipped: false,
    ok: result.status === 0,
    error: result.status === 0 ? "" : (result.stderr || result.stdout || "git restore failed").trim(),
  };
}

export function checkoutNamedBranch(cwd, branch, opts = {}) {
  const name = String(branch || "").trim();
  const fromPr = Number(opts.fromPr || 0);
  if (!name) return { ok: false, error: "empty branch", branch: name };
  if (isPrSlashRef(name)) {
    return { ok: false, error: "refusing to checkout pr/<N> remote ref", branch: name };
  }
  const beforeBranch = currentBranch(cwd);
  if (beforeBranch === name) {
    return { ok: true, method: "already", branch: name, current_branch: beforeBranch };
  }
  const beforePorcelain = git(["status", "--porcelain"], { cwd }).stdout;
  git(["fetch", "origin", name], { cwd, timeoutMs: 180000 });
  let co = git(["checkout", name], { cwd });
  if (currentBranch(cwd) !== name) {
    co = git(["checkout", "-B", name, `origin/${name}`], { cwd });
  }
  if (currentBranch(cwd) === name) {
    return { ok: true, method: "git-fetch-checkout", branch: name, current_branch: name };
  }
  const afterPorcelain = git(["status", "--porcelain"], { cwd }).stdout;
  const leftover = restoreLeftoverCheckoutPaths(cwd, beforePorcelain, afterPorcelain);
  if (fromPr > 0) {
    const ghCo = gh(["pr", "checkout", String(fromPr)], { cwd, timeoutMs: 180000 });
    if (currentBranch(cwd) === name) {
      return {
        ok: true,
        method: "gh-pr-checkout",
        branch: name,
        current_branch: name,
        leftover_restored: leftover.restored,
      };
    }
    return {
      ok: false,
      error: (ghCo.stderr || ghCo.stdout || co.stderr || co.stdout || "checkout failed").trim(),
      branch: name,
      current_branch: currentBranch(cwd),
      leftover_restored: leftover.restored,
    };
  }
  return {
    ok: false,
    error: (co.stderr || co.stdout || "git checkout failed").trim(),
    branch: name,
    current_branch: currentBranch(cwd),
    leftover_restored: leftover.restored,
  };
}

export function summarizePorcelain(text, sampleLimit = 8) {
  const counts = { modified: 0, deleted: 0, added: 0, untracked: 0, other: 0 };
  const samples = [];
  let total = 0;
  for (const line of String(text || "").split(/\r?\n/)) {
    if (!line.trim()) continue;
    const xy = line.slice(0, 2);
    const filePath = porcelainPath(line);
    if (xy === "??" && isIgnorableDirtyPath(filePath)) continue;
    total += 1;
    if (xy.includes("D")) counts.deleted += 1;
    else if (xy === "??") counts.untracked += 1;
    else if (xy.includes("A")) counts.added += 1;
    else if (xy.includes("M")) counts.modified += 1;
    else counts.other += 1;
    if (samples.length < sampleLimit) samples.push(filePath || line.trim());
  }
  const parts = [];
  if (counts.deleted) parts.push(`${counts.deleted} deleted`);
  if (counts.modified) parts.push(`${counts.modified} modified`);
  if (counts.added) parts.push(`${counts.added} added`);
  if (counts.untracked) parts.push(`${counts.untracked} untracked`);
  if (counts.other) parts.push(`${counts.other} other`);
  return {
    counts,
    samples,
    total,
    summary: total === 0 ? "" : parts.join(", "),
  };
}

export function porcelainIsDirty(text) {
  return summarizePorcelain(text).total > 0;
}

export function pickStartBranch({ explicitStart, currentBranch, fromPrHead }) {
  if (explicitStart) return { branch: String(explicitStart), resolved_from_pr: false };
  if (fromPrHead) return { branch: String(fromPrHead), resolved_from_pr: true };
  return { branch: String(currentBranch || ""), resolved_from_pr: false };
}

export function gitRoot(cwd) {
  const result = git(["rev-parse", "--show-toplevel"], { cwd });
  if (result.status !== 0) return "";
  return result.stdout.trim();
}

export function currentBranch(cwd) {
  const result = git(["branch", "--show-current"], { cwd });
  return result.stdout.trim();
}

export function remoteOriginUrl(cwd) {
  const result = git(["remote", "get-url", "origin"], { cwd });
  return result.status === 0 ? result.stdout.trim() : "";
}

export function parseOwnerRepo(remoteUrl) {
  const raw = String(remoteUrl || "").trim();
  const ssh = raw.match(/git@[^:]+:([^/]+)\/(.+?)(?:\.git)?$/);
  if (ssh) return `${ssh[1]}/${ssh[2]}`;
  try {
    const url = new URL(raw);
    const parts = url.pathname.replace(/^\//, "").replace(/\.git$/, "").split("/");
    if (parts.length >= 2) return `${parts[0]}/${parts[1]}`;
  } catch {
    // ignore
  }
  const gh = raw.match(/github\.com[/:]([^/]+)\/([^/.]+)/);
  if (gh) return `${gh[1]}/${gh[2]}`;
  return "";
}

export function isIgnorableCheck(check) {
  const name = String((check && (check.name || check.workflow || check.context)) || "").toLowerCase();
  if (!name) return false;
  if (name.includes("mergeability")) return true;
  if (name.includes("graphite") && (name.includes("merge") || name.includes("check") || name.includes("stack"))) {
    return true;
  }
  return false;
}

export function classifyCheck(check) {
  if (isIgnorableCheck(check)) return "ignored";
  const bucket = String(check.bucket || "").toLowerCase();
  const state = String(check.state || check.conclusion || "").toLowerCase();
  if (bucket === "fail" || ["failure", "error", "failed"].includes(state)) return "fail";
  if (bucket === "pending" || ["pending", "queued", "in_progress", "expected"].includes(state)) {
    return "pending";
  }
  if (bucket === "cancel" || ["cancelled", "canceled", "timed_out", "startup_failure", "stale"].includes(state)) {
    return "transient";
  }
  if (bucket === "pass" || ["success", "neutral", "skipped"].includes(state)) return "pass";
  if (bucket === "skipping") return "pass";
  return "unknown";
}

export function threadHasReply(thread) {
  const comments = thread && thread.comments;
  if (comments && typeof comments.totalCount === "number") {
    return comments.totalCount > 1;
  }
  const nodes = (comments && comments.nodes) || comments || thread && thread.comment_count;
  if (typeof thread?.comment_count === "number") return thread.comment_count > 1;
  if (typeof thread?.has_reply === "boolean") return thread.has_reply;
  return Array.isArray(nodes) && nodes.length > 1;
}

export function partitionUnresolvedThreads(threads) {
  const unresolved = [];
  const actionable = [];
  const awaitingHumanClose = [];
  for (const thread of threads || []) {
    if (!thread) continue;
    const resolved = thread.isResolved === true || thread.is_resolved === true;
    if (resolved) continue;
    unresolved.push(thread);
    if (threadHasReply(thread)) awaitingHumanClose.push(thread);
    else actionable.push(thread);
  }
  return { unresolved, actionable, awaitingHumanClose };
}

export function wallClockFromCheckpoint(existing, now, maxWallMinutes) {
  const maxMs = Math.max(1, Number(maxWallMinutes) || 720) * 60 * 1000;
  const nowMsValue = Number(now) || 0;
  if (existing && existing.started_at_ms) {
    const started = Number(existing.started_at_ms);
    const oldDeadline = Number(existing.deadline_ms) || started + maxMs;
    if (nowMsValue <= oldDeadline) {
      return { startedAt: started, deadlineMs: started + maxMs, refreshed: false };
    }
  }
  return { startedAt: nowMsValue, deadlineMs: nowMsValue + maxMs, refreshed: true };
}

export function needsWorkFromLite({
  actionableUnresolvedCount,
  unresolvedCount,
  reviewDecision,
  mergeable,
  ciFail,
}) {
  const actionable =
    actionableUnresolvedCount === undefined || actionableUnresolvedCount === null
      ? Number(unresolvedCount || 0)
      : Number(actionableUnresolvedCount);
  if (actionable > 0) return true;
  if (String(reviewDecision || "") === "CHANGES_REQUESTED") return true;
  if (String(mergeable || "") === "CONFLICTING") return true;
  if (Number(ciFail) > 0) return true;
  return false;
}

export function sleepSeconds(seconds) {
  const ms = Math.max(0, Number(seconds) || 0) * 1000;
  if (ms <= 0) return;
  const result = spawnSync("sleep", [String(seconds)], { encoding: "utf8" });
  if (result.error) {
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
  }
}
