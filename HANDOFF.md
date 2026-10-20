# Handoff

The one handoff file for this repo. Update it before stopping, before a compaction, and at
every checkpoint. Keep it short; history lives in git and in ADRs.

## State

- Branch: `feat/phase2-traits` (worktree `.worktrees/phase2-traits`), from main 3054d7c.
  **Phase 2 (traits and law kits) implemented and committed; reviewer FINAL VERDICT: APPROVE WITH
  NITS (blocker B1 and should-fixes S1–S3 fixed in eeca1f3); waiting for the lead to merge.**
- Deferred review nits (phase 3/4): N2 `Sum`/`Prod`/`Mean` accept scalar elements only (document
  or relax); N4 `BifunctorStyle` claims `IsBifunctor` for non-2-tuples; N5 mismatched classes in
  `alt`/`ap` give `MethodError`, not `ArgumentError`.
- Factory 0.2.5, package profile. Contracts binding since 2026-10-19.
- Remote: `origin` (github.com/bonmac/ChuiCore.jl) exists locally with `origin/main` at 06d2ae6,
  behind local main (3054d7c). `dod.jl` and `lane audit` prefer `origin/main` as the base, so they
  also count phase 1's files until main is pushed (the lead's/user's call).
- Phase 1 (Research and ADRs) done: ADRs 0001–0008 Accepted 2026-10-20.
- Phase 2 plan: `docs/superpowers/plans/2026-10-20-phase2-traits.md` (names, tiers, clash evidence).

## What phase 2 delivered

- Composition: `⨟`/`opcompose` (CompositionsBase's binding), `pipe`, `papply`, `flip`, `ChuiCore.curry`.
- Monoid family (ADR-0001 §1–2): `init`/`partial`/`combine`/`final`/`iscommutative`, `neutral`
  (fresh per call), `default_monoid`, `AlgebraClass`, `combineall`; the CC-007 aggregators
  (`Sum` … `MapM`, `Moments(:var | :std; corrected)`, `ReduceM(op; neutral, commutative)`).
- Constructor classes (ADR-0001 §3): tags, `constructorclass`, 11 `*Style` traits, operations,
  instances on Maybe/Array/Tuple/Dict/Pair/Function and owned `Identity`, `ZipVector`, `Predicate`.
- Law kits (ADR-0007): 14 exported stubs; `ChuiCoreTestExt` and `ChuiCoreSuppositionExt`
  (`@check record=false db=false` + `@test`); a planted violation per law under both drivers.
- Tiers (ADR-0005): exported / public (`@compat public`) / internal; clash list checked in
  `test/exports/` (two environments: TypeClasses 1.x cannot be installed next to ChuiCore).

## Decisions taken in phase 2 (lead, 2026-10-20)

1. ADR-0005 rule 2 wins over rule 3's listing: `neutral`, `curry`, `fmap`, `pure`, `ap` are public,
   not exported (TypeClasses 1.1.0 / Functors 0.4.12 export them). Rule 3 needs a correction
   (draft item in the lane report; ecosystem ADR-0009 lane informed by the lead).
2. **ConstructionBase (ADR-0008) is deferred to phase 3**, when optics use it (an unused hard
   dependency fails Aqua's stale-deps check). Do not forget it in phase 3.

## Open contract follow-ups

- PROVISIONAL items that phase 2 can now fill (coordinator, T3): CompositionsBase binding, export
  list, typeclass trait encoding, law kits, composition helpers, the `Moments`/`ReduceM`
  constructors. The lane report carries draft wording.
- ADR-0003 Decision 4 (only `isstateless` pipelines per partition): proposed for the contract.

## Open lanes

| Lane | Agent | File scope | Status | Report |
|---|---|---|---|---|
| phase2-traits | the lead's teammate (this lane) | `src/**`, `ext/**`, `test/**`, `Project.toml`, `docs/**`, `benchmark/**`, `HANDOFF.md`, `changelog.d/phase2-traits.md` | committed, not merged | sent to the lead |

Sub-lanes p2-algebra and p2-classes (implementer agents) reported and are closed; their worktrees
were removed (`scripts/lane remove`); the empty branches `feat/p2-algebra`, `feat/p2-classes`
(at 58bad5d, no own commits) remain for the lead to delete.

## Evidence

`subagent_mode: actual`. Julia 1.13.2 and 1.10.12. Gate outputs are pasted in the lane report;
logs under `.lanes/evidence/` (gitignored).

## Checks NOT run, and why

- `ci.jl contracts`: NOT RUN (waiting): ChuiCore is the root package and has no upstreams.
- Benchmarks and TTFX budgets: phase 4.
- Snapshot tests: nothing prints in a tested way yet.

## Next action

- The lead merges `feat/phase2-traits`; then phase 3 (recursion schemes, free monads, laziness,
  optics with ConstructionBase, transducers).
