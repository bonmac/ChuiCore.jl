# Law-kit packaging, module layout and candidate names

- **Date:** 2026-10-20. **Author:** the phase-1 lane (run directly, not delegated).
- **Julia:** 1.10.12 (`julia +lts`) and 1.13.2 (`julia +release`), Apple Silicon.
- **Scratch:** `/private/tmp/claude-501/-Users-bonmac-personal-projects-julia-data-analysis/5c1f011c-1151-4765-9a79-8eba6d64f4e6/scratchpad/phase1/lead/`
  (`KitPkg/`, `check.jl`, `names.jl`, `names.out`). Scratch is not kept; the output is pasted below.

## L-1 Law kits as stubs plus an extension on `Test` (ADR-0007 §2 option (a))

**Question.** Can ChuiCore export `test_monoid_laws` as a method-less stub whose methods come from
an extension keyed on the `Test` stdlib, so that `using ChuiCore` never loads `Test` (CC-011), and
do `@test` results land in the caller's testset?

**Method.** A scratch package `KitPkg` with `[weakdeps] Test`, `[extensions] KitPkgTestExt = "Test"`,
a stub `function test_monoid_laws end` exported from the parent, the method defined in the extension;
also a submodule `KitPkg.Algebra` whose `combine`/`neutral` the parent re-exports. Driver:
`julia +<v> --startup-file=no check.jl <env> KitPkg`, which `Pkg.develop`s the package into a fresh
environment and runs a subprocess.

**Output** (identical on both versions apart from the timing column):
```
== lts
Test loaded after using KitPkg: false
methods before Test: 0
identity of re-exported submodule name: true
exports: [:KitPkg, :combine, :neutral, :test_monoid_laws]
methods after Test: 1
Test Summary: | Pass  Total  Time
x             |   33     33  0.2s
ext ok
== release
(same lines; Time 0.3s)
```

**Findings.**
- A stdlib (`Test`) works as a weakdep on 1.10.12 and 1.13.2; the extension loads on `using Test`.
- `using KitPkg` does not load `Test` (CC-011's check, on both versions).
- The stub is exported with 0 methods; after `using Test` it has 1. The kit's inner `@testset`
  results are counted in the caller's `@testset "x"` (33 passes reported under `x`).
- A name defined in a submodule and re-exported is the same binding (`===`), so internal
  submodules do not by themselves break a contract that names `ChuiCore.combine`.
- The two-trigger form (`Test` + Supposition) is L-4. Not run: the same check inside a downstream
  package's `test/` environment (as opposed to a scratch environment).

## L-2 Candidate names versus Base, Core and the standard libraries

**Method.** `names.jl` loads Statistics, LinearAlgebra, Dates, Random, Test, Printf, Serialization,
Distributed and SparseArrays and prints, for ~90 candidate names, the modules that export each one,
and whether Base defines it without exporting it.

**Output** (`names.out`; names not listed hit nothing):
```
1.10.12
Fix1        Symbol[] (Base defines, not exported)
Fix2        Symbol[] (Base defines, not exported)
Filter      Symbol[] (Base defines, not exported)
bind        [:Base]
Const       Symbol[] (Base defines, not exported)
Nothing     [:Core] (Base defines, not exported)
Some        [:Base]
view        [:Base]
first       [:Base]
second      [:Dates]
empty       [:Base]
1.13.2
Fix         Symbol[] (Base defines, not exported)
(the rest as on 1.10.12, except `Nothing     [:Base, :Core]`)
```

**Findings** (input to the trait-encoding ADR and to CC-010):
- **Taken by an export**, so ChuiCore must not export a new binding of them (CC-010): `bind`
  (Base, sockets), `first` (Base), `second` (Dates), `empty` (Base), `view` (Base), `Some`.
  So: monadic bind, Arrow's `first`/`second`, Alternative's `empty`, and a lens `view` need other
  names, or must be methods of the Base function on ChuiCore-owned types only.
- **Free on both versions** (exported by none of the modules above): `Fix`, `Lazy`, `Thunk`,
  `force`, `Lens`, `Prism`, `Map`, `MapCat`, `Take`, `TakeWhile`, `Partition`, `Scan`, `Reduced`,
  `reduced`, `foldxl`, `foldxt`, `Pure`, `Free`, `Coproduct`, `Sum`, `inj`, `prj`, `cata`, `ana`,
  `hylo`, `para`, `apo`, `histo`, `futu`, `fmap`, `pure`, `ap`, `neutral`, `combine`, `init`,
  `final`, `partial`, `papply`, `curry`, `pipe`, `compose`, `opcompose`, `Semigroup`, `Monoid`,
  `Functor`, `Monad`, `fold`, `foldmap`, `traverse`, `sequence`, `lift`, `complete`, `embed`,
  `project`, `Identity`, `Either`, `Left`, `Right`, `Maybe`, `Just`, `Option`, `set`, `modify`,
  `over`, `Compose`, `dimap`, `lmap`, `rmap`, `contramap`, `bimap`, `arr`, `Category`, `Arrow`,
  `Kleisli`, `@match`, `@data`, `unfix`, `alt`, `memo`.
- **Defined but unexported in Base:** `Base.Fix` (1.13.2 only; it arrived in 1.12 per the contract's
  composition item), `Base.Fix1`, `Base.Fix2`, `Base.Filter`, `Base.Const`. An exported
  `ChuiCore.Fix` does not clash, but it shares a name with `Base.Fix` (partial application) and means
  something unrelated (a recursion-scheme fixed point): a documentation hazard, not a binding conflict.
- **Internal clash inside ChuiCore:** `Sum` is already the aggregator `ChuiCore.Sum` (CC-007), so the
  coproduct of functors (Haskell's `Data.Functor.Sum`) cannot also be named `Sum`.
- **Addendum (after critic review):** `Base.Iterators` was not in the module list above. Checked
  separately on both versions:
  ```
  julia +<v> --startup-file=no -e 'for n in (:flatmap, :chain, :andthen, :mbind, :fmap, :pure,
      :traverse, :Lens, :foldm); println(n, " Iterators=", Base.isexported(Base.Iterators, n),
      " Base=", Base.isexported(Base, n)); end'
  flatmap Iterators=true Base=false          (1.10.12 and 1.13.2)
  chain / andthen / mbind / fmap / pure / traverse / Lens / foldm: false, false (both)
  ```
  So `flatmap` is taken (by `Base.Iterators`) as well. Outside the stdlib, the critic found
  `Lens` exported by Setfield and `fmap` by Functors.jl (FluxML; GitHub master source, not a tagged
  release): UNVERIFIED by this lane beyond the critic's citation. `Base.Docs.undocumented_names`
  exists on 1.13.2 but not on 1.10.12 (`isdefined(Base.Docs, :undocumented_names)`).
- Packages outside the standard library are not covered (e.g. DataFrames exports `combine`, E-38;
  Transducers exports `Map`, `Filter`, `foldxl`: see `transducers.md`).

## L-3 Submodules: what the experiment does and does not show

- Shown (L-1): re-exported submodule names keep their identity, and an extension can add methods to a
  stub owned by the top module.
- Not measured: load-time or TTFX differences between one flat module and internal submodules. No
  claim is made; the module-layout ADR decides on maintainability grounds and names a budget check
  for phase 4.

## L-4 Two-trigger extension (`Test` + Supposition), and a Supposition defect on 1.10

**Method.** `KitPkg2`: `[weakdeps] Test, Supposition`, `[extensions] KitPkg2LawsExt = ["Test",
"Supposition"]`; the extension's `test_monoid_laws(op, e, gen)` runs two `@check` properties.
Supposition 0.3.5 resolved in both scratch environments (`check2.jl`, `check2.out`).

**Output.**
```
== lts                                    == release
Supposition version: 0.3.5                Supposition version: 0.3.5
loaded Test/Supposition: Symbol[]         loaded Test/Supposition: Symbol[]
methods with Test only: 0                 methods with Test only: 0
methods with both: 1                      methods with both: 1
Test Summary: |Time                       Test Summary: | Pass  Total  Time
outer         | None  1.5s                outer         |    2      2  3.2s
```

The extension loads only when both triggers are loaded, on both versions. But on 1.10.12 the
`@check` results are **not recorded** in the enclosing testset ("None"). A deliberately false
property (`check3.jl`: `@check function bad(a = Data.Integers{Int32}()); a < 5; end` inside a
`@testset`) prints "Found counterexample … a::Int32 = 5" on both versions, but:
```
1.10 exit=0      # Test Summary: outer | None   -> the run PASSES
1.13 exit=1      # Test Summary: outer | Pass 1 Fail 1 -> the run fails
```

**Workaround, verified on both versions** (`check5.jl`, `check6.jl`): call `@check record=false …`,
which returns a `Supposition.SuppositionReport`, and assert on it with an explicit `@test`:
```julia
passed(r) = r.result isa Some && something(r.result) isa Supposition.Pass
r = @check record=false function bad2(a = Data.Integers{Int32}()); a < 5; end
@test passed(r)      # fails the testset; process exit 1 on 1.10.12 and 1.13.2
r = @check record=false function good(a = Data.Integers{Int32}()); a + zero(a) == a; end
@test passed(r)      # passes on both (Pass 1/1)
```
`passed` reads Supposition internals (`result`, `Supposition.Pass`) that are not documented API
here: UNVERIFIED as stable across Supposition releases. The root cause on 1.10 was not
investigated (UNVERIFIED; possibly how Supposition hooks `Test.record` on 1.10).

**Consequence.** Any Chui law kit or property test that relies on `@check` being recorded would pass
vacuously on the blocking LTS CI job. Kits must use the explicit-`@test` form, and a kit's own
test suite must include a planted violation that fails on 1.10 (the law-tester's "a planted
violation fails" scorecard item). This affects ADR-0007 §2 (ecosystem): a note for the lead.

## L-5 Cause of the 1.10 recording defect (critic review, confirmed by source)

- Supposition 0.3.5 defines `Test.get_test_counts(::SuppositionReport)` only under
  `@static if VERSION.major >= 1 && VERSION.minor >= 11` (its src/testset.jl, lines 37–43, read in
  the installed package). Julia 1.10.12's `Test` counts only child testsets that are
  `DefaultTestSet`s (`isa(t, DefaultTestSet)` at stdlib Test.jl lines 1226, 1244). So the defect is
  a 1.10 `Test` limitation that Supposition works around only on ≥ 1.11; a Supposition release that
  fixes 1.10 is unlikely.
- Supposition's own `results(sr)` (testset.jl lines 8–17) computes `ispass` taking `broken` into
  account; it has no docstring, so it is as internal as `report.result`.

## L-6 Load times re-measured on a quieter host

The optics note's load times were taken at load averages 58–197. Re-measured here at load average
7.0 (`uptime`), Accessors 0.1.45, ConstructionBase 1.6.0, CompositionsBase 0.1.2, InverseFunctions
0.1.18, precompiled; `t = @elapsed using P` in a fresh `julia --startup-file=no` process, 3 runs:

```
4.2 4.2 6.1  ms  lts CompositionsBase
23.1 16.9 16.0  ms  lts ConstructionBase
74.1 66.2 70.4  ms  lts Accessors
1.3 1.4 1.3  ms  release CompositionsBase
2.3 7.6 2.1  ms  release ConstructionBase
35.5 24.7 24.8  ms  release Accessors
```
(`load.out` in the scratch directory.) A critic measured 47.5–49.5 / 23.1–23.8 ms for Accessors and
14.6–14.7 / 2.1–2.6 ms for ConstructionBase at load average ~5: the same order. The earlier
"0.1–0.5 s" figures are about 10× too high; the ratio Accessors ≈ 10–20× CompositionsBase holds.

**Marginal cost of Accessors over ChuiCore's proposed hard dependencies** (load average 6.1, 5 runs,
`t = @elapsed using <set>`, `load2.out`):
```
30.7 26.5 25.2 26.1 21.8  ms  lts [Compat, CompositionsBase, ConstructionBase]
72.9 57.1 71.6 54.3 66.8  ms  lts [Compat, CompositionsBase, ConstructionBase, Accessors]
6.6 5.7 6.1 5.2 6.3  ms  release [Compat, CompositionsBase, ConstructionBase]
28.7 28.0 27.0 28.0 27.2  ms  release [Compat, CompositionsBase, ConstructionBase, Accessors]
```
Medians: 26.1 → 66.8 ms on 1.10.12 (+≈ 41 ms), 6.1 → 28.0 ms on 1.13.2 (+≈ 22 ms). Accessors adds
3 registered packages (Accessors, InverseFunctions, MacroTools) plus the Dates stdlib.

## UNVERIFIED

- Load-time effect of submodules.
- Stability of `SuppositionReport.result` and `Supposition.Pass` across Supposition releases.
- The cause of the 1.10 recording defect: now L-5 (source read, not debugged at runtime).
