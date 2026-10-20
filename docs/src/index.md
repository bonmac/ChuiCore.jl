# ChuiCore.jl

The functional-programming core of the Chui ecosystem: composition, algebraic structures as Holy
traits with reusable law-test kits, monoids and aggregators, a transducer substrate, recursion
schemes, free monads, optics, laziness, and a name-conflict banner. It depends on no other Chui
package; ChuiTypes and ChuiFrames build on it.

```@docs
ChuiCore
```

## Install

ChuiCore is pre-release and not registered yet. Once v0.1.0 is registered in the personal
registry ChuiRegistry (ecosystem ADR-0005):

```julia
using Pkg
Pkg.Registry.add(Pkg.RegistrySpec(url = "https://github.com/bonmac/ChuiRegistry"))
Pkg.add("ChuiCore")
```

Until then, add it by URL once the repository is public, or develop a local clone:

```julia
Pkg.add(url = "https://github.com/bonmac/ChuiCore.jl")   # once the repository is public
Pkg.develop(path = "path/to/ChuiCore.jl")                # a local clone
```

ChuiCore supports Julia 1.10 (LTS) and later.

## A 30-second example

Compose left to right with `⨟`, fold with a transducer, and aggregate partitions with a monoid:

```jldoctest
julia> using ChuiCore

julia> f = (x -> x + 1) ⨟ (x -> 2x);   # first +1, then ×2

julia> f(3)
8

julia> ChuiCore.foldxl(+, ChuiCore.Map(abs2) ⨟ ChuiCore.Filter(iseven), 1:10; init = 0)
220

julia> m = ChuiCore.Mean();

julia> a = ChuiCore.partial(m, ChuiCore.init(m), [1.0, 2.0]);   # one partition

julia> b = ChuiCore.partial(m, ChuiCore.init(m), [3.0]);        # another

julia> ChuiCore.final(m, ChuiCore.combine(m, a, b))
2.0
```

The aggregators, `Map` and `Filter` are public but not exported: use them qualified, or with
`using ChuiCore: Map, Filter`. [Export tiers and the clash list](explanation/export-tiers.md)
explains why.

## Where to go next

- **Tutorials** (learning, runnable end to end): [composition](tutorials/composition.md),
  [monoids and aggregators](tutorials/monoids.md), [typeclasses](tutorials/typeclasses.md),
  [law kits](tutorials/law-kits.md), [transducers](tutorials/transducers.md),
  [recursion schemes](tutorials/recursion-schemes.md), [free monads](tutorials/free-monads.md),
  [optics](tutorials/optics.md), [laziness](tutorials/laziness.md),
  [the conflict banner](tutorials/conflict-banner.md).
- **How-to recipes**: [short task recipes](howto/recipes.md).
- **Explanation**: [why ChuiCore](explanation/why.md), [purity and effects](explanation/purity-effects.md),
  [export tiers](explanation/export-tiers.md), [the runtime cost model](explanation/cost-model.md),
  [performance measurements](performance.md).
- **Reference**: [composition and law kits](reference/core.md),
  [monoids and aggregators](reference/algebra.md), [typeclasses](reference/classes.md),
  [transducers](reference/transducers.md), [recursion schemes and free monads](reference/schemes.md),
  [optics](reference/optics.md), [laziness and the banner](reference/lazy.md),
  [internals](reference/internals.md).
- [Changelog](changelog.md).
