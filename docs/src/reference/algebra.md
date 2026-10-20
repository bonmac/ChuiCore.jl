# Reference: monoids and aggregators

The aggregation protocol (`init`, `partial`, `combine`, `final`, `iscommutative`), the algebra
classes, `neutral`, `combineall`, the built-in aggregators and the combinators. All public, not
exported: write `ChuiCore.Sum` or `using ChuiCore: Sum`. Tutorial:
[monoids and aggregators](../tutorials/monoids.md).

**Contract items** (`<root>/contracts/chui-core.md`):

| ID | Item | Names |
|---|---|---|
| CC-004 | The aggregator protocol and its laws | `init`, `partial`, `combine`, `final` |
| CC-005 | The `iscommutative` trait and the ordering obligation | `iscommutative` |
| CC-006 | Empty-input semantics | `init`, `final` |
| CC-007 | Built-in aggregators and their classification | `Sum`, `Prod`, `Count`, `CountTrue`, `AnyM`, `AllM`, `Max`, `Min`, `Extrema`, `First`, `Last`, `Mean`, `ReduceM`, `MapM` |
| CC-013 | These names are public, not exported | all of the above |

`Moments`' constructor, `neutral`, `AlgebraClass`, `combineall` and `default_monoid` are
PROVISIONAL in the contract.

```@autodocs
Modules = [ChuiCore]
Private = false
Pages = [
    "algebra/aggregators.jl", "algebra/algebra.jl", "algebra/combinators.jl", "algebra/lawtables.jl",
    "algebra/protocol.jl", "algebra/statistics.jl", "algebra/tolerance.jl",
]
```
