let meta = #{
    name: "preflight-gate",
    description: "Read-only pre-commit gate: review the diff, audit tests from AGENTS.md, scan for secrets, then SHIP or BLOCK",
    when_to_use: "Before committing. Read-only SHIP or BLOCK on the working diff: correctness, AGENTS.md tests, secrets.",
    phases: [
        #{ title: "Inspect", detail: "load the diff vs the baseline ref" },
        #{ title: "Scan", detail: "diff review, AGENTS.md tests, secrets in parallel" },
        #{ title: "Verify", detail: "adversarial check of each blocker" },
        #{ title: "Decide", detail: "SHIP or BLOCK report" },
    ],
};

const MAX_FINDINGS = 8;
const MAX_VERIFY = 12;
const MAX_DIFF_CHARS = 8000;

let findings_schema = #{
    "type": "object",
    "required": ["findings", "summary"],
    "properties": #{
        "findings": #{
            "type": "array",
            "maxItems": 8,
            "items": #{
                "type": "object",
                "required": ["file", "issue", "evidence", "severity"],
                "properties": #{
                    "file": #{ "type": "string" },
                    "issue": #{ "type": "string" },
                    "evidence": #{ "type": "string" },
                    "severity": #{ "type": "string" },
                },
            },
        },
        "summary": #{ "type": "string" },
    },
};

let verdict_schema = #{
    "type": "object",
    "required": ["real", "reason", "evidence"],
    "properties": #{
        "real": #{ "type": "boolean" },
        "reason": #{ "type": "string" },
        "evidence": #{ "type": "string" },
    },
};

fn trimmed(s) {
    if type_of(s) == "string" {
        s.trim();
        s
    } else {
        ""
    }
}

fn as_array(x) {
    if type_of(x) == "array" { return x; }
    []
}

fn non_empty(s) {
    trimmed(s) != ""
}

fn path_under(s, prefix) {
    let path = trimmed(s);
    let rootp = trimmed(prefix);
    if rootp == "." || rootp == "" { return true; }
    if path == rootp { return true; }
    let slash = rootp + "/";
    let back = rootp + "\\";
    if path.len() >= slash.len() && path.sub_string(0, slash.len()) == slash { return true; }
    if path.len() >= back.len() && path.sub_string(0, back.len()) == back { return true; }
    false
}

fn take_n(arr, n) {
    let out = [];
    let i = 0;
    for x in arr {
        if i >= n { break; }
        out.push(x);
        i += 1;
    }
    out
}

fn finding_usable(it) {
    it != () && non_empty(it.file) && non_empty(it.issue) && non_empty(it.evidence)
}

fn is_block_severity(it) {
    let s = trimmed(it.severity);
    s == "block" || s == ""
}

fn filter_root_findings(arr, root) {
    let out = [];
    let dropped = 0;
    for it in as_array(arr) {
        if it != () && path_under(it.file, root) {
            out.push(it);
        } else {
            dropped += 1;
        }
    }
    if dropped > 0 {
        log("Dropped " + dropped.to_string() + " out-of-root findings (root=" + root + ")");
    }
    out
}

fn keep_usable_findings(arr) {
    let out = [];
    let dropped = 0;
    for it in as_array(arr) {
        if finding_usable(it) {
            out.push(it);
        } else {
            dropped += 1;
        }
    }
    if dropped > 0 {
        log("Dropped " + dropped.to_string() + " unusable findings");
    }
    out
}

fn lane_from(r) {
    if r == () {
        return #{ ok: false, findings: [], summary: "lane returned no result" };
    }
    if r.success != true {
        return #{ ok: false, findings: [], summary: "lane agent failed" };
    }
    if r.output == () {
        return #{ ok: false, findings: [], summary: "lane output missing" };
    }
    if r.output.findings == () {
        return #{ ok: false, findings: [], summary: "lane findings missing" };
    }
    let sum = "";
    if r.output.summary != () {
        sum = trimmed(r.output.summary);
    }
    #{ ok: true, findings: as_array(r.output.findings), summary: sum }
}

fn excerpt(text, max_chars) {
    if type_of(text) != "string" { return ""; }
    if text.len() <= max_chars { return text; }
    text.sub_string(0, max_chars)
}

let since_ref = "HEAD";
let root = ".";
if args != () {
    if args.since != () {
        let s = trimmed(args.since);
        if s != "" { since_ref = s; }
    }
    if args.root != () {
        let r = trimmed(args.root);
        if r != "" { root = r; }
    }
}

phase("Inspect");
log("Preflight vs " + since_ref + " (root=" + root + ")");

let diff = "";
try {
    let raw = git_diff_since(since_ref);
    if type_of(raw) == "string" {
        diff = raw;
    }
} catch (e) {
    log("Host git_diff_since failed; scanners will inspect git themselves");
}

let diff_was_truncated = false;
if diff.len() > MAX_DIFF_CHARS {
    log("Truncated host diff from " + diff.len().to_string() + " to " + MAX_DIFF_CHARS.to_string() + " chars");
    diff = excerpt(diff, MAX_DIFF_CHARS);
    diff_was_truncated = true;
}

let encoded_diff = json_encode(diff);
let encoded_since = json_encode(since_ref);
let encoded_root = json_encode(root);

let root_note = "";
if root != "." {
    root_note = " Scope every path to this root: " + root + ". Ignore sibling trees outside it.";
}

let shared_preamble = "";
shared_preamble += "You are a cold pre-commit scanner with no memory of this conversation.";
shared_preamble += " This gate is READ-ONLY: use only read_file, list_dir, grep, and git inspection (status/diff/show).";
shared_preamble += " Do not edit files. Do not run tests, lint, typecheck, build, or any write/execute shell.";
shared_preamble += root_note;
shared_preamble += " Baseline ref (JSON): ";
shared_preamble += encoded_since;
shared_preamble += " Root (JSON): ";
shared_preamble += encoded_root;
shared_preamble += " Host diff excerpt (JSON, may be truncated or empty; do NOT treat it as complete): ";
shared_preamble += encoded_diff;
shared_preamble += " MUST inspect git yourself before answering: status and diff vs the baseline, including staged and unstaged, in the git checkout that contains the root.";
shared_preamble += " This workspace may have several sibling checkouts; pick the repo that matches the root (or the checkout that actually has changes).";
shared_preamble += " Then read the changed files, not only the hunks.";

let findings_tail = "";
findings_tail += " Report at most 8 findings as {file, issue, evidence, severity}.";
findings_tail += " file is repo-relative. issue is one concrete problem. evidence is a quote or hunk you independently inspected.";
findings_tail += " severity is \"block\" (must not commit) or \"warn\" (advisory, does not block).";
findings_tail += " Prefer \"block\" for secrets, AGENTS.md hard-rule breaks, missing tests for changed behavior, and correctness bugs that would ship.";
findings_tail += " summary is one sentence covering the lane (including a clean tree).";
findings_tail += " An empty findings list is valid ONLY after you inspected the real diff or confirmed a clean tree with git status/diff.";

phase("Scan");
log("Scanning diff, AGENTS.md tests, and secrets (read-only)");

let diff_prompt = "";
diff_prompt += shared_preamble;
diff_prompt += " Lane: DIFF REVIEW.";
diff_prompt += " Look for correctness bugs, regressions, broken imports, auth/data leaks, and AGENTS.md hard-rule violations.";
diff_prompt += " You MUST open AGENTS.md (and AGENTS.project.md if present) under the root and check the change against those rules.";
diff_prompt += " Typical hard rules in this app family: never delete or abandon startup.sh; never create a .env; never strip grok PWA chrome, PreviewHostBridge, or the Remix/Created-with-Grok branding;";
diff_prompt += " never start Vite without npm run dev / with-app-env; auth and @/lib/db only when the project asks for accounts.";
diff_prompt += " Confirm each suspected violation by reading the file as it exists now. Do not answer from memory.";
diff_prompt += findings_tail;

let tests_prompt = "";
tests_prompt += shared_preamble;
tests_prompt += " Lane: TESTS FROM AGENTS.md (static audit — you cannot run commands).";
tests_prompt += " MUST read AGENTS.md and AGENTS.project.md under the root. Extract the quality bar and verification steps (build, typecheck, test, browser-smoke, and any other named commands).";
tests_prompt += " MUST read package.json scripts (and any wrapper they call, e.g. scripts/test.mjs) so commands come from files, not memory.";
tests_prompt += " Typical quality-bar commands in this app family include npm test, npm run typecheck, npm run build, and node scripts/browser-smoke.mjs — but only claim them if you read them.";
tests_prompt += " For each changed source file, look for a colocated or matching *.test.ts / *.test.mjs / *.test.js and READ those tests.";
tests_prompt += " BLOCK if: changed behavior has no covering test; tests were deleted or gutted; a new module shipped without a test;";
tests_prompt += " AGENTS.md-required scripts are missing from package.json; or the existing test does not exercise the changed API.";
tests_prompt += " WARN if coverage is thin but a relevant test exists. Do NOT claim tests passed or failed at runtime — this lane does not execute them.";
tests_prompt += " Do not invent npm test / pytest / cargo test. Empty findings is valid ONLY after you read AGENTS.md, package.json, the diff, and the relevant test files (or confirmed no source changed).";
tests_prompt += findings_tail;

let secrets_prompt = "";
secrets_prompt += shared_preamble;
secrets_prompt += " Lane: SECRETS SCAN.";
secrets_prompt += " Scan ADDED and modified lines in the real diff, then open those files to confirm.";
secrets_prompt += " BLOCK for live credentials: API keys, access tokens, private keys (PEM), passwords, JWT secrets, database URLs with passwords, cloud keys, .env files with values, auth cookies.";
secrets_prompt += " Also BLOCK committing secret material in docs, fixtures, screenshots metadata, or scripts.";
secrets_prompt += " Do NOT flag placeholders, empty values, variable NAMES without values, *.example / deploy.env.example templates, or obviously fake documentation strings.";
secrets_prompt += " Quote the matching line in evidence, but redact the secret value itself (keep a short prefix plus ellipsis).";
secrets_prompt += " Empty findings is valid ONLY after you scanned the full added-line diff (or confirmed a clean tree).";
secrets_prompt += findings_tail;

let scan_jobs = [
    #{
        prompt: diff_prompt,
        label: "scan:diff",
        capability_mode: "read-only",
        agent_type: "explore",
        output_schema: findings_schema,
    },
    #{
        prompt: tests_prompt,
        label: "scan:tests",
        capability_mode: "read-only",
        agent_type: "explore",
        output_schema: findings_schema,
    },
    #{
        prompt: secrets_prompt,
        label: "scan:secrets",
        capability_mode: "read-only",
        agent_type: "explore",
        output_schema: findings_schema,
    },
];

let scanned = parallel(scan_jobs);

let lane_names = ["diff", "tests", "secrets"];
let lane_ok = [false, false, false];
let lane_summaries = ["", "", ""];
let failed_lanes = [];
let blockers = [];
let warnings = [];

let li = 0;
for r in scanned {
    let lane = lane_from(r);
    let name = lane_names[li];
    lane_ok[li] = lane.ok;
    lane_summaries[li] = lane.summary;
    if lane.ok != true {
        failed_lanes.push(name);
        log("Lane " + name + " failed closed: " + lane.summary);
    } else {
        let kept = keep_usable_findings(filter_root_findings(lane.findings, root));
        if kept.len() > MAX_FINDINGS {
            log("Truncated " + name + " findings from " + kept.len().to_string() + " to " + MAX_FINDINGS.to_string());
            kept = take_n(kept, MAX_FINDINGS);
        }
        for f in kept {
            let item = #{
                lane: name,
                file: trimmed(f.file),
                issue: trimmed(f.issue),
                evidence: trimmed(f.evidence),
                severity: trimmed(f.severity),
            };
            if is_block_severity(f) {
                if item.severity == "" { item.severity = "block"; }
                blockers.push(item);
            } else {
                warnings.push(item);
            }
        }
        log("Lane " + name + " ok; blockers so far " + blockers.len().to_string());
    }
    li += 1;
}

if blockers.len() > MAX_VERIFY {
    log("Truncated blockers from " + blockers.len().to_string() + " to " + MAX_VERIFY.to_string() + " before verify");
    blockers = take_n(blockers, MAX_VERIFY);
}

let to_verify = blockers;
let remaining = budget().remaining;
if remaining < to_verify.len() {
    let keep = remaining;
    if keep < 0 { keep = 0; }
    log("Budget remaining " + remaining.to_string() + "; verifying only " + keep.to_string() + " blockers");
    to_verify = take_n(to_verify, keep);
}

let confirmed = [];
let unverified = 0;

if to_verify.len() > 0 {
    phase("Verify");
    log("Verifying " + to_verify.len().to_string() + " candidate blockers");

    let vjobs = [];
    let vi = 0;
    for f in to_verify {
        let encoded = json_encode(#{
            lane: f.lane,
            file: f.file,
            issue: f.issue,
            evidence: f.evidence,
            severity: f.severity,
        });
        let vp = "";
        vp += "Adversarially verify this pre-commit BLOCK finding. You are a cold subagent. Do not trust the scanner.";
        vp += " Use only read-only tools (read_file, list_dir, grep, git diff/show). Do not edit or run tests.";
        vp += " Finding JSON:\n";
        vp += encoded;
        vp += "\nIndependently open the cited file (and the surrounding diff vs ";
        vp += encoded_since;
        vp += ") and check whether the issue is real in the current tree.";
        vp += " Set real=true ONLY with a concrete quote in evidence that you inspected yourself.";
        vp += " For secrets, real=true only if the added content looks like a live credential, not a placeholder or example.";
        vp += " For tests, real=true only if you confirmed the coverage/contract gap by reading AGENTS.md or the test files.";
        vp += " If the file is missing, the quote is absent, or the claim is speculative, set real=false.";
        vp += " Default real=false when unsure.";
        vjobs.push(#{
            prompt: vp,
            label: "verify:" + vi.to_string(),
            capability_mode: "read-only",
            agent_type: "explore",
            output_schema: verdict_schema,
        });
        vi += 1;
    }

    let verdicts = parallel(vjobs);
    let i = 0;
    for v in verdicts {
        let accepted = false;
        if v != () && v.success == true && v.output != () {
            if v.output.real == true && v.output.evidence != () && trimmed(v.output.evidence) != "" {
                accepted = true;
            }
        }
        if accepted {
            let item = to_verify[i];
            if v.output.reason != () {
                item.reason = trimmed(v.output.reason);
            }
            item.verified_evidence = trimmed(v.output.evidence);
            confirmed.push(item);
        } else {
            unverified += 1;
        }
        i += 1;
    }
    log(confirmed.len().to_string() + "/" + to_verify.len().to_string() + " blockers survived verification");
} else {
    phase("Verify");
    log("No candidate blockers to verify");
}

phase("Decide");

let blocked = false;
if failed_lanes.len() > 0 { blocked = true; }
if confirmed.len() > 0 { blocked = true; }

let verdict = "SHIP";
if blocked { verdict = "BLOCK"; }

log("Verdict " + verdict + " (confirmed=" + confirmed.len().to_string() + " failed_lanes=" + failed_lanes.len().to_string() + ")");

let md = "";
md += "# Preflight gate: ";
md += verdict;
md += "\n\n";
md += "Read-only pre-commit gate. Tests were **audited against AGENTS.md**, not executed.\n\n";
md += "- **Baseline:** `";
md += since_ref;
md += "`\n";
md += "- **Root:** `";
md += root;
md += "`\n";
if diff_was_truncated {
    md += "- Host diff excerpt was truncated; scanners were required to inspect git themselves.\n";
}
md += "\n## Verdict\n\n";
if verdict == "SHIP" {
    md += "**SHIP** — no confirmed blockers and every scan lane completed.\n\n";
} else {
    md += "**BLOCK** — do not commit until the items below are fixed";
    if failed_lanes.len() > 0 {
        md += ", and re-run if a scan lane failed";
    }
    md += ".\n\n";
}

md += "## Lanes\n\n";
let lj = 0;
while lj < 3 {
    let mark = "FAILED";
    if lane_ok[lj] == true { mark = "ok"; }
    md += "- **";
    md += lane_names[lj];
    md += ":** ";
    md += mark;
    if lane_summaries[lj] != "" {
        md += " — ";
        md += lane_summaries[lj];
    }
    md += "\n";
    lj += 1;
}
md += "\n";

if failed_lanes.len() > 0 {
    md += "Failed lanes are a gate failure (fail closed): ";
    let first_fail = true;
    for name in failed_lanes {
        if first_fail != true { md += ", "; }
        first_fail = false;
        md += "`" + name + "`";
    }
    md += ".\n\n";
}

md += "## Confirmed blockers\n\n";
if confirmed.len() == 0 {
    md += "_None. Unverified scanner claims are not treated as blockers._\n\n";
} else {
    for it in confirmed {
        md += "- **";
        md += it.lane;
        md += "** `";
        md += it.file;
        md += "`: ";
        md += it.issue;
        md += "\n";
        md += "  - Scanner evidence: ";
        md += it.evidence;
        md += "\n";
        if it.verified_evidence != () && trimmed(it.verified_evidence) != "" {
            md += "  - Verified: ";
            md += trimmed(it.verified_evidence);
            md += "\n";
        }
    }
    md += "\n";
}

md += "## Warnings (do not block)\n\n";
if warnings.len() == 0 {
    md += "_None._\n\n";
} else {
    for it in warnings {
        md += "- **";
        md += it.lane;
        md += "** `";
        md += it.file;
        md += "`: ";
        md += it.issue;
        md += "\n";
        md += "  - ";
        md += it.evidence;
        md += "\n";
    }
    md += "\n";
}

md += "## Limits\n\n";
md += "- Read-only: no edits; tests/lint/typecheck/build were not executed.\n";
md += "- A BLOCK finding must survive an independent file-backed check. Missing verification is not a confirming vote.\n";
md += "- A scan lane that fails to complete **does** block (fail closed).\n";
md += "- Scan fan-out is 3; verification is capped at ";
md += MAX_VERIFY.to_string();
md += " blockers.\n";
md += "- Rejected candidate blockers: ";
md += unverified.to_string();
md += ".\n";

let report_path = write_scratch_file("preflight-gate.md", md);

let summary = verdict + ": " + confirmed.len().to_string() + " confirmed blockers, ";
summary += failed_lanes.len().to_string() + " failed lanes, ";
summary += warnings.len().to_string() + " warnings";

complete(#{
    path: report_path,
    verdict: verdict,
    summary: summary,
    since: since_ref,
    root: root,
    blockers: confirmed,
    warnings: warnings,
    failed_lanes: failed_lanes,
    unverified: unverified,
});
