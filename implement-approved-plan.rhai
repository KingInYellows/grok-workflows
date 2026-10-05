let meta = #{
    name: "implement-approved-plan",
    description: "Implement an approved plan in an isolated worktree, run tests after, and stop without applying if tests fail",
    when_to_use: "After a design or planning document is approved: implement only the approved work in a worktree, then run tests and halt on failure",
    phases: [
        #{ title: "Load", detail: "read the approved plan and the real test command" },
        #{ title: "Implement", detail: "apply approved work in an isolated worktree" },
        #{ title: "Test", detail: "run tests in that worktree; stop on failure" },
        #{ title: "Report", detail: "write the run report" },
    ],
};

const MAX_STEPS = 12;
const MAX_FILES = 40;
const MAX_FAILING = 20;

let plan_schema = #{
    "type": "object",
    "required": ["title", "approved", "approval_evidence", "steps", "files", "constraints", "cwd"],
    "properties": #{
        "title": #{ "type": "string" },
        "approved": #{ "type": "boolean" },
        "approval_evidence": #{ "type": "string" },
        "steps": #{
            "type": "array", "maxItems": 12,
            "items": #{
                "type": "object",
                "required": ["id", "title", "description", "files"],
                "properties": #{
                    "id": #{ "type": "string" },
                    "title": #{ "type": "string" },
                    "description": #{ "type": "string" },
                    "files": #{ "type": "array", "items": #{ "type": "string" } },
                },
            },
        },
        "files": #{ "type": "array", "items": #{ "type": "string" } },
        "constraints": #{ "type": "array", "items": #{ "type": "string" } },
        "cwd": #{ "type": "string" },
    },
};

let command_schema = #{
    "type": "object",
    "required": ["command", "cwd", "source_file", "evidence"],
    "properties": #{
        "command": #{ "type": "string" },
        "cwd": #{ "type": "string" },
        "source_file": #{ "type": "string" },
        "evidence": #{ "type": "string" },
    },
};

let impl_schema = #{
    "type": "object",
    "required": ["ok", "summary", "files_changed", "commit", "notes"],
    "properties": #{
        "ok": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "files_changed": #{ "type": "array", "maxItems": 40, "items": #{ "type": "string" } },
        "commit": #{ "type": "string" },
        "notes": #{ "type": "string" },
    },
};

let test_schema = #{
    "type": "object",
    "required": ["passed", "command", "cwd", "summary", "failing"],
    "properties": #{
        "passed": #{ "type": "boolean" },
        "command": #{ "type": "string" },
        "cwd": #{ "type": "string" },
        "summary": #{ "type": "string" },
        "failing": #{ "type": "array", "maxItems": 20, "items": #{ "type": "string" } },
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

fn non_empty(s) {
    trimmed(s) != ""
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

fn str_list(arr, cap) {
    let out = [];
    if arr == () { return out; }
    let i = 0;
    for x in arr {
        if i >= cap { break; }
        let t = trimmed(x);
        if t != "" { out.push(t); i += 1; }
    }
    out
}

fn pick_str(preferred, fallback) {
    if non_empty(preferred) { return trimmed(preferred); }
    trimmed(fallback)
}

if args == () {
    pause("verification", "Pass args.plan — path to the approved plan document.");
}

let plan_path = "";
if args.plan != () { plan_path = trimmed(args.plan); }
if plan_path == "" {
    pause("verification", "Pass args.plan — a non-empty path to the approved plan document.");
}

let arg_cwd = "";
let arg_test = "";
if args.cwd != () { arg_cwd = trimmed(args.cwd); }
if args.test_command != () { arg_test = trimmed(args.test_command); }

let plan_json = json_encode(plan_path);

phase("Load");
log("Reading approved plan and discovering the real test command");

let plan_prompt = "";
plan_prompt += "You are a cold subagent. Parse an APPROVED implementation plan from a file. Use read-only tools.";
plan_prompt += " MUST call read_file on this path before answering: ";
plan_prompt += plan_json;
plan_prompt += " If the path is missing, set approved=false and put the error in approval_evidence.";
plan_prompt += " Do not invent sections you did not read.";
plan_prompt += " approved=true ONLY if the file itself records approval (for example: Status approved,";
plan_prompt += " 'D01, D02, D03, and D04 are approved', a reviewer reporting 0 open issues, or an explicit owner approval).";
plan_prompt += " Quote the approval sentence in approval_evidence. If approval is mixed, approved=true only for the document as a whole";
plan_prompt += " when at least one item is approved; then list ONLY the approved items as steps.";
plan_prompt += " Exclude proposed, open, deferred, unapproved, and 'awaits the user' items. Do not treat a discussion draft as fully approved.";
plan_prompt += " If the file has a ## PR Plan section, those PR entries that are in scope become steps (id PR N, title, description, files).";
plan_prompt += " If it is a decision record, each approved ID (e.g. D01) is a step. title is the document title.";
plan_prompt += " files are repo-relative paths named in the approved work. constraints are binding 'must not' / 'do not' rules you read.";
plan_prompt += " cwd is the package directory the work lives in if the doc names one, else empty.";
plan_prompt += " Empty steps are valid ONLY after reading the file and finding no implementable approved work.";
plan_prompt += " At most 12 steps. Do not run tests or edit files.";

let cmd_prompt = "";
cmd_prompt += "Find the REAL test command for this repo. You are a cold subagent. Use only read-only tools.";
cmd_prompt += " MUST read package.json (scripts.test and related), scripts/test.mjs if that is what test delegates to,";
cmd_prompt += " pyproject.toml, Makefile, justfile, and .github/workflows if present. Prefer the package that args/plan work would touch.";
if arg_cwd != "" {
    cmd_prompt += " Preferred package directory: " + json_encode(arg_cwd) + ".";
}
cmd_prompt += " Do NOT run tests. Do NOT invent npm test / cargo test / pytest from memory.";
cmd_prompt += " Return {command, cwd, source_file, evidence}.";
cmd_prompt += " command is the exact developer invocation (e.g. npm test) plus the wrapper it delegates to if you read that file.";
cmd_prompt += " cwd is the package directory relative to the repo root. source_file is the file you read. evidence quotes the script.";
cmd_prompt += " If several app copies exist, pick the primary application tree unless the plan path sits inside a copy.";
cmd_prompt += " If you cannot find a test script after searching those manifests, return empty command and explain in evidence.";

let load_jobs = [
    #{
        prompt: plan_prompt,
        label: "load:plan",
        capability_mode: "read-only",
        agent_type: "explore",
        output_schema: plan_schema,
    },
    #{
        prompt: cmd_prompt,
        label: "load:test-command",
        capability_mode: "read-only",
        agent_type: "explore",
        output_schema: command_schema,
    },
];

let loaded = parallel(load_jobs);
let plan_r = loaded[0];
let cmd_r = loaded[1];

let plan_ok = false;
let plan_out = ();
if plan_r != () && plan_r.success == true && plan_r.output != () {
    plan_ok = true;
    plan_out = plan_r.output;
}

if !plan_ok {
    log("Plan load failed; stopping");
    let md = "";
    md += "# Implement approved plan\n\n";
    md += "**Status:** load_failed\n\n";
    md += "Could not read or parse `" + plan_path + "`. No implementation ran. Parent workspace is unchanged.\n";
    let p = write_scratch_file("implement-approved-plan.md", md);
    complete(#{
        path: p,
        status: "load_failed",
        summary: "Plan load failed; stopped before implementation.",
        plan: plan_path,
        isolation: "worktree",
        parent_unchanged: true,
        tests_passed: false,
    });
}

let approved = false;
if plan_out.approved == true { approved = true; }
let title = trimmed(plan_out.title);
let approval_evidence = trimmed(plan_out.approval_evidence);
let steps = [];
if plan_out.steps != () { steps = take_n(plan_out.steps, MAX_STEPS); }
let plan_files = str_list(plan_out.files, MAX_FILES);
let constraints = str_list(plan_out.constraints, 20);
let plan_cwd = "";
if plan_out.cwd != () { plan_cwd = trimmed(plan_out.cwd); }

if !approved {
    log("Plan is not approved; stopping");
    let md = "";
    md += "# Implement approved plan\n\n";
    md += "**Status:** not_approved\n\n";
    md += "Stopped before implementation. `" + plan_path + "` was not treated as approved.\n\n";
    if approval_evidence != "" {
        md += "**Evidence:** " + approval_evidence + "\n";
    }
    md += "\nParent workspace is unchanged. Pass a document that records approval, or start a new run with a different `args.plan`.\n";
    let p = write_scratch_file("implement-approved-plan.md", md);
    complete(#{
        path: p,
        status: "not_approved",
        summary: "Plan is not approved; stopped before implementation.",
        plan: plan_path,
        title: title,
        approval_evidence: approval_evidence,
        isolation: "worktree",
        parent_unchanged: true,
        tests_passed: false,
    });
}

let discovered_cmd = "";
let discovered_cwd = "";
let cmd_source = "";
let cmd_evidence = "";
if cmd_r != () && cmd_r.success == true && cmd_r.output != () {
    discovered_cmd = trimmed(cmd_r.output.command);
    discovered_cwd = trimmed(cmd_r.output.cwd);
    cmd_source = trimmed(cmd_r.output.source_file);
    cmd_evidence = trimmed(cmd_r.output.evidence);
}

let test_cmd = pick_str(arg_test, discovered_cmd);
let pkg_cwd = ".";
if non_empty(discovered_cwd) { pkg_cwd = discovered_cwd; }
if non_empty(plan_cwd) { pkg_cwd = plan_cwd; }
if non_empty(arg_cwd) { pkg_cwd = arg_cwd; }

if test_cmd == "" {
    log("No real test command found; stopping");
    let md = "";
    md += "# Implement approved plan\n\n";
    md += "**Status:** no_test_command\n\n";
    md += "Stopped before implementation because no file-backed test command was found, and `args.test_command` was not set.\n\n";
    if cmd_evidence != "" {
        md += "**Discovery:** " + cmd_evidence + "\n";
    }
    md += "\nPass `args.test_command` or add a test script the loader can read. Parent workspace is unchanged.\n";
    let p = write_scratch_file("implement-approved-plan.md", md);
    complete(#{
        path: p,
        status: "no_test_command",
        summary: "No test command; stopped before implementation.",
        plan: plan_path,
        title: title,
        isolation: "worktree",
        parent_unchanged: true,
        tests_passed: false,
    });
}

log("Approved plan loaded (" + steps.len().to_string() + " steps). Test: " + test_cmd + " (cwd " + pkg_cwd + ")");

phase("Implement");
log("Implementing approved work in an isolated worktree");

let plan_payload = json_encode(#{
    path: plan_path,
    title: title,
    approval_evidence: approval_evidence,
    steps: steps,
    files: plan_files,
    constraints: constraints,
    cwd: pkg_cwd,
});

let impl_prompt = "";
impl_prompt += "You are implementing an APPROVED plan in an isolated git worktree. The parent workspace must stay clean.";
impl_prompt += " You are a cold subagent. Do not answer from memory: read the plan file and the code before editing.";
impl_prompt += " Plan path (MUST read_file this): " + plan_json + "\n";
impl_prompt += " Parsed approved work JSON:\n";
impl_prompt += plan_payload;
impl_prompt += "\nWorking directory for the package: " + json_encode(pkg_cwd) + ".\n";
impl_prompt += " Instructions:\n";
impl_prompt += "1. Read the plan file in full. Read AGENTS.md / AGENTS.project.md in the package if they exist.\n";
impl_prompt += "2. Implement ONLY approved steps. Do not implement proposed, deferred, open, or unapproved items.\n";
impl_prompt += "3. Smallest change that matches the plan. Follow existing patterns. Do not add extra features.\n";
impl_prompt += "4. Honor constraints from the plan (no trades/waivers/lineups/messages, no unapproved model/provider work, etc.).\n";
impl_prompt += "5. Do NOT run the full test suite. Tests are a later gated phase. You may typecheck if cheap.\n";
impl_prompt += "6. Stay in this worktree. Do not merge, cherry-pick, or copy changes into the parent workspace.\n";
impl_prompt += "7. Commit your work in the worktree with a descriptive message if git is available.\n";
impl_prompt += " Return {ok, summary, files_changed, commit, notes}. ok=true only if the approved work was applied in this worktree.";
impl_prompt += " files_changed are repo-relative paths you actually edited. commit is the SHA or empty if you could not commit.";
impl_prompt += " notes cover deviations and anything left unimplemented. If the plan has no implementable code changes, ok=true, files_changed=[], and say so in summary.";

let impl_r = agent(impl_prompt, #{
    label: "implement:worktree",
    capability_mode: "all",
    isolation_worktree: true,
    output_schema: impl_schema,
});

let impl_ok = false;
let impl_summary = "";
let impl_commit = "";
let impl_notes = "";
let files_changed = [];
if impl_r != () && impl_r.success == true && impl_r.output != () {
    if impl_r.output.ok == true { impl_ok = true; }
    impl_summary = trimmed(impl_r.output.summary);
    impl_commit = trimmed(impl_r.output.commit);
    impl_notes = trimmed(impl_r.output.notes);
    files_changed = str_list(impl_r.output.files_changed, MAX_FILES);
}

if !impl_ok {
    log("Implementation failed; skipping tests and stopping");
    let md = "";
    md += "# Implement approved plan\n\n";
    md += "**Status:** implement_failed\n\n";
    md += "Implementation in the isolated worktree did not succeed. Tests were not run. Parent workspace is unchanged.\n\n";
    md += "- **Plan:** `" + plan_path + "`\n";
    md += "- **Title:** " + title + "\n";
    if impl_summary != "" { md += "- **Summary:** " + impl_summary + "\n"; }
    if impl_notes != "" { md += "- **Notes:** " + impl_notes + "\n"; }
    let p = write_scratch_file("implement-approved-plan.md", md);
    complete(#{
        path: p,
        status: "implement_failed",
        summary: "Implementation failed; stopped before tests.",
        plan: plan_path,
        title: title,
        isolation: "worktree",
        parent_unchanged: true,
        tests_passed: false,
        files_changed: files_changed,
        notes: impl_notes,
    });
}

phase("Test");
log("Running tests in the implementer's worktree; will stop if they fail");

let test_payload = json_encode(#{
    command: test_cmd,
    cwd: pkg_cwd,
    source_file: cmd_source,
    evidence: cmd_evidence,
});

let test_prompt = "";
test_prompt += "You are resumed in the same isolated worktree as the implementation. Run tests NOW. Do not implement more plan work.";
test_prompt += " Do not fix failures. Do not skip tests. Do not claim a pass from memory.";
test_prompt += " MUST execute this exact command (or the documented equivalent in this cwd) with the shell:\n";
test_prompt += test_payload;
test_prompt += "\nIf cwd is not '.', run the command from that package directory.";
test_prompt += " passed=true ONLY if the process exited 0. If it failed, timed out, or you could not run it, passed=false.";
test_prompt += " summary must include the exit code and a short excerpt of the tail of the output.";
test_prompt += " failing is the list of failing test names (at most 20). Empty only on a real pass or a harness crash with no names.";
test_prompt += " Return {passed, command, cwd, summary, failing}. command is what you actually ran.";

let test_opts = #{
    label: "test:worktree",
    capability_mode: "execute",
    output_schema: test_schema,
};
if impl_r.agent_id != () {
    test_opts.resume_from = impl_r.agent_id;
}

let test_r = agent(test_prompt, test_opts);

let tests_passed = false;
let test_ran = "";
let test_cwd_used = pkg_cwd;
let test_summary = "";
let failing = [];
let test_agent_ok = false;
if test_r != () && test_r.success == true && test_r.output != () {
    test_agent_ok = true;
    if test_r.output.passed == true { tests_passed = true; }
    test_ran = trimmed(test_r.output.command);
    if non_empty(test_r.output.cwd) { test_cwd_used = trimmed(test_r.output.cwd); }
    test_summary = trimmed(test_r.output.summary);
    failing = str_list(test_r.output.failing, MAX_FAILING);
}

if !test_agent_ok {
    tests_passed = false;
    test_summary = "Test agent failed or returned no usable output. Treated as a test failure (fail closed).";
}

if test_ran == "" { test_ran = test_cmd; }

if !tests_passed {
    log("STOP: tests failed");
    let md = "";
    md += "# Implement approved plan\n\n";
    md += "**Status:** tests_failed\n\n";
    md += "Tests failed after implementation. **Stopped.** No apply to the parent workspace. No fix loop.\n\n";
    md += "## Plan\n\n";
    md += "- **Path:** `" + plan_path + "`\n";
    md += "- **Title:** " + title + "\n";
    if approval_evidence != "" {
        md += "- **Approval:** " + approval_evidence + "\n";
    }
    md += "\n## Implementation (worktree only)\n\n";
    md += impl_summary + "\n\n";
    if impl_commit != "" { md += "- **Commit:** `" + impl_commit + "`\n"; }
    if impl_notes != "" { md += "- **Notes:** " + impl_notes + "\n"; }
    md += "- **Files:**\n";
    if files_changed.len() == 0 {
        md += "  - _(none reported)_\n";
    } else {
        for f in files_changed { md += "  - `" + f + "`\n"; }
    }
    md += "\n## Tests\n\n";
    md += "- **Command:** `" + test_ran + "`\n";
    md += "- **cwd:** `" + test_cwd_used + "`\n";
    if cmd_source != "" { md += "- **Source:** `" + cmd_source + "`\n"; }
    md += "- **Result:** FAILED\n\n";
    md += test_summary + "\n\n";
    if failing.len() > 0 {
        md += "**Failing:**\n";
        for t in failing { md += "- " + t + "\n"; }
        md += "\n";
    }
    md += "Parent workspace is unchanged. Isolation was worktree. Resume does not bypass this gate; start a new run after fixing tests.\n";
    let p = write_scratch_file("implement-approved-plan.md", md);
    complete(#{
        path: p,
        status: "tests_failed",
        summary: "Tests failed; stopped. Parent workspace unchanged.",
        plan: plan_path,
        title: title,
        isolation: "worktree",
        parent_unchanged: true,
        tests_passed: false,
        test_command: test_ran,
        cwd: test_cwd_used,
        files_changed: files_changed,
        failing: failing,
        notes: test_summary,
    });
}

phase("Report");
log("Tests passed. Work remains in the isolated worktree; parent is unchanged");

let md = "";
md += "# Implement approved plan\n\n";
md += "**Status:** passed\n\n";
md += "Approved work was implemented in an **isolated worktree** and tests passed. ";
md += "The parent workspace was **not** updated (worktree isolation does not merge).\n\n";
md += "## Plan\n\n";
md += "- **Path:** `" + plan_path + "`\n";
md += "- **Title:** " + title + "\n";
if approval_evidence != "" {
    md += "- **Approval:** " + approval_evidence + "\n";
}
md += "- **Steps implemented:** " + steps.len().to_string() + "\n\n";
if steps.len() > 0 {
    for s in steps {
        let sid = trimmed(s.id);
        let st = trimmed(s.title);
        md += "- **" + sid + "** " + st + "\n";
    }
    md += "\n";
}
md += "## Implementation\n\n";
md += impl_summary + "\n\n";
if impl_commit != "" { md += "- **Commit:** `" + impl_commit + "`\n"; }
if impl_notes != "" { md += "- **Notes:** " + impl_notes + "\n"; }
md += "- **Files:**\n";
if files_changed.len() == 0 {
    md += "  - _(none reported)_\n";
} else {
    for f in files_changed { md += "  - `" + f + "`\n"; }
}
md += "\n## Tests\n\n";
md += "- **Command:** `" + test_ran + "`\n";
md += "- **cwd:** `" + test_cwd_used + "`\n";
if cmd_source != "" { md += "- **Source:** `" + cmd_source + "`\n"; }
md += "- **Result:** passed\n\n";
if test_summary != "" { md += test_summary + "\n\n"; }
md += "## Isolation\n\n";
md += "Implementer used `isolation_worktree`. Tests resumed in that worktree. ";
md += "Nothing was copied into the parent workspace. Apply the worktree commit yourself if you want it on the working branch.\n";

let report_path = write_scratch_file("implement-approved-plan.md", md);
complete(#{
    path: report_path,
    status: "passed",
    summary: "Approved plan implemented in a worktree; tests passed. Parent workspace unchanged.",
    plan: plan_path,
    title: title,
    isolation: "worktree",
    parent_unchanged: true,
    tests_passed: true,
    test_command: test_ran,
    cwd: test_cwd_used,
    files_changed: files_changed,
    commit: impl_commit,
});
