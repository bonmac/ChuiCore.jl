# Export tiers and the clash list

```@meta
DocTestSetup = :(using ChuiCore)
```

Every ChuiCore name sits in exactly one of three tiers (ChuiCore ADR-0005; contract CC-013):

| Tier | How you write it | Stability | Count (0.0.1) |
|---|---|---|---|
| **Exported** | bare, after `using ChuiCore` | contract / semver | 35 |
| **Public, not exported** | `ChuiCore.combine`, or `using ChuiCore: combine` | contract / semver | 153 |
| **Internal** | do not use | none | the rest |

Public names are declared with `@compat public` (from Compat.jl): the `public` keyword on Julia
1.11 and later, a no-op on 1.10, where `public` is a syntax error. On 1.10 the public tier is
therefore documented here and in the docstrings but not visible to `Base.ispublic`.

```jldoctest tiers
julia> using ChuiCore

julia> Base.isexported(ChuiCore, :papply), Base.isexported(ChuiCore, :combine)
(true, false)

julia> Base.ispublic(ChuiCore, :combine)   # Julia ≥ 1.11
true

julia> using ChuiCore: Sum, init, partial, final

julia> final(Sum(), partial(Sum(), init(Sum()), [1, 2, 3]))
6
```

## The exported vocabulary

- Composition: `⨟`, `opcompose` (CompositionsBase's own bindings, re-exported: CC-001, CC-012),
  `papply`, `pipe`, `flip`.
- Constructor-class operations whose names clash with nothing on the list: `chain`, `alt`,
  `zeroalt`, `contramap`, `bimap`, `dimap`, `lmap`, `rmap`, and the arrow operations `idarrow`,
  `arr`, `arrfirst`, `arrsecond`, `arrsplit`, `fanout`.
- The law kits `test_*_laws` (stubs until `Test` is loaded; CC-011).

Everything else that is meant for you is public: the aggregation protocol and the aggregators,
`neutral`, `curry`, `fmap`, `pure`, `ap`, `traverse`, `sequence`, the trait hooks downstream code
extends, transducers, recursion schemes, free monads, optics, laziness and the banner.

## The clash rule

A name may be exported only if **no module on the clash list exports a different binding with the
same name**. The list (ADR-0005 §2) is Base, Core, `Base.Iterators`, the standard libraries
Dates, LinearAlgebra, Random, Statistics and Test, and the packages DataFrames, Transducers,
Accessors, Setfield, Functors, TypeClasses, ConstructionBase and CompositionsBase (whose `⨟` and
`opcompose` ChuiCore re-exports as the same binding, so they cannot clash). Passing the rule does
not export a name: `init` and `partial` pass and stay public, so the four-function protocol stays
in one tier.

Why it matters: when two modules you `using` both export a name as **different** bindings, Julia
exports neither of them unqualified, and every bare use in your module fails:

```julia
module A; export combine; combine(x) = :a; end
module B; export combine; combine(x) = :b; end
using .A, .B
combine(1)   # ERROR: UndefVarError: `combine` not defined in `Main`
             # Hint: It looks like two or more modules export different bindings with this name, …
```

(Julia 1.13.2's wording; 1.10.12 prints `WARNING: both B and A export "combine"; uses of it in
module Main must be qualified` instead of the hint. The failure is the same.) Adding a method to an
existing function, by contrast, is never a clash: ChuiCore's `Base.show` methods are methods of
Base's binding. The [conflict banner](../tutorials/conflict-banner.md) reports real clashes at load
time.

A `:quality` test, "ADR-0005 clash list" in `test/quality_tests.jl`, installs every package on the
list in its own environment and checks ChuiCore's exports against them, on stable Julia.

## Why `neutral`, `curry`, `pure`, `ap` and `fmap` are public but not exported

These are the names a functional-programming user most expects to write bare, and each fails the
clash rule:

| Name | Exported, as a different binding, by |
|---|---|
| `fmap` | Functors.jl (0.4.12) |
| `neutral` | TypeClasses.jl (1.1.0) |
| `curry` | TypeClasses.jl |
| `pure` | TypeClasses.jl |
| `ap` | TypeClasses.jl |

Exporting them would break every user who also loads Functors.jl or TypeClasses.jl: their bare `fmap` or `pure` would stop resolving. So ChuiCore keeps
them public (ecosystem ADR-0009 as amended, recorded in CC-013). Bring them into scope by name
when you want them bare; an explicit import takes precedence over `using`, so it also resolves a
clash in your favour:

```jldoctest tiers
julia> using ChuiCore: fmap, pure, neutral, curry

julia> fmap(x -> x + 1, [1, 2, 3])
3-element Vector{Int64}:
 2
 3
 4

julia> curry(+, 2)(1)(2)
3

julia> neutral(ChuiCore.Sum())
0
```

The same reasoning keeps other public names unexported: `combine` (DataFrames, TypeClasses),
`Map`, `Filter`, `Count` and `foldxl` (Transducers), `set` and `modify` (Accessors, Setfield), and
`Lens` (Setfield). The aggregators (`Sum`, `Max`, …) stay public with the protocol they serve, so
aggregation code is written one way: `ChuiCore.Sum()` next to `ChuiCore.combine`. (Inside the one
flat namespace, the aggregator also took the name `Sum`, so the functor coproduct is called
`Coproduct`.)

## Moving a name between tiers

Moving a name between tiers changes the contract (ecosystem ADR-0010): exporting a public name
can break users through a new clash, and un-exporting one breaks bare uses. It needs a contract
change and a release note.

## What it costs

Nothing at run time: tiers are names, and a qualified call compiles to the same code as a bare
one.
