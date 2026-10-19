# Handoff

The one handoff file for this repo. Update it before stopping, before a compaction, and at
every checkpoint. Keep it short; history lives in git and in ADRs.

## State

- Branch / last commit: `main`; before this HANDOFF refresh, a7e7630
  `chore: sync factory 0.2.4 and refresh ecosystem copies`.
- Factory 0.2.4, package profile (`.factory-version`). `docs/agent/ECOSYSTEM.md` and `BRIEF.md`
  are copies from coordinator commit ff0100a (the coordinator history was rewritten; its content
  is unchanged). Contracts are binding since 2026-10-19.
- Remote: none yet. The public GitHub repo `bonmac/ChuiCore.jl` is approved; the lead creates it.
- Phase and current task: **scaffolded; phase 1 (Research and ADRs) not started.**

## Open lanes

| Lane | Agent | File scope | Status | Report |
|---|---|---|---|---|
| (none) | | | | |

Closure proof: no lanes were opened; `git worktree list` shows only the main checkout.

## Evidence

`subagent_mode: actual` (2026-10-20, Julia 1.13.2, on the working tree of this refresh).

- `julia --startup-file=no scripts/ci.jl guards`: `ci.jl guards: OK` (factory tests 1189/1189).
- `julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'`: `ChuiCore | 4 4`, tests passed.
- The scaffold's earlier checks (LTS 1.10.12 tests, `ci.jl quality`, docs build, fresh clone)
  are in git history; they were not re-run for this refresh.

## Checks NOT run, and why

- `julia scripts/ci.jl jet`: not run (nothing to analyse yet).
- `julia scripts/ci.jl format` (Runic): not run; the formatter is a pending ★ (ADR-0007).
- GitHub workflows: not run; they need the GitHub remote.

## Blockers and decisions waiting

- None blocking. ★ defaults taken from Proposed ADRs: version 0.0.1 (ADR-0004),
  `julia = "1.10"` (ADR-0006), TestItemRunner and Runic (ADR-0007), docs layout (ADR-0008),
  MIT (ADR-0011).

## Next action

- Phase 1 (Research and ADRs) per `docs/agent/BRIEF.md`, started by the lead at L1, ending in a
  ★ report to the lead.
