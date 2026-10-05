let meta = #{
    name: "implement-from-plan",
    description: "Read source file(s), write a step-by-step process file, implement from it, test+fix, then run a mandatory local visual+performance final test before declaring complete",
    when_to_use: "Any repo: turn a spec/handoff/TODO/issue dump into a process file, implement, verify with local visual+perf, and fix before marking done",
    phases: [
        #{ title: "Ingest", detail: "read sources and map codebase context" },
        #{ title: "Plan", detail: "write durable step-by-step process file" },
        #{ title: "Approve", detail: "optional human gate before edits" },
        #{ title: "Implement", detail: "execute process steps in order" },
        #{ title: "Verify", detail: "build/unit checks against acceptance criteria" },
        #{ title: "Fix", detail: "bounded fix+retest loop until green or cap" },
        #{ title: "LocalVisualPerf", detail: "mandatory on-machine visual + performance final test" },
        #{ title: "Gate", detail: "fail-closed complete only if process done, unit verify, and local visual+perf pass" },
    ],
};

// --- schemas -----------------------------------------------------------------

let ingest_schema = #{
    "type": "object",
    "required": ["summary", "sources_read", "constraints", "relevant_paths", "risks", "open_questions"],
    "properties": #{
        "summary": #{ "type": "string" },
        "sources_read": #{
            "type": "array",
            "maxItems": 40,
            "items": #{ "type": "string" },
        },
        "constraints": #{
            "type": "array",
            "maxItems": 20,
            "items": #{ "type": "string" },
        },
        "relevant_paths": #{
            "type": "array",
            "maxItems": 40,
            "items": #{ "type": "string" },
        },
        "risks": #{
            "type": "array",
            "maxItems": 16,
            "items": #{ "type": "string" },
        },
        "open_questions": #{
            "type": "array",
            "maxItems": 12,
            "items": #{ "type": "string" },
        },
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

// Final on-machine visual + performance gate (required for complete=true)
let visual_perf_schema = #{
    "type": "object",
    "required": [
        "passed",
        "local_machine_confirmed",
        "visual_passed",
        "perf_passed",
        "commands_run",
        "visual_evidence",
        "perf_evidence",
        "artifacts",
        "summary",
        "failures",
    ],
    "properties": #{
        "passed": #{ "type": "boolean" },
        "local_machine_confirmed": #{ "type": "boolean" },
        "visual_passed": #{ "type": "boolean" },
        "perf_passed": #{ "type": "boolean" },
        "commands_run": #{
            "type": "array",
            "maxItems": 30,
            "items": #{ "type": "string" },
        },
        "visual_evidence": #{ "type": "string" },
        "perf_evidence": #{ "type": "string" },
        "artifacts": #{
            "type": "array",
            "maxItems": 40,
            "items": #{ "type": "string" },
        },
        "summary": #{ "type": "string" },
        "failures": #{
            "type": "array",
            "maxItems": 30,
            "items": #{ "type": "string" },
        },
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

fn int_arg(v, default_val, min_v, max_v) {
    let n = default_val;
    if v == () {
        // keep default
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
// Guard `args` first: property access on unit is a runtime error.

let sources_arg = if args == () { () } else { args.sources };
if sources_arg == () && args != () { sources_arg = args.files; }
if sources_arg == () && args != () { sources_arg = args.source; }
if sources_arg == () && args != () { sources_arg = args.file; }

let goal_arg = if args == () { () } else { args.goal };
let plan_path_arg = if args == () { () } else { args.plan_path };
let test_cmd_arg = if args == () { () } else { args.test_command };
if test_cmd_arg == () && args != () { test_cmd_arg = args.test; }
let visual_cmd_arg = if args == () { () } else { args.visual_command };
if visual_cmd_arg == () && args != () { visual_cmd_arg = args.visual; }
let perf_cmd_arg = if args == () { () } else { args.perf_command };
if perf_cmd_arg == () && args != () { perf_cmd_arg = args.perf; }
if perf_cmd_arg == () && args != () { perf_cmd_arg = args.performance_command; }
// Optional combined launcher (e.g. one benchmark that also captures frames)
let visual_perf_cmd_arg = if args == () { () } else { args.visual_perf_command };
if visual_perf_cmd_arg == () && args != () { visual_perf_cmd_arg = args.local_visual_perf_command; }
let auto_approve = bool_arg(if args == () { () } else { args.auto_approve_plan }, false);
// max_fix_rounds: numeric or numeric-string args; clamp 1..5. Default 3.
let max_fix = int_arg(if args == () { () } else { args.max_fix_rounds }, 3, 1, 5);
// Extra fix rounds dedicated to visual/perf after unit verify is green
let max_vp_fix = int_arg(if args == () { () } else { args.max_visual_perf_fix_rounds }, 2, 0, 4);

// Normalize sources into a display string + bullet list for prompts
let sources_list = [];
if sources_arg == () {
    // empty — will pause
} else if type_of(sources_arg) == "array" {
    for s in sources_arg {
        let t = trimmed(s.to_string());
        if t != "" { sources_list.push(t); }
    }
} else {
    // string: allow comma or newline separation
    let raw = trimmed(sources_arg.to_string());
    // split on commas by simple scan
    let cur = "";
    let i = 0;
    let n = raw.len();
    while i < n {
        let ch = raw[i];
        if ch == ',' || ch == '\n' || ch == ';' {
            cur.trim();
            if cur != "" { sources_list.push(cur); }
            cur = "";
        } else {
            cur += ch;
        }
        i += 1;
    }
    cur.trim();
    if cur != "" { sources_list.push(cur); }
}

if sources_list.len() == 0 {
    pause("verification", "Pass args.sources (path string, comma-separated paths, or array of paths) — files to read as the feature/spec input. Optional: goal, plan_path, test_command, visual_command, perf_command, visual_perf_command, auto_approve_plan, max_fix_rounds, max_visual_perf_fix_rounds.");
}

let sources_blob = "";
for s in sources_list {
    sources_blob += "- " + s + "\n";
}

let goal_text = if goal_arg == () || trimmed(goal_arg.to_string()) == "" {
    "Implement everything required by the source file(s). Prefer smallest correct change set."
} else {
    trimmed(goal_arg.to_string())
};

let plan_path = if plan_path_arg == () || trimmed(plan_path_arg.to_string()) == "" {
    "IMPLEMENTATION_PROCESS.md"
} else {
    trimmed(plan_path_arg.to_string())
};

let test_hint = if test_cmd_arg == () || trimmed(test_cmd_arg.to_string()) == "" {
    "Discover the repo's normal build/unit verify path (package.json scripts, cargo test, pytest, cmake --build, dotnet test, make test, etc.). Prefer the fastest meaningful check that covers the change. Visual and performance runs are a SEPARATE final phase — do not claim them done here."
} else {
    "Prefer this build/unit verify command when applicable: " + trimmed(test_cmd_arg.to_string()) + ". Visual and performance runs are a SEPARATE final phase."
};

let visual_hint = if visual_cmd_arg == () || trimmed(visual_cmd_arg.to_string()) == "" {
    "Discover how THIS repo is visually exercised on a developer machine: launch scripts, demo/app targets, screenshot tools, Playwright/Cypress headed runs, storybook, game client, preview .bat/.sh, etc. You MUST actually launch a local process and inspect real output (window, screenshot files, rendered frames) — not reason about code alone."
} else {
    "Prefer this visual command on the local machine: " + trimmed(visual_cmd_arg.to_string())
};

let perf_hint = if perf_cmd_arg == () || trimmed(perf_cmd_arg.to_string()) == "" {
    "Discover how THIS repo measures performance locally: benchmark targets, Launch_benchmark-style scripts, `npm run bench`, hyperfine, cargo bench, frame-time/FPS logs, profiler scripts. You MUST run a real local measurement and report numbers from that run — not estimates."
} else {
    "Prefer this performance command on the local machine: " + trimmed(perf_cmd_arg.to_string())
};

let visual_perf_combo = if visual_perf_cmd_arg == () || trimmed(visual_perf_cmd_arg.to_string()) == "" {
    ""
} else {
    "If useful, a combined visual+perf launcher was provided: " + trimmed(visual_perf_cmd_arg.to_string()) + ". You may use it when it covers both concerns; still report visual_evidence and perf_evidence separately."
};

// --- Phase 1: Ingest ---------------------------------------------------------

phase("Ingest");
log("Reading " + sources_list.len().to_string() + " source file(s)");

let ingest_prompt = "";
ingest_prompt += "You are the INGEST agent for a universal implement-from-plan workflow.\n";
ingest_prompt += "Any language/stack. Working directory is the current repository root.\n";
ingest_prompt += "Goal (user): " + goal_text + "\n";
ingest_prompt += "Source files to READ fully with read_file (do not invent contents):\n" + sources_blob;
ingest_prompt += "REQUIRED method:\n";
ingest_prompt += "1) read_file every listed source. If a path is missing, note it in open_questions and continue with what exists.\n";
ingest_prompt += "2) Explore only enough of the codebase (list_dir, grep, CODEBASE*/README/docs if present) to ground implementation. Do not rewrite the product from memory.\n";
ingest_prompt += "3) Extract constraints, acceptance criteria, and out-of-scope notes from the sources.\n";
ingest_prompt += "4) List relevant_paths you actually inspected or that the sources name.\n";
ingest_prompt += "5) risks: ship/regression hazards. open_questions: ambiguities that block a correct plan.\n";
ingest_prompt += "Return structured fields only. Empty open_questions is valid only after careful reading.\n";

let ingest_r = agent(ingest_prompt, #{
    label: "ingest",
    capability_mode: "execute",
    output_schema: ingest_schema,
});

if ingest_r == () || !ingest_r.success || ingest_r.output == () {
    pause("infra", "Ingest agent failed. Resume to retry, or re-run with clearer args.sources.");
}

let ingest = ingest_r.output;
let ingest_summary = if ingest.summary != () { ingest.summary } else { "(no summary)" };
let constraints_blob = join_lines(ingest.constraints, "- ");
let risks_blob = join_lines(ingest.risks, "- ");
let paths_blob = join_lines(ingest.relevant_paths, "- ");
let questions_blob = join_lines(ingest.open_questions, "- ");
let sources_read_blob = join_lines(ingest.sources_read, "- ");
if constraints_blob == "" { constraints_blob = "- (none stated)\n"; }
if risks_blob == "" { risks_blob = "- (none tagged)\n"; }
if paths_blob == "" { paths_blob = "- (none listed)\n"; }
if questions_blob == "" { questions_blob = "- (none)\n"; }
if sources_read_blob == "" { sources_read_blob = sources_blob; }

log("Ingest: " + ingest_summary);

// --- Phase 2: Plan -----------------------------------------------------------

phase("Plan");
log("Writing process file to " + plan_path);

let plan_prompt = "";
plan_prompt += "You are the PLANNER for a universal implement-from-plan workflow.\n";
plan_prompt += "Write a durable step-by-step PROCESS FILE that later agents will execute, update, and use as the completion checklist.\n";
plan_prompt += "User goal: " + goal_text + "\n";
plan_prompt += "Sources:\n" + sources_blob;
plan_prompt += "Ingest summary: " + ingest_summary + "\n";
plan_prompt += "Sources actually read:\n" + sources_read_blob;
plan_prompt += "Constraints:\n" + constraints_blob;
plan_prompt += "Relevant paths:\n" + paths_blob;
plan_prompt += "Risks:\n" + risks_blob;
plan_prompt += "Open questions:\n" + questions_blob;
plan_prompt += "Process file path (WRITE THIS FILE with the write/search_replace tools): " + plan_path + "\n";
plan_prompt += "REQUIRED file format (markdown):\n";
plan_prompt += "# Implementation Process\n\n";
plan_prompt += "## Goal\n...\n\n";
plan_prompt += "## Sources\n- paths...\n\n";
plan_prompt += "## Context\nshort grounding from ingest\n\n";
plan_prompt += "## Constraints\n- ...\n\n";
plan_prompt += "## Steps\n";
plan_prompt += "### Step N: <title>\n";
plan_prompt += "- Status: pending\n";
plan_prompt += "- Actions: concrete file-level actions\n";
plan_prompt += "- Acceptance: observable done condition\n";
plan_prompt += "- Verify: how this step is checked (command or inspection)\n\n";
plan_prompt += "## Done criteria\n- [ ] ...\n- [ ] Local visual test run on this machine\n- [ ] Local performance test run on this machine\n\n";
plan_prompt += "## Test strategy\nBuild/unit checks, then mandatory final local visual + performance.\n\n";
plan_prompt += "## Local visual + performance final test\n";
plan_prompt += "- Status: pending\n";
plan_prompt += "- Visual: how to launch and what to observe (command or script path if known)\n";
plan_prompt += "- Performance: how to measure (command, metric, pass bar if known)\n";
plan_prompt += "- Artifacts: where screenshots/logs/FPS dumps should land\n";
plan_prompt += "- Note: this runs on the developer's LOCAL machine as the last automated gate before complete.\n\n";
plan_prompt += "## Verification log\n(empty; later agents append)\n\n";
plan_prompt += "Rules:\n";
plan_prompt += "- 3–15 ordered steps; atomic, buildable increments preferred.\n";
plan_prompt += "- Every step starts Status: pending.\n";
plan_prompt += "- Include docs/changelog/tests steps only if the sources or repo conventions require them — do not invent project-specific bureaucracy.\n";
plan_prompt += "- Always include done criteria for local visual + local performance final tests.\n";
plan_prompt += "- If open questions would force guessing architecture, put a first step to resolve by reading code, not by inventing APIs.\n";
plan_prompt += "- You MUST create/overwrite " + plan_path + " on disk before finishing.\n";
plan_prompt += "- Return structured steps mirroring the file (status all pending), step_count, done_criteria, test_strategy, notes.\n";
plan_prompt += "- plan_path in output must be the path you wrote.\n";
plan_prompt += "Visual hint for planning: " + visual_hint + "\n";
plan_prompt += "Perf hint for planning: " + perf_hint + "\n";
if visual_perf_combo != "" {
    plan_prompt += visual_perf_combo + "\n";
}

let plan_r = agent(plan_prompt, #{
    label: "plan",
    capability_mode: "read-write",
    output_schema: plan_schema,
});

if plan_r == () || !plan_r.success || plan_r.output == () {
    pause("infra", "Plan agent failed before a process file was confirmed. Resume to retry.");
}

let plan = plan_r.output;
let written_plan = if plan.plan_path != () && trimmed(plan.plan_path) != "" {
    trimmed(plan.plan_path)
} else {
    plan_path
};
let plan_goal = if plan.goal != () { plan.goal } else { goal_text };
let step_count = if plan.step_count != () { plan.step_count } else { 0 };
let test_strategy = if plan.test_strategy != () { plan.test_strategy } else { test_hint };
let plan_notes = if plan.notes != () { plan.notes } else { "" };

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
if steps_blob == "" { steps_blob = "(no structured steps returned — implementer must read the process file)\n"; }

let done_blob = join_lines(plan.done_criteria, "- ");
if done_blob == "" {
    done_blob = "- Process file steps complete\n- Build/unit verification passes\n- Local visual test run on this machine\n- Local performance test run on this machine\n";
}

log("Process file: " + written_plan + " (" + step_count.to_string() + " steps)");

// Scratch copy of plan summary for the run UI
let plan_scratch = "";
plan_scratch += "# Process plan summary\n\n";
plan_scratch += "**Path:** " + written_plan + "\n\n";
plan_scratch += "**Goal:** " + plan_goal + "\n\n";
plan_scratch += "## Steps\n" + steps_blob + "\n";
plan_scratch += "## Done criteria\n" + done_blob + "\n";
plan_scratch += "## Test strategy\n" + test_strategy + "\n\n";
plan_scratch += "## Final gate (required)\n";
plan_scratch += "- Local visual test on this machine\n";
plan_scratch += "- Local performance test on this machine\n";
if plan_notes != "" {
    plan_scratch += "\n## Notes\n" + plan_notes + "\n";
}
let plan_scratch_path = write_scratch_file("process-plan-summary.md", plan_scratch);

// --- Phase 3: Approve --------------------------------------------------------

phase("Approve");
if !auto_approve {
    let approve_msg = "";
    approve_msg += "Process file written to: " + written_plan + "\n";
    approve_msg += "Goal: " + plan_goal + "\n";
    approve_msg += "Steps:\n" + steps_blob;
    approve_msg += "Review/edit the process file if needed, then resume to implement. ";
    approve_msg += "Or re-run with auto_approve_plan=true to skip this gate.";
    await_user("user", approve_msg);
} else {
    log("auto_approve_plan=true — skipping human plan gate");
}

// --- Phase 4: Implement ------------------------------------------------------

phase("Implement");
log("Implementing from " + written_plan);

let impl_prompt = "";
impl_prompt += "You are the IMPLEMENTER for a universal implement-from-plan workflow.\n";
impl_prompt += "You execute the process file. Do not freestyle a different design unless the process file is impossible as written — then update the process file with a short amendment and continue.\n";
impl_prompt += "Process file path: " + written_plan + "\n";
impl_prompt += "User goal: " + plan_goal + "\n";
impl_prompt += "Original sources:\n" + sources_blob;
impl_prompt += "Ingest summary: " + ingest_summary + "\n";
impl_prompt += "Constraints:\n" + constraints_blob;
impl_prompt += "Structured steps (may be stale — re-read the process file):\n" + steps_blob;
impl_prompt += "REQUIRED method:\n";
impl_prompt += "1) read_file the process file first. Also re-read any source specs you need.\n";
impl_prompt += "2) Work steps in order. For each step: make the code/doc changes, then set Status: done (or blocked with reason).\n";
impl_prompt += "3) Prefer atomic, compiling increments. Match existing project style and ownership boundaries.\n";
impl_prompt += "4) Do not expand scope beyond the process file and user goal.\n";
impl_prompt += "5) Do not declare the whole feature complete — verification is a later phase.\n";
impl_prompt += "6) Update the process file on disk as you go (statuses, short notes under Verification log if useful).\n";
impl_prompt += "7) Use tools (read_file, grep, list_dir, apply patches/write, shell only if needed for generation). No speculative giant rewrites.\n";
impl_prompt += "Return steps_done (ids/titles), steps_blocked, files_changed, plan_updated, remaining work summary.\n";

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
    log("Implement agent failed — continuing to verify/fix loop may still recover partial work");
} else {
    log("Implement: " + impl_summary);
}

// --- Phase 5+6: Verify / Fix loop --------------------------------------------

let tests_passed = false;
let last_test_summary = "";
let last_failures_blob = "";
let last_evidence = "";
let last_commands_blob = "";
let fix_round = 0;
let fix_summaries = "";

// Rounds: verify always once; up to max_fix fix+reverify cycles after a failure
// Total verify attempts = max_fix + 1
let attempt = 0;
let max_attempts = max_fix + 1;

while attempt < max_attempts {
    attempt += 1;
    phase("Verify");
    log("Verify attempt " + attempt.to_string() + "/" + max_attempts.to_string());

    let test_prompt = "";
    test_prompt += "You are the VERIFIER for a universal implement-from-plan workflow. Fail closed.\n";
    test_prompt += "Process file: " + written_plan + "\n";
    test_prompt += "User goal: " + plan_goal + "\n";
    test_prompt += "Done criteria:\n" + done_blob;
    test_prompt += "Test strategy from plan: " + test_strategy + "\n";
    test_prompt += "Verify hint: " + test_hint + "\n";
    test_prompt += "Implementation summary: " + impl_summary + "\n";
    test_prompt += "Files reported changed:\n" + files_changed_blob;
    test_prompt += "Blocked steps:\n" + blocked_blob;
    test_prompt += "REQUIRED method:\n";
    test_prompt += "1) read_file the process file. Confirm step statuses vs reality (spot-check key files).\n";
    test_prompt += "2) Run the best available BUILD/UNIT automated checks for THIS repo using shell tools. ";
    test_prompt += "Discover from lockfiles/build files if no explicit command was given.\n";
    test_prompt += "3) Do NOT run the final visual/performance suite here — that is a later mandatory phase. ";
    test_prompt += "Focus on compile, unit/integration tests, static checks.\n";
    test_prompt += "4) passed=true ONLY if: (a) process implementation steps that claim done look done, ";
    test_prompt += "(b) no hard blocked critical steps remain for the goal, and ";
    test_prompt += "(c) automated build/unit checks you ran exited successfully OR you have concrete evidence ";
    test_prompt += "the project has no applicable automated test and static review of the change is clean.\n";
    test_prompt += "5) If you could not run required checks (missing toolchain), passed=false and explain in failures.\n";
    test_prompt += "6) evidence must quote command outcomes (exit codes, key error lines) or inspection proof.\n";
    test_prompt += "7) Append a short note to the process file Verification log (use tools to edit).\n";
    test_prompt += "Return commands_run, failures (empty if pass), summary, evidence, passed.\n";

    let test_r = agent(test_prompt, #{
        label: "verify:" + attempt.to_string(),
        capability_mode: "all",
        output_schema: test_schema,
    });

    let this_passed = false;
    if test_r != () && test_r.success && test_r.output != () {
        let to = test_r.output;
        if to.passed == true {
            // require non-empty evidence for pass
            if to.evidence != () && trimmed(to.evidence) != "" {
                this_passed = true;
            } else {
                log("Verifier claimed pass without evidence — treating as fail (fail closed)");
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

    // Fix if we still have fix budget (attempts remaining after this one)
    if attempt >= max_attempts {
        break;
    }

    phase("Fix");
    fix_round += 1;
    log("Fix round " + fix_round.to_string() + "/" + max_fix.to_string());

    let fix_prompt = "";
    fix_prompt += "You are the FIXER for a universal implement-from-plan workflow.\n";
    fix_prompt += "Tests/verification failed. Repair the implementation and process file; do not expand scope.\n";
    fix_prompt += "Process file: " + written_plan + "\n";
    fix_prompt += "User goal: " + plan_goal + "\n";
    fix_prompt += "Done criteria:\n" + done_blob;
    fix_prompt += "Last verify summary: " + last_test_summary + "\n";
    fix_prompt += "Failures:\n" + last_failures_blob;
    fix_prompt += "Evidence:\n" + last_evidence + "\n";
    fix_prompt += "Commands run:\n" + last_commands_blob;
    fix_prompt += "Prior implement summary: " + impl_summary + "\n";
    fix_prompt += "REQUIRED method:\n";
    fix_prompt += "1) read_file process file + the failing sources/files from evidence.\n";
    fix_prompt += "2) Fix root causes. Re-run targeted commands yourself if cheap to confirm progress.\n";
    fix_prompt += "3) Update process file statuses and Verification log with what you fixed.\n";
    fix_prompt += "4) still_failing: honest residual risk if any.\n";
    fix_prompt += "Return fixed items, files_changed, plan_updated, summary, still_failing.\n";

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
        // refresh files_changed list for next verify
        let more = join_lines(fo.files_changed, "- ");
        if more != "" {
            files_changed_blob += more;
        }
    } else {
        fix_summaries += "- round " + fix_round.to_string() + ": fix agent failed\n";
        log("Fix agent failed this round");
    }
}

// --- Phase: Local visual + performance (mandatory final on-machine test) -----

let visual_perf_passed = false;
let vp_local_confirmed = false;
let vp_visual_passed = false;
let vp_perf_passed = false;
let vp_summary = "";
let vp_visual_evidence = "";
let vp_perf_evidence = "";
let vp_commands_blob = "";
let vp_failures_blob = "";
let vp_artifacts_blob = "";
let vp_fix_round = 0;
let vp_fix_summaries = "";
let vp_attempted = false;

if !tests_passed {
    log("Skipping LocalVisualPerf — build/unit verify did not pass (fail closed)");
    vp_summary = "Skipped: build/unit verification failed";
    vp_failures_blob = "- prerequisite build/unit verify not green\n";
} else {
    let vp_attempt = 0;
    let vp_max_attempts = max_vp_fix + 1;

    while vp_attempt < vp_max_attempts {
        vp_attempt += 1;
        vp_attempted = true;
        phase("LocalVisualPerf");
        log("Local visual+perf attempt " + vp_attempt.to_string() + "/" + vp_max_attempts.to_string());

        let vp_prompt = "";
        vp_prompt += "You are the LOCAL VISUAL + PERFORMANCE FINAL TESTER for a universal implement-from-plan workflow.\n";
        vp_prompt += "This is the MANDATORY last automated quality gate before complete. Fail closed.\n";
        vp_prompt += "You MUST run tests on THIS local machine (the developer's host). Do not simulate, invent FPS, or pass from code reading alone.\n";
        vp_prompt += "Process file: " + written_plan + "\n";
        vp_prompt += "User goal: " + plan_goal + "\n";
        vp_prompt += "Implementation summary: " + impl_summary + "\n";
        vp_prompt += "Files changed:\n" + files_changed_blob;
        vp_prompt += "Done criteria:\n" + done_blob;
        vp_prompt += "Visual guidance: " + visual_hint + "\n";
        vp_prompt += "Performance guidance: " + perf_hint + "\n";
        if visual_perf_combo != "" {
            vp_prompt += visual_perf_combo + "\n";
        }
        vp_prompt += "REQUIRED method:\n";
        vp_prompt += "1) read_file the process file section 'Local visual + performance final test' (or equivalent).\n";
        vp_prompt += "2) Discover launchers if needed: scripts (*.bat, *.sh, package.json scripts), README run instructions, ";
        vp_prompt += "benchmark targets, screenshot/capture tools, demo apps. Prefer repo-native paths.\n";
        vp_prompt += "3) VISUAL: Launch a real local process that exercises the change visually. Capture evidence: ";
        vp_prompt += "screenshot paths, capture outputs, headless-with-image dumps, or windowed run logs that prove the UI/render path ran. ";
        vp_prompt += "If the app requires a display and none is available, visual_passed=false with a clear failure (do not fake pass).\n";
        vp_prompt += "4) PERFORMANCE: Run a real local perf/benchmark path for the change area. Record concrete metrics ";
        vp_prompt += "(FPS, frame time ms, bench scores, duration, memory if available) from the run output.\n";
        vp_prompt += "5) local_machine_confirmed=true only if you actually invoked local shell commands on this host for both concerns ";
        vp_prompt += "(or one combined command that clearly covers both).\n";
        vp_prompt += "6) visual_passed / perf_passed independently; passed=true only if BOTH are true AND local_machine_confirmed AND evidence strings are non-empty.\n";
        vp_prompt += "7) artifacts: list paths to screenshots, logs, benchmark JSON, video captures you produced or found from the run.\n";
        vp_prompt += "8) Update the process file: set Local visual+perf Status, append Verification log lines with commands + metrics + artifact paths.\n";
        vp_prompt += "9) Do not declare the whole feature complete — the Gate phase does that.\n";
        vp_prompt += "Return all schema fields honestly.\n";

        let vp_r = agent(vp_prompt, #{
            label: "local-visual-perf:" + vp_attempt.to_string(),
            capability_mode: "all",
            output_schema: visual_perf_schema,
        });

        let this_vp_ok = false;
        if vp_r != () && vp_r.success && vp_r.output != () {
            let vo = vp_r.output;
            vp_local_confirmed = (vo.local_machine_confirmed == true);
            vp_visual_passed = (vo.visual_passed == true);
            vp_perf_passed = (vo.perf_passed == true);
            if vo.summary != () { vp_summary = vo.summary; }
            if vo.visual_evidence != () { vp_visual_evidence = vo.visual_evidence; }
            if vo.perf_evidence != () { vp_perf_evidence = vo.perf_evidence; }
            vp_failures_blob = join_lines(vo.failures, "- ");
            vp_commands_blob = join_lines(vo.commands_run, "- ");
            vp_artifacts_blob = join_lines(vo.artifacts, "- ");

            // Script-level fail closed (agents don't enforce invariants)
            let vis_ev_ok = vp_visual_evidence != () && trimmed(vp_visual_evidence) != "";
            let perf_ev_ok = vp_perf_evidence != () && trimmed(vp_perf_evidence) != "";
            if vo.passed == true
                && vp_local_confirmed
                && vp_visual_passed
                && vp_perf_passed
                && vis_ev_ok
                && perf_ev_ok
            {
                this_vp_ok = true;
            } else {
                if vo.passed == true {
                    log("LocalVisualPerf claimed pass but evidence/local flags incomplete — treating as fail");
                }
                // force flags consistent with fail-closed
                if !vp_local_confirmed || !vis_ev_ok { vp_visual_passed = false; }
                if !vp_local_confirmed || !perf_ev_ok { vp_perf_passed = false; }
            }
        } else {
            vp_summary = "Local visual+perf agent failed or returned unusable output";
            vp_failures_blob = "- visual/perf agent infrastructure failure\n";
            vp_visual_evidence = "";
            vp_perf_evidence = "";
            vp_commands_blob = "";
            vp_artifacts_blob = "";
            vp_local_confirmed = false;
            vp_visual_passed = false;
            vp_perf_passed = false;
        }

        if vp_failures_blob == "" { vp_failures_blob = "- (none listed)\n"; }
        if vp_commands_blob == "" { vp_commands_blob = "- (none listed)\n"; }
        if vp_artifacts_blob == "" { vp_artifacts_blob = "- (none listed)\n"; }

        if this_vp_ok {
            visual_perf_passed = true;
            log("LocalVisualPerf PASS: " + vp_summary);
            break;
        }

        log("LocalVisualPerf FAIL: " + vp_summary);

        if vp_attempt >= vp_max_attempts {
            break;
        }

        // Fix focused on visual/perf failures, then retry
        phase("Fix");
        vp_fix_round += 1;
        log("Visual/perf fix round " + vp_fix_round.to_string() + "/" + max_vp_fix.to_string());

        let vp_fix_prompt = "";
        vp_fix_prompt += "You are the FIXER after a failed LOCAL visual/performance final test.\n";
        vp_fix_prompt += "Repair root causes so the next local visual+perf run can pass. Stay in scope of the process file.\n";
        vp_fix_prompt += "Process file: " + written_plan + "\n";
        vp_fix_prompt += "User goal: " + plan_goal + "\n";
        vp_fix_prompt += "Visual failures / evidence:\n" + vp_visual_evidence + "\n";
        vp_fix_prompt += "Perf failures / evidence:\n" + vp_perf_evidence + "\n";
        vp_fix_prompt += "Failures:\n" + vp_failures_blob;
        vp_fix_prompt += "Commands that were run:\n" + vp_commands_blob;
        vp_fix_prompt += "Summary: " + vp_summary + "\n";
        vp_fix_prompt += "REQUIRED: read process file + failing code; fix; update process file Verification log; do not skip local retest (next agent will retest).\n";

        let vp_fix_r = agent(vp_fix_prompt, #{
            label: "fix-visual-perf:" + vp_fix_round.to_string(),
            capability_mode: "all",
            output_schema: fix_schema,
        });

        if vp_fix_r != () && vp_fix_r.success && vp_fix_r.output != () {
            let fo = vp_fix_r.output;
            let fs = if fo.summary != () { fo.summary } else { "(no summary)" };
            vp_fix_summaries += "- vp round " + vp_fix_round.to_string() + ": " + fs + "\n";
            log("Visual/perf fix: " + fs);
            let more = join_lines(fo.files_changed, "- ");
            if more != "" { files_changed_blob += more; }
        } else {
            vp_fix_summaries += "- vp round " + vp_fix_round.to_string() + ": fix agent failed\n";
            log("Visual/perf fix agent failed this round");
        }
    }
}

// --- Phase: Gate -------------------------------------------------------------

phase("Gate");
log("Completion gate (tests_passed=" + tests_passed.to_string()
    + " visual_perf_passed=" + visual_perf_passed.to_string() + ")");

let gate_prompt = "";
gate_prompt += "You are the COMPLETION GATE for a universal implement-from-plan workflow. Fail closed.\n";
gate_prompt += "complete=true ONLY if: process done criteria met, build/unit verification passed, ";
gate_prompt += "AND mandatory local visual + performance final test passed with on-machine evidence.\n";
gate_prompt += "Process file: " + written_plan + "\n";
gate_prompt += "User goal: " + plan_goal + "\n";
gate_prompt += "Done criteria:\n" + done_blob;
gate_prompt += "Implement summary: " + impl_summary + "\n";
gate_prompt += "Blocked steps:\n" + blocked_blob;
gate_prompt += "Remaining (from implementer): " + remaining + "\n";
gate_prompt += "tests_passed flag: " + tests_passed.to_string() + "\n";
gate_prompt += "visual_perf_passed flag: " + visual_perf_passed.to_string() + "\n";
gate_prompt += "local_machine_confirmed: " + vp_local_confirmed.to_string() + "\n";
gate_prompt += "visual_passed: " + vp_visual_passed.to_string() + " perf_passed: " + vp_perf_passed.to_string() + "\n";
gate_prompt += "Last unit verify summary: " + last_test_summary + "\n";
gate_prompt += "Last unit failures:\n" + last_failures_blob;
gate_prompt += "Last unit evidence:\n" + last_evidence + "\n";
gate_prompt += "Local visual+perf summary: " + vp_summary + "\n";
gate_prompt += "Visual evidence:\n" + vp_visual_evidence + "\n";
gate_prompt += "Perf evidence:\n" + vp_perf_evidence + "\n";
gate_prompt += "Visual/perf failures:\n" + vp_failures_blob;
gate_prompt += "Visual/perf commands:\n" + vp_commands_blob;
gate_prompt += "Artifacts:\n" + vp_artifacts_blob;
gate_prompt += "Unit fix rounds:\n" + fix_summaries;
gate_prompt += "Visual/perf fix rounds:\n" + vp_fix_summaries;
gate_prompt += "REQUIRED:\n";
gate_prompt += "1) read_file the process file and spot-check claimed-done steps + Local visual+perf section.\n";
gate_prompt += "2) verdict must be exactly one of: COMPLETE | INCOMPLETE | BLOCKED\n";
gate_prompt += "3) complete=true only with COMPLETE, tests_passed, and visual_perf_passed all satisfied.\n";
gate_prompt += "4) If tests_passed is false OR visual_perf_passed is false, complete must be false.\n";
gate_prompt += "5) unmet_criteria lists what is still open; next_steps are concrete.\n";
gate_prompt += "6) Optionally update process file final status line if incomplete.\n";

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

// Hard fail-closed overrides in the script (agents don't enforce invariants)
if !tests_passed || !visual_perf_passed {
    is_complete = false;
    if verdict == "COMPLETE" { verdict = "INCOMPLETE"; }
}
if is_complete && verdict != "COMPLETE" {
    // complete flag without COMPLETE verdict → force incomplete
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
        unmet_blob = "- verification, local visual, and/or performance criteria not fully met\n";
    }
}
if next_blob == "" {
    if is_complete {
        next_blob = "- Review the process file and commit when ready\n";
    } else {
        next_blob = "- Resume work from " + written_plan + " and re-run this workflow\n";
        if !visual_perf_passed {
            next_blob += "- Ensure local visual + performance commands succeed on this machine\n";
        }
    }
}
if headline == "" {
    if is_complete {
        headline = "Process complete; build/unit and local visual+performance final tests passed.";
    } else {
        headline = "Not complete — see unmet criteria (includes local visual/perf if pending).";
    }
}

// Final report artifact
let md = "";
md += "# implement-from-plan report\n\n";
md += "**Verdict:** " + verdict + "\n\n";
md += "**Complete:** " + is_complete.to_string() + "\n\n";
md += "**Headline:** " + headline + "\n\n";
md += "## Goal\n\n" + plan_goal + "\n\n";
md += "## Process file\n\n`" + written_plan + "`\n\n";
md += "## Sources\n\n" + sources_blob + "\n";
md += "## Ingest\n\n" + ingest_summary + "\n\n";
md += "### Constraints\n\n" + constraints_blob + "\n";
md += "### Risks\n\n" + risks_blob + "\n";
md += "## Implementation\n\n" + impl_summary + "\n\n";
md += "### Steps done\n\n" + steps_done_blob + "\n";
md += "### Blocked\n\n" + blocked_blob + "\n";
md += "### Files changed\n\n" + files_changed_blob + "\n";
md += "## Build / unit verification\n\n";
md += "- tests_passed: " + tests_passed.to_string() + "\n";
md += "- attempts: " + attempt.to_string() + " / " + max_attempts.to_string() + "\n";
md += "- fix_rounds: " + fix_round.to_string() + " / " + max_fix.to_string() + "\n";
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
md += "## Local visual + performance final test\n\n";
md += "- attempted: " + vp_attempted.to_string() + "\n";
md += "- visual_perf_passed: " + visual_perf_passed.to_string() + "\n";
md += "- local_machine_confirmed: " + vp_local_confirmed.to_string() + "\n";
md += "- visual_passed: " + vp_visual_passed.to_string() + "\n";
md += "- perf_passed: " + vp_perf_passed.to_string() + "\n";
md += "- vp_fix_rounds: " + vp_fix_round.to_string() + " / " + max_vp_fix.to_string() + "\n";
md += "- summary: " + vp_summary + "\n\n";
md += "### Commands\n\n" + vp_commands_blob + "\n";
md += "### Visual evidence\n\n" + vp_visual_evidence + "\n\n";
md += "### Performance evidence\n\n" + vp_perf_evidence + "\n\n";
md += "### Artifacts\n\n" + vp_artifacts_blob + "\n";
md += "### Failures\n\n" + vp_failures_blob + "\n";
md += "### Visual/perf fix log\n\n";
if vp_fix_summaries == "" {
    md += "- (no visual/perf fix rounds)\n\n";
} else {
    md += vp_fix_summaries + "\n";
}
md += "## Unmet criteria\n\n" + unmet_blob + "\n";
md += "## Next steps\n\n" + next_blob + "\n";
md += "## Plan summary artifact\n\n" + plan_scratch_path + "\n";

let report_path = write_scratch_file("implement-from-plan-report.md", md);
log("Gate: " + verdict + " (complete=" + is_complete.to_string() + ")");

// Always complete() the workflow run successfully as orchestration;
// the result object carries complete=false when the feature is not done.
complete(#{
    path: report_path,
    plan_path: written_plan,
    plan_summary: plan_scratch_path,
    verdict: verdict,
    complete: is_complete,
    headline: headline,
    tests_passed: tests_passed,
    visual_perf_passed: visual_perf_passed,
    local_machine_confirmed: vp_local_confirmed,
    visual_passed: vp_visual_passed,
    perf_passed: vp_perf_passed,
    fix_rounds: fix_round,
    max_fix_rounds: max_fix,
    visual_perf_fix_rounds: vp_fix_round,
    max_visual_perf_fix_rounds: max_vp_fix,
    implement_ok: impl_ok,
});
