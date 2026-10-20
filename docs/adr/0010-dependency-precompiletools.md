# ADR-0010: Depend on PrecompileTools for a precompile workload that calls one function on opaque inputs

- **Status:** Proposed (2026-10-20, phase-4 lane)
- **Date:** 2026-10-20
- **Deciders:** the lead; the user at the next ★ (a new hard dependency)
- **Scope:** ChuiCore.jl (a dependency ADR)

## Context

- ADR-0009 budgets load plus first call. Without a workload, the first call of the TTFX workload
  costs 216–253 ms on 1.13.2 and 211–271 ms on 1.10.12 (warm medians; shared machine at load
  average 8–21), against a 12–40 ms load: compilation dominates.
- Facts (General registry, read by the lane and the critic, 2026-10-20): PrecompileTools 1.3.x
  needs Julia ≥ 1.12; 1.2.1, the last 1.2.x, allows Julia `1`. Both depend only on Preferences.
  `using PrecompileTools` alone: median ≈25 ms (19–56) on 1.13, ≈10 ms (8–16) on 1.10.
- Prototypes (interleaved A/B, 15 fresh processes each, warm medians of load + first call;
  first-call setup inside the timer in this run):
  | Variant | 1.13 | 1.10 | `--trace-compile` misses (1.13) |
  |---|---|---|---|
  | main, no workload | 324 ms | 398 ms | all |
  | PrecompileTools, workload inline at top level | 92 ms | 223 ms | 0 |
  | no dependency: `ccall(:jl_generating_output, …) == 1 && _workload()` | 108 ms | 134 ms | 4 |
  | PrecompileTools `@compile_workload _workload()` | 97 ms | 106 ms | 4 (critic) |
  The 4 misses (`foldxl`'s keyword call, `aggregate`, `partial(::Max, ::NoValue, ::Vector{Int})`,
  `final(::Max, ::Int)`) are entry points inlined into `_workload`, so a top-level call still
  compiles them.
- **The implemented variant** (row 4 plus inputs passed through `_opaque(x) = Ref{Any}(x)[]`, so
  every call is dispatched at run time as a user's top-level call is, plus `precompile(final,
  (Max, Int))` and `(Min, Int)`, which 1.13 otherwise serves from a widened `final(::Max, ::Any)`
  instance): 0 misses on both versions (`test/precompile_tests.jl`); against main in one
  interleaved A/B (setup outside the timer): **230 → 47 ms on 1.13, 247 → 69 ms on 1.10**; first
  call alone 216 → 11 ms and 211 → 9 ms; load 12 → 38 ms and 34 → 57 ms.
- Downstream ecosystem packages will likely use PrecompileTools too (UNVERIFIED until they
  exist), which would share its load cost.

## Decision

1. ChuiCore **must** depend on PrecompileTools with `[compat] PrecompileTools = "1.2"`.
2. The workload **must** live in `src/precompile.jl` as one function, `_precompile_workload()`,
   called from `@compile_workload` inside `@setup_workload`; its inputs and aggregators pass
   through `_opaque`. It uses only ChuiCore's types plus `Float64`, `Int` and their vectors and
   views. Inline top-level workloads are not used (slower on 1.10, row 2).
3. The workload covers the TTFX workload of `benchmark/ttfx.jl`; `test/precompile_tests.jl`
   checks it. A miss is fixed in the workload (an opaque call, or a named `precompile` when Julia
   widens the instance), never by dropping the call from the TTFX workload.
4. Nothing that needs a user type (recursion schemes over user functors) is in the workload.
5. Users may disable it with PrecompileTools' `precompile_workload = false` preference for
   ChuiCore (UNVERIFIED on 1.10's PrecompileTools 1.2.1 beyond its README).

## Alternatives rejected

| Alternative | Why rejected |
|---|---|
| No workload | Fails ADR-0009 §3 by 1.5–2× on both versions. |
| Dependency-free `jl_generating_output` workload | Misses entry signatures (row 3). Fallback if PrecompileTools ever becomes a problem. |
| Hand-written `precompile(...)` directives only | Brittle (signatures drift with refactors) and misses callees; used only for the two widened instances. |
| A larger workload (schemes, optics, laziness) | Each needs user types or rarely runs first; precompile time would grow for no TTFX gain. |

## Consequences

- Hard dependencies: Compat, CompositionsBase, ConstructionBase, PrecompileTools (+ Preferences).
- `using ChuiCore` costs ≈23–26 ms more (both versions, interleaved A/B; sequential runs showed
  up to +40 ms at load average 12), recovered many times over by the first call. Precompile time
  roughly doubles (0.84 → 1.6 s on 1.13, 0.88 → 1.4 s on 1.10), inside ADR-0009's 3.0 s.
- Aqua's dependency checks and ExplicitImports cover the new import.

## Verification

- Prototype copies and the A/B harness of the phase-4 lane (scratch), `benchmark/ttfx.jl`,
  `test/precompile_tests.jl` (seen failing on the misses above before the fix); results in
  `docs/src/performance.md`. Critic review 2026-10-20 (its finding 1 corrected the row-4 claim).
- UNVERIFIED: invalidations PrecompileTools or the workload cause in downstream packages.

## Revisit when

- PrecompileTools drops Julia 1.10 support in a release ChuiCore needs, or Base gains an equivalent.
- `using PrecompileTools` alone exceeds half of ChuiCore's load budget (≈38 ms on 1.13; today ≈25).
