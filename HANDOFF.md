# Handoff

The one handoff file for this repo. Update it before stopping, before a compaction, and at
every checkpoint. Keep it short; history lives in git and in ADRs.

## State

- Branch: `feat/phase3-schemes` (worktree `.worktrees/phase3-schemes`), from main 20f5c14 (phases
  1–2 merged). **Phase 3 implemented and committed; reviewer FINAL VERDICT: APPROVE WITH NITS
  (S1–S4 and the nits fixed; the final re-review at 8f8a9ca leaves only N6, a factory-tooling note:
  `dod.jl`/`lane audit` use the stale `origin/main`); waiting for the lead to merge.** Plan: `docs/superpowers/plans/2026-10-20-phase3-schemes.md`.
- Factory 0.2.5, package profile. Contracts binding since 2026-10-19.
- Remote: `origin/main` is at 06d2ae6, behind local main, so `dod.jl` and `lane audit` count
  phases 1–2 too until main is pushed (run `dod.jl --base 20f5c14` meanwhile).

## What phase 3 delivered (all public, not exported, except the two lens/prism kits)

- Transducer substrate (ADR-0003; R3, R7): `Map`, `Filter`, `MapCat`, `Take`, `TakeWhile`, `Scan`,
  `Partition`, `Composed`; `asrf`, `R`, `Bottom`; `start`/`next`/`complete`; `Reduced`;
  fail-closed `isstateless`; `foldxl`, `foldparts`, `foldxt`, `aggregate`.
- Recursion schemes (R6): `Fix`, `project`, `cata` … `futu`, `cataM`/`anaM`/`hyloM`, over own
  node types without rewrapping. À la carte `Coproduct`/`Inl`/`Inr`/`inj`/`prj`; freer monad
  `Free`/`Pure`/`Impure`/`liftF`/`interpret`/`cohandler`/`foldfree`.
- Optics (ADR-0004, ADR-0008): `Lens`, `IndexLens`, `@lens`, `Prism`, `preview`, `review`, `set`,
  `modify`; kits `test_lens_laws`, `test_prism_laws` (exported); ConstructionBase 1.6 is a hard
  dependency; `ChuiCoreAccessorsExt`.
- Laziness (R5): `Thunk`, thread-safe memoised `Lazy`, `force`, `isforced`, `@lazy`, `LazyTag`.
- Banner (R9): `binding_conflicts`, `conflict_banner`.
- Phase-2 nits: N5 fixed (ArgumentError on mismatched `ap`/`alt`; instance methods must type the
  style argument), N2 documented; N4 carried (a tag-level trait cannot see tuple length).

## Decisions taken in phase 3 (lane, recorded in the plan)

1. Recursion-scheme encoding (R6 left it open): `project(x) = x` by default, so downstream node
   types are their own base functor; `Fix` (field `Any`) for generic code; unfolds take `embed`.
2. À la carte names are Swierstra's `inj`/`prj` (`project` is the schemes'); freer encoding.
3. `Lazy` caches a thrown exception (at most one evaluation); a self-forcing body throws.
4. `R` and `Bottom` are public (downstream transducers dispatch on `R{<:T}`).
5. `foldparts` waits for every task; results after a stop are discarded.
6. A root `JuliaTestItems.toml` excludes `.lanes/` and `.worktrees/` from the test-item search
   (review S3; the lead approved the file 2026-10-20 and is seeding it in the factory template).

## Deferred (with reasons)

- `ChuiCoreTransducersExt` (ADR-0003 §8): needs Transducers.jl (20 transitive deps) in the test
  environment, and no consumer asks for it yet.
- Prisms inside *Accessors* compositions: needs Accessors' non-public `OpticStyle`/`ModifyBased`.
- `eduction`, a stack-safe iterative `cata`, a typed `Cofree`: not in v1.

## Open contract follow-ups (for the lead; drafts in the lane report)

- The PROVISIONAL "transducer substrate", "recursion schemes", "free monads", "laziness",
  "optics" and "name-conflict banner" items now have names; ADR-0012 P2's obligation can become an
  entry (v1 transducer set fixed).

## Open lanes

| Lane | Agent | File scope | Status | Report |
|---|---|---|---|---|
| phase3-schemes | the lead's teammate (this lane) | `src/**`, `ext/**`, `test/**`, `Project.toml`, `docs/**`, `benchmark/**`, `HANDOFF.md`, `changelog.d/phase3-schemes.md`, `.gitignore` | committed, not merged | sent to the lead |

Sub-lanes p3-xf, p3-schemes, p3-optics, p3-lazy (implementer agents) worked in scratch copies under
`.lanes/scratch/`; all reported, were merged by the lane lead and are closed; the copies were deleted.

## Evidence

`subagent_mode: actual`. Julia 1.13.2 and 1.10.12. Gate outputs are under `.lanes/evidence/`
(gitignored) and pasted in the lane report.

## Checks NOT run, and why

- `ci.jl contracts`: NOT RUN (waiting): ChuiCore is the root package and has no upstreams.
- Benchmarks, TTFX and load-time budgets: phase 4.

## Next action

- The lead merges `feat/phase3-schemes`; then phase 4 (performance pass).
