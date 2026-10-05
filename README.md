# grok-workflows

Personal library of [Grok Build](https://x.ai/cli) workflow files (`.rhai`).

Grok loads user-level workflows from `~/.grok/workflows/`. On this machine that path is a symlink to this repo, so saved workflows stay in git instead of Google Drive.

## Workflows

| Slash command | What it does |
| --- | --- |
| `/branch-review` | Read-only review of `origin/main...HEAD` (or another range): one reviewer per changed file, then an independent verifier per finding |
| `/class-audit` | Audit one defect class: scan in parallel, adversarially verify each hit, keep only file-backed confirmed instances |
| `/dependabot-pr-triage` | Read-only triage of open Dependabot (and optional Renovate) PRs: MERGE / HOLD / REJECT. Never merges, approves, or comments |
| `/docs-refresh` | Evidence-based documentation reconciliation for one Git repository |
| `/export-workflows` | Read Grok workflows and emit a host-agnostic universal template |
| `/goal-planning` | One-shot meta-planner that writes exactly two `docs/goals` files for the next long-horizon goal |
| `/graphite-pr-review` | Review one Graphite PR, refute findings, plan repairs, then optionally commit and submit |
| `/graphite-stack-merge` | Land a Graphite stack via Graphite merge or merge-when-ready. Never uses `gh pr merge` |
| `/graphite-stack-review` | Review and remediate a Graphite PR stack bottom-up while monitoring CI and review feedback |
| `/him-to-implement` | Universal HIM audit: prove failure points with real tests, write codex + handoff |
| `/implement-approved-plan` | Implement an approved plan in an isolated worktree, run tests after, and stop without applying if tests fail |
| `/implement-from-plan` | Read source files, write a step-by-step process file, implement from it, then test and fix |
| `/linear-cycle-deliver` | Plan and, when apply is true, TDD-implement the current Linear cycle as Graphite PRs |
| `/linear-organize` | Report Linear triage, cycle, label, priority, and shipped-but-open issues |
| `/multi-track-ship` | Multi-track ship: read a multi-area plan and implement tracks in parallel |
| `/preflight` | Universal pre-commit/pre-PR gate: map the change set, multi-dimension review |
| `/preflight-gate` | Read-only pre-commit gate: review the diff, audit tests from `AGENTS.md`, scan for secrets, then SHIP or BLOCK |
| `/repo-map` | Read-only map of repo layout, real test/lint commands, and the smallest safe change |
| `/search-and-destroy` | AFK opportunistic improvement: scout bugs, polish, and half-done work |
| `/tech-debt-scan` | Scan one git root for technical debt and overwrite `TECH_DEBT.md` with a verified remediation plan |
| `/workspace-map` | Read-only map of git roots, stacks, and verified commands in a multi-repo workspace |

## Local layout

```text
~/projects/grok-workflows     # this git repo
~/.grok/workflows             # symlink -> ~/projects/grok-workflows
```

Grok only executes `*.rhai` files in that directory. `README.md` and `.git` are ignored.

## Adding a workflow

1. In a Grok session: `/create-workflow ...` (saves under `~/.grok/workflows/`, which is this repo).
2. Or copy a `.rhai` file into this directory.
3. Commit and push.

Launch with `/workflow <name>` or `/<name>` when the name is unique.

## Notes

- Started from live WSL `~/.grok/workflows/` (2026-10-05), then synced newer files from `G:\My Drive\AI-Tools-and-Prompts\Grok Workflows\wsl-home`.
- GitHub is the source of truth. The Drive folder is a backup only.
- Project-scoped workflows can still live in a repo's `.grok/workflows/` if they should not follow you everywhere.
