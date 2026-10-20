# The transducer substrate (ADR-0003): transducer structs, reducing-function structs, the
# start/next/complete protocol, early termination and composition. The folds are in folds.jl.

"""
    Reduced(value)

Early termination (ADR-0003 §2): a reducing step returns `Reduced(acc)` to stop the fold. The
fold then stops supplying input and still runs `complete` once on `unreduced` of it. Build it with
[`ChuiCore.reduced`](@ref); test with [`ChuiCore.isreduced`](@ref). Cost: an immutable wrapper,
no allocation for an immutable accumulator.
"""
struct Reduced{T}
    value::T
end

"""
    reduced(x)

Wrap `x` in a [`ChuiCore.Reduced`](@ref) (an already reduced value is returned as is). A reducing
function returns this to stop the fold early. Cost: none beyond the wrapper.
"""
reduced(x) = Reduced(x)
reduced(x::Reduced) = x

"""
    unreduced(x)

The value inside a [`ChuiCore.Reduced`](@ref), or `x` itself. Cost: none.
"""
unreduced(x) = x
unreduced(x::Reduced) = x.value

"""
    isreduced(x)::Bool

Whether `x` is a [`ChuiCore.Reduced`](@ref). Cost: a type check, folded at compile time.
"""
isreduced(x) = x isa Reduced

"""
    Transducer

Supertype of ChuiCore's transducers (ADR-0003 §1): immutable structs that describe a step of a
reduction (`Map`, `Filter`, `MapCat`, `Take`, `TakeWhile`, `Scan`, `Partition`, `Composed`).
Transducers have **no call method**: they are not callables, so CC-001's composition law does not
apply to `a ⨟ b`; turn one into a reducing function with [`ChuiCore.asrf`](@ref), or fold with
[`ChuiCore.foldxl`](@ref). Compose with `a ⨟ b` ("a, then b"), which equals `b ∘ a`.

A user transducer `T <: Transducer` defines `next(rf::R{<:T}, acc, x)` (and, when it keeps state,
`start` and `complete`, see [`ChuiCore.R`](@ref)). It stays out of parallel folds unless it
declares [`ChuiCore.isstateless`](@ref).

Composing a transducer with a plain function (`Map(f) ⨟ g`) is **not supported**: it builds
Base's `ComposedFunction`, which no fold accepts.
"""
abstract type Transducer end

"""
    Map(f)

Transducer that sends `f(x)` downstream for each input `x`. Stateless
([`ChuiCore.isstateless`](@ref) is `true`). Cost: one call of `f` per element; no allocation, no
dynamic dispatch for a concretely typed `f`.
"""
struct Map{F} <: Transducer
    f::F
end

"""
    Filter(p)

Transducer that sends `x` downstream only when `p(x)` is `true`. Stateless. Cost: one call of `p`
per element; no allocation.
"""
struct Filter{P} <: Transducer
    p::P
end

"""
    MapCat(f)

Transducer that sends each element of the iterable `f(x)` downstream, in order (a flat map). It
conveys a downstream `Reduced` out of its inner loop. Stateless. Cost: one call of `f` and one
iteration of its result per element; no allocation when `f` returns a tuple or a range.

Not to be confused with CC-007's `MapM(f, inner)`, an **aggregator** that applies `f` to each
element before an inner aggregator: `MapM` maps one value to one value inside an aggregation,
while `MapCat` maps one value to any number of values inside a transducer pipeline.
"""
struct MapCat{F} <: Transducer
    f::F
end

"""
    Take(n)

Transducer that sends the first `n` inputs downstream, then stops the fold (`Reduced`) right after
the `n`-th, so no further input is read. `n ≥ 0`. Stateful (the count lives in the accumulator,
created by `start`), so one `Take(3)` can be reused across folds. Cost: an `Int` counter per fold,
no allocation.
"""
struct Take <: Transducer
    n::Int
    function Take(n::Integer)
        n >= 0 || throw(ArgumentError("Take(n) needs n ≥ 0, got $n"))
        return new(Int(n))
    end
end

"""
    TakeWhile(p)

Transducer that sends inputs downstream while `p(x)` is `true` and stops the fold at the first `x`
for which it is `false`. It keeps no state, but it is **not** stateless for parallel folds
([`ChuiCore.isstateless`](@ref) is `false`): per partition it would stop each partition separately.
Cost: one call of `p` per element; no allocation.
"""
struct TakeWhile{P} <: Transducer
    p::P
end

"""
    Scan(op, init)

Transducer that sends the running accumulation downstream: for inputs `x₁, x₂, …` it emits
`s₁ = op(init, x₁)`, `s₂ = op(s₁, x₂)`, …. Stateful (the running value lives in the accumulator).
Cost: one call of `op` per element; no allocation when `op` keeps the type of `init` (otherwise the
fold loses type stability).
"""
struct Scan{F, T} <: Transducer
    op::F
    init::T
end

"""
    Partition{T}(n)
    Partition(n) = Partition{Any}(n)

Transducer that groups inputs into chunks of `n` and sends each full chunk downstream as a fresh
`Vector{T}` (a copy, safe to keep). On `complete` it flushes the remainder as a last, shorter
chunk, **unless the downstream has reduced** (its buffer is cleared before every downstream call,
so nothing is pending then). `n ≥ 1`. Stateful. Cost: one buffer of capacity `n` per fold
(created by `start`), plus one `Vector{T}` per emitted chunk.
"""
struct Partition{T} <: Transducer
    n::Int
    function Partition{T}(n::Integer) where {T}
        n >= 1 || throw(ArgumentError("Partition(n) needs n ≥ 1, got $n"))
        return new{T}(Int(n))
    end
end
Partition(n::Integer) = Partition{Any}(n)

"""
    Composed(xfs::Tuple)

A pipeline of transducers applied in data order: `Composed((a, b, c))` is `a ⨟ b ⨟ c`. Built by
`a ⨟ b` or `b ∘ a`, which flatten nested compositions into one tuple; `Composed(())` is the
identity pipeline. Field `xfs`. Cost: none of its own; the pipeline compiles to nested
[`ChuiCore.R`](@ref) structs with concrete types.
"""
struct Composed{T <: Tuple} <: Transducer
    xfs::T
end

_xfs(x::Transducer) = (x,)
_xfs(x::Composed) = x.xfs

# `a ⨟ b` (CompositionsBase's `opcompose`) is `b ∘ a`: data flows through `a`, then `b`.
Base.:∘(b::Transducer, a::Transducer) = Composed((_xfs(a)..., _xfs(b)...))

"""
    isstateless(xf)::Bool

Whether `xf` may be run per partition by a parallel executor (ADR-0003 §4). **Fail-closed:** the
default is `false` for every value; only `Map`, `Filter`, `MapCat` and a `Composed` of only those
return `true`. Early-terminating transducers (`Take`, `TakeWhile`) are not stateless. A user
transducer that opts in (`ChuiCore.isstateless(::MyXf) = true`) promises that `start` and
`complete` pass the accumulator through unchanged and that `next` keeps no state. Only
`isstateless` pipelines may run per partition, in ChuiCore's executors or downstream ones; all
others run sequentially through [`ChuiCore.foldxl`](@ref). Cost: dispatch only, a constant.
"""
isstateless(_) = false
isstateless(::Union{Map, Filter, MapCat}) = true
isstateless(x::Composed) = all(isstateless, x.xfs)

"""
    Bottom(op)

The innermost reducing function: wraps a plain binary `op(acc, x)` (ADR-0003 §1). `next` calls
`op`; `start` and `complete` return the accumulator unchanged. `op` may return a
[`ChuiCore.Reduced`](@ref) to stop the fold. Field `op`. Cost: none beyond `op`.
"""
struct Bottom{F}
    op::F
end

"""
    R(xf, inner)

A reducing function: the transducer `xf` in front of the reducing function `inner` (an `R` or a
[`ChuiCore.Bottom`](@ref)). Built by [`ChuiCore.asrf`](@ref), never a closure, so its type is
concrete and inspectable (`R{Map{typeof(f)}, R{Filter{typeof(p)}, Bottom{typeof(+)}}}`). Fields
`xf`, `inner`.

To write a transducer `T`: define `ChuiCore.next(rf::R{<:T}, acc, x)`, calling
`next(rf.inner, …)` zero or more times and returning the new accumulator (or a `Reduced` to stop).
A stateful one also defines `start(rf::R{<:T}, acc)`, returning its own wrapper struct around
`start(rf.inner, acc)` (state is created there, once per fold; never in a `Ref` captured at
construction), and `complete(rf::R{<:T}, w)`, which may flush into `rf.inner` (not after the
downstream has reduced) and then calls `complete(rf.inner, …)` exactly once. When the downstream
reduces, return `Reduced(wrapper)`, keeping `Reduced` outermost. Cost: none of its own.
"""
struct R{X <: Transducer, I}
    xf::X
    inner::I
end

_asrf(op) = Bottom(op)
_asrf(rf::Union{R, Bottom}) = rf

"""
    asrf(xf, op)

The reducing function of the transducer `xf` in front of the binary operation `op` (or of an
existing reducing function): an [`ChuiCore.R`](@ref) struct, or a [`ChuiCore.Bottom`](@ref) for an
empty `Composed`. Drive it with `start`, `next` and `complete`. Cost: builds an immutable struct;
no allocation for isbits fields.
"""
asrf(xf::Transducer, op) = R(xf, _asrf(op))
asrf(xf::Composed, op) = _apply(xf.xfs, _asrf(op))
_apply(::Tuple{}, rf) = rf
_apply(t::Tuple, rf) = asrf(first(t), _apply(Base.tail(t), rf))

"""
    start(rf, acc)

Protocol (ADR-0003 §2): the accumulator a fold begins with, built from the user's initial value
`acc`. Stateful transducers create their per-fold state here (once per fold, once per partition),
wrapping the inner accumulator; stateless ones pass `acc` through. Cost: a stateful layer's state
(e.g. one buffer for `Partition`); nothing for stateless layers.
"""
start(::Bottom, acc) = acc
start(rf::R, acc) = start(rf.inner, acc)

"""
    next(rf, acc, x)

Protocol (ADR-0003 §2): one reduction step; returns the new accumulator, or a
[`ChuiCore.Reduced`](@ref) to stop the fold. Every transducer defines a method for `R{<:T}`.
Cost: the step of each layer; stateless layers neither allocate nor dispatch dynamically.
"""
next(rf::Bottom, acc, x) = rf.op(acc, x)

"""
    complete(rf, acc)

Protocol (ADR-0003 §2): the completion step, run **exactly once** per fold, also after early
termination (on the unreduced accumulator). Stateful layers flush pending state into their
downstream (never after it has reduced), unwrap their state and complete the inner reducing
function once. Cost: a layer's flush, if any.
"""
complete(::Bottom, acc) = acc
complete(rf::R, acc) = complete(rf.inner, acc)

# Per-fold state of a stateful layer, carried in the accumulator: (state, inner accumulator).
struct _State{S, A}
    state::S
    acc::A
end

# Rewrap after a downstream call, keeping `Reduced` outermost so outer layers still see their state.
@inline _rewrap(s, a) = a isa Reduced ? Reduced(_State(s, a.value)) : _State(s, a)

next(rf::R{<:Map}, acc, x) = next(rf.inner, acc, rf.xf.f(x))
next(rf::R{<:Filter}, acc, x) = rf.xf.p(x) ? next(rf.inner, acc, x) : acc
next(rf::R{<:TakeWhile}, acc, x) = rf.xf.p(x) ? next(rf.inner, acc, x) : Reduced(acc)

function next(rf::R{<:MapCat}, acc, x)
    for y in rf.xf.f(x)
        a = next(rf.inner, acc, y)
        a isa Reduced && return a
        acc = a
    end
    return acc
end

start(rf::R{Take}, acc) = _State(0, start(rf.inner, acc))
function next(rf::R{Take}, w::_State, x)
    seen = w.state
    seen >= rf.xf.n && return Reduced(w)          # only for Take(0)
    seen += 1
    a = next(rf.inner, w.acc, x)
    a isa Reduced && return Reduced(_State(seen, a.value))
    return seen < rf.xf.n ? _State(seen, a) : Reduced(_State(seen, a))
end
complete(rf::R{Take}, w::_State) = complete(rf.inner, w.acc)

start(rf::R{<:Scan}, acc) = _State(rf.xf.init, start(rf.inner, acc))
function next(rf::R{<:Scan}, w::_State, x)
    s = rf.xf.op(w.state, x)
    return _rewrap(s, next(rf.inner, w.acc, s))
end
complete(rf::R{<:Scan}, w::_State) = complete(rf.inner, w.acc)

function start(rf::R{Partition{T}}, acc) where {T}
    buf = Vector{T}()
    sizehint!(buf, rf.xf.n)
    return _State(buf, start(rf.inner, acc))
end
function next(rf::R{<:Partition}, w::_State, x)
    buf = w.state
    push!(buf, x)
    length(buf) < rf.xf.n && return w
    chunk = copy(buf)
    empty!(buf)                                   # clear before calling downstream (Clojure rule)
    return _rewrap(buf, next(rf.inner, w.acc, chunk))
end
function complete(rf::R{<:Partition}, w::_State)
    buf = w.state
    a = w.acc
    if !isempty(buf)                              # empty whenever the downstream has reduced
        a = unreduced(next(rf.inner, a, copy(buf)))
        empty!(buf)
    end
    return complete(rf.inner, a)
end
