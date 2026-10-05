let meta = #{
    name: "workspace-map",
    description: "Read-only map of git roots, stacks, and verified commands in a multi-repo workspace",
    when_to_use: "Before starting work in a multi-repo workspace: discover git roots and worktrees, then report stack, verified commands, dirtiness, and a first-touch file.",
    phases: [
        #{ title: "Discover", detail: "find git roots and worktrees under args.root" },
        #{ title: "Map", detail: "one inspector per root" },
        #{ title: "Verify", detail: "prove each command name against AGENTS.md or Makefile" },
        #{ title: "Report", detail: "one table plus an 8-line summary" },
    ],
};

let discover_schema = #{
    "type": "object",
    "required": ["roots"],
    "properties": #{
        "roots": #{
            "type": "array",
            "maxItems": 24,
            "items": #{
                "type": "object",
                "required": ["path", "source"],
                "properties": #{
                    "path": #{ "type": "string" },
                    "source": #{ "type": "string" },
                },
            },
        },
    },
};

let repo_schema = #{
    "type": "object",
    "required": [
        "path", "origin", "branch", "dirty", "ahead_behind", "stack",
        "test_cmd", "lint_cmd", "typecheck_cmd", "verify_cmd", "kind", "first_touch",
    ],
    "properties": #{
        "path": #{ "type": "string" },
        "origin": #{ "type": "string" },
        "branch": #{ "type": "string" },
        "dirty": #{ "type": "boolean" },
        "ahead_behind": #{ "type": "string" },
        "stack": #{ "type": "string" },
        "test_cmd": #{ "type": "string" },
        "lint_cmd": #{ "type": "string" },
        "typecheck_cmd": #{ "type": "string" },
        "verify_cmd": #{ "type": "string" },
        "kind": #{ "type": "string" },
        "first_touch": #{ "type": "string" },
        "test_cmd_file": #{ "type": "string" },
        "lint_cmd_file": #{ "type": "string" },
        "typecheck_cmd_file": #{ "type": "string" },
        "verify_cmd_file": #{ "type": "string" },
        "first_touch_file": #{ "type": "string" },
        "source": #{ "type": "string" },
    },
};

let verdict_schema = #{
    "type": "object",
    "required": ["path", "test_ok", "lint_ok", "typecheck_ok", "verify_ok", "first_touch_ok", "evidence"],
    "properties": #{
        "path": #{ "type": "string" },
        "test_ok": #{ "type": "boolean" },
        "lint_ok": #{ "type": "boolean" },
        "typecheck_ok": #{ "type": "boolean" },
        "verify_ok": #{ "type": "boolean" },
        "first_touch_ok": #{ "type": "boolean" },
        "evidence": #{ "type": "string" },
    },
};

fn max_root_cap() { 12 }

fn as_str(x) {
    if x == () { return ""; }
    let t = type_of(x);
    if t == "string" { return x; }
    if t == "i64" || t == "f64" { return x.to_string(); }
    if t == "bool" {
        if x { return "true"; }
        return "false";
    }
    ""
}

fn trimmed(s) {
    if type_of(s) != "string" { return ""; }
    s.trim();
    s
}

fn normalize_dir(p) {
    let s = trimmed(p);
    while s.len() > 1 && s.sub_string(s.len() - 1, 1) == "/" {
        s = s.sub_string(0, s.len() - 1);
    }
    s
}

fn basename_of(p) {
    let s = trimmed(p);
    let last = 0;
    let i = 0;
    while i < s.len() {
        if s.sub_string(i, 1) == "/" { last = i + 1; }
        i += 1;
    }
    s.sub_string(last, s.len() - last)
}

fn path_under_root(p, root) {
    let a = normalize_dir(p);
    let b = normalize_dir(root);
    if a == "" || b == "" { return false; }
    if a == b { return true; }
    let prefix = b + "/";
    if a.len() < prefix.len() { return false; }
    a.sub_string(0, prefix.len()) == prefix
}

fn is_immediate_child_path(p, root) {
    let a = normalize_dir(p);
    let b = normalize_dir(root);
    if a == b || a == "" || b == "" { return false; }
    if !path_under_root(a, b) { return false; }
    let rest = a.sub_string(b.len() + 1, a.len() - b.len() - 1);
    if rest.len() == 0 { return false; }
    let i = 0;
    while i < rest.len() {
        if rest.sub_string(i, 1) == "/" { return false; }
        i += 1;
    }
    true
}

fn has_skipped_segment(p) {
    let s = trimmed(p);
    if s == "" { return true; }
    let i = 0;
    let n = s.len();
    let seg_start = 0;
    while i <= n {
        if i == n || s.sub_string(i, 1) == "/" {
            let seglen = i - seg_start;
            if seglen > 0 {
                let seg = s.sub_string(seg_start, seglen);
                if seg == "node_modules" || seg == ".git" || seg == ".terraform" || seg == ".." {
                    return true;
                }
            }
            seg_start = i + 1;
        }
        i += 1;
    }
    false
}

fn classify_source(s) {
    let x = trimmed(s);
    if x == "cwd" || x == "root" { return "cwd"; }
    if x == "child" || x == "immediate" { return "child"; }
    if x == "worktree" || x == "wt" { return "worktree"; }
    "other"
}

fn already_have(paths, p) {
    let needle = normalize_dir(p);
    for x in paths {
        if normalize_dir(x) == needle { return true; }
    }
    false
}

fn allowed_cmd_file(f) {
    let b = basename_of(f);
    b == "AGENTS.md" || b == "Makefile" || b == "makefile"
}

fn clip(s, n) {
    let t = sanitize_cell(s);
    if t.len() <= n { return t; }
    return t.sub_string(0, n) + "...";
}

fn sanitize_cell(s) {
    let t = as_str(s);
    t.trim();
    let out = "";
    let i = 0;
    while i < t.len() {
        let ch = t.sub_string(i, 1);
        if ch == "|" || ch == "\n" || ch == "\r" || ch == "`" {
            out += " ";
        } else {
            out += ch;
        }
        i += 1;
    }
    if out == "" { return "UNKNOWN"; }
    out
}

fn rel_path(p, root) {
    let a = normalize_dir(p);
    let b = normalize_dir(root);
    if a == b { return "."; }
    let prefix = b + "/";
    if a.len() >= prefix.len() && a.sub_string(0, prefix.len()) == prefix {
        return a.sub_string(prefix.len(), a.len() - prefix.len());
    }
    a
}

fn kind_label(k) {
    let s = trimmed(k);
    if s == "app" || s == "docs" { return s; }
    if s == "IAC" || s == "iac" { return "IAC"; }
    "unknown"
}

fn dirty_label(d) {
    if d == true { return "dirty"; }
    if d == false { return "clean"; }
    "unknown"
}

fn join_list(arr) {
    if arr.len() == 0 { return "none"; }
    let out = "";
    let i = 0;
    for x in arr {
        if i > 0 { out += ", "; }
        out += as_str(x);
        i += 1;
    }
    out
}

fn clamp_repos(n) {
    let cap = max_root_cap();
    let t = type_of(n);
    if t == "i64" {
        cap = n;
    }
    if cap < 1 { cap = 1; }
    if cap > max_root_cap() { cap = max_root_cap(); }
    cap
}

fn finalize_cmd(cmd, cmd_file, verdict_ok) {
    let c = trimmed(cmd);
    if c == "" || c == "UNKNOWN" { return "UNKNOWN"; }
    if !allowed_cmd_file(cmd_file) { return "UNKNOWN"; }
    if verdict_ok != true { return "UNKNOWN"; }
    c
}

fn forbidden_block() {
    let p = "";
    p += "READ-ONLY RUN. Do not edit, create, delete, move, or write any file in the workspace.\n";
    p += "Do not git add, commit, push, fetch, pull, checkout, switch, merge, rebase, stash, reset, or apply.\n";
    p += "Do not terraform apply/plan, ansible-playbook, packer, npm/pnpm/yarn/pip/cargo install, or install plugins.\n";
    p += "Do not run tests, linters, or formatters. Read Makefile/AGENTS.md; never execute their targets.\n";
    p += "Never read .env, *.tfvars, terraform.tfstate, *.tfstate, auth.json, or anything under secrets/.\n";
    p += "Never invent scripts, make targets, or package.json scripts. If a file is missing, that command is UNKNOWN.\n";
    p
}

fn discover_prompt(root, cap) {
    let p = forbidden_block();
    p += "Discover git roots under this workspace directory (JSON): " + json_encode(root) + "\n";
    p += "Keep at most 24 candidates so the host can cap to " + cap.to_string() + ".\n\n";
    p += "Use the terminal and directory listing. Do not answer from memory.\n";
    p += "An empty roots list is valid only after you listed immediate children and checked each one.\n\n";
    p += "Algorithm:\n";
    p += "1. CWD: run `git -C <root> rev-parse --is-inside-work-tree` and `--show-toplevel`.\n";
    p += "   If it is a work tree and toplevel equals <root>, add {path: toplevel, source: \"cwd\"}.\n";
    p += "2. Immediate children only (not recursive): list directories of <root>.\n";
    p += "   Skip a child whose name is node_modules, .git, or .terraform.\n";
    p += "   For each remaining child, run `git -C <root>/<child> rev-parse --show-toplevel`.\n";
    p += "   If toplevel equals that child directory, add {path: toplevel, source: \"child\"}.\n";
    p += "3. Worktrees: for the cwd repo (if any) and each child repo, run\n";
    p += "   `git -C <repo> worktree list --porcelain`.\n";
    p += "   Add each worktree path with source \"worktree\" when it is still under <root>.\n";
    p += "   Skip the primary worktree if it is already listed as cwd or child.\n";
    p += "4. Do not recurse looking for nested .git directories. Do not add submodules unless they\n";
    p += "   appeared as an immediate child or a worktree list entry.\n";
    p += "5. Skip any path whose segments include node_modules, .git, or .terraform.\n";
    p += "Return roots in order: cwd, then children, then worktrees. Paths must be absolute.\n";
    p
}

fn mapper_prompt(root, repo_path, source) {
    let p = forbidden_block();
    p += "Inspect exactly this git root and no other path.\n";
    p += "Workspace root (JSON): " + json_encode(root) + "\n";
    p += "Git root (JSON): " + json_encode(repo_path) + "\n";
    p += "Discovery source (JSON): " + json_encode(source) + "\n\n";
    p += "You must run tools before answering. A guess is invalid.\n\n";
    p += "Git (read-only, -C the git root; never fetch):\n";
    p += "- remote origin: `git remote get-url origin` — else origin=\"none\"\n";
    p += "- branch: `git branch --show-current` — else \"UNKNOWN\"\n";
    p += "- dirty: `git status --porcelain` non-empty => dirty true, empty => false\n";
    p += "- ahead/behind: from `git status -sb` or `git rev-list --left-right --count @{upstream}...HEAD`\n";
    p += "  Format as \"ahead N / behind M\". If upstream is missing, ahead_behind=\"unknown\".\n\n";
    p += "Stack from lockfiles in the git-root directory only (do not recurse):\n";
    p += "pnpm-lock.yaml => javascript/pnpm; package-lock.json => javascript/npm;\n";
    p += "go.mod => go; Cargo.toml => rust/cargo; requirements*.txt => python/pip.\n";
    p += "Join multiples with +. If none exist, stack=\"UNKNOWN\".\n\n";
    p += "Commands: read ONLY AGENTS.md and Makefile (or makefile) at the git root.\n";
    p += "Extract real test, lint, typecheck, and verify commands those files name.\n";
    p += "Verify each name against the file contents you read. If the file does not exist or\n";
    p += "does not name that command, the field is UNKNOWN. Never invent. Never use package.json.\n";
    p += "Set test_cmd_file/lint_cmd_file/typecheck_cmd_file/verify_cmd_file to the file you read,\n";
    p += "or empty when UNKNOWN.\n\n";
    p += "Kind: IAC if terraform/, ansible/, packer/, or *.tf; app if application/library code;\n";
    p += "docs if primarily documentation. IAC wins over app; app wins over docs. One of: app, IAC, docs.\n\n";
    p += "first_touch: one existing file a new agent should open first (prefer AGENTS.md, else Makefile,\n";
    p += "else README.md) OR one verified command. first_touch_file must exist. Do not point at secrets.\n";
    p += "Echo source as given. path must be the git root you inspected.\n";
    p
}

fn verifier_prompt(root, claim) {
    let p = forbidden_block();
    p += "Adversarially verify this repo map claim. Default every *_ok to false.\n";
    p += "Workspace root (JSON): " + json_encode(root) + "\n";
    p += "Claim (JSON): " + claim + "\n\n";
    p += "Independently inspect the git root. Use read_file/list_dir/grep on AGENTS.md and Makefile only.\n";
    p += "Do not trust the claim. Do not invent commands.\n\n";
    p += "For each of test_cmd, lint_cmd, typecheck_cmd, verify_cmd:\n";
    p += "- If the claim is UNKNOWN: set *_ok true only after you confirmed the named source file is\n";
    p += "  absent OR exists and does not name that kind of command. Otherwise *_ok false.\n";
    p += "- If the claim is a concrete command: set *_ok true only when the cited file exists, is\n";
    p += "  named AGENTS.md or Makefile, sits in this git root, and the file text actually contains\n";
    p += "  that command (a Makefile target or an explicit instruction). Otherwise *_ok false.\n";
    p += "- Commands taken from package.json, CI yaml, or README do not count.\n";
    p += "first_touch_ok true only if that file exists (read it) or the first_touch string is one of\n";
    p += "the commands you just confirmed. evidence: quote the file path and the line you saw.\n";
    p
}

if args == () {
    pause("verification", "Pass args.root — the workspace directory to map. Optional args.max_repos (1-12, default 12).");
}

let root_raw = args.root;
if root_raw == () || trimmed(as_str(root_raw)) == "" {
    pause("verification", "Pass args.root — the workspace directory to map. Optional args.max_repos (1-12, default 12).");
}

let root = normalize_dir(as_str(root_raw));
let cap = max_root_cap();
if args.max_repos != () {
    cap = clamp_repos(args.max_repos);
}

log("Mapping git roots under " + root + " (cap " + cap.to_string() + ")");

phase("Discover");
let disc = agent(discover_prompt(root, cap), #{
    label: "discover-roots",
    capability_mode: "execute",
    output_schema: discover_schema,
});

let raw_roots = [];
if disc != () && disc.success && disc.output != () && disc.output.roots != () {
    if type_of(disc.output.roots) == "array" {
        raw_roots = disc.output.roots;
    }
}

let cwd_roots = [];
let child_roots = [];
let worktree_roots = [];
let dropped = [];
let seen = [];

for item in raw_roots {
    if item == () { continue; }
    let pth = "";
    let src_raw = "";
    if type_of(item) == "map" {
        pth = as_str(item.path);
        src_raw = as_str(item.source);
    }
    let pnorm = normalize_dir(pth);
    if pnorm == "" {
        dropped.push("(empty path)");
        continue;
    }
    if !path_under_root(pnorm, root) {
        dropped.push(pnorm + " (outside root)");
        continue;
    }
    if has_skipped_segment(pnorm) {
        dropped.push(pnorm + " (skipped segment)");
        continue;
    }
    if already_have(seen, pnorm) {
        dropped.push(pnorm + " (duplicate)");
        continue;
    }
    let src = classify_source(src_raw);
    let keep = false;
    if pnorm == root {
        keep = true;
        src = "cwd";
    } else if is_immediate_child_path(pnorm, root) {
        keep = true;
        if src != "worktree" { src = "child"; }
    } else if src == "worktree" {
        keep = true;
    }
    if !keep {
        dropped.push(pnorm + " (nested non-worktree)");
        continue;
    }
    seen.push(pnorm);
    let rec = #{ path: pnorm, source: src };
    if src == "cwd" {
        cwd_roots.push(rec);
    } else if src == "child" {
        child_roots.push(rec);
    } else {
        worktree_roots.push(rec);
    }
}

let kept = [];
for r in cwd_roots { kept.push(r); }
for r in child_roots { kept.push(r); }
for r in worktree_roots { kept.push(r); }

let over_cap = [];
if kept.len() > cap {
    let i = cap;
    while i < kept.len() {
        over_cap.push(kept[i].path);
        i += 1;
    }
    let trimmed_kept = [];
    let j = 0;
    while j < cap {
        trimmed_kept.push(kept[j]);
        j += 1;
    }
    kept = trimmed_kept;
}

if dropped.len() > 0 {
    log("Dropped " + dropped.len().to_string() + " discovered paths as out of scope or duplicate");
}
if over_cap.len() > 0 {
    log("Capped at " + cap.to_string() + "; omitted " + over_cap.len().to_string() + " extra roots");
}
log("Keeping " + kept.len().to_string() + " git roots");

if kept.len() == 0 {
    phase("Report");
    let empty = "";
    empty += "# Workspace map\n\n";
    empty += "No git roots found under `" + sanitize_cell(root) + "` after checking cwd, immediate children, and worktrees.\n\n";
    empty += "| path | origin | branch | status | ahead/behind | stack | test | lint | typecheck | verify | kind | first touch |\n";
    empty += "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |\n\n";
    empty += "## Workspace summary\n";
    empty += "Mapped 0 git roots under " + root + " (cap " + cap.to_string() + ").\n";
    empty += "Safe to work in now: none — no repositories discovered.\n";
    empty += "Dirty: none.\n";
    empty += "No verified commands: none (no repos).\n";
    empty += "Stack mix: none.\n";
    empty += "Kind mix: none.\n";
    empty += "Worktrees included: none.\n";
    empty += "Read-only map; do not edit, commit, push, apply terraform, or install plugins.\n";
    if dropped.len() > 0 {
        empty += "\nDropped: " + join_list(dropped) + "\n";
    }
    let empty_path = write_scratch_file("workspace-map.md", empty);
    complete(#{ path: empty_path, report: empty, repos: [], dropped: dropped });
}

phase("Map");
let map_jobs = [];
let mi = 0;
for rec in kept {
    let lbl = "map:" + mi.to_string();
    map_jobs.push(#{
        prompt: mapper_prompt(root, rec.path, rec.source),
        label: lbl,
        capability_mode: "execute",
        output_schema: repo_schema,
    });
    mi += 1;
}
let map_results = parallel(map_jobs);

let mapped = [];
let idx = 0;
for rec in kept {
    let slot = ();
    if idx < map_results.len() { slot = map_results[idx]; }
    let row = #{
        path: rec.path,
        source: rec.source,
        origin: "UNKNOWN",
        branch: "UNKNOWN",
        dirty: (),
        ahead_behind: "unknown",
        stack: "UNKNOWN",
        test_cmd: "UNKNOWN",
        lint_cmd: "UNKNOWN",
        typecheck_cmd: "UNKNOWN",
        verify_cmd: "UNKNOWN",
        kind: "unknown",
        first_touch: "UNKNOWN",
        test_cmd_file: "",
        lint_cmd_file: "",
        typecheck_cmd_file: "",
        verify_cmd_file: "",
        first_touch_file: "",
        mapped_ok: false,
    };
    if slot != () && slot.success && slot.output != () {
        let o = slot.output;
        row.mapped_ok = true;
        if o.path != () && trimmed(as_str(o.path)) != "" {
            let claimed = normalize_dir(as_str(o.path));
            if path_under_root(claimed, root) && !has_skipped_segment(claimed) {
                row.path = claimed;
            }
        }
        if o.origin != () { row.origin = as_str(o.origin); }
        if o.branch != () { row.branch = as_str(o.branch); }
        if o.dirty == true || o.dirty == false { row.dirty = o.dirty; }
        if o.ahead_behind != () { row.ahead_behind = as_str(o.ahead_behind); }
        if o.stack != () { row.stack = as_str(o.stack); }
        if o.test_cmd != () { row.test_cmd = as_str(o.test_cmd); }
        if o.lint_cmd != () { row.lint_cmd = as_str(o.lint_cmd); }
        if o.typecheck_cmd != () { row.typecheck_cmd = as_str(o.typecheck_cmd); }
        if o.verify_cmd != () { row.verify_cmd = as_str(o.verify_cmd); }
        row.kind = kind_label(o.kind);
        if o.first_touch != () { row.first_touch = as_str(o.first_touch); }
        if o.test_cmd_file != () { row.test_cmd_file = as_str(o.test_cmd_file); }
        if o.lint_cmd_file != () { row.lint_cmd_file = as_str(o.lint_cmd_file); }
        if o.typecheck_cmd_file != () { row.typecheck_cmd_file = as_str(o.typecheck_cmd_file); }
        if o.verify_cmd_file != () { row.verify_cmd_file = as_str(o.verify_cmd_file); }
        if o.first_touch_file != () { row.first_touch_file = as_str(o.first_touch_file); }
        if o.source != () && classify_source(o.source) != "other" {
            row.source = classify_source(o.source);
        }
    }
    mapped.push(row);
    idx += 1;
}

phase("Verify");
let vjobs = [];
let vi = 0;
for row in mapped {
    let claim = json_encode(#{
        path: row.path,
        test_cmd: row.test_cmd,
        lint_cmd: row.lint_cmd,
        typecheck_cmd: row.typecheck_cmd,
        verify_cmd: row.verify_cmd,
        test_cmd_file: row.test_cmd_file,
        lint_cmd_file: row.lint_cmd_file,
        typecheck_cmd_file: row.typecheck_cmd_file,
        verify_cmd_file: row.verify_cmd_file,
        first_touch: row.first_touch,
        first_touch_file: row.first_touch_file,
        mapped_ok: row.mapped_ok,
    });
    vjobs.push(#{
        prompt: verifier_prompt(root, claim),
        label: "verify:" + vi.to_string(),
        capability_mode: "execute",
        output_schema: verdict_schema,
    });
    vi += 1;
}
let verdicts = parallel(vjobs);

let verified = [];
let vi2 = 0;
for row in mapped {
    let v = ();
    if vi2 < verdicts.len() { v = verdicts[vi2]; }
    let test_ok = false;
    let lint_ok = false;
    let typecheck_ok = false;
    let verify_ok = false;
    let touch_ok = false;
    if v != () && v.success && v.output != () {
        let vo = v.output;
        if vo.test_ok == true { test_ok = true; }
        if vo.lint_ok == true { lint_ok = true; }
        if vo.typecheck_ok == true { typecheck_ok = true; }
        if vo.verify_ok == true { verify_ok = true; }
        if vo.first_touch_ok == true { touch_ok = true; }
    }
    let test_cmd = finalize_cmd(row.test_cmd, row.test_cmd_file, test_ok);
    let lint_cmd = finalize_cmd(row.lint_cmd, row.lint_cmd_file, lint_ok);
    let typecheck_cmd = finalize_cmd(row.typecheck_cmd, row.typecheck_cmd_file, typecheck_ok);
    let verify_cmd = finalize_cmd(row.verify_cmd, row.verify_cmd_file, verify_ok);
    let first_touch = "UNKNOWN";
    if touch_ok == true {
        let ft = trimmed(row.first_touch);
        if ft != "" { first_touch = ft; }
    }
    verified.push(#{
        path: row.path,
        source: row.source,
        origin: row.origin,
        branch: row.branch,
        dirty: row.dirty,
        ahead_behind: row.ahead_behind,
        stack: row.stack,
        test_cmd: test_cmd,
        lint_cmd: lint_cmd,
        typecheck_cmd: typecheck_cmd,
        verify_cmd: verify_cmd,
        kind: row.kind,
        first_touch: first_touch,
        mapped_ok: row.mapped_ok,
    });
    vi2 += 1;
}
mapped = verified;

phase("Report");

let safe = [];
let dirty_repos = [];
let no_cmds = [];
let stacks_seen = [];
let kinds_app = 0;
let kinds_iac = 0;
let kinds_docs = 0;
let kinds_unknown = 0;
let worktrees = [];
let unknown_status = [];

for row in mapped {
    if row.source == "worktree" { worktrees.push(rel_path(row.path, root)); }
    if row.kind == "app" { kinds_app += 1; }
    else if row.kind == "IAC" { kinds_iac += 1; }
    else if row.kind == "docs" { kinds_docs += 1; }
    else { kinds_unknown += 1; }
    let st = trimmed(row.stack);
    if st != "" && st != "UNKNOWN" {
        if !already_have(stacks_seen, st) { stacks_seen.push(st); }
    }
    let rel = rel_path(row.path, root);
    if row.dirty == true { dirty_repos.push(rel); }
    else if row.dirty != false { unknown_status.push(rel); }
    let has_cmd = row.test_cmd != "UNKNOWN" || row.lint_cmd != "UNKNOWN" || row.typecheck_cmd != "UNKNOWN" || row.verify_cmd != "UNKNOWN";
    if !has_cmd { no_cmds.push(rel); }
    if row.dirty == false && has_cmd { safe.push(rel); }
}

let table = "";
table += "# Workspace map\n\n";
table += "Root: `" + sanitize_cell(root) + "` — " + mapped.len().to_string() + " git roots (cap " + cap.to_string() + ").\n\n";
table += "| path | origin | branch | status | ahead/behind | stack | test | lint | typecheck | verify | kind | first touch |\n";
table += "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |\n";
for row in mapped {
    let line = "| ";
    line += sanitize_cell(rel_path(row.path, root));
    line += " | ";
    line += clip(row.origin, 40);
    line += " | ";
    line += sanitize_cell(row.branch);
    line += " | ";
    line += dirty_label(row.dirty);
    line += " | ";
    line += sanitize_cell(row.ahead_behind);
    line += " | ";
    line += clip(row.stack, 36);
    line += " | ";
    line += sanitize_cell(row.test_cmd);
    line += " | ";
    line += sanitize_cell(row.lint_cmd);
    line += " | ";
    line += sanitize_cell(row.typecheck_cmd);
    line += " | ";
    line += sanitize_cell(row.verify_cmd);
    line += " | ";
    line += sanitize_cell(row.kind);
    line += " | ";
    line += clip(row.first_touch, 40);
    line += " |\n";
    table += line;
}

table += "\n## Workspace summary\n";
table += "Mapped " + mapped.len().to_string() + " git roots under " + root + " (cap " + cap.to_string() + "; omitted " + over_cap.len().to_string() + " over cap, dropped " + dropped.len().to_string() + " out of scope).\n";
table += "Safe to work in now: " + join_list(safe) + ".\n";
table += "Dirty: " + join_list(dirty_repos) + ".\n";
table += "No verified commands: " + join_list(no_cmds) + ".\n";
table += "Stack mix: " + join_list(stacks_seen) + ".\n";
let kind_mix = "app " + kinds_app.to_string() + ", IAC " + kinds_iac.to_string() + ", docs " + kinds_docs.to_string() + ", unknown " + kinds_unknown.to_string();
table += "Kind mix: " + kind_mix + ".\n";
table += "Worktrees included: " + join_list(worktrees) + ".\n";
table += "Read-only map; do not edit, commit, push, apply terraform, or install plugins.\n";

if unknown_status.len() > 0 {
    table += "\nStatus unknown (mapper failed or did not report dirty): " + join_list(unknown_status) + ".\n";
}
if over_cap.len() > 0 {
    table += "Omitted over cap: " + join_list(over_cap) + ".\n";
}

let report_path = write_scratch_file("workspace-map.md", table);
log("Wrote workspace map with " + mapped.len().to_string() + " rows");
complete(#{ path: report_path, report: table, repos: mapped, dropped: dropped, omitted: over_cap });
