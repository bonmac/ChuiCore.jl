# Phase 4 design: performance pass (JET, allocation and TTFX budgets, PrecompileTools)

- **Date:** 2026-10-20. **Branch:** `feat/phase4-perf` (from main b4f1ca3). **Tier:** T2 (a new hard
  dependency, `Project.toml`). **Brief:** `docs/agent/BRIEF.md` Phases §4 and "Done means".
- **Decisions:** ADR-0009 (budgets, benchmark set), ADR-0010 (PrecompileTools). Ecosystem ADR-0011
  (AirspeedVelocity, warning-only benchmark CI).

## Goals

1. JET clean at the strictness of `julia scripts/ci.jl jet` (`JET.test_package(ChuiCore;
   target_modules = (ChuiCore,))`, default mode). Measured clean at b4f1ca3 before any change.
2. Allocation budgets asserted in tests for: the aggregators' `partial`/`combine`/`final`;
   transducer folds over chunks (`foldxl`, `foldparts`, `foldxt`, `aggregate`); recursion schemes
   over small trees (`cata`, `para`); composition calls.
3. Load, first-call (TTFX) and precompile times measured on 1.13.2 and 1.10.12, cold and warm,
   with medians and spreads, before and after; losses published.
4. A PrecompileTools workload bringing load + first call under budget on both versions.
5. `benchmark/benchmarks.jl` (`SUITE`) runnable by AirspeedVelocity and `scripts/ci.jl bench`.

## Non-goals

- `ChuiCoreTransducersExt` stays deferred (ADR-0003 §8): it needs Transducers.jl and its
  dependencies in the test environment and has no consumer; it would not change ChuiCore's own load
  time (an extension loads only with Transducers), but it is not a performance item.
- Making the benchmark CI job blocking (ADR-0011: a later T3 change).
- Speeding up paths that already meet their budget (measure first: no change without a number).

## Design

| Piece | File | Notes |
|---|---|---|
| Workload | `src/precompile.jl` | `_precompile_workload()` called from `@compile_workload`; inputs made type-opaque so entry points compile as top-level calls do |
| Trace check | `test/precompile_tests.jl` (`:slow`) | fresh process, `--trace-compile`, no `ChuiCore.` line after the TTFX workload |
| Allocation budgets | `test/perf_allocs_tests.jl` (`:unit`), `benchmark/allocs.jl` (prints the numbers) | one zero-argument closure per case over local values; skipped under coverage |
| Benchmark suite | `benchmark/benchmarks.jl`, `benchmark/Project.toml` | public API only, so it runs on the merge base |
| Report and time budgets | `benchmark/run.jl`, `benchmark/budgets.toml` | `--check` compares medians with `[time]` |
| TTFX | `benchmark/ttfx.jl` | fresh processes, a scratch depot stacked first, `--check` against `[ttfx.*]` |
| Results | `docs/src/performance.md` | the budget table, before/after, losses |

## Testing

- `julia scripts/ci.jl test` on 1.13.2 and 1.10.12; `test -- all`; `quality`; `jet`; `format`;
  `guards`; `docs`; `dod.jl --base b4f1ca3`.
- The trace check was seen failing on real misses (three entry signatures, then a widened
  `final(::Max, ::Any)` instance) before the workload was fixed.
