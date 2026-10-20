# grok-workflows

Personal library of [Grok Build](https://x.ai/cli) workflow files (`.rhai`).

Grok loads user-level workflows from real files under `${GROK_HOME:-$HOME/.grok}/workflows/` (not a symlink). This git repo is the source of truth. After a pull, run the sync script to copy workflows and their bundled support helpers into the chosen Grok home.

## Workflows

| Slash command | What it does |
| --- | --- |
| `/branch-review` | Read-only review of `origin/main...HEAD` (or another range): one reviewer per changed file, then an independent verifier per finding |
| `/class-audit` | Audit one defect class: scan in parallel, adversarially verify each hit, keep only file-backed confirmed instances |
| `/dependabot-pr-triage` | Read-only triage of open Dependabot (and optional Renovate) PRs: MERGE / HOLD / REJECT. Never merges, approves, or comments |
| `/docs-refresh` | Evidence-based documentation reconciliation for one Git repository |
| `/export-workflows` | Read Grok workflows and emit a host-agnostic universal template |
| `/goal-execute` | Implement `docs/goals/GOAL_NEXT.md`, commit when the terminal allows it, then accept that commit |
| `/goal-planning` | One-shot meta-planner that writes exactly two `docs/goals` files. The companion is `/goal-execute` |
| `/graphite-pr-review` | Review one Graphite PR, refute findings, plan repairs, then optionally commit and submit |
| `/graphite-stack-merge` | Land a Graphite stack via Graphite merge or merge-when-ready. Never uses `gh pr merge` |
| `/graphite-stack-review` | Review and remediate a Graphite PR stack bottom-up while monitoring CI and review feedback |
| `/him-to-implement` | Universal HIM audit: prove failure points with real tests, write codex + handoff |
| `/implement-approved-plan` | Implement an approved plan in an isolated worktree, run tests after, and stop without applying if tests fail |
| `/implement-from-plan` | Read source files, write a step-by-step process file, implement from it, then test and fix |
| `/linear-cycle-deliver` | Plan and, when apply is true, TDD-implement the current Linear cycle as Graphite PRs |
| `/linear-organize` | Health pass for the current git checkout. The Linear team matches the origin repository name, or `args.team` |
| `/multi-track-goal-plan` | Review the repo and open issues, pick the next multi-area goal, and write the file that launches `/multi-track-plan`. Does not implement |
| `/multi-track-plan` | Read a multi-track goal and write the source plan that launches `/multi-track-ship`. Does not implement |
| `/multi-track-ship` | Multi-track ship: implement tracks sequentially in one shared worktree, then run shared verification; diagnosis can run in parallel |
| `/preflight` | Universal pre-commit/pre-PR gate: map the change set, multi-dimension review |
| `/preflight-gate` | Read-only pre-commit gate: review the diff, audit tests from `AGENTS.md`, scan for secrets, then SHIP or BLOCK |
| `/repo-map` | Read-only map of repo layout, real test/lint commands, and the smallest safe change |
| `/search-and-destroy` | AFK opportunistic improvement: scout bugs, polish, and half-done work |
| `/ship-next-issue` | Pick the next open Linear issue (current cycle, then the rest of the team), implement it, review it, and submit one Graphite PR. Unrelated tracked changes stay unstaged. Never merges |
| `/tech-debt-scan` | Scan one git root for technical debt and overwrite `TECH_DEBT.md` with a verified remediation plan |
| `/workspace-map` | Read-only map of git roots, stacks, and verified commands in a multi-repo workspace |

## Prerequisites and layout

- Grok Build with workflow support. This repair was statically checked against 1.0.52 host behavior; that is not an end-to-end execution certification.
- Node.js 18+ for the bundled Graphite helper; Git, GitHub CLI (`gh`), and Graphite CLI (`gt`) on PATH for Graphite workflows. Authenticate `gh` and `gt` yourself before a live run. The installer does not install binaries or change authentication.
- Project-specific test tools and any requested MCP integrations (for example Linear) must also be available.

The clone can live anywhere. Both installers honor `GROK_HOME`, falling back to the current user's `.grok` directory. They install:

```text
<Grok home>/workflows/*.rhai
<Grok home>/skills/<name>/
<Grok home>/workflow-support/graphite-stack-review/cli.mjs
<Grok home>/workflow-support/graphite-stack-review/lib.mjs
```

The four Graphite helper consumers use a shell-neutral Node launcher, resolving `GROK_HOME` or Node's home directory at execution time. Paths containing spaces are passed as arguments, never interpolated into a shell command. Run Grok with the same `GROK_HOME` used to install. `GRAPHITE_STACK_REVIEW_HOME` separately overrides helper checkpoint/lock storage; it does not select the installed CLI. Without that override, state also follows `GROK_HOME`.

Do not symlink the user workflow directory or the user skills directory to this clone. Project-scoped `.grok/workflows/`, explicit workflow paths, and inline scripts are other supported launch mechanisms; these scripts install user-level copies only. Skill files in this repo live in `skills/<name>/`, not `.grok/skills/`. A `[skills]` table in a project `.grok/config.toml` does not load.

## Sync repo → Grok config

From a Bash shell in this clone:

```bash
./sync-workflows.sh                  # current user's Grok home only
./sync-workflows.sh --dry-run        # preview without writing
GROK_HOME="/path/custom grok" ./sync-workflows.sh
./sync-workflows.sh --destination "/mnt/c/Users/YourName/.grok"
./sync-workflows.sh --prune          # remove obsolete destination .rhai files only
./sync-workflows.sh --prune-skills   # remove destination skills this repo does not ship
./scripts/verify.sh                  # safe local fixture/static tests, no live workflows
```

From Windows PowerShell in this clone:

```powershell
.\sync-workflows.ps1
.\sync-workflows.ps1 -DryRun
$env:GROK_HOME = 'C:\path\custom grok'
.\sync-workflows.ps1
.\sync-workflows.ps1 -Destination '\\wsl$\YourDistro\home\yourname\.grok'
.\sync-workflows.ps1 -Prune
.\sync-workflows.ps1 -PruneSkills
```

Additional homes are explicit and additive: repeat `--destination` in Bash or pass an array to `-Destination` in PowerShell. Each destination is a Grok home, not its `workflows` subdirectory. No Windows accounts or WSL distributions are discovered automatically. Run the installer appropriate to the shell; Bash destinations use mounted POSIX paths, PowerShell destinations use native/UNC paths.

`--prune` / `-Prune` is opt-in so local-only workflows are preserved by default. Pruning affects only `workflows/*.rhai`; skill directories, support checkpoints, locks, and other state are never pruned. `--prune-skills` / `-PruneSkills` is a separate opt-in. It does nothing when this clone has no `skills/` directory. Once `skills/` exists, it deletes every `<Grok home>/skills/<name>/` directory that has no `skills/<name>/SKILL.md` in this repo, and it deletes extra files inside a skill this repo does ship. That includes personal skills that were never imported. Files under `node_modules` or `.git` stay. Bash also stops the prune when it finds a symlink under the destination skill, including inside those directories. The daily updater never passes either prune flag. Runtime `.mjs` helpers are copied together with workflows, excluding test files. Skill trees are copied as regular files. A symlink in the source skill tree, or on the destination path from `<Grok home>/skills` through the target file, stops the install before that file is written. `node_modules` and `.git` inside a skill are not copied. Dry runs copy neither. The Bash installer and launcher are exercised in temporary directories; PowerShell behavior still needs a Windows smoke test.

## Daily update

Pull `origin/main` (fast-forward only) and copy workflows, skill trees, and bundled helpers into the selected Grok home. Never prunes, so local-only workflows and skills stay put. Refuses to run if this clone is dirty, not on `main`, or cannot fast-forward.

```bash
cd ~/projects/grok-workflows
./scripts/update-workflows.sh            # fetch, ff-only pull, sync
./scripts/update-workflows.sh --dry-run  # show git + copy actions from the fetched revision
./scripts/update-workflows.sh --no-pull  # copy the current tree only
```

A dry run fetches but does not merge. If the remote is ahead, copy actions are previewed from that revision, not from the unchanged checkout. `git fetch` is bounded (120s by default, `UPDATE_WORKFLOWS_FETCH_TIMEOUT`). If it ignores TERM, it is killed after a further 10s (`UPDATE_WORKFLOWS_FETCH_KILL_AFTER`) so a stalled remote cannot hold the lock.

Cron example (runs only while WSL is up):

```cron
15 9 * * * mkdir -p $HOME/.grok/logs && $HOME/projects/grok-workflows/scripts/update-workflows.sh >>$HOME/.grok/logs/update-workflows.log 2>&1
```

Do not `git pull` inside `~/.grok/workflows`. Grok writes files there.

## Adding a workflow

1. In a Grok session: `/create-workflow ...` (saves under `~/.grok/workflows/`).
2. Copy the new `.rhai` into this git repo, commit, and push.
3. Run `./sync-workflows.sh` or `.\sync-workflows.ps1` for each explicitly selected Grok home.

Launch with `/workflow <name>` or `/<name>` when the name is unique.

## Adding a skill

Skills in this repo are user skills. They are not project skills, and they are not loaded from this clone until the installer copies them.

```text
skills/<name>/SKILL.md
skills/<name>/scripts/        # optional
skills/<name>/references/     # optional
```

`<name>` uses lowercase letters, digits, and hyphens. `SKILL.md` needs `name` and `description` frontmatter.

1. Write the skill under `skills/<name>/` in this clone, or run `/create-skill` and copy the new directory from `~/.grok/skills/<name>/` (or a project `.grok/skills/<name>/`) into this repo. `/create-skill` does not write into this clone.
2. Commit the skill tree.
3. Run `./sync-workflows.sh` or `.\sync-workflows.ps1` for each explicitly selected Grok home. `./scripts/update-workflows.sh` copies skills after a fast-forward and does not prune.
4. Run `grok inspect`. The installed skill's source is `user` and its path is `<Grok home>/skills/<name>/SKILL.md`.

Edit the repo copy, then sync. The next sync overwrites a different installed file of the same path. Do not point `[skills] paths` at this clone's `skills/` directory while also installing copies. Grok reads that key only from `~/.grok/config.toml`. `[paths] extra_skill_dirs` does not inject skills. A `[skills] paths` entry is a separate single-machine option, and workflows still need this copy because Grok has no extra path for `.rhai` files.

## Notes

- GitHub is the source of truth.
- Project-scoped workflows can still live in a repo's `.grok/workflows/` if they should not follow you everywhere.

## Recovery and execution lifecycle

- A same-process resume replays committed host-call results with the original script and arguments. It does not retry a previously completed failed agent call, reload edited source into that call, or accept new arguments. Terminal `pause()` messages now request a new run where that is required.
- `await_user()` approval gates can continue to a *new* collection call when the workflow explicitly includes one. The Graphite dirty-worktree gates do this. Do not replace a terminal pause with an approval gate and keep consuming failed output.
- A process restart cannot resume its in-memory workflow. Helper checkpoints are separate from Grok replay. Before starting again, inspect the working tree, commits, remote PR state, and any pending cleanup: an external effect may have occurred before its result was recorded. A new run is not an automatic rollback or an exactly-once retry.
- `implement-approved-plan` requires the implementer's agent ID before testing. If it is absent, the workflow stops without testing the parent checkout or applying the isolated worktree. Inspect that worktree before restarting.
- `graphite-pr-review` prints the collected head as `Reviewed SHA`. That SHA must match `gh pr view` headRefOid; a missing or different head is partial coverage. A diff past the review cap, or a whole file hunk that does not fit in two packets, is partial coverage and blocks submit. The collector returns only those packed hunks, not the unpacked diff. Duplicate confirmed findings collapse to the earliest id, including when groups overlap. A bound the diff states and a test asserts is a residual and is not a repair. Incomplete coverage is listed once under Limits, after the report header. Repair edits only when HEAD is still that reviewed SHA.
- `graphite-pr-review` reviews any branch read-only, but automatic repair/commit/submit now requires a verified unfrozen leaf (no descendants). Unknown topology, a frozen branch, or a non-leaf branch stops before repair; handle those manually. This is a deliberate scope restriction: [Graphite's command reference](https://graphite.com/docs/command-reference) documents recursive downstack freeze and upstack unfreeze, while modify automatically restacks descendants and has no documented no-restack option. Automatic freeze/unfreeze is forbidden. The scratch `freeze-cleanup.json` journal remains for recovery reporting; any pending legacy entries require manual recovery, and the final journal audit is read-only. Never blanket-unfreeze a stack.
- `graphite-stack-merge` no longer depends on an absent Python helper. Dirty or unverified checkouts stop before diagnosis/preparation, with cleanliness rechecked immediately before live preparation. Its native read-only collector requires an unambiguous ancestry chain and the intended tip already checked out; explicit start_branch and range endpoints must match the verified chain. It fails closed on missing evidence or an explicit tip mismatch; select the correct tip yourself and start a new run. Merge dry-run results and actual queue membership must be verified before any preparation or landing. Diagnosis records the local tip SHA and the complete trunk-to-tip PR-number/head-OID set, including ancestors below from_pr. Enqueue rechecks every saved PR head and the local tip after approval and stops on any drift, missing entry, or changed membership. This is a point-in-time check, not an atomic expected-SHA condition: another actor can still race the final Graphite command.
- `linear-cycle-deliver` creates missing PRs without `--update-only`, updates existing PRs with it, and verifies the actual PR number, URL, and remote SHA before adding a Linear link.
- `preflight-gate` host-blocks private local stores (sqlite/db files and sidecars, and `household` JSON outside `src/`, `tests/`, `test/`, `docs/`, `scripts/`, `fixtures/`, and `testdata/`) even when the three lanes are clean. Suffix and `household` matching is case-insensitive. Those hits are not model-refutable. Paths Git does not list are not findings. A staged deletion is not a hit; a staged rename is judged only by its destination.

Workflow agent budgets are cumulative (default 128 calls; explicit supported range 1–1024). Large parallel review panels can exhaust the budget before later verification. Set `--agent-budget` and `--effort` using the installed CLI's launch help; increasing a tool-resumed run's budget requires the corresponding resume option, not a new argument to the old script. Reports of incomplete verification or cleanup are blockers, not successful completion.
