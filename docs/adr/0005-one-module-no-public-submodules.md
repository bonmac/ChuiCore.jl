# ADR-0005: ChuiCore is one module with no public submodules; names are tiered exported / public / internal by a tested clash rule

- **Status:** Proposed
- **Date:** 2026-10-20
- **Deciders:** the user, at the phase-1 ★ checkpoint (★ Q2: the export tiers and ecosystem ADR-0009)
- **Scope:** ChuiCore.jl

## Context

- The brief asks phase 1 to decide "whether the package is split internally (submodules)".
  Ecosystem ADR-0002 already rejected a separate micro-package for monoids/transducers ("revisit
  if ChuiCore outgrows its TTFX budget").
- The contract names everything qualified at the top level (`ChuiCore.partial`, `ChuiCore.Sum`)
  and leaves the export list PROVISIONAL. **Ecosystem ADR-0009 (Accepted), Consequences, says
  "ChuiCore exports `partial` (protocol), `papply` (partial application) and `neutral`."** This ADR
  proposes not exporting `partial`; that needs the lead to amend ADR-0009 (★ Q2).
- Facts:
  - A submodule name re-exported by the parent is the same binding (`===`), and an extension can add
    methods to a parent stub (`law-kits-modules-names.md` L-1, both versions).
  - Measured clashes of candidate exports: DataFrames exports `combine` (E-38); Transducers.jl
    exports `Map`, `Filter`, `foldxl`, `Count` (`transducers.md` R6); Accessors exports `set`
    (`optics.md`); `Base.Iterators` exports `flatmap` (L-2 addendum, both versions); Setfield
    exports `Lens`, `set`, `get`, `modify` (installed source, its src/lens.jl line 1); TypeClasses
    exports `neutral` and `combine` (installed source, line 4); Functors.jl exports `fmap` (critic,
    from its GitHub master source).
  - Internal collisions: the aggregator `Sum` (CC-007) vs Haskell's functor coproduct `Sum`.
  - `public` is a `ParseError` on 1.10; `@compat public` is the gate (ecosystem ADR-0006 §3–4).

## Decision

1. ChuiCore **must** be a single module, its source split into files by area (`compose.jl`,
   `algebra/*.jl`, `aggregators.jl`, `transducers.jl`, `schemes.jl`, `free.jl`, `lazy.jl`,
   `optics.jl`, `banner.jl`; names indicative), all `include`d at top level, with **no** submodules
   (public or internal). Collisions are resolved by naming (the functor coproduct is `Coproduct`).
2. **The clash list.** A name may be exported only if it is not exported, as a different binding,
   by Base, Core, `Base.Iterators`, the standard libraries of CC-010, or these packages:
   DataFrames, Transducers, Accessors, Setfield, Functors, TypeClasses, ConstructionBase,
   CompositionsBase (except its `⨟` and
   `opcompose`, which are the same binding). A `:quality` test checks this in its own environment
   (like JET's; a new `exports` directory under `test`, created in phase 2), on stable only; the list is extended by ADR.
3. **Three tiers, each name in exactly one:**
   - **Exported** (unqualified vocabulary that passes the clash list): `⨟`, `opcompose` (CC-001),
     `neutral` and `papply` (ecosystem ADR-0009), the law-kit stubs (ADR-0007), and the
     constructor-class operations and traits of ADR-0001 whose final names pass the list.
   - **Public, not exported** (`@compat public`; used qualified or via `using ChuiCore: x`):
     - the aggregation protocol `init`, `partial`, `combine`, `final`, `iscommutative` — so
       `combine`, also the Semigroup operation (ADR-0001), is always written `ChuiCore.combine`;
     - the built-in aggregators (`Sum`, `Count`, …);
     - the transducer substrate (`Map`, `Filter`, `foldxl`, `Reduced`, …; ADR-0003);
     - optics (`Lens`, `Prism`, `preview`, `review`, `set`, `modify`; ADR-0004);
     - the hooks downstream code extends (ADR-0001): `AlgebraClass`, `IsSemigroup`, `IsMonoid`,
       `NotAlgebra`, `default_monoid`, `constructorclass`, the constructor tags and the
       `*Style` trait functions and values, unless phase 2 exports a trait name that passes the list;
     - test helpers: `default_eq` (ADR-0007) and the closed-sum exhaustiveness helper (ADR-0002);
     - recursion schemes, free monads, laziness (`cata`, `ana`, `hylo`, …, `Fix`, `Coproduct`), whose
       main consumer is ChuiFrames' optimizer and whose names are jargon.
   - **Internal:** everything else (no stability promise).
4. Every name in the first two tiers must have a docstring; on ≥ 1.11 a `:quality` test checks
   `Docs.undocumented_names(ChuiCore)` is empty (the function is missing on 1.10.12, L-2 addendum).
5. The tiers are the proposal for the contract's PROVISIONAL "Export list" item; the lead decides
   (no contract edit here).

## Alternatives rejected

| Alternative | Why rejected |
|---|---|
| Public submodules (`ChuiCore.Algebra`, `ChuiCore.Optics`, …) | Users import several things; contract names need submodule paths or re-exports, duplicating the export decision per submodule; ExplicitImports' owner checks get noisier. |
| Internal submodules re-exported at the top | Same binding (L-1), so legal, but adds `using .Sub: x` plumbing for cross-area names (`combine` serves algebra and aggregators; `Sum` is an aggregator next to the coproduct) with no user-visible gain. |
| An opt-in `ChuiCore.Prelude` module exporting the full vocabulary | Attractive (it would let `combine`, `fmap`, `cata` be unqualified on request) but it is a second, parallel export decision; ecosystem ADR-0009 rejected the analogous `ChuiFrames.Grammar` submodule. Offered to the user as the ★ Q2 alternative. |
| Export `partial` as ecosystem ADR-0009's Consequences say | Splits the four-function protocol across two tiers (`partial` bare, `combine`/`init`/`final` qualified, since `combine` clashes with DataFrames); recommended: amend ADR-0009 (★ Q2). |
| Separate packages per area | A fifth+ repo, versioned in lockstep; rejected by ecosystem ADR-0002 unless TTFX forces it. |
| Export everything | Bare-name breakage with DataFrames, Transducers, Accessors, `Base.Iterators`, Setfield, Functors. |
| Export nothing but `⨟` | Every typeclass call becomes qualified; the brief wants a usable functional vocabulary. |

## Consequences

- One flat namespace: each new name is checked against all existing names and the clash list.
- Downstream code writes `ChuiCore.combine`, `ChuiCore.Sum`, `ChuiCore.Map` (already the contract's
  style) or `using ChuiCore: …`.
- On 1.10 `public` is a no-op (`@compat public`): the public tier is documented, not enforced, there;
  ExplicitImports' `*_are_public` checks run only on ≥ 1.11 (ecosystem ADR-0007 §3).
- The exports test environment adds DataFrames, Transducers, Accessors, Setfield, Functors and TypeClasses as
  test-only dependencies of that one job (not of `test/Project.toml`).

## Verification

- `docs/research/law-kits-modules-names.md` L-1, L-2 (+ addendum); `transducers.md` R6;
  `optics.md` (bare `set` clash); E-06, E-37, E-38; ecosystem ADR-0009 Consequences (the `partial` line).
- UNVERIFIED: Functors' `fmap` export at a tagged release (seen on GitHub master); any load-time or TTFX
  difference between one module and submodules (not measured, not relied on).

## Revisit when

- Phase 4 measures load time or TTFX over budget (ecosystem ADR-0002's trigger): measure a split first.
- ChuiCore's conflict banner or the coordinator's `integration/` environment reports a clash with an
  exported name.
- The user chooses the `Prelude` alternative at ★ Q2.
