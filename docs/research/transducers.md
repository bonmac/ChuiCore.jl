# Research: the transducer substrate

Date: 2026-10-20. Lane: phase1-research (researcher). Status: evidence for ChuiCore's
transducer ADR; nothing here is a decision.

## Question

Ecosystem ADR-0002 §4 says ChuiCore owns the one transducer substrate as its own small
implementation, with the prototype's names, and talks to Transducers.jl only through a
`ChuiCoreTransducersExt` extension. ChuiCore's own ADR designs it. This note answers:

1. What Transducers.jl's API and protocol look like (version, dependencies, stateful
   transducers in parallel folds).
2. What Clojure's transducer semantics require (the three arities, early termination, state).
3. Where the prototype substrate (`reference/prototype/Tidy.jl` lines 13-71, `TakeRows`
   lines 614-626) falls short, and what a minimal Julian design that fixes this looks like,
   shown with code that runs.
4. Benchmarks on Julia 1.10.12 and 1.13.2: prototype, minimal design, Transducers.jl, Base.
5. Interop: what `ChuiCoreTransducersExt` would need, and whether ChuiCore should export the
   names that Transducers.jl also exports.

Consumers to keep in mind: ChuiTypes streams (possibly unbounded and effectful) and ChuiFrames
execution (partitioned parallel folds using the CC-004 aggregator protocol `init` factory,
`partial`, `combine`, `final`, plus CC-005 `iscommutative`, with combination in partition
order).

## Method

- **Context7 first.** `resolve-library-id` for "Transducers.jl", "JuliaFolds Transducers" and
  "Transducers" returned no Transducers.jl entry (only CUDA.jl, ChunkSplitters.jl,
  OhMyThreads.jl, Clojure's xforms, and similar). So no Context7 source exists for it. I used
  the package source instead (docstrings in core.jl, reduce.jl and library.jl under the `src`
  directory of the installed Transducers 0.4.85) and ran the behaviour.
- **Clojure:** the official reference page <https://clojure.org/reference/transducers>, fetched
  2026-10-20 (the page header says "Published 2026-10-16").
- **Code:** everything ran in a scratch directory outside the repo:
  `/private/tmp/claude-501/-Users-bonmac-personal-projects-julia-data-analysis/5c1f011c-1151-4765-9a79-8eba6d64f4e6/scratchpad/phase1/transducers/`
  (called `$S` below), with separate environments `$S/env110` (Julia 1.10.12, `julia +lts`)
  and `$S/env113` (Julia 1.13.2, `julia +release`). Both have Transducers 0.4.85,
  BenchmarkTools 1.8.0 and CompositionsBase 0.1.2. All runs used `--startup-file=no`, and the
  threaded runs used `-t 4`.
- **Prototype:** I copied `Tidy.jl` lines 13-71 verbatim into `$S/proto.jl` (module `Proto`),
  changing only `hastake` to drop `TakeRows`, which needs tables. Nothing ran in
  `reference/prototype`.
- **Minimal design:** `$S/mini.jl` (module `Mini`, about 200 lines including the aggregator
  bridge), with checks in `$S/mini_checks.jl`.
- **Machine:** Apple M3 Pro, 12 cores. **The machine was heavily loaded** (load average 55-76
  during the benchmark runs, from `uptime`), so absolute times are noisy. Two runs per version
  are pasted below. Read them for allocation counts and order of magnitude, not for a ranking
  within about 30%.

## Results

### R1. Transducers.jl version and dependencies

```
$ julia +release --project=$S/env113 $S/deps.jl
direct: 14 (non-stdlib: 11)
transitive: 42 total; registered non-stdlib: 20
Accessors@0.1.45, ArgCheck@2.5.0, BangBang@0.4.9, Baselet@0.1.1, CompositionsBase@0.1.2, ConstructionBase@1.6.0, DataAPI@1.16.0, DataValueInterfaces@1.0.0, DefineSingletons@0.1.2, InitialValues@0.3.1, InverseFunctions@0.1.18, IteratorInterfaceExtensions@1.0.0, MacroTools@0.5.16, MicroCollections@0.2.0, OrderedCollections@2.0.3, Setfield@1.1.2, SplittablesBase@0.1.15, StaticArraysCore@1.4.4, TableTraits@1.0.1, Tables@1.14.0
```

`Project.toml` of Transducers 0.4.85 (installed source): `[deps]` has Accessors, ArgCheck,
BangBang, Baselet, CompositionsBase, ConstructionBase, DefineSingletons, InitialValues,
MicroCollections, SplittablesBase and Tables (11 registered), plus the stdlibs Distributed,
Logging and Markdown. The compat floor is `julia = "1.10"`. It has six weak-dependency
extensions (Adapt, BlockArrays, DataFrames, LazyArrays, OnlineStatsBase, Referenceables).
**This confirms ADR-0002 §4 / E-27: 11 direct registered dependencies and about 20
transitive.**

Load time, fresh process:

```
## julia +lts (1.10.12)
@time using Transducers:
  0.443109 seconds (280.82 k allocations: 23.304 MiB, 33.76% compilation time)
## julia +release (1.13.2)
@time using Transducers:
  0.364269 seconds (199.89 k allocations: 15.597 MiB)
```

### R2. Transducers.jl API behaviour (`$S/tx_api.jl`, `$S/tx_api2.jl`, Julia 1.13.2, 4 threads)

```
Julia 1.13.2 Transducers 0.4.85 nthreads=4
foldxl(+, 1:10 |> Map(x->2x) |> Filter(iseven))                => 110
(Map(x->x+1) ⨟ Filter(iseven)) order: collect(xf, 1:6)         => [2, 4, 6]
(Filter(iseven) ∘ Map(x->x+1)) collect 1:6                     => [2, 4, 6]
collect(MapCat(x->1:x), 1:3)                                   => [1, 1, 2, 1, 2, 3]
collect(Take(3), 1:10)                                         => [1, 2, 3]
collect(TakeWhile(<(4)), 1:10)                                 => [1, 2, 3]
collect(Partition(3) ⨟ Map(copy), 1:8)                         => [[1, 2, 3], [4, 5, 6]]
collect(Partition(3; flush=true) ⨟ Map(copy), 1:8)             => [[1, 2, 3], [4, 5, 6], [7, 8]]
collect(Scan(+), 1:5)                                          => [1, 3, 6, 10, 15]
collect(Enumerate(), [:a,:b])                                  => [(1, :a), (2, :b)]
foldxl((a,x)-> x>3 ? reduced(a) : a+x, 1:10)                   => 6
foldxl(+, eduction(Map(abs2), 1:4))                            => 30
typeof(eduction(Map(abs2), 1:4))                               => :Eduction
foldxt(+, 1:10^6 |> Map(x->2x); basesize=1000)                 => 1000001000000
foldxt(+, 1:10^6 |> Take(5); basesize=1000)                    => 15
foldxt(+, 1:100 |> Filter(isodd) |> Take(5); basesize=10)      => ERROR Stateful transducer Take(5) does not support `combine`
foldxt(+, 1:100 |> Scan(+); basesize=10)                       => ERROR Stateful transducer Scan(+) does not support `combine`
foldxl(+, 1:100 |> Scan(+))                                    => 171700
foldxt(right, 1:100 |> Partition(7) |> Map(sum); basesize=10)  => ERROR Stateful transducer Partition(7, 7, false) does not support `combine`
foldxt(+, 1:100 |> TakeWhile(<(50)); basesize=10)              => 1225
foldxt(+, 1:100 |> Enumerate() |> Map(first); basesize=10)     => ERROR Stateful transducer Enumerate(1, 1) does not support `combine`
foldxd(+, 1:100 |> Map(x->2x))                                 => 10100
foldxl(Completing((a,x)->a+x), 1:4; init=0)                    => 10
foldxl(+, Map(identity), Int[])  (empty, no init)              => ERROR EmptyResultError: Reducing function `+` is never called.
foldxl(+, Filter(iseven), [1,3]; init=0)                       => 0
Transducers.start/next/complete on Map ∘ +                     => 6
Take state: typeof(start((Take(2))'(+), 0))                    => Transducers.PrivateState{Transducers.Reduction{Take, Transducers.BottomRF{typeof(+)}}, Int64, Int64}
---
opcompose(Map(f), Filter(iseven)) == Map(f) ⨟ Filter(iseven)           => true
Map(f) ⨟ Filter(iseven) == Filter(iseven) ∘ Map(f)                     => true
foldxt(whencombine(append!!, push!!), Map(identity), 1:5; init=OnInit(()->Int[]), basesize=2) => [1, 2, 3, 4, 5]
foldxt with Filter(isodd)|>Take(5) basesize=1000                       => 25
foldxt(+, 1:10^6 |> Take(5000); basesize=1000)                         => ERROR Stateful transducer Take(5000) does not support `combine`
foldxt(+, (1:100) |> Partition(7; flush=true) |> Map(sum); basesize=1000) => 5050
foldxt((a,x)-> x==500 ? reduced(x) : a, 1:10^6; init=0, basesize=1000) => 500
```

(The first-script line `opcompose(...) == ⨟ => false` came from two different anonymous
functions. With a named `f` it is `true`, as shown in the second block.)

### R3. Prototype gaps, demonstrated (`$S/proto_gaps.jl`)

```
Julia 1.13.2
same rf, fold 1: 3   fold 2: 0   (expected 3, 3)
closure field types of Take(2)(+): (Take, typeof(+), Base.RefValue{Int64})
no completion: rf has no 1-arg method: false
foldxt with Take falls back to sequential: 15
Julia 1.10.12
same rf, fold 1: 3   fold 2: 0   (expected 3, 3)
```

The benchmark (R5) also shows the prototype `foldxt` allocating 8,002,880 bytes (1.10) and
8,014,048 bytes (1.13) per call on a 10^6 `Float64` vector, because it runs `collect(itr)`
before batching.

### R4. Minimal design checks (`$S/mini_checks.jl`; full code in `$S/mini.jl`)

```
Julia 1.10.12 nthreads=4
semantics ok
rf reuse ok
typeof(xf(+)) = Main.Mini.R{Map{typeof(f)}, Main.Mini.R{Filter{typeof(p)}, Main.Mini.Bottom{typeof(+)}}}
@inferred ok
@allocated Vector{Float64}: 16
@allocated 1:10^6:          0
@allocated with Take(1000): 16
parallel ok
-----
Julia 1.13.2 nthreads=4
semantics ok
rf reuse ok
typeof(xf(+)) = Main.Mini.R{Map{typeof(f)}, Main.Mini.R{Filter{typeof(p)}, Main.Mini.Bottom{typeof(+)}}}
@inferred ok
@allocated Vector{Float64}: 0
@allocated 1:10^6:          0
@allocated with Take(1000): 0
parallel ok
```

The 16 bytes on 1.10 come from calling `@allocated` at top level with non-`const` globals,
which boxes the `Float64` result. Measured inside a function (R5, `allocs_of`), the same
pipeline allocates 0 bytes on 1.10 as well. `code_warntype` for
`next(::R{Map,R{Filter,Bottom{+}}}, ::Float64, ::Float64)` shows `Body::Float64`, with every
field a `Core.Const`.

What the checks cover (all `@test`, all passed on both versions):

- Order: `Map(x->x+1) ⨟ Filter(iseven)` over `1:6` gives 2+4+6, and
  `Map(f) ⨟ Filter(p) == Filter(p) ∘ Map(f)`.
- `MapCat`, `Take`, `TakeWhile`, `Scan(+, 0)`.
- `Partition(3)` with flush gives `[[1,2,3],[4,5,6],[7,8]]` (completion step), and without
  flush gives `[[1,2,3],[4,5,6]]`.
- `Partition(3) ⨟ Take(1)` gives `[[1,2,3]]`: no flush after the downstream reduced.
- `Take(2) ⨟ Partition(3)` gives `[[1,2]]`: flush after the upstream reduced.
- Early termination from the bottom function, via `reduced`.
- A reducing function can be reused: two folds with the same `Take(2)(+)` both give 3. This
  is the fix for R3.
- `@inferred` holds for `next`, for `foldxl` over `Vector{Float64}` and over `1:10^6`, and for
  a pipeline that contains `Take`.
- Parallel: `foldxt` equals `foldxl`, and the aggregator bridge `foldxt(Sum(), xf, v)` equals
  it too. `foldxt(First(), Filter(>(500)), 1:10^6; ntasks=8) == 501` (non-commutative, so
  combined in partition order). Collecting with `combine = append!` keeps order. Early
  termination at element 600_000 is exact. Stateful pipelines (`Take(5)`,
  `Filter(isodd) ⨟ Take(5000)`, `Scan`) fall back to sequential and give the sequential answer.

### R5. Benchmarks: map → filter → sum, 10^6 elements (`$S/bench.jl`)

The pipeline is `f(x) = 2x`, `p(x) = x > 1.0` over `rand(10^6)` (seed 1); for `1:10^6` the
filter is `x % 3 == 0`. Every implementation gives the same result (`@assert` in the script).
"Base iter" is `sum(Iterators.filter(p, Iterators.map(f, v)); init=0.0)`, and "Base
mapreduce" is `mapreduce(f, +, Iterators.filter(x->p(f(x)), v); init=0.0)`. (The brief's
`sum(x->f(x), Iterators.filter(p, v))` filters *before* mapping, so it is a different
pipeline. Both forms here filter on the mapped value.) Median of 200 samples with
`evals=1`; `allocs(BT)` is BenchmarkTools' allocation count, and `@allocated` is bytes after
warm-up inside a function.

Run 1:

```
Julia 1.10.12 Transducers 0.4.85 BenchmarkTools 1.8.0 nthreads=4
case                              median        allocs(BT)  @allocated
proto  foldxl  Vector{Float64}    1.350 ms      0           0
mini   foldxl  Vector{Float64}    1.250 ms      0           0
Tx.jl  foldxl  Vector{Float64}    1.239 ms      0           0
Base sum(filter(map))  Vector     1.242 ms      0           0
Base mapreduce  Vector            1.234 ms      0           0
hand-written loop  Vector         1.142 ms      0           0
proto  foldxl  1:10^6             735.771 μs    0           0
mini   foldxl  1:10^6             618.646 μs    0           0
Tx.jl  foldxl  1:10^6             1.006 ms      0           0
Base sum(filter(map))  1:10^6     661.792 μs    0           0
proto  foldxt  Vector (4 thr)     962.875 μs    43          8002880
mini   foldxt  Vector (4 thr)     723.105 μs    33          2672
Tx.jl  foldxt  Vector (4 thr)     497.021 μs    22          1744
-----
Julia 1.13.2 Transducers 0.4.85 BenchmarkTools 1.8.0 nthreads=4
case                              median        allocs(BT)  @allocated
proto  foldxl  Vector{Float64}    1.868 ms      0           0
mini   foldxl  Vector{Float64}    1.788 ms      0           0
Tx.jl  foldxl  Vector{Float64}    1.978 ms      0           0
Base sum(filter(map))  Vector     2.181 ms      0           0
Base mapreduce  Vector            2.298 ms      0           0
hand-written loop  Vector         1.980 ms      0           0
proto  foldxl  1:10^6             564.980 μs    0           0
mini   foldxl  1:10^6             350.438 μs    0           0
Tx.jl  foldxl  1:10^6             256.854 μs    0           0
Base sum(filter(map))  1:10^6     480.541 μs    0           0
proto  foldxt  Vector (4 thr)     1.253 ms      46          8014048
mini   foldxt  Vector (4 thr)     596.896 μs    35          2048
Tx.jl  foldxt  Vector (4 thr)     674.250 μs    22          1264
```

Run 2 (load average 55-76 before and 70-76 after):

```
Julia 1.13.2 Transducers 0.4.85 BenchmarkTools 1.8.0 nthreads=4
proto  foldxl  Vector{Float64}    2.782 ms      0           0
mini   foldxl  Vector{Float64}    2.196 ms      0           0
Tx.jl  foldxl  Vector{Float64}    1.941 ms      0           0
Base sum(filter(map))  Vector     1.842 ms      0           0
Base mapreduce  Vector            1.935 ms      0           0
hand-written loop  Vector         1.928 ms      0           0
proto  foldxl  1:10^6             293.146 μs    0           0
mini   foldxl  1:10^6             601.979 μs    0           0
Tx.jl  foldxl  1:10^6             542.042 μs    0           0
Base sum(filter(map))  1:10^6     631.104 μs    0           0
proto  foldxt  Vector (4 thr)     2.897 ms      46          8014048
mini   foldxt  Vector (4 thr)     1.382 ms      35          2048
Tx.jl  foldxt  Vector (4 thr)     914.938 μs    22          1264
Julia 1.10.12 Transducers 0.4.85 BenchmarkTools 1.8.0 nthreads=4
proto  foldxl  Vector{Float64}    1.278 ms      0           0
mini   foldxl  Vector{Float64}    1.331 ms      0           0
Tx.jl  foldxl  Vector{Float64}    1.511 ms      0           0
Base sum(filter(map))  Vector     1.502 ms      0           0
Base mapreduce  Vector            1.342 ms      0           0
hand-written loop  Vector         1.166 ms      0           0
proto  foldxl  1:10^6             676.583 μs    0           0
mini   foldxl  1:10^6             433.062 μs    0           0
Tx.jl  foldxl  1:10^6             491.125 μs    0           0
Base sum(filter(map))  1:10^6     680.396 μs    0           0
proto  foldxt  Vector (4 thr)     1.446 ms      43          8002880
mini   foldxt  Vector (4 thr)     557.438 μs    33          2672
Tx.jl  foldxt  Vector (4 thr)     352.084 μs    22          1744
```

Fresh-process TTFX, three processes each (`$S/ttfx_*.jl`). "load" is `include` of the
scratch module (or `using Transducers`), and "first" is the first `foldxl` call:

```
## julia +lts
proto load(include)=0.084s first foldxl=0.529s
proto load(include)=0.196s first foldxl=0.258s
proto load(include)=0.052s first foldxl=0.355s
mini  load(include+CompositionsBase)=0.141s first foldxl=0.109s
mini  load(include+CompositionsBase)=0.17s first foldxl=0.056s
mini  load(include+CompositionsBase)=0.106s first foldxl=0.058s
Tx.jl using Transducers=0.341s first foldxl=0.102s
Tx.jl using Transducers=0.444s first foldxl=0.259s
Tx.jl using Transducers=0.353s first foldxl=0.374s
Base  first sum(filter(map))=0.036s
Base  first sum(filter(map))=0.087s
Base  first sum(filter(map))=0.043s
## julia +release
proto load(include)=0.1s first foldxl=0.28s
proto load(include)=0.14s first foldxl=0.157s
proto load(include)=0.047s first foldxl=0.138s
mini  load(include+CompositionsBase)=0.118s first foldxl=0.079s
mini  load(include+CompositionsBase)=0.243s first foldxl=0.063s
mini  load(include+CompositionsBase)=0.241s first foldxl=0.093s
Tx.jl using Transducers=0.431s first foldxl=0.106s
Tx.jl using Transducers=0.668s first foldxl=0.28s
Tx.jl using Transducers=0.626s first foldxl=0.108s
Base  first sum(filter(map))=0.13s
Base  first sum(filter(map))=0.072s
Base  first sum(filter(map))=0.114s
```

The scratch modules are `include`d, so they are **not precompiled**. A real ChuiCore with a
`PrecompileTools` workload would load and run its first call differently. That case was not
measured.

### R6. Name clashes with Transducers.jl (`$S/clash.jl`, `$S/clash2.jl`)

A module `ChuiCoreLike` exports its own `Map`, `Filter` and `foldxl`, and re-exports
CompositionsBase's `⨟`. Then `using .ChuiCoreLike, Transducers`:

```
WARNING: both Transducers and ChuiCoreLike export "Map"; uses of it in module Main must be qualified
WARNING: both Transducers and ChuiCoreLike export "foldxl"; uses of it in module Main must be qualified
WARNING: both Transducers and ChuiCoreLike export "Filter"; uses of it in module Main must be qualified
Julia 1.10.12
Map(identity)                                => UndefVarError: UndefVarError: `Map` not defined
foldxl(+, 1:3)                               => UndefVarError: UndefVarError: `foldxl` not defined
Filter(iseven)                               => UndefVarError: UndefVarError: `Filter` not defined
(⨟) === Transducers.:⨟                       => true
ChuiCoreLike.:⨟ === Transducers.:⨟           => true
Base.isexported(ChuiCoreQualified, :Map)     => false
isdefined(Base, :ispublic) ? Base.ispublic(ChuiCoreQualified, :Map) : :no_ispublic => :no_ispublic
1.10.12: Map(identity) => Map(identity) ; ⨟ === Transducers.:⨟ => true
-----
Julia 1.13.2
Map(identity)                                => UndefVarError: UndefVarError: `Map` not defined in `Main`
Hint: It looks like two or more modules export different bindings with this name, resulting in am
foldxl(+, 1:3)                               => UndefVarError: ...
Filter(iseven)                               => UndefVarError: ...
(⨟) === Transducers.:⨟                       => true
ChuiCoreLike.:⨟ === Transducers.:⨟           => true
Base.isexported(ChuiCoreQualified, :Map)     => false
isdefined(Base, :ispublic) ? Base.ispublic(ChuiCoreQualified, :Map) : :no_ispublic => true
1.13.2: Map(identity) => Map(identity) ; ⨟ === Transducers.:⨟ => true
```

On 1.13.2 no warning is printed; the clash shows only at the use. This matches E-37 in the
contract. `ChuiCoreQualified` (no export of `Map`; `public Map, foldxl` on ≥ 1.11 through
`@static if VERSION >= v"1.11" eval(Meta.parse("public ..."))`) loads next to Transducers
without any clash on both versions. `⨟` never clashes, because both packages hold the
CompositionsBase binding.

### R7. A real package extension (`$S/ChuiCoreLike/`, `$S/extcheck.jl`)

This is a scratch package whose `[weakdeps]` holds Transducers and whose
`[extensions] ChuiCoreLikeTransducersExt = "Transducers"` (code in
`$S/ChuiCoreLike/ext/ChuiCoreLikeTransducersExt.jl`). It is developed into `$S/envext_+lts`
and `$S/envext_+release`.

```
Julia 1.10.12; ext loaded before Transducers? false
ext loaded after `using Transducers`? true
totransducers: Map(Main.λ❓) ⨟ Filter(iseven) ⨟ Take(3)
Transducers.foldxl on ChuiCore xf: 12 vs ChuiCore: 12
Transducers.foldxt stateless: 1000001000000
-----
Julia 1.13.2; ext loaded before Transducers? false
ext loaded after `using Transducers`? true
totransducers: Map(Main.λ❓) ⨟ Filter(iseven) ⨟ Take(3)
Transducers.foldxl on ChuiCore xf: 12 vs ChuiCore: 12
Transducers.foldxt stateless: 1000001000000
```

## Findings with sources

### F1. Transducers.jl 0.4.85 (source: installed package, `Project.toml` and `src/`; behaviour R2)

- **Types.** `abstract type Transducer` (`core.jl:188`), with `AbstractFilter <: Transducer`
  for filter-like ones (`core.jl:189`). A reducing function is
  `Reduction{X<:Transducer, I} <: AbstractReduction{I} <: Function` (`core.jl:252, 305`), a
  struct holding `xform` and `inner`. The bottom is `BottomRF`. `xf'(op)` builds the reducing
  function (R2, last lines).
- **Protocol** (`core.jl:440-560`, docstrings):
  - `start(rf, init)` is optional. Stateful transducers bundle private state into the
    accumulator with `wrap(rf, state, start(inner(rf), result))`. The docstring says this has
    "no related API in Clojure" and is based on the C++ library atria.
  - `next(rf, result, input)` is the only required method.
  - `complete(rf, result)` is optional. It is "the last chance to flush". If `start` wrapped,
    `complete` **must** `unwrap` before handing on.
  - `combine(rf, a, b)` is optional. Stateful transducers must define it to support `foldxt`.
    The default errors: `"Stateful transducer … does not support combine"` (`core.jl:564-576`).
- **State threading.** `wrap`, `unwrap`, `wrapping(f, rf, result)` and the type
  `PrivateState{RF, State, Result}` (R2 shows
  `PrivateState{Reduction{Take,…}, Int64, Int64}`). `wrap(rf, state, iresult::Reduced)`
  *drops* the private state (`core.jl:704`).
- **Early termination.** `Reduced{T}`, `reduced(x)`, `unreduced` (`core.jl:48-93`). `Take`
  calls `reduced(complete(inner(rf), iresult))` when it terminates, so the inner
  reducing function is completed **inside** `next` (`library.jl:440-453`).
- **Composition.** `Base.:∘(g::Transducer, f::Transducer) = Composition(f, g)`
  (`core.jl:381`). `⨟`/`opcompose` come from CompositionsBase (`Transducers.jl:91`), where
  `opcompose(fs...) = ∘(reverse(fs)...)`. So `Map(f) ⨟ Filter(p) == Filter(p) ∘ Map(f)`, and
  both mean "map, then filter" on the data (R2).
- **Init.** `Completing(op)` adds a 1-argument completion to a binary op. `OnInit(f)` is an
  init *factory* (R2: it works with `foldxt` through `whencombine(append!!, push!!)`).
  Without `init`, an empty or fully filtered input throws `EmptyResultError` (R2). That uses
  the InitialValues.jl machinery that the minimal design leaves out.
- **Folds.** `foldxl` (sequential), `foldxt` (threads; "the bottom reduction function … must
  be associative and `init` must be its identity element … Transducers composing `xf` must be
  stateless … except for ScanEmit. Note that Scan is not supported", `reduce.jl:1-13`),
  `foldxd` (Distributed). `eduction(xf, itr)` builds a lazy foldable `Eduction`.
- **Stateful transducers in `foldxt`: the result depends on the data.** `Take`, `Scan`,
  `Partition` and `Enumerate` error with "does not support combine" whenever two non-reduced
  chunk results must be combined. `Take(5)` over `1:10^6` *succeeds* (15), because the first
  chunk reaches `Reduced` and `wrap` drops the state, while `Take(5000)` errors. Input smaller
  than `basesize` runs sequentially and succeeds (R2). It never returned a silently wrong
  answer in these probes, but whether a call errors depends on `basesize` and the data.
- Exported names that overlap the prototype: `Map`, `Filter`, `MapCat`, `Take`, `TakeWhile`,
  `Partition`, `Scan`, `Enumerate`, `Reduced`, `reduced`, `unreduced`, `foldxl`, `foldxt`,
  `foldxd`, `eduction`, `opcompose`, `⨟`, `Completing`, `OnInit` (export list,
  `Transducers.jl:3-78`). It also exports `Count`, which clashes with the CC-007 aggregator
  name `Count` if ChuiCore ever exports that.

### F2. Clojure semantics (clojure.org/reference/transducers, fetched 2026-10-20)

- **Three arities.**
  - Init (arity 0) "should call the init arity on the nested transform rf".
  - Step (arity 2) is a standard reduction step that may call the nested step zero or more
    times.
  - Completion (arity 1) produces the final value or flushes state, and "must call the rf
    completion arity exactly once".
- **Early termination.** `reduced`, `reduced?` and `deref`. A step that runs a nested reduce
  must "check for and convey reduced values". The process stops supplying input after a
  reduced value, and **completion still runs** on the dereferenced value.
- **Stateful transducers.** State is created when the transducer is applied to `rf` (a
  `volatile!` per application). A stateful transducer "should flush state prior to calling the
  nested transformer's completion function". `partition-all` is the flush example.
- **Composition.** `comp` composes right-to-left as functions, "but builds a transformation
  stack that runs left-to-right". So `(comp (map f) (filter p))` means map first. Julia's
  `Filter(p) ∘ Map(f)` / `Map(f) ⨟ Filter(p)` reads the other way round, so it matches
  `->>`-style reading only with `⨟`.
- **No init.** `transduce` uses `(f)` (the 0-arity of the reducing function) when no init is
  given.

### F3. Prototype gaps (source: `Tidy.jl` 13-71, 614-626; DESIGN.md §3.5, §5 bug 2; R3, R5)

1. **No completion.** A reducing function is a 2-argument closure with no 1-argument method
   (R3). So `Partition` with flush, `Scan` with a final emit, a `TakeLast`, or any
   per-stream "finish" cannot be expressed. ChuiTypes streams need exactly this, for example
   windowing an unbounded stream and flushing on close.
2. **State lives in a `Ref` captured when `xf(rf)` is built**, not when a fold starts.
   - A reducing function cannot be reused: the second fold with the same `Take(2)(+)` returns 0
     instead of 3 (R3).
   - Sharing one built reducing function across tasks would race on the counter.
   - The prototype avoids the race only because `foldxl` calls `xf(rf)` again per task. That
     also gives one counter per batch, which was DESIGN.md §5 bug 2. The fix was to run any
     plan containing `Take`/`TakeRows` sequentially (`hastake`).
3. **`foldxt` collects its input** (`parts = collect(itr)`). That is 8 MB per call on 10^6
   `Float64` (R5) and impossible for an unbounded stream. It also uses `reduce(combine, …)`
   over fetched results, which is in partition order (good), but it does not stop on an
   early `Reduced` in a middle batch: a `Reduced` from one batch is not unwrapped before
   `combine`. (The prototype only reaches this with `MapCat` plus a user `reduced`, since
   `Take` plans go sequential. Read from the code, not reproduced.)
4. **`⨟` is the prototype's own function** (`⨟(a::Transducer, b::Transducer)` and
   `⨟(f, g) = g ∘ f`), a different binding from CompositionsBase's. Next to Transducers.jl or
   Accessors this would be the R6 clash for `⨟` itself. The contract's PROVISIONAL
   "CompositionsBase binding" item already recommends re-using CompositionsBase's.
5. **Closures are type-stable.** The `Take` closure captures `(Take, typeof(+),
   RefValue{Int64})`, all concrete (R3), and `foldxl` allocates 0 bytes (R5). Closures are
   therefore not a performance problem. Their problems are a type you cannot name or dispatch
   on (no `complete`/`combine` methods) and printing.

### F4. Performance (R5): all sequential designs reach the hand-written loop

- Every sequential `foldxl` (prototype, minimal design, Transducers.jl) and both Base forms
  allocate 0 bytes. Their medians sit within about ±30% of the hand-written loop, and the
  order changes between runs on this loaded machine. **I cannot rank them**, and I claim no
  difference between the minimal design and Transducers.jl on sequential folds.
- Threaded `foldxt` on 4 threads: the minimal design makes about 33-35 allocations and about
  2-2.7 kB; Transducers.jl about 22 allocations and about 1.3-1.7 kB; the prototype 43-46
  allocations and 8 MB (input copy). Transducers.jl was faster in 3 of 4 runs. Its
  divide-and-conquer with `basesize` is more mature than the sketch's "one chunk per thread".
- TTFX: the non-precompiled `include` of the minimal design reached the first fold in about
  0.06-0.11 s. `using Transducers` costs 0.34-0.67 s before the first call (precompiled
  package). The prototype's first call was 0.14-0.53 s. All noisy (R5).

## Recommended substrate design (for ChuiCore's transducer ADR)

Every point below runs in `$S/mini.jl` on 1.10.12 and 1.13.2 (R4). Names follow the prototype
and Transducers.jl.

**Types**

- `abstract type Transducer end`. The concrete transducers are immutable structs:
  `Map{F}`, `Filter{P}`, `MapCat{F}`, `Take`, `TakeWhile{P}`, `Scan{F,I}`, `Partition`, plus
  `Composed{T<:Tuple}`.
- A reducing function is also a struct, `R{X<:Transducer, I<:RF}`, with `Bottom{F}` wrapping
  a plain binary op. `xf(op)` returns `R(xf, asrf(op))`, not a closure. For a composition,
  `_apply` recurses over the tuple, so the full type is concrete
  (`R{Map{typeof(f)}, R{Filter{typeof(p)}, Bottom{typeof(+)}}}`, R4).
- `Reduced{T}`, `reduced`, `unreduced`, `isreduced`.

**Protocol** (generic functions owned by ChuiCore, not exported; see interop)

| Function | Default | Stateful transducer |
|---|---|---|
| `start(rf, acc)` | passes to `inner` | returns `Wrapped(state0, start(inner, acc))`; **state is created here**, once per fold, once per partition task |
| `next(rf, acc, x)` | required | uses `wrapping(w) do state, a … end`; returns `Reduced` to stop |
| `complete(rf, acc)` | passes to `inner` | flushes buffered state into `inner` with `next`, then calls `complete(inner, …)` **exactly once** (Clojure rule) |
| `combine(rf, a, b)` | `Bottom`: `op(a, b)`; stateless `R`: passes to `inner` | errors unless the transducer defines a combine (none do in v1) |

- **State goes through the accumulator** (Transducers.jl's `wrap`/`unwrap` idea, kept
  minimal as `Wrapped{S,A}`). It does not go in a `Ref`. This makes each reducing function a
  pure value: reusable, safe to share across tasks, and each fold or task gets fresh state
  from `start`. This fixes F3.2.
- For a `Partition` buffer, the state is a vector allocated in `start`, so it is mutable but
  still per fold.
- **Reduced placement.** `Reduced` is kept outermost: `wrapping` rewraps as
  `Reduced(Wrapped(s, a))`, so outer layers still see their state at completion. This differs
  from Transducers.jl, which drops state on reduce, and is what lets `complete` run once,
  after termination, as Clojure says.
- **Flushing after a downstream reduce.** A layer clears its buffer *before* calling
  downstream, so nothing is flushed after a downstream reduce (`Partition(3) ⨟ Take(1)` gives
  `[[1,2,3]]`). Upstream termination still flushes (`Take(2) ⨟ Partition(3)` gives `[[1,2]]`).

**Composition**

- Define only `Base.:∘(b::Transducer, a::Transducer) = Composed((xfs(a)..., xfs(b)...))`,
  which is Transducers.jl's convention.
- Use CompositionsBase's `⨟`/`opcompose` unchanged (re-exported). Then `Map(f) ⨟ Filter(p)`
  means map then filter, it is `== Filter(p) ∘ Map(f)`, and `⨟` is the same binding as in
  Transducers.jl and Accessors (R6). Adding methods to `Base.:∘` for ChuiCore's own types is
  not piracy.
- This replaces the prototype's own `⨟` function (F3.4) and agrees with the contract's
  CompositionsBase recommendation.

**Folds**

- `foldxl(op, xf, itr; init)` runs `start`, then a `next` loop, then `complete`.
  `Reduced` stops the loop, and `complete` still runs. `init` is required in v1; see
  trade-offs.
- `foldxt(op, xf, itr; init, combine = op, ntasks)`:
  - `init` is a **factory**, as in CC-004.
  - Contiguous partitions (`Iterators.partition`, which gives views for vectors, so there is
    no input copy). One `start(rf, init())` per partition.
  - Results are combined **strictly in partition order**, so `combine` only needs to be
    associative. This fits CC-005 for non-commutative aggregators.
  - `complete` runs once, on the combined accumulator.
- **Early termination in parallel.** A partition that returns `Reduced` records its index in
  an atomic minimum. Later partitions skip work, and combination stops after that partition
  (R4, exact at element 600_000).
- **Stateful pipelines** are detected by a trait `isstateless(xf)` (true for
  `Map`/`Filter`/`MapCat`/`TakeWhile`, false for `Take`/`Scan`/`Partition`, and `all` over a
  `Composed`). They **fall back to `foldxl`**, which is the prototype's rule generalised.
  Transducers.jl errors here instead, depending on the data (F1). A deterministic fallback is
  better for ChuiFrames.
  - `TakeWhile` is marked stateless: per partition it is correct only together with the
    stop-after-first-`Reduced` rule above.
- An optimisation for later: ChuiFrames can still parallelise `head(n)` with a per-partition
  `Take(n)`, combination in order, and a final truncate, because it knows its partitions are
  ordered row ranges. That is an executor rule, not a substrate rule.

**Mapping onto the aggregator protocol (CC-004/CC-005)**

```julia
struct AggStep{A}; agg::A; end
(s::AggStep)(acc, x) = partial(s.agg, acc, (x,))           # per element, through CC-004 `partial`
foldxt(agg, xf, itr) = final(agg, foldxt(AggStep(agg), xf, itr;
                            init = () -> init(agg),          # CC-004 factory
                            combine = (a, b) -> combine(agg, a, b)))   # partition order (CC-005)
```

- R4 checks this for `Sum` (commutative) and `First` (non-commutative, answer 501).
- When `iscommutative(agg)` is true, an executor *may* combine in completion order. The sketch
  does not, and in-order is always correct.
- Feeding one element at a time through `partial(agg, acc, (x,))` was **not** benchmarked
  against chunked `partial(agg, acc, view)`. For a stateless `Map`/`Filter` prefix ChuiFrames
  will likely want to apply the transducer per morsel and call `partial` once per chunk.
  Listed as UNVERIFIED performance.

**Trade-offs and open points for the ADR**

- **`init` required vs optional.** Transducers.jl supports no-init folds through
  InitialValues.jl (one more dependency) and throws `EmptyResultError` on empty input.
  Options:
  - require `init` (the sketch);
  - a `NoValue` sentinel like CC-006's "no value yet", which needs first-element peeling to
    stay type-stable;
  - Clojure-style `op()` as init.
  
  A type-changing accumulator (`init = 0` with `Float64` data) makes the loop type-unstable
  in any design. The ADR should say so.
- **`Partition` element type.** The sketch's buffer is `Any[]`. A typed version needs the
  element type: `Partition{T}`, or `start` taking the input eltype.
- **Stateful `combine`.** Transducers.jl supports a parallel `ScanEmit` through a stateful
  `combine`. Leaving it out keeps v1 small. `Scan` in parallel is possible in theory (a
  prefix-sum style two-pass) and could come later.
- **Effects and unbounded streams (ChuiTypes).**
  - `foldxl` over any iterable works unchanged on unbounded iterators as long as something
    terminates with `Reduced`.
  - `complete` gives the hook for flushing on stream close.
  - `foldxt` must *not* be used on unbounded sources; it needs `length`. The ADR should give
    `foldxt` an `AbstractVector` or `Base.HasLength` requirement, or a separate chunked-stream
    executor in ChuiTypes.
- **What the sketch does not have.** `eduction`, `foldxd`, `Enumerate`, `Completing`,
  `OnInit` and the `|>` adjoint syntax (`itr |> xf`). `eduction` (a lazy foldable) is the most
  useful of these for ChuiTypes. I recommend it as a v1 candidate. The rest can wait.

## Interop notes (`ChuiCoreTransducersExt`)

R7 ran a real weak-dependency extension on both versions. It needs:

1. **ChuiCore → Transducers.jl.** A function stub in ChuiCore (`totransducers`, name open),
   with extension methods mapping `Map → Transducers.Map`, `Filter → Transducers.Filter`,
   `MapCat`, `Take`, `TakeWhile`, `Scan` and `Composed` (via `mapfoldl(…, ⨟, xfs)`).
2. **Transducers.jl folds accepting ChuiCore pipelines.** In the extension:
   `Transducers.foldxl(op, xf::ChuiCore.Transducer, itr; kw...)` and `foldxt` likewise, by
   conversion. The signature contains a ChuiCore-owned type, so it is not type piracy. No
   ambiguity showed up in R7, because `ChuiCore.Transducer` is not a subtype of
   `Transducers.Transducer`.
3. **Transducers.jl → ChuiCore.** Constructors such as `ChuiCore.Map(x::Transducers.Map)`, so
   ChuiCore's folds accept Transducers.jl pipelines. These methods were written in R7 but
   **not exercised** (see UNVERIFIED).
4. **Do not alias the types.** `ChuiCore.Map` must stay a different type from
   `Transducers.Map`. Otherwise ChuiCore would depend on Transducers.jl, against ADR-0002 §4.

**Export recommendation.** Do **not** export `Map`, `Filter`, `MapCat`, `Take`, `TakeWhile`,
`Scan`, `Partition`, `Reduced`, `reduced`, `foldxl` or `foldxt`.

- With exports, `using ChuiCore, Transducers` makes every bare use an `UndefVarError`. On
  1.10 this comes with a warning; on 1.13 it comes only at the use (R6).
- Mark them `public` on ≥ 1.11, through the version-gated form the contract's "Export list"
  item already names (Compat's `@compat public …`, or the `@static`/`eval(Meta.parse)` form
  that ran in R6). Users then write `ChuiCore.Map` or `using ChuiCore: Map, Filter`; the
  explicit `using` is resolved at import and does not clash.
- Re-export **only** `⨟` (and maybe `opcompose`), the CompositionsBase binding, which never
  clashes (R6).
- The protocol functions (`start`, `next`, `complete`, `combine`) stay unexported. `combine`
  is already CC-004's aggregator function. The sketch adds `combine(rf::RF, a, b)` methods to
  the same generic function, which is consistent with "method extension of the same binding is
  not a conflict" (contract, name-conflict banner item). Whether to share one function for
  both meanings is a naming decision for the ADR.

## UNVERIFIED

- **Context7 has no Transducers.jl entry** (three queries). The API facts come from the
  installed 0.4.85 source and runs, not from the hosted documentation site
  (juliafolds.github.io), which I did not fetch.
- **Benchmark rankings.** The machine was under heavy load (load average 55-76). The medians
  are noisy, and I make no claim that one sequential `foldxl` is faster than another. Rerun on
  an idle machine before citing numbers in an ADR. I also wrote no `.lanes/evidence/` file
  (`scripts/evidence.jl`), because the lane's file scope is this note only.
- **TTFX of a precompiled ChuiCore** (with `PrecompileTools`) was not measured. The scratch
  modules were `include`d.
- **Transducers.jl `foldxt` with stateful transducers never returning a wrong answer** is
  based only on the probes in R2, not on a proof or a source audit of every path.
- **The prototype's `foldxt` mishandling a `Reduced` from a middle batch** (F3.3) is from
  reading the code; not reproduced.
- **Extension reverse constructors** (`ChuiCore.Map(::Transducers.Map)`,
  `ChuiCore.Filter(::Transducers.Filter)` using field `pred`) were written but not exercised.
- **Aqua's piracy check** on the extension's `Transducers.foldxl(::Any, ::ChuiCore.Transducer,
  ::Any)` methods was not run.
- **Element-wise `partial(agg, acc, (x,))`** vs chunked `partial` performance: not measured.
- **JET** was not run on the sketch. Type stability is shown only by `@inferred`,
  `code_warntype` for `next`, and 0-byte `@allocated`.
- **The Clojure page's "Published 2026-10-16"** is what the fetch reported. The quotes came
  through a summariser, so check them against the page before quoting in an ADR.

## Also noticed

- Transducers.jl exports `Count`, which clashes with the CC-007 aggregator name `Count` if
  ChuiCore exports its aggregators. That is one more reason to keep aggregators `public`
  rather than exported.
- Transducers.jl's `Take` completes the inner reducing function inside `next` when it
  terminates (`library.jl:450`). How the fold loop then treats completion of that already
  reduced value was not traced (UNVERIFIED). Compare Clojure's "completion runs once at the
  end".
