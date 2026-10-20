- Phase 4 (performance pass): JET clean at the `ci.jl jet` strictness (it already was at
  b4f1ca3; no source change needed). ADR-0009 (Proposed) sets the budgets: allocation budgets
  asserted in `test/perf_allocs_tests.jl` (aggregators, transducer folds, recursion schemes,
  composition: 0 B on the hot paths), per-version time budgets in `benchmark/budgets.toml`
  (`benchmark/run.jl --check`), and load/TTFX/precompile budgets (`benchmark/ttfx.jl --check`).
- New hard dependency PrecompileTools (`"1.2"`, ADR-0010, Proposed): a precompile workload in
  `src/precompile.jl` cuts load + first call from 230 to 47 ms on Julia 1.13.2 and from 247 to
  69 ms on 1.10.12 (interleaved A/B, loaded machine). Costs: `using ChuiCore` ≈23–26 ms slower,
  precompile ≈0.84 → 1.6 s (1.13) and 0.88 → 1.4 s (1.10). `test/precompile_tests.jl` (`:slow`)
  checks that the TTFX workload compiles no ChuiCore method after load.
- Benchmark suite `benchmark/benchmarks.jl` (a BenchmarkTools `SUITE`, runnable by
  AirspeedVelocity and `scripts/ci.jl bench`), with `benchmark/Project.toml`; results, losses
  included, in the new docs page `docs/src/performance.md`.
