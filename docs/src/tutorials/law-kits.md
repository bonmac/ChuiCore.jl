# Law kits for downstream packages

```@meta
DocTestSetup = :(using ChuiCore)
DocTestFilters = [r"(Test Summary:.*)?"s, r"t::Tuple\{.*\} = .*"]
```

A package that defines its own aggregator, monoid, functor or lens should test that the instance
obeys the laws ChuiCore's algorithms rely on. ChuiCore ships those tests as **law kits**: one
exported function per structure, `test_<structure>_laws(instance, generators...; eq, laws,
max_examples)` (ecosystem ADR-0007; ChuiCore's `docs/adr/0007-law-kits-as-stubs-plus-extensions.md`).
Each kit records one inner `@testset` per law, holding one `@test`, in your own test set.

## Loading the kits: `Test`, then Supposition

The kits are exported by ChuiCore but have **no methods** until you load their drivers, which
are package extensions:

| You load | Extension | Generators the kits accept |
|---|---|---|
| `using Test` | `ChuiCoreTestExt` | finite sample collections (any iterable) |
| `using Test, Supposition` | `ChuiCoreSuppositionExt` | Supposition generators (`Data.Possibility`), with shrinking |

Loading ChuiCore alone loads neither `Test` nor Supposition, and neither is a dependency of
ChuiCore (contract CC-011). Put them in your package's test environment (`test/Project.toml`),
not in its `[deps]`. In a fresh process:

```julia
using ChuiCore
any(m -> nameof(m) in (:Test, :Supposition), values(Base.loaded_modules))   # false
```

In a test file:

```jldoctest kits
julia> using Test

julia> using ChuiCore: Sum, Max, Mean, ReduceM, First, default_eq, ExactEq, Law
```

## What a kit compares: `Law`, `ExactEq`, `default_eq`

A kit is a table of [`Law`](@ref ChuiCore.Law)s: a name, the generator each argument is drawn
from, and a predicate. The driver draws arguments and records `@test` that no counterexample was
found. You never build kits from `Law`s yourself; the type is public so you can read what a kit
checks.

Results are compared with the kit's `eq` keyword. Its default is
[`default_eq(instance)`](@ref ChuiCore.default_eq):

- for most instances [`ExactEq()`](@ref ChuiCore.ExactEq), which is `isequal` (so `NaN` equals
  `NaN`, and `0.1 + 0.2` does not equal `0.3`);
- for the float aggregators `Sum`, `Prod`, `Mean`, `Moments` (and `MapM` over them), CC-004's
  tolerance, which scales with the **whole input**. Aggregator kits therefore call
  `eq(r₁, r₂, v)` with `v` the input; the other kits call `eq(a, b)`.

```jldoctest kits
julia> default_eq(Max())
ExactEq()

julia> v = [1.0, 1e16, -1e16];

julia> sum(v), sum(v[1:1]) + sum(v[2:3])   # one split of v gives a different float
(0.0, 1.0)

julia> default_eq(Sum())(0.0, 1.0, v)   # accepted: within ε · sum(abs, v)
true

julia> ExactEq()(0.0, 1.0)
false
```

Pass your own `eq` when your instance needs a different notion of equality, with the arity the
kit uses: `eq = (a, b, v) -> isapprox(a, b; rtol = 1e-6)` for an aggregator kit.

## The monoid family, worked

[`test_semigroup_laws`](@ref ChuiCore.test_semigroup_laws) checks associativity of `combine`.
Its samples are *chunks*: each becomes a fresh accumulator `partial(m, init(m), chunk)`, and
results are compared after `final`:

```jldoctest kits
julia> test_semigroup_laws(Max(), [[3, 1], Int[], [7], [-2, 5]])
Test Summary:                       | Pass  Total  Time
test_semigroup_laws(ChuiCore.Max()) |    1      1  0.0s
```

[`test_monoid_laws`](@ref ChuiCore.test_monoid_laws) adds `left identity` and `right identity`
of `neutral(m)`, `neutral matches init`, and `neutral is fresh` (mutating one `neutral(m)` must
not change the next). Concatenation of vectors is a monoid that is not commutative:

```jldoctest kits
julia> concat = ReduceM(vcat; neutral = Int[]);

julia> @testset "vcat monoid" test_monoid_laws(concat, [[1], Int[], [2, 3], [4]]);
Test Summary: | Pass  Total  Time
vcat monoid   |    5      5  0.0s
```

[`test_aggregator_laws`](@ref ChuiCore.test_aggregator_laws) checks CC-004 on each sample
*input* `v`: `split invariance` over fixed splits with empty chunks, `empty partition
identity`, `chunk concatenation`, `commutativity` (vacuous unless
`ChuiCore.iscommutative(agg)`), `init is fresh`, and, with `reference`, `agrees with reference`
on non-empty inputs:

```jldoctest kits
julia> mean_ref(v) = sum(v) / length(v);

julia> test_aggregator_laws(Mean(), [[1.0, 2.5], Float64[], [4.0, -1.0, 0.5]]; reference = mean_ref)
Test Summary:                         | Pass  Total  Time
test_aggregator_laws(ChuiCore.Mean()) |    6      6  0.0s
```

Run a subset with `laws`. A misspelled law name is an error, not a silent pass:

```jldoctest kits
julia> @testset "split only" test_aggregator_laws(Sum(), [[1, 2, 3]]; laws = ["split invariance"]);
Test Summary: | Pass  Total  Time
split only    |    1      1  0.0s

julia> test_aggregator_laws(Sum(), [[1, 2, 3]]; laws = ["split invariant"])
ERROR: ArgumentError: unknown law name(s) ["split invariant"]; this kit's laws are ["split invariance", "empty partition identity", "chunk concatenation", "commutativity", "init is fresh"]
Stacktrace:
[...]
```

With sample collections a law with `k` arguments uses at most 12 samples per argument and at
most 1,728 argument combinations, so keep the interesting cases (empty, one element, negative,
`NaN`, `missing` if you accept it) near the front.

## The class and optics kits

The same conventions hold for the constructor classes (instance = a tag such as
`ChuiCore.MaybeTag()`; [Typeclasses](typeclasses.md)) and for optics ([Optics](optics.md)):
[`test_functor_laws`](@ref ChuiCore.test_functor_laws),
[`test_applicative_laws`](@ref ChuiCore.test_applicative_laws),
[`test_monad_laws`](@ref ChuiCore.test_monad_laws),
[`test_alternative_laws`](@ref ChuiCore.test_alternative_laws),
[`test_foldable_laws`](@ref ChuiCore.test_foldable_laws),
[`test_traversable_laws`](@ref ChuiCore.test_traversable_laws),
[`test_contravariant_laws`](@ref ChuiCore.test_contravariant_laws),
[`test_bifunctor_laws`](@ref ChuiCore.test_bifunctor_laws),
[`test_profunctor_laws`](@ref ChuiCore.test_profunctor_laws),
[`test_category_laws`](@ref ChuiCore.test_category_laws),
[`test_arrow_laws`](@ref ChuiCore.test_arrow_laws),
[`test_lens_laws`](@ref ChuiCore.test_lens_laws) and
[`test_prism_laws`](@ref ChuiCore.test_prism_laws). Their `eq` takes two arguments. One example:

```jldoctest kits
julia> test_functor_laws(ChuiCore.MaybeTag(), [Some(1), nothing, Some(-3)], [x -> x + 1, abs])
Test Summary:                          | Pass  Total  Time
test_functor_laws(ChuiCore.MaybeTag()) |    2      2  0.0s
```

## Property-based: Supposition generators

When the first generator is a Supposition `Data.Possibility`, the kit draws `max_examples`
examples (default 200) per law and shrinks any counterexample. The other generators may then be
plain collections; they are sampled with `Data.SampledFrom`.

```jldoctest kits
julia> using Supposition

julia> using Supposition: Data

julia> chunks = Data.Vectors(Data.Integers(-100, 100); max_size = 8);

julia> test_monoid_laws(Sum(), chunks; max_examples = 50)
Test Summary:                    | Pass  Total  Time
test_monoid_laws(ChuiCore.Sum()) |    5      5  0.0s
```

### The rule: `@check record=false db=false`, then `@test` on the report

Every law the Supposition driver runs is

```julia
report = @check record = false db = false max_examples = n prop(gen)
@test passed(report)
```

and your own property tests should use the same form:

```jldoctest kits
julia> using Supposition: @check

julia> sr = @check record = false db = false max_examples = 50 function sum_commutes(
               x = Data.Vectors(Data.Integers(-9, 9)), y = Data.Vectors(Data.Integers(-9, 9)))
           sum(x) + sum(y) == sum(y) + sum(x)
       end;

julia> @test Supposition.results(sr).ispass
Test Passed
```

Why both settings:

- **`record=false` plus an explicit `@test`.** On Julia 1.10, a failing `@check` inside a
  `@testset` is *not recorded*: the test set passes and the process exits 0 (Supposition 0.3.5;
  1.13 records it). Julia 1.10's `Test` counts only `DefaultTestSet` children, which Supposition
  works around only on 1.11 and later. Asserting the report yourself fails correctly on every
  version (ecosystem ADR-0007 §2; ChuiCore's `docs/research/law-kits-modules-names.md`, findings
  L-4 and L-5).
- **`db=false`.** Otherwise Supposition writes each counterexample into a database under your
  `test/SuppositionDB` and replays it on the next run. A database written by a newer Julia makes a
  later 1.10 run throw ("Cannot read stream serialized with a newer version of Julia"). Keep a
  counterexample you care about as an ordinary unit test instead, and gitignore
  `/test/SuppositionDB/` (ChuiCore's own `.gitignore` does).

## A planted violation must fail

A kit that cannot fail proves nothing, so check that yours catch a broken instance. Here `First`
is wrapped and falsely declared commutative:

```jldoctest kits
julia> struct BadFirst end   # First, but claims to be commutative

julia> ChuiCore.init(::BadFirst) = ChuiCore.init(First());

julia> ChuiCore.final(::BadFirst, acc) = ChuiCore.final(First(), acc);

julia> ChuiCore.partial(::BadFirst, acc, chunk) = ChuiCore.partial(First(), acc, chunk);

julia> ChuiCore.combine(::BadFirst, a, b) = ChuiCore.combine(First(), a, b);

julia> ChuiCore.iscommutative(::BadFirst) = true;
```

Running the kit inside a plain `@testset` would fail your test suite, which is the point in real
use. To *assert* the failure instead (as ChuiCore's own planted-violation tests do, ADR-0007 §5),
run the kit inside a small test set that captures results rather than reporting them:

```jldoctest kits
julia> mutable struct Capture <: Test.AbstractTestSet
           description::String
           results::Vector{Any}
       end

julia> Capture(description; kwargs...) = Capture(description, Any[]);

julia> Test.record(ts::Capture, r) = (push!(ts.results, r); r);

julia> function Test.finish(ts::Capture)   # nested captures report to their parent capture
           parent = Test.get_testset_depth() > 0 ? Test.get_testset() : nothing
           parent isa Capture && Test.record(parent, ts)
           return ts
       end;

julia> failures(ts::Capture) = [name => r for (name, r) in _leaves(ts) if r isa Test.Fail];

julia> _leaves(ts::Capture) =
           [p for r in ts.results for p in (r isa Capture ? _leaves(r) : [ts.description => r])];
```

With samples, the kit reports the first counterexample it found, `([3], [1, 2])`: combining
those two partitions in either order gives a different first element.

```jldoctest kits
julia> ts = @testset Capture "planted" test_aggregator_laws(BadFirst(), [[1, 2], [3]]);

julia> [name => fail.data for (name, fail) in failures(ts)]
1-element Vector{Pair{String, String}}:
 "commutativity" => "([3], [1, 2]) === nothing"
```

With a Supposition generator the same law fails, and Supposition prints the shrunk
counterexample:

```jldoctest kits
julia> gen = Data.Vectors(Data.Integers(0, 9); min_size = 1, max_size = 3);

julia> ts = @testset Capture "planted" test_aggregator_laws(BadFirst(), gen; max_examples = 100);
Found counterexample
  Context: chui_law

  Arguments:
      t::Tuple{Vector{Int64}, Vector{Int64}} = ([0], [1])

julia> first.(failures(ts))
1-element Vector{String}:
 "commutativity"
```

The other laws passed: `BadFirst` is a correct semigroup, only its commutativity claim is false.

## What it costs

- **Sample collections:** per law, at most 12 samples per argument and at most 1,728 predicate
  calls; the aggregator kits also run a fixed set of splits per input (an empty first, middle and
  last chunk, halves, thirds, singletons), so `split invariance` costs O(n) `partial`/`combine`
  calls per split for an input of length `n`.
- **Supposition:** `max_examples` examples per law (default 200), plus shrinking when a law
  fails; `max_examples = 50` is usually enough in a unit-test run.
- **Fresh accumulators everywhere:** because `partial` and `combine` may mutate, every comparison
  rebuilds its accumulators with `partial(m, init(m), collect(chunk))`; that copies each chunk
  once per use. The float tolerance makes one pass over the input per comparison.
- **Effects:** a kit records one `@test` per law in the current test set, prints the summary
  only when it is the top-level test set, and throws `Test.TestSetException` at the top level if
  a law fails. The Supposition driver seeds from `Random.RandomDevice` (each run draws different
  examples), prints counterexamples, and writes no files.
- **Nothing at load time:** without `using Test` the kits have no methods and ChuiCore loads
  neither `Test` nor Supposition.
