# Handoff

The one handoff file for this repo. Update it before stopping, before a compaction, and at
every checkpoint. Keep it short; history lives in git and in ADRs.

## State

- Branch / last commit: `main`, the initial commit `chore: scaffold ChuiCore.jl from factory 0.2.1`
  (factory 0.2.1, coordinator commit 275e879). No remote.
- Phase and current task: **scaffolded; phase 1 (Research and ADRs) not started.** The brief is
  `docs/agent/BRIEF.md`; the shared rules are `docs/agent/ECOSYSTEM.md`.

## Open lanes

| Lane | Agent | File scope | Status | Report |
|---|---|---|---|---|
| (none) | | | | |

Closure proof: no lanes were opened; `git worktree list` shows only the main checkout.

## Evidence

`subagent_mode: actual` (scaffolded by the `scaffold-core` lane for the coordinator, 2026-10-19).

- `julia --project=. -e 'using Pkg; Pkg.test()'` on 1.13.2: `ChuiCore | 4 4`, tests passed.
- Same on `julia +lts` (1.10.12): `ChuiCore | 4 4`, tests passed.
- `julia scripts/ci.jl quality`: 17/17 pass on 1.13.2, 15/15 on 1.10.12 (the two
  ExplicitImports `*_are_public` checks are gated to `VERSION >= v"1.11"`, ADR-0006).
- `julia scripts/ci.jl test`: OK. `julia scripts/gen.jl --check`: OK (30 files).
- `julia scripts/test/runtests.jl` (factory tests, package profile): 631/631 pass.
- `julia scripts/contract_usage.jl`: OK (0 IDs). actionlint on `.github/workflows/*.yml`: clean.
- Docs: `julia scripts/ci.jl docs` built in a scratch copy (Documenter 1.19.0, writes `objects.inv`).
- Fresh clone (`git clone` to a scratch dir) + `julia --project=. -e 'using Pkg;
  Pkg.instantiate(); Pkg.test()'` on 1.13.2: `ChuiCore | 4 4`, tests passed.

## Checks NOT run, and why

- `julia scripts/ci.jl guards`: **fails** on two factory issues (below), not on package code.
- `julia scripts/check_docs.jl`: fails on `docs/agent/ECOSYSTEM.md:60` (`scripts/lane.py`, a
  reference-project path quoted by the ecosystem rules). Passes when the two `docs/agent/` copies
  are excluded via a scratch `--config`.
- `julia scripts/ci.jl jet`: not run (JET env not instantiated in the scaffold; nothing to analyse yet).
- `julia scripts/ci.jl format` (Runic): not run; the formatter is a pending ★ (ADR-0007).
- GitHub workflows: linted only; running them needs a GitHub remote (★ push approval).

## Blockers and decisions waiting

- Factory bug: seeded `ratchets.toml` caps `.claude/hooks/*.sh` at 150 lines, but managed
  `bash_guard.sh` has 210, so `ratchet.jl` (and `ci.jl guards`) fails in every vendored repo.
- Factory bug: the package profile's seeded `.agents/factory.toml` does not exclude
  `docs/agent/ECOSYSTEM.md` / `BRIEF.md` from `check_docs`, though the coordinator excludes their
  source (`prompts/**`). Fixing it here is a T3 edit (needs the user or `FACTORY_ALLOW_T3=1`).
- ★ defaults taken from Proposed ADRs: version 0.0.1 (ADR-0004), `julia = "1.10"` (ADR-0006),
  TestItemRunner and Runic in CLAUDE.md (ADR-0007), docs layout (ADR-0008), MIT (ADR-0011).

## Next action

- Coordinator: fix the two factory issues, then re-sync this repo.
- Phase 1 (Research and ADRs) per `docs/agent/BRIEF.md`, ending in a ★ report to the lead.
