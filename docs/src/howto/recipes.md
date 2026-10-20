# How-to recipes

```@meta
DocTestSetup = :(using ChuiCore)
```

Short answers to common tasks. Each links to the tutorial that explains it.

## Use public names without the `ChuiCore.` prefix

Import them by name; an explicit import also wins over a clashing `using` of another package
([export tiers](../explanation/export-tiers.md)):

```jldoctest recipes
julia> using ChuiCore: Sum, Max, init, partial, combine, final

julia> final(Sum(), partial(Sum(), init(Sum()), 1:4))
10
```

## Aggregate partitions and merge the results

Build one accumulator per partition, merge them in partition order, then finalize. Empty
partitions are fine ([monoids and aggregators](../tutorials/monoids.md)):

```jldoctest recipes
julia> parts = [[1, 2, 3], [4, 5], Int[]];

julia> accs = [partial(Max(), init(Max()), p) for p in parts];

julia> final(Max(), ChuiCore.combineall(Max(), accs))
5

julia> ChuiCore.aggregate(ChuiCore.Mean(), ChuiCore.Map(identity), parts)   # the same, as one call
3.0
```

## Check your own monoid or instance in your test suite

Load `Test` (and optionally `Supposition`) and call the kit inside a `@testset`
([law kits](../tutorials/law-kits.md)):

```julia
using ChuiCore, Test
@testset "MyMonoid laws" begin
    test_monoid_laws(MyMonoid(), [[1, 2], Int[], [3]])
end
```

## Update a nested field of an immutable struct

Compose lenses with `⨟` and use `ChuiCore.set` / `ChuiCore.modify` ([optics](../tutorials/optics.md)):

```jldoctest recipes
julia> struct Pt; x::Int; y::Int; end

julia> struct Box; p::Pt; tag::Symbol; end

julia> l = ChuiCore.Lens(:p) ⨟ ChuiCore.Lens(:x);

julia> ChuiCore.set(Box(Pt(1, 2), :a), l, 10)
Box(Pt(10, 2), :a)

julia> ChuiCore.modify(x -> x + 1, Box(Pt(1, 2), :a), l)
Box(Pt(2, 2), :a)
```

## Make your type a Functor (or Monad, …)

Map the type to a tag, give the tag a style, and write the instance method with the style argument
typed ([typeclasses](../tutorials/typeclasses.md), rule N5).

## Stop a fold early

Return `ChuiCore.reduced(acc)` from the step function, or put a `Take`/`TakeWhile` in the pipeline.
Over partitions, only the second form stops the whole fold ([transducers](../tutorials/transducers.md),
the S1 caveat).

## Silence the conflict banner

Set the environment variable before the packages load:

```sh
export CHUI_QUIET_CONFLICTS=1     # or "true", any case
```

The banner then computes nothing and prints nothing ([the conflict banner](../tutorials/conflict-banner.md)).

## Show the banner from your own package

```julia
module MyPkg
using ChuiCore
export myfun
myfun(x) = x
__init__() = isinteractive() && ChuiCore.conflict_banner(stderr, @__MODULE__)
end
```

## Run the doctests of this package

```sh
julia scripts/ci.jl docs            # builds the site and runs every doctest
julia scripts/ci.jl test -- doctest # the :doctest test item only (stable Julia)
```
