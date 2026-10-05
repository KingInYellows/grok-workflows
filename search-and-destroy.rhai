let meta = #{
    name: "search-and-destroy",
    description: "AFK opportunistic improvement: scout bugs/polish/half-done work across any repo, skip or re-verify already-shipped work, pick high-ROI targets, todo-list them, implement, verify, fix",
    when_to_use: "When you want the agent to hunt improvements with no specific ticket — clean, fix, polish, complete half-done features; any language/stack",
    phases: [
        #{ title: "Scout", detail: "map repo, docs, todos, process files, incomplete work" },
        #{ title: "Candidates", detail: "surface bugs, polish, hygiene, half-done features" },
        #{ title: "PriorWork", detail: "check if already done; verify holds unless freshly complete" },
        #{ title: "Plan", detail: "write process file + durable todo list" },
        #{ title: "Approve", detail: "optional human gate (default auto for AFK)" },
        #{ title: "Destroy", detail: "implement selected todos; hard why + destroy_reasoning trail" },
        #{ title: "Verify", detail: "build/test/smoke + adversarial audit of destroy reasoning" },
        #{ title: "Fix", detail: "bounded fix loop" },
        #{ title: "Gate", detail: "fail-closed complete with evidence" },
    ],
};

// --- schemas -----------------------------------------------------------------

let scout_schema = #{
    "type": "object",
    "required": ["summary", "stack_hints", "doc_paths", "todo_paths", "process_paths", "notes"],
    "properties": #{
        "summary": #{ "type": "string" },
        "stack_hints": #{ "type": "array", "maxItems": 12, "items": #{ "type": "string" } },
        "doc_paths": #{ "type": "array", "maxItems": 30, "items": #{ "type": "string" } },
        "todo_paths": #{ "type": "array", "maxItems": 30, "items": #{ "type": "string" } },
        "process_paths": #{ "type": "array", "maxItems": 20, "items": #{ "type": "string" } },
        "notes": #{ "type": "string" },
    },
};

let candidates_schema = #{
    "type": "object",
    "required": ["candidates", "skipped_obvious"],
    "properties": #{
        "candidates": #{
            "type": "array",
            "maxItems": 20,
            "items": #{
                "type": "object",
                "required": ["id", "kind", "title", "why", "evidence_paths", "effort", "priority"],
                "properties": #{
                    "id": #{ "type": "string" },
                    "kind": #{ "type": "string" },
                    "title": #{ "type": "string" },
                    "why": #{ "type": "string" },
                    "evidence_paths": #{
                        "type": "array",
                        "maxItems": 12,
                        "items": #{ "type": "string" },
                    },
                    "effort": #{ "type": "string" },
                    "priority": #{ "type": "integer" },
                },
            },
        },
        "skipped_obvious": #{ "type": "array", "maxItems": 20, "items": #{ "type": "string" } },
    },
};

let prior_schema = #{
    "type": "object",
    "required": ["id", "disposition", "reason", "evidence", "reopen"],
    "properties": #{
        "id": #{ "type": "string" },
        "disposition": #{ "type": "string" },
        "reason": #{ "type": "string" },
        "evidence": #{ "type": "string" },
        "reopen": #{ "type": "boolean" },
    },
};

let plan_schema = #{
    "type": "object",
    "required": ["plan_path", "todo_path", "selected_ids", "summary", "notes"],
    "properties": #{
        "plan_path": #{ "type": "string" },
        "todo_path": #{ "type": "string" },
        "selected_ids": #{
            "type": "array",
            "maxItems": 12,
            "items": #{ "type": "string" },
        },
        "summary": #{ "type": "string" },
        "notes": #{ "type": "string" },
    },
};

let destroy_schema = #{
    "type": "object",
    "required": [
        "item_id",
        "status",
        "summary",
        "files_changed",
        "acceptance_met",
        "blocked_reason",
        "plan_updated",
        "why_destroyed",
        "destroy_reasoning",
        "change_claims",
        "verify_checks",
        "destroyed",
    ],
    "properties": #{
        "item_id": #{ "type": "string" },
        "status": #{ "type": "string" },
        "summary": #{ "type": "string" },
        "files_changed": #{
            "type": "array",
            "maxItems": 40,
            "items": #{ "type": "string" },
        },
        "acceptance_met": #{ "type": "boolean" },
        "blocked_reason": #{ "type": "string" },
        "plan_updated": #{ "type": "boolean" },
        // Hard "why" trail for Verify — not optional fluff.
        "why_destroyed": #{ "type": "string" },
        "destroy_reasoning": #{ "type": "string" },
        "change_claims": #{
            "type": "array",
            "maxItems": 20,
            "items": #{ "type": "string" },
        },
        "verify_checks": #{
            "type": "array",
            "maxItems": 20,
            "items": #{ "type": "string" },
        },
        "destroyed": #{ "type": "boolean" },
    },
};

let verify_schema = #{
    "type": "object",
    "required": [
        "passed",
        "commands_run",
        "summary",
        "failures",
        "evidence",
        "reasoning_valid",
        "reasoning_review",
        "invalid_reasoning",
    ],
    "properties": #{
        "passed": #{ "type": "boolean" },
        "commands_run": #{
            "type": "array",
            "maxItems": 30,
            "items": #{ "type": "string" },
        },
        "summary": #{ "type": "string" },
        "failures": #{
            "type": "array",
            "maxItems": 30,
            "items": #{ "type": "string" },
        },
        "evidence": #{ "type": "string" },
        // Destroy rationale audit (fail closed if reasoning is thin or false).
        "reasoning_valid": #{ "type": "boolean" },
        "reasoning_review": #{ "type": "string" },
        "invalid_reasoning": #{
            "type": "array",
            "maxItems": 30,
            "items": #{ "type": "string" },
        },
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

// Accept JSON numbers or numeric strings ("3", "10") so CLI/JSON args behave the same.
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

// --- args (all optional — AFK default) ---------------------------------------

let focus_arg = if args == () { () } else { args.focus };
if focus_arg == () && args != () { focus_arg = args.goal; }
if focus_arg == () && args != () { focus_arg = args.hint; }

let plan_path_arg = if args == () { () } else { args.plan_path };
let todo_path_arg = if args == () { () } else { args.todo_path };
// AFK: auto-approve by default (user can set false)
let auto_approve = bool_arg(if args == () { () } else { args.auto_approve_plan }, true);
let allow_features = bool_arg(if args == () { () } else { args.allow_features }, true);
let allow_hygiene = bool_arg(if args == () { () } else { args.allow_hygiene }, true);

let max_items = int_arg(if args == () { () } else { args.max_items }, 4, 1, 8);
let max_fix = int_arg(if args == () { () } else { args.max_fix_rounds }, 2, 1, 4);

let focus_text = if focus_arg == () || trimmed(focus_arg.to_string()) == "" {
    "No specific aim. Improve this application: fix bugs, reduce friction, polish visuals/UX if relevant, complete half-done work, light hygiene. Prefer high ROI and small atomic wins. Hit whatever is most valuable first."
} else {
    trimmed(focus_arg.to_string())
};

let plan_path = if plan_path_arg == () || trimmed(plan_path_arg.to_string()) == "" {
    "SEARCH_AND_DESTROY_PROCESS.md"
} else {
    trimmed(plan_path_arg.to_string())
};

let todo_path = if todo_path_arg == () || trimmed(todo_path_arg.to_string()) == "" {
    "SEARCH_AND_DESTROY_TODO.md"
} else {
    trimmed(todo_path_arg.to_string())
};

// --- Phase 1: Scout ----------------------------------------------------------

phase("Scout");
log("Scouting repository (universal search-and-destroy)");

let scout_prompt = "";
scout_prompt += "You are SCOUT for universal search-and-destroy (AFK improvement run).\n";
scout_prompt += "Any language/stack. Working directory = current repo root.\n";
scout_prompt += "Soft focus (not exclusive): " + focus_text + "\n";
scout_prompt += "REQUIRED — use tools (list_dir, read_file, grep, git status/log as needed):\n";
scout_prompt += "1) Detect stack hints (package.json, Cargo.toml, CMakeLists, go.mod, pyproject, .sln, etc.).\n";
scout_prompt += "2) Find rich docs: README*, docs/**, CODEBASE*, AGENTS.md, CLAUDE.md, .github/instructions, design docs.\n";
scout_prompt += "3) Find todo/process files: TODO*.md, *HANDOFF*, WORKPLANS/**, IMPLEMENTATION_PROCESS*.md, *TODO*.md, issues notes.\n";
scout_prompt += "4) Note incomplete work signals: unchecked boxes, Status: pending/blocked, WIP, FIXME, XXX, failing tests if obvious.\n";
scout_prompt += "5) Do NOT invent files. Empty lists only after searching.\n";
scout_prompt += "Return stack_hints, doc_paths, todo_paths, process_paths, summary, notes.\n";

let scout_r = agent(scout_prompt, #{
    label: "scout",
    capability_mode: "execute",
    output_schema: scout_schema,
});

if scout_r == () || !scout_r.success || scout_r.output == () {
    pause("infra", "Scout agent failed. Resume to retry.");
}

let scout = scout_r.output;
let scout_summary = if scout.summary != () { scout.summary } else { "(no summary)" };
let stack_blob = join_lines(scout.stack_hints, "- ");
let docs_blob = join_lines(scout.doc_paths, "- ");
let todos_blob = join_lines(scout.todo_paths, "- ");
let process_blob = join_lines(scout.process_paths, "- ");
let scout_notes = if scout.notes != () { scout.notes } else { "" };
if stack_blob == "" { stack_blob = "- (unknown stack)\n"; }
if docs_blob == "" { docs_blob = "- (none found)\n"; }
if todos_blob == "" { todos_blob = "- (none found)\n"; }
if process_blob == "" { process_blob = "- (none found)\n"; }

log("Scout: " + scout_summary);

// --- Phase 2: Candidates -----------------------------------------------------

phase("Candidates");
log("Mining candidates (bugs / polish / half-done / hygiene)");

let cand_prompt = "";
cand_prompt += "You are CANDIDATE MINER for search-and-destroy.\n";
cand_prompt += "Soft focus: " + focus_text + "\n";
cand_prompt += "Scout summary: " + scout_summary + "\n";
cand_prompt += "Stack:\n" + stack_blob;
cand_prompt += "Docs:\n" + docs_blob;
cand_prompt += "Todos:\n" + todos_blob;
cand_prompt += "Process files:\n" + process_blob;
cand_prompt += "Scout notes: " + scout_notes + "\n";
cand_prompt += "allow_features=" + allow_features.to_string() + " allow_hygiene=" + allow_hygiene.to_string() + "\n";
cand_prompt += "REQUIRED:\n";
cand_prompt += "1) Read the highest-value docs/todos/process files with tools. Grep for TODO/FIXME/XXX/HACK/BUG, failing tests, incomplete Status.\n";
cand_prompt += "2) Propose up to 20 concrete candidates. kind MUST be one of:\n";
cand_prompt += "   bug | polish | hygiene | incomplete_feature | complete_existing | docs | test | performance\n";
cand_prompt += "3) If allow_features=false, do not propose large greenfield features (only bug/polish/hygiene/complete_existing/test).\n";
cand_prompt += "4) If allow_hygiene=false, skip pure cleanup.\n";
cand_prompt += "5) Each candidate needs: id (short slug), title, why, evidence_paths (files you actually opened or grepped), effort (S|M|L), priority (1=highest).\n";
cand_prompt += "6) Prefer S/M effort atomic wins that ship this run. Large L epics only if clearly half-done and close to complete.\n";
cand_prompt += "7) skipped_obvious: low-value noise you intentionally ignored.\n";
cand_prompt += "Empty candidates only if the tree is truly pristine after real search.\n";

let cand_r = agent(cand_prompt, #{
    label: "candidates",
    capability_mode: "execute",
    output_schema: candidates_schema,
});

if cand_r == () || !cand_r.success || cand_r.output == () {
    pause("infra", "Candidate miner failed. Resume to retry.");
}

let candidates = [];
if cand_r.output.candidates != () {
    for c in cand_r.output.candidates {
        if c.id != () && trimmed(c.id) != "" {
            // Hard-filter kinds against flags. allow_features is prompt-only (cand_prompt
            // already steers the miner away from large greenfield when false); do not
            // pretend to filter incomplete_feature/complete_existing here — that branch
            // never set keep=false and was a no-op. Hygiene still drops when disallowed.
            let k = if c.kind != () { trimmed(c.kind) } else { "polish" };
            let keep = true;
            if !allow_hygiene && k == "hygiene" { keep = false; }
            if keep { candidates.push(c); }
        }
    }
}

let skipped_blob = join_lines(cand_r.output.skipped_obvious, "- ");
if skipped_blob == "" { skipped_blob = "- (none)\n"; }

// sort by priority ascending
let sorted_cands = [];
while candidates.len() > 0 {
    let best_i = 0;
    let best_p = 9999;
    let ti = 0;
    for c in candidates {
        let p = 50;
        if c.priority != () { p = c.priority; }
        if p < best_p { best_p = p; best_i = ti; }
        ti += 1;
    }
    let rest = [];
    let chosen = ();
    let nj = 0;
    for c in candidates {
        if nj == best_i { chosen = c; } else { rest.push(c); }
        nj += 1;
    }
    if chosen != () { sorted_cands.push(chosen); }
    candidates = rest;
}
candidates = sorted_cands;

let cand_blob = "";
for c in candidates {
    let id = if c.id != () { c.id } else { "?" };
    let kind = if c.kind != () { c.kind } else { "?" };
    let title = if c.title != () { c.title } else { "" };
    let why = if c.why != () { c.why } else { "" };
    let eff = if c.effort != () { c.effort } else { "?" };
    let pr = if c.priority != () { c.priority.to_string() } else { "?" };
    let ev = join_lines(c.evidence_paths, "    ");
    cand_blob += "- [" + pr + "] " + id + " (" + kind + "/" + eff + "): " + title + "\n  why: " + why + "\n  evidence:\n" + ev;
}

if candidates.len() == 0 {
    let md0 = "# search-and-destroy report\n\n**Verdict:** CLEAN\n\nNo actionable candidates after scout+mine.\n\nScout: " + scout_summary + "\n";
    let p0 = write_scratch_file("search-and-destroy-report.md", md0);
    complete(#{
        path: p0,
        verdict: "CLEAN",
        complete: true,
        headline: "No actionable candidates",
        selected: 0,
    });
}

log(candidates.len().to_string() + " candidate(s) before prior-work filter");

// Cap prior-work fan-out
const MAX_PRIOR = 12;
let to_check = [];
let dropped_prior = 0;
let ci = 0;
for c in candidates {
    if ci < MAX_PRIOR { to_check.push(c); } else { dropped_prior += 1; }
    ci += 1;
}
if dropped_prior > 0 {
    log("Prior-work check capped at " + MAX_PRIOR.to_string() + "; dropped " + dropped_prior.to_string());
}

// --- Phase 3: Prior work check (parallel) ------------------------------------

phase("PriorWork");
log("Checking whether candidates are already done / still hold");

let pjobs = [];
for c in to_check {
    let id = if c.id != () { c.id } else { "item" };
    let title = if c.title != () { c.title } else { "" };
    let why = if c.why != () { c.why } else { "" };
    let kind = if c.kind != () { c.kind } else { "" };
    let ev = join_lines(c.evidence_paths, "- ");
    let pp = "";
    pp += "You are PRIOR-WORK CHECKER for search-and-destroy. Fail closed toward SKIP if already solidly done.\n";
    pp += "Candidate id: " + id + "\nkind: " + kind + "\ntitle: " + title + "\nwhy: " + why + "\n";
    pp += "Evidence paths claimed:\n" + ev;
    pp += "Process/todo files from scout:\n" + process_blob + todos_blob;
    pp += "REQUIRED method:\n";
    pp += "1) Search process files, changelogs, git log/diff, TODO Status lines for this work.\n";
    pp += "2) disposition MUST be exactly one of:\n";
    pp += "   - proceed — not done, or incomplete, or broken\n";
    pp += "   - verify_only — marked done/complete; must re-check it still holds (tests/code inspect)\n";
    pp += "   - skip_fresh — completed VERY recently (same day / process Status done with solid acceptance) and no reason to re-touch\n";
    pp += "   - skip_done — already done and re-verification shows it still holds\n";
    pp += "3) If Status is done/complete but code/tests contradict, set disposition=proceed and reopen=true.\n";
    pp += "4) If Status is done and looks solid without re-running heavy work, skip_fresh or skip_done.\n";
    pp += "5) evidence: what you read (non-empty). reason: short.\n";
    pp += "   skip_fresh/skip_done REQUIRE non-empty evidence of what you inspected; empty evidence is treated as proceed.\n";
    pp += "6) reopen=true only when previously claimed complete but does not hold.\n";
    pp += "Use tools. Do not invent git history.\n";
    pjobs.push(#{
        prompt: pp,
        label: "prior:" + id,
        capability_mode: "execute",
        output_schema: prior_schema,
    });
}

let prior_results = parallel(pjobs);

let proceed_ids = [];
let verify_only = [];
let prior_log = "";
let pi = 0;
for pr in prior_results {
    let base = to_check[pi];
    let bid = if base.id != () { base.id } else { "?" };
    if pr == () || !pr.success || pr.output == () {
        // fail open toward proceed if prior check fails? Prefer proceed with caution
        proceed_ids.push(bid);
        prior_log += "- " + bid + ": prior-check failed → treat as proceed\n";
    } else {
        let o = pr.output;
        let disp = if o.disposition != () { trimmed(o.disposition) } else { "proceed" };
        let reason = if o.reason != () { o.reason } else { "" };
        let evd = if o.evidence != () { o.evidence } else { "" };
        let reo = (o.reopen == true);
        prior_log += "- " + bid + ": " + disp + " reopen=" + reo.to_string() + " — " + reason + "\n  evidence: " + evd + "\n";
        if disp == "proceed" || reo {
            proceed_ids.push(bid);
        } else if disp == "verify_only" {
            verify_only.push(bid);
            // still may become work if verify fails later — keep as light todo
            proceed_ids.push(bid);
        } else if disp == "skip_fresh" || disp == "skip_done" {
            // Only skip with non-empty evidence; empty-evidence skip is tool-less skip-all risk
            if trimmed(evd) != "" {
                // skip — solid evidence of already done / freshly complete
            } else {
                proceed_ids.push(bid);
                prior_log += "  empty-evidence skip rejected → treat as proceed\n";
            }
        } else {
            // unknown disposition → proceed
            proceed_ids.push(bid);
        }
    }
    pi += 1;
}

// Dedup proceed_ids and map back to candidates, take max_items
let selected = [];
for c in candidates {
    if selected.len() >= max_items { break; }
    let id = if c.id != () { trimmed(c.id) } else { "" };
    let wanted = false;
    for pid in proceed_ids {
        if trimmed(pid) == id { wanted = true; }
    }
    if wanted { selected.push(c); }
}

if selected.len() == 0 {
    let md1 = "";
    md1 += "# search-and-destroy report\n\n**Verdict:** NOTHING_TO_DO\n\n";
    md1 += "All candidates were skip_fresh/skip_done after prior-work checks.\n\n";
    md1 += "## Prior-work log\n" + prior_log + "\n";
    md1 += "## Candidates considered\n" + cand_blob + "\n";
    let p1 = write_scratch_file("search-and-destroy-report.md", md1);
    complete(#{
        path: p1,
        verdict: "NOTHING_TO_DO",
        complete: true,
        headline: "Everything candidate was already done or freshly complete",
        selected: 0,
    });
}

let selected_blob = "";
for c in selected {
    let id = if c.id != () { c.id } else { "?" };
    let title = if c.title != () { c.title } else { "" };
    let kind = if c.kind != () { c.kind } else { "?" };
    selected_blob += "- " + id + " (" + kind + "): " + title + "\n";
}

log("Selected " + selected.len().to_string() + " item(s) to destroy");

// --- Phase 4: Plan + todos ---------------------------------------------------

phase("Plan");
log("Writing process + todo files");

let plan_prompt = "";
plan_prompt += "You are PLANNER for search-and-destroy. Write durable PROCESS + TODO files the user can open.\n";
plan_prompt += "Process path: " + plan_path + "\nTodo path: " + todo_path + "\n";
plan_prompt += "Soft focus: " + focus_text + "\n";
plan_prompt += "Scout: " + scout_summary + "\n";
plan_prompt += "Selected work:\n" + selected_blob;
plan_prompt += "Candidate details:\n" + cand_blob;
plan_prompt += "Prior-work log:\n" + prior_log;
plan_prompt += "REQUIRED:\n";
plan_prompt += "1) WRITE " + plan_path + " with markdown:\n";
plan_prompt += "   # Search and Destroy Process\n## Goal\n## Stack\n## Prior-work policy applied\n";
plan_prompt += "   ## Selected items (ordered)\n### Item <id>\n- Status: pending\n- Kind\n- Actions\n- Acceptance\n- Verify\n";
plan_prompt += "   - Why destroyed: (filled by Destroy)\n- Destroy reasoning: (filled by Destroy — full chain)\n- Change claims: (filled by Destroy)\n- Verify checks: (filled by Destroy — how Verify must re-check the why)\n";
plan_prompt += "   ## Done criteria\n## Destroy reasoning log\n## Verification log\n";
plan_prompt += "2) WRITE " + todo_path + " as a checkbox todo list the user can scan:\n";
plan_prompt += "   # Search and Destroy Todos\n- [ ] **id**: title — acceptance one-liner\n";
plan_prompt += "3) selected_ids must match the items you wrote, same order, max " + max_items.to_string() + ".\n";
plan_prompt += "4) Keep items atomic and buildable. Respect repo conventions if docs specify changelogs/agent tags.\n";

let plan_r = agent(plan_prompt, #{
    label: "plan",
    capability_mode: "read-write",
    output_schema: plan_schema,
});

if plan_r == () || !plan_r.success || plan_r.output == () {
    pause("infra", "Plan agent failed. Resume to retry.");
}

let written_plan = plan_path;
let written_todo = todo_path;
if plan_r.output.plan_path != () && trimmed(plan_r.output.plan_path) != "" {
    written_plan = trimmed(plan_r.output.plan_path);
}
if plan_r.output.todo_path != () && trimmed(plan_r.output.todo_path) != "" {
    written_todo = trimmed(plan_r.output.todo_path);
}
let plan_summary = if plan_r.output.summary != () { plan_r.output.summary } else { focus_text };

let order_ids = [];
if plan_r.output.selected_ids != () {
    for id in plan_r.output.selected_ids {
        let t = trimmed(id.to_string());
        if t != "" { order_ids.push(t); }
    }
}
if order_ids.len() == 0 {
    for c in selected {
        if c.id != () { order_ids.push(trimmed(c.id)); }
    }
}

// Fail-closed: only Destroy ids present in selected candidates.
// Invented/typo plan selected_ids would otherwise enter Destroy with empty meta
// (title=iid, empty why/evidence). Preserve planner relative order among survivors.
// Duplicates after intersect still possible — backlog: sad-order-ids-max-dedupe
let filtered_order = [];
for id in order_ids {
    let in_selected = false;
    for c in selected {
        if c.id != () && trimmed(c.id) == id { in_selected = true; }
    }
    if in_selected {
        filtered_order.push(id);
    } else {
        log("order_ids: dropped unknown id " + id);
    }
}
if filtered_order.len() == 0 {
    // Filter emptied (all invented/typo) — fall back to selected array order
    order_ids = [];
    for c in selected {
        if c.id != () { order_ids.push(trimmed(c.id)); }
    }
} else {
    order_ids = filtered_order;
}

let order_blob = "";
for id in order_ids { order_blob += "- " + id + "\n"; }

let plan_scratch = "";
plan_scratch += "# search-and-destroy plan summary\n\n";
plan_scratch += "**Process:** " + written_plan + "\n**Todos:** " + written_todo + "\n\n";
plan_scratch += plan_summary + "\n\n## Order\n" + order_blob + "\n## Prior-work\n" + prior_log;
let plan_scratch_path = write_scratch_file("search-and-destroy-plan.md", plan_scratch);

// --- Phase 5: Approve (default auto for AFK) ---------------------------------

phase("Approve");
if !auto_approve {
    await_user("user", "search-and-destroy plan ready.\nProcess: " + written_plan + "\nTodos: " + written_todo + "\nItems:\n" + order_blob + "Resume to implement.");
} else {
    log("auto_approve_plan=true (AFK default) — implementing");
}

// --- Phase 6: Destroy (sequential items) -------------------------------------
// Every destroy must leave a hard "why" trail. Verify adversarially re-checks it.

phase("Destroy");
log("Destroying " + order_ids.len().to_string() + " item(s) (with hard why/reasoning trail)");

let destroy_log = "";
let destroy_reasoning_log = "";
let files_all = "";
let items_ok = 0;
let destroy_reason_fail = 0;
let di = 0;
for iid in order_ids {
    di += 1;
    // find candidate meta
    let meta_c = ();
    for c in selected {
        if c.id != () && trimmed(c.id) == iid { meta_c = c; }
    }
    let title = if meta_c != () && meta_c.title != () { meta_c.title } else { iid };
    let why = if meta_c != () && meta_c.why != () { meta_c.why } else { "" };
    let kind = if meta_c != () && meta_c.kind != () { meta_c.kind } else { "" };
    let ev = if meta_c != () { join_lines(meta_c.evidence_paths, "- ") } else { "" };

    log("Item " + di.to_string() + "/" + order_ids.len().to_string() + ": " + iid);

    // Per-item prior disposition from PriorWork (verify_only still proceeds into Destroy)
    let prior_disp = "proceed";
    for vid in verify_only {
        if trimmed(vid) == iid { prior_disp = "verify_only"; }
    }

    let ip = "";
    ip += "You are DESTROYER for search-and-destroy. Implement ONE selected item only.\n";
    ip += "Item id: " + iid + "\nTitle: " + title + "\nKind: " + kind + "\nCandidate why: " + why + "\n";
    ip += "prior_disposition=" + prior_disp + "\n";
    ip += "Evidence paths:\n" + ev;
    ip += "Process file: " + written_plan + "\nTodo file: " + written_todo + "\n";
    ip += "Soft focus: " + focus_text + "\n";
    ip += "Stack:\n" + stack_blob;
    ip += "REQUIRED:\n";
    ip += "1) Re-read process item + relevant docs. Confirm still not freshly completed by someone else.\n";
    if prior_disp == "verify_only" {
        ip += "2) prior_disposition=verify_only for THIS item: first re-verify that the claimed completion still holds (tests/code inspect); only change code if it does NOT hold. If it holds: destroyed=false, status done/partial, change_claims must say 'no code change; verify-only held because …'.\n";
    } else {
        ip += "2) prior_disposition=proceed for THIS item: implement the fix (not a re-verify-first of already-done work).\n";
    }
    ip += "3) Implement the smallest correct fix/improvement. Match project style and docs/changelog rules if present.\n";
    ip += "4) HARD REASONING TRAIL (this is mandatory — Verify will attack it):\n";
    ip += "   - destroyed=true only if you actually changed the tree (or confirm verify-only held with no code change needed).\n";
    ip += "   - why_destroyed: one dense paragraph — WHY this item deserved destruction NOW (problem, risk if left, why this fix over no-op).\n";
    ip += "   - destroy_reasoning: full chain of thought that Verify can re-run: symptoms → root cause → chosen edit → why alternatives were worse → how acceptance is met.\n";
    ip += "   - change_claims: concrete bullets of what changed (file + behavior), or explicit 'no code change; verify-only held because …'.\n";
    ip += "   - verify_checks: bullets Verify MUST use to falsify or confirm your reasoning (grep targets, read lines, tests, invariants).\n";
    ip += "   Empty why_destroyed/destroy_reasoning on status done|partial is INVALID — Prefer status=blocked over fake done.\n";
    ip += "5) Update process Status (done|blocked|partial), fill Why destroyed / Destroy reasoning / Change claims / Verify checks fields, and check off " + written_todo + " when done.\n";
    ip += "6) Append a short entry under ## Destroy reasoning log in the process file.\n";
    ip += "7) Build/test as appropriate for this stack when you touch code.\n";
    ip += "8) Do not expand into other selected items.\n";
    ip += "status: done|blocked|partial. acceptance_met only if acceptance truly met.\n";

    let ir = agent(ip, #{
        label: "destroy:" + iid,
        capability_mode: "all",
        output_schema: destroy_schema,
    });

    let st = "failed";
    let sum = "agent failed";
    let met = false;
    let destroyed_flag = false;
    let why_d = "";
    let reason_d = "";
    let claims = "";
    let vchecks = "";
    if ir != () && ir.success && ir.output != () {
        let o = ir.output;
        if o.status != () { st = trimmed(o.status); }
        if o.summary != () { sum = o.summary; }
        if o.acceptance_met == true { met = true; }
        if o.destroyed == true { destroyed_flag = true; }
        if o.why_destroyed != () { why_d = trimmed(o.why_destroyed); }
        if o.destroy_reasoning != () { reason_d = trimmed(o.destroy_reasoning); }
        claims = join_lines(o.change_claims, "  - ");
        vchecks = join_lines(o.verify_checks, "  - ");
        let more = join_lines(o.files_changed, "- ");
        if more != "" { files_all += more; }
        if o.blocked_reason != () && trimmed(o.blocked_reason) != "" {
            sum += " | " + o.blocked_reason;
        }
    }

    // Fail-closed on thin reasoning for work claimed done.
    let reason_ok = true;
    if st == "done" || st == "partial" || met {
        if why_d == "" || reason_d == "" {
            reason_ok = false;
            destroy_reason_fail += 1;
            log("Destroy " + iid + ": missing why_destroyed/destroy_reasoning — not counting as ok");
        } else if claims == "" && destroyed_flag {
            // Destroy claimed but no concrete change_claims — Verify will still audit, but flag thin trail.
            log("Destroy " + iid + ": destroyed=true with empty change_claims (verify will audit hard)");
        }
    }
    if !reason_ok {
        if st == "done" { st = "partial"; }
        met = false;
    }

    destroy_log += "- " + iid + " [" + st + "] destroyed=" + destroyed_flag.to_string()
        + " met=" + met.to_string() + " reason_ok=" + reason_ok.to_string() + ": " + sum + "\n";
    destroy_reasoning_log += "### " + iid + " [" + st + "]\n";
    destroy_reasoning_log += "- destroyed: " + destroyed_flag.to_string() + "\n";
    destroy_reasoning_log += "- why_destroyed: " + (if why_d == "" { "(MISSING)" } else { why_d }) + "\n";
    destroy_reasoning_log += "- destroy_reasoning: " + (if reason_d == "" { "(MISSING)" } else { reason_d }) + "\n";
    destroy_reasoning_log += "- change_claims:\n" + (if claims == "" { "  - (none)\n" } else { claims });
    destroy_reasoning_log += "- verify_checks:\n" + (if vchecks == "" { "  - (none)\n" } else { vchecks });
    destroy_reasoning_log += "\n";

    if (met || st == "done") && reason_ok { items_ok += 1; }
}

log("Destroy phase: " + items_ok.to_string() + "/" + order_ids.len().to_string()
    + " ok-ish; reasoning gaps=" + destroy_reason_fail.to_string());

// --- Phase 7+8: Verify / Fix ------------------------------------------------

let tests_passed = false;
let last_summary = "";
let last_failures = "";
let last_evidence = "";
let last_commands = "";
let last_reasoning_review = "";
let last_invalid_reasoning = "";
let last_reasoning_valid = false;
let fix_round = 0;
let fix_log = "";
let attempt = 0;
let max_attempts = max_fix + 1;

while attempt < max_attempts {
    attempt += 1;
    phase("Verify");
    log("Verify attempt " + attempt.to_string() + "/" + max_attempts.to_string()
        + " (includes destroy-reasoning audit)");

    let vp = "";
    vp += "You are VERIFIER for search-and-destroy. Fail closed.\n";
    vp += "You must audit BOTH (A) build/behavior and (B) Destroy reasoning validity.\n";
    vp += "Process: " + written_plan + "\nTodos: " + written_todo + "\n";
    vp += "Stack:\n" + stack_blob;
    vp += "Items destroyed (summary):\n" + destroy_log;
    // Trail is Destroy snapshot + post-Fix refresh blocks — not sole authority when process fields were repaired.
    vp += "DESTROY REASONING TRAIL (in-memory snapshot from Destroy + any fix-round refresh blocks):\n" + destroy_reasoning_log;
    vp += "SOURCE OF TRUTH: When process file per-item Why destroyed / Destroy reasoning / Change claims / Verify checks OR ## Destroy reasoning log are present and non-empty, they OVERRIDE this in-memory trail for those items (including superseding (MISSING) or weak text if Fix repaired the process file). Attack the freshest filled reasoning — do not fail solely because the pre-Fix snapshot still says (MISSING) while process fields are filled.\n";
    vp += "Files touched:\n" + files_all;
    vp += "REQUIRED:\n";
    vp += "1) Read process/todo statuses vs tree. Confirm Why destroyed / Destroy reasoning fields were written for each done item. Prefer process-file fields (and ## Destroy reasoning log) over a stale in-memory trail when both exist and process fields are filled.\n";
    vp += "2) REASONING AUDIT (push hard):\n";
    vp += "   For each item with status done|partial:\n";
    vp += "   a) Is why_destroyed non-empty and specific (process file first, then trail; not generic 'fixed bug')?\n";
    vp += "   b) Does destroy_reasoning chain (symptom → cause → edit → acceptance) match the actual files/diff?\n";
    vp += "   c) Are change_claims true (read the files; no phantom edits)?\n";
    vp += "   d) Run every listed verify_checks that is feasible; note results.\n";
    vp += "   e) If reasoning is circular, post-hoc, or contradicted by the tree → reasoning_valid=false and list in invalid_reasoning.\n";
    vp += "   f) Do NOT mark reasoning_valid=false solely because the in-memory trail still shows (MISSING) for an item whose process fields / ## Destroy reasoning log were filled after Fix.\n";
    vp += "3) Discover and run the best build/test/lint for THIS stack (npm test, cargo test, ctest, pytest, cmake --build, etc.).\n";
    vp += "   If the tree is pure orchestration/scripts (e.g. only .rhai workflows) with no package harness: do NOT invent npm/cargo. Verify by re-reading changed files for dialect/fail-closed issues, honest process/todo status, and any host smoke (validate_only) available — still require non-empty evidence.\n";
    vp += "4) passed=true ONLY if: build/inspect evidence is non-empty AND reasoning_valid=true AND no material invalid_reasoning for done items.\n";
    vp += "5) reasoning_review: short paragraph summarizing the audit.\n";
    vp += "6) Append Verification log + reasoning audit notes to the process file.\n";

    let vr = agent(vp, #{
        label: "verify:" + attempt.to_string(),
        capability_mode: "all",
        output_schema: verify_schema,
    });

    let ok = false;
    last_reasoning_valid = false;
    if vr != () && vr.success && vr.output != () {
        let o = vr.output;
        if o.summary != () { last_summary = o.summary; }
        if o.evidence != () { last_evidence = o.evidence; }
        if o.reasoning_review != () { last_reasoning_review = o.reasoning_review; }
        if o.reasoning_valid == true { last_reasoning_valid = true; }
        last_failures = join_lines(o.failures, "- ");
        last_invalid_reasoning = join_lines(o.invalid_reasoning, "- ");
        last_commands = join_lines(o.commands_run, "- ");
        // Fail closed before placeholder "- (none)": material invalid_reasoning
        // must never co-exist with ok=true / reasoning_valid=true (prompt rule #4).
        let material_inv = trimmed(last_invalid_reasoning) != "";
        if material_inv {
            last_reasoning_valid = false;
        }
        if o.passed == true
            && trimmed(last_evidence) != ""
            && last_reasoning_valid
        {
            ok = true;
        } else if o.passed == true {
            log("Verify claimed pass without evidence and/or valid destroy reasoning — fail closed");
            if material_inv {
                last_failures += "- non-empty invalid_reasoning — fail closed (script)\n";
                log("Verify claimed pass with non-empty invalid_reasoning — fail closed");
            }
            if !last_reasoning_valid {
                last_failures += "- destroy reasoning audit failed (reasoning_valid=false)\n";
            }
            if trimmed(last_evidence) == "" {
                last_failures += "- empty evidence\n";
            }
        }
    } else {
        last_summary = "verifier failed";
        last_failures = "- verifier infrastructure failure\n";
        last_evidence = "";
        last_reasoning_review = "";
        last_invalid_reasoning = "- verifier failed\n";
        last_reasoning_valid = false;
    }
    if last_failures == "" { last_failures = "- (none)\n"; }
    if last_invalid_reasoning == "" { last_invalid_reasoning = "- (none)\n"; }

    if ok {
        tests_passed = true;
        log("Verify PASS: " + last_summary);
        break;
    }
    log("Verify FAIL: " + last_summary + " reasoning_valid=" + last_reasoning_valid.to_string());
    if attempt >= max_attempts { break; }

    phase("Fix");
    fix_round += 1;
    let fp = "";
    fp += "You are FIXER for search-and-destroy after verify failure.\n";
    fp += "Process: " + written_plan + "\n";
    fp += "Failures:\n" + last_failures;
    fp += "Invalid destroy reasoning:\n" + last_invalid_reasoning;
    fp += "Reasoning review:\n" + last_reasoning_review + "\n";
    fp += "Evidence:\n" + last_evidence + "\n";
    fp += "Destroy log:\n" + destroy_log;
    fp += "Destroy reasoning trail (may still show pre-Fix MISSING/weak text; process-file fields you repair supersede it; host appends a fix-round refresh after this agent):\n" + destroy_reasoning_log;
    fp += "Fix root causes for selected items OR repair/correct the destroy reasoning if the code is fine but the why was weak/false.\n";
    fp += "Update process Why destroyed / Destroy reasoning / Change claims / Verify checks so a re-verify can pass.\n";
    fp += "Do not expand scope.\n";

    let fr = agent(fp, #{
        label: "fix:" + fix_round.to_string(),
        capability_mode: "all",
        output_schema: fix_schema,
    });
    if fr != () && fr.success && fr.output != () {
        let fs = if fr.output.summary != () { fr.output.summary } else { "" };
        fix_log += "- " + fs + "\n";
        let more = join_lines(fr.output.files_changed, "- ");
        if more != "" { files_all += more; }
        // A: refresh in-memory trail so re-Verify does not solely attack stale pre-Fix MISSING/weak text.
        destroy_reasoning_log += "### fix-round-" + fix_round.to_string() + " refresh\n";
        destroy_reasoning_log += "- summary: " + (if fs == "" { "(none)" } else { fs }) + "\n";
        destroy_reasoning_log += "- files_changed:\n" + (if more == "" { "  - (none)\n" } else { more });
        let fixed_items = join_lines(fr.output.fixed, "- ");
        if fixed_items != "" {
            destroy_reasoning_log += "- fixed:\n" + fixed_items;
        }
        let still = if fr.output.still_failing != () { trimmed(fr.output.still_failing.to_string()) } else { "" };
        if still != "" {
            destroy_reasoning_log += "- still_failing: " + still + "\n";
        }
        destroy_reasoning_log += "- note: process file Why destroyed / Destroy reasoning / Change claims / Verify checks and ## Destroy reasoning log supersede any earlier (MISSING) or weak trail text for repaired items. Re-Verify must attack on-disk process fields when they differ from the pre-Fix snapshot above.\n\n";
        log("Fix round " + fix_round.to_string() + ": appended destroy_reasoning_log refresh block");
    } else {
        fix_log += "- fix agent failed\n";
    }
}

// --- Phase 9: Gate -----------------------------------------------------------

phase("Gate");
log("Gate tests_passed=" + tests_passed.to_string());

let gp = "";
gp += "COMPLETION GATE for search-and-destroy. Fail closed.\n";
gp += "complete=true only if selected todos are honestly done (or verify-only held) AND verification passed with evidence.\n";
gp += "Process: " + written_plan + "\nTodos: " + written_todo + "\n";
gp += "Destroy log:\n" + destroy_log;
gp += "Destroy reasoning trail (includes post-Fix refresh blocks if any; process ## Destroy reasoning log / per-item Why destroyed fields override when filled):\n" + destroy_reasoning_log;
gp += "tests_passed=" + tests_passed.to_string() + "\n";
gp += "reasoning_valid=" + last_reasoning_valid.to_string() + "\n";
gp += "Verify: " + last_summary + "\nFailures:\n" + last_failures;
gp += "Invalid reasoning:\n" + last_invalid_reasoning;
gp += "Reasoning review:\n" + last_reasoning_review + "\n";
gp += "Evidence:\n" + last_evidence + "\n";
gp += "Prior-work:\n" + prior_log;
gp += "REQUIRED: read process+todo files. Align verdict with complete:\n";
gp += "  - COMPLETE only when destroy work was done (or verify-only held), tests_passed, reasoning_valid, and complete=true\n";
gp += "  - PARTIAL when some items improved but verify/reasoning failed or work remains (complete=false)\n";
gp += "  - INCOMPLETE when little or no honest progress (complete=false)\n";
gp += "Do NOT use CLEAN on this post-destroy gate — CLEAN is reserved for the early empty-candidate exit (no destroy run).\n";
gp += "complete=true only with verdict COMPLETE and tests_passed and reasoning_valid; never with CLEAN/PARTIAL/INCOMPLETE.\n";
gp += "If tests_passed is false OR reasoning_valid is false, complete must be false.\n";

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

// Hard overrides: complete only with COMPLETE + tests_passed + reasoning_valid.
// CLEAN is reserved for early empty-candidate exit; never complete after destroy.
if !tests_passed || !last_reasoning_valid {
    is_complete = false;
    if verdict == "COMPLETE" { verdict = "PARTIAL"; }
}
if is_complete && verdict != "COMPLETE" {
    is_complete = false;
    if verdict == "CLEAN" { verdict = "PARTIAL"; }
}
if !is_complete && verdict == "COMPLETE" { verdict = "INCOMPLETE"; }

if unmet == "" {
    unmet = if is_complete { "- (none)\n" } else { "- verify or todos incomplete\n" };
}
if nexts == "" {
    nexts = if is_complete {
        "- Review " + written_todo + " and commit when ready\n"
    } else {
        "- Re-run /search-and-destroy or finish " + written_plan + "\n"
    };
}
if headline == "" {
    headline = if is_complete { "Search-and-destroy complete." } else { "Incomplete — see todos." };
}

let md = "";
md += "# search-and-destroy report\n\n";
md += "**Verdict:** " + verdict + "\n**Complete:** " + is_complete.to_string() + "\n";
md += "**Headline:** " + headline + "\n\n";
md += "## Focus\n" + focus_text + "\n\n";
md += "## Scout\n" + scout_summary + "\n\n";
md += "## Prior-work filter\n" + prior_log + "\n";
md += "## Selected\n" + selected_blob + "\n";
md += "## Destroy log\n" + destroy_log + "\n";
md += "## Destroy reasoning trail\n" + destroy_reasoning_log + "\n";
md += "## Verify\n- passed: " + tests_passed.to_string() + "\n- reasoning_valid: " + last_reasoning_valid.to_string() + "\n- " + last_summary + "\n";
md += "### Commands\n" + last_commands + "\n### Failures\n" + last_failures + "\n";
md += "### Invalid reasoning\n" + last_invalid_reasoning + "\n";
md += "### Reasoning review\n" + last_reasoning_review + "\n\n";
md += "### Evidence\n" + last_evidence + "\n\n";
md += "### Fix log\n" + (if fix_log == "" { "- (none)\n" } else { fix_log });
md += "\n## Process / todos\n- `" + written_plan + "`\n- `" + written_todo + "`\n\n";
md += "## Unmet\n" + unmet + "\n## Next\n" + nexts + "\n";
md += "## Plan summary\n" + plan_scratch_path + "\n";

let report_path = write_scratch_file("search-and-destroy-report.md", md);
log("Gate: " + verdict + " complete=" + is_complete.to_string()
    + " reasoning_valid=" + last_reasoning_valid.to_string());

complete(#{
    path: report_path,
    plan_path: written_plan,
    todo_path: written_todo,
    plan_summary: plan_scratch_path,
    verdict: verdict,
    complete: is_complete,
    headline: headline,
    tests_passed: tests_passed,
    reasoning_valid: last_reasoning_valid,
    selected: order_ids.len(),
    items_ok: items_ok,
    destroy_reason_gaps: destroy_reason_fail,
    fix_rounds: fix_round,
});
