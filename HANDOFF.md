# Handoff

The one handoff file for this repo. Update it before stopping, before a compaction, and at
every checkpoint. Keep it short; history lives in git and in ADRs.

## State

- Branch: `feat/phase4-perf` (worktree `.worktrees/phase4-perf`), from main b4f1ca3 (phases 1–3
  merged). **Phase 4 (performance pass) implemented and committed; under review; not merged.**
  Spec `docs/superpowers/specs/2026-10-20-phase4-perf-design.md`, plan
  `docs/superpowers/plans/2026-10-20-phase4-perf.md`.
- Factory 0.2.5, package profile. Contracts binding since 2026-10-19.
- Remote: `origin/main` is behind local main, so `dod.jl` and `lane audit` count earlier phases
  until main is pushed (run `dod.jl --base b4f1ca3` meanwhile).

## What phase 4 delivered

- JET: clean at the `ci.jl jet` strictness (already clean at b4f1ca3; no source change needed).
- ADR-0009 (Proposed): allocation budgets (tests, `test/perf_allocs_tests.jl`), per-version time
  budgets (`benchmark/budgets.toml`, `benchmark/run.jl --check`), load/TTFX/precompile budgets
  (`benchmark/ttfx.jl --check`), the benchmark set (`benchmark/benchmarks.jl`).
- ADR-0010 (Proposed): hard dependency PrecompileTools `"1.2"`; workload `src/precompile.jl`;
  `test/precompile_tests.jl` (`:slow`) checks the TTFX workload compiles no ChuiCore method.
- Load + first call: 230 → 47 ms (1.13.2), 247 → 69 ms (1.10.12); load +23–26 ms; precompile
  0.84 → 1.6 s / 0.88 → 1.4 s. All budgets met on both versions. Results and losses:
  `docs/src/performance.md` (new docs page).

## Decisions waiting (★, for the lead to take to the user)

1. Accept ADR-0010 (a new hard dependency, PrecompileTools). Recommendation: accept.
2. ADR-0009's policy items: the 3× (1-2-5) time-budget multiplier, the 3.0 s precompile budget,
   the one-way "only tighten" rule, and keeping `run.jl --check`/`ttfx.jl --check`/`test -- slow`
   out of CI (run at release and by engine-changing lanes). Recommendation: accept as written.

## Deferred (with reasons)

- `ChuiCoreTransducersExt` (ADR-0003 §8): still deferred; needs Transducers.jl (≈20 transitive
  deps) in the test environment and no consumer asks for it. Not a performance item.
- Prisms inside *Accessors* compositions; `eduction`, a stack-safe `cata`, a typed `Cofree`.
- Factory nit N6 (`dod.jl`/`lane audit` use the stale `origin/main`): factory lane's.

## Open lanes

| Lane | Agent | File scope | Status | Report |
|---|---|---|---|---|
| phase4-perf | the lead's teammate (this lane) | `src/**`, `ext/**`, `test/**`, `Project.toml`, `docs/**`, `benchmark/**`, `HANDOFF.md`, `changelog.d/phase4-perf.md`, `JuliaTestItems.toml` | committed, in review | to the lead |

Sub-lane p4-allocs (implementer, `test/perf_allocs_tests.jl` only) reported and is closed; a
critic reviewed ADR-0009/0010 (ACCEPT WITH CHANGES, findings applied) and is closed.

## Evidence

`subagent_mode: actual`. Julia 1.13.2 and 1.10.12, Apple M3 Pro, machine loaded (load average
8–21). Gate and measurement outputs under `.lanes/evidence/` (gitignored), pasted in the lane
report.

## Checks NOT run, and why

- `ci.jl contracts`: NOT RUN (waiting): ChuiCore is the root package and has no upstreams.
- `ci.jl bench` (HEAD vs merge base): the merge base has no `benchmark/benchmarks.jl`, so it
  reports nothing to compare; AirspeedVelocity was run instead (main vs branch, 1.13.2).
- Measurements on a quiet machine or on CI runners: none available.

## Next action

- The reviewer's FINAL verdict, then the lead merges `feat/phase4-perf` after the ★ answers.
