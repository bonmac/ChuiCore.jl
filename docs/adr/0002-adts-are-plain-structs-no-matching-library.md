# ADR-0002: ADTs are plain structs with `Union` aliases; no pattern-matching library

- **Status:** Proposed
- **Date:** 2026-10-20
- **Deciders:** the user, at the phase-1 ★ checkpoint
- **Scope:** ChuiCore.jl

## Context

- The brief: "evaluate building your own versus Moshi.jl, SumTypes.jl and MLStyle.jl. Benchmark type
  stability, allocations and compile latency for each, then decide in an ADR." ChuiCore needs sums
  for recursion-scheme base functors (`ExprF`, ChuiFrames' plan nodes), free-monad instruction sets,
  and coproducts of functors. Maybe is Base's `Some{T}`/`nothing` (ADR-0001 §3); Option-like data
  types belong to ChuiTypes. Every Chui package loads ChuiCore, so load cost multiplies.
- Facts (`docs/research/adt-pattern-matching.md`, both 1.10.12 and 1.13.2; host heavily loaded, so
  timings are rough, allocations and inference are not affected):
  - Packages: Moshi 0.3.13 (2 deps; README: API "subject to change"); SumTypes 0.5.9 (3 registered
    deps: MacroTools, PrecompileTools, Preferences; plus 4 stdlibs); MLStyle 0.4.17 (0 deps, last
    release 2023-02-13, 53 open issues).
  - Hand-rolled `Union` + `isa` chain: 0 allocations, stable inference, lowest medians (1.13: 0.95 ms
    per 10^6 values with 3 variants, 1.38 ms with 6, 110 µs for the recursive fold); Moshi and
    SumTypes 0 allocations, 1.7–2.5 ms.
  - Dynamic dispatch: with 6 variants, a loop dispatching over an abstract supertype infers `Any` and
    allocates 2 per element (2,000,000 per 10^6, ~250 ms) on both versions; over a `Union`, 3 per
    element on 1.10 only, clean on 1.13. With 3 variants all is clean.
  - Critic B (scratch `critic-b/`, both versions): the trigger is the number of **applicable
    methods**, not variants. Three variants plus one fallback method on the supertype already infer
    `Any` (3,200,000 B per 10^6); with 4 variants an abstract supertype allocates on both versions,
    a `Union` on 1.10 only. Both versions report `max_methods = 3`.
  - Only hand-rolled and MLStyle allow dispatch on one variant; in Moshi and SumTypes all variants
    share one Julia type (`x isa ExprF.Add == false`), which ADR-0001's per-type tags cannot use.
  - Exhaustiveness: only SumTypes checks (at first call). For a `Union` alias a check is one line
    (`[T for T in Base.uniontypes(U) if !hasmethod(f, Tuple{T})]`, critic B, both versions), blind to
    catch-all methods; `Base.uniontypes` is internal.
  - Load: `using` ~0.1–0.3 s with a library vs < 10 ms hand-rolled (loaded host); precompile
    0.85–3.5 s vs ~0.5 s.
  - Critic B: a `Union` alias containing `Nothing` that receives Base methods (`Base.length(::Maybe)`)
    changes `length(nothing)` for everyone; Aqua flags it as piracy.
- Free-monad interpreters over open instruction sets infer `Any` and cost ~0.5–1.2 µs per
  instruction (`recursion-schemes-free-laziness.md`).

## Decision

1. ChuiCore **must not** depend on Moshi, SumTypes or MLStyle (not even as a weakdep in v1).
2. **A variant is a plain (usually immutable, parametric) struct.**
   - A **closed** sum is a `Union` alias of variants ChuiCore (or the defining package) owns, e.g.
     `const ExprF{A} = Union{Lit, Add{A}, Neg{A}}`.
   - A `Union` alias that contains a type its package does not own (`Nothing`, `Some`) **must not**
     receive methods of Base functions, and a non-owned type is a member of at most one ChuiCore sum.
   - An **open** sum (free-monad instructions, à-la-carte components, downstream plan nodes) is an
     abstract type with concrete variant structs, extended by dispatch.
3. **Closed sums in loops:** a function over a closed sum that is called in a loop over a container
   of the alias, and that has 4 or more applicable methods (fallbacks included), **must** be written
   as an explicit `isa` chain. Check: a test asserts `Base.return_types` of the loop over
   `Vector{Alias}` is concrete and the loop allocates 0 bytes, on both supported versions.
4. **Open sums accept dynamic dispatch.** Its cost is documented (2–3 allocations and ~170–270 ns per
   call in the measured 6-variant loop; ~0.5–1.2 µs per free-monad instruction). Code must not loop
   over a container of an open abstract type on a hot path; ChuiFrames-style optimizers apply rules
   per node, not in bulk loops.
5. No pattern-matching macro in v1. A small macro (variant structs, the alias, an `isa`-chain
   dispatcher) may be proposed in phase 3, only with its own measurement against these numbers.
6. **Exhaustiveness helper in v1:** a public test helper that lists the members of a closed sum's
   alias lacking a method of `f`, documented as blind to catch-all methods and relying on the
   internal `Base.uniontypes` (tested on every supported Julia).
7. **Runtime cost (documented):** a variant is a struct (no overhead); dispatch with ≤ 3 applicable
   methods on a concretely known alias is static; beyond that see Decisions 3–4, with the
   Julia-version caveat (a `Union` with 4–6 variants was clean on 1.13, not on 1.10).

## Alternatives rejected

| Alternative | Why rejected |
|---|---|
| Moshi.jl | No per-variant types (blocks ADR-0001's tags and dispatch-based coproducts); unused-parameter variants need `Lit{B}(3)` and broke `promote_op` in a fold; "API subject to change"; slowest script TTFX (4.1 s / 7.9 s). |
| SumTypes.jl | The cheapest library and the only built-in exhaustiveness check, but no per-variant types (ADR-0001's `constructorclass` needs them) and 3 registered deps in every Chui package's load path. Kept as the fallback if a library is ever needed. |
| MLStyle.jl | Per-variant dispatch, but stale (2023 release, 53 open issues), allocates in recursive folds on 1.10 (27,166 allocations), awkward no-field variants of generic types. |
| Abstract supertype + dispatch everywhere | Allocates and infers `Any` once 4 or more methods apply (critic B); kept only for open sums. |
| Defining ChuiCore's own `Maybe`/`Just` | Conflicts with ADR-0001 (Base `Some`/`nothing`) and with ChuiTypes' ownership of data types. |
| A full own pattern-matching DSL now | Large surface for no measured gain over `isa` chains. |

## Consequences

- No nested-pattern syntax; exhaustiveness only via the helper (blind to catch-alls).
- Adding a variant to a closed sum is a breaking change for that sum.
- Prisms (ADR-0004) target plain variant structs, so `preview` is an `isa` test.
- ChuiFrames' plan nodes are an open sum: per-node rewriting accepts dynamic dispatch (Decision 4).

## Verification

- `docs/research/adt-pattern-matching.md` (registry, `gh api`, Context7 `/thautwarm/mlstyle.jl`,
  installed sources, scratch `phase1/adt/out/`); `recursion-schemes-free-laziness.md`; critic-B
  scratch `phase1/critic-b/` (`methods.jl`, `thresh2.jl`, `maybe.jl`, `cbdiv.jl`, both versions).
- UNVERIFIED: why a 4–6-variant `Union` allocates on 1.10 only; why MLStyle's fold allocates on
  1.10; absolute timings; a 10+ variant `ExprF`; JET.

## Revisit when

- Julia changes `max_methods`/union-splitting defaults, or a library gains per-variant types with
  ≤ 1 dependency and < 20 ms load.
- Phase 3 finds a closed sum with ≥ 8 variants in a hot path where `isa` chains are unmanageable.
- A real user bug traces to a missed case that the helper's catch-all blind spot hid.
