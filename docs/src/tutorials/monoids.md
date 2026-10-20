# Monoids and aggregators

```@meta
DocTestSetup = :(using ChuiCore)
DocTestFilters = [r"(Test Summary:.*)?"s]
```

An *aggregator* is a small value, such as `ChuiCore.Sum()`, that says how to reduce a column of
values that may be split into partitions: per partition, then across partitions, in any number of
tasks. ChuiFrames' engine and ChuiCore's own folds run every aggregator through one protocol of
four functions (contract CC-004). This tutorial walks through that protocol, the built-in
aggregators, the empty-input rules (CC-006), and how to write and check your own.

The protocol and the built-ins are **public, not exported** (CC-013): write `ChuiCore.Sum`, or
import the names you use.

```jldoctest monoids
julia> using ChuiCore: init, partial, combine, final, iscommutative, neutral, combineall

julia> using ChuiCore: Sum, Count, Max, First, Last, Mean, Moments, ReduceM, MapM
```

## The protocol: `init`, `partial`, `combine`, `final`

| Function | Does |
|---|---|
| [`init(agg)`](@ref ChuiCore.init) | a fresh accumulator; a *factory*, called once per partition |
| [`partial(agg, acc, chunk)`](@ref ChuiCore.partial) | folds every element of `chunk` into `acc` |
| [`combine(agg, a, b)`](@ref ChuiCore.combine) | merges an earlier partition's accumulator `a` with a later one's `b` |
| [`final(agg, acc)`](@ref ChuiCore.final) | turns the accumulator into the result (default: `acc` itself) |

Three partitions of one column, one of them empty:

```jldoctest monoids
julia> parts = [[1, 2, 3], Int[], [4, 5]];

julia> accs = [partial(Sum(), init(Sum()), p) for p in parts]
3-element Vector{Int64}:
 6
 0
 9

julia> final(Sum(), combine(Sum(), combine(Sum(), accs[1], accs[2]), accs[3]))
15
```

Every partition starts from its own `init(agg)`. `partial` and `combine` are allowed to mutate
their accumulator argument, so an accumulator is used once and the return value is what counts.
A chunk can be any iterable: a vector, a generator, an `Iterators.flatten`.

A small helper runs that recipe over any partitions; the rest of this page uses it:

```jldoctest monoids
julia> function by_parts(agg, parts)
           acc = partial(agg, init(agg), first(parts))
           for p in Iterators.drop(parts, 1)
               acc = combine(agg, acc, partial(agg, init(agg), p))
           end
           return final(agg, acc)
       end;

julia> by_parts(Sum(), parts), by_parts(Count(), parts), by_parts(Max(), parts)
(15, 5, 5)
```

ChuiCore's executor for this is [`ChuiCore.aggregate`](@ref ChuiCore.aggregate), which runs one
task per partition through a transducer and merges the results in partition order:

```jldoctest monoids
julia> ChuiCore.aggregate(Sum(), ChuiCore.Map(abs2), parts)   # 1 + 4 + 9 + 16 + 25
55
```

## The built-ins

| Built-in | Like | Class | Commutative | Empty input |
|---|---|---|---|---|
| `Sum()`, `Prod()` | `sum`, `prod` | Monoid | yes | `0`, `1` |
| `Count()`, `CountTrue()` | `length`, `count` | Monoid | yes | `0` |
| `AnyM()`, `AllM()` | `any`, `all` | Monoid | yes | `false`, `true` |
| `Max()`, `Min()`, `Extrema()` | `maximum`, `minimum`, `extrema` | Semigroup | yes | throws `ArgumentError` |
| `First()`, `Last()` | `first`, `last` | Semigroup | **no** | throws `BoundsError` |
| `Mean()` | `Statistics.mean` | Monoid accumulator plus `final` | yes | `NaN` |
| `Moments(:var)`, `Moments(:std)` | `Statistics.var`, `std` | Semigroup plus `final` | yes | `NaN` |
| `ReduceM(op; neutral, commutative)` | `reduce(op, v)` | you declare it | you declare it | `ArgumentError` unless `neutral` |
| `MapM(f, inner)` | `inner` on `map(f, v)` | as `inner` | as `inner` | as `inner` |

### `Mean`: an aggregate with a final step

`Mean`'s accumulator is not the mean: it is `(float sum, count)`, which merges by adding both
parts. Only `final` divides. Averaging two partition means would be wrong whenever the partitions
differ in size.

```jldoctest monoids
julia> a = partial(Mean(), init(Mean()), [1, 2, 3])
(6.0, 3)

julia> b = partial(Mean(), init(Mean()), [10])
(10.0, 1)

julia> final(Mean(), combine(Mean(), a, b))   # 16 / 4, not (2 + 10) / 2
4.0
```

`Moments` does the same for the variance: Welford's update within a partition, Chan's parallel
merge across partitions, then `final` divides by `n - 1` (or `n` with `corrected = false`). Float
merges are associative only up to rounding, so the law kits compare `Sum`, `Prod`, `Mean` and
`Moments` results with CC-004's tolerance rather than exactly.

```jldoctest monoids
julia> by_parts(Moments(), [[1.0, 2.0], [3.0], [4.0]])   # Statistics.var(1.0:4.0)
1.6666666666666667

julia> by_parts(Moments(:std; corrected = false), [[1.0], [3.0]])
1.0
```

### `ReduceM` and `MapM`: build your own from an operation

`ReduceM(op)` aggregates with any associative `op`. By default it is a Semigroup that is not
commutative; declare what you know:

```jldoctest monoids
julia> by_parts(ReduceM(*), [["a", "b"], ["c"]])   # string concatenation
"abc"

julia> g = ReduceM(gcd; neutral = 0, commutative = true);

julia> by_parts(g, [[12, 18], Int[], [8]]), iscommutative(g)
(2, true)
```

`MapM(f, inner)` applies `f` lazily to each element before `inner` sees it (no intermediate
array):

```jldoctest monoids
julia> by_parts(MapM(abs2, Sum()), [[1, -2], [3]])   # sum(abs2, v)
14

julia> by_parts(MapM(length, Max()), [["a", "abc"], ["ab"]])
3
```

## Monoids: `neutral`, `AlgebraClass`, `combineall`

A **monoid** has an identity element: `neutral(m)`, which changes nothing when combined on either
side. A **semigroup** has only an associative `combine`. The trait
[`ChuiCore.AlgebraClass`](@ref ChuiCore.AlgebraClass) says which one an aggregator is; it is
resolved by dispatch, at compile time.

```jldoctest monoids
julia> ChuiCore.AlgebraClass(Sum()), ChuiCore.AlgebraClass(Max()), ChuiCore.AlgebraClass(g)
(ChuiCore.IsMonoid(), ChuiCore.IsSemigroup(), ChuiCore.IsMonoid())

julia> neutral(Sum()), neutral(Sum(), Float64), neutral(Mean())
(0, 0.0, (0.0, 0))
```

`neutral` is a factory like `init`: each call returns a fresh value, because `combine` may mutate
it. `neutral(m, T)` gives an identity of element type `T` where one exists.

[`combineall(m, accs)`](@ref ChuiCore.combineall) folds already-built accumulators in order. Its
start depends on the class: a monoid starts from `neutral(m)`, so no accumulators give the
identity; a semigroup starts from "no value yet":

```jldoctest monoids
julia> final(Sum(), combineall(Sum(), accs))
15

julia> combineall(Sum(), Int[])
0

julia> combineall(Max(), Int[])
ChuiCore.NoValue()
```

[`ChuiCore.default_monoid`](@ref ChuiCore.default_monoid) names the monoid that `neutral(T)` uses
for a type. ChuiCore declares none, not even for numbers (sum and product are both monoids on
`Int`); a package declares one for its own types:

```jldoctest monoids
julia> struct Tally
           n::Int
       end

julia> ChuiCore.default_monoid(::Type{Tally}) = Count();

julia> neutral(Tally)
0
```

## Partition order matters: `iscommutative`

[`iscommutative(agg)`](@ref ChuiCore.iscommutative) declares whether `combine(agg, a, b)` and
`combine(agg, b, a)` give the same result (CC-005). It defaults to `false`, and every executor
then merges in **partition order**. `First` and `Last` are why:

```jldoctest monoids
julia> early = partial(First(), init(First()), [1, 2]); late = partial(First(), init(First()), [3]);

julia> final(First(), combine(First(), early, late)), final(First(), combine(First(), late, early))
(1, 3)

julia> iscommutative(First()), iscommutative(Last()), iscommutative(Sum())
(false, false, true)
```

An engine that reorders partitions (a shuffle, a hash repartition) must carry an order key for
such aggregators, or merge them sequentially. Declaring `true` for an aggregator that is not
commutative is a bug in the aggregator.

## Empty input (CC-006)

**Value cases.** Where Base returns a value on an empty collection, so does the aggregator:
`final(agg, init(agg))` matches it (compared with `isequal`, so `NaN` matches `NaN`). The element
type is not promised: `init` does not know the input's element type.

```jldoctest monoids
julia> final(Sum(), init(Sum())), final(Count(), init(Count())), final(Mean(), init(Mean()))
(0, 0, NaN)
```

**Throwing cases.** Where Base throws, ChuiCore throws **one exception type on every supported
Julia**: `ArgumentError` for `Max`, `Min`, `Extrema` and `ReduceM` without a neutral, and
`BoundsError` for `First` and `Last`. Base's own type is version-dependent
(`maximum(Float64[])` throws a `MethodError` on Julia 1.10 and an `ArgumentError` on 1.13), so
ChuiCore does not mirror it; one documented type is testable exactly with `@test_throws`.

```jldoctest monoids
julia> final(Max(), init(Max()))
ERROR: ArgumentError: Max(): empty input (an empty collection has no maximum)
Stacktrace:
[...]

julia> final(First(), init(First()))
ERROR: BoundsError: attempt to access Tuple{} at index [1]
Stacktrace:
[...]

julia> final(ReduceM(*), init(ReduceM(*)))
ERROR: ArgumentError: ReduceM: empty input and no declared neutral element
Stacktrace:
[...]
```

**The "no value yet" state.** An aggregator without an identity still needs something for
`init` to return. That is an internal state, `ChuiCore.NoValue()`, which `combine` treats as an
identity on either side and `final` turns into the empty-input result (the exception, or `NaN`
for `Moments`). It is never a user-visible result.

```jldoctest monoids
julia> init(Max()), init(Moments())
(ChuiCore.NoValue(), ChuiCore.NoValue())
```

**Empty partitions** are therefore harmless, wherever they fall:

```jldoctest monoids
julia> by_parts(Max(), [Int[], [3, 9], Int[], [4]])
9

julia> by_parts(First(), [Int[], Int[], [7, 8]])
7

julia> by_parts(Moments(), [Float64[], [1.0, 3.0]])
2.0
```

**`ReduceM` with a declared neutral** is a monoid: empty input returns (a fresh copy of) the
neutral. It is not compared with Base, which special-cases some operators
(`reduce(+, Float64[]) == 0.0`).

```jldoctest monoids
julia> by_parts(g, [Int[], Int[]])
0
```

## Write your own aggregator

A *range* aggregator, `max - min`, needs both ends, so its accumulator is a `(lo, hi)` pair. It
has no identity, so it is a semigroup and needs its own "no value yet" state: here `nothing`,
which `combine` treats as an identity on either side and `final` turns into an `ArgumentError`
(the built-ins use the internal `ChuiCore.NoValue()` for the same job; your own type is clearer
for your own aggregator). Define the four functions, plus the two traits:

```jldoctest monoids
julia> struct Range end

julia> ChuiCore.init(::Range) = nothing;

julia> ChuiCore.partial(::Range, acc, chunk) =
           foldl((a, x) -> a === nothing ? (x, x) : (min(a[1], x), max(a[2], x)), chunk; init = acc);

julia> ChuiCore.combine(::Range, a, b) =
           a === nothing ? b : b === nothing ? a : (min(a[1], b[1]), max(a[2], b[2]));

julia> ChuiCore.final(::Range, acc) =
           acc === nothing ? throw(ArgumentError("Range(): empty input")) : acc[2] - acc[1];

julia> ChuiCore.iscommutative(::Range) = true;

julia> ChuiCore.AlgebraClass(::Type{Range}) = ChuiCore.IsSemigroup();

julia> by_parts(Range(), [[3, 1], Int[], [10]])
9
```

Then check it with the law kits. They need `Test` loaded (`ChuiCoreTestExt`; see
[law kits](law-kits.md)). [`test_aggregator_laws`](@ref ChuiCore.test_aggregator_laws) checks
CC-004's laws (split invariance with empty chunks, empty partitions, chunk concatenation,
commutativity since we declared it, fresh `init`) and, with `reference`, agreement with Base:

```jldoctest monoids
julia> using Test

julia> samples = [[3, 1, 10], [5], [-2, 7, 7, 0], Int[]];

julia> test_aggregator_laws(Range(), samples; reference = v -> maximum(v) - minimum(v))
Test Summary:                 | Pass  Total  Time
test_aggregator_laws(Range()) |    6      6  0.0s

julia> test_semigroup_laws(Range(), samples)
Test Summary:                | Pass  Total  Time
test_semigroup_laws(Range()) |    1      1  0.0s
```

(The test summaries on this page are shown for reading, but not compared by the doctests: Test
prints a summary only for a top-level test set, and its Time column varies.)

A monoid is checked with [`test_monoid_laws`](@ref ChuiCore.test_monoid_laws), which adds the
identity laws of `neutral`. A sum of squares, declared through `ReduceM`:

```jldoctest monoids
julia> sq = MapM(abs2, ReduceM(+; neutral = 0, commutative = true));

julia> @testset "sum of squares" test_monoid_laws(sq, [[1, 2], Int[], [-3]]);
Test Summary:  | Pass  Total  Time
sum of squares |    5      5  0.0s
```

(The outer `@testset` only gives the summary a short title: the kit's own title prints the whole
`MapM{…}` type.)

## What it costs

- **No allocation in the protocol** for the built-ins on number elements: their accumulators are
  immutable (`0`, a tuple, `NoValue()`), and the test item "perf allocs: built-in aggregators
  partial/combine/final are 0 B" checks `partial`, `combine` and `final` at 0 bytes.
- **One pass per chunk** at most. `Sum`, `Prod` and `Mean` use Base's pairwise `sum`/`prod` on a
  non-empty `AbstractArray` chunk; `Count` and `Last` are O(1) there; `First` reads one element
  and then stops iterating; `AnyM`/`AllM` short-circuit.
- **`combine` is O(1)**: one `+`, `max`, tuple merge, or Chan merge; one `op` call for `ReduceM`.
- **Traits are free**: `iscommutative` and `AlgebraClass` are constants chosen by dispatch, folded
  at compile time.
- **"No value yet"** makes a semigroup's accumulator a small `Union{NoValue, T}` until the first
  element, which Julia handles by union splitting.
- **Copies only where you ask**: `init`/`neutral` of `ReduceM(op; neutral = x)` `deepcopy` a
  mutable `x` on every call; `MapM` gives up the inner aggregator's `AbstractArray` fast paths.
