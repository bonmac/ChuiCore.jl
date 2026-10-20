# ADR-0009: ChuiCore's performance budgets: zero-allocation hot paths, a load-plus-first-call budget, a fixed benchmark set

- **Status:** Proposed (2026-10-20, phase-4 lane). The numbers come from measurements; the
  multipliers, the one-way rule (§5) and keeping the checks out of CI (§6) are policy choices for
  the user at the next ★.
- **Date:** 2026-10-20
- **Deciders:** the user at the phase-4 ★ (policy items above), the lead (the measured numbers)
- **Scope:** ChuiCore.jl

## Context

- BRIEF "Done means": the benchmarks meet *the ADR budget*. Ecosystem ADR-0011: `benchmark/
  benchmarks.jl` defines a BenchmarkTools `SUITE`, AirspeedVelocity compares PRs with `main`
  (warning-only at first), the regression tolerance is `ratchets.toml` `bench.time_tolerance`
  (0.10), and "the budgets come from each package's performance ADR". This is that ADR.
- Measurements at main b4f1ca3 (Apple M3 Pro, 12 cores, **a shared machine at load average
  8–21**: absolute numbers are inflated, ratios are what to trust; results and commands in
  `docs/src/performance.md`):
  - Allocations (one named function per case, as `test/perf_allocs_tests.jl` measures; a generic
    `@allocated f(args...)` helper reports a spurious 48–96 B when `args` holds functions):
    every built-in aggregator's `partial` (Vector, SubArray, generator), `combine`, `final`: 0 B
    on 1.13.2 and 1.10.12; `foldxl` over vectors and views with `Map`, `Filter`, `MapCat`, `Take`,
    `TakeWhile`, `Scan` and compositions: 0 B; `cata` over an own node type: 0 B; composition
    calls: 0 B. Inherent costs: `Fix` (field `Any`) ≈47 B/node; `para` ≈46–48 B/node on 1.13 and
    ≈76–80 B/node on 1.10 (1.10 boxes the `(child, result)` hole tuple; a callable struct in place
    of the closure measures the same); `foldparts`/`aggregate` ≈0.5–0.66 kB per partition (one
    task each) plus ≈0.5 kB; `Partition{T}` one vector per chunk.
  - Load and first call (warm medians of 15 fresh processes; `using` timed inside the process, so
    Julia's own 80–190 ms startup is excluded): `using ChuiCore` 12–14 ms on 1.13 and 34–40 ms on
    1.10; first call of the TTFX workload 216–253 ms (1.13), 211–271 ms (1.10); precompile of
    ChuiCore alone 0.84 s (1.13), 0.88 s (1.10).
  - With the ADR-0010 workload: load + first call 47–71 ms (1.13) and 69–89 ms (1.10);
    precompile 1.6 s (1.13; the critic saw a median of 1.86 s, max 2.44 s, at load average 20)
    and 1.4 s (1.10).

## Decision

1. **Allocation budgets** are asserted in `test/perf_allocs_tests.jl` (tag `:unit`; skipped,
   visibly, when coverage is on), on both Julia versions, after warm-up, minimum of 5 runs:
   | Hot path | Budget |
   |---|---|
   | built-in aggregators: `partial` over `Vector`/`SubArray`/generator of `Float64`, `Int` or `Bool`, `combine`, `final` | 0 B |
   | `foldxl` over a vector or view with `Map`, `Filter`, `MapCat` (tuple-returning `f`), `Take`, `TakeWhile`, `Scan`, and their compositions | 0 B |
   | `foldxl` with `Partition{T}(n)`, isbits `T` | ≤ 2·(64 + n·sizeof(T)) B per emitted chunk |
   | `aggregate` / `foldparts` / `foldxt` over `k` partitions | ≤ 1024 + 1024·k B |
   | `cata` over an own node type (`project(x) = x`), any size | ≤ 128 B per call |
   | `cata` over `Fix` | ≤ 64 B per node |
   | `para` over an own node type | ≤ 64 B per node (≤ 96 on 1.10) |
   | calling `f ⨟ g ⨟ h`, `pipe(x, fs...)`, `papply`, `flip` values on isbits arguments | 0 B |
2. **Time budgets** live in `benchmark/budgets.toml`, one table per Julia version
   (`[time."1.13"]`, `[time."1.10"]`; other versions use the 1.10 table), one row per `SUITE`
   key, and are checked by `julia benchmark/run.jl --check`, which also fails when the rows and
   the `SUITE` keys differ. Each budget is 3× that version's median at b4f1ca3, rounded up to
   1-2-5 (3× to 7.5×), with a 10 ns floor for call-overhead entries. They catch a lost
   specialization or a type instability (an order of magnitude or more; UNVERIFIED as a general
   rule), not a 10–50 % drift: that is AirspeedVelocity's job (ADR-0011, `bench.time_tolerance`).
3. **Load and TTFX budgets** (warm medians of `--runs` fresh processes, `benchmark/ttfx.jl
   --check`; `using` timed inside the process, Julia's startup excluded):
   | Measure | 1.13 (stable) | 1.10 (LTS, and other versions) |
   |---|---|---|
   | `using ChuiCore` | ≤ 75 ms | ≤ 100 ms |
   | load + first call of the TTFX workload | ≤ 150 ms | ≤ 175 ms |
   | precompile of ChuiCore alone (`Base.compilecache`) | ≤ 3.0 s | ≤ 3.0 s |
4. **Coverage of the TTFX workload** by the precompile workload is checked by
   `test/precompile_tests.jl` (`:slow`): after loading the package image, the TTFX workload
   compiles no `ChuiCore` method (`--trace-compile`). This is a *coverage* check, not a timing
   check: zero entries does not by itself mean a fast first call (§3 checks that). It runs with
   `julia scripts/ci.jl test -- slow` or `-- all`, not in the default CI test job.
5. **The benchmark set** is `benchmark/benchmarks.jl`: aggregators (`partial` per container,
   `combine`+`final`), transducer folds (`foldxl` per transducer, `aggregate` over 4 parts),
   recursion schemes (`cata` own/`Fix`, `para`, 1023 nodes), composition calls. A new hot path
   adds a `SUITE` entry and a budget row per version in the same PR. Budgets **may only tighten**
   without an amendment; loosening one needs an amendment with the measurement that forces it
   (the 1.10 `para` row is such an amendment, made before acceptance).
6. `run.jl --check`, `ttfx.jl --check` and `test -- slow` are run by the lane that changes an
   engine or the workload, and at release (`/release-check`); they are not CI jobs (a CI job is
   a T3 change, for when baselines exist on CI runners).

## Alternatives rejected

| Alternative | Why rejected |
|---|---|
| Time budgets as `@test` assertions | Wall time in the test suite flakes on shared CI runners; allocation counts do not. |
| One time table for both versions | 7–27× loose on 1.13 for some rows (critic): a 20× regression would pass. |
| Precompile ≤ 2.0 s | Measured up to 2.44 s at load average 20 on this host. |
| Zero allocations for `Fix` schemes | `Fix.unfix::Any` is deliberate (research A1, schemes.jl); a typed `Fix` recompiles per shape. |

## Consequences

- New: `benchmark/{benchmarks.jl,run.jl,ttfx.jl,budgets.toml,Project.toml}`,
  `test/perf_allocs_tests.jl`, `test/precompile_tests.jl`, `docs/src/performance.md`.
- The allocation tests are skipped in the coverage job (stable, ubuntu). So on x86-64 Linux they
  run only on LTS; on stable they run in the macOS (aarch64) job and locally.
- That coverage moves `@allocated` counts is plausible but UNVERIFIED; the skip is visible
  (`@info` and `@test_skip`).

## Verification

- `julia +release|+lts benchmark/run.jl --check`, `benchmark/ttfx.jl --check`, the A/B harness
  of the phase-4 lane, `test/perf_allocs_tests.jl`; outputs in `docs/src/performance.md`.
- Critic review 2026-10-20 (ACCEPT WITH CHANGES; findings applied).
- UNVERIFIED: the numbers on a quiet machine and on CI runners (x86-64 Linux).

## Revisit when

- A quiet-machine or CI baseline exists (tighten the TTFX and time budgets), or a downstream
  package reports a hot path missing from the set.
- AirspeedVelocity's job becomes blocking (ADR-0011).
