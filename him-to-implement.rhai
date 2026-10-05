let meta = #{
    name: "him-to-implement",
    description: "Universal HIM audit: prove failure points with real tests, write codex+handoff, then hands-off implement-from-plan (auto plan, implement, verify, fix)",
    when_to_use: "Any repo: send HIM in on a target/diff, require evidence+tests before fixes, then automatically implement confirmed findings without human gates",
    phases: [
        #{ title: "Scope", detail: "map surface and risk domains" },
        #{ title: "Hunt", detail: "HIM parallel domain scan — candidates only" },
        #{ title: "Prove", detail: "create/run tests for each candidate; fail closed" },
        #{ title: "Codex", detail: "write HIM codex + implement-from-plan handoff source" },
        #{ title: "Plan", detail: "hands-off process file from proven findings" },
        #{ title: "Implement", detail: "execute process steps" },
        #{ title: "Verify", detail: "build/unit checks against acceptance" },
        #{ title: "Fix", detail: "bounded fix+retest until green or cap" },
        #{ title: "Gate", detail: "fail-closed complete only with proven fixes" },
    ],
};

// --- schemas -----------------------------------------------------------------

let scope_schema = #{
    "type": "object",
    "required": ["summary", "files", "risk_domains", "test_entrypoints", "notes"],
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
        "risk_domains": #{
            "type": "array",
            "maxItems": 12,
            "items": #{ "type": "string" },
        },
        "test_entrypoints": #{
            "type": "array",
            "maxItems": 20,
            "items": #{ "type": "string" },
        },
        "notes": #{ "type": "string" },
    },
};

let candidates_schema = #{
    "type": "object",
    "required": ["candidates"],
    "properties": #{
        "candidates": #{
            "type": "array",
            "maxItems": 6,
            "items": #{
                "type": "object",
                "required": ["id", "title", "file", "domain", "hypothesis", "how_to_test", "severity_guess"],
                "properties": #{
                    "id": #{ "type": "string" },
                    "title": #{ "type": "string" },
                    "file": #{ "type": "string" },
                    "domain": #{ "type": "string" },
                    "hypothesis": #{ "type": "string" },
                    "how_to_test": #{ "type": "string" },
                    "severity_guess": #{ "type": "string" },
                },
            },
        },
    },
};

let prove_schema = #{
    "type": "object",
    "required": [
        "candidate_id",
        "proven",
        "severity",
        "evidence",
        "test_commands",
        "tests_created",
        "repro_steps",
        "reason",
        "fix_guidance",
    ],
    "properties": #{
        "candidate_id": #{ "type": "string" },
        "proven": #{ "type": "boolean" },
        "severity": #{ "type": "string" },
        "evidence": #{ "type": "string" },
        "test_commands": #{
            "type": "array",
            "maxItems": 12,
            "items": #{ "type": "string" },
        },
        "tests_created": #{
            "type": "array",
            "maxItems": 12,
            "items": #{ "type": "string" },
        },
        "repro_steps": #{ "type": "string" },
        "reason": #{ "type": "string" },
        "fix_guidance": #{ "type": "string" },
    },
};

let plan_schema = #{
    "type": "object",
    "required": ["plan_path", "goal", "step_count", "steps", "done_criteria", "test_strategy", "notes"],
    "properties": #{
        "plan_path": #{ "type": "string" },
        "goal": #{ "type": "string" },
        "step_count": #{ "type": "integer" },
        "steps": #{
            "type": "array",
            "maxItems": 30,
            "items": #{
                "type": "object",
                "required": ["id", "title", "actions", "acceptance", "status"],
                "properties": #{
                    "id": #{ "type": "string" },
                    "title": #{ "type": "string" },
                    "actions": #{ "type": "string" },
                    "acceptance": #{ "type": "string" },
                    "status": #{ "type": "string" },
                },
            },
        },
        "done_criteria": #{
            "type": "array",
            "maxItems": 20,
            "items": #{ "type": "string" },
        },
        "test_strategy": #{ "type": "string" },
        "notes": #{ "type": "string" },
    },
};

let implement_schema = #{
    "type": "object",
    "required": ["summary", "steps_done", "steps_blocked", "files_changed", "plan_updated", "remaining"],
    "properties": #{
        "summary": #{ "type": "string" },
        "steps_done": #{
            "type": "array",
            "maxItems": 30,
            "items": #{ "type": "string" },
        },
        "steps_blocked": #{
            "type": "array",
            "maxItems": 20,
            "items": #{
                "type": "object",
                "required": ["id", "reason"],
                "properties": #{
                    "id": #{ "type": "string" },
                    "reason": #{ "type": "string" },
                },
            },
        },
        "files_changed": #{
            "type": "array",
            "maxItems": 60,
            "items": #{ "type": "string" },
        },
        "plan_updated": #{ "type": "boolean" },
        "remaining": #{ "type": "string" },
    },
};

let test_schema = #{
    "type": "object",
    "required": ["passed", "commands_run", "summary", "failures", "evidence"],
    "properties": #{
        "passed": #{ "type": "boolean" },
        "commands_run": #{
            "type": "array",
            "maxItems": 20,
            "items": #{ "type": "string" },
        },
        "summary": #{ "type": "string" },
        "failures": #{
            "type": "array",
            "maxItems": 30,
            "items": #{ "type": "string" },
        },
        "evidence": #{ "type": "string" },
    },
};

let fix_schema = #{
    "type": "object",
    "required": ["summary", "fixed", "files_changed", "plan_updated", "still_failing"],
    "properties": #{
        "summary": #{ "type": "string" },
        "fixed": #{
            "type": "array",
            "maxItems": 30,
            "items": #{ "type": "string" },
        },
        "files_changed": #{
            "type": "array",
            "maxItems": 40,
            "items": #{ "type": "string" },
        },
        "plan_updated": #{ "type": "boolean" },
        "still_failing": #{ "type": "string" },
    },
};

let gate_schema = #{
    "type": "object",
    "required": ["complete", "verdict", "headline", "unmet_criteria", "next_steps"],
    "properties": #{
        "complete": #{ "type": "boolean" },
        "verdict": #{ "type": "string" },
        "headline": #{ "type": "string" },
        "unmet_criteria": #{
            "type": "array",
            "maxItems": 20,
            "items": #{ "type": "string" },
        },
        "next_steps": #{
            "type": "array",
            "maxItems": 12,
            "items": #{ "type": "string" },
        },
    },
};

// --- helpers -----------------------------------------------------------------

fn trimmed(s) {
    if type_of(s) == "string" {
        s.trim();
        s
    } else {
        ""
    }
}

fn join_lines(items, prefix) {
    let out = "";
    if items == () { return out; }
    for it in items {
        if it != () {
            let t = trimmed(it.to_string());
            if t != "" {
                out += prefix + t + "\n";
            }
        }
    }
    out
}

fn bool_arg(v, default_val) {
    if v == () { return default_val; }
    if type_of(v) == "bool" { return v; }
    let s = trimmed(v.to_string());
    if s == "true" || s == "1" || s == "yes" || s == "on" { return true; }
    if s == "false" || s == "0" || s == "no" || s == "off" { return false; }
    default_val
}

// Accept JSON numbers or numeric strings so stringly CLI args clamp correctly.
fn int_arg(v, default_val, min_v, max_v) {
    let n = default_val;
    if v == () {
    } else if type_of(v) == "i64" || type_of(v) == "int" {
        n = v;
    } else {
        let s = trimmed(v.to_string());
        let acc = 0;
        let digits = 0;
        let i = 0;
        let len = s.len();
        while i < len {
            let ch = s[i];
            if ch == '0' { acc = acc * 10; digits += 1; }
            else if ch == '1' { acc = acc * 10 + 1; digits += 1; }
            else if ch == '2' { acc = acc * 10 + 2; digits += 1; }
            else if ch == '3' { acc = acc * 10 + 3; digits += 1; }
            else if ch == '4' { acc = acc * 10 + 4; digits += 1; }
            else if ch == '5' { acc = acc * 10 + 5; digits += 1; }
            else if ch == '6' { acc = acc * 10 + 6; digits += 1; }
            else if ch == '7' { acc = acc * 10 + 7; digits += 1; }
            else if ch == '8' { acc = acc * 10 + 8; digits += 1; }
            else if ch == '9' { acc = acc * 10 + 9; digits += 1; }
            else { digits = 0; break; }
            i += 1;
        }
        if digits > 0 { n = acc; }
    }
    if n < min_v { n = min_v; }
    if n > max_v { n = max_v; }
    n
}

// --- args --------------------------------------------------------------------
// Guard args first: property access on unit is a runtime error.

let target = if args == () { () } else { args.target };
let focus = if args == () { () } else { args.focus };
let codex_path_arg = if args == () { () } else { args.codex_path };
let handoff_path_arg = if args == () { () } else { args.handoff_path };
let plan_path_arg = if args == () { () } else { args.plan_path };
let test_cmd_arg = if args == () { () } else { args.test_command };
if test_cmd_arg == () && args != () { test_cmd_arg = args.test; }

// Hands-off implement after proven findings (default true).
// Workflows cannot launch other workflows — implement-from-plan logic is inlined.
let do_implement = bool_arg(if args == () { () } else { args.implement }, true);
// Low severity: report only, never promote to fix plan (HIM rule).
let fix_low = bool_arg(if args == () { () } else { args.fix_low }, false);

let max_fix = int_arg(if args == () { () } else { args.max_fix_rounds }, 3, 1, 5);

const MAX_PROVE = 8;

let target_desc = if target == () || trimmed(target.to_string()) == "" {
    "the current uncommitted working tree vs HEAD (git status + git diff + staged). If clean, scan the highest-risk product surfaces discoverable from README/docs/entrypoints."
} else {
    "target: " + trimmed(target.to_string())
};

let focus_note = if focus == () || trimmed(focus.to_string()) == "" {
    ""
} else {
    " Extra focus (still stay in-scope): " + trimmed(focus.to_string()) + "."
};

let codex_path = if codex_path_arg == () || trimmed(codex_path_arg.to_string()) == "" {
    ".grok/him-codex.md"
} else {
    trimmed(codex_path_arg.to_string())
};

let handoff_path = if handoff_path_arg == () || trimmed(handoff_path_arg.to_string()) == "" {
    "HIM_IMPLEMENT_HANDOFF.md"
} else {
    trimmed(handoff_path_arg.to_string())
};

let plan_path = if plan_path_arg == () || trimmed(plan_path_arg.to_string()) == "" {
    "IMPLEMENTATION_PROCESS.md"
} else {
    trimmed(plan_path_arg.to_string())
};

let test_hint = if test_cmd_arg == () || trimmed(test_cmd_arg.to_string()) == "" {
    "Discover the repo's normal test/build path (pytest, cargo test, npm test, go test, dotnet test, make test, project scripts under tools/ or tests/). Prefer the fastest meaningful check for the change."
} else {
    "Prefer this test command when applicable: " + trimmed(test_cmd_arg.to_string())
};

// --- Phase 1: Scope ----------------------------------------------------------

phase("Scope");
log("HIM scope: " + target_desc);

let scope_prompt = "";
scope_prompt += "You are the SCOPER for a universal HIM (hardening) pipeline on the current repository.\n";
scope_prompt += "Any language/stack. Working directory is the repo root.\n";
scope_prompt += "Target: " + target_desc + "\n";
scope_prompt += focus_note + "\n";
scope_prompt += "REQUIRED method — use tools, do not invent:\n";
scope_prompt += "1) Map the change set or named surface with git status/diff and/or list_dir/read_file/grep.\n";
scope_prompt += "2) Identify risk_domains from: correctness, security, economy/progression, balance, robustness/persistence, api, ui, tests.\n";
scope_prompt += "3) Discover test_entrypoints: existing test files, scripts, package scripts, CI job names, tools/*audit*, Makefile targets.\n";
scope_prompt += "4) Empty files is valid only after you inspected and found a clean tree AND you still listed primary product surfaces in notes.\n";
scope_prompt += "Return summary, files[{path,change}], risk_domains, test_entrypoints, notes.\n";
scope_prompt += "Never paste secrets from diffs.\n";

let scope_r = agent(scope_prompt, #{
    label: "scope",
    capability_mode: "execute",
    output_schema: scope_schema,
});

if scope_r == () || !scope_r.success || scope_r.output == () {
    pause("infra", "Scope agent failed. Resume to retry, or re-run with clearer args.target.");
}

let scope = scope_r.output;
let scope_summary = if scope.summary != () { scope.summary } else { "(no summary)" };
let scope_notes = if scope.notes != () { scope.notes } else { "" };

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
if file_list == "" { file_list = "(no files listed — may be clean tree or whole-surface scan)\n"; }

let risk_list = "";
if scope.risk_domains != () {
    for ra in scope.risk_domains {
        risk_list += "- " + ra + "\n";
    }
}
if risk_list == "" { risk_list = "- correctness\n- robustness\n- security\n"; }

let tests_list = "";
if scope.test_entrypoints != () {
    for te in scope.test_entrypoints {
        tests_list += "- " + te + "\n";
    }
}
if tests_list == "" { tests_list = "- (none discovered — provers must create minimal repro tests)\n"; }

log("Scope: " + scope_summary);

// --- Phase 2: Hunt (candidates only — not Findings yet) ----------------------

phase("Hunt");
log("HIM hunt: candidates only (must be proven later)");

// Fixed universal HIM domains (skill-aligned). Not every domain will hit.
let domains = [
    #{
        id: "correctness",
        title: "correctness and logic breaks",
        brief: "Crash paths, wrong defaults, stuck states, off-by-one, silent failures, incomplete cleanup, dead branches that look live. Whole-function review of files you open.",
    },
    #{
        id: "security",
        title: "security and trust boundaries",
        brief: "Injection, path traversal, authz bypass, secrets in logs, unsafe deserialization, privilege escalation. Skip theoretical multi-user issues if this is clearly a local single-player tool unless focus demands it.",
    },
    #{
        id: "economy",
        title: "economy, progression, and game-system exploits",
        brief: "Loot/XP/quest/trade duplication, infinite resource loops, double-complete, arbitrage. Only if the repo has those systems. Do not invent economy design complaints.",
    },
    #{
        id: "robustness",
        title: "robustness, persistence, and re-entry",
        brief: "Partial writes, save/load desync, re-entry, concurrent edit hazards, network drop mid-action, missing error paths on I/O.",
    },
    #{
        id: "tests_gaps",
        title: "missing regression protection for risky paths",
        brief: "Risky code paths in scope with no test that could catch a real break. Propose candidates only when you can describe a concrete failing scenario to prove — not 'needs more tests' fluff.",
    },
];

let hunt_jobs = [];
for d in domains {
    let p = "";
    p += "You are HIM HUNTER for domain: " + d.title + " (" + d.id + ").\n";
    p += "HIM rules: neutral start — surface is clean until a check can prove otherwise. Do NOT invent issues.\n";
    p += "You report CANDIDATES only. Candidates are NOT findings until the Prove phase runs real tests.\n";
    p += "Scope summary: " + scope_summary + "\n";
    p += "Files:\n" + file_list;
    p += "Risk domains:\n" + risk_list;
    p += "Known test entrypoints:\n" + tests_list;
    p += "Scoper notes: " + scope_notes + "\n";
    p += focus_note + "\n";
    p += "Focus brief: " + d.brief + "\n";
    p += "REQUIRED method:\n";
    p += "1) Use git diff / read_file / grep. Read entire functions you inspect. Do not answer from memory.\n";
    p += "2) For each candidate: concrete hypothesis + how_to_test (command, script, or minimal new test idea).\n";
    p += "3) severity_guess: critical|high|med|low — only a guess; Prove will re-grade with evidence.\n";
    p += "4) domain must be exactly: " + d.id + "\n";
    p += "5) id: short stable slug like " + d.id + "-1\n";
    p += "6) Empty candidates is VALID and PREFERRED when nothing looks broken. Do not pad.\n";
    p += "7) Intentional design is not a candidate. Style/naming/polish is not a candidate.\n";
    p += "8) Max 6 candidates. Prefer fewer high-signal ones.\n";
    hunt_jobs.push(#{
        prompt: p,
        label: "hunt:" + d.id,
        capability_mode: "execute",
        output_schema: candidates_schema,
    });
}

let hunt_results = parallel(hunt_jobs);

let candidates = [];
let hunt_fail = 0;
let hi = 0;
for r in hunt_results {
    if r == () || !r.success || r.output == () || r.output.candidates == () {
        hunt_fail += 1;
    } else {
        for c in r.output.candidates {
            let cid = if c.id != () { trimmed(c.id) } else { "" };
            let title = if c.title != () { trimmed(c.title) } else { "" };
            let file = if c.file != () { trimmed(c.file) } else { "?" };
            let hyp = if c.hypothesis != () { trimmed(c.hypothesis) } else { "" };
            let how = if c.how_to_test != () { trimmed(c.how_to_test) } else { "" };
            let sev = if c.severity_guess != () { trimmed(c.severity_guess) } else { "med" };
            let dom = if c.domain != () && trimmed(c.domain) != "" {
                trimmed(c.domain)
            } else if hi < domains.len() {
                domains[hi].id
            } else {
                "unknown"
            };
            if title != "" && hyp != "" && how != "" {
                if cid == "" { cid = dom + "-" + candidates.len().to_string(); }
                candidates.push(#{
                    id: cid,
                    title: title,
                    file: file,
                    domain: dom,
                    hypothesis: hyp,
                    how_to_test: how,
                    severity_guess: sev,
                });
            }
        }
    }
    hi += 1;
}

if hunt_fail > 0 {
    log(hunt_fail.to_string() + " hunt domain(s) failed or returned unusable output");
}
log(candidates.len().to_string() + " candidate(s) before prove cap");

// Cap prove fan-out
let to_prove = [];
let dropped = 0;
let ci = 0;
for c in candidates {
    if ci < MAX_PROVE {
        to_prove.push(c);
    } else {
        dropped += 1;
    }
    ci += 1;
}
if dropped > 0 {
    log("Dropped " + dropped.to_string() + " candidate(s) past MAX_PROVE=" + MAX_PROVE.to_string());
}

// --- Phase 3: Prove (mandatory tests before Finding) -------------------------

let proven = [];
let disproven = [];
let prove_unusable = 0;

if to_prove.len() == 0 {
    phase("Prove");
    log("No candidates — surface treated as clean (no invent)");
} else {
    phase("Prove");
    log("Proving " + to_prove.len().to_string() + " candidate(s) with real tests");

    let pjobs = [];
    let pi = 0;
    for c in to_prove {
        let pp = "";
        pp += "You are HIM PROVER. Fail closed. proven=true ONLY with observed failure evidence from a real check you ran or a minimal test you created and ran.\n";
        pp += "Candidate:\n";
        pp += "- id: " + c.id + "\n";
        pp += "- title: " + c.title + "\n";
        pp += "- file: " + c.file + "\n";
        pp += "- domain: " + c.domain + "\n";
        pp += "- severity_guess: " + c.severity_guess + "\n";
        pp += "- hypothesis: " + c.hypothesis + "\n";
        pp += "- suggested how_to_test: " + c.how_to_test + "\n";
        pp += "Scope: " + scope_summary + "\n";
        pp += "Known test entrypoints:\n" + tests_list;
        pp += "Test hint: " + test_hint + "\n";
        pp += "HIM evidence bar — proven=true requires at least one of:\n";
        pp += "1) Observed failure (test fail, exception, wrong API/DB/UI state)\n";
        pp += "2) Reproducible exploit path you actually exercised\n";
        pp += "3) Contradiction with explicit project rule that you demonstrated matters in practice\n";
        pp += "NOT enough: style, theoretical future risk, design taste, untested hunches.\n";
        pp += "REQUIRED method:\n";
        pp += "1) read_file the suspect code (whole function/module).\n";
        pp += "2) Prefer existing tests/scripts. If none cover the failure point, CREATE a minimal focused test or small script under the repo's normal test layout (or tools/ if that is the convention). Keep it small and deterministic.\n";
        pp += "3) RUN the test/command via shell. Capture exit codes and key output in evidence.\n";
        pp += "4) If you cannot run the toolchain, proven=false and explain under reason — do not claim proven.\n";
        pp += "5) If the check PASSES and the bug does not repro: proven=false (disproven). That is a successful HIM outcome.\n";
        pp += "6) If proven=true: severity critical|high|med|low; fix_guidance is the minimal correct fix direction (not a full patch essay); repro_steps concrete; tests_created lists new files; test_commands lists what you ran.\n";
        pp += "7) Do NOT implement product fixes in this phase — only tests/repro harnesses. Fixing is later.\n";
        pp += "8) candidate_id must echo: " + c.id + "\n";
        pjobs.push(#{
            prompt: pp,
            label: "prove:" + pi.to_string() + ":" + c.id,
            capability_mode: "all",
            output_schema: prove_schema,
        });
        pi += 1;
    }

    let prove_results = parallel(pjobs);

    let pii = 0;
    for pr in prove_results {
        if pii >= to_prove.len() { break; }
        let base = to_prove[pii];
        if pr == () || !pr.success || pr.output == () {
            prove_unusable += 1;
        } else {
            let o = pr.output;
            let evidence = if o.evidence != () { trimmed(o.evidence) } else { "" };
            let reason = if o.reason != () { trimmed(o.reason) } else { "" };
            let sev = if o.severity != () && trimmed(o.severity) != "" {
                trimmed(o.severity)
            } else {
                base.severity_guess
            };
            let fix_g = if o.fix_guidance != () { trimmed(o.fix_guidance) } else { "" };
            let repro = if o.repro_steps != () { trimmed(o.repro_steps) } else { "" };
            let cmds = join_lines(o.test_commands, "- ");
            let created = join_lines(o.tests_created, "- ");

            // Fail closed: proven requires true + non-empty evidence
            if o.proven == true && evidence != "" {
                // Optional: skip low unless fix_low
                let is_low = (sev == "low");
                if is_low && !fix_low {
                    disproven.push(#{
                        id: base.id,
                        title: base.title,
                        file: base.file,
                        domain: base.domain,
                        reason: "proven low severity — report only (fix_low=false): " + reason,
                        evidence: evidence,
                    });
                } else {
                    proven.push(#{
                        id: base.id,
                        title: base.title,
                        file: base.file,
                        domain: base.domain,
                        severity: sev,
                        hypothesis: base.hypothesis,
                        evidence: evidence,
                        repro_steps: repro,
                        fix_guidance: fix_g,
                        test_commands: cmds,
                        tests_created: created,
                        reason: reason,
                    });
                }
            } else {
                disproven.push(#{
                    id: base.id,
                    title: base.title,
                    file: base.file,
                    domain: base.domain,
                    reason: if reason != "" { reason } else { "not proven / empty evidence" },
                    evidence: evidence,
                });
            }
        }
        pii += 1;
    }

    log(proven.len().to_string() + " proven finding(s); "
        + disproven.len().to_string() + " disproven/report-only; "
        + prove_unusable.to_string() + " prove slot(s) unusable");
}

// --- Phase 4: Codex + handoff source -----------------------------------------

phase("Codex");
log("Writing codex + implement handoff");

let codex_prompt = "";
codex_prompt += "You are HIM CODEX WRITER for a universal pipeline. Write durable files on disk with tools.\n";
codex_prompt += "Codex path (create/append session block): " + codex_path + "\n";
codex_prompt += "Handoff path (OVERWRITE — this is the implement-from-plan source): " + handoff_path + "\n";
codex_prompt += "Scope summary: " + scope_summary + "\n";
codex_prompt += "Files:\n" + file_list;
codex_prompt += "Risk domains:\n" + risk_list;
codex_prompt += "Test entrypoints:\n" + tests_list;
codex_prompt += "Scoper notes: " + scope_notes + "\n";

// Proven blob
let proven_blob = "";
let bi = 0;
for f in proven {
    bi += 1;
    proven_blob += bi.to_string() + ". [" + f.severity + "] (" + f.domain + ") " + f.id + " — " + f.title + "\n";
    proven_blob += "   file: " + f.file + "\n";
    proven_blob += "   hypothesis: " + f.hypothesis + "\n";
    proven_blob += "   evidence: " + f.evidence + "\n";
    proven_blob += "   repro: " + f.repro_steps + "\n";
    proven_blob += "   fix_guidance: " + f.fix_guidance + "\n";
    proven_blob += "   tests_created:\n" + f.tests_created;
    proven_blob += "   test_commands:\n" + f.test_commands;
    proven_blob += "\n";
}
if proven_blob == "" { proven_blob = "(none — clean bill of health)\n"; }

let disproven_blob = "";
let di = 0;
for d in disproven {
    di += 1;
    disproven_blob += di.to_string() + ". " + d.id + " — " + d.title + " (" + d.file + ")\n";
    disproven_blob += "   reason: " + d.reason + "\n";
    if d.evidence != () && d.evidence != "" {
        disproven_blob += "   notes: " + d.evidence + "\n";
    }
    disproven_blob += "\n";
}
if disproven_blob == "" { disproven_blob = "(none)\n"; }

codex_prompt += "PROVEN findings (only these are Findings):\n" + proven_blob;
codex_prompt += "DISPROVEN / not fixed:\n" + disproven_blob;
codex_prompt += "Stats: candidates=" + candidates.len().to_string();
codex_prompt += " proven=" + proven.len().to_string();
codex_prompt += " disproven=" + disproven.len().to_string();
codex_prompt += " hunt_fail=" + hunt_fail.to_string();
codex_prompt += " prove_unusable=" + prove_unusable.to_string() + "\n";
codex_prompt += "REQUIRED files:\n";
codex_prompt += "A) Codex markdown structure:\n";
codex_prompt += "# HIM Codex — session\n## Scope\n## Checked\n## Findings (or None)\n## Fixes (None until implement)\n## Tests / simulations\n## Still open (unverified only)\n";
codex_prompt += "If " + codex_path + " exists, APPEND a new session section rather than destroying history when possible.\n";
codex_prompt += "B) Handoff file " + handoff_path + " must be a self-contained implement-from-plan SOURCE:\n";
codex_prompt += "# HIM Implement Handoff\n## Goal\nFix only proven HIM findings; do not invent work if Findings are None.\n";
codex_prompt += "## Proven findings\n(each: severity, file, evidence, repro, fix guidance, tests to keep green)\n";
codex_prompt += "## Constraints\n- Evidence-only: do not expand into polish or redesign\n";
codex_prompt += "- Keep and extend tests created during Prove; add regression coverage for each fix\n";
codex_prompt += "- Match project conventions; atomic buildable changes\n";
codex_prompt += "- Low severity: report-only unless already included\n";
codex_prompt += "## Test strategy\n" + test_hint + "\n";
codex_prompt += "## Acceptance\n- Each proven finding fixed OR explicitly blocked with product reason\n";
codex_prompt += "- All prove tests + project suite relevant to change pass\n";
codex_prompt += "- Codex Fixes section can be updated after implement\n";
codex_prompt += "If ZERO proven findings: handoff still written stating clean bill; Goal = no product code changes required.\n";
codex_prompt += "Return a short plain-text summary of what you wrote (paths + finding count). Use tools to write both files.\n";

let codex_r = agent(codex_prompt, #{
    label: "codex",
    capability_mode: "all",
});

let codex_summary = "(codex agent failed)";
if codex_r != () && codex_r.success && codex_r.output != () {
    codex_summary = trimmed(codex_r.output.to_string());
    if codex_summary == "" { codex_summary = "codex wrote files"; }
}
log("Codex: " + codex_summary);

// Scratch report early state
let early_md = "";
early_md += "# HIM → implement report (partial)\n\n";
early_md += "**Scope:** " + scope_summary + "\n\n";
early_md += "**Proven:** " + proven.len().to_string() + "\n\n";
early_md += "## Proven\n\n" + proven_blob + "\n";
early_md += "## Disproven\n\n" + disproven_blob + "\n";
early_md += "## Handoff\n\n`" + handoff_path + "`\n\n";
early_md += "## Codex\n\n`" + codex_path + "`\n";
let early_path = write_scratch_file("him-partial.md", early_md);

// Clean path: no proven findings → complete without implement
if proven.len() == 0 {
    phase("Gate");
    let clean_md = "";
    clean_md += "# HIM → implement report\n\n";
    clean_md += "**Verdict:** CLEAN\n\n";
    clean_md += "**Headline:** No evidence-backed defects after hunt+prove. No product fixes required.\n\n";
    clean_md += "## Scope\n\n" + scope_summary + "\n\n";
    clean_md += "### Files\n\n" + file_list + "\n";
    clean_md += "### Risk domains\n\n" + risk_list + "\n";
    clean_md += "## Candidates hunted\n\n" + candidates.len().to_string() + "\n\n";
    clean_md += "## Proven findings\n\n_None._\n\n";
    clean_md += "## Disproven / not fixed\n\n" + disproven_blob + "\n";
    clean_md += "## Artifacts\n\n- codex: `" + codex_path + "`\n- handoff: `" + handoff_path + "`\n";
    clean_md += "\n## Coverage\n\n";
    clean_md += "- hunt failures: " + hunt_fail.to_string() + "\n";
    clean_md += "- prove unusable: " + prove_unusable.to_string() + "\n";
    clean_md += "- dropped past cap: " + dropped.to_string() + "\n";
    clean_md += "\n## Next steps\n\n";
    clean_md += "- Review `" + codex_path + "`\n";
    clean_md += "- No implement-from-plan run required (nothing proven to fix)\n";
    if !do_implement {
        clean_md += "- implement was disabled via args.implement=false\n";
    }
    let report_path = write_scratch_file("him-to-implement-report.md", clean_md);
    log("HIM CLEAN — skipping implement");
    complete(#{
        path: report_path,
        verdict: "CLEAN",
        complete: true,
        proven: 0,
        disproven: disproven.len(),
        handoff_path: handoff_path,
        codex_path: codex_path,
        implement_ran: false,
        headline: "No proven findings — clean bill of health",
        // Compatible args if user still wants to force implement-from-plan
        implement_from_plan_args: #{
            sources: [handoff_path, codex_path],
            goal: "No product fixes required (HIM clean). Only update docs if handoff says so.",
            auto_approve_plan: true,
            plan_path: plan_path,
        },
    });
}

if !do_implement {
    phase("Gate");
    let ho_md = "";
    ho_md += "# HIM → implement report\n\n";
    ho_md += "**Verdict:** HANDOFF_ONLY\n\n";
    ho_md += "**Headline:** Proven findings written; implement skipped (args.implement=false).\n\n";
    ho_md += "## Proven\n\n" + proven_blob + "\n";
    ho_md += "## Next: run implement-from-plan hands-off\n\n";
    ho_md += "```\n";
    ho_md += "/workflow implement-from-plan with sources=[" + handoff_path + ", " + codex_path + "] auto_approve_plan=true\n";
    ho_md += "```\n";
    let report_path = write_scratch_file("him-to-implement-report.md", ho_md);
    log("Handoff only — user must run implement-from-plan");
    complete(#{
        path: report_path,
        verdict: "HANDOFF_ONLY",
        complete: false,
        proven: proven.len(),
        disproven: disproven.len(),
        handoff_path: handoff_path,
        codex_path: codex_path,
        implement_ran: false,
        headline: "Handoff ready for implement-from-plan",
        implement_from_plan_args: #{
            sources: [handoff_path, codex_path],
            goal: "Fix only proven HIM findings in " + handoff_path + ". Keep prove tests green. No invented scope.",
            auto_approve_plan: true,
            plan_path: plan_path,
        },
    });
}

// --- Phase 5: Plan (hands-off — no await_user) -------------------------------
// Workflows cannot nest; this is the inlined implement-from-plan Plan+… path.

phase("Plan");
log("Hands-off plan from " + handoff_path);

let plan_prompt = "";
plan_prompt += "You are the PLANNER for hands-off implement-from-plan after HIM prove.\n";
plan_prompt += "Write a durable PROCESS FILE that implement/verify agents will execute.\n";
plan_prompt += "Process file path (WRITE with tools): " + plan_path + "\n";
plan_prompt += "MUST read fully with read_file:\n- " + handoff_path + "\n- " + codex_path + " (if exists)\n";
plan_prompt += "Proven findings (source of truth for scope):\n" + proven_blob;
plan_prompt += "User/system goal: Fix ONLY proven HIM findings. Do not invent polish. Keep prove-created tests.\n";
plan_prompt += "Scope summary: " + scope_summary + "\n";
plan_prompt += "Test hint: " + test_hint + "\n";
plan_prompt += "REQUIRED file format (markdown):\n";
plan_prompt += "# Implementation Process\n## Goal\n## Sources\n## Context\n## Constraints\n";
plan_prompt += "## Steps\n### Step N: title\n- Status: pending\n- Actions: ...\n- Acceptance: ...\n- Verify: ...\n";
plan_prompt += "## Done criteria\n- [ ] each proven finding fixed or blocked\n- [ ] prove tests still pass\n- [ ] project tests for touch area pass\n";
plan_prompt += "## Test strategy\n## Verification log\n";
plan_prompt += "Rules: 3–15 ordered steps; every step Status pending; include a step to update " + codex_path + " Fixes section after code changes; ";
plan_prompt += "include regression tests for each fix; no architecture rewrites unless a proven finding requires it.\n";
plan_prompt += "Return structured steps mirroring the file, plan_path, goal, step_count, done_criteria, test_strategy, notes.\n";

let plan_r = agent(plan_prompt, #{
    label: "plan",
    capability_mode: "all",
    output_schema: plan_schema,
});

if plan_r == () || !plan_r.success || plan_r.output == () {
    pause("infra", "Plan agent failed. Resume to retry. Handoff already at " + handoff_path);
}

let plan = plan_r.output;
let written_plan = if plan.plan_path != () && trimmed(plan.plan_path) != "" {
    trimmed(plan.plan_path)
} else {
    plan_path
};
let plan_goal = if plan.goal != () { plan.goal } else {
    "Fix proven HIM findings from " + handoff_path
};
let step_count = if plan.step_count != () { plan.step_count } else { 0 };
let test_strategy = if plan.test_strategy != () { plan.test_strategy } else { test_hint };

let steps_blob = "";
if plan.steps != () {
    for st in plan.steps {
        let sid = if st.id != () { st.id } else { "?" };
        let title = if st.title != () { st.title } else { "" };
        let actions = if st.actions != () { st.actions } else { "" };
        let acc = if st.acceptance != () { st.acceptance } else { "" };
        steps_blob += "- " + sid + ": " + title + "\n  actions: " + actions + "\n  acceptance: " + acc + "\n";
    }
}
if steps_blob == "" { steps_blob = "(no structured steps — implementer must read process file)\n"; }

let done_blob = join_lines(plan.done_criteria, "- ");
if done_blob == "" {
    done_blob = "- Proven findings fixed\n- Prove tests pass\n- Project tests green for touch area\n";
}

log("Process file: " + written_plan + " (" + step_count.to_string() + " steps) — auto-approved");

// --- Phase 6: Implement ------------------------------------------------------

phase("Implement");
log("Implementing from " + written_plan);

let impl_prompt = "";
impl_prompt += "You are the IMPLEMENTER for hands-off HIM fixes (implement-from-plan style).\n";
impl_prompt += "Execute the process file. Do not freestyle unrelated refactors.\n";
impl_prompt += "Process file: " + written_plan + "\n";
impl_prompt += "Handoff: " + handoff_path + "\n";
impl_prompt += "Codex: " + codex_path + "\n";
impl_prompt += "Goal: " + plan_goal + "\n";
impl_prompt += "Proven findings:\n" + proven_blob;
impl_prompt += "Structured steps (re-read file for truth):\n" + steps_blob;
impl_prompt += "REQUIRED:\n";
impl_prompt += "1) read_file process file + handoff + relevant source.\n";
impl_prompt += "2) Fix root causes for proven findings only. Keep prove tests; extend if needed.\n";
impl_prompt += "3) Update process file statuses as you go.\n";
impl_prompt += "4) Update " + codex_path + " Fixes section with what changed.\n";
impl_prompt += "5) Atomic, buildable changes. Match project style.\n";
impl_prompt += "6) Do not declare complete — verification is next.\n";
impl_prompt += "Return steps_done, steps_blocked, files_changed, plan_updated, remaining, summary.\n";

let impl_r = agent(impl_prompt, #{
    label: "implement",
    capability_mode: "all",
    output_schema: implement_schema,
});

let impl_summary = "(implement agent failed)";
let files_changed_blob = "";
let steps_done_blob = "";
let blocked_blob = "";
let remaining = "";
let impl_ok = false;

if impl_r != () && impl_r.success && impl_r.output != () {
    impl_ok = true;
    let io = impl_r.output;
    if io.summary != () { impl_summary = io.summary; }
    if io.remaining != () { remaining = io.remaining; }
    steps_done_blob = join_lines(io.steps_done, "- ");
    files_changed_blob = join_lines(io.files_changed, "- ");
    if io.steps_blocked != () {
        for b in io.steps_blocked {
            let id = if b.id != () { b.id } else { "?" };
            let reason = if b.reason != () { b.reason } else { "?" };
            blocked_blob += "- " + id + ": " + reason + "\n";
        }
    }
}
if steps_done_blob == "" { steps_done_blob = "- (none reported)\n"; }
if files_changed_blob == "" { files_changed_blob = "- (none reported)\n"; }
if blocked_blob == "" { blocked_blob = "- (none)\n"; }

if !impl_ok {
    log("Implement agent failed — verify/fix may still recover");
} else {
    log("Implement: " + impl_summary);
}

// --- Phase 7+8: Verify / Fix loop --------------------------------------------

let tests_passed = false;
let last_test_summary = "";
let last_failures_blob = "";
let last_evidence = "";
let last_commands_blob = "";
let fix_round = 0;
let fix_summaries = "";
let attempt = 0;
let max_attempts = max_fix + 1;

while attempt < max_attempts {
    attempt += 1;
    phase("Verify");
    log("Verify attempt " + attempt.to_string() + "/" + max_attempts.to_string());

    let test_prompt = "";
    test_prompt += "You are the VERIFIER after HIM implement. Fail closed.\n";
    test_prompt += "Process file: " + written_plan + "\n";
    test_prompt += "Handoff: " + handoff_path + "\n";
    test_prompt += "Goal: " + plan_goal + "\n";
    test_prompt += "Done criteria:\n" + done_blob;
    test_prompt += "Test strategy: " + test_strategy + "\n";
    test_prompt += "Test hint: " + test_hint + "\n";
    test_prompt += "Proven findings that should now be fixed:\n" + proven_blob;
    test_prompt += "Implement summary: " + impl_summary + "\n";
    test_prompt += "Files changed:\n" + files_changed_blob;
    test_prompt += "Blocked:\n" + blocked_blob;
    test_prompt += "REQUIRED:\n";
    test_prompt += "1) read_file process file; spot-check key fixes vs proven list.\n";
    test_prompt += "2) Re-run prove tests / new regression tests and the best project test command for the touch area.\n";
    test_prompt += "3) passed=true ONLY if evidence shows commands succeeded AND proven issues no longer repro (or blocked with documented product reason).\n";
    test_prompt += "4) If toolchain missing, passed=false.\n";
    test_prompt += "5) evidence must quote outcomes. Append Verification log on process file.\n";
    test_prompt += "Return passed, commands_run, failures, summary, evidence.\n";

    let test_r = agent(test_prompt, #{
        label: "verify:" + attempt.to_string(),
        capability_mode: "all",
        output_schema: test_schema,
    });

    let this_passed = false;
    if test_r != () && test_r.success && test_r.output != () {
        let to = test_r.output;
        if to.passed == true {
            if to.evidence != () && trimmed(to.evidence) != "" {
                this_passed = true;
            } else {
                log("Verifier claimed pass without evidence — fail closed");
            }
        }
        if to.summary != () { last_test_summary = to.summary; }
        if to.evidence != () { last_evidence = to.evidence; }
        last_failures_blob = join_lines(to.failures, "- ");
        last_commands_blob = join_lines(to.commands_run, "- ");
    } else {
        last_test_summary = "Verifier agent failed or returned unusable output";
        last_failures_blob = "- verifier infrastructure failure\n";
        last_evidence = "";
        last_commands_blob = "";
    }
    if last_failures_blob == "" { last_failures_blob = "- (none listed)\n"; }
    if last_commands_blob == "" { last_commands_blob = "- (none listed)\n"; }

    if this_passed {
        tests_passed = true;
        log("Verify PASS: " + last_test_summary);
        break;
    }

    log("Verify FAIL: " + last_test_summary);
    if attempt >= max_attempts { break; }

    phase("Fix");
    fix_round += 1;
    log("Fix round " + fix_round.to_string() + "/" + max_fix.to_string());

    let fix_prompt = "";
    fix_prompt += "You are the FIXER after failed verification of HIM fixes.\n";
    fix_prompt += "Process file: " + written_plan + "\n";
    fix_prompt += "Goal: " + plan_goal + "\n";
    fix_prompt += "Failures:\n" + last_failures_blob;
    fix_prompt += "Evidence:\n" + last_evidence + "\n";
    fix_prompt += "Commands:\n" + last_commands_blob;
    fix_prompt += "Proven scope:\n" + proven_blob;
    fix_prompt += "REQUIRED: fix root causes only; re-run cheap tests if useful; update process file + codex Fixes; no scope creep.\n";

    let fix_r = agent(fix_prompt, #{
        label: "fix:" + fix_round.to_string(),
        capability_mode: "all",
        output_schema: fix_schema,
    });

    if fix_r != () && fix_r.success && fix_r.output != () {
        let fo = fix_r.output;
        let fs = if fo.summary != () { fo.summary } else { "(no summary)" };
        fix_summaries += "- round " + fix_round.to_string() + ": " + fs + "\n";
        log("Fix: " + fs);
        let more = join_lines(fo.files_changed, "- ");
        if more != "" { files_changed_blob += more; }
    } else {
        fix_summaries += "- round " + fix_round.to_string() + ": fix agent failed\n";
        log("Fix agent failed this round");
    }
}

// --- Phase 9: Gate -----------------------------------------------------------

phase("Gate");
log("Completion gate (tests_passed=" + tests_passed.to_string() + ")");

let gate_prompt = "";
gate_prompt += "You are the COMPLETION GATE for HIM→implement. Fail closed.\n";
gate_prompt += "complete=true only if proven findings are fixed (or cleanly blocked) AND verification passed with evidence.\n";
gate_prompt += "Process: " + written_plan + "\n";
gate_prompt += "Handoff: " + handoff_path + "\n";
gate_prompt += "Codex: " + codex_path + "\n";
gate_prompt += "Goal: " + plan_goal + "\n";
gate_prompt += "Done criteria:\n" + done_blob;
gate_prompt += "Proven:\n" + proven_blob;
gate_prompt += "Implement: " + impl_summary + "\n";
gate_prompt += "Blocked steps:\n" + blocked_blob;
gate_prompt += "Remaining: " + remaining + "\n";
gate_prompt += "tests_passed flag: " + tests_passed.to_string() + "\n";
gate_prompt += "Last verify: " + last_test_summary + "\n";
gate_prompt += "Failures:\n" + last_failures_blob;
gate_prompt += "Evidence:\n" + last_evidence + "\n";
gate_prompt += "Fix rounds:\n" + fix_summaries;
gate_prompt += "REQUIRED: read process file; verdict exactly COMPLETE|INCOMPLETE|BLOCKED; ";
gate_prompt += "complete=true only with COMPLETE and tests_passed; list unmet_criteria and next_steps.\n";

let gate_r = agent(gate_prompt, #{
    label: "gate",
    capability_mode: "read-write",
    output_schema: gate_schema,
});

let is_complete = false;
let verdict = "INCOMPLETE";
let headline = "";
let unmet_blob = "";
let next_blob = "";

if gate_r != () && gate_r.success && gate_r.output != () {
    let gate_out = gate_r.output;
    if gate_out.verdict != () && trimmed(gate_out.verdict) != "" { verdict = trimmed(gate_out.verdict); }
    if gate_out.headline != () { headline = gate_out.headline; }
    if gate_out.complete == true { is_complete = true; }
    unmet_blob = join_lines(gate_out.unmet_criteria, "- ");
    next_blob = join_lines(gate_out.next_steps, "- ");
} else {
    headline = "Gate agent failed — treating as incomplete";
    log(headline);
}

if !tests_passed {
    is_complete = false;
    if verdict == "COMPLETE" { verdict = "INCOMPLETE"; }
}
if is_complete && verdict != "COMPLETE" {
    is_complete = false;
    verdict = "INCOMPLETE";
}
if !is_complete && verdict == "COMPLETE" {
    verdict = "INCOMPLETE";
}

if unmet_blob == "" {
    if is_complete {
        unmet_blob = "- (none)\n";
    } else {
        unmet_blob = "- verification and/or proven-fix criteria not fully met\n";
    }
}
if next_blob == "" {
    if is_complete {
        next_blob = "- Review codex and commit when ready\n";
    } else {
        next_blob += "- Resume from " + written_plan + " / " + handoff_path + "\n";
        next_blob += "- Or re-run /workflow implement-from-plan with sources=[" + handoff_path + "] auto_approve_plan=true\n";
    }
}
if headline == "" {
    if is_complete {
        headline = "Proven HIM findings fixed; verification passed.";
    } else {
        headline = "Not complete — see unmet criteria.";
    }
}

let md = "";
md += "# HIM → implement report\n\n";
md += "**Verdict:** " + verdict + "\n\n";
md += "**Complete:** " + is_complete.to_string() + "\n\n";
md += "**Headline:** " + headline + "\n\n";
md += "## Scope\n\n" + scope_summary + "\n\n";
md += "### Files\n\n" + file_list + "\n";
md += "## Proven findings (pre-implement)\n\n" + proven_blob + "\n";
md += "## Disproven / report-only\n\n" + disproven_blob + "\n";
md += "## Artifacts\n\n";
md += "- codex: `" + codex_path + "`\n";
md += "- handoff: `" + handoff_path + "`\n";
md += "- process: `" + written_plan + "`\n\n";
md += "## Implementation\n\n" + impl_summary + "\n\n";
md += "### Steps done\n\n" + steps_done_blob + "\n";
md += "### Blocked\n\n" + blocked_blob + "\n";
md += "### Files changed\n\n" + files_changed_blob + "\n";
md += "## Verification\n\n";
md += "- tests_passed: " + tests_passed.to_string() + "\n";
md += "- attempts: " + attempt.to_string() + " / " + max_attempts.to_string() + "\n";
md += "- summary: " + last_test_summary + "\n\n";
md += "### Commands\n\n" + last_commands_blob + "\n";
md += "### Failures\n\n" + last_failures_blob + "\n";
md += "### Evidence\n\n" + last_evidence + "\n\n";
md += "### Fix log\n\n";
if fix_summaries == "" {
    md += "- (no fix rounds)\n\n";
} else {
    md += fix_summaries + "\n";
}
md += "## Unmet criteria\n\n" + unmet_blob + "\n";
md += "## Next steps\n\n" + next_blob + "\n";
md += "## Coverage stats\n\n";
md += "- candidates: " + candidates.len().to_string() + "\n";
md += "- proven: " + proven.len().to_string() + "\n";
md += "- disproven: " + disproven.len().to_string() + "\n";
md += "- hunt failures: " + hunt_fail.to_string() + "\n";
md += "- prove unusable: " + prove_unusable.to_string() + "\n";
md += "- dropped past cap: " + dropped.to_string() + "\n";
md += "\n## Note on workflow nesting\n\n";
md += "Host workflows cannot launch other workflows. This run inlined hands-off implement-from-plan ";
md += "(plan → implement → verify → fix → gate) after HIM prove. ";
md += "Standalone re-run: `/workflow implement-from-plan` with sources=`" + handoff_path + "` and auto_approve_plan=true.\n";

let report_path = write_scratch_file("him-to-implement-report.md", md);
log("Gate: " + verdict + " (complete=" + is_complete.to_string() + ")");

complete(#{
    path: report_path,
    verdict: verdict,
    complete: is_complete,
    headline: headline,
    proven: proven.len(),
    disproven: disproven.len(),
    tests_passed: tests_passed,
    handoff_path: handoff_path,
    codex_path: codex_path,
    plan_path: written_plan,
    implement_ran: true,
    implement_from_plan_args: #{
        sources: [handoff_path, codex_path],
        goal: "Fix only proven HIM findings in " + handoff_path + ". Keep prove tests green.",
        auto_approve_plan: true,
        plan_path: plan_path,
    },
});
