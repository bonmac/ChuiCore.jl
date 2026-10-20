# Composition helpers (ADR-0006 for `⨟`; the rest fixed in the phase-2 plan).
# `⨟`/`opcompose` are CompositionsBase's binding, re-exported from ChuiCore.jl.

"""
    pipe(x, fs...)

Thread `x` through the functions `fs` from left to right: `pipe(x, f, g) == g(f(x))`, and
`pipe(x) == x`. The data-first counterpart of `x |> f |> g`, convenient when the functions are a
collection (`pipe(x, fs...)`).

Runtime cost: one call per function; the recursion unrolls for a tuple of functions.

```jldoctest
julia> using ChuiCore

julia> pipe(3, x -> x + 1, x -> 2x)
8
```
"""
pipe(x) = x
pipe(x, f, fs...) = pipe(f(x), fs...)

"""
    Curried{N}

The callable returned by [`curry`](@ref): it collects `N` arguments one call at a time, then calls
the wrapped function. Internal type; its printing and fields are not part of the API.
"""
struct Curried{N, F, A <: Tuple}
    f::F
    args::A
end

"""
    curry(f, n::Integer)
    curry(f, ::Val{n})

Turn an `n`-argument function into a chain of one-argument calls:
`curry(f, 3)(a)(b)(c) == f(a, b, c)`. `curry(f, 1)` takes one argument and calls `f`; `n` must be
at least 1. Use `curry(f, Val(n))` where `n` is a constant, to keep the result type inferable.

Runtime cost: one small immutable struct per partial call; no closures.

```jldoctest
julia> using ChuiCore

julia> ChuiCore.curry(+, 3)(1)(2)(3)
6
```
"""
curry(f, n::Integer) = curry(f, Val(Int(n)))
function curry(f::F, ::Val{N}) where {F, N}
    N isa Int && N >= 1 || throw(ArgumentError("curry needs n ≥ 1, got $N"))
    return Curried{N, F, Tuple{}}(f, ())
end

function (c::Curried{N})(x) where {N}
    args = (c.args..., x)
    return length(args) == N ? c.f(args...) : Curried{N, typeof(c.f), typeof(args)}(c.f, args)
end

"""
    PApply

The callable returned by [`papply`](@ref). Internal type; its fields are not part of the API.
"""
struct PApply{F, A <: Tuple, K <: NamedTuple}
    f::F
    args::A
    kwargs::K
end

(p::PApply)(rest...; kw...) = p.f(p.args..., rest...; p.kwargs..., kw...)

"""
    papply(f, args...; kwargs...)

Partial application: fix the leading positional arguments (and any keyword arguments) of `f`.
`papply(f, a, b)(c, d) == f(a, b, c, d)`; keywords given at the call override the fixed ones.

Named `papply`, not `partial`, because `ChuiCore.partial` is the aggregation protocol (CC-004,
ecosystem ADR-0009). Unlike `Base.Fix1`, it accepts any number of later arguments on every
supported Julia.

Runtime cost: one immutable struct holding the fixed arguments; the call splats them.

```jldoctest
julia> using ChuiCore

julia> papply(-, 10)(3)
7
```
"""
papply(f, args...; kwargs...) = PApply(f, args, NamedTuple(kwargs))

"""
    Flip

The callable returned by [`flip`](@ref). Internal type.
"""
struct Flip{F}
    f::F
end

(fl::Flip)(a, b, rest...; kw...) = fl.f(b, a, rest...; kw...)

"""
    flip(f)

Swap the first two arguments: `flip(f)(a, b, c...) == f(b, a, c...)`.

Runtime cost: none beyond the wrapped call.

```jldoctest
julia> using ChuiCore

julia> flip(-)(1, 10)
9
```
"""
flip(f) = Flip(f)
