# Reference: core

Composition, law kits, the aggregation protocol and aggregators, and the constructor classes.
Public names are used qualified (`ChuiCore.combine`) or imported with `using ChuiCore: combine`.
The phase-3 areas have their own pages: [Transducers](transducers.md),
[Recursion schemes and free monads](schemes.md), [Optics](optics.md),
[Laziness and the conflict banner](lazy.md).

```@autodocs
Modules = [ChuiCore]
Private = false
Pages = [
    "compose.jl", "laws.jl",
    "algebra/aggregators.jl", "algebra/algebra.jl", "algebra/combinators.jl", "algebra/lawtables.jl",
    "algebra/protocol.jl", "algebra/statistics.jl", "algebra/tolerance.jl",
    "classes/class_laws.jl", "classes/classes.jl", "classes/core.jl", "classes/instances.jl",
    "classes/owned.jl",
]
Filter = t -> t !== ChuiCore
```

## Documented internals

```@autodocs
Modules = [ChuiCore]
Public = false
Filter = t -> t !== ChuiCore
```
