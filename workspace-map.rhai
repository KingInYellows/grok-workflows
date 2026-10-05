let meta = #{
    name: "workspace-map",
    description: "Read-only map of a multi-repo workspace: git roots, stack, real commands, kind, and the smallest safe first touch",
    when_to_use: "Map a multi-repo workspace before changing anything. Discover git roots and worktrees, report stack and file-backed commands, and name one safe first touch per repo.",
    phases: [
        #{ title: "Discover", detail: "git roots, immediate children, and worktrees" },
        #{ title: "Map", detail: "one read-only mapper per root" },
        #{ title: "Verify", detail: "commands and cited files must exist" },
        #{ title: "Report", detail: "one table plus an 8-line summary" },
    ],
};

const HARD_CAP = 12;

let roots_schema = #{
    "type": "object", "required": ["roots"],
    "properties": #{
        "roots": #{ "type": "array", "maxItems": 24, "items": #{
            "type": "object", "required": ["path", "relpath", "source"],
            "properties": #{
                "path": #{ "type": "string" },
                "relpath": #{ "type": "string" },
                "source": #{ "type": "string" },
            },
        }},
    },
};

let repo_schema = #{
    "type": "object",
    "required": [
        "path", "origin", "branch", "dirty", "ahead_behind",
        "language", "package_manager", "lockfiles",
        "test_command", "lint_command", "typecheck_command", "verify_command",
        "kind", "kind_evidence_file",
        "smallest_safe_change", "smallest_safe_file",
    ],
    "properties": #{
        "path": #{ "type": "string" },
        "origin": #{ "type": "string" },
        "branch": #{ "type": "string" },
        "dirty": #{ "type": "string" },
        "ahead_behind": #{ "type": "string" },
        "language": #{ "type": "string" },
        "package_manager": #{ "type": "string" },
        "lockfiles": #{ "type": "array", "maxItems": 8, "items": #{ "type": "string" } },
        "test_command": #{ "type": "string" },
        "lint_command": #{ "type": "string" },
        "typecheck_command": #{ "type": "string" },
        "verify_command": #{ "type": "string" },
        "command_source_file": #{ "type": "string" },
        "kind": #{ "type": "string" },
        "kind_evidence_file": #{ "type": "string" },
        "smallest_safe_change": #{ "type": "string" },
        "smallest_safe_file": #{ "type": "string" },
    },
};

let verdict_schema = #{
    "type": "object",
    "required": [
        "inspected", "evidence",
        "test_command", "lint_command", "typecheck_command", "verify_command",
        "kind_ok", "smallest_ok", "lockfiles_ok",
    ],
    "properties": #{
        "inspected": #{ "type": "boolean" },
        "evidence": #{ "type": "string" },
        "test_command": #{ "type": "string" },
        "lint_command": #{ "type": "string" },
        "typecheck_command": #{ "type": "string" },
        "verify_command": #{ "type": "string" },
        "kind_ok": #{ "type": "boolean" },
        "smallest_ok": #{ "type": "boolean" },
        "lockfiles_ok": #{ "type": "boolean" },
    },
};

fn trimmed(s) {
    if type_of(s) != "string" { return ""; }
    s.trim();
    s
}

fn as_string(x) {
    if type_of(x) == "string" { trimmed(x) } else { "" }
}

fn is_map(x) {
    x != () && type_of(x) == "map"
}

fn as_array(x) {
    if x != () && type_of(x) == "array" { x } else { [] }
}

fn ends_with(s, suffix) {
    let a = as_string(s);
    let b = as_string(suffix);
    if b == "" { return true; }
    if a.len() < b.len() { return false; }
    a.sub_string(a.len() - b.len(), b.len()) == b
}

fn strip_dot_slash(p) {
    let s = as_string(p);
    if s.len() >= 2 && s.sub_string(0, 2) == "./" {
        return s.sub_string(2, s.len() - 2);
    }
    s
}

fn strip_trailing_slash(p) {
    let s = as_string(p);
    while s.len() > 1 && ends_with(s, "/") {
        s = s.sub_string(0, s.len() - 1);
    }
    s
}

fn norm_path(p) {
    strip_trailing_slash(strip_dot_slash(p))
}

fn has_dotdot(s) {
    let p = as_string(s);
    if p == ".." { return true; }
    if p.len() >= 3 && p.sub_string(0, 3) == "../" { return true; }
    if p.len() >= 3 && ends_with(p, "/..") { return true; }
    let i = 0;
    while i + 4 <= p.len() {
        if p.sub_string(i, 4) == "/../" { return true; }
        i += 1;
    }
    false
}

fn forbidden_path(p) {
    let s = norm_path(p);
    if s == "" { return true; }
    if has_dotdot(s) { return true; }
    if s == "node_modules" || s == ".git" || s == ".terraform" { return true; }
    if s.contains("/node_modules/") { return true; }
    if ends_with(s, "/node_modules") { return true; }
    if s.contains("/.terraform/") { return true; }
    if ends_with(s, "/.terraform") { return true; }
    if s.contains("/.git/") { return true; }
    if ends_with(s, "/.git") { return true; }
    false
}

fn already_seen(keys, k) {
    for x in keys {
        if x == k { return true; }
    }
    false
}

fn last_index_of(s, needle) {
    let n = as_string(s);
    let k = as_string(needle);
    if k == "" { return -1; }
    let found = -1;
    let i = 0;
    while i + k.len() <= n.len() {
        if n.sub_string(i, k.len()) == k { found = i; }
        i += 1;
    }
    found
}

fn last_segment(p) {
    let s = norm_path(p);
    let slash = last_index_of(s, "/");
    if slash < 0 { return s; }
    if slash + 1 >= s.len() { return s; }
    s.sub_string(slash + 1, s.len() - slash - 1)
}

fn drop_last_segment(p) {
    let s = norm_path(p);
    let slash = last_index_of(s, "/");
    if slash <= 0 { return ""; }
    s.sub_string(0, slash)
}

fn is_single_segment(p) {
    let s = norm_path(p);
    if s == "" || s == "." || s == ".." { return false; }
    !s.contains("/")
}

fn display_path(path, relpath) {
    let rel = norm_path(relpath);
    if rel != "" && rel != "." { return rel; }
    let p = norm_path(path);
    if p == "" { return "."; }
    p
}

fn short_origin(url) {
    let s = as_string(url);
    if s == "" || s == "unknown" || s == "UNKNOWN" { return "unknown"; }
    let colon = last_index_of(s, ":");
    if colon >= 0 {
        let after = s.sub_string(colon + 1, s.len() - colon - 1);
        if after.contains("/") && colon > 6 {
            return after;
        }
    }
    let a = last_segment(s);
    let parent = last_segment(drop_last_segment(s));
    if parent == "" || parent == "github.com" || parent == "www.github.com" { return a; }
    parent + "/" + a
}

fn norm_dirty(x) {
    let s = as_string(x);
    if s == "dirty" || s == "clean" || s == "unknown" { return s; }
    if s == "" { return "unknown"; }
    s
}

fn norm_ahead(x) {
    let s = as_string(x);
    if s == "" { return "unknown"; }
    if s == "even" { return "even"; }
    if s == "ahead 0, behind 0" { return "even"; }
    if s == "ahead 0 behind 0" { return "even"; }
    if s == "0 0" { return "even"; }
    if s == "0\t0" { return "even"; }
    s
}

fn cmd_or_unknown(x) {
    let s = as_string(x);
    if s == "" { return "UNKNOWN"; }
    s
}

fn allowed_lockfile(name) {
    let n = as_string(name);
    if n == "" { return false; }
    if has_dotdot(n) { return false; }
    if n.contains("/") { return false; }
    if n == "pnpm-lock.yaml" { return true; }
    if n == "package-lock.json" { return true; }
    if n == "go.mod" { return true; }
    if n == "Cargo.toml" { return true; }
    if n == "Pipfile" { return true; }
    if n == "Pipfile.lock" { return true; }
    if n == "pyproject.toml" { return true; }
    if n == "poetry.lock" { return true; }
    if n == "requirements.txt" { return true; }
    if n.len() >= 15 && n.sub_string(0, 12) == "requirements" && ends_with(n, ".txt") { return true; }
    false
}

fn join_names(items) {
    let out = "";
    for item in items {
        if out != "" { out += ", "; }
        out += "`" + item + "`";
    }
    if out == "" { return "(none)"; }
    out
}

fn clamp_max_repos(raw, fallback, hi) {
    let n = fallback;
    if raw == () { return n; }
    let t = type_of(raw);
    if t == "i64" || t == "i32" || t == "int" || t == "u64" {
        n = raw;
    }
    if n < 1 { n = 1; }
    if n > hi { n = hi; }
    n
}

fn is_self_root(relpath, path, root) {
    let rel = norm_path(relpath);
    let p = norm_path(path);
    let r = norm_path(root);
    if rel == "." { return true; }
    if p == r { return true; }
    if (r == "." || r == "") && (p == "." || p == "") { return true; }
    false
}

fn take_bucket(bucket, roots, seen, max_repos, dropped_dup, dropped_cap) {
    for rec in bucket {
        if roots.len() >= max_repos {
            dropped_cap += 1;
            continue;
        }
        let keys = [rec.path];
        if rec.relpath != "" && rec.relpath != "." {
            keys.push("rel:" + rec.relpath);
        }
        let dup = false;
        for k in keys {
            if already_seen(seen, k) { dup = true; }
        }
        if dup {
            dropped_dup += 1;
            continue;
        }
        for k in keys { seen.push(k); }
        roots.push(rec);
    }
    #{ roots: roots, seen: seen, dropped_dup: dropped_dup, dropped_cap: dropped_cap }
}

let root = ".";
let max_repos = HARD_CAP;
if args != () {
    if args.root != () && type_of(args.root) == "string" {
        root = args.root;
        root.trim();
        if root == "" { root = "."; }
    }
    if args.max_repos != () {
        max_repos = clamp_max_repos(args.max_repos, HARD_CAP, HARD_CAP);
    }
}
if max_repos < 1 { max_repos = 1; }
if max_repos > HARD_CAP { max_repos = HARD_CAP; }

let root_json = json_encode(root);
let max_json = json_encode(max_repos);

phase("Discover");
log("Discovering git roots under " + root + " (map cap " + max_repos.to_string() + ")");

let discover_prompt = "";
discover_prompt += "Map git repository roots in a workspace. This is READ-ONLY observation.\n";
discover_prompt += "Do not edit, commit, push, checkout, reset, stash, rebase, apply terraform, install packages, or install plugins.\n";
discover_prompt += "Never read, open, or grep: .env, *.tfvars, terraform.tfstate, auth.json, secrets/, or any file under a secrets/ directory.\n\n";
discover_prompt += "Workspace root to scan (JSON): " + root_json + "\n";
discover_prompt += "Return at most 24 roots. A later filter maps at most " + max_json + ", preferring self and immediate children over extra worktrees.\n\n";
discover_prompt += "Required steps — use tools; do not answer from memory:\n";
discover_prompt += "1. list_dir the workspace root.\n";
discover_prompt += "2. If the workspace root itself is a git repo (`.git` file/dir or `git -C <root> rev-parse --is-inside-work-tree`), include it with source \"self\" and relpath \".\".\n";
discover_prompt += "3. For every IMMEDIATE child directory only, check for `.git`. Skip names node_modules, .git, .terraform. Do not recurse into those, and do not report nested repos inside them. Include each immediate child git repo with source \"child\" and relpath set to that single directory name (example: \"example\"). path may be absolute; relpath must still be the single child name with no slash.\n";
discover_prompt += "4. For the workspace root (if a repo) and each accepted child, run `git -C <path> worktree list --porcelain` if allowed. Include EXTRA worktrees only (skip a worktree whose path is already the self or child main checkout) with source \"worktree\". relpath is the path relative to the workspace root when the worktree is inside it (example: \".worktrees/botfix-ts1\"); use empty relpath when the worktree is outside the workspace.\n";
discover_prompt += "5. If shell git is blocked, fall back to list_dir of `.worktrees` and `.git` files. Still skip node_modules, .git, .terraform.\n\n";
discover_prompt += "Allowed shell: git rev-parse, git worktree list, test/ls for `.git` existence. Forbidden: git add/commit/push/checkout/reset/stash/rebase/clean, terraform, npm/pnpm/pip/cargo/pipenv install, writes, rm.\n\n";
discover_prompt += "Return {path, relpath, source}. path is the working tree (prefer `git rev-parse --show-toplevel`, not the .git dir). source is exactly one of: self, child, worktree.\n";
discover_prompt += "relpath is required: \".\" for self, a single path segment for child, workspace-relative or empty for worktree.\n";
discover_prompt += "Do not invent paths. Every path must come from list_dir or git worktree list.\n";
discover_prompt += "List self and children first, then extra worktrees. An empty list is valid only after you listed the workspace root and checked for `.git` in it and in immediate children.";

let located = agent(discover_prompt, #{
    label: "discover",
    capability_mode: "execute",
    output_schema: roots_schema,
});

let raw_roots = [];
if located != () && located.success && is_map(located.output) {
    raw_roots = as_array(located.output.roots);
}
log("Discoverer returned " + raw_roots.len().to_string() + " raw roots");

let bucket_self = [];
let bucket_child = [];
let bucket_wt = [];
let dropped_scope = 0;
for item in raw_roots {
    if !is_map(item) {
        dropped_scope += 1;
        continue;
    }
    let p = norm_path(item.path);
    let rel = norm_path(item.relpath);
    let src = as_string(item.source);
    if forbidden_path(p) {
        log("drop forbidden path: " + p);
        dropped_scope += 1;
        continue;
    }
    if rel != "" && forbidden_path(rel) {
        log("drop forbidden relpath: " + rel);
        dropped_scope += 1;
        continue;
    }
    let rec = #{ path: p, relpath: rel, source: src };
    if src == "self" {
        if is_self_root(rel, p, root) {
            bucket_self.push(rec);
        } else {
            log("drop out-of-scope self: " + p);
            dropped_scope += 1;
        }
    } else if src == "child" {
        if is_single_segment(rel) {
            bucket_child.push(rec);
        } else {
            log("drop child without single-segment relpath: " + p + " relpath=" + rel);
            dropped_scope += 1;
        }
    } else if src == "worktree" {
        bucket_wt.push(rec);
    } else {
        log("drop unknown source: " + src + " " + p);
        dropped_scope += 1;
    }
}

let roots = [];
let seen = [];
let dropped_dup = 0;
let dropped_cap = 0;

let t1 = take_bucket(bucket_self, roots, seen, max_repos, dropped_dup, dropped_cap);
roots = t1.roots;
seen = t1.seen;
dropped_dup = t1.dropped_dup;
dropped_cap = t1.dropped_cap;
let t2 = take_bucket(bucket_child, roots, seen, max_repos, dropped_dup, dropped_cap);
roots = t2.roots;
seen = t2.seen;
dropped_dup = t2.dropped_dup;
dropped_cap = t2.dropped_cap;
let t3 = take_bucket(bucket_wt, roots, seen, max_repos, dropped_dup, dropped_cap);
roots = t3.roots;
seen = t3.seen;
dropped_dup = t3.dropped_dup;
dropped_cap = t3.dropped_cap;

if dropped_scope > 0 { log("Dropped " + dropped_scope.to_string() + " out-of-scope or malformed roots"); }
if dropped_dup > 0 { log("Dropped " + dropped_dup.to_string() + " duplicate roots"); }
if dropped_cap > 0 { log("Dropped " + dropped_cap.to_string() + " roots over cap " + max_repos.to_string()); }
log("Keeping " + roots.len().to_string() + " roots to map (self " + bucket_self.len().to_string() + ", child " + bucket_child.len().to_string() + ", worktree " + bucket_wt.len().to_string() + ")");

phase("Map");
let map_jobs = [];
let mi = 0;
for repo in roots {
    let path_json = json_encode(repo.path);
    let mp = "";
    mp += "Map ONE git working tree. This is READ-ONLY observation of that tree only.\n";
    mp += "Do not edit, commit, push, checkout, reset, stash, rebase, apply terraform, install packages, or install plugins.\n";
    mp += "Never read, open, or grep: .env, *.tfvars, terraform.tfstate, auth.json, secrets/, or any file under a secrets/ directory.\n";
    mp += "Do not wander into sibling repos. Stay inside this working tree.\n\n";
    mp += "Working tree path (JSON): " + path_json + "\n\n";
    mp += "Required steps — use tools; do not answer from memory:\n";
    mp += "1. Confirm the path exists (list_dir). If it does not, still return the schema with UNKNOWN/empty fields and dirty \"unknown\".\n";
    mp += "2. Git identity. Prefer these read-only commands if the sandbox allows:\n";
    mp += "   - git -C <path> remote get-url origin\n";
    mp += "   - git -C <path> branch --show-current\n";
    mp += "   - git -C <path> status --porcelain\n";
    mp += "   - git -C <path> status -sb\n";
    mp += "   - git -C <path> rev-list --left-right --count @{upstream}...HEAD\n";
    mp += "   If porcelain output is empty, dirty is \"clean\"; if any lines, dirty is \"dirty\". ";
    mp += "   ahead_behind is \"even\" when both sides are 0, otherwise \"ahead N\" / \"behind N\" / \"ahead N, behind M\". If unknown, \"unknown\".\n";
    mp += "   If shell is blocked, read <path>/.git/HEAD and <path>/.git/config (or the gitdir from a `.git` file) for branch and origin. dirty and ahead_behind then \"unknown\".\n";
    mp += "   origin is the remote URL or \"unknown\". branch is the current branch or \"HEAD\" if detached, or \"unknown\".\n";
    mp += "3. Stack from FILES that EXIST at the working tree root (list_dir; files only, never a directory named requirements):\n";
    mp += "   - pnpm-lock.yaml → javascript/typescript + pnpm\n";
    mp += "   - package-lock.json → javascript/typescript + npm\n";
    mp += "   - go.mod → go + go modules\n";
    mp += "   - Cargo.toml → rust + cargo\n";
    mp += "   - requirements.txt or other requirements*.txt file → python + pip\n";
    mp += "   - Pipfile or Pipfile.lock → python + pipenv\n";
    mp += "   - pyproject.toml or poetry.lock → python + poetry/uv\n";
    mp += "   lockfiles is the array of those filenames you actually saw. If several match, join language/package_manager with \" + \". ";
    mp += "   If none, language and package_manager are UNKNOWN.\n";
    mp += "4. Commands ONLY from AGENTS.md or Makefile at the working tree root. ";
    mp += "   Read those files if they exist. Do not use package.json, CI, README, justfile, or tox as command sources.\n";
    mp += "   Extract exact invocations for purposes test, lint, typecheck, verify. If a purpose is not named in those files, the field is UNKNOWN.\n";
    mp += "   Never invent scripts. Copy the command text as written. command_source_file is the file you copied from, or empty if all UNKNOWN.\n";
    mp += "5. Kind: app, iac, or docs. Pick the primary one.\n";
    mp += "   - app: application source (package.json, go.mod, Cargo.toml, pyproject, Pipfile, src/, backend/, frontend/)\n";
    mp += "   - iac: Terraform/Pulumi/CDK (*.tf, terragrunt). Do not open tfvars or terraform.tfstate.\n";
    mp += "   - docs: primarily markdown/docs with little or no app/IAC code\n";
    mp += "   kind_evidence_file is a file you opened that justifies the kind.\n";
    mp += "6. Smallest safe change: ONE existing file a new agent should touch first. ";
    mp += "   Prefer a test or docs file over production and over IAC apply. smallest_safe_file must exist (you listed or read it) and should be relative to this working tree. ";
    mp += "   smallest_safe_change is one short sentence naming that file.\n\n";
    mp += "Allowed shell: only the git read commands above plus listing files. Forbidden: any write, install, terraform apply, plugin install.\n";
    mp += "Output the schema. Use UNKNOWN (uppercase) for missing command/stack fields rather than guessing.";
    map_jobs.push(#{
        prompt: mp,
        label: "map:" + mi.to_string(),
        capability_mode: "execute",
        output_schema: repo_schema,
    });
    mi += 1;
}

let map_results = [];
if map_jobs.len() > 0 {
    log("Mapping " + map_jobs.len().to_string() + " roots in parallel");
    map_results = parallel(map_jobs);
} else {
    log("No roots to map");
}

let mapped = [];
let map_i = 0;
for repo in roots {
    let row = #{
        path: repo.path,
        relpath: repo.relpath,
        source: repo.source,
        origin: "unknown",
        branch: "unknown",
        dirty: "unknown",
        ahead_behind: "unknown",
        language: "UNKNOWN",
        package_manager: "UNKNOWN",
        lockfiles: [],
        test_command: "UNKNOWN",
        lint_command: "UNKNOWN",
        typecheck_command: "UNKNOWN",
        verify_command: "UNKNOWN",
        command_source_file: "",
        kind: "unknown",
        kind_evidence_file: "",
        smallest_safe_change: "UNKNOWN",
        smallest_safe_file: "",
        mapped_ok: false,
    };
    let r = ();
    if map_i < map_results.len() { r = map_results[map_i]; }
    if r != () && r.success && is_map(r.output) {
        let o = r.output;
        row.origin = cmd_or_unknown(o.origin);
        row.branch = cmd_or_unknown(o.branch);
        row.dirty = norm_dirty(o.dirty);
        row.ahead_behind = norm_ahead(o.ahead_behind);
        row.language = cmd_or_unknown(o.language);
        row.package_manager = cmd_or_unknown(o.package_manager);
        let locks = [];
        for lf in as_array(o.lockfiles) {
            let name = as_string(lf);
            if allowed_lockfile(name) { locks.push(name); }
        }
        row.lockfiles = locks;
        row.test_command = cmd_or_unknown(o.test_command);
        row.lint_command = cmd_or_unknown(o.lint_command);
        row.typecheck_command = cmd_or_unknown(o.typecheck_command);
        row.verify_command = cmd_or_unknown(o.verify_command);
        row.command_source_file = as_string(o.command_source_file);
        let kind = as_string(o.kind);
        if kind == "app" || kind == "iac" || kind == "docs" {
            row.kind = kind;
        } else if kind != "" {
            row.kind = kind;
        }
        row.kind_evidence_file = as_string(o.kind_evidence_file);
        row.smallest_safe_change = cmd_or_unknown(o.smallest_safe_change);
        row.smallest_safe_file = as_string(o.smallest_safe_file);
        row.mapped_ok = true;
    } else {
        log("mapper produced no usable output for " + repo.path);
    }
    mapped.push(row);
    map_i += 1;
}

phase("Verify");
let vjobs = [];
let vi = 0;
for row in mapped {
    let payload = #{
        path: row.path,
        lockfiles: row.lockfiles,
        test_command: row.test_command,
        lint_command: row.lint_command,
        typecheck_command: row.typecheck_command,
        verify_command: row.verify_command,
        command_source_file: row.command_source_file,
        kind: row.kind,
        kind_evidence_file: row.kind_evidence_file,
        smallest_safe_change: row.smallest_safe_change,
        smallest_safe_file: row.smallest_safe_file,
    };
    let encoded = json_encode(payload);
    let vp = "";
    vp += "Adversarially verify a workspace-map row by opening files yourself. Fail closed.\n";
    vp += "Use only read-only tools: list_dir, read_file, grep. Do not write. Do not run installs, tests, terraform, or git mutations.\n";
    vp += "Never read, open, or grep: .env, *.tfvars, terraform.tfstate, auth.json, secrets/, or any file under secrets/.\n\n";
    vp += "Claim JSON:\n" + encoded + "\n\n";
    vp += "Required checks:\n";
    vp += "1. list_dir the path. If it does not exist, set inspected=false, all commands UNKNOWN, kind_ok=false, smallest_ok=false, lockfiles_ok=false, and explain in evidence.\n";
    vp += "2. Commands: ONLY AGENTS.md and Makefile (at the working tree root) count. Read them if they exist. ";
    vp += "For each of test, lint, typecheck, verify: if the mapper's command is not UNKNOWN, set that field to the same string ONLY if you quote a matching line in AGENTS.md or Makefile. ";
    vp += "Otherwise set it to UNKNOWN. Never invent a script from package.json, CI, README, or memory. ";
    vp += "If both files are missing, all four are UNKNOWN and that is correct.\n";
    vp += "3. lockfiles_ok=true only if every listed lockfile name exists as a FILE in the working tree root (list_dir). Empty list is ok (lockfiles_ok=true after you listed the root and saw none of the expected names). A directory named requirements does not count.\n";
    vp += "4. kind_ok=true only if kind_evidence_file exists and fairly supports app, iac, or docs. You may list_dir; do not open tfvars or state.\n";
    vp += "5. smallest_ok=true only if smallest_safe_file exists (read_file or list_dir succeeded, relative to the working tree or as given) and the proposed first touch is a small, reversible file.\n";
    vp += "inspected=true only if you actually listed the path. evidence must quote filenames or short excerpts you saw.\n";
    vp += "Default kind_ok/smallest_ok/lockfiles_ok to false when evidence is missing.";
    vjobs.push(#{
        prompt: vp,
        label: "verify:" + vi.to_string(),
        capability_mode: "read-only",
        output_schema: verdict_schema,
    });
    vi += 1;
}

let verdicts = [];
if vjobs.len() > 0 {
    log("Verifying " + vjobs.len().to_string() + " mapped roots against files");
    verdicts = parallel(vjobs);
} else {
    log("No mapped roots to verify");
}

let verified = [];
let vindex = 0;
let n_verified = 0;
for row in mapped {
    let out = #{
        path: row.path,
        relpath: row.relpath,
        source: row.source,
        origin: row.origin,
        branch: row.branch,
        dirty: row.dirty,
        ahead_behind: row.ahead_behind,
        language: row.language,
        package_manager: row.package_manager,
        lockfiles: row.lockfiles,
        test_command: "UNKNOWN",
        lint_command: "UNKNOWN",
        typecheck_command: "UNKNOWN",
        verify_command: "UNKNOWN",
        kind: "unknown",
        smallest_safe_change: "UNKNOWN",
        smallest_safe_file: "",
        inspected: false,
        label: display_path(row.path, row.relpath),
    };
    let v = ();
    if vindex < verdicts.len() { v = verdicts[vindex]; }
    let ok = false;
    if v != () && v.success && is_map(v.output) {
        if v.output.inspected == true && as_string(v.output.evidence) != "" {
            ok = true;
        }
    }
    if ok {
        n_verified += 1;
        let vo = v.output;
        out.inspected = true;
        out.test_command = cmd_or_unknown(vo.test_command);
        out.lint_command = cmd_or_unknown(vo.lint_command);
        out.typecheck_command = cmd_or_unknown(vo.typecheck_command);
        out.verify_command = cmd_or_unknown(vo.verify_command);
        if vo.lockfiles_ok != true {
            out.language = "UNKNOWN";
            out.package_manager = "UNKNOWN";
            out.lockfiles = [];
        }
        if vo.kind_ok == true {
            out.kind = row.kind;
        }
        if vo.smallest_ok == true {
            out.smallest_safe_change = row.smallest_safe_change;
            out.smallest_safe_file = row.smallest_safe_file;
        }
    } else {
        log("fail-closed unverified row: " + row.path);
    }
    verified.push(out);
    vindex += 1;
}
log(n_verified.to_string() + "/" + mapped.len().to_string() + " roots survived file-backed verification");

phase("Report");

let clean = [];
let dirty_list = [];
let unknown_dirty = [];
let no_commands = [];
let n_app = 0;
let n_iac = 0;
let n_docs = 0;
let n_kind_unknown = 0;
let n_worktree = 0;
let n_child = 0;
let n_self = 0;
for row in verified {
    if row.source == "worktree" { n_worktree += 1; }
    else if row.source == "child" { n_child += 1; }
    else if row.source == "self" { n_self += 1; }
    if row.dirty == "clean" { clean.push(row.label); }
    else if row.dirty == "dirty" { dirty_list.push(row.label); }
    else { unknown_dirty.push(row.label); }
    if row.test_command == "UNKNOWN" && row.lint_command == "UNKNOWN" && row.typecheck_command == "UNKNOWN" && row.verify_command == "UNKNOWN" {
        no_commands.push(row.label);
    }
    if row.kind == "app" { n_app += 1; }
    else if row.kind == "iac" { n_iac += 1; }
    else if row.kind == "docs" { n_docs += 1; }
    else { n_kind_unknown += 1; }
}

let md = "";
md += "# Workspace map\n\n";
md += "Read-only scan of `" + root + "` (cap " + max_repos.to_string() + "). ";
md += "Commands are shown only when copied from `AGENTS.md` or `Makefile` and re-read by a verifier. ";
md += "Missing purposes are `UNKNOWN`. Git identity is mapper-reported. ";
md += "Main checkouts are listed before extra worktrees.\n\n";

md += "## Repos\n\n";
md += "| Path | Origin | Branch | Dirty | Ahead/behind | Stack | Kind | test | lint | typecheck | verify | First touch |\n";
md += "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |\n";
if verified.len() == 0 {
    md += "| _none_ | | | | | | | | | | | |\n";
} else {
    for row in verified {
        let stack = row.language + "/" + row.package_manager;
        let first = row.smallest_safe_file;
        if first == "" { first = row.smallest_safe_change; }
        md += "| `" + row.label + "` ";
        md += "| `" + short_origin(row.origin) + "` ";
        md += "| `" + row.branch + "` ";
        md += "| " + row.dirty + " ";
        md += "| " + row.ahead_behind + " ";
        md += "| " + stack + " ";
        md += "| " + row.kind + " ";
        md += "| `" + row.test_command + "` ";
        md += "| `" + row.lint_command + "` ";
        md += "| `" + row.typecheck_command + "` ";
        md += "| `" + row.verify_command + "` ";
        md += "| `" + first + "` |\n";
    }
}
md += "\n";

md += "## Workspace summary\n\n";
let line1 = "1. Workspace root `" + root + "`; mapped " + verified.len().to_string() + " git roots (self " + n_self.to_string() + ", child " + n_child.to_string() + ", worktree " + n_worktree.to_string() + "; discoverer raw " + raw_roots.len().to_string() + ").";
let line2 = "2. Safe to work in now (clean working tree): " + join_names(clean) + ".";
let line3 = "3. Dirty working trees: " + join_names(dirty_list) + ".";
let line4 = "4. Dirty state unknown: " + join_names(unknown_dirty) + ".";
let line5 = "5. Share no commands (test/lint/typecheck/verify all UNKNOWN): " + join_names(no_commands) + ".";
let line6 = "6. Kinds — app " + n_app.to_string() + ", iac " + n_iac.to_string() + ", docs " + n_docs.to_string() + ", unknown " + n_kind_unknown.to_string() + ".";
let line7 = "7. Dropped before map: scope " + dropped_scope.to_string() + ", dup " + dropped_dup.to_string() + ", cap " + dropped_cap.to_string() + " (children kept before extra worktrees).";
let line8 = "8. File-backed verification kept " + n_verified.to_string() + "/" + mapped.len().to_string() + " roots; commands never invented; secrets/tfvars/state unread.";
md += line1 + "\n";
md += line2 + "\n";
md += line3 + "\n";
md += line4 + "\n";
md += line5 + "\n";
md += line6 + "\n";
md += line7 + "\n";
md += line8 + "\n";

md += "\n## How this was produced\n\n";
md += "A discoverer listed the workspace root, immediate child git repos, and extra `git worktree list` entries, each with a workspace-relative `relpath`. ";
md += "The script keeps self, then children (single-segment relpath), then worktrees; skips node_modules/.git/.terraform; dedupes by path and relpath; and caps at " + max_repos.to_string() + ". ";
md += "Each kept root was mapped in parallel, then a read-only verifier re-opened AGENTS.md/Makefile and cited files. ";
md += "Unverified command, kind, and first-touch claims were reset to UNKNOWN. ";
md += "This workflow does not edit, commit, push, apply terraform, or install plugins.\n";

let report_path = write_scratch_file("report.md", md);
complete(#{
    path: report_path,
    report: md,
    root: root,
    max_repos: max_repos,
    roots: verified.len(),
    verified: n_verified,
    dropped_scope: dropped_scope,
    dropped_dup: dropped_dup,
    dropped_cap: dropped_cap,
    clean: clean,
    dirty: dirty_list,
    no_commands: no_commands,
});
