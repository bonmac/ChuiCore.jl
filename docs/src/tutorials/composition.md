# Composition

```@meta
DocTestSetup = :(using ChuiCore)
```

This page builds small pipelines out of functions: `⨟` and `opcompose` to compose, `pipe` to
thread a value through, `papply`, `ChuiCore.curry` and `flip` to reshape a function's arguments.
Every block is a doctest; the state carries through the page.

## `⨟` composes left to right

Base's `∘` reads like mathematics: `(f ∘ g)(x) == f(g(x))`, so the function written last runs
first. `⨟` (typed `\bbsemi` then Tab) reads in the order things happen: `(f ⨟ g)(x) == g(f(x))`.
That is the contract CC-001.

```jldoctest composition
julia> inc(x) = x + 1;

julia> dbl(x) = 2x;

julia> (inc ⨟ dbl)(3)          # inc first, then dbl
8

julia> (inc ∘ dbl)(3)          # Base: dbl first, then inc
7

julia> (inc ⨟ dbl)(3) == dbl(inc(3)) == (dbl ∘ inc)(3)
true
```

`opcompose` is the ASCII name of the same function, and the prefix form takes any number of
functions:

```jldoctest composition
julia> opcompose === ⨟
true

julia> ⨟(inc, dbl, string)(3)
"8"

julia> (inc ⨟ dbl ⨟ string)(3)  # left-associative: (inc ⨟ dbl) ⨟ string
"8"
```

`⨟` binds tighter than `|>` and every comparison (precedence 12, as `∘`), so
`x |> f ⨟ g` means `x |> (f ⨟ g)`, while a mixed expression such as `v .> 3 ⨟ g` must be
parenthesised.

```jldoctest composition
julia> 3 |> inc ⨟ dbl
8
```

### No conflict with CompositionsBase or Accessors

ChuiCore does not define its own `⨟`: it re-exports the binding of
CompositionsBase.jl (contract CC-012,
ChuiCore's ADR-0006). Every package that does the same, Accessors included, exports *one*
binding, so `using` several of them together is not ambiguous:

```julia
using ChuiCore, CompositionsBase   # no "both export ⨟" ambiguity: it is the same binding
```

```jldoctest composition
julia> which(ChuiCore, :⨟)
CompositionsBase

julia> using Accessors

julia> Accessors.:⨟ === ChuiCore.:⨟
true

julia> (inc ⨟ dbl)(1)          # still unambiguous with both loaded
4
```

## `pipe`: thread a value through functions

`pipe(x, f, g, h)` is `h(g(f(x)))`, the data-first counterpart of `x |> f |> g |> h`. It is handy
when the functions are a collection you splat:

```jldoctest composition
julia> pipe(" Hello ", strip, lowercase, Symbol)
:hello

julia> steps = (abs, sqrt, x -> round(x; digits = 3));

julia> pipe(-2.0, steps...)
1.414

julia> pipe(5)                 # no functions: the value itself
5
```

## `papply`: fix leading arguments

`papply(f, a, b)(c) == f(a, b, c)`. Keywords can be fixed too; keywords given at the call win.

```jldoctest composition
julia> from10 = papply(-, 10);

julia> map(from10, [1, 2, 3])
3-element Vector{Int64}:
 9
 8
 7

julia> r2 = papply(round; digits = 2);

julia> r2(3.14159), r2(3.14159; digits = 4)
(3.14, 3.1416)
```

It is called `papply`, not `partial`, because `ChuiCore.partial` is a different thing: the step
function of the aggregation protocol (`init`, `partial`, `combine`, `final`) that ChuiFrames'
engine relies on.

```jldoctest composition
julia> ChuiCore.partial === papply
false
```

## `ChuiCore.curry`: one argument at a time

`ChuiCore.curry(f, n)` turns an `n`-argument function into a chain of one-argument calls. It is
public but **not exported**: TypeClasses.jl exports a `curry` of its own, and a second export
would make the bare name ambiguous for anyone using both. Use it qualified, or import it.

```jldoctest composition
julia> add3 = ChuiCore.curry((a, b, c) -> a + 10b + 100c, Val(3));

julia> add3(1)(2)(3)
321

julia> add1 = add3(1);         # partially applied, still waiting for two

julia> add1(0)(0), add1(5)(5)
(1, 551)
```

Pass `Val(n)` when `n` is a constant: the curried value then has a concrete type.

## `flip`: swap the first two arguments

```jldoctest composition
julia> flip(-)(1, 10)          # 10 - 1
9

julia> flip(vcat)(1, 2, 3)     # only the first two swap
3-element Vector{Int64}:
 2
 1
 3
```

## Point-free style, and when not to use it

Point-free code names the pipeline and never the data. In Julia it works well for short,
linear pipelines of named functions, where `⨟` reads like a sentence:

```jldoctest composition
julia> normalise = strip ⨟ lowercase ⨟ Symbol;

julia> map(normalise, [" Apple", "BANANA "])
2-element Vector{Symbol}:
 :apple
 :banana
```

It stops paying off as soon as you need to fix an argument in the middle or use a value twice.
Then Julia's own tools are clearer:

- `Base.Fix1(f, a)` is `x -> f(a, x)` and `Base.Fix2(f, b)` is `x -> f(x, b)`; Base functions
  return them already, as in `==(3)`, `in(xs)` or `isequal(x)`. Prefer them to
  `papply`/`flip` for a single fixed argument: every Julia programmer reads them.
- A closure or a `do` block is clearest when the argument appears more than once, or not in
  first or last position.

```jldoctest composition
julia> filter(>(2), [1, 2, 3, 4])         # Base.Fix2(>, 2)
2-element Vector{Int64}:
 3
 4

julia> map(Base.Fix2(-, 1), [10, 20])     # x - 1
2-element Vector{Int64}:
  9
 19

julia> map(x -> x^2 + x, [1, 2, 3])        # x twice: a closure beats any combinator
3-element Vector{Int64}:
  2
  6
 12
```

## What it costs

- **`⨟`, `∘`, `opcompose`:** building a composition is a `ComposedFunction`, a small immutable
  struct; calling it is the calls of its parts, inlined when the parts are known. The one trap:
  `ComposedFunction <: Function`, and Julia does not specialize a method on a `Function`
  argument that it only passes on. A function of yours that takes a composition and hands it to
  another function should give it a type parameter (`g(x, o::O) where {O}`), or each call
  dispatches dynamically (see [`ChuiCore.set`](@ref ChuiCore.set) for a measured case).
- **`pipe`:** one call per function; the recursion unrolls for a tuple of functions.
- **`papply`, `flip`, `ChuiCore.curry`:** one small immutable struct holding the fixed
  arguments, no closures; the call splats them. `curry(f, n)` with a runtime `n` is not
  inferable: use `curry(f, Val(n))`.
- **`Base.Fix1`/`Fix2` and closures:** the same, a struct holding the captured values. Pick
  whichever reads best; the cost does not decide it.

See also the reference: [`pipe`](@ref ChuiCore.pipe), [`papply`](@ref ChuiCore.papply),
[`flip`](@ref ChuiCore.flip),
[`ChuiCore.curry`](@ref ChuiCore.curry).
