let meta = #{
    name: "class-audit",
    description: "Audit one defect class: scan in parallel, adversarially verify each hit, keep only file-backed confirmed instances",
    when_to_use: "When hunting one defect class (a smell, API, or bug pattern) across the repo and keeping only hits that survive independent verification",
    phases: [
        #{ title: "Discover", detail: "list source trees to shard the scan" },
        #{ title: "Scan", detail: "one scanner per shard for the defect class" },
        #{ title: "Verify", detail: "one skeptic per hit; fail closed" },
        #{ title: "Report", detail: "write confirmed vs rejected hits" },
    ],
};

const MAX_SHARDS = 6;
const MAX_HITS_PER_SHARD = 8;
const MAX_HITS = 16;

let shards_schema = #{
    "type": "object", "required": ["shards"],
    "properties": #{
        "shards": #{ "type": "array", "maxItems": 6, "items": #{
            "type": "object",
            "required": ["path", "role"],
            "properties": #{
                "path": #{ "type": "string" },
                "role": #{ "type": "string" },
            },
        }},
    },
};

let hits_schema = #{
    "type": "object", "required": ["hits"],
    "properties": #{
        "hits": #{ "type": "array", "maxItems": 8, "items": #{
            "type": "object",
            "required": ["file", "issue", "snippet", "why_this_class"],
            "properties": #{
                "file": #{ "type": "string" },
                "issue": #{ "type": "string" },
                "snippet": #{ "type": "string" },
                "why_this_class": #{ "type": "string" },
                "line": #{ "type": "string" },
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

fn starts_with(s, prefix) {
    if type_of(s) != "string" || type_of(prefix) != "string" { return false; }
    if prefix == "" { return true; }
    if s.len() < prefix.len() { return false; }
    s.sub_string(0, prefix.len()) == prefix
}

fn contains_str(hay, needle) {
    if type_of(hay) != "string" || type_of(needle) != "string" { return false; }
    if needle == "" { return true; }
    let nlen = needle.len();
    let hlen = hay.len();
    if hlen < nlen { return false; }
    let i = 0;
    let last = hlen - nlen;
    while i <= last {
        if hay.sub_string(i, nlen) == needle { return true; }
        i += 1;
    }
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

fn normalize_path(p) {
    let s = trimmed(p);
    if starts_with(s, "./") {
        return s.sub_string(2, s.len() - 2);
    }
    s
}

fn is_junk_path(p) {
    let s = normalize_path(p);
    if s == "" { return true; }
    if contains_str(s, "node_modules") { return true; }
    if contains_str(s, ".git/") { return true; }
    if contains_str(s, ".git\\") { return true; }
    if contains_str(s, "/dist/") { return true; }
    if contains_str(s, "\\dist\\") { return true; }
    if contains_str(s, "/build/") { return true; }
    if contains_str(s, "\\build\\") { return true; }
    if contains_str(s, "/coverage/") { return true; }
    if contains_str(s, "routeTree.gen.ts") { return true; }
    false
}

fn hit_key(h) {
    if h == () { return ""; }
    normalize_path(h.file) + "\n" + trimmed(h.issue)
}

fn already_has_key(arr, key) {
    for x in arr {
        if hit_key(x) == key { return true; }
    }
    false
}

fn already_has_path(arr, path) {
    for x in arr {
        if x != () && normalize_path(x.path) == path { return true; }
    }
    false
}

fn non_empty(s) {
    trimmed(s) != ""
}

fn hit_usable(h) {
    h != () && non_empty(h.file) && non_empty(h.issue) && non_empty(h.snippet) && non_empty(h.why_this_class) && !is_junk_path(h.file)
}

fn shard_usable(s) {
    s != () && non_empty(s.path) && !is_junk_path(s.path)
}

fn shards_of(r) {
    if r == () { return []; }
    if r.success != true { return []; }
    if r.output == () { return []; }
    if type_of(r.output) != "map" { return []; }
    if r.output.shards == () { return []; }
    r.output.shards
}

fn hits_of(r) {
    if r == () { return []; }
    if r.success != true { return []; }
    if r.output == () { return []; }
    if type_of(r.output) != "map" { return []; }
    if r.output.hits == () { return []; }
    r.output.hits
}

fn md_escape_cell(s) {
    let t = trimmed(s);
    let out = "";
    let i = 0;
    while i < t.len() {
        let ch = t.sub_string(i, 1);
        if ch == "|" { out += "\\|"; } else { out += ch; }
        i += 1;
    }
    out
}

let pattern = ();
if args != () {
    if args.pattern != () {
        let p = trimmed(args.pattern);
        if p != "" { pattern = p; }
    }
}
if pattern == () {
    pause("verification", "Pass args.pattern — the defect class to audit (e.g. unsanitized innerHTML, bare catch, as any).");
}

let encoded_pattern = json_encode(pattern);

phase("Discover");
log("Discovering source trees to shard a read-only audit of " + pattern);

let discover_prompt = "";
discover_prompt += "List source trees in this workspace so another agent can audit ONE defect class inside each tree. ";
discover_prompt += "You are a cold subagent with no memory of this conversation. ";
discover_prompt += "MUST use read-only tools: list_dir on the workspace root, then list_dir on each top-level directory that looks like an app, package, or src tree. ";
discover_prompt += "Do not use write or execute tools. Do not run tests. ";
discover_prompt += "Skip node_modules, dist, build, coverage, .git, lockfiles, and screenshot/image-only folders. ";
discover_prompt += "If several similar app copies exist (PR folders, duplicates), list each distinct source tree you actually listed. ";
discover_prompt += "Report at most 6 shards as {path, role}. path is repo-relative (a directory). role is e.g. primary app, PR copy, scripts, server. ";
discover_prompt += "An empty list is valid ONLY after you listed the root and found no source trees.";

let discovered = agent(discover_prompt, #{
    label: "discover:shards",
    capability_mode: "read-only",
    agent_type: "explore",
    output_schema: shards_schema,
});

let shards = [];
for s in shards_of(discovered) {
    if shard_usable(s) {
        let path = normalize_path(s.path);
        if path != "" && !already_has_path(shards, path) {
            shards.push(#{ path: path, role: trimmed(s.role) });
        }
    }
}

if shards.len() == 0 {
    log("Discovery returned no usable shards; scanning workspace root");
    shards.push(#{ path: ".", role: "workspace-root" });
}

if shards.len() > MAX_SHARDS {
    log("Truncated shards from " + shards.len().to_string() + " to " + MAX_SHARDS.to_string());
    shards = take_n(shards, MAX_SHARDS);
}

let rem = budget().remaining;
if rem < shards.len() {
    let keep = rem;
    if keep < 0 { keep = 0; }
    log("Budget remaining " + rem.to_string() + "; scanning only " + keep.to_string() + " shards");
    shards = take_n(shards, keep);
}

if shards.len() == 0 {
    let empty = "";
    empty += "# Class audit\n\n";
    empty += "Pattern: " + pattern + "\n\n";
    empty += "No shards could be scanned under the remaining agent budget.\n";
    let p = write_scratch_file("class-audit.md", empty);
    complete(#{
        path: p,
        summary: "No budget left to scan.",
        pattern: pattern,
        confirmed: [],
        rejected: [],
        confirmed_count: 0,
        rejected_count: 0,
        candidates: 0,
        shards: 0,
    });
}

phase("Scan");
log("Scanning " + shards.len().to_string() + " shards for defect class: " + pattern);

let scan_jobs = [];
let si = 0;
for s in shards {
    let encoded_shard = json_encode(s.path);
    let sp = "";
    sp += "Audit ONE defect class inside a single shard of this repository. ";
    sp += "You are a cold subagent. Use only read-only tools (grep, read_file, list_dir). Do not edit files. Do not run tests or lint. ";
    sp += "Defect class (JSON): ";
    sp += encoded_pattern;
    sp += "\nShard directory (JSON): ";
    sp += encoded_shard;
    sp += "\nStay inside that shard. Do not search node_modules, dist, build, coverage, or generated files such as routeTree.gen.ts. ";
    sp += "Treat the defect class as a real bug/smell class, not only a literal string. Use grep for likely tokens, then read surrounding code to confirm each hit belongs to this class. ";
    sp += "Skip comments-only mentions, changelog lines, and test fixtures that only assert the pattern unless the test itself is the defect. ";
    sp += "Report at most 8 hits as {file, issue, snippet, why_this_class, line}. ";
    sp += "file is repo-relative. issue is one sentence. snippet is a short quote you actually read. why_this_class explains why this instance is that class. line is a string line number if you have one. ";
    sp += "An empty list is valid ONLY after you grepped and listed the shard and found no instances of this class.";
    scan_jobs.push(#{
        prompt: sp,
        label: "scan:" + si.to_string(),
        capability_mode: "read-only",
        agent_type: "explore",
        output_schema: hits_schema,
    });
    si += 1;
}

let scan_results = parallel(scan_jobs);

let hits = [];
let dropped_unusable = 0;
let dropped_dup = 0;
for r in scan_results {
    for h in hits_of(r) {
        if !hit_usable(h) {
            dropped_unusable += 1;
        } else {
            let key = hit_key(h);
            if already_has_key(hits, key) {
                dropped_dup += 1;
            } else {
                hits.push(#{
                    file: normalize_path(h.file),
                    issue: trimmed(h.issue),
                    snippet: trimmed(h.snippet),
                    why_this_class: trimmed(h.why_this_class),
                    line: trimmed(h.line),
                });
            }
        }
    }
}
if dropped_unusable > 0 {
    log("Dropped " + dropped_unusable.to_string() + " unusable hits");
}
if dropped_dup > 0 {
    log("Dropped " + dropped_dup.to_string() + " duplicate hits");
}

if hits.len() > MAX_HITS {
    log("Truncated hits from " + hits.len().to_string() + " to " + MAX_HITS.to_string() + " before verify");
    hits = take_n(hits, MAX_HITS);
}

log("Scan produced " + hits.len().to_string() + " candidate hits across " + shards.len().to_string() + " shards");

if hits.len() == 0 {
    phase("Report");
    let empty = "";
    empty += "# Class audit\n\n";
    empty += "**Pattern:** " + pattern + "\n\n";
    empty += "Scanned " + shards.len().to_string() + " shard(s). No usable candidate hits. ";
    empty += "This is not proof the class is absent — scanners returned nothing that passed filters.\n\n";
    empty += "## Shards\n\n";
    for s in shards {
        empty += "- `" + s.path + "` — " + s.role + "\n";
    }
    empty += "\n## Limits\n\n";
    empty += "- Read-only. No edits, tests, or lint.\n";
    empty += "- Per-shard cap " + MAX_HITS_PER_SHARD.to_string() + "; verify cap " + MAX_HITS.to_string() + ".\n";
    let p = write_scratch_file("class-audit.md", empty);
    complete(#{
        path: p,
        summary: "No candidate hits for " + pattern,
        pattern: pattern,
        confirmed: [],
        rejected: [],
        confirmed_count: 0,
        rejected_count: 0,
        candidates: 0,
        shards: shards.len(),
    });
}

let rem_v = budget().remaining;
if rem_v < hits.len() {
    let keep = rem_v;
    if keep < 0 { keep = 0; }
    log("Budget remaining " + rem_v.to_string() + "; verifying only " + keep.to_string() + " hits");
    hits = take_n(hits, keep);
}

if hits.len() == 0 {
    phase("Report");
    let empty = "";
    empty += "# Class audit\n\n";
    empty += "**Pattern:** " + pattern + "\n\n";
    empty += "Scan produced candidates but none could be verified under the remaining agent budget.\n";
    let p = write_scratch_file("class-audit.md", empty);
    complete(#{
        path: p,
        summary: "No budget left to verify hits.",
        pattern: pattern,
        confirmed: [],
        rejected: [],
        confirmed_count: 0,
        rejected_count: 0,
        candidates: 0,
        shards: shards.len(),
    });
}

phase("Verify");
log("Adversarially verifying " + hits.len().to_string() + " hits (fail closed)");

let vjobs = [];
let vi = 0;
for h in hits {
    let encoded_hit = json_encode(#{
        pattern: pattern,
        file: h.file,
        line: h.line,
        issue: h.issue,
        snippet: h.snippet,
        why_this_class: h.why_this_class,
    });
    let vp = "";
    vp += "Adversarially verify whether this is a REAL instance of one defect class. Do not trust the scanner. ";
    vp += "You are a cold subagent. Use only read-only tools (read_file, grep, list_dir). Do not edit files. Do not run tests. ";
    vp += "Independently open the cited file and read the surrounding code. ";
    vp += "Claim JSON:\n";
    vp += encoded_hit;
    vp += "\nSet real=true ONLY if all of these hold: the file exists, the snippet (or the same code) is present, ";
    vp += "and the site is an unmitigated instance of this defect class — not a comment, not generated noise, not a test that merely mentions it, ";
    vp += "not already guarded/safe usage of a similar API. Quote the supporting code in evidence. ";
    vp += "If the file is missing, the snippet is absent, the class does not match, or you are unsure, set real=false. Default real=false.";
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
    let h = hits[i];
    let accepted = false;
    let reason = "unverified (failed, missing, or no evidence)";
    let evidence = "";
    if v != () && v.success == true && v.output != () {
        if v.output.reason != () { reason = trimmed(v.output.reason); }
        if v.output.evidence != () { evidence = trimmed(v.output.evidence); }
        if v.output.real == true && evidence != "" {
            accepted = true;
        }
    }
    if accepted {
        confirmed.push(#{
            file: h.file,
            line: h.line,
            issue: h.issue,
            snippet: h.snippet,
            why_this_class: h.why_this_class,
            reason: reason,
            evidence: evidence,
        });
    } else {
        rejected.push(#{
            file: h.file,
            line: h.line,
            issue: h.issue,
            reason: reason,
        });
    }
    i += 1;
}

log(confirmed.len().to_string() + "/" + hits.len().to_string() + " hits survived verification");

phase("Report");

let md = "";
md += "# Class audit\n\n";
md += "**Pattern:** " + pattern + "\n\n";
md += "Read-only audit. Scanners proposed hits; independent skeptics had to confirm each one against the file. ";
md += "Missing, failed, or evidenceless verification counts as rejected.\n\n";
md += "- Shards scanned: " + shards.len().to_string() + "\n";
md += "- Candidate hits verified: " + hits.len().to_string() + "\n";
md += "- Confirmed: " + confirmed.len().to_string() + "\n";
md += "- Rejected: " + rejected.len().to_string() + "\n\n";

md += "## Shards\n\n";
for s in shards {
    md += "- `" + s.path + "` — " + s.role + "\n";
}
md += "\n";

md += "## Confirmed\n\n";
if confirmed.len() == 0 {
    md += "_No hits survived verification._\n\n";
} else {
    for h in confirmed {
        let loc = "`" + h.file + "`";
        if h.line != "" { loc += ":" + h.line; }
        md += "### " + loc + "\n\n";
        md += h.issue + "\n\n";
        md += "- **Why this class:** " + h.why_this_class + "\n";
        md += "- **Snippet:** `" + md_escape_cell(h.snippet) + "`\n";
        md += "- **Verifier:** " + h.reason + "\n";
        md += "- **Evidence:** " + h.evidence + "\n\n";
    }
}

md += "## Rejected\n\n";
if rejected.len() == 0 {
    md += "_None._\n\n";
} else {
    md += "| File | Issue | Reason |\n";
    md += "| --- | --- | --- |\n";
    for h in rejected {
        let loc = h.file;
        if h.line != "" { loc += ":" + h.line; }
        md += "| `" + md_escape_cell(loc) + "` | " + md_escape_cell(h.issue) + " | " + md_escape_cell(h.reason) + " |\n";
    }
    md += "\n";
}

md += "## Limits\n\n";
md += "- Read-only: no edits, and tests/lint were not executed.\n";
md += "- Unverified scanner claims are listed as rejected, not implied true.\n";
md += "- Shard cap " + MAX_SHARDS.to_string() + "; per-shard hits " + MAX_HITS_PER_SHARD.to_string() + "; verify cap " + MAX_HITS.to_string() + ".\n";
md += "- Maximum logical agents per default run: 1 discover + up to 6 scanners + up to 16 verifiers = 23.\n";

let report_path = write_scratch_file("class-audit.md", md);
complete(#{
    path: report_path,
    summary: confirmed.len().to_string() + " confirmed / " + rejected.len().to_string() + " rejected for " + pattern,
    pattern: pattern,
    confirmed: confirmed,
    rejected: rejected,
    confirmed_count: confirmed.len(),
    rejected_count: rejected.len(),
    candidates: hits.len(),
    shards: shards.len(),
});
