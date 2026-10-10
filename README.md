# grok-workflows

Personal library of [Grok Build](https://x.ai/cli) workflow files (`.rhai`).

Grok loads user-level workflows from real files in `~/.grok/workflows/` (not a symlink). This git repo is the source of truth. After a pull, run the sync script to copy `*.rhai` into the config dirs.

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
| `/multi-track-ship` | Multi-track ship: read a multi-area plan and implement tracks in parallel |
| `/preflight` | Universal pre-commit/pre-PR gate: map the change set, multi-dimension review |
| `/preflight-gate` | Read-only pre-commit gate: review the diff, audit tests from `AGENTS.md`, scan for secrets, then SHIP or BLOCK |
| `/repo-map` | Read-only map of repo layout, real test/lint commands, and the smallest safe change |
| `/search-and-destroy` | AFK opportunistic improvement: scout bugs, polish, and half-done work |
| `/ship-next-issue` | Pick the next open Linear issue (current cycle, then the rest of the team), implement it, review it, and submit one Graphite PR. Unrelated tracked changes stay unstaged. Never merges |
| `/tech-debt-scan` | Scan one git root for technical debt and overwrite `TECH_DEBT.md` with a verified remediation plan |
| `/workspace-map` | Read-only map of git roots, stacks, and verified commands in a multi-repo workspace |

## Local layout

```text
~/projects/grok-workflows              # this git repo (source of truth)
~/.grok/workflows/*.rhai               # WSL Grok 1.0.46 config copies (real files)
%USERPROFILE%\.grok\workflows\*.rhai  # Windows grok.exe config copies
```

Grok only executes `*.rhai` files in those config directories. Do not symlink the config dir at the git repo; the harness may not load workflows through a directory symlink.

## Sync repo → Grok config

From WSL:

```bash
cd ~/projects/grok-workflows
./sync-workflows.sh            # copy *.rhai into WSL + Windows grok homes
./sync-workflows.sh --dry-run  # show what would change
./sync-workflows.sh --prune    # also delete dest *.rhai files not in this repo
./scripts/verify.sh            # check the in-repo Graphite monitor CLI
```

From Windows PowerShell:

```powershell
cd \\wsl$\Ubuntu-24.04\home\kinginyellow\projects\grok-workflows
.\sync-workflows.ps1
.\sync-workflows.ps1 -DryRun
.\sync-workflows.ps1 -Prune
```

`--prune` / `-Prune` is opt-in so a workflow created with `/create-workflow` is not deleted until you copy it into git.

## Daily update

Pull `origin/main` (fast-forward only) and copy `*.rhai` into Grok config dirs. Never prunes, so local-only workflows stay put. Refuses to run if this clone is dirty, not on `main`, or cannot fast-forward.

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
3. Run `./sync-workflows.sh` or `.\sync-workflows.ps1` so every Grok home matches the repo.

Launch with `/workflow <name>` or `/<name>` when the name is unique.

## Notes

- GitHub is the source of truth.
- Project-scoped workflows can still live in a repo's `.grok/workflows/` if they should not follow you everywhere.
