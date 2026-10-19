# ADR-0004: ChuiCore owns a minimal Lens/Prism core; Accessors.jl is an extension, not a dependency

- **Status:** Proposed
- **Date:** 2026-10-20
- **Deciders:** the user, at the phase-1 ★ checkpoint (★ Q3: Accessors as a dependency or not)
- **Scope:** ChuiCore.jl

## Context

- The brief: "Optics: lenses and prisms. Evaluate Accessors.jl and reuse it if it's good enough."
  Ecosystem ADR-0002 keeps ChuiCore's dependency budget tiny, because every Chui package loads it.
- Facts (`docs/research/optics.md` and its addendum; both 1.10.12 and 1.13.2; Context7 has no
  Accessors entry):
  - Accessors 0.1.45 (2026-06-26), `julia = "1.10.0 - 1"`, actively released. Hard deps:
    CompositionsBase, ConstructionBase, InverseFunctions, MacroTools (+ Dates stdlib).
  - Load time on a quiet host (`law-kits-modules-names.md` L-6, load average 7): `using Accessors`
    66–74 ms on 1.10.12 and 25–36 ms on 1.13.2, against CompositionsBase 4–6 / 1.3 ms and
    ConstructionBase 16–23 / 2–8 ms (wall clock `@elapsed using`, 3 runs). A critic measured the
    same order (Accessors 48–50 / 23–24 ms). The earlier 0.1–0.5 s figures were inflated by load.
  - API and lens laws (get-set, set-get, set-set) hold on nested structs, NamedTuples, Tuples and
    composed lenses; `set`/`modify` pass `@inferred`, allocate 0 bytes and time like a hand-written
    lens. A hand-written lens is type-stable only with the field name in its type.
  - **No prisms** in Accessors or AccessorsExtra; `If` filters but cannot get or build.
    AccessorsExtra is heavy and changes `@optic` parsing globally.
  - Accessors composes optics as Base `ComposedFunction`s and re-exports CompositionsBase's `⨟`.
  - **Struct rebuild:** Accessors rebuilds through ConstructionBase's `constructorof(T) =
    Base.typename(T).wrapper`; it fails on types with non-default inner constructors or phantom
    parameters (`@set Interval(0.0).hi = 5.0` → `MethodError`) unless the type's owner defines
    `ConstructionBase.constructorof` (critic B, both versions).
  - A scratch package with its own lenses plus an Accessors extension worked both ways; Aqua found no
    piracy with `treat_as_own`. Exporting a second `set` makes a bare `set` an `UndefVarError`.
  - Only Accessors 0.1.45 was resolved and run.

## Decision

1. **Is Accessors "good enough"?** As a library, yes; as a hard dependency of the package every Chui
   package loads, no. Over ChuiCore's own hard dependencies (Compat, CompositionsBase,
   ConstructionBase) it adds 3 registered packages (Accessors, InverseFunctions, MacroTools) plus
   Dates, and measured medians of +41 ms on 1.10.12 (26 → 67 ms) and +22 ms on 1.13.2 (6 → 28 ms)
   to every `using` (L-6), and it still has no prisms, which ChuiCore must write anyway. The user
   decides at ★ Q3; this ADR proposes not depending on it.
2. ChuiCore owns a minimal optic core:
   - `Lens` focuses a **property** named in its type parameters (built from `Val` or a small
     macro): it reads with `getproperty` and writes with `ConstructionBase.setproperties`, exactly
     like Accessors' `PropertyLens`; an index lens reads with `getindex` and writes with
     `Base.setindex` (tuples) or a copy (arrays). There is no separate field (`getfield`) lens in
     v1. Getting is calling the optic, `optic(x)`, as in Accessors.
   - `Prism` for ChuiCore's sum types (ADR-0002): `preview(p, x)` returns `Some(v)` or `nothing`;
     `review(p, v)` builds the variant.
   - `ChuiCore.set(x, optic, v)` and `ChuiCore.modify(f, x, optic)` with Accessors' argument order.
   - Composition is Base's: `l₂ ∘ l₁` and `l₁ ⨟ l₂` give a `ComposedFunction`, as in Accessors;
     ChuiCore's `set`/`modify` have methods for `ComposedFunction`s of optics. ChuiCore adds no
     `opcompose`/`∘` methods for lenses.
   - All optics names are **public, not exported** (`@compat public`; ADR-0005).
   - Law kits (ADR-0007): lens get-set/set-get/set-set; prism preview-review/review-preview.
3. **Struct rebuild uses ConstructionBase's hook** (`constructorof`/`setproperties`, ADR-0008), the
   same one Accessors uses, so a type behaves the same under `ChuiCore.set` and `Accessors.set`.
   Types with non-default inner constructors or phantom parameters are supported only when their
   owner defines `ConstructionBase.constructorof`; the docs say so.
4. `ChuiCoreAccessorsExt` (weakdep, `[compat] Accessors = "0.1.45"`, the version tested) makes
   ChuiCore optics usable in `Accessors.set`/`modify`/`@set` and lets ChuiCore's functions accept
   Accessors optics; its piracy check uses Aqua's `treat_as_own`.
5. Runtime cost (documented): a type-parameterised lens get/set is a field access plus a constructor
   call, 0 bytes; a lens built from a runtime `Symbol` is type-unstable and is not the default.

## Alternatives rejected

| Alternative | Why rejected |
|---|---|
| (a) Hard-depend on Accessors and re-export it | +3 packages (+ Dates) and +22–41 ms per `using` in every Chui package; no prisms; Accessors' 0.1.x breaking changes become ChuiCore's. The ★ Q3 alternative; the fallback if ChuiFrames needs Accessors anyway. |
| (c) Own optics, no Accessors interop | Gives up interop with the most used Julia optics library for no saving over (b). |
| Own rebuild rule (default positional constructor) without ConstructionBase | Two rebuild rules for one type: `Accessors.set` honours an owner's `constructorof`, ChuiCore's would not (critic B). |
| AccessorsExtra for prism-like optics | Heavy; decides by field presence, not variant; patches `@optic` globally. |
| Export `set`/`modify` | Bare `set` becomes `UndefVarError` with Accessors loaded. |
| A field lens (`getfield` + `constructorof`) as the default | Disagrees with `setproperties` on types that overload properties (critic B, `props.jl`), so it would differ from `Accessors.set`. |
| Own `opcompose(::Lens, ::Lens)` methods | `∘` would not go through them; plain `ComposedFunction` matches Accessors. |

## Consequences

- ChuiCore writes and tests its own prisms; the prism design depends on ADR-0002.
- ConstructionBase becomes a hard dependency (ADR-0008).
- The contract's PROVISIONAL "Optics" item can name `Lens`, `Prism`, `preview`, `review`,
  `ChuiCore.set`, `ChuiCore.modify` after phase 3 (note for the lead).
- If ChuiFrames adopts Accessors as a hard dependency, this ADR is revisited.

## Verification

- `docs/research/optics.md` (+ addendum), `compositionsbase.md`, `law-kits-modules-names.md` L-6;
  critic-B scratch `phase1/critic-b/` (`rebuild.jl`, `cbdiv.jl`, both versions).
- UNVERIFIED: prism design and laws (not prototyped); Accessors versions below 0.1.45; the cause of
  InverseFunctions' compile time.

## Revisit when

- A downstream package takes Accessors as a hard dependency.
- Accessors gains prisms or drops InverseFunctions from its hard dependencies.
- Phase 4 sets a load budget under which +22–41 ms is acceptable.
