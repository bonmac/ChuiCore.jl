# Performance

Budgets: ADR-0009 (`docs/adr/0009-performance-budgets.md`); the precompile workload: ADR-0010.
This page records the phase-4 measurements, **losses included**.

**Host and caveat.** Apple M3 Pro (12 cores, 18 GB), macOS, Julia 1.13.2 and 1.10.12, one
thread. The machine was shared and loaded the whole time (load average 8–21 on 12 cores), so
absolute numbers are inflated and noisy; trust the ratios, and the interleaved A/B runs over the
sequential ones. Nothing here was measured on a quiet machine or on CI runners.

## How to reproduce

```sh
julia +release benchmark/ttfx.jl --runs 15 --check   # load, first call, precompile vs budget
julia +lts     benchmark/ttfx.jl --runs 15 --check
julia +release benchmark/run.jl --check              # the SUITE, time budgets per version
julia +lts     benchmark/run.jl --check
julia scripts/ci.jl test -- slow                     # the precompile workload covers the TTFX workload
benchpkg ChuiCore --rev=main,dirty --path=. -s benchmark/benchmarks.jl   # AirspeedVelocity (ADR-0011)
```

## Load and time to first call (ADR-0009 §3)

Interleaved A/B, 15 fresh processes per variant, warm medians [min, max]. "Load" is `using
ChuiCore` timed inside the process (Julia's own startup, 80–190 ms, excluded); "first call" is the
TTFX workload of `benchmark/ttfx.jl` after its Base-only setup.

| Julia | Variant | load | first call | load + first call | budget |
|---|---|---|---|---|---|
| 1.13.2 | main b4f1ca3 | 11.8 ms [10.2, 21.0] | 215.6 ms [184.4, 263.6] | 230.0 ms [201.6, 276.8] | 150 ms |
| 1.13.2 | phase 4 | 37.6 ms [31.8, 52.0] | 11.1 ms [6.6, 22.0] | **47.1 ms** [40.6, 74.1] | 150 ms |
| 1.10.12 | main b4f1ca3 | 34.2 ms [30.3, 41.4] | 210.5 ms [184.8, 312.7] | 247.4 ms [218.1, 347.4] | 175 ms |
| 1.10.12 | phase 4 | 57.3 ms [50.0, 73.6] | 8.6 ms [6.6, 12.7] | **68.6 ms** [57.8, 82.3] | 175 ms |

Sequential `ttfx.jl --check` runs (15 warm processes, 3 compiles; load average 10–12):

| Julia | Variant | precompile (ChuiCore alone) | cold load + first call | warm load | warm load + first call |
|---|---|---|---|---|---|
| 1.13.2 | main | 0.84 s [0.74, 0.98] | 513 + 192 ms | 14.0 ms | 272.0 ms |
| 1.13.2 | phase 4 | **1.61 s** [1.54, 1.71] (budget 3.0 s) | 559 + 9 ms | 54.7 ms (budget 75) | 70.9 ms (budget 150) |
| 1.10.12 | main | 0.88 s [0.87, 0.91] | 555 + 320 ms | 39.8 ms | 328.9 ms |
| 1.10.12 | phase 4 | **1.39 s** [1.36, 1.41] (budget 3.0 s) | 541 + 8 ms | 75.0 ms (budget 100) | 88.5 ms (budget 175) |

"Cold" is the first process after a compile; the ≈0.5 s cold load is the same before and after
(the first load of a fresh package image), so the workload does not cause it.

## Allocations (ADR-0009 §1, asserted in `test/perf_allocs_tests.jl`)

| Hot path | Budget | 1.13.2 | 1.10.12 |
|---|---|---|---|
| aggregators: `partial` (Vector, view, generator), `combine`, `final` | 0 B | 0 | 0 |
| `foldxl`: `Map`, `Filter`, `MapCat`, `Take`, `TakeWhile`, `Scan`, compositions | 0 B | 0 | 0 |
| `foldxl` + `Partition{Float64}(10)` | ≤ 288 B/chunk | 112–126 | 144–160 |
| `aggregate`/`foldparts` over k = 1, 2, 4, 8 parts | ≤ 1024 + 1024k | 992 / 1504 / 2496 / 4480 | 1152 / 1808 / 3120 / 5744 |
| `cata`, own node type, depth 4 and 8 | ≤ 128 B/call | 0 | 0 |
| `cata` over `Fix` | ≤ 64 B/node | 46.5–47.9 | 46.5–47.9 |
| `para`, own node type | ≤ 64 B/node (96 on 1.10) | 45.4–47.8 | 76.4–79.8 |
| `f ⨟ g ⨟ h`, `pipe`, `papply`, `flip` calls | 0 B | 0 | 0 |

## Benchmarks (ADR-0009 §2, `benchmark/benchmarks.jl`)

`run.jl --check` passed on both versions: 44 of 44 entries within their per-version budget
(load average 13–21 during the runs). AirspeedVelocity 0.6.6 (`benchpkg`, `--tune`) comparing
main b4f1ca3 with this branch on 1.13.2, a selection (medians ± spread; ratio = main / branch):

| Benchmark | main | branch | ratio |
|---|---|---|---|
| `partial` Sum, `Vector{Float64}` (10^4) | 0.774 μs | 0.775 μs | 1.00 |
| `partial` Mean, `Vector{Float64}` | 1.02 ± 1.4 μs | 0.776 μs | 1.32 ± 1.7 |
| `partial` Var, `Vector{Float64}` | 54.3 μs | 44.1 μs | 1.23 ± 0.43 |
| `foldxl` Map⨟Filter, Vector | 14 ± 5.2 μs | 14 ± 5 μs | 1.00 |
| `foldxl` Partition(100) | 43.7 μs | 43.4 μs | 1.01 |
| `aggregate` Sum, 4 parts | 34.6 ± 52 μs | 22.8 ± 10 μs | 1.52 ± 2.4 |
| `cata`, own node type (1023 nodes) | 18.2 μs | 17.9 μs | 1.02 |
| `cata`, `Fix` (1023 nodes) | 77 μs | 76.5 μs | 1.01 |
| `para`, own node type | 286 ± 180 μs | 167 μs | 1.71 ± 1.1 |
| `⨟` (3 functions) | 1.5 ns | 1.12 ns | 1.33 ± 0.37 |
| time to load (AirspeedVelocity's own, 5 samples) | 82 ± 80 ms | 73 ± 7 ms | 1.12 ± 1.1 |

Phase 4 changes no hot-path code, so the runtime ratios are noise (every one is within its
spread of 1.0); the full 45-row table is in the lane's evidence. Throughput on 1.13.2 (b4f1ca3):
`Sum`/`Mean` over a vector ≈0.08 ns per element, `Var` ≈4.4 ns, `foldxl` Map⨟Filter ≈1.4 ns,
`cata` ≈18 ns/node over an own node type and ≈77 ns/node over `Fix`.

## Losses and limits

- **Load time** grows by ≈23–26 ms (A/B) on both versions: PrecompileTools' own load (≈25 ms on
  1.13, ≈10 ms on 1.10) and a larger package image. Sequential runs under heavier load showed up
  to +40 ms. Net: load + first call is still 4–5× faster.
- **Precompile time** roughly doubles: 0.84 → 1.61 s (1.13), 0.88 → 1.39 s (1.10).
- **1.10 is slower on `Max`/`Min`/`Extrema`:** ≈0.56 ns per element against ≈0.07 on 1.13 (7×);
  Base's own `maximum` on 1.10 is 4.1 μs against our 5.5 μs for 10^4 elements, so no second code
  path was added.
- **`para` on 1.10** allocates ≈80 B/node against ≈48 on 1.13 (1.10 boxes the hole tuple).
- **`Fix` trees** cost ≈47 B and ≈77 ns per node, 4× an own node type; by design (ADR, research A1).
- **`aggregate`/`foldparts`** pay ≈0.5–0.66 kB and a task per partition: use few, large partitions.
- **Not precompiled:** recursion schemes, optics and laziness over user types (they need the
  user's types), so their first call still compiles.
- Turn the workload off with PrecompileTools' preference `precompile_workload = false` for ChuiCore.
