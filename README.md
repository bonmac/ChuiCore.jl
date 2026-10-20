# ChuiCore.jl

The functional-programming core of the Chui ecosystem: left-to-right composition, algebraic
structures as Holy traits with reusable law-test kits, monoids and aggregators built for
partitioned data, a transducer substrate, recursion schemes, free monads, optics, laziness, and a
name-conflict banner. It depends on no other Chui package; ChuiTypes and ChuiFrames build on it.

**Status:** pre-release (version 0.0.1, not registered yet). Supports Julia 1.10 (LTS) and later.

## Installation

Once v0.1.0 is registered in the Chui personal registry:

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

## Quick example

```julia
julia> using ChuiCore

julia> f = (x -> x + 1) ⨟ (x -> 2x);   # left to right: first +1, then ×2

julia> f(3)
8

julia> ChuiCore.foldxl(+, ChuiCore.Map(abs2) ⨟ ChuiCore.Filter(iseven), 1:10; init = 0)
220

julia> m = ChuiCore.Mean();             # an aggregator: merge per-partition results, then finalize

julia> a = ChuiCore.partial(m, ChuiCore.init(m), [1.0, 2.0]);

julia> b = ChuiCore.partial(m, ChuiCore.init(m), [3.0]);

julia> ChuiCore.final(m, ChuiCore.combine(m, a, b))
2.0
```

Aggregators, transducers and most other names are public but not exported, so they never clash
with DataFrames, Transducers.jl, Accessors.jl, Functors.jl or TypeClasses.jl: write them qualified
or import them with `using ChuiCore: Mean, Map`.

## Documentation

The Documenter site (tutorials, how-to recipes, explanation, reference) is built from `docs/`:

```sh
julia scripts/ci.jl docs      # builds docs/build/ and runs every doctest
```

It is not deployed yet (no public repository). Start at `docs/src/index.md`; tutorials are in
`docs/src/tutorials/`, design notes in `docs/src/explanation/`, decisions in `docs/adr/`.

## Development

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
julia scripts/ci.jl --list      # every CI job, runnable locally
```

Agent and process instructions: [`CLAUDE.md`](CLAUDE.md). Current state: [`HANDOFF.md`](HANDOFF.md).
Changes: [`CHANGELOG.md`](CHANGELOG.md).

## License

MIT; see [`LICENSE`](LICENSE).
