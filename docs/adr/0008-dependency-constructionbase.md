# ADR-0008: Depend on ConstructionBase for struct rebuilding in optics

- **Status:** Accepted (2026-10-20, user at the ChuiCore phase-1 ★)
- **Date:** 2026-10-20
- **Deciders:** the user, at the phase-1 ★ checkpoint (★ Q3, with ADR-0004)
- **Scope:** ChuiCore.jl (a dependency ADR)

## Context

- ADR-0004 gives ChuiCore its own lenses. Setting a field of an immutable struct means rebuilding
  it, and the rebuild rule must agree with Accessors', or one value gets two different results from
  `ChuiCore.set` and `Accessors.set`.
- Facts:
  - ConstructionBase 1.6.0: no registered hard dependencies (`optics.md`); `constructorof(T)`
    defaults to `Base.typename(T).wrapper`, and type owners override `constructorof` or
    `setproperties` for custom constructors; Accessors uses exactly this hook (critic B, reading
    ConstructionBase 1.6.0 source and running `cbdiv.jl` on both versions).
  - Load time (`law-kits-modules-names.md` L-6, quiet host): `using ConstructionBase` 16–23 ms on
    1.10.12, 2–8 ms on 1.13.2 (critic: 14.6–14.7 / 2.1–2.6 ms).
  - ConstructionBase is already a hard dependency of Accessors (and so loaded by anyone who uses
    Accessors).

## Decision

1. ChuiCore **must** depend on ConstructionBase with `[compat] ConstructionBase = "1.6"` (the
   version tested; ADR-0004 also pins Accessors to its tested version).
2. ChuiCore's property lenses **must** write through `ConstructionBase.setproperties` (which uses
   `constructorof`, the hook type owners override), never through a rule of their own. Types that
   overload `propertynames` must implement `setproperties` for lenses to set them, as with Accessors
   (critic B, `props.jl`).
3. ChuiCore does not re-export ConstructionBase names; type owners extend `ConstructionBase`'s
   functions directly.

## Alternatives rejected

| Alternative | Why rejected |
|---|---|
| Own default-constructor rule | Diverges from Accessors for any type whose owner defines `constructorof` (critic B). |
| Vendor ConstructionBase's code | A second hook: owners would have to implement both. |
| Support only NamedTuples and Tuples in v1 | Lenses on user structs are the main use of optics. |
| Accessors as the dependency instead | ADR-0004 Decision 1. |

## Consequences

- ChuiCore's hard dependencies: Compat (ecosystem ADR-0006 §4), CompositionsBase (ADR-0006),
  ConstructionBase (this ADR). Load cost of the three is a phase-4 budget item.
- `Base.typename(T).wrapper` fails for phantom parameters; the docs point owners to `constructorof`.

## Verification

- `docs/research/optics.md` (dependency facts), `law-kits-modules-names.md` L-6 (load times),
  critic-B scratch `phase1/critic-b/cbdiv.jl`, `rebuild.jl`.
- UNVERIFIED: invalidations it causes.

## Revisit when

- Phase 4 attributes a significant share of ChuiCore's load time to it.
- Base gains a public struct-rebuild protocol.
