let meta = #{
    name: "repo-map",
    description: "Read-only map of repo layout, real test/lint commands, and the smallest safe change, with every claim verified against files",
    when_to_use: "Onboarding to a repo, before a first change, or when you need verified test/lint commands instead of guesses",
    phases: [
        #{ title: "Discover", detail: "layout, commands, and smallest safe change in parallel" },
        #{ title: "Verify", detail: "adversarial file-backed check of every claim" },
        #{ title: "Report", detail: "write the verified map" },
    ],
};

const MAX_LAYOUT = 8;
const MAX_COMMANDS = 8;
const MAX_CHANGES = 3;
const LAYOUT_QUOTA = 4;
const COMMAND_QUOTA = 5;
const CHANGE_QUOTA = 3;
// 8 + 8 + 3, so a full discovery fits and refill is not dead.
const MAX_VERIFY = 19;

let layout_schema = #{
    "type": "object", "required": ["items"],
    "properties": #{
        "items": #{ "type": "array", "maxItems": 8, "items": #{
            "type": "object",
            "required": ["path", "role", "language", "evidence_file", "evidence"],
            "properties": #{
                "path": #{ "type": "string" },
                "role": #{ "type": "string" },
                "language": #{ "type": "string" },
                "evidence_file": #{ "type": "string" },
                "evidence": #{ "type": "string" },
            },
        }},
    },
};

let commands_schema = #{
    "type": "object", "required": ["items"],
    "properties": #{
        "items": #{ "type": "array", "maxItems": 8, "items": #{
            "type": "object",
            "required": ["kind", "command", "cwd", "source_file", "evidence"],
            "properties": #{
                "kind": #{ "type": "string" },
                "command": #{ "type": "string" },
                "cwd": #{ "type": "string" },
                "source_file": #{ "type": "string" },
                "evidence": #{ "type": "string" },
            },
        }},
    },
};

let change_schema = #{
    "type": "object", "required": ["items"],
    "properties": #{
        "items": #{ "type": "array", "maxItems": 3, "items": #{
            "type": "object",
            "required": ["title", "description", "why_safe", "files", "verify_command", "cwd", "evidence_file", "evidence"],
            "properties": #{
                "title": #{ "type": "string" },
                "description": #{ "type": "string" },
                "why_safe": #{ "type": "string" },
                "files": #{ "type": "array", "items": #{ "type": "string" } },
                "verify_command": #{ "type": "string" },
                "cwd": #{ "type": "string" },
                "evidence_file": #{ "type": "string" },
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
        "flaw": #{ "type": "string" },
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
    for x in as_array(arr) {
        if i >= n { break; }
        out.push(x);
        i += 1;
    }
    out
}

fn skip_n(arr, n) {
    let out = [];
    let i = 0;
    for x in as_array(arr) {
        if i >= n { out.push(x); }
        i += 1;
    }
    out
}

fn append_up_to(dst, src, n) {
    let out = [];
    for x in as_array(dst) { out.push(x); }
    if n <= 0 { return out; }
    let i = 0;
    for x in as_array(src) {
        if i >= n { break; }
        out.push(x);
        i += 1;
    }
    out
}

fn items_of(r) {
    if r == () { return []; }
    if r.success != true { return []; }
    if r.output == () { return []; }
    if r.output.items == () { return []; }
    as_array(r.output.items)
}

fn item_in_root(it, root) {
    if root == "." || root == "" { return true; }
    if it == () { return false; }
    if path_under(it.path, root) { return true; }
    if path_under(it.cwd, root) { return true; }
    if path_under(it.source_file, root) { return true; }
    if path_under(it.evidence_file, root) { return true; }
    false
}

fn filter_root(arr, root) {
    let out = [];
    let dropped = 0;
    for it in as_array(arr) {
        if item_in_root(it, root) {
            out.push(it);
        } else {
            dropped += 1;
        }
    }
    if dropped > 0 {
        log("Dropped " + dropped.to_string() + " out-of-root items (root=" + root + ")");
    }
    out
}

fn non_empty(s) {
    trimmed(s) != ""
}

fn layout_usable(it) {
    it != () && non_empty(it.path) && non_empty(it.evidence_file) && non_empty(it.evidence)
}

fn command_usable(it) {
    it != () && non_empty(it.command) && non_empty(it.source_file) && non_empty(it.evidence)
}

fn change_usable(it) {
    it != () && non_empty(it.title) && non_empty(it.evidence_file) && non_empty(it.evidence) && non_empty(it.verify_command)
}


fn item_label(kind, it) {
    if it == () { return ""; }
    if kind == "layout" { return trimmed(it.path); }
    if kind == "command" { return trimmed(it.command); }
    if kind == "change" { return trimmed(it.title); }
    ""
}

fn log_extra(kind, arr) {
    for it in as_array(arr) {
        let label = item_label(kind, it);
        if label != "" {
            log("Dropped " + kind + ": " + label);
        }
    }
}

fn keep_usable(arr, kind) {
    let out = [];
    let dropped = 0;
    for it in as_array(arr) {
        let ok = false;
        if kind == "layout" { ok = layout_usable(it); }
        if kind == "command" { ok = command_usable(it); }
        if kind == "change" { ok = change_usable(it); }
        if ok { out.push(it); } else { dropped += 1; }
    }
    if dropped > 0 {
        log("Dropped " + dropped.to_string() + " unusable " + kind + " items");
    }
    out
}

let root = ".";
let focus = "";
if args != () {
    if args.root != () {
        let r = trimmed(args.root);
        if r != "" { root = r; }
    }
    if args.focus != () {
        let f = trimmed(args.focus);
        if f != "" { focus = f; }
    }
}

let root_note = "";
if root != "." {
    root_note = " Scope every path to this root: " + root + ". Ignore sibling trees outside it.";
}
let focus_note = "";
if focus != "" {
    focus_note = " Extra focus (still verify against files): " + focus + ".";
}

phase("Discover");
log("Mapping layout, commands, and smallest safe change (read-only)");

let layout_prompt = "";
layout_prompt += "Map this repository's layout. You are a cold subagent with no memory of this conversation.";
layout_prompt += root_note;
layout_prompt += focus_note;
layout_prompt += " MUST use read-only tools before answering: list_dir on the workspace root, then list_dir on each top-level directory,";
layout_prompt += " and read_file on README.md, AGENTS.md, AGENTS.project.md, CONTRIBUTING.md, and every package.json / pyproject.toml / Cargo.toml / go.mod / mix.exs you find.";
layout_prompt += " Use grep only to locate those manifests. Do not run tests, lint, or any write/execute shell.";
layout_prompt += " Do not invent directories. If several similar app trees exist (copies, PR folders, packages), list each one you actually listed.";
layout_prompt += " Skip node_modules, vendor, target, dist, build, .git, and lockfile-only listings.";
layout_prompt += " Report at most 8 items as {path, role, language, evidence_file, evidence}.";
layout_prompt += " Prefer top-level trees (src, lib, app, crates, packages, cmd, scripts, tests, docs, migrations, integration)";
layout_prompt += " over listing a directory and its manifest as two items.";
layout_prompt += " path is repo-relative. role is e.g. primary app, library crate, package, docs, scripts, migrations.";
layout_prompt += " evidence_file is a file you opened. evidence is a short quote or fact from that file.";
layout_prompt += " An empty list is valid ONLY after you listed the root and found no source trees or manifests.";

let commands_prompt = "";
commands_prompt += "Find the REAL test, lint, typecheck, and format commands in this repo. You are a cold subagent.";
commands_prompt += root_note;
commands_prompt += focus_note;
commands_prompt += " MUST use read-only tools: read every package.json scripts block, Makefile, justfile, pyproject.toml, tox.ini, Cargo.toml,";
commands_prompt += " go.mod, eslint.config.*, ruff.toml, .golangci.yml, and .github/workflows/* if present.";
commands_prompt += " If a script delegates (e.g. test via a wrapper file), also read that file so you report what actually runs.";
commands_prompt += " Do NOT run the commands. Do NOT invent npm test / cargo test / pytest / go test / make test from memory.";
commands_prompt += " For each item: {kind, command, cwd, source_file, evidence}.";
commands_prompt += " kind is one of test, lint, typecheck, format, check.";
commands_prompt += " command is the exact invocation a developer would run in that stack, plus what it delegates to if you read the wrapper.";
commands_prompt += " cwd is the package/crate directory relative to the repo root. source_file is the file you read. evidence quotes the script or CI step.";
commands_prompt += " At most 8 items. Prefer commands a developer actually runs.";
commands_prompt += " If several packages share scripts, report the primary tree and only claim copies match if you compared their manifests.";
commands_prompt += " Empty list is valid ONLY after you searched for package.json, Makefile, pyproject.toml, Cargo.toml, go.mod, and .github/workflows and found no test/lint scripts.";

let change_prompt = "";
change_prompt += "Identify the smallest SAFE change surface in this repo — the cheapest place a future agent could land a verified fix.";
change_prompt += root_note;
change_prompt += focus_note;
change_prompt += " MUST use read-only tools: list_dir, read_file, grep. Read existing unit tests wherever they live";
change_prompt += " (*.test.ts, *.test.js, *.test.mjs, *_test.go, *_test.rs, test_*.py, tests/, spec/),";
change_prompt += " the test runner, and package.json / Makefile / pyproject.toml / Cargo.toml / CI plus AGENTS.md if present.";
change_prompt += " Do not run tests. Do not edit files.";
change_prompt += " Prefer a leaf module that already has a colocated unit test. Prefer pure helpers over UI, auth, database, Docker, or migrations.";
change_prompt += " Do not recommend editing node_modules, vendor, target, dist, lockfiles, generated files (*gen.ts, *_generated.*), or every package in a monorepo at once.";
change_prompt += " Stop as soon as you have 3 qualifying candidates. Do not keep scanning the repository after that.";
change_prompt += " For each candidate, open only that file, its colocated test, and one manifest or CI file that names the verify command.";
change_prompt += " Report at most 3 items as {title, description, why_safe, files, verify_command, cwd, evidence_file, evidence}.";
change_prompt += " why_safe must cite isolation you observed. verify_command must be a command you read from a manifest or runner, not invented";
change_prompt += " (match the stack: npm test, cargo test, pytest, go test, make test, etc.).";
change_prompt += " files must be repo-relative paths you listed or read. evidence_file is a file you opened.";
change_prompt += " Empty list is valid ONLY after you looked for tests and isolated modules and found none.";

let discover_jobs = [
    #{
        prompt: layout_prompt,
        label: "map:layout",
        capability_mode: "read-only",
        agent_type: "explore",
        output_schema: layout_schema,
    },
    #{
        prompt: commands_prompt,
        label: "map:commands",
        capability_mode: "read-only",
        agent_type: "explore",
        output_schema: commands_schema,
    },
    #{
        prompt: change_prompt,
        label: "map:change",
        capability_mode: "read-only",
        agent_type: "explore",
        output_schema: change_schema,
    },
];

let discovered = parallel(discover_jobs);
let layout_items = keep_usable(filter_root(items_of(discovered[0]), root), "layout");
let command_items = keep_usable(filter_root(items_of(discovered[1]), root), "command");
let change_items = keep_usable(filter_root(items_of(discovered[2]), root), "change");

if layout_items.len() > MAX_LAYOUT {
    log("Truncated layout from " + layout_items.len().to_string() + " to " + MAX_LAYOUT.to_string());
    layout_items = take_n(layout_items, MAX_LAYOUT);
}
if command_items.len() > MAX_COMMANDS {
    log("Truncated commands from " + command_items.len().to_string() + " to " + MAX_COMMANDS.to_string());
    command_items = take_n(command_items, MAX_COMMANDS);
}
if change_items.len() > MAX_CHANGES {
    log("Truncated changes from " + change_items.len().to_string() + " to " + MAX_CHANGES.to_string());
    change_items = take_n(change_items, MAX_CHANGES);
}

log("Discovered layout=" + layout_items.len().to_string() + " commands=" + command_items.len().to_string() + " changes=" + change_items.len().to_string());

let layout_extra = skip_n(layout_items, LAYOUT_QUOTA);
let command_extra = skip_n(command_items, COMMAND_QUOTA);
let change_extra = skip_n(change_items, CHANGE_QUOTA);
layout_items = take_n(layout_items, LAYOUT_QUOTA);
command_items = take_n(command_items, COMMAND_QUOTA);
change_items = take_n(change_items, CHANGE_QUOTA);

let leftover = MAX_VERIFY - layout_items.len() - command_items.len() - change_items.len();
if leftover > 0 {
    change_items = append_up_to(change_items, change_extra, leftover);
    change_extra = skip_n(change_extra, leftover);
    leftover = MAX_VERIFY - layout_items.len() - command_items.len() - change_items.len();
}
if leftover > 0 {
    command_items = append_up_to(command_items, command_extra, leftover);
    command_extra = skip_n(command_extra, leftover);
    leftover = MAX_VERIFY - layout_items.len() - command_items.len() - change_items.len();
}
if leftover > 0 {
    layout_items = append_up_to(layout_items, layout_extra, leftover);
    layout_extra = skip_n(layout_extra, leftover);
}
log_extra("change", change_extra);
log_extra("command", command_extra);
log_extra("layout", layout_extra);

log("Verify queue layout=" + layout_items.len().to_string() + " commands=" + command_items.len().to_string() + " changes=" + change_items.len().to_string());

let claims = [];
for it in change_items {
    let statement = "";
    statement += "Smallest safe change: " + trimmed(it.title) + " — " + trimmed(it.description);
    statement += " Verify with: " + trimmed(it.verify_command) + " (cwd " + trimmed(it.cwd) + ").";
    claims.push(#{
        kind: "change",
        statement: statement,
        file: trimmed(it.evidence_file),
        payload: it,
    });
}
for it in command_items {
    let statement = "";
    statement += "Command (" + trimmed(it.kind) + ") in `" + trimmed(it.cwd) + "`: " + trimmed(it.command) + ".";
    claims.push(#{
        kind: "command",
        statement: statement,
        file: trimmed(it.source_file),
        payload: it,
    });
}
for it in layout_items {
    let statement = "";
    statement += "Layout: `" + trimmed(it.path) + "` is " + trimmed(it.role);
    statement += " (language: " + trimmed(it.language) + ").";
    claims.push(#{
        kind: "layout",
        statement: statement,
        file: trimmed(it.evidence_file),
        payload: it,
    });
}

if claims.len() == 0 {
    let empty = "# Repo map\n\nNo file-backed claims survived discovery. Scanners returned nothing usable; this is not a map of the repo.\n";
    let p = write_scratch_file("repo-map.md", empty);
    complete(#{
        path: p,
        summary: "No usable claims from discovery.",
        layout: [],
        commands: [],
        change: [],
        verified: 0,
        unverified: 0,
    });
}

if claims.len() > MAX_VERIFY {
    log("Truncated claims from " + claims.len().to_string() + " to " + MAX_VERIFY.to_string() + " before verify");
    for c in skip_n(claims, MAX_VERIFY) {
        log("Dropped " + c.kind + ": " + trimmed(c.statement));
    }
    claims = take_n(claims, MAX_VERIFY);
}

let remaining = budget().remaining;
if remaining < claims.len() {
    let keep = remaining;
    if keep < 0 { keep = 0; }
    log("Budget remaining " + remaining.to_string() + "; verifying only " + keep.to_string() + " claims");
    for c in skip_n(claims, keep) {
        log("Dropped for budget " + c.kind + ": " + trimmed(c.statement));
    }
    claims = take_n(claims, keep);
}

if claims.len() == 0 {
    let empty = "# Repo map\n\nDiscovery produced claims but none could be verified under the remaining agent budget.\n";
    let p = write_scratch_file("repo-map.md", empty);
    complete(#{
        path: p,
        summary: "No budget left to verify claims.",
        layout: [],
        commands: [],
        change: [],
        verified: 0,
        unverified: 0,
    });
}

phase("Verify");
log("Verifying " + claims.len().to_string() + " claims against files");

let vjobs = [];
let vi = 0;
for c in claims {
    let encoded = json_encode(#{
        kind: c.kind,
        statement: c.statement,
        file: c.file,
        payload: c.payload,
    });
    let vp = "";
    vp += "Adversarially verify this repo-map claim by independently reading the cited file. Do not trust the scanner.";
    vp += " You are a cold subagent. Use only read-only tools (read_file, list_dir, grep). Do not run tests or lint.";
    vp += " Claim JSON:\n";
    vp += encoded;
    vp += "\nOpen only the cited file and at most one supporting file (the path the claim names, or the colocated test). Do not explore the rest of the repository.";
    vp += "\nSet real=true ONLY if every material clause of the statement and payload is supported by those files.";
    vp += " A mostly-true claim is not real: if any clause is false, overstated, or unsupported, set real=false and put that clause in flaw.";
    vp += " Leave flaw empty only when the whole claim holds. Quote the supporting snippet in evidence.";
    vp += " If the file is missing, the quote is absent, the command is not in the scripts/CI file,";
    vp += " or the path does not exist, set real=false. Default real=false when unsure.";
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

let confirmed_layout = [];
let confirmed_commands = [];
let confirmed_change = [];
let unverified = 0;
let i = 0;
for v in verdicts {
    let accepted = false;
    if v != () && v.success == true && v.output != () {
        if v.output.real == true && v.output.evidence != () && trimmed(v.output.evidence) != "" {
            let flawed = false;
            if v.output.flaw != () && trimmed(v.output.flaw) != "" { flawed = true; }
            if flawed {
                log("Rejected claim with a false clause: " + trimmed(v.output.flaw));
            } else {
                accepted = true;
            }
        }
    }
    if accepted {
        let c = claims[i];
        if c.kind == "layout" { confirmed_layout.push(c.payload); }
        if c.kind == "command" { confirmed_commands.push(c.payload); }
        if c.kind == "change" { confirmed_change.push(c.payload); }
    } else {
        unverified += 1;
    }
    i += 1;
}

let verified_n = confirmed_layout.len() + confirmed_commands.len() + confirmed_change.len();
log(verified_n.to_string() + "/" + claims.len().to_string() + " claims survived verification (" + unverified.to_string() + " rejected)");

phase("Report");

let md = "";
md += "# Repo map\n\n";
md += "Read-only map. Commands were **read from files**, not executed. Only claims that survived adversarial file checks are listed.\n\n";
if root != "." {
    md += "Scoped to `" + root + "`.\n\n";
}
if focus != "" {
    md += "Focus: " + focus + "\n\n";
}
md += "Verified " + verified_n.to_string() + " / " + claims.len().to_string() + " claims. ";
md += unverified.to_string() + " rejected or lacked evidence.\n\n";

md += "## Layout\n\n";
if confirmed_layout.len() == 0 {
    md += "_No layout claims survived verification._\n\n";
} else {
    for it in confirmed_layout {
        md += "- `" + trimmed(it.path) + "` — " + trimmed(it.role);
        md += " (" + trimmed(it.language) + ")\n";
        md += "  - Evidence (`" + trimmed(it.evidence_file) + "`): " + trimmed(it.evidence) + "\n";
    }
    md += "\n";
}

md += "## Test and lint commands\n\n";
if confirmed_commands.len() == 0 {
    md += "_No command claims survived verification._\n\n";
} else {
    md += "| Kind | Command | cwd | Source |\n";
    md += "| --- | --- | --- | --- |\n";
    for it in confirmed_commands {
        md += "| " + trimmed(it.kind) + " | `" + trimmed(it.command) + "` | `" + trimmed(it.cwd) + "` | `" + trimmed(it.source_file) + "` |\n";
    }
    md += "\n";
    for it in confirmed_commands {
        md += "- **" + trimmed(it.kind) + "** `" + trimmed(it.command) + "`: " + trimmed(it.evidence) + "\n";
    }
    md += "\n";
}

md += "## Smallest safe change\n\n";
if confirmed_change.len() == 0 {
    md += "_No smallest-safe-change claims survived verification._\n\n";
} else {
    for it in confirmed_change {
        md += "### " + trimmed(it.title) + "\n\n";
        md += trimmed(it.description) + "\n\n";
        md += "- **Why safe:** " + trimmed(it.why_safe) + "\n";
        md += "- **cwd:** `" + trimmed(it.cwd) + "`\n";
        md += "- **Verify:** `" + trimmed(it.verify_command) + "`\n";
        md += "- **Files:**\n";
        for f in as_array(it.files) {
            md += "  - `" + trimmed(f) + "`\n";
        }
        md += "- **Evidence (`" + trimmed(it.evidence_file) + "`):** " + trimmed(it.evidence) + "\n\n";
    }
}

md += "## Limits\n\n";
md += "- Read-only: no edits, and test/lint commands were not executed.\n";
md += "- Unverified scanner claims are omitted, not implied true.\n";
md += "- Discovery fan-out is 3; verification is capped at " + MAX_VERIFY.to_string() + " claims.\n";
md += "- Verify quotas: " + LAYOUT_QUOTA.to_string() + " layout, " + COMMAND_QUOTA.to_string() + " commands, " + CHANGE_QUOTA.to_string() + " changes; unused slots refill change, then commands, then layout.\n";
md += "- Claims that do not fit the verify cap are logged by name and omitted here.\n";
md += "- Each verifier opens the cited file and at most one supporting file. A claim with any false clause is omitted.\n";

let report_path = write_scratch_file("repo-map.md", md);
complete(#{
    path: report_path,
    summary: verified_n.to_string() + " verified claims (" + confirmed_layout.len().to_string() + " layout, " + confirmed_commands.len().to_string() + " commands, " + confirmed_change.len().to_string() + " changes); " + unverified.to_string() + " rejected",
    layout: confirmed_layout,
    commands: confirmed_commands,
    change: confirmed_change,
    verified: verified_n,
    unverified: unverified,
});
