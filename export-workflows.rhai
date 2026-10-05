let meta = #{
    name: "export-workflows",
    description: "Read Grok (or other) multi-agent workflows, emit a host-agnostic universal template, then port to other LLM stacks (Claude, Codex, Cursor, generic)",
    when_to_use: "When you want the same phase contracts runnable outside Grok Build — universal IR plus adapter packs for Claude Code, Codex, Cursor, or a generic multi-agent prompt pack",
    phases: [
        #{ title: "Ingest", detail: "discover and read source workflow definitions" },
        #{ title: "Universal", detail: "write host-agnostic universal template + per-workflow IR" },
        #{ title: "Port", detail: "emit target-LLM adapter packs in parallel" },
        #{ title: "Verify", detail: "check ports cover phases, fail-closed rules, and schemas" },
        #{ title: "Gate", detail: "fail-closed complete with artifact index" },
    ],
};

// --- schemas -----------------------------------------------------------------

let ingest_schema = #{
    "type": "object",
    "required": ["summary", "workflows", "notes"],
    "properties": #{
        "summary": #{ "type": "string" },
        "workflows": #{
            "type": "array",
            "maxItems": 20,
            "items": #{
                "type": "object",
                "required": ["id", "source_path", "title", "purpose", "phases", "args", "fail_closed_rules", "artifacts"],
                "properties": #{
                    "id": #{ "type": "string" },
                    "source_path": #{ "type": "string" },
                    "title": #{ "type": "string" },
                    "purpose": #{ "type": "string" },
                    "phases": #{
                        "type": "array",
                        "maxItems": 20,
                        "items": #{
                            "type": "object",
                            "required": ["name", "goal", "inputs", "outputs", "parallelism"],
                            "properties": #{
                                "name": #{ "type": "string" },
                                "goal": #{ "type": "string" },
                                "inputs": #{ "type": "string" },
                                "outputs": #{ "type": "string" },
                                "parallelism": #{ "type": "string" },
                            },
                        },
                    },
                    "args": #{
                        "type": "array",
                        "maxItems": 30,
                        "items": #{ "type": "string" },
                    },
                    "fail_closed_rules": #{
                        "type": "array",
                        "maxItems": 20,
                        "items": #{ "type": "string" },
                    },
                    "artifacts": #{
                        "type": "array",
                        "maxItems": 20,
                        "items": #{ "type": "string" },
                    },
                },
            },
        },
        "notes": #{ "type": "string" },
    },
};

let universal_schema = #{
    "type": "object",
    "required": ["template_path", "ir_paths", "index_path", "summary", "workflow_ids"],
    "properties": #{
        "template_path": #{ "type": "string" },
        "ir_paths": #{
            "type": "array",
            "maxItems": 30,
            "items": #{ "type": "string" },
        },
        "index_path": #{ "type": "string" },
        "summary": #{ "type": "string" },
        "workflow_ids": #{
            "type": "array",
            "maxItems": 20,
            "items": #{ "type": "string" },
        },
    },
};

let port_schema = #{
    "type": "object",
    "required": ["target", "status", "root_path", "files_written", "summary", "gaps"],
    "properties": #{
        "target": #{ "type": "string" },
        "status": #{ "type": "string" },
        "root_path": #{ "type": "string" },
        "files_written": #{
            "type": "array",
            "maxItems": 60,
            "items": #{ "type": "string" },
        },
        "summary": #{ "type": "string" },
        "gaps": #{
            "type": "array",
            "maxItems": 20,
            "items": #{ "type": "string" },
        },
    },
};

let verify_schema = #{
    "type": "object",
    "required": ["passed", "summary", "checks", "failures", "evidence"],
    "properties": #{
        "passed": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "checks": #{
            "type": "array",
            "maxItems": 40,
            "items": #{ "type": "string" },
        },
        "failures": #{
            "type": "array",
            "maxItems": 30,
            "items": #{ "type": "string" },
        },
        "evidence": #{ "type": "string" },
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

// --- args --------------------------------------------------------------------

let sources_arg = if args == () { () } else { args.sources };
if sources_arg == () && args != () { sources_arg = args.files; }
if sources_arg == () && args != () { sources_arg = args.source; }

let out_dir_arg = if args == () { () } else { args.out_dir };
if out_dir_arg == () && args != () { out_dir_arg = args.output_dir; }

let targets_arg = if args == () { () } else { args.targets };
if targets_arg == () && args != () { targets_arg = args.target; }

let filter_arg = if args == () { () } else { args.workflow };
if filter_arg == () && args != () { filter_arg = args.name; }
if filter_arg == () && args != () { filter_arg = args.only; }

let include_universal = bool_arg(if args == () { () } else { args.include_universal }, true);
let auto_approve = bool_arg(if args == () { () } else { args.auto_approve }, true);

let out_dir = if out_dir_arg == () || trimmed(out_dir_arg.to_string()) == "" {
    "workflow-exports"
} else {
    trimmed(out_dir_arg.to_string())
};

// sources list (optional — empty means discover *.rhai / process packs in cwd)
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

// targets list — default full port set
let default_targets = ["claude", "codex", "cursor", "generic"];
let targets_list = [];
if targets_arg == () {
    for t in default_targets { targets_list.push(t); }
} else if type_of(targets_arg) == "array" {
    for t in targets_arg {
        let x = trimmed(t.to_string());
        if x != "" { targets_list.push(x); }
    }
} else {
    let raw = trimmed(targets_arg.to_string());
    let cur = "";
    let i = 0;
    let n = raw.len();
    while i < n {
        let ch = raw[i];
        if ch == ',' || ch == '\n' || ch == ';' || ch == ' ' {
            cur.trim();
            if cur != "" { targets_list.push(cur); }
            cur = "";
        } else {
            cur += ch;
        }
        i += 1;
    }
    cur.trim();
    if cur != "" { targets_list.push(cur); }
}
if targets_list.len() == 0 {
    for t in default_targets { targets_list.push(t); }
}

// normalize known target aliases
let norm_targets = [];
for t in targets_list {
    let x = trimmed(t);
    // lower-case-ish aliases without full lower API — accept common forms
    if x == "Claude" || x == "claude-code" || x == "Claude-Code" || x == "anthropic" {
        x = "claude";
    }
    if x == "Codex" || x == "openai-codex" || x == "codex-cli" {
        x = "codex";
    }
    if x == "Cursor" || x == "cursor-ide" {
        x = "cursor";
    }
    if x == "Generic" || x == "openai" || x == "multi-agent" || x == "llm" {
        x = "generic";
    }
    let seen = false;
    for e in norm_targets {
        if e == x { seen = true; }
    }
    if !seen && x != "" { norm_targets.push(x); }
}
targets_list = norm_targets;

let filter_text = if filter_arg == () || trimmed(filter_arg.to_string()) == "" {
    ""
} else {
    trimmed(filter_arg.to_string())
};

let sources_blob = "";
if sources_list.len() == 0 {
    sources_blob = "(none passed — discover workflow definitions in the current working directory: *.rhai, and any workflow-exports IR already present)\n";
} else {
    for s in sources_list { sources_blob += "- " + s + "\n"; }
}

let targets_blob = "";
for t in targets_list { targets_blob += "- " + t + "\n"; }

// --- Phase 1: Ingest ---------------------------------------------------------

phase("Ingest");
log("Ingesting workflow sources for export");

let ingest_prompt = "";
ingest_prompt += "You are INGEST for export-workflows.\n";
ingest_prompt += "Goal: extract host-agnostic phase contracts from multi-agent workflow definitions so they can be re-emitted for other LLM stacks.\n";
ingest_prompt += "Working directory = current repo/folder root.\n";
ingest_prompt += "Out dir for later writes (do not write yet): " + out_dir + "\n";
ingest_prompt += "Optional filter (workflow id/name substring; empty = all): " + filter_text + "\n";
ingest_prompt += "Explicit sources:\n" + sources_blob;
ingest_prompt += "REQUIRED method — use tools (list_dir, read_file, grep). Do not invent files.\n";
ingest_prompt += "1) Discover sources: if explicit sources listed, read those. Else scan for *.rhai workflow scripts (especially Grok Build style with let meta = #{ name, description, phases }). Also accept markdown process files that already encode phase pipelines if no rhai present.\n";
ingest_prompt += "2) For each workflow, extract:\n";
ingest_prompt += "   - id (meta.name or slug), source_path, title, purpose (description/when_to_use)\n";
ingest_prompt += "   - ordered phases: name, goal, inputs, outputs, parallelism (none|parallel|sequential loop)\n";
ingest_prompt += "   - args (operator-facing knobs with defaults if visible)\n";
ingest_prompt += "   - fail_closed_rules (evidence required, complete only if..., blocking severity, etc.)\n";
ingest_prompt += "   - artifacts (process files, reports, codex paths, qa dirs)\n";
ingest_prompt += "3) Skip pure helpers and non-workflow scripts. If filter is set, keep only matching ids/paths.\n";
ingest_prompt += "4) notes: stack quirks (e.g. Grok Rhai host APIs: agent/parallel/phase/complete) that ports must emulate, not copy literally.\n";
ingest_prompt += "Empty workflows only after a real search found nothing.\n";

let ingest_r = agent(ingest_prompt, #{
    label: "ingest",
    capability_mode: "execute",
    output_schema: ingest_schema,
});

if ingest_r == () || !ingest_r.success || ingest_r.output == () {
    pause("infra", "Ingest failed. Resume to retry, or pass args.sources pointing at workflow files.");
}

let ingest = ingest_r.output;
let ingest_summary = if ingest.summary != () { ingest.summary } else { "(no summary)" };
let ingest_notes = if ingest.notes != () { ingest.notes } else { "" };

let workflows = [];
if ingest.workflows != () {
    for w in ingest.workflows {
        if w.id != () && trimmed(w.id) != "" {
            workflows.push(w);
        }
    }
}

if workflows.len() == 0 {
    pause("verification", "No workflows extracted. Point args.sources at .rhai workflow files (or run from a folder that contains them), then resume.");
}

let wf_blob = "";
for w in workflows {
    let id = if w.id != () { w.id } else { "?" };
    let path = if w.source_path != () { w.source_path } else { "?" };
    let purpose = if w.purpose != () { w.purpose } else { "" };
    wf_blob += "### " + id + "\n";
    wf_blob += "- path: " + path + "\n";
    wf_blob += "- purpose: " + purpose + "\n";
    if w.phases != () {
        wf_blob += "- phases:\n";
        for p in w.phases {
            let pn = if p.name != () { p.name } else { "?" };
            let pg = if p.goal != () { p.goal } else { "" };
            let pp = if p.parallelism != () { p.parallelism } else { "none" };
            wf_blob += "  - " + pn + " [" + pp + "]: " + pg + "\n";
        }
    }
    wf_blob += "- fail_closed:\n" + join_lines(w.fail_closed_rules, "  - ");
    wf_blob += "- args:\n" + join_lines(w.args, "  - ");
    wf_blob += "- artifacts:\n" + join_lines(w.artifacts, "  - ");
    wf_blob += "\n";
}

log("Ingest: " + workflows.len().to_string() + " workflow(s) — " + ingest_summary);

// --- Phase 2: Universal template + IR ----------------------------------------

phase("Universal");
log("Writing universal template under " + out_dir);

let uni_prompt = "";
uni_prompt += "You are UNIVERSAL TEMPLATE WRITER for export-workflows.\n";
uni_prompt += "Write a host-agnostic intermediate representation that ANY multi-agent LLM stack can implement.\n";
uni_prompt += "Out directory (create as needed): " + out_dir + "\n";
uni_prompt += "Include universal template: " + include_universal.to_string() + "\n";
uni_prompt += "Ingest summary: " + ingest_summary + "\n";
uni_prompt += "Notes: " + ingest_notes + "\n";
uni_prompt += "Workflows extracted:\n" + wf_blob;
uni_prompt += "REQUIRED — use write/search_replace tools to create real files:\n";
uni_prompt += "1) If include_universal=true, WRITE " + out_dir + "/UNIVERSAL_WORKFLOW_TEMPLATE.md with:\n";
uni_prompt += "   # Universal Multi-Agent Workflow Template\n";
uni_prompt += "   ## Purpose\n## Core vocabulary (phase, agent role, schema, fail-closed gate, artifact, budget)\n";
uni_prompt += "   ## Authoring checklist\n## Phase contract schema (markdown tables)\n";
uni_prompt += "   ## Structured I/O (JSON Schema conventions)\n## Parallelism patterns\n";
uni_prompt += "   ## Fail-closed rules\n## Human gates\n## Porting matrix (Grok / Claude / Codex / Cursor / Generic)\n";
uni_prompt += "   ## Blank workflow skeleton (copy-paste)\n";
uni_prompt += "   Make it usable without Grok-specific APIs. Map concepts: agent()→subagent/task, parallel()→fan-out barrier, phase()→section, complete()→final report, await_user→human gate.\n";
uni_prompt += "2) For EACH workflow id, WRITE " + out_dir + "/ir/<id>.md — full IR: purpose, args, phases (goal/inputs/outputs/parallelism/prompt skeleton), schemas (as fenced json where known), fail-closed rules, artifacts, acceptance for complete=true.\n";
uni_prompt += "3) WRITE " + out_dir + "/INDEX.md listing every workflow + links to ir/*.md and later ports.\n";
uni_prompt += "4) Return template_path, ir_paths[], index_path, summary, workflow_ids[].\n";
uni_prompt += "Do not invent phases that were not in the extract; you may clarify wording.\n";

let uni_r = agent(uni_prompt, #{
    label: "universal",
    capability_mode: "read-write",
    output_schema: universal_schema,
});

if uni_r == () || !uni_r.success || uni_r.output == () {
    pause("infra", "Universal template agent failed. Resume to retry.");
}

let template_path = if uni_r.output.template_path != () { trimmed(uni_r.output.template_path) } else { out_dir + "/UNIVERSAL_WORKFLOW_TEMPLATE.md" };
let index_path = if uni_r.output.index_path != () { trimmed(uni_r.output.index_path) } else { out_dir + "/INDEX.md" };
let uni_summary = if uni_r.output.summary != () { uni_r.output.summary } else { "" };
let ir_blob = join_lines(uni_r.output.ir_paths, "- ");
if ir_blob == "" { ir_blob = "- (see " + out_dir + "/ir/)\n"; }

let ids_blob = "";
if uni_r.output.workflow_ids != () {
    for id in uni_r.output.workflow_ids {
        ids_blob += "- " + id + "\n";
    }
}
if ids_blob == "" {
    for w in workflows {
        if w.id != () { ids_blob += "- " + w.id + "\n"; }
    }
}

log("Universal: " + uni_summary);

if !auto_approve {
    await_user("user", "Universal IR written under " + out_dir + ".\nTemplate: " + template_path + "\nIndex: " + index_path + "\nResume to port to targets:\n" + targets_blob);
}

// --- Phase 3: Port to target stacks ------------------------------------------

phase("Port");
log("Porting to " + targets_list.len().to_string() + " target stack(s)");

let port_jobs = [];
for t in targets_list {
    let pp = "";
    pp += "You are PORT WRITER for target stack: " + t + ".\n";
    pp += "Export root: " + out_dir + "\n";
    pp += "Universal template path: " + template_path + "\n";
    pp += "Index path: " + index_path + "\n";
    pp += "IR files:\n" + ir_blob;
    pp += "Workflow ids:\n" + ids_blob;
    pp += "Source extract (authority for phases/rules):\n" + wf_blob;
    pp += "Host notes: " + ingest_notes + "\n";
    pp += "REQUIRED — read IR + template with tools, then WRITE a complete adapter pack under " + out_dir + "/" + t + "/ :\n";
    if t == "claude" {
        pp += "Claude Code oriented pack:\n";
        pp += "- README.md (how to install/run)\n";
        pp += "- For each workflow: skills/<id>/SKILL.md (triggers, phases as procedure, fail-closed, tool use commands)\n";
        pp += "- Optional: prompts/<id>/<phase>.md for long phase prompts\n";
        pp += "- Map Grok agent/parallel to Claude multi-agent / Task patterns without claiming false host APIs.\n";
    } else if t == "codex" {
        pp += "Codex CLI oriented pack:\n";
        pp += "- README.md\n";
        pp += "- AGENTS.md or agents/<id>.md describing multi-step orchestration\n";
        pp += "- prompts/<id>/*.md phase prompts with explicit tool-use requirements\n";
        pp += "- scripts or checklist for human-driven phase order if host lacks parallel()\n";
    } else if t == "cursor" {
        pp += "Cursor oriented pack:\n";
        pp += "- README.md\n";
        pp += "- .cursor/rules/<id>.mdc or rules/<id>.md with always-apply false + description triggers\n";
        pp += "- prompts/<id>/*.md for composer/agent phases\n";
        pp += "- Keep rules actionable and scoped; encode fail-closed gates clearly.\n";
    } else {
        pp += "Generic multi-agent pack (host-neutral):\n";
        pp += "- README.md\n";
        pp += "- For each workflow: <id>/workflow.md (phase runbook) + <id>/schemas/*.json if schemas were extractable\n";
        pp += "- <id>/roles/*.md (one file per agent role)\n";
        pp += "- OPERATORS.md: how to run phases manually with any chat/agent product\n";
    }
    pp += "status: done|partial|blocked. List files_written with real paths. gaps: anything the target cannot faithfully represent.\n";
    pp += "Do not drop fail-closed rules. Do not invent product APIs that do not exist.\n";
    port_jobs.push(#{
        prompt: pp,
        label: "port:" + t,
        capability_mode: "all",
        output_schema: port_schema,
    });
}

let port_results = parallel(port_jobs);
let port_log = "";
let port_files = "";
let ports_ok = 0;
let pi = 0;
for r in port_results {
    let tname = if pi < targets_list.len() { targets_list[pi] } else { "?" };
    if r == () || !r.success || r.output == () {
        port_log += "- " + tname + ": FAILED (agent)\n";
    } else {
        let o = r.output;
        let st = if o.status != () { trimmed(o.status) } else { "unknown" };
        let sum = if o.summary != () { o.summary } else { "" };
        let root = if o.root_path != () { o.root_path } else { out_dir + "/" + tname };
        port_log += "- " + tname + " [" + st + "] root=" + root + " — " + sum + "\n";
        port_log += join_lines(o.gaps, "  gap: ");
        let more = join_lines(o.files_written, "  - ");
        if more != "" { port_files += more; }
        if st == "done" || st == "partial" { ports_ok += 1; }
    }
    pi += 1;
}

log("Ports ok-ish: " + ports_ok.to_string() + "/" + targets_list.len().to_string());

// --- Phase 4: Verify ---------------------------------------------------------

phase("Verify");
log("Verifying export completeness");

let vp = "";
vp += "You are VERIFIER for export-workflows. Fail closed.\n";
vp += "Out dir: " + out_dir + "\n";
vp += "Template: " + template_path + "\n";
vp += "Index: " + index_path + "\n";
vp += "IR paths:\n" + ir_blob;
vp += "Targets:\n" + targets_blob;
vp += "Port log:\n" + port_log;
vp += "Files claimed:\n" + port_files;
vp += "Source workflows:\n" + wf_blob;
vp += "REQUIRED:\n";
vp += "1) list_dir/read_file the export tree. Confirm universal template (if required), INDEX, ir/* for each workflow id, and each target root exists with README.\n";
vp += "2) Spot-check one workflow across targets: every phase name appears; fail-closed rules not silently dropped.\n";
vp += "3) passed=true only with non-empty evidence of files actually present.\n";
vp += "4) failures: missing files, empty stubs, dropped phases/rules.\n";

let vr = agent(vp, #{
    label: "verify",
    capability_mode: "execute",
    output_schema: verify_schema,
});

let verify_passed = false;
let verify_summary = "";
let verify_evidence = "";
let verify_failures = "";
let verify_checks = "";
if vr != () && vr.success && vr.output != () {
    let o = vr.output;
    if o.summary != () { verify_summary = o.summary; }
    if o.evidence != () { verify_evidence = o.evidence; }
    verify_failures = join_lines(o.failures, "- ");
    verify_checks = join_lines(o.checks, "- ");
    if o.passed == true && trimmed(verify_evidence) != "" {
        verify_passed = true;
    }
} else {
    verify_summary = "verifier failed";
    verify_failures = "- verifier infrastructure failure\n";
}
if verify_failures == "" { verify_failures = "- (none)\n"; }

log("Verify passed=" + verify_passed.to_string() + ": " + verify_summary);

// --- Phase 5: Gate -----------------------------------------------------------

phase("Gate");

let gp = "";
gp += "COMPLETION GATE for export-workflows. Fail closed.\n";
gp += "complete=true only if universal IR exists for extracted workflows AND each requested target has a real adapter pack AND verify_passed with evidence.\n";
gp += "out_dir=" + out_dir + "\n";
gp += "template=" + template_path + "\n";
gp += "index=" + index_path + "\n";
gp += "ports_ok=" + ports_ok.to_string() + "/" + targets_list.len().to_string() + "\n";
gp += "verify_passed=" + verify_passed.to_string() + "\n";
gp += "Verify: " + verify_summary + "\nEvidence:\n" + verify_evidence + "\n";
gp += "Failures:\n" + verify_failures;
gp += "Port log:\n" + port_log;
gp += "Read INDEX and sample target READMEs. verdict COMPLETE|PARTIAL|INCOMPLETE.\n";

let gr = agent(gp, #{
    label: "gate",
    capability_mode: "execute",
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

if !verify_passed {
    is_complete = false;
    if verdict == "COMPLETE" { verdict = "PARTIAL"; }
}
if ports_ok < targets_list.len() {
    is_complete = false;
    if verdict == "COMPLETE" { verdict = "PARTIAL"; }
}
if is_complete && verdict != "COMPLETE" {
    is_complete = false;
}
if !is_complete && verdict == "COMPLETE" { verdict = "INCOMPLETE"; }

if unmet == "" {
    unmet = if is_complete { "- (none)\n" } else { "- export incomplete or verify failed\n" };
}
if nexts == "" {
    nexts = if is_complete {
        "- Open " + index_path + " and use target packs under " + out_dir + "/\n"
    } else {
        "- Re-run export-workflows after fixing missing IR/ports; pass clearer args.sources if needed\n"
    };
}

let report = "";
report += "# export-workflows report\n\n";
report += "**Verdict:** " + verdict + "\n\n";
report += "**Headline:** " + headline + "\n\n";
report += "**Complete:** " + is_complete.to_string() + "\n\n";
report += "## Out dir\n\n`" + out_dir + "`\n\n";
report += "## Universal\n\n- template: " + template_path + "\n- index: " + index_path + "\n\n";
report += "## Workflows\n\n" + ids_blob + "\n";
report += "## Targets\n\n" + targets_blob + "\n";
report += "## Port log\n\n" + port_log + "\n";
report += "## Verify\n\n" + verify_summary + "\n\n### Checks\n" + verify_checks + "\n### Failures\n" + verify_failures + "\n### Evidence\n" + verify_evidence + "\n\n";
report += "## Unmet\n\n" + unmet + "\n## Next steps\n\n" + nexts + "\n";

let report_path = write_scratch_file("export-workflows-report.md", report);
log("export-workflows done: " + verdict);

complete(#{
    path: report_path,
    complete: is_complete,
    verdict: verdict,
    headline: headline,
    out_dir: out_dir,
    template_path: template_path,
    index_path: index_path,
    targets: targets_list.len(),
    ports_ok: ports_ok,
    verify_passed: verify_passed,
});
