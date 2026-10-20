# Constructor classes, part 2: ChuiCore's own instance types (ADR-0001 §3). Base functions get
# methods only on these owned types.

const _SALT_IDENTITY = 0x5d3a2f0e8c1b7a64 % UInt
const _SALT_ZIP = 0x1f9e4b7c2d6a8035 % UInt
const _SALT_PRED = 0x7b2c9e1d4f3a6058 % UInt
const _SALT_COMPOSE = 0x2e8d5a1c9b7f3046 % UInt

# ---------------------------------------------------------------------------------------------
# Identity

"""
    Identity(x)

The identity functor: a box around one value. Tag `IdentityTag()`; Functor, Applicative
(`pure(IdentityTag(), x) == Identity(x)`), Monad, Foldable (iterates its one value) and
Traversable. It is the applicative of the Traversable `identity` law. `==`, `isequal` and `hash`
compare the value.

```jldoctest
julia> ChuiCore.fmap(x -> x + 1, ChuiCore.Identity(1)) == ChuiCore.Identity(2)
true

julia> chain(x -> ChuiCore.Identity(2x), ChuiCore.Identity(3)).value
6

julia> collect(ChuiCore.Identity(5))
1-element Vector{Int64}:
 5
```

Cost: nothing beyond the stored value: an immutable one-field struct, so no heap allocation when
the value is isbits.
"""
struct Identity{T}
    value::T
end

constructorclass(::Type{<:Identity}) = IdentityTag()
Base.:(==)(a::Identity, b::Identity) = a.value == b.value
Base.isequal(a::Identity, b::Identity) = isequal(a.value, b.value)
Base.hash(a::Identity, h::UInt) = hash(a.value, h ⊻ _SALT_IDENTITY)
Base.iterate(a::Identity) = (a.value, nothing)
Base.iterate(::Identity, ::Nothing) = nothing
Base.length(::Identity) = 1
Base.eltype(::Type{Identity{T}}) where {T} = T
# `foldr` iterates backward; with one element that is forward iteration.
Base.mapfoldr(f, op, a::Identity; kw...) = mapfoldl(f, (x, y) -> op(y, x), a; kw...)
Base.map(f, a::Identity) = Identity(f(a.value))

for C in (:Functor, :Applicative, :Monad, :Foldable, :Traversable)
    @eval $(Symbol(C, :Style))(::IdentityTag) = $(Symbol(:Is, C))()
end
fmap(::IsFunctor, f, a::Identity) = Identity(f(a.value))
pure(::IdentityTag, x) = Identity(x)
ap(::IsApplicative, ff::Identity, fx::Identity) = Identity(ff.value(fx.value))
chain(::IsMonad, f, m::Identity) = f(m.value)
traverse(::IsTraversable, tag, f, a::Identity) = fmap(Identity, f(a.value))

# ---------------------------------------------------------------------------------------------
# ZipVector

"""
    ZipVector(xs::AbstractVector)

A vector with the **zip** Applicative (Haskell `ZipList`), the second lawful Applicative on
vectors, as a wrapper type with its own tag `ZipVectorTag()` (ADR-0001 §3). Functor: `map` over
the elements. `ap` pairs functions and values position by position, truncating to the shorter;
`pure(ZipVectorTag(), x)` is an infinite repetition of `x` (stored as one element and a flag), so
the Applicative laws hold exactly. `==`, `isequal` and `hash` compare by value; a repetition
equals only a repetition.

```jldoctest
julia> ChuiCore.ap(ChuiCore.ZipVector([x -> x + 1, x -> 10x]), ChuiCore.ZipVector([1, 2, 3]))
ChuiCore.ZipVector([2, 20])

julia> ChuiCore.pure(ChuiCore.ZipVectorTag(), 1)
ChuiCore.pure(ChuiCore.ZipVectorTag(), 1)

julia> ChuiCore.ap(ChuiCore.pure(ChuiCore.ZipVectorTag(), x -> 2x), ChuiCore.ZipVector([1, 2]))
ChuiCore.ZipVector([2, 4])
```

Cost: one new `Vector` per construction (`collect` copies the input) and per `fmap` or `ap`.
"""
struct ZipVector{T}
    xs::Vector{T}
    repeated::Bool
    function ZipVector{T}(xs::Vector{T}, repeated::Bool) where {T}
        repeated && length(xs) != 1 && throw(ArgumentError("a repeated ZipVector holds one value"))
        return new{T}(xs, repeated)
    end
end
ZipVector(xs::AbstractVector) = (v = collect(xs); ZipVector{eltype(v)}(v, false))
_ziprepeat(x) = ZipVector{typeof(x)}([x], true)

constructorclass(::Type{<:ZipVector}) = ZipVectorTag()
Base.:(==)(a::ZipVector, b::ZipVector) = a.repeated == b.repeated && a.xs == b.xs
Base.isequal(a::ZipVector, b::ZipVector) = a.repeated == b.repeated && isequal(a.xs, b.xs)
Base.hash(a::ZipVector, h::UInt) = hash(a.xs, hash(a.repeated, h ⊻ _SALT_ZIP))
function Base.show(io::IO, a::ZipVector)
    if a.repeated
        print(io, "ChuiCore.pure(ChuiCore.ZipVectorTag(), ")
        show(io, only(a.xs))
        print(io, ")")
    else
        print(io, "ChuiCore.ZipVector(")
        show(io, a.xs)
        print(io, ")")
    end
    return nothing
end

FunctorStyle(::ZipVectorTag) = IsFunctor()
ApplicativeStyle(::ZipVectorTag) = IsApplicative()
fmap(::IsFunctor, f, a::ZipVector) = a.repeated ? _ziprepeat(f(only(a.xs))) : ZipVector(map(f, a.xs))
pure(::ZipVectorTag, x) = _ziprepeat(x)
function ap(::IsApplicative, ff::ZipVector, fx::ZipVector)
    ff.repeated && fx.repeated && return _ziprepeat(only(ff.xs)(only(fx.xs)))
    ff.repeated && return ZipVector(map(only(ff.xs), fx.xs))
    fx.repeated && return ZipVector(map(f -> f(only(fx.xs)), ff.xs))
    return ZipVector([f(x) for (f, x) in zip(ff.xs, fx.xs)])
end

# ---------------------------------------------------------------------------------------------
# Predicate

"""
    Predicate(f)

A callable `a -> Bool` wrapping `f`; `Predicate(f)(x)` asserts that `f(x)` is a `Bool`. Tag
`PredicateTag()`; Contravariant: `contramap(g, p) == Predicate(g ⨟ p.f)`, so
`contramap(g, p)(x) == p(g(x))`. `==`, `isequal` and `hash` compare the wrapped function.

```jldoctest
julia> p = ChuiCore.Predicate(iseven);

julia> p(4)
true

julia> contramap(length, p)("abc")
false

julia> ChuiCore.Predicate(x -> x)(1)
ERROR: TypeError: non-boolean (Int64) used in boolean context
```

Cost: a call costs the call of `f` plus a type assertion; the wrapper is an immutable one-field
struct (no heap allocation when `f` is isbits).
"""
struct Predicate{F}
    f::F
end
(p::Predicate)(x) = p.f(x)::Bool

constructorclass(::Type{<:Predicate}) = PredicateTag()
Base.:(==)(a::Predicate, b::Predicate) = a.f == b.f
Base.isequal(a::Predicate, b::Predicate) = isequal(a.f, b.f)
Base.hash(a::Predicate, h::UInt) = hash(a.f, h ⊻ _SALT_PRED)

ContravariantStyle(::PredicateTag) = IsContravariant()
contramap(::IsContravariant, f, p::Predicate) = Predicate(f ⨟ p.f)

# ---------------------------------------------------------------------------------------------
# Compose (internal): the composition of two applicatives, used by the Traversable composition
# law. `F` and `G` are the tag *types* of the outer and inner applicative.

struct ComposeTag{F, G} end

struct Compose{F, G, X}
    value::X
end
Compose{F, G}(value::X) where {F, G, X} = Compose{F, G, X}(value)

constructorclass(::Type{<:Compose{F, G}}) where {F, G} = ComposeTag{F, G}()
Base.:(==)(a::Compose{F, G}, b::Compose{F, G}) where {F, G} = a.value == b.value
Base.isequal(a::Compose{F, G}, b::Compose{F, G}) where {F, G} = isequal(a.value, b.value)
Base.hash(a::Compose, h::UInt) = hash(a.value, h ⊻ _SALT_COMPOSE)

FunctorStyle(::ComposeTag) = IsFunctor()
ApplicativeStyle(::ComposeTag) = IsApplicative()
fmap(::IsFunctor, f, c::Compose{F, G}) where {F, G} = Compose{F, G}(fmap(y -> fmap(f, y), c.value))
pure(::ComposeTag{F, G}, x) where {F, G} = Compose{F, G}(pure(F(), pure(G(), x)))
function ap(::IsApplicative, cf::Compose{F, G}, cx::Compose{F, G}) where {F, G}
    return Compose{F, G}(ap(fmap(gf -> (gx -> ap(gf, gx)), cf.value), cx.value))
end
