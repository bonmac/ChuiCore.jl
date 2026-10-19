# ADR-0007: Law kits are exported stubs whose methods live in extensions on Test and Supposition

- **Status:** Proposed
- **Date:** 2026-10-20
- **Deciders:** the user, at the phase-1 ★ checkpoint
- **Scope:** ChuiCore.jl

## Context

- The brief asks for a reusable, **exported** law-test kit per algebraic structure. Contract CC-011
  (stable): loading ChuiCore never loads `Test` or Supposition, and neither is in `[deps]`.
  Ecosystem ADR-0007 §2 leaves ChuiCore to pick (a) an extension with exported stubs or (b) a
  separate test-utilities package. The contract's PROVISIONAL "Law kits" item recommends (a) with
  `test_*_laws(instance, gen; eq = …)` and CC-004's tolerance as the default for floats.
- Verified (`docs/research/law-kits-modules-names.md`, both 1.10.12 and 1.13.2):
  - L-1: a stdlib (`Test`) works as a weakdep; `using` the package does not load it; an exported
    stub has 0 methods until `using Test`; a kit's inner `@testset` counts in the caller's testset.
  - L-4: a two-trigger extension (`["Test", "Supposition"]`) loads only when both are loaded.
    **With Supposition 0.3.5 on Julia 1.10.12 a failing `@check` inside a `@testset` is not recorded
    and the process exits 0** (1.13.2: exit 1). `@check record=false` plus an explicit `@test` on the
    returned report fails correctly on both.
  - L-5: the cause is 1.10's `Test` counting only `DefaultTestSet` children, which Supposition works
    around only on ≥ 1.11; a Supposition fix for 1.10 is unlikely.
- Critic C (scratch `critic-c/`, both versions): Aqua 0.8.18 `test_deps_compat` requires a compat
  entry for every weakdep, stdlibs included (`[weakdeps] Test` with only `julia` compat → "missing
  weakdeps compat"); a custom `Test.AbstractTestSet` that captures results lets a test assert that a
  kit failed without failing itself (`capture.jl`, Pass 1/1 on both).
- CC-004's tolerance `τ(agg, v)` depends on the whole input `v`, so a binary `eq(r₁, r₂)` cannot
  express it (e.g. `Sum` on `[1.0, 1e16, -1e16]`, results 0.0 vs 1.0, must be accepted).

## Decision

1. ChuiCore **must** declare and export one method-less stub per kit (`test_semigroup_laws`,
   `test_monoid_laws`, `test_aggregator_laws`, `test_functor_laws`, … one per typeclass of
   ADR-0001, plus the aggregator protocol of CC-004), each with the kit's docstring.
2. **Two extensions:**
   - `ChuiCoreTestExt`, trigger `Test`: kits whose `gen` is a finite collection of samples. To bound
     cost, a kit uses at most 12 samples for 3-element laws (≤ 1,728 triples) and a fixed set of
     ordered splits (including empty chunks) for CC-004's split law, not all `2^(n-1)`.
   - `ChuiCoreSuppositionExt`, triggers `["Test", "Supposition"]`: methods for `gen` that is a
     Supposition generator (`Supposition.Data.Possibility`), with shrinking.
3. **Calling convention:** the instance comes first, as ADR-0001 §6 states: an instance value
   (`test_monoid_laws(m, gen; eq)`) or a constructor tag (`test_functor_laws(tag, gen_fa, gen_f;
   eq)`). Each kit records each law as an inner `@testset "<law name>"` holding **one `@test`**,
   carrying the first counterexample, in the caller's testset.
   - For aggregator kits `eq` takes three arguments, `eq(r₁, r₂, v)`, where `v` is the whole input
     the results came from; the default is CC-004's `≈ᵃ` for `agg` on `v`. Other kits take
     `eq(a, b)`, default `isequal`. `default_eq(instance)` is public (ADR-0005).
   - Exact signatures are settled in phase 2 and then proposed for the contract.
4. **Supposition results must be asserted explicitly:** the Supposition extension calls
   `@check record=false …` and `@test`s the report's pass state (handling `broken`, as
   Supposition's internal `results(sr).ispass` does). It never relies on `@check` recording itself.
5. **Planted violations, one per law:** each kit's own test suite runs the kit on a deliberately
   unlawful instance per law inside a capturing `Test.AbstractTestSet`, and asserts that exactly the
   inner testset named after that law holds a failure. These tests run on the LTS job.
6. `Test` and Supposition **must not** be in `[deps]`. They are in `[weakdeps]` with compat
   `Test = "1"` and `Supposition = "0.3"`.

## Alternatives rejected

| Alternative | Why rejected |
|---|---|
| (b) A separate `ChuiCoreLaws.jl` package | A fifth repo to version, register and keep in lockstep; an ecosystem ADR-0003 naming review; no gain over extensions. |
| One extension on `["Test", "Supposition"]` only | Packages that avoid Supposition (single maintainer, last release 2024-07-27) could not use the kits. |
| Kits that rely on `@check` recording | Pass vacuously on the blocking 1.10 job (L-4, L-5). |
| A binary `eq` for aggregator kits | Cannot express CC-004's input-scaled tolerance. |
| Exhaustive triples and splits | 100 samples give 10^6 triples; splits grow as `2^(n-1)`. |
| A submodule that hard-depends on Supposition | Rejected by ecosystem ADR-0007 §2; breaks CC-011. |
| Unexported kits reached through `Base.get_extension` | Clumsy for downstream users. |

## Consequences

- Exports grow by one `test_*_laws` per typeclass; each must pass ADR-0005's clash list.
- The PROVISIONAL "Law kits" item can become stable after phase 2 (note for the lead).
- **Note for the lead (ecosystem ADR-0007 §2):** the 1.10 defect affects every Chui package's
  property tests, not only ChuiCore's kits; the factory's test template should show the
  `record=false` + `@test` form, and each repo's debt register should carry it.
- The pass check reads Supposition internals (`report.result` or `results(sr)`): pinned by
  `Supposition = "0.3"` and covered by the planted-violation tests.

## Verification

- `docs/research/law-kits-modules-names.md` L-1, L-4, L-5 (`check3.jl` exit 0 on 1.10.12, exit 1 on
  1.13.2; `check5.jl`/`check6.jl` for the workaround; source lines of the cause); critic-C scratch
  `aqua.jl` (weakdep compat), `capture.jl` (planted-violation form); ecosystem ADR-0007 §2, E-13.
- UNVERIFIED: the 12-sample bound's adequacy (a judgement); stability of Supposition's internals.

## Revisit when

- The LTS moves past 1.10 (the defect then disappears).
- Supposition is abandoned or replaced (ecosystem ADR-0007's trigger).
- A downstream package needs kits outside a test environment.
