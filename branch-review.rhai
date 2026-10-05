let meta = #{
    name: "branch-review",
    description: "Read-only review of origin/main...HEAD (or another range): one reviewer per changed file, then an independent verifier per finding",
    when_to_use: "Review the current branch vs origin/main with per-file fan-out and adversarial verification. Read-only.",
    phases: [
        #{ title: "Review", detail: "one read-only reviewer per changed file" },
        #{ title: "Verify", detail: "independent skeptic per finding" },
        #{ title: "Report", detail: "write confirmed findings" },
    ],
};

const MAX_FILES = 24;
const MAX_FINDINGS_PER_FILE = 4;
const MAX_DIFF_CHARS = 8000;

let findings_schema = #{
    "type": "object", "required": ["findings"],
    "properties": #{
        "findings": #{ "type": "array", "maxItems": 4, "items": #{
            "type": "object",
            "required": ["file", "issue"],
            "properties": #{
                "file": #{ "type": "string" },
                "line": #{ "type": "integer" },
                "severity": #{ "type": "string" },
                "issue": #{ "type": "string" },
                "evidence": #{ "type": "string" },
            },
        }},
    },
};

let verdict_schema = #{
    "type": "object", "required": ["real", "reason", "evidence"],
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

fn as_int(x, fallback) {
    if x == () { return fallback; }
    let t = type_of(x);
    if t == "i64" || t == "int" || t == "u64" { return x; }
    fallback
}

fn budget_remaining() {
    let b = budget();
    if b == () { return 128; }
    let rem = as_int(b.remaining, -1);
    if rem >= 0 { return rem; }
    let total = as_int(b.total, 128);
    let spent = as_int(b.spent, 0);
    let calc = total - spent;
    if calc < 0 { return 0; }
    calc
}

fn starts_with(s, prefix) {
    if type_of(s) != "string" || type_of(prefix) != "string" { return false; }
    if prefix == "" { return true; }
    if s.len() < prefix.len() { return false; }
    s.sub_string(0, prefix.len()) == prefix
}

fn ends_with(s, suffix) {
    if type_of(s) != "string" || type_of(suffix) != "string" { return false; }
    if suffix == "" { return true; }
    if s.len() < suffix.len() { return false; }
    s.sub_string(s.len() - suffix.len(), suffix.len()) == suffix
}

fn contains(s, needle) {
    if type_of(s) != "string" || type_of(needle) != "string" { return false; }
    if needle == "" { return true; }
    let idx = s.index_of(needle);
    idx != () && idx >= 0
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

fn clip(s, n) {
    if type_of(s) != "string" { return ""; }
    if s.len() <= n { return s; }
    s.sub_string(0, n) + "\n[truncated]"
}

fn unquote(s) {
    let t = trimmed(s);
    if t.len() >= 2 && starts_with(t, "\"") && ends_with(t, "\"") {
        return t.sub_string(1, t.len() - 2);
    }
    t
}

fn b_path_from_git_line(line) {
    if type_of(line) != "string" { return ""; }
    let idx = line.index_of(" b/");
    if idx != () && idx >= 0 {
        return unquote(line.sub_string(idx + 3, line.len() - idx - 3));
    }
    let idx2 = line.index_of(" \"b/");
    if idx2 != () && idx2 >= 0 {
        let rest = line.sub_string(idx2 + 4, line.len() - idx2 - 4);
        rest.trim();
        if rest.len() > 0 && ends_with(rest, "\"") {
            return rest.sub_string(0, rest.len() - 1);
        }
        return rest;
    }
    ""
}

fn skip_file(path) {
    let p = path;
    if ends_with(p, "package-lock.json") { return true; }
    if ends_with(p, "yarn.lock") { return true; }
    if ends_with(p, "pnpm-lock.yaml") { return true; }
    if ends_with(p, "Cargo.lock") { return true; }
    if ends_with(p, ".png") { return true; }
    if ends_with(p, ".jpg") { return true; }
    if ends_with(p, ".jpeg") { return true; }
    if ends_with(p, ".gif") { return true; }
    if ends_with(p, ".webp") { return true; }
    if ends_with(p, ".ico") { return true; }
    if ends_with(p, ".pdf") { return true; }
    if ends_with(p, ".woff") { return true; }
    if ends_with(p, ".woff2") { return true; }
    if ends_with(p, ".map") { return true; }
    if ends_with(p, ".gen.ts") { return true; }
    if ends_with(p, ".gen.js") { return true; }
    if contains(p, "/node_modules/") { return true; }
    if starts_with(p, "node_modules/") { return true; }
    if contains(p, "/screenshots/") { return true; }
    if starts_with(p, "screenshots/") { return true; }
    false
}

fn parse_diff_files(diff) {
    let files = [];
    let seen = #{};
    if type_of(diff) != "string" || diff == "" { return files; }
    let lines = diff.split("\n");
    for line in lines {
        if starts_with(line, "diff --git ") {
            let path = trimmed(b_path_from_git_line(line));
            if path != "" && path != "/dev/null" && seen[path] != true {
                seen[path] = true;
                files.push(path);
            }
        }
    }
    files
}

fn extract_selected_diffs(diff, wanted) {
    let map = #{};
    if type_of(diff) != "string" || diff == "" { return map; }
    let lines = diff.split("\n");
    let current = "";
    let buf = "";
    let capturing = false;
    for line in lines {
        if starts_with(line, "diff --git ") {
            if capturing && current != "" && buf != "" {
                map[current] = clip(buf, MAX_DIFF_CHARS);
            }
            current = trimmed(b_path_from_git_line(line));
            capturing = current != "" && wanted[current] == true;
            if capturing {
                buf = line;
            } else {
                buf = "";
            }
        } else if capturing {
            buf += "\n";
            buf += line;
        }
    }
    if capturing && current != "" && buf != "" {
        map[current] = clip(buf, MAX_DIFF_CHARS);
    }
    map
}

fn line_of(f) {
    if f == () { return 0; }
    as_int(f.line, 0)
}

fn severity_of(s) {
    let x = trimmed(s);
    if x == "bug" || x == "risk" || x == "suggestion" { return x; }
    if x == "nit" { return "suggestion"; }
    "risk"
}

fn empty_report(range, summary) {
    let md = "";
    md += "# Branch review\n\n";
    md += summary + "\n\n";
    md += "Range: `" + range + "`\n";
    let p = write_scratch_file("branch-review.md", md);
    complete(#{
        path: p,
        summary: summary,
        range: range,
        confirmed: [],
        rejected: 0,
        files_reviewed: [],
    });
}

let base = "origin/main";
let head = "HEAD";
let root = "";
let max_files = MAX_FILES;
let explicit = [];

if args != () {
    if args.base != () {
        let b = trimmed(args.base);
        if b != "" { base = b; }
    }
    if args.head != () {
        let h = trimmed(args.head);
        if h != "" { head = h; }
    }
    if args.root != () {
        let r = trimmed(args.root);
        if r != "" { root = r; }
    }
    if args.max_files != () {
        let t = type_of(args.max_files);
        if t == "i64" || t == "int" || t == "u64" {
            if args.max_files > 0 { max_files = args.max_files; }
        }
    }
    if args.files != () {
        if type_of(args.files) == "string" {
            let one = trimmed(args.files);
            if one != "" { explicit.push(one); }
        }
        if type_of(args.files) == "array" {
            for f in args.files {
                let p = trimmed(f);
                if p != "" { explicit.push(p); }
            }
        }
    }
}

let range = base + "..." + head;
let diff = "";
let diff_ok = false;
try {
    diff = git_diff_since(base);
    diff_ok = true;
} catch (e) {
    log("git_diff_since(" + base + ") failed");
}
if diff == () { diff = ""; }

if !diff_ok && explicit.len() == 0 {
    pause("infra", "git_diff_since failed. Run inside a git checkout, or pass args.files (and args.root for a nested repo). Default range is origin/main...HEAD.");
}

let parsed = parse_diff_files(diff);
log("Host diff listed " + parsed.len().to_string() + " files for " + range);

let files = [];
let skipped_n = 0;
if explicit.len() > 0 {
    if parsed.len() > 0 {
        let allow = #{};
        for p in parsed { allow[p] = true; }
        let dropped = 0;
        for p in explicit {
            if allow[p] == true {
                files.push(p);
            } else {
                dropped += 1;
            }
        }
        if files.len() == 0 {
            log("args.files were not in the host diff; reviewing them anyway");
            files = explicit;
        } else if dropped > 0 {
            log("Dropped " + dropped.to_string() + " args.files not present in the host diff");
        }
    } else {
        files = explicit;
    }
} else {
    for p in parsed {
        if skip_file(p) {
            skipped_n += 1;
        } else {
            files.push(p);
        }
    }
    if skipped_n > 0 {
        log("Skipped " + skipped_n.to_string() + " lock/binary/generated files");
    }
}

if files.len() == 0 {
    if diff_ok {
        empty_report(range, "No files to review in " + range + ".");
    }
    pause("verification", "No changed files. Pass args.files, or run from a git checkout that has changes vs " + base + ".");
}

let remaining = budget_remaining();
let review_slots = remaining / 2;
if review_slots > max_files { review_slots = max_files; }
if review_slots < 1 && remaining >= 1 { review_slots = 1; }
if files.len() > review_slots {
    log("Truncated files from " + files.len().to_string() + " to " + review_slots.to_string() + " (raise args.max_files and/or agent_budget)");
    files = take_n(files, review_slots);
}

if files.len() == 0 {
    empty_report(range, "No agent budget remaining to review " + range + ".");
}

let wanted = #{};
for p in files { wanted[p] = true; }
let per_file_diff = extract_selected_diffs(diff, wanted);

let root_note = "";
if root != "" {
    root_note += " The git checkout lives at ";
    root_note += json_encode(root);
    root_note += ". Paths are relative to that checkout. Run git -C there (or cd first). read_file the joined path.";
}

phase("Review");
log("Reviewing " + files.len().to_string() + " files in " + range);

let jobs = [];
let ri = 0;
for path in files {
    let hunk = "";
    if per_file_diff[path] != () { hunk = per_file_diff[path]; }
    let prompt = "";
    prompt += "You are a cold subagent reviewing ONE file from git range ";
    prompt += range;
    prompt += ".";
    prompt += root_note;
    prompt += " Assigned file: ";
    prompt += json_encode(path);
    prompt += "\nMUST use read-only tools before answering: inspect the per-file diff below, git diff ";
    prompt += range;
    prompt += " -- the assigned file, and read_file the current source plus callers/types the diff actually touches.";
    prompt += " grep only for symbols you saw in the diff. Do not write files, do not run tests, do not review other files.";
    prompt += " Look for correctness bugs, broken error handling, security issues, regressions, and cross-module side effects.";
    prompt += " Do not inflate severity. A bug is an actual defect, not a style preference. Skip nits unless they hide a bug.";
    prompt += " Be specific: cite a post-change line number when you can see it.";
    prompt += " Report at most 4 findings as {file, line, severity, issue, evidence}.";
    prompt += " file MUST be exactly the assigned file. line is the post-change line or 0.";
    prompt += " severity is bug, risk, or suggestion. issue is a concrete defect, not a summary of the change.";
    prompt += " evidence quotes the code or diff hunk you inspected.";
    prompt += " An empty findings list is valid ONLY after you inspected this file's diff and source. Not inspecting is a failure, not an empty list.";
    prompt += " Do not invent issues to fill space.\nPer-file diff JSON:\n";
    prompt += json_encode(hunk);
    jobs.push(#{
        prompt: prompt,
        label: "review:" + ri.to_string(),
        capability_mode: "read-only",
        agent_type: "explore",
        output_schema: findings_schema,
    });
    ri += 1;
}

let results = parallel(jobs);

let findings = [];
let out_of_scope = 0;
let fi = 0;
for r in results {
    let assigned = files[fi];
    if r != () && r.success == true && r.output != () && r.output.findings != () {
        for f in r.output.findings {
            if f != () {
                let issue = trimmed(f.issue);
                if issue != "" {
                    let fp = trimmed(f.file);
                    if fp == "" { fp = assigned; }
                    let in_scope = wanted[fp] == true;
                    if !in_scope {
                        if fp == assigned {
                            in_scope = true;
                        }
                    }
                    if !in_scope {
                        out_of_scope += 1;
                    } else {
                        let ev = "";
                        if f.evidence != () { ev = trimmed(f.evidence); }
                        findings.push(#{
                            file: assigned,
                            line: line_of(f),
                            severity: severity_of(f.severity),
                            issue: issue,
                            evidence: ev,
                        });
                    }
                }
            }
        }
    }
    fi += 1;
}
if out_of_scope > 0 {
    log("Dropped " + out_of_scope.to_string() + " out-of-scope findings");
}
log("Reviewers reported " + findings.len().to_string() + " in-scope findings");

if findings.len() == 0 {
    phase("Report");
    let md = "";
    md += "# Branch review\n\n";
    md += "Range: `" + range + "`\n\n";
    md += "Reviewed " + files.len().to_string() + " files. No in-scope findings.\n\n";
    md += "## Files reviewed\n\n";
    for p in files {
        md += "- `" + p + "`\n";
    }
    md += "\nRead-only. Empty findings after inspection are treated as a clean review of those files, not coverage of files that were truncated or skipped.\n";
    let p = write_scratch_file("branch-review.md", md);
    complete(#{
        path: p,
        summary: "No in-scope findings across " + files.len().to_string() + " file(s).",
        range: range,
        confirmed: [],
        rejected: 0,
        files_reviewed: files,
    });
}

let v_remaining = budget_remaining();
if findings.len() > v_remaining {
    log("Truncated findings from " + findings.len().to_string() + " to " + v_remaining.to_string() + " before verify (agent budget)");
    findings = take_n(findings, v_remaining);
}

if findings.len() == 0 {
    phase("Report");
    let md = "";
    md += "# Branch review\n\n";
    md += "Range: `" + range + "`\n\nReview produced findings but none could be verified under the remaining agent budget.\n";
    let p = write_scratch_file("branch-review.md", md);
    complete(#{
        path: p,
        summary: "No budget left to verify findings.",
        range: range,
        confirmed: [],
        rejected: 0,
        files_reviewed: files,
    });
}

phase("Verify");
log("Verifying " + findings.len().to_string() + " findings independently");

let vjobs = [];
let vi = 0;
for f in findings {
    let encoded = json_encode(f);
    let vp = "";
    vp += "Adversarially verify this branch-review finding. You are a cold independent skeptic. Do not trust the reviewer.";
    vp += root_note;
    vp += " Git range: ";
    vp += range;
    vp += "\nFinding JSON:\n";
    vp += encoded;
    vp += "\nMUST independently inspect the cited file and that file's ";
    vp += range;
    vp += " diff using read-only tools (read_file, grep, git diff). Re-read the code; do not reuse the reviewer's evidence without seeing it yourself.";
    vp += " Set real=true ONLY if the cited file exists, the issue is actually present in the current code or the diff, and evidence is a quote you personally read.";
    vp += " Style nits, speculative 'might' issues, and claims about files you did not open are real=false.";
    vp += " Default real=false when unsure. reason explains the verdict. evidence is the quote you read, or why the claim failed.";
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

let confirmed = [];
let rejected = [];
let i = 0;
for v in verdicts {
    let accepted = false;
    let why = "verifier failed or returned no evidence";
    if v != () && v.success == true && v.output != () {
        if v.output.reason != () { why = trimmed(v.output.reason); }
        if v.output.real == true && v.output.evidence != () && trimmed(v.output.evidence) != "" {
            accepted = true;
        }
    }
    if accepted {
        let item = findings[i];
        item.verdict_reason = why;
        item.verdict_evidence = trimmed(v.output.evidence);
        confirmed.push(item);
    } else {
        let item = findings[i];
        item.verdict_reason = why;
        rejected.push(item);
    }
    i += 1;
}

log(confirmed.len().to_string() + "/" + findings.len().to_string() + " findings survived verification");

phase("Report");

let md = "";
md += "# Branch review\n\n";
md += "Read-only review of `" + range + "`.";
md += " One reviewer per file, then an independent verifier per finding.";
md += " Only findings that survived verification are confirmed.\n\n";
if root != "" {
    md += "Checkout: `" + root + "`\n\n";
}
md += "- Files reviewed: " + files.len().to_string() + "\n";
md += "- Findings sent to verify: " + findings.len().to_string() + "\n";
md += "- Confirmed: " + confirmed.len().to_string() + "\n";
md += "- Rejected or unverified: " + rejected.len().to_string() + "\n\n";

md += "## Confirmed findings\n\n";
if confirmed.len() == 0 {
    md += "_None. Unverified reviewer claims are omitted, not implied true._\n\n";
} else {
    let ci = 1;
    for it in confirmed {
        let loc = "`" + it.file + "`";
        let line_n = as_int(it.line, 0);
        if line_n > 0 { loc = "`" + it.file + ":" + line_n.to_string() + "`"; }
        md += "### " + ci.to_string() + " — " + it.severity + " — " + loc + "\n\n";
        md += it.issue + "\n\n";
        md += "- **Evidence:** " + it.verdict_evidence + "\n";
        md += "- **Verifier:** " + it.verdict_reason + "\n\n";
        ci += 1;
    }
}

md += "## Rejected or unverified\n\n";
if rejected.len() == 0 {
    md += "_None._\n\n";
} else {
    for it in rejected {
        let loc = it.file;
        let line_n = as_int(it.line, 0);
        if line_n > 0 { loc = it.file + ":" + line_n.to_string(); }
        md += "- **" + it.severity + "** `" + loc + "`: " + it.issue + "\n";
        md += "  - " + it.verdict_reason + "\n";
    }
    md += "\n";
}

md += "## Files reviewed\n\n";
for p in files {
    md += "- `" + p + "`\n";
}
md += "\n";

md += "## Limits\n\n";
md += "- Read-only: no edits, no tests executed.\n";
md += "- File list comes from `git_diff_since(" + base + ")` (plus optional `args.files`). Reviewers inspect `" + range + "`.\n";
md += "- Lockfiles, images, screenshots, generated `*.gen.ts`, and `node_modules` are skipped unless named in `args.files`.\n";
md += "- Review fan-out is capped at " + max_files.to_string() + " files (and at half the remaining agent budget). Verification is fail-closed.\n";

let report_path = write_scratch_file("branch-review.md", md);
complete(#{
    path: report_path,
    summary: confirmed.len().to_string() + " confirmed / " + findings.len().to_string() + " verified across " + files.len().to_string() + " files",
    range: range,
    confirmed: confirmed,
    rejected: rejected.len(),
    files_reviewed: files,
});
