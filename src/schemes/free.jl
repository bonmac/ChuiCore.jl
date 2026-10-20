# Data types à la carte (Swierstra 2008) and the freer monad (Kiselyov & Ishii 2015):
# docs/research/recursion-schemes-free-laziness.md §4, Recommendations 5–6. ChuiTypes owns the
# effect runtime; this is the minimal program-as-data pattern: instructions are plain structs,
# programs are `Free` values, an interpreter is a loop.

const _SALT_INL = 0x6a3f1c8e5b2d7094 % UInt
const _SALT_INR = 0x3d9b6e2a7c1f4058 % UInt

# ---------------------------------------------------------------------------------------------
# Coproducts of signatures

"""
    Coproduct{F, G}

The coproduct of two signatures or base functors (Swierstra's `f :+: g`): a value is either
[`ChuiCore.Inl`](@ref)`{F,G}(x)` with `x isa F`, or [`ChuiCore.Inr`](@ref)`{F,G}(x)` with `x`
in `G`. `F` and `G` are types, usually the abstract types of two instruction sets
(`Coproduct{KV, Log}`); nest to the right for more (`Coproduct{KV, Coproduct{Log, Err}}`).
Build values with [`ChuiCore.inj`](@ref), take them apart with [`ChuiCore.prj`](@ref).

Tag `CoproductTag()`: Functor and Traversable, delegating to the payload (so `cata` runs over a
`Fix` of coproduct layers when both components are Functors). Dispatch on instruction types
already gives open sums; a `Coproduct` adds a closed, nameable signature.

**Cost:** one box per injection (field `Any`), one extra dispatch per `fmap` or handler call.
"""
abstract type Coproduct{F, G} end

"""
    Inl{F, G}(x)

The left injection of a [`ChuiCore.Coproduct`](@ref)`{F,G}` (`x isa F`). `==`, `isequal` and
`hash` are structural; `Inl` and `Inr` values are never equal.
"""
struct Inl{F, G} <: Coproduct{F, G}
    x::Any
end

"""
    Inr{F, G}(x)

The right injection of a [`ChuiCore.Coproduct`](@ref)`{F,G}` (`x` in `G`, itself possibly an
injection into a nested coproduct). `==`, `isequal` and `hash` are structural.
"""
struct Inr{F, G} <: Coproduct{F, G}
    x::Any
end

Base.:(==)(a::Inl{F, G}, b::Inl{F, G}) where {F, G} = a.x == b.x
Base.:(==)(a::Inr{F, G}, b::Inr{F, G}) where {F, G} = a.x == b.x
Base.isequal(a::Inl{F, G}, b::Inl{F, G}) where {F, G} = isequal(a.x, b.x)
Base.isequal(a::Inr{F, G}, b::Inr{F, G}) where {F, G} = isequal(a.x, b.x)
Base.hash(a::Inl{F, G}, h::UInt) where {F, G} = hash(a.x, hash(Coproduct{F, G}, h ⊻ _SALT_INL))
Base.hash(a::Inr{F, G}, h::UInt) where {F, G} = hash(a.x, hash(Coproduct{F, G}, h ⊻ _SALT_INR))

"""
    CoproductTag()

Constructor-class tag (ADR-0001 §3) of every [`ChuiCore.Coproduct`](@ref): Functor and
Traversable, delegating to the payload's instance (an `ArgumentError` if the payload has none).
A singleton: dispatch on it costs nothing at run time.
"""
struct CoproductTag end

constructorclass(::Type{<:Coproduct}) = CoproductTag()
FunctorStyle(::CoproductTag) = IsFunctor()
TraversableStyle(::CoproductTag) = IsTraversable()
fmap(::IsFunctor, f, c::Inl{F, G}) where {F, G} = Inl{F, G}(fmap(f, c.x))
fmap(::IsFunctor, f, c::Inr{F, G}) where {F, G} = Inr{F, G}(fmap(f, c.x))
traverse(::IsTraversable, tag, f, c::Inl{F, G}) where {F, G} = fmap(Inl{F, G}, traverse(tag, f, c.x))
traverse(::IsTraversable, tag, f, c::Inr{F, G}) where {F, G} = fmap(Inr{F, G}, traverse(tag, f, c.x))

# The components of a concrete coproduct type, or `nothing`. One argument: no ambiguity.
_parts(::Type{Coproduct{F, G}}) where {F, G} = (F, G)
_parts(::Type) = nothing

# Does the signature `S` contain values of type `T` (as `T <: S` or inside a component)?
function _injects(S, T)
    T <: S && return true
    p = _parts(S)
    return p !== nothing && (_injects(p[1], T) || _injects(p[2], T))
end

"""
    inj(S, x)

Inject the instruction `x` into the signature `S` (Swierstra's `inj`, class `:<:`): `x` itself
when `x isa S` (reflexive); otherwise, for `S = Coproduct{F,G}`, `Inl{F,G}(inj(F, x))` when `F`
contains `x`'s type, else `Inr{F,G}(inj(G, x))`, so nested right coproducts work
(`inj(Coproduct{KV, Coproduct{Log, Err}}, Throw("e"))` is `Inr(Inr(Throw("e")))`). A type that
`S` does not contain throws an `ArgumentError`.

One method with type-level checks (not one method per case), so the method table has no
ambiguities. **Cost:** the checks are on types and usually fold at compile time; one box per
coproduct level.
"""
function inj(::Type{S}, x) where {S}
    x isa S && return x
    _injects(S, typeof(x)) ||
        throw(ArgumentError("cannot inject a $(typeof(x)) into the signature $S: no component contains it"))
    F, G = _parts(S)
    return _injects(F, typeof(x)) ? Inl{F, G}(inj(F, x)) : Inr{F, G}(inj(G, x))
end

"""
    prj(T, x) -> Some(y) or nothing

Project `x` onto `T` (Swierstra's `prj`): `Some(x)` when `x isa T`; for an `Inl`/`Inr`, the
projection of its payload; otherwise `nothing`. `prj(T, inj(S, y)) == Some(y)` when `y isa T`.

**Cost:** one `isa` per coproduct level.
"""
function prj(::Type{T}, x) where {T}
    x isa T && return Some(x)
    x isa Union{Inl, Inr} && return prj(T, x.x)
    return nothing
end

# ---------------------------------------------------------------------------------------------
# The freer monad

const _COST_FREE = """
**Cost:** a program is data: ≈0.5–1.2 µs and ≈0.4–0.5 KB per interpreted instruction in the
research measurement, 80–200× a plain loop. Free monads are for describing programs and plans
(data to inspect, optimise and interpret), not for inner loops. Nothing infers (`Any`).
"""

"""
    Free

A program in the freer monad (Kiselyov & Ishii 2015): either [`ChuiCore.Pure`](@ref)`(x)` (done,
with result `x`) or [`ChuiCore.Impure`](@ref) (one instruction plus its continuation). Build
programs with [`ChuiCore.liftF`](@ref), `chain`, `fmap`, `ap` and `pure(FreeTag(), x)`; run
them with [`ChuiCore.interpret`](@ref) or [`ChuiCore.foldfree`](@ref). Instructions need no
Functor instance. Tag [`ChuiCore.FreeTag`](@ref)`()`: Functor, Applicative, Monad.

Binding is O(1) in both associations (the continuation is a tree, re-associated during
interpretation), so left-nested `chain`s stay linear where the classic `Free` encoding is
quadratic (research: 43–47 s against 5–12 ms at 10^4 left binds).

$_COST_FREE
"""
abstract type Free end

"""
    Pure(x)

A finished [`ChuiCore.Free`](@ref) program with result `x`; `pure(FreeTag(), x) == Pure(x)`.
"""
struct Pure{T} <: Free
    value::T
end

# The type-aligned continuation queue (FTCQueue), internal: a leaf holds one continuation
# `x -> Free`, a node composes its left queue before its right one.
abstract type _Queue end
struct _Leaf{F} <: _Queue
    f::F
end
struct _Node <: _Queue
    l::_Queue
    r::_Queue
end

"""
    Impure(op, k)

A [`ChuiCore.Free`](@ref) program that performs the instruction `op` and continues with `k`
applied to the instruction's answer. `k` is an internal continuation tree: build `Impure`
values with [`ChuiCore.liftF`](@ref) and `chain`, not by hand. Field `op` is public (an
interpreter dispatches on it).
"""
struct Impure <: Free
    op::Any
    k::_Queue
end

"""
    FreeTag()

Constructor-class tag (ADR-0001 §3) of [`ChuiCore.Free`](@ref) programs: Functor, Applicative
(`pure(FreeTag(), x) == Pure(x)`), Monad. `chain` and `fmap` on an `Impure` are O(1) (they
append to the continuation tree). A singleton: dispatch on it costs nothing at run time.
"""
struct FreeTag end

"""
    liftF(op)
    liftF(S, op) = liftF(inj(S, op))

The one-instruction program: perform `op` and return its answer. The two-argument form first
injects `op` into the signature `S` (see [`ChuiCore.inj`](@ref)).

**Cost:** one `Impure` and one continuation leaf.
"""
liftF(op) = Impure(op, _Leaf(Pure))
liftF(::Type{S}, op) where {S} = liftF(inj(S, op))

struct _PureAfter{F} <: Function
    f::F
end
(p::_PureAfter)(x) = Pure(p.f(x))

constructorclass(::Type{<:Free}) = FreeTag()
for C in (:Functor, :Applicative, :Monad)
    @eval $(Symbol(C, :Style))(::FreeTag) = $(Symbol(:Is, C))()
end
fmap(::IsFunctor, f, m::Pure) = Pure(f(m.value))
fmap(::IsFunctor, f, m::Impure) = Impure(m.op, _Node(m.k, _Leaf(_PureAfter(f))))
pure(::FreeTag, x) = Pure(x)
ap(::IsApplicative, ff::Free, fx::Free) = chain(f -> fmap(f, fx), ff)
chain(::IsMonad, f, m::Pure) = f(m.value)
chain(::IsMonad, f, m::Impure) = Impure(m.op, _Node(m.k, _Leaf(f)))

@noinline function _notfree(m)
    throw(ArgumentError("a Free continuation must return a Free program (Pure or Impure), got a $(typeof(m))"))
end

# Apply the continuation queue `q` to `x`, in a loop: rotate a left-nested node to reach the
# leftmost continuation, apply it, and either continue with a `Pure` result or return an
# `Impure` whose continuation is the rest of the queue appended.
function _qapply(q::_Queue, x)
    while true
        q isa _Leaf && return q.f(x)
        l = (q::_Node).l
        r = q.r
        while l isa _Node
            r = _Node(l.r, r)
            l = l.l
        end
        m = (l::_Leaf).f(x)
        if m isa Pure
            x = m.value
            q = r
        elseif m isa Impure
            return Impure(m.op, _Node(m.k, r))
        else
            _notfree(m)
        end
    end
    return nothing # unreachable
end

"""
    interpret(handler, m::Free)

Run the program `m`: for each instruction `op`, `handler(op)` performs it and returns the answer
fed to the continuation; the result is the final `Pure` value. The interpreter is an explicit
`while` loop (a trampoline), never recursive, so programs of 10^6 instructions run in constant
stack, in either bind association. A handler is any callable, usually one method per instruction
type, and may hold state (a callable struct). For a [`ChuiCore.Coproduct`](@ref) signature
combine one handler per component with [`ChuiCore.cohandler`](@ref).

$_COST_FREE
"""
function interpret(handler, m::Free)
    while m isa Impure
        m = _qapply(m.k, handler(m.op))
    end
    m isa Pure || _notfree(m)
    return m.value
end

struct _CoHandler{L, R}
    left::L
    right::R
end
(h::_CoHandler)(op::Inl) = h.left(op.x)
(h::_CoHandler)(op::Inr) = h.right(op.x)

"""
    cohandler(hf, hg)
    cohandler(h1, h2, h3, ...) = cohandler(h1, cohandler(h2, h3, ...))

A handler for the signature `Coproduct{F,G}` from a handler `hf` for `F` and one `hg` for `G`:
it calls `hf(x)` on `Inl(x)` and `hg(x)` on `Inr(x)`. With more handlers it nests to the right,
matching `Coproduct{F, Coproduct{G, H}}`. Pass it to [`ChuiCore.interpret`](@ref) (or, with
handlers returning monadic values, as the natural transformation of
[`ChuiCore.foldfree`](@ref)). An instruction outside the signature is a `MethodError`.
`==` compares the component handlers.

**Cost:** one dispatch per coproduct level per instruction.
"""
cohandler(hf, hg) = _CoHandler(hf, hg)
cohandler(h1, h2, h3, rest...) = _CoHandler(h1, cohandler(h2, h3, rest...))

struct _FoldK{T, N, Q}
    tag::T
    nt::N
    q::Q
end
(k::_FoldK)(x) = foldfree(k.tag, k.nt, _qapply(k.q, x))

"""
    foldfree(tag, nt, m::Free)

Interpret the program `m` into the Monad of class `tag`: each instruction `op` becomes the
monadic value `nt(op)` (a natural transformation from instructions to `tag`), sequenced with
`chain`; `Pure(x)` becomes `pure(tag, x)`. For example `foldfree(MaybeTag(), nt, m)` stops at
the first instruction `nt` maps to `nothing`, and `ArrayTag()` explores every answer.

**Stack:** recursive through `chain`: with a strict target monad (Maybe, Identity, Array) the
depth grows with the number of instructions run, about 4 frames each, so long programs (beyond
roughly 10^4 instructions) can overflow. For long programs use [`ChuiCore.interpret`](@ref),
which is a loop, or a target monad whose `chain` is itself stack-safe.

$_COST_FREE
"""
foldfree(tag, nt, m::Pure) = pure(tag, m.value)
foldfree(tag, nt, m::Impure) = chain(_FoldK(tag, nt, m.k), nt(m.op))
