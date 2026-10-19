# ADR-0006: Depend on CompositionsBase for the one `⨟` binding

- **Status:** Accepted (2026-10-20, user at the ChuiCore phase-1 ★). Depends on a pending
  coordinator amendment: CC-001 via a contract ADR (Chui-added methods stay binary; the upstream
  fallback and a downstream closing varargs method may be variadic).
- **Date:** 2026-10-20
- **Deciders:** the user, at the phase-1 ★ checkpoint
- **Scope:** ChuiCore.jl (a dependency ADR)

## Context

- Contract CC-001/CC-002 (stable): ChuiCore exports `⨟` and `opcompose`, `opcompose === ⨟`,
  `(f ⨟ g)(x...) == g(f(x...))`, one `⨟` binding in the ecosystem, downstream packages only add
  methods. The contract's PROVISIONAL "CompositionsBase binding" item and ecosystem ADR-0009 §1
  *recommend* taking the binding from CompositionsBase; ChuiCore's ADR confirms. This is that ADR.
- Facts (`docs/research/compositionsbase.md`, run on 1.10.12 and 1.13.2):
  - CompositionsBase 0.1.2: no hard dependencies, `julia = "1"`, InverseFunctions only as an
    extension; last repo change 2023-04-20, not archived, 0 open issues.
  - Source: `const var"⨟" = opcompose`; one untyped method `opcompose(fs...) = ∘(reverse(fs)...)`;
    no methods added to `Base.∘`; exports `∘`, `compose`, `opcompose`, `⨟`, `decompose`, `deopcompose`.
  - A module re-exporting `⨟` keeps the binding (`M.:⨟ === CompositionsBase.:⨟`); a bare `⨟`
    resolves after `using M, CompositionsBase` and after `using M, Accessors` (Accessors re-exports
    it). `f ⨟ g` returns a `ComposedFunction`; the behavioural law holds. A downstream
    `⨟(::Step, ::Step)` works and Aqua flags no piracy.
  - A separate ChuiCore `⨟` with Accessors loaded: warning then `UndefVarError` on 1.10;
    `UndefVarError` with an ambiguity hint on 1.13.
  - Load cost: 1–2 ms for the package itself (`@time_imports`); 1.3 ms (1.13.2) and 4–6 ms
    (1.10.12) wall clock for `@elapsed using CompositionsBase` (`law-kits-modules-names.md` L-6).
  - Gotcha: infix `a ⨟ b ⨟ c` is nested binary calls (CC-001), but the prefix call `⨟(a, b, c)` hits
    the generic varargs method and returns a nested `ComposedFunction`, not a downstream type.
  - **Conflict with CC-001's wording:** CC-001 says "`⨟` is binary, not n-ary: methods take exactly
    two arguments", but CompositionsBase's only method is variadic (`opcompose(fs...)`; critic B,
    `cb.jl`, both versions: `all methods binary: false`). Taking the binding imports that method.
  - Transducers.jl re-exports CompositionsBase's `⨟` (its src/Transducers.jl line 108,
    `export ⨟`, installed 0.4.85).

## Decision

1. ChuiCore **must** depend on CompositionsBase with `[compat] CompositionsBase = "0.1.2"`.
2. ChuiCore **must** re-export exactly `⨟` and `opcompose` from it, and nothing else (not
   `compose`, `decompose`, `deopcompose`, nor its re-export of `Base.∘`; critic B confirmed
   `names(M) == [:M, :opcompose, :⨟]` without `∘`).
3. ChuiCore and downstream packages add methods through `ChuiCore.:⨟` (`import ChuiCore: ⨟`, CC-002's
   wording; the same function as `CompositionsBase.opcompose`), each on a type they own, and every
   method they add is binary, except a downstream's closing varargs method (below and Decision 4).
   A downstream that gives `⨟` a non-function meaning (ChuiFrames'
   `Pipeline`) **should** also define a varargs method so `⨟(a, b, c)` agrees with `a ⨟ b ⨟ c`;
   that is a "should" until CC-001's wording is amended.
4. **Request to the lead (contract ADR):** amend CC-001's "methods take exactly two arguments" to
   "methods added by Chui packages are binary; the upstream fallback (and a downstream's closing
   varargs method) is variadic". No contract edit here.
5. Once accepted, the contract's PROVISIONAL "CompositionsBase binding" item becomes stable, with
   the tests it already names: `ChuiCore.:⨟ === CompositionsBase.:⨟` and `opcompose` likewise; a
   bare `⨟` resolves after `using ChuiCore, CompositionsBase`, `using ChuiCore, Accessors` and
   `using ChuiCore, Transducers`; and no check relies on the absence of a warning (E-37).

## Alternatives rejected

| Alternative | Why rejected |
|---|---|
| ChuiCore defines its own `⨟` | Bare `⨟` breaks for anyone who also loads Accessors or Transducers (both re-export CompositionsBase's), on both Julia versions. |
| Re-export all of CompositionsBase's exports | `compose`/`decompose` are not part of the contract and enlarge the export surface for no user. |
| Vendor (copy) the two lines | Creates a second binding: the same clash as the first row. |
| Wait for Base to define `⨟` | Base defines no `⨟` on 1.10–master (E-01, E-02); no sign it will. |

## Consequences

- One of ChuiCore's three hard dependencies, with Compat (allowed by ecosystem ADR-0006 §4 without
  a per-package ADR) and ConstructionBase (ADR-0008).
- A dormant upstream (last change 2023) is a low risk for a 30-line package; a fork under a new
  UUID would be a second binding (the vendoring clash), so if a change is ever needed the
  mitigation is an upstream pull request or a maintainer handover (UNVERIFIED whether the
  maintainers would respond).
- `1 ⨟ 2` builds a composition without error and fails only when called (upstream's untyped
  method); ChuiCore documents this rather than restricting it (restricting would be piracy).

## Verification

- `docs/research/compositionsbase.md` (registry, `gh api`, source, scratch modules on both
  versions, Aqua), ecosystem E-01, E-02, E-03, E-28; critic-B scratch `phase1/critic-b/cb.jl`
  (method arity, export list); installed Transducers 0.4.85 source (line 108).
- UNVERIFIED: the exact release date of 0.1.2 (only a `v0.1.0` tag exists; on or after 2023-04-20).

## Revisit when

- Base defines `⨟`, or CompositionsBase is archived or makes a breaking release.
- A downstream package needs a CompositionsBase export other than `⨟`/`opcompose`.
- The lead rejects the CC-001 amendment (Decision 4): then Decision 3's varargs advice is dropped and
  the conflict goes to a contract ADR.
