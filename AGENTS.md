# Agent instructions

## Linear linking

Every branch and pull request in this repo must reference a Linear issue in the
**grok-workflows** team (key `GROK`). The advisory `linear-link` check warns on PRs that don't.

- Existing work: use Linear's "Copy git branch name" for the branch, or put
  `Fixes GROK-123` in the PR description (`Refs GROK-123` for partial work).
- New work with no issue yet: put `Fixes GROK-NEW` in the PR description.
- Never reference another team's key unless the work genuinely belongs there.
- If Linear links the wrong issue, add `Ignore <ID>` (for example
  `Ignore CLAUDE-123`) to the PR description.
