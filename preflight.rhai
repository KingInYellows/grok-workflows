let meta = #{
    name: "preflight",
    description: "Universal pre-commit/pre-PR gate: map the change set, multi-dimension review, adversarial verify, ship-or-block report",
    when_to_use: "Before commit or PR on any repo; uncommitted working tree by default, or a named target",
    phases: [
        #{ title: "Scope", detail: "map the change set and risk areas" },
        #{ title: "Review", detail: "parallel quality dimensions" },
        #{ title: "Verify", detail: "adversarial confirmation of findings" },
        #{ title: "Report", detail: "synthesize ship gate" },
    ],
};

// --- schemas -----------------------------------------------------------------

let scope_schema = #{
    "type": "object",
    "required": ["summary", "files", "risk_areas", "notes"],
    "properties": #{
        "summary": #{ "type": "string" },
        "files": #{
            "type": "array",
            "maxItems": 40,
            "items": #{
                "type": "object",
                "required": ["path", "change"],
                "properties": #{
                    "path": #{ "type": "string" },
                    "change": #{ "type": "string" },
                },
            },
        },
        "risk_areas": #{
            "type": "array",
            "maxItems": 12,
            "items": #{ "type": "string" },
        },
        "notes": #{ "type": "string" },
    },
};

let findings_schema = #{
    "type": "object",
    "required": ["findings"],
    "properties": #{
        "findings": #{
            "type": "array",
            "maxItems": 8,
            "items": #{
                "type": "object",
                "required": ["file", "issue", "severity", "dimension"],
                "properties": #{
                    "file": #{ "type": "string" },
                    "issue": #{ "type": "string" },
                    "severity": #{ "type": "string" },
                    "dimension": #{ "type": "string" },
                },
            },
        },
    },
};

let verdict_schema = #{
    "type": "object",
    "required": ["real", "reason", "evidence", "severity"],
    "properties": #{
        "real": #{ "type": "boolean" },
        "reason": #{ "type": "string" },
        "evidence": #{ "type": "string" },
        "severity": #{ "type": "string" },
    },
};

let report_schema = #{
    "type": "object",
    "required": ["verdict", "headline", "blocking", "warnings", "clean", "next_steps"],
    "properties": #{
        "verdict": #{ "type": "string" },
        "headline": #{ "type": "string" },
        "blocking": #{
            "type": "array",
            "maxItems": 16,
            "items": #{ "type": "string" },
        },
        "warnings": #{
            "type": "array",
            "maxItems": 16,
            "items": #{ "type": "string" },
        },
        "clean": #{ "type": "string" },
        "next_steps": #{
            "type": "array",
            "maxItems": 8,
            "items": #{ "type": "string" },
        },
    },
};

// --- args --------------------------------------------------------------------
// Guard `args` itself first: property access on unit is a runtime error.

let target = if args == () { () } else { args.target };
let focus = if args == () { () } else { args.focus };

// Treat whitespace-only strings as empty (args often arrive as "  ").
let target_str = if target == () { "" } else { target.to_string() };
if type_of(target_str) == "string" { target_str.trim(); }
let focus_str = if focus == () { "" } else { focus.to_string() };
if type_of(focus_str) == "string" { focus_str.trim(); }

let target_desc = if target == () || target_str == "" {
    "the current uncommitted working tree vs HEAD (git status + git diff + staged). Prefer staged+unstaged; if clean, say so."
} else {
    "target: " + target_str
};

let focus_note = if focus == () || focus_str == "" {
    ""
} else {
    " Extra focus from the user (still stay in-scope of the change set): " + focus_str + "."
};

// --- Phase 1: Scope ----------------------------------------------------------

phase("Scope");
log("Mapping change set (" + target_desc + ")");

let scope_prompt = "";
scope_prompt += "You are the SCOPER for a universal preflight gate on the current repository.\n";
scope_prompt += "Goal: map what is about to ship so reviewers stay in-scope.\n";
scope_prompt += "Target: " + target_desc + "\n";
scope_prompt += "You MUST use tools (run_terminal_command for git status/diff/log as needed, list_dir/read_file/grep for context). ";
scope_prompt += "Do not invent files. Empty change set is valid only after you ran git and saw a clean tree.\n";
scope_prompt += "Return:\n";
scope_prompt += "- summary: 1-3 sentences on what the change does\n";
scope_prompt += "- files: up to 40 {path, change} where change is added|modified|deleted|renamed|other\n";
scope_prompt += "- risk_areas: short tags like 'build', 'security', 'api', 'tests', 'data-migration', 'concurrency', 'ui', 'docs'\n";
scope_prompt += "- notes: anything reviewers must know (WIP markers, binary assets, generated files)\n";
scope_prompt += "Ignore secrets in diffs when quoting; never paste full credentials.\n";
scope_prompt += focus_note;

let scope_r = agent(scope_prompt, #{
    label: "scope",
    capability_mode: "execute",
    output_schema: scope_schema,
});

if scope_r == () || !scope_r.success || scope_r.output == () {
    pause("infra", "Scope agent failed. Resume to retry, or re-run with clearer args.target.");
}

let scope = scope_r.output;
let file_list = "";
if scope.files != () {
    let fi = 0;
    for f in scope.files {
        if fi < 40 {
            if f.path != () {
                file_list += f.path;
                if f.change != () { file_list += " (" + f.change + ")"; }
                file_list += "\n";
            }
        }
        fi += 1;
    }
}
if file_list == "" { file_list = "(no files listed — tree may be clean or scoper failed to enumerate)\n"; }

let risk_list = "";
if scope.risk_areas != () {
    for ra in scope.risk_areas {
        risk_list += "- " + ra + "\n";
    }
}
if risk_list == "" { risk_list = "- (none tagged)\n"; }

let scope_summary = if scope.summary != () { scope.summary } else { "(no summary)" };
let scope_notes = if scope.notes != () { scope.notes } else { "" };

log("Scope: " + scope_summary);

// --- Phase 2: Review ---------------------------------------------------------

phase("Review");

let dimensions = [
    #{
        id: "correctness",
        title: "correctness and logic bugs",
        brief: "Wrong behavior, off-by-one, race conditions, broken invariants, null/empty mishandling, dead code that still runs a bad path. Cite file+concrete issue.",
    },
    #{
        id: "safety",
        title: "security, secrets, and unsafe patterns",
        brief: "Hardcoded credentials, injection, path traversal, insecure defaults, unchecked untrusted input, privilege issues. Never echo secret values — describe location only.",
    },
    #{
        id: "errors",
        title: "error handling and edge cases",
        brief: "Swallowed errors, missing failure paths, partial writes, resource leaks, timeout/retry gaps, bad defaults on empty input.",
    },
    #{
        id: "tests",
        title: "tests and regression risk",
        brief: "Missing coverage for new behavior, broken tests, untested edge paths, flaky patterns, behavior changes without tests. Note if the repo has no test harness.",
    },
    #{
        id: "compat",
        title: "API, build, and compatibility breakage",
        brief: "Public API breaks, schema/format changes, dependency/CMake/package issues, feature flags, migration hazards, circular deps, wrong ownership boundaries.",
    },
    #{
        id: "hygiene",
        title: "docs, changelog, and incomplete wiring",
        brief: "Missing changelog when required by the repo, stale docs, TODOs that block ship, half-wired features, orphaned config, instructions that contradict the code.",
    },
];

let review_jobs = [];
for d in dimensions {
    let p = "";
    p += "You are a PREFLIGHT REVIEWER for dimension: " + d.title + " (" + d.id + ").\n";
    p += "This is a universal gate — any language/stack. Stay strictly in-scope of the change set below.\n";
    p += "Change summary: " + scope_summary + "\n";
    p += "Risk areas:\n" + risk_list;
    p += "Files:\n" + file_list;
    p += "Scoper notes: " + scope_notes + "\n";
    p += "Focus: " + d.brief + "\n";
    p += focus_note + "\n";
    p += "REQUIRED method:\n";
    p += "1) Use git diff / read_file / grep on the listed files. Do not answer from memory.\n";
    p += "2) Report at most 8 findings as {file, issue, severity, dimension}.\n";
    p += "3) severity must be one of: blocking | warning | info\n";
    p += "4) dimension must be exactly: " + d.id + "\n";
    p += "5) Empty findings is valid ONLY after you inspected the relevant diffs/files and found nothing material.\n";
    p += "6) Prefer concrete, ship-blocking issues over style nits. No duplicate noise.\n";
    review_jobs.push(#{
        prompt: p,
        label: "review:" + d.id,
        capability_mode: "execute",
        output_schema: findings_schema,
    });
}

let review_results = parallel(review_jobs);

let findings = [];
let review_fail = 0;
let ri = 0;
for r in review_results {
    if r == () || !r.success || r.output == () || r.output.findings == () {
        review_fail += 1;
    } else {
        for f in r.output.findings {
            // Enforce dimension id if agent drifted
            let dim = if f.dimension != () && f.dimension != "" {
                f.dimension
            } else if ri < dimensions.len() {
                dimensions[ri].id
            } else {
                "unknown"
            };
            let sev = if f.severity != () && f.severity != "" { f.severity } else { "warning" };
            let file = if f.file != () { f.file } else { "?" };
            let issue = if f.issue != () { f.issue } else { "?" };
            // Drop empties
            if issue != "?" && issue != "" {
                findings.push(#{
                    file: file,
                    issue: issue,
                    severity: sev,
                    dimension: dim,
                });
            }
        }
    }
    ri += 1;
}

if review_fail > 0 {
    log(review_fail.to_string() + " review dimension(s) failed or returned unusable output");
}
log(findings.len().to_string() + " raw finding(s) before verification");

// Cap verification fan-out so budget stays sane
const MAX_VERIFY = 12;
let to_verify = [];
let dropped = 0;
let fi2 = 0;
for f in findings {
    if fi2 < MAX_VERIFY {
        to_verify.push(f);
    } else {
        dropped += 1;
    }
    fi2 += 1;
}
if dropped > 0 {
    log("Dropped " + dropped.to_string() + " finding(s) past MAX_VERIFY=" + MAX_VERIFY.to_string());
}

if to_verify.len() == 0 {
    phase("Report");
    // Same string for MD body and complete() — avoid hardcoding SHIP when review panels failed.
    let v = if review_fail > 0 { "SHIP_WITH_CAVEATS" } else { "SHIP" };
    let clean_report = "";
    clean_report += "# Preflight report\n\n";
    clean_report += "**Verdict:** " + v + "\n\n";
    clean_report += "**Headline:** No material findings after multi-dimension review.\n\n";
    clean_report += "## Scope\n\n" + scope_summary + "\n\n";
    clean_report += "### Files\n\n" + file_list + "\n";
    clean_report += "### Risk areas\n\n" + risk_list + "\n";
    if review_fail > 0 {
        clean_report += "## Caveat\n\n";
        clean_report += review_fail.to_string() + " review panel(s) failed; treat clean result as partial coverage.\n\n";
    }
    clean_report += "## Next steps\n\n- Proceed to commit/PR if local build/tests are green.\n";
    let path = write_scratch_file("preflight-report.md", clean_report);
    complete(#{
        path: path,
        verdict: v,
        summary: "No confirmed findings",
        raw_findings: 0,
        confirmed: 0,
        review_failures: review_fail,
    });
}

// --- Phase 3: Verify ---------------------------------------------------------

phase("Verify");
log("Adversarially verifying " + to_verify.len().to_string() + " finding(s)");

let vjobs = [];
let vi = 0;
for f in to_verify {
    let vp = "";
    vp += "You are an ADVERSARIAL VERIFIER for a preflight gate. Default to real=false.\n";
    vp += "Claimed finding:\n";
    vp += "- file: " + f.file + "\n";
    vp += "- dimension: " + f.dimension + "\n";
    vp += "- severity (claimed): " + f.severity + "\n";
    vp += "- issue: " + f.issue + "\n";
    vp += "Change-set context: " + scope_summary + "\n";
    vp += "REQUIRED:\n";
    vp += "1) Independently inspect the shipped/working code with read_file/grep/git diff. Do not trust the claim.\n";
    vp += "2) Set real=true ONLY with concrete evidence you inspected (quote symbols, conditions, missing calls).\n";
    vp += "3) evidence must be non-empty if real=true; otherwise real=false.\n";
    vp += "4) severity: blocking | warning | info — downgrade nits; upgrade only with hard proof of ship risk.\n";
    vp += "5) reason: one short sentence for the verdict.\n";
    vjobs.push(#{
        prompt: vp,
        label: "verify:" + vi.to_string() + ":" + f.dimension,
        capability_mode: "execute",
        output_schema: verdict_schema,
    });
    vi += 1;
}

let verdicts = parallel(vjobs);

let confirmed = [];
let unverified = 0;
let i = 0;
for v in verdicts {
    if i >= to_verify.len() { break; }
    let base = to_verify[i];
    if v == () || !v.success || v.output == () {
        unverified += 1;
    } else if v.output.real == true
        && v.output.evidence != ()
        && v.output.evidence != ""
    {
        let sev = if v.output.severity != () && v.output.severity != "" {
            v.output.severity
        } else {
            base.severity
        };
        let reason = if v.output.reason != () { v.output.reason } else { "" };
        confirmed.push(#{
            file: base.file,
            issue: base.issue,
            dimension: base.dimension,
            severity: sev,
            evidence: v.output.evidence,
            reason: reason,
        });
    }
    i += 1;
}

log(confirmed.len().to_string() + "/" + to_verify.len().to_string()
    + " finding(s) confirmed; " + unverified.to_string() + " verify slot(s) unusable");

// --- Phase 4: Report ---------------------------------------------------------

phase("Report");

let confirmed_blob = "";
let bi = 0;
for c in confirmed {
    bi += 1;
    confirmed_blob += bi.to_string() + ". [" + c.severity + "] (" + c.dimension + ") " + c.file + "\n";
    confirmed_blob += "   issue: " + c.issue + "\n";
    confirmed_blob += "   evidence: " + c.evidence + "\n";
    if c.reason != () && c.reason != "" {
        confirmed_blob += "   reason: " + c.reason + "\n";
    }
    confirmed_blob += "\n";
}
if confirmed_blob == "" {
    confirmed_blob = "(none confirmed)\n";
}

let report_prompt = "";
report_prompt += "You are the PREFLIGHT SYNTHESIZER. Produce a final ship gate from verified evidence only.\n";
report_prompt += "Scope summary: " + scope_summary + "\n";
report_prompt += "Files:\n" + file_list;
report_prompt += "Risk areas:\n" + risk_list;
report_prompt += "Confirmed findings (already adversarially verified):\n" + confirmed_blob;
report_prompt += "Stats: raw=" + findings.len().to_string();
report_prompt += " verified_slots=" + to_verify.len().to_string();
report_prompt += " confirmed=" + confirmed.len().to_string();
report_prompt += " review_failures=" + review_fail.to_string();
report_prompt += " verify_unusable=" + unverified.to_string() + "\n";
report_prompt += "Rules:\n";
report_prompt += "- verdict must be exactly one of: SHIP | SHIP_WITH_WARNINGS | BLOCK\n";
report_prompt += "- BLOCK if any confirmed severity is blocking, or if critical panels failed and risk is high\n";
report_prompt += "- SHIP_WITH_WARNINGS if only warnings/info confirmed or partial coverage caveats\n";
report_prompt += "- SHIP only if no confirmed material issues and coverage is adequate\n";
report_prompt += "- blocking/warnings arrays: short actionable bullets (file: issue)\n";
report_prompt += "- clean: one sentence on what looks good\n";
report_prompt += "- next_steps: 1-5 concrete actions\n";
report_prompt += "- Do not invent findings not in the confirmed list. You may note coverage caveats.\n";
report_prompt += "You may re-read files only if needed to phrase next_steps accurately.\n";

let report_r = agent(report_prompt, #{
    label: "report",
    capability_mode: "read-only",
    output_schema: report_schema,
});

// Always write a markdown report even if the synthesizer fails
let md = "";
md += "# Preflight report\n\n";

let final_verdict = "SHIP_WITH_WARNINGS";
let headline = "";
let blocking_lines = [];
let warning_lines = [];
let clean_line = "";
let next_steps = [];

if report_r != () && report_r.success && report_r.output != () {
    let o = report_r.output;
    if o.verdict != () && o.verdict != "" { final_verdict = o.verdict; }
    if o.headline != () { headline = o.headline; }
    if o.clean != () { clean_line = o.clean; }
    if o.blocking != () {
        for b in o.blocking { blocking_lines.push(b); }
    }
    if o.warnings != () {
        for w in o.warnings { warning_lines.push(w); }
    }
    if o.next_steps != () {
        for n in o.next_steps { next_steps.push(n); }
    }
} else {
    log("Synthesizer failed — deriving verdict from confirmed list");
    let has_block = false;
    for c in confirmed {
        let line = c.file + ": " + c.issue;
        if c.severity == "blocking" {
            has_block = true;
            blocking_lines.push(line);
        } else {
            warning_lines.push(line);
        }
    }
    if has_block {
        final_verdict = "BLOCK";
        headline = "Confirmed blocking issue(s).";
    } else if confirmed.len() > 0 {
        final_verdict = "SHIP_WITH_WARNINGS";
        headline = "Confirmed non-blocking findings.";
    } else if review_fail > 0 || unverified > 0 {
        final_verdict = "SHIP_WITH_WARNINGS";
        headline = "No confirmed findings, but coverage was partial.";
    } else {
        final_verdict = "SHIP";
        headline = "No confirmed findings.";
    }
    clean_line = "See confirmed list and scope summary.";
    next_steps.push("Address blocking items before merge.");
}

// Hard fail-closed override: any confirmed blocking forces BLOCK
for c in confirmed {
    if c.severity == "blocking" {
        final_verdict = "BLOCK";
        break;
    }
}

md += "**Verdict:** " + final_verdict + "\n\n";
md += "**Headline:** " + headline + "\n\n";
md += "## Scope\n\n" + scope_summary + "\n\n";
md += "### Files\n\n" + file_list + "\n";
md += "### Risk areas\n\n" + risk_list + "\n";
if scope_notes != "" {
    md += "### Scoper notes\n\n" + scope_notes + "\n\n";
}

md += "## Blocking\n\n";
if blocking_lines.len() == 0 {
    md += "_None._\n\n";
} else {
    for b in blocking_lines { md += "- " + b + "\n"; }
    md += "\n";
}

md += "## Warnings\n\n";
if warning_lines.len() == 0 {
    md += "_None._\n\n";
} else {
    for w in warning_lines { md += "- " + w + "\n"; }
    md += "\n";
}

md += "## Confirmed evidence\n\n" + confirmed_blob + "\n";
md += "## What looks good\n\n" + clean_line + "\n\n";
md += "## Next steps\n\n";
if next_steps.len() == 0 {
    md += "- None listed.\n";
} else {
    for n in next_steps { md += "- " + n + "\n"; }
}
md += "\n## Coverage stats\n\n";
md += "- raw findings: " + findings.len().to_string() + "\n";
md += "- verified slots: " + to_verify.len().to_string() + "\n";
md += "- confirmed: " + confirmed.len().to_string() + "\n";
md += "- review failures: " + review_fail.to_string() + "\n";
md += "- verify unusable: " + unverified.to_string() + "\n";
if dropped > 0 {
    md += "- dropped past cap: " + dropped.to_string() + "\n";
}

let report_path = write_scratch_file("preflight-report.md", md);
log("Preflight complete: " + final_verdict);

complete(#{
    path: report_path,
    verdict: final_verdict,
    headline: headline,
    confirmed: confirmed.len(),
    raw_findings: findings.len(),
    review_failures: review_fail,
    verify_unusable: unverified,
});
