# ChuiCore.jl

The functional-programming core of the Chui ecosystem.

**Status:** pre-release (0.0.1, phase 2 of the brief). Tutorials, how-to guides and explanation pages
come in phase 5; the [reference](api.md) lists every documented name.

```@docs
ChuiCore
```

## Names come in three tiers (ADR-0005)

- **Exported**: `⨟`, `opcompose`, `papply`, `pipe`, `flip`; the constructor-class operations whose
  names clash with nothing on the clash list (`chain`, `alt`, `zeroalt`, `contramap`, `bimap`,
  `dimap`, `lmap`, `rmap`, `idarrow`, `arr`, `arrfirst`, `arrsecond`, `arrsplit`, `fanout`); the
  `test_*_laws` kits.
- **Public, used qualified**: the aggregation protocol (`ChuiCore.init`, `ChuiCore.partial`,
  `ChuiCore.combine`, `ChuiCore.final`, `ChuiCore.iscommutative`), the aggregators
  (`ChuiCore.Sum`, …), `ChuiCore.neutral`, `ChuiCore.curry`, `ChuiCore.fmap`, `ChuiCore.pure`,
  `ChuiCore.ap`, `ChuiCore.traverse`, `ChuiCore.sequence`, and the trait hooks downstream code extends.
  Some of these would be convenient unqualified, but another common package exports the same name
  (DataFrames `combine`, Functors `fmap`, TypeClasses `neutral`/`pure`/`ap`/`curry`).
- **Internal**: everything else.

## Law kits

`using Test` gives the kits methods over sample collections; `using Test, Supposition` adds methods
over Supposition generators. Loading ChuiCore alone loads neither (CC-011).

```julia
using ChuiCore, Test
@testset "my monoid" begin
    test_monoid_laws(ChuiCore.Sum(), [[1, 2], Int[], [3]])
end
```
