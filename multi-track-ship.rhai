let meta = #{
    name: "multi-track-ship",
    description: "Multi-track ship: read a multi-area plan, implement tracks (not one solo agent), run a shared visible QA pipeline after tracks/fixes, local visual+perf, fail-closed complete",
    when_to_use: "Large multi-area work (structures, systems) with parallel concerns, shared test artifacts the user can open, and fix-all-issues loops — not single-file micro tasks",
    phases: [
        #{ title: "Ingest", detail: "read sources; map tracks and foundation" },
        #{ title: "Plan", detail: "write process file with tracks + pipeline contract" },
        #{ title: "Approve", detail: "optional human gate" },
        #{ title: "Tracks", detail: "implement each track (sequential ownership)" },
        #{ title: "Pipeline", detail: "shared QA pipeline; artifacts on disk" },
        #{ title: "Diagnose", detail: "parallel per failing track" },
        #{ title: "Fix", detail: "fix issues; re-run pipeline" },
        #{ title: "LocalVisualPerf", detail: "mandatory local visual + performance" },
        #{ title: "Gate", detail: "complete only if tracks + pipeline + visual/perf pass" },
    ],
};

// --- schemas -----------------------------------------------------------------

let ingest_schema = #{
    "type": "object",
    "required": ["summary", "tracks", "excluded", "foundation_notes", "pipeline_hints", "risks"],
    "properties": #{
        "summary": #{ "type": "string" },
        "tracks": #{
            "type": "array",
            "maxItems": 16,
            "items": #{
                "type": "object",
                "required": ["id", "title", "priority", "files", "acceptance"],
                "properties": #{
                    "id": #{ "type": "string" },
                    "title": #{ "type": "string" },
                    "priority": #{ "type": "integer" },
                    "files": #{ "type": "array", "maxItems": 20, "items": #{ "type": "string" } },
                    "acceptance": #{ "type": "string" },
                },
            },
        },
        "excluded": #{ "type": "array", "maxItems": 20, "items": #{ "type": "string" } },
        "foundation_notes": #{ "type": "string" },
        "pipeline_hints": #{ "type": "string" },
        "qa_dir": #{ "type": "string" },
        "visual_command": #{ "type": "string" },
        "perf_command": #{ "type": "string" },
        "risks": #{ "type": "array", "maxItems": 16, "items": #{ "type": "string" } },
    },
};

let plan_schema = #{
    "type": "object",
    "required": ["plan_path", "goal", "track_order", "pipeline_mode", "qa_dir", "notes"],
    "properties": #{
        "plan_path": #{ "type": "string" },
        "goal": #{ "type": "string" },
        "track_order": #{
            "type": "array",
            "maxItems": 16,
            "items": #{ "type": "string" },
        },
        "pipeline_mode": #{ "type": "string" },
        "qa_dir": #{ "type": "string" },
        "notes": #{ "type": "string" },
    },
};

let track_impl_schema = #{
    "type": "object",
    "required": ["track_id", "summary", "status", "files_changed", "acceptance_met", "blocked_reason", "plan_updated"],
    "properties": #{
        "track_id": #{ "type": "string" },
        "summary": #{ "type": "string" },
        "status": #{ "type": "string" },
        "files_changed": #{ "type": "array", "maxItems": 40, "items": #{ "type": "string" } },
        "acceptance_met": #{ "type": "boolean" },
        "blocked_reason": #{ "type": "string" },
        "plan_updated": #{ "type": "boolean" },
    },
};

let pipeline_schema = #{
    "type": "object",
    "required": ["passed", "commands_run", "artifacts", "track_results", "summary", "failures", "evidence"],
    "properties": #{
        "passed": #{ "type": "boolean" },
        "commands_run": #{ "type": "array", "maxItems": 30, "items": #{ "type": "string" } },
        "artifacts": #{ "type": "array", "maxItems": 40, "items": #{ "type": "string" } },
        "track_results": #{
            "type": "array",
            "maxItems": 16,
            "items": #{
                "type": "object",
                "required": ["track_id", "ok", "note"],
                "properties": #{
                    "track_id": #{ "type": "string" },
                    "ok": #{ "type": "boolean" },
                    "note": #{ "type": "string" },
                },
            },
        },
        "summary": #{ "type": "string" },
        "failures": #{ "type": "array", "maxItems": 40, "items": #{ "type": "string" } },
        "evidence": #{ "type": "string" },
    },
};

let diagnose_schema = #{
    "type": "object",
    "required": ["track_id", "root_causes", "fix_actions", "evidence"],
    "properties": #{
        "track_id": #{ "type": "string" },
        "root_causes": #{ "type": "array", "maxItems": 12, "items": #{ "type": "string" } },
        "fix_actions": #{ "type": "array", "maxItems": 12, "items": #{ "type": "string" } },
        "evidence": #{ "type": "string" },
    },
};

let fix_schema = #{
    "type": "object",
    "required": ["summary", "fixed", "files_changed", "plan_updated", "still_failing"],
    "properties": #{
        "summary": #{ "type": "string" },
        "fixed": #{ "type": "array", "maxItems": 30, "items": #{ "type": "string" } },
        "files_changed": #{ "type": "array", "maxItems": 40, "items": #{ "type": "string" } },
        "plan_updated": #{ "type": "boolean" },
        "still_failing": #{ "type": "string" },
    },
};

let visual_perf_schema = #{
    "type": "object",
    "required": [
        "passed", "local_machine_confirmed", "visual_passed", "perf_passed",
        "commands_run", "visual_evidence", "perf_evidence", "artifacts", "summary", "failures",
    ],
    "properties": #{
        "passed": #{ "type": "boolean" },
        "local_machine_confirmed": #{ "type": "boolean" },
        "visual_passed": #{ "type": "boolean" },
        "perf_passed": #{ "type": "boolean" },
        "commands_run": #{ "type": "array", "maxItems": 30, "items": #{ "type": "string" } },
        "visual_evidence": #{ "type": "string" },
        "perf_evidence": #{ "type": "string" },
        "artifacts": #{ "type": "array", "maxItems": 40, "items": #{ "type": "string" } },
        "summary": #{ "type": "string" },
        "failures": #{ "type": "array", "maxItems": 30, "items": #{ "type": "string" } },
    },
};

let gate_schema = #{
    "type": "object",
    "required": ["complete", "verdict", "headline", "unmet_criteria", "next_steps"],
    "properties": #{
        "complete": #{ "type": "boolean" },
        "verdict": #{ "type": "string" },
        "headline": #{ "type": "string" },
        "unmet_criteria": #{ "type": "array", "maxItems": 20, "items": #{ "type": "string" } },
        "next_steps": #{ "type": "array", "maxItems": 12, "items": #{ "type": "string" } },
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
            if t != "" { out += prefix + t + "\n"; }
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

fn first_text(primary, secondary) {
    let chosen = trimmed(primary);
    if chosen != "" { return chosen; }
    trimmed(secondary)
}

fn rel_dir(raw) {
    let text = trimmed(raw);
    if text == "" { return ""; }
    if text.contains("..") { return ""; }
    if text.contains("\\") { return ""; }
    if text.contains("\n") { return ""; }
    if text.sub_string(0, 1) == "/" { return ""; }
    text
}

fn visual_hint_for(cmd, dir) {
    let command = trimmed(cmd);
    if command != "" { return "Prefer visual command: " + command; }
    "Run the plan's building-qa / preview / in-game visual checks; write notes under " + dir + "/visual_notes.md. Must run on this local machine."
}

fn perf_hint_for(cmd, dir) {
    let command = trimmed(cmd);
    if command != "" { return "Prefer perf command: " + command; }
    "Run local perf smoke (benchmark script or Launch_benchmark) and copy results into " + dir + "/"
}

fn hint_self_check() {
    if first_text("from-arg", "from-plan") != "from-arg" { return "arg wins"; }
    if first_text("", "from-plan") != "from-plan" { return "plan fills empty"; }
    if first_text((), ()) != "" { return "empty hint"; }
    if rel_dir("../qa") != "" { return "reject parent"; }
    if rel_dir("/tmp/qa") != "" { return "reject abs"; }
    if rel_dir("qa/feature") != "qa/feature" { return "keep rel"; }
    let visual = visual_hint_for("pnpm test:visual", "qa/feature");
    if !visual.contains("Prefer visual command: pnpm test:visual") { return "visual command"; }
    if visual.contains("building-qa") { return "visual default leaked"; }
    let fallback = visual_hint_for("", "qa/structures");
    if !fallback.contains("building-qa") { return "visual default"; }
    if !fallback.contains("qa/structures/visual_notes.md") { return "visual dir"; }
    let perf = perf_hint_for("pnpm test:perf", "qa/feature");
    if !perf.contains("Prefer perf command: pnpm test:perf") { return "perf command"; }
    if perf.contains("Launch_benchmark") { return "perf default leaked"; }
    let perf_fallback = perf_hint_for("", "qa/feature");
    if !perf_fallback.contains("Launch_benchmark") { return "perf default"; }
    if !perf_fallback.contains("qa/feature/") { return "perf dir"; }
    ""
}

// --- args --------------------------------------------------------------------

let sources_arg = if args == () { () } else { args.sources };
if sources_arg == () && args != () { sources_arg = args.files; }
if sources_arg == () && args != () { sources_arg = args.source; }

let goal_arg = if args == () { () } else { args.goal };
let plan_path_arg = if args == () { () } else { args.plan_path };
let qa_dir_arg = if args == () { () } else { args.qa_dir };
let pipeline_mode_arg = if args == () { () } else { args.pipeline_mode };
let auto_approve = bool_arg(if args == () { () } else { args.auto_approve_plan }, false);

let max_fix = int_arg(if args == () { () } else { args.max_fix_rounds }, 3, 1, 5);
let max_vp_fix = int_arg(if args == () { () } else { args.max_visual_perf_fix_rounds }, 2, 0, 4);

let visual_cmd_arg = if args == () { () } else { args.visual_command };
let perf_cmd_arg = if args == () { () } else { args.perf_command };
if perf_cmd_arg == () && args != () { perf_cmd_arg = args.perf; }

// parse sources list
let sources_list = [];
if sources_arg == () {
} else if type_of(sources_arg) == "array" {
    for s in sources_arg {
        let t = trimmed(s.to_string());
        if t != "" { sources_list.push(t); }
    }
} else {
    let raw = trimmed(sources_arg.to_string());
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

let hint_error = hint_self_check();
if hint_error != "" {
    pause("verification", "multi-track-ship hint self-check failed: " + hint_error);
}

if sources_list.len() == 0 {
    pause("verification", "Pass args.sources — multi-track plan file(s). Optional: goal, plan_path, qa_dir, pipeline_mode (after_each|batch|both), auto_approve_plan, max_fix_rounds, visual_command, perf_command.");
}

let sources_blob = "";
for s in sources_list { sources_blob += "- " + s + "\n"; }

let goal_text = if goal_arg == () || trimmed(goal_arg.to_string()) == "" {
    "Ship all tracks in the multi-track plan (exclude any marked DONE foundation). Use multi-agent tracks + shared visible QA pipeline."
} else {
    trimmed(goal_arg.to_string())
};

let plan_path = if plan_path_arg == () || trimmed(plan_path_arg.to_string()) == "" {
    "IMPLEMENTATION_PROCESS_MULTI_TRACK.md"
} else {
    trimmed(plan_path_arg.to_string())
};

let qa_from_arg = false;
let qa_dir = "qa/structures";
if qa_dir_arg != () && trimmed(qa_dir_arg.to_string()) != "" {
    qa_from_arg = true;
    qa_dir = trimmed(qa_dir_arg.to_string());
}

let pipeline_mode = if pipeline_mode_arg == () || trimmed(pipeline_mode_arg.to_string()) == "" {
    "both"
} else {
    trimmed(pipeline_mode_arg.to_string())
};
// normalize
if pipeline_mode != "after_each" && pipeline_mode != "batch" && pipeline_mode != "both" {
    pipeline_mode = "both";
}

// --- Phase 1: Ingest ---------------------------------------------------------

phase("Ingest");
log("Ingest multi-track plan (" + sources_list.len().to_string() + " source(s))");

let ingest_prompt = "";
ingest_prompt += "You are INGEST for multi-track-ship. Multi-agent workflow — extract TRACKS, not a single blob of work.\n";
ingest_prompt += "User goal: " + goal_text + "\n";
ingest_prompt += "Sources (read fully with read_file):\n" + sources_blob;
ingest_prompt += "REQUIRED:\n";
ingest_prompt += "1) Read every source. Honor EXCLUSIONS / DONE foundation — do not re-open finished phases.\n";
ingest_prompt += "2) Extract ordered tracks with id, title, priority (lower first), key files, acceptance.\n";
ingest_prompt += "3) foundation_notes: what is already shipped and must not be rewritten.\n";
ingest_prompt += "4) pipeline_hints: shared QA pipeline steps and artifact dirs from the plan (default qa dir: " + qa_dir + ").\n";
ingest_prompt += "5) Copy qa_dir, visual_command, and perf_command only when the source plan states them. Leave each one empty when it is absent. Do not invent a command.\n";
ingest_prompt += "6) risks: merge conflicts, sequential file ownership needs.\n";
ingest_prompt += "Use tools. Empty tracks is invalid if the plan lists work.\n";

let ingest_r = agent(ingest_prompt, #{
    label: "ingest",
    capability_mode: "execute",
    output_schema: ingest_schema,
});

if ingest_r == () || !ingest_r.success || ingest_r.output == () {
    pause("infra", "Ingest failed. Resume or re-run with clearer args.sources.");
}

let ingest = ingest_r.output;
let ingest_summary = if ingest.summary != () { ingest.summary } else { "(no summary)" };
let foundation = if ingest.foundation_notes != () { ingest.foundation_notes } else { "" };
let pipeline_hints = if ingest.pipeline_hints != () { ingest.pipeline_hints } else { "Use " + qa_dir + " for all pipeline artifacts." };
if !qa_from_arg {
    let planned_dir = rel_dir(if ingest.qa_dir != () { ingest.qa_dir } else { "" });
    if planned_dir != "" { qa_dir = planned_dir; }
}
let visual_cmd = first_text(visual_cmd_arg, if ingest.visual_command != () { ingest.visual_command } else { "" });
let perf_cmd = first_text(perf_cmd_arg, if ingest.perf_command != () { ingest.perf_command } else { "" });
if visual_cmd != "" { pipeline_hints += "\nvisual_command: " + visual_cmd; }
if perf_cmd != "" { pipeline_hints += "\nperf_command: " + perf_cmd; }
let risks_blob = join_lines(ingest.risks, "- ");
let excluded_blob = join_lines(ingest.excluded, "- ");
if risks_blob == "" { risks_blob = "- (none)\n"; }
if excluded_blob == "" { excluded_blob = "- (see plan)\n"; }

let tracks = [];
if ingest.tracks != () {
    for t in ingest.tracks {
        if t.id != () && trimmed(t.id) != "" {
            tracks.push(t);
        }
    }
}
// sort by priority ascending (simple insertion)
let sorted = [];
while tracks.len() > 0 {
    let best_i = 0;
    let best_p = 9999;
    let ti = 0;
    for t in tracks {
        let p = 100;
        if t.priority != () { p = t.priority; }
        if p < best_p {
            best_p = p;
            best_i = ti;
        }
        ti += 1;
    }
    // extract tracks[best_i]
    let nj = 0;
    let chosen = ();
    let rest = [];
    for t in tracks {
        if nj == best_i { chosen = t; } else { rest.push(t); }
        nj += 1;
    }
    if chosen != () { sorted.push(chosen); }
    tracks = rest;
}
tracks = sorted;

if tracks.len() == 0 {
    pause("verification", "Ingest found zero tracks. Plan must list multi-track work. Fix sources and resume.");
}

let tracks_blob = "";
for t in tracks {
    let id = if t.id != () { t.id } else { "?" };
    let title = if t.title != () { t.title } else { "" };
    let acc = if t.acceptance != () { t.acceptance } else { "" };
    let files = join_lines(t.files, "    ");
    tracks_blob += "- " + id + ": " + title + "\n  acceptance: " + acc + "\n  files:\n" + files;
}

log("Tracks: " + tracks.len().to_string() + " — " + ingest_summary);

// --- Phase 2: Plan -----------------------------------------------------------

phase("Plan");
log("Writing multi-track process file → " + plan_path);

let plan_prompt = "";
plan_prompt += "You are PLANNER for multi-track-ship. Write a durable PROCESS FILE for multi-agent execution.\n";
plan_prompt += "Path: " + plan_path + " (WRITE with tools).\n";
plan_prompt += "QA dir (user-visible artifacts): " + qa_dir + "\n";
plan_prompt += "pipeline_mode: " + pipeline_mode + "\n";
plan_prompt += "Goal: " + goal_text + "\n";
plan_prompt += "Ingest: " + ingest_summary + "\n";
plan_prompt += "Foundation (DO NOT REDO):\n" + foundation + "\n";
plan_prompt += "Excluded:\n" + excluded_blob;
plan_prompt += "Tracks (ordered):\n" + tracks_blob;
plan_prompt += "Pipeline hints:\n" + pipeline_hints + "\n";
plan_prompt += "Risks:\n" + risks_blob;
plan_prompt += "REQUIRED markdown sections:\n";
plan_prompt += "# Implementation Process (Multi-Track)\n## Goal\n## Foundation (done — do not redo)\n## Excluded\n";
plan_prompt += "## Shared QA pipeline\n- qa_dir, modes, P1–P8 steps, artifact paths\n";
plan_prompt += "## Tracks\n### Track <id>: title\n- Status: pending\n- Owner files\n- Actions\n- Acceptance\n- Pipeline checks\n";
plan_prompt += "## Diagnose/Fix policy\n## Done criteria\n## Verification log\n";
plan_prompt += "Rules: sequential track order unless non-overlapping; after_each/batch/both honored; every track Status pending initially.\n";
plan_prompt += "Return track_order ids, pipeline_mode, qa_dir, plan_path, goal, notes.\n";

let plan_r = agent(plan_prompt, #{
    label: "plan",
    capability_mode: "read-write",
    output_schema: plan_schema,
});

if plan_r == () || !plan_r.success || plan_r.output == () {
    pause("infra", "Plan agent failed. Resume to retry.");
}

let plan = plan_r.output;
let written_plan = if plan.plan_path != () && trimmed(plan.plan_path) != "" {
    trimmed(plan.plan_path)
} else {
    plan_path
};
let plan_goal = if plan.goal != () { plan.goal } else { goal_text };
if plan.qa_dir != () && trimmed(plan.qa_dir) != "" { qa_dir = trimmed(plan.qa_dir); }
if plan.pipeline_mode != () && trimmed(plan.pipeline_mode) != "" {
    let pm = trimmed(plan.pipeline_mode);
    if pm == "after_each" || pm == "batch" || pm == "both" { pipeline_mode = pm; }
}

// Prefer planner track_order if present
let order_ids = [];
if plan.track_order != () {
    for id in plan.track_order {
        let t = trimmed(id.to_string());
        if t != "" { order_ids.push(t); }
    }
}
if order_ids.len() == 0 {
    for t in tracks {
        if t.id != () { order_ids.push(trimmed(t.id)); }
    }
}

let order_blob = "";
for id in order_ids { order_blob += "- " + id + "\n"; }

log("Process: " + written_plan + " | mode=" + pipeline_mode + " | qa=" + qa_dir);

let plan_scratch = "";
plan_scratch += "# Multi-track plan summary\n\n";
plan_scratch += "**Path:** " + written_plan + "\n**QA dir:** " + qa_dir + "\n**Mode:** " + pipeline_mode + "\n\n";
plan_scratch += "## Tracks\n" + order_blob + "\n";
plan_scratch += "## Goal\n" + plan_goal + "\n";
let plan_scratch_path = write_scratch_file("multi-track-plan-summary.md", plan_scratch);

// --- Phase 3: Approve --------------------------------------------------------

phase("Approve");
if !auto_approve {
    await_user("user", "Multi-track process written to " + written_plan + "\nTracks:\n" + order_blob + "QA artifacts will land in " + qa_dir + "\nResume to implement, or edit the process file first.");
} else {
    log("auto_approve_plan=true — skipping plan gate");
}

// --- helper: run pipeline agent ----------------------------------------------

// Rhai nested fns do not close over outer lets — pass schema in explicitly.
fn run_pipeline(label_sfx, written_plan, qa_dir, plan_goal, tracks_blob, order_blob, mode_note, full, pipe_schema) {
    let pp = "";
    pp += "You are the SHARED QA PIPELINE RUNNER for multi-track-ship. Fail closed. User must be able to open artifacts.\n";
    pp += "Process file: " + written_plan + "\n";
    pp += "QA directory (CREATE if needed): " + qa_dir + "\n";
    pp += "Goal: " + plan_goal + "\n";
    pp += "Mode note: " + mode_note + "\n";
    pp += "Tracks:\n" + order_blob;
    pp += "Track details:\n" + tracks_blob;
    pp += "REQUIRED:\n";
    pp += "1) read_file process file for pipeline steps and track acceptances.\n";
    pp += "2) Ensure " + qa_dir + " exists. Write/update " + qa_dir + "/README.md if missing.\n";
    if full {
        pp += "3) FULL pipeline: build engine, build tests, ctest, building-qa (or plan equivalent), track_checks, visual notes, perf smoke if plan requires, pipeline_report.md + .json.\n";
    } else {
        pp += "3) LIGHT pipeline: build affected targets + ctest if tests exist + any cheap track checks; still write logs under " + qa_dir + ".\n";
    }
    pp += "4) Copy or write all logs/JSON under " + qa_dir + ". List every artifact path in output.\n";
    pp += "5) track_results: one entry per track_id with ok true/false and note (unknown if not yet verifiable).\n";
    pp += "6) passed=true only if hard steps succeed AND evidence non-empty. Quote exit codes in evidence.\n";
    pp += "7) Append Verification log lines to the process file.\n";
    pp += "Use shell tools on THIS machine. Do not claim pass without files on disk.\n";

    let r = agent(pp, #{
        label: "pipeline:" + label_sfx,
        capability_mode: "all",
        output_schema: pipe_schema,
    });
    r
}

// --- Phase 4: Tracks (sequential implementers) -------------------------------

phase("Tracks");
log("Implementing " + order_ids.len().to_string() + " track(s) sequentially");

let track_summaries = "";
let files_all = "";
let tracks_ok = 0;
let tracks_blocked = 0;
let ti = 0;

for tid in order_ids {
    ti += 1;
    // find track meta
    let meta_t = ();
    for t in tracks {
        if t.id != () && trimmed(t.id) == tid { meta_t = t; }
    }
    let title = if meta_t != () && meta_t.title != () { meta_t.title } else { tid };
    let acc = if meta_t != () && meta_t.acceptance != () { meta_t.acceptance } else { "" };
    let files = if meta_t != () { join_lines(meta_t.files, "- ") } else { "" };

    log("Track " + ti.to_string() + "/" + order_ids.len().to_string() + ": " + tid);

    let ip = "";
    ip += "You are TRACK IMPLEMENTER for multi-track-ship. You own ONE track only.\n";
    ip += "Track id: " + tid + "\nTitle: " + title + "\n";
    ip += "Acceptance: " + acc + "\n";
    ip += "Likely files:\n" + files;
    ip += "Process file: " + written_plan + " (read first; update this track Status).\n";
    ip += "Goal: " + plan_goal + "\n";
    ip += "Foundation (DO NOT REDO / break):\n" + foundation + "\n";
    ip += "Excluded:\n" + excluded_blob;
    ip += "QA dir for any track-local notes: " + qa_dir + "\n";
    ip += "REQUIRED:\n";
    ip += "1) read process file + current code for this track.\n";
    ip += "2) Implement ONLY this track. Do not freestyle other tracks.\n";
    ip += "3) Build after meaningful edits when possible.\n";
    ip += "4) Update process file Status: done|blocked and Result line.\n";
    ip += "5) status field: done | blocked | partial. acceptance_met true only if acceptance satisfied.\n";
    ip += "Stay in scope. Atomic, compiling changes.\n";

    let ir = agent(ip, #{
        label: "track:" + tid,
        capability_mode: "all",
        output_schema: track_impl_schema,
    });

    let st = "failed";
    let sum = "track agent failed";
    let met = false;
    if ir != () && ir.success && ir.output != () {
        let o = ir.output;
        if o.status != () { st = trimmed(o.status); }
        if o.summary != () { sum = o.summary; }
        if o.acceptance_met == true { met = true; }
        let more = join_lines(o.files_changed, "- ");
        if more != "" { files_all += more; }
        if o.blocked_reason != () && trimmed(o.blocked_reason) != "" {
            sum += " | blocked: " + o.blocked_reason;
        }
    }
    track_summaries += "- " + tid + " [" + st + "] met=" + met.to_string() + ": " + sum + "\n";
    if met || st == "done" { tracks_ok += 1; }
    if st == "blocked" { tracks_blocked += 1; }

    // light pipeline after each track when mode says so
    if pipeline_mode == "after_each" || pipeline_mode == "both" {
        phase("Pipeline");
        log("Light pipeline after track " + tid);
        let pr = run_pipeline("after-" + tid, written_plan, qa_dir, plan_goal, tracks_blob, order_blob, "light after_each for " + tid, false, pipeline_schema);
        if pr != () && pr.success && pr.output != () {
            log("Pipeline after " + tid + ": " + (if pr.output.summary != () { pr.output.summary } else { "" }));
        }
    }
}

log("Tracks finished: ok-ish=" + tracks_ok.to_string() + " blocked=" + tracks_blocked.to_string());

// --- Phase 5+6: Full pipeline + diagnose/fix loops --------------------------

let pipeline_passed = false;
let last_pipe_summary = "";
let last_pipe_failures = "";
let last_pipe_evidence = "";
let last_pipe_artifacts = "";
let last_pipe_commands = "";
let last_track_results = "";
let fix_round = 0;
let fix_log = "";

let attempt = 0;
let max_attempts = max_fix + 1;

while attempt < max_attempts {
    attempt += 1;
    phase("Pipeline");
    log("Full pipeline attempt " + attempt.to_string() + "/" + max_attempts.to_string());

    let pr = run_pipeline("full-" + attempt.to_string(), written_plan, qa_dir, plan_goal, tracks_blob, order_blob, "FULL batch pipeline", true, pipeline_schema);

    let ok = false;
    if pr != () && pr.success && pr.output != () {
        let o = pr.output;
        if o.summary != () { last_pipe_summary = o.summary; }
        if o.evidence != () { last_pipe_evidence = o.evidence; }
        last_pipe_failures = join_lines(o.failures, "- ");
        last_pipe_artifacts = join_lines(o.artifacts, "- ");
        last_pipe_commands = join_lines(o.commands_run, "- ");
        last_track_results = "";
        if o.track_results != () {
            for tr in o.track_results {
                let id = if tr.track_id != () { tr.track_id } else { "?" };
                let tok = (tr.ok == true);
                let note = if tr.note != () { tr.note } else { "" };
                last_track_results += "- " + id + " ok=" + tok.to_string() + " " + note + "\n";
            }
        }
        if o.passed == true && last_pipe_evidence != () && trimmed(last_pipe_evidence) != "" {
            ok = true;
        } else if o.passed == true {
            log("Pipeline claimed pass without evidence — fail closed");
        }
    } else {
        last_pipe_summary = "pipeline agent failed";
        last_pipe_failures = "- pipeline infrastructure failure\n";
        last_pipe_evidence = "";
    }
    if last_pipe_failures == "" { last_pipe_failures = "- (none)\n"; }
    if last_pipe_artifacts == "" { last_pipe_artifacts = "- (none listed)\n"; }

    if ok {
        pipeline_passed = true;
        log("Pipeline PASS: " + last_pipe_summary);
        break;
    }

    log("Pipeline FAIL: " + last_pipe_summary);
    if attempt >= max_attempts { break; }

    // Diagnose failing tracks in parallel
    phase("Diagnose");
    let failing_ids = [];
    // from track_results if any false; else all order_ids
    if last_track_results != "" {
        // parse crudely: if line contains ok=false
        // simpler: diagnose all order_ids when pipeline failed
    }
    for id in order_ids { failing_ids.push(id); }
    // cap diagnose fan-out
    const MAX_DIAG = 8;
    let djobs = [];
    let di = 0;
    for id in failing_ids {
        if di >= MAX_DIAG { break; }
        let dp = "";
        dp += "You are DIAGNOSE for track " + id + " after shared pipeline failure.\n";
        dp += "Process: " + written_plan + "\nQA dir: " + qa_dir + "\n";
        dp += "Pipeline summary: " + last_pipe_summary + "\n";
        dp += "Failures:\n" + last_pipe_failures;
        dp += "Evidence:\n" + last_pipe_evidence + "\n";
        dp += "Artifacts:\n" + last_pipe_artifacts;
        dp += "Track summaries so far:\n" + track_summaries;
        dp += "REQUIRED: read " + qa_dir + " logs/JSON and process file. Use tools. ";
        dp += "Return root_causes, concrete fix_actions, evidence. Default to few high-value fixes.\n";
        djobs.push(#{
            prompt: dp,
            label: "diagnose:" + id,
            capability_mode: "execute",
            output_schema: diagnose_schema,
        });
        di += 1;
    }
    let dres = parallel(djobs);
    let diag_blob = "";
    for dr in dres {
        if dr != () && dr.success && dr.output != () {
            let o = dr.output;
            let id = if o.track_id != () { o.track_id } else { "?" };
            diag_blob += "### " + id + "\n";
            diag_blob += join_lines(o.root_causes, "- cause: ");
            diag_blob += join_lines(o.fix_actions, "- fix: ");
            if o.evidence != () { diag_blob += "evidence: " + o.evidence + "\n"; }
        }
    }
    if diag_blob == "" { diag_blob = "(no diagnose output)\n"; }

    phase("Fix");
    fix_round += 1;
    log("Fix round " + fix_round.to_string() + " (attempt to fix ALL pipeline issues)");

    let fp = "";
    fp += "You are FIXER for multi-track-ship. Attempt to fix ALL reported pipeline/track issues this round.\n";
    fp += "Process: " + written_plan + "\nQA: " + qa_dir + "\n";
    fp += "Foundation (preserve):\n" + foundation + "\n";
    fp += "Track summaries:\n" + track_summaries;
    fp += "Pipeline failures:\n" + last_pipe_failures;
    fp += "Evidence:\n" + last_pipe_evidence + "\n";
    fp += "Diagnose reports:\n" + diag_blob;
    fp += "REQUIRED: read logs + code; fix root causes across tracks if needed; update process file; ";
    fp += "prefer green pipeline over perfect polish. still_failing = honest residual.\n";

    let fr = agent(fp, #{
        label: "fix:" + fix_round.to_string(),
        capability_mode: "all",
        output_schema: fix_schema,
    });

    if fr != () && fr.success && fr.output != () {
        let fo = fr.output;
        let fs = if fo.summary != () { fo.summary } else { "(no summary)" };
        fix_log += "- fix " + fix_round.to_string() + ": " + fs + "\n";
        log("Fix: " + fs);
        let more = join_lines(fo.files_changed, "- ");
        if more != "" { files_all += more; }
    } else {
        fix_log += "- fix " + fix_round.to_string() + ": agent failed\n";
    }
}

// --- Phase: Local visual + perf ----------------------------------------------

let visual_perf_passed = false;
let vp_local = false;
let vp_vis = false;
let vp_perf = false;
let vp_summary = "";
let vp_vis_ev = "";
let vp_perf_ev = "";
let vp_art = "";
let vp_fail = "";
let vp_cmds = "";
let vp_fix_round = 0;
let vp_fix_log = "";

let visual_hint = visual_hint_for(visual_cmd, qa_dir);
let perf_hint = perf_hint_for(perf_cmd, qa_dir);

if !pipeline_passed {
    log("Skipping LocalVisualPerf — shared pipeline not green");
    vp_summary = "Skipped: pipeline not passed";
    vp_fail = "- prerequisite pipeline failed\n";
} else {
    let vp_attempt = 0;
    let vp_max = max_vp_fix + 1;
    while vp_attempt < vp_max {
        vp_attempt += 1;
        phase("LocalVisualPerf");
        log("Local visual+perf " + vp_attempt.to_string() + "/" + vp_max.to_string());

        let vp = "";
        vp += "You are LOCAL VISUAL + PERFORMANCE final tester. Fail closed. Run on THIS machine.\n";
        vp += "Process: " + written_plan + "\nQA dir: " + qa_dir + "\n";
        vp += "Goal: " + plan_goal + "\n";
        vp += "Visual: " + visual_hint + "\n";
        vp += "Perf: " + perf_hint + "\n";
        vp += "Pipeline artifacts already at " + qa_dir + " — re-run or extend with visual/perf evidence.\n";
        vp += "REQUIRED: real local commands; visual_evidence + perf_evidence non-empty; ";
        vp += "local_machine_confirmed=true; copy key outputs into " + qa_dir + "; ";
        vp += "passed only if BOTH visual_passed and perf_passed.\n";

        let vr = agent(vp, #{
            label: "local-visual-perf:" + vp_attempt.to_string(),
            capability_mode: "all",
            output_schema: visual_perf_schema,
        });

        let this_ok = false;
        if vr != () && vr.success && vr.output != () {
            let o = vr.output;
            vp_local = (o.local_machine_confirmed == true);
            vp_vis = (o.visual_passed == true);
            vp_perf = (o.perf_passed == true);
            if o.summary != () { vp_summary = o.summary; }
            if o.visual_evidence != () { vp_vis_ev = o.visual_evidence; }
            if o.perf_evidence != () { vp_perf_ev = o.perf_evidence; }
            vp_fail = join_lines(o.failures, "- ");
            vp_cmds = join_lines(o.commands_run, "- ");
            vp_art = join_lines(o.artifacts, "- ");
            let ve_ok = trimmed(vp_vis_ev) != "";
            let pe_ok = trimmed(vp_perf_ev) != "";
            if o.passed == true && vp_local && vp_vis && vp_perf && ve_ok && pe_ok {
                this_ok = true;
            }
        } else {
            vp_summary = "visual/perf agent failed";
            vp_fail = "- agent failure\n";
            vp_local = false;
            vp_vis = false;
            vp_perf = false;
        }
        if vp_fail == "" { vp_fail = "- (none)\n"; }

        if this_ok {
            visual_perf_passed = true;
            log("LocalVisualPerf PASS");
            break;
        }
        log("LocalVisualPerf FAIL: " + vp_summary);
        if vp_attempt >= vp_max { break; }

        phase("Fix");
        vp_fix_round += 1;
        let vfp = "";
        vfp += "FIX after failed local visual/perf. Process: " + written_plan + " QA: " + qa_dir + "\n";
        vfp += "Vis: " + vp_vis_ev + "\nPerf: " + vp_perf_ev + "\nFail:\n" + vp_fail;
        vfp += "Fix root causes; update process file.\n";
        let vfr = agent(vfp, #{
            label: "fix-vp:" + vp_fix_round.to_string(),
            capability_mode: "all",
            output_schema: fix_schema,
        });
        if vfr != () && vfr.success && vfr.output != () {
            let fs = if vfr.output.summary != () { vfr.output.summary } else { "" };
            vp_fix_log += "- " + fs + "\n";
        }
    }
}

// --- Gate --------------------------------------------------------------------

phase("Gate");
log("Gate pipeline=" + pipeline_passed.to_string() + " visual_perf=" + visual_perf_passed.to_string());

let gp = "";
gp += "COMPLETION GATE multi-track-ship. Fail closed.\n";
gp += "complete=true only if all track acceptances met (or honest residual listed as unmet), ";
gp += "shared pipeline passed with artifacts under " + qa_dir + ", and local visual+perf passed.\n";
gp += "Process: " + written_plan + "\n";
gp += "Goal: " + plan_goal + "\n";
gp += "Track summaries:\n" + track_summaries;
gp += "pipeline_passed=" + pipeline_passed.to_string() + " visual_perf_passed=" + visual_perf_passed.to_string() + "\n";
gp += "Pipeline: " + last_pipe_summary + "\nFailures:\n" + last_pipe_failures;
gp += "Artifacts:\n" + last_pipe_artifacts;
gp += "Track results:\n" + last_track_results;
gp += "VP: " + vp_summary + "\nVis:\n" + vp_vis_ev + "\nPerf:\n" + vp_perf_ev + "\n";
gp += "REQUIRED: read process file + " + qa_dir + "/pipeline_report.md if present. ";
gp += "verdict COMPLETE|INCOMPLETE|BLOCKED. If pipeline or visual_perf false → complete false.\n";

let gr = agent(gp, #{
    label: "gate",
    capability_mode: "read-write",
    output_schema: gate_schema,
});

let is_complete = false;
let verdict = "INCOMPLETE";
let headline = "";
let unmet = "";
let nexts = "";

if gr != () && gr.success && gr.output != () {
    let o = gr.output;
    if o.verdict != () { verdict = trimmed(o.verdict); }
    if o.headline != () { headline = o.headline; }
    if o.complete == true { is_complete = true; }
    unmet = join_lines(o.unmet_criteria, "- ");
    nexts = join_lines(o.next_steps, "- ");
} else {
    headline = "Gate agent failed";
}

if !pipeline_passed || !visual_perf_passed {
    is_complete = false;
    if verdict == "COMPLETE" { verdict = "INCOMPLETE"; }
}
if is_complete && verdict != "COMPLETE" {
    is_complete = false;
    verdict = "INCOMPLETE";
}
if !is_complete && verdict == "COMPLETE" { verdict = "INCOMPLETE"; }

if unmet == "" {
    unmet = if is_complete { "- (none)\n" } else { "- tracks, pipeline, and/or visual-perf not fully green\n" };
}
if nexts == "" {
    nexts = if is_complete {
        "- Review " + qa_dir + "/pipeline_report.md and commit when ready\n"
    } else {
        "- Open " + qa_dir + " artifacts and " + written_plan + "; re-run multi-track-ship\n"
    };
}
if headline == "" {
    headline = if is_complete {
        "All tracks + shared pipeline + local visual/perf complete."
    } else {
        "Not complete — see unmet criteria and " + qa_dir;
    };
}

let md = "";
md += "# multi-track-ship report\n\n";
md += "**Verdict:** " + verdict + "\n**Complete:** " + is_complete.to_string() + "\n";
md += "**Headline:** " + headline + "\n\n";
md += "## Goal\n" + plan_goal + "\n\n";
md += "## Process\n`" + written_plan + "`\n\n## QA dir\n`" + qa_dir + "`\n\n";
md += "## Tracks\n" + track_summaries + "\n";
md += "## Pipeline\n- passed: " + pipeline_passed.to_string() + "\n- summary: " + last_pipe_summary + "\n";
md += "### Commands\n" + last_pipe_commands + "\n### Failures\n" + last_pipe_failures + "\n";
md += "### Artifacts\n" + last_pipe_artifacts + "\n### Track results\n" + last_track_results + "\n";
md += "### Fix log\n" + (if fix_log == "" { "- (none)\n" } else { fix_log });
md += "\n## Local visual+perf\n- passed: " + visual_perf_passed.to_string() + "\n- " + vp_summary + "\n";
md += "### Visual\n" + vp_vis_ev + "\n### Perf\n" + vp_perf_ev + "\n";
md += "### Artifacts\n" + vp_art + "\n";
md += "## Unmet\n" + unmet + "\n## Next\n" + nexts + "\n";
md += "## Plan summary\n" + plan_scratch_path + "\n";

let report_path = write_scratch_file("multi-track-ship-report.md", md);
log("Gate: " + verdict + " complete=" + is_complete.to_string());

complete(#{
    path: report_path,
    plan_path: written_plan,
    plan_summary: plan_scratch_path,
    qa_dir: qa_dir,
    pipeline_mode: pipeline_mode,
    verdict: verdict,
    complete: is_complete,
    headline: headline,
    pipeline_passed: pipeline_passed,
    visual_perf_passed: visual_perf_passed,
    tracks: order_ids.len(),
    fix_rounds: fix_round,
    visual_perf_fix_rounds: vp_fix_round,
});
