# Constructor classes, part 3: instances on Base types (ADR-0001 §3). Only ChuiCore functions get
# methods here; Base functions on Base types are never extended (no piracy).

# ---------------------------------------------------------------------------------------------
# Maybe: `Some{T}` / `nothing`

for C in (:Functor, :Applicative, :Monad, :Alternative, :Traversable)
    @eval $(Symbol(C, :Style))(::MaybeTag) = $(Symbol(:Is, C))()
end
fmap(::IsFunctor, f, x::Some) = Some(f(x.value))
fmap(::IsFunctor, f, ::Nothing) = nothing
pure(::MaybeTag, x) = Some(x)
ap(::IsApplicative, ff::Some, fx::Some) = Some(ff.value(fx.value))
ap(::IsApplicative, ::Some, ::Nothing) = nothing
ap(::IsApplicative, ::Nothing, _) = nothing
chain(::IsMonad, f, m::Some) = f(m.value)
chain(::IsMonad, f, ::Nothing) = nothing
zeroalt(::MaybeTag) = nothing
alt(::IsAlternative, a::Some, _) = a
alt(::IsAlternative, ::Nothing, b) = b
traverse(::IsTraversable, tag, f, x::Some) = fmap(Some, f(x.value))
traverse(::IsTraversable, tag, f, ::Nothing) = pure(tag, nothing)

# ---------------------------------------------------------------------------------------------
# Array: list semantics

for C in (:Functor, :Applicative, :Monad, :Alternative, :Foldable, :Traversable)
    @eval $(Symbol(C, :Style))(::ArrayTag) = $(Symbol(:Is, C))()
end
fmap(::IsFunctor, f, x::Array) = map(f, x)
pure(::ArrayTag, x) = [x]
ap(::IsApplicative, ff::Array, fx::Array) = [f(x) for f in ff for x in fx]
chain(::IsMonad, f, m::Array) = [y for x in m for y in f(x)]
zeroalt(::ArrayTag) = Union{}[]
alt(::IsAlternative, a::Array, b::Array) = vcat(a, b)

_snoc(v, x) = vcat(v, [x])
_snoc(t::Tuple, x) = (t..., x)
_snocf(acc) = x -> _snoc(acc, x)

function traverse(::IsTraversable, tag, f, xs::Array)
    acc = pure(tag, Union{}[])
    for x in xs
        acc = ap(fmap(_snocf, acc), f(x))
    end
    ndims(xs) == 1 && return acc
    dims = size(xs)
    return fmap(v -> reshape(v, dims), acc)
end

# ---------------------------------------------------------------------------------------------
# Tuple

for C in (:Functor, :Foldable, :Traversable, :Bifunctor)
    @eval $(Symbol(C, :Style))(::TupleTag) = $(Symbol(:Is, C))()
end
fmap(::IsFunctor, f, x::Tuple) = map(f, x)
function traverse(::IsTraversable, tag, f, xs::Tuple)
    acc = pure(tag, ())
    for x in xs
        acc = ap(fmap(_snocf, acc), f(x))
    end
    return acc
end
bimap(::IsBifunctor, f, g, p::Tuple{Any, Any}) = (f(p[1]), g(p[2]))
function bimap(::IsBifunctor, f, g, p::Tuple)
    throw(ArgumentError("bimap needs a 2-tuple, got a tuple of length $(length(p))"))
end

# ---------------------------------------------------------------------------------------------
# Dict: Functor on the values

FunctorStyle(::DictTag) = IsFunctor()
fmap(::IsFunctor, f, d::Dict) = Dict(k => f(v) for (k, v) in d)

# ---------------------------------------------------------------------------------------------
# Pair: Bifunctor

BifunctorStyle(::PairTag) = IsBifunctor()
bimap(::IsBifunctor, f, g, p::Pair) = f(p.first) => g(p.second)

# ---------------------------------------------------------------------------------------------
# Function: Profunctor, Category (composition `⨟`), Arrow

for C in (:Profunctor, :Category, :Arrow)
    @eval $(Symbol(C, :Style))(::FunctionTag) = $(Symbol(:Is, C))()
end
dimap(::IsProfunctor, f, g, h::Function) = f ⨟ h ⨟ g
lmap(::IsProfunctor, f, h::Function) = f ⨟ h
rmap(::IsProfunctor, g, h::Function) = h ⨟ g
idarrow(::FunctionTag) = identity
arr(::FunctionTag, f) = f

# The callables returned by the Arrow operations on functions: `<: Function`, so they stay in
# `FunctionTag`.
struct _ArrFirst{F} <: Function
    f::F
end
(a::_ArrFirst)(p) = (a.f(p[1]), p[2])

struct _ArrSecond{F} <: Function
    f::F
end
(a::_ArrSecond)(p) = (p[1], a.f(p[2]))

struct _ArrSplit{F, G} <: Function
    f::F
    g::G
end
(a::_ArrSplit)(p) = (a.f(p[1]), a.g(p[2]))

struct _Fanout{F, G} <: Function
    f::F
    g::G
end
(a::_Fanout)(x) = (a.f(x), a.g(x))

arrfirst(::IsArrow, f::Function) = _ArrFirst(f)
arrsecond(::IsArrow, f::Function) = _ArrSecond(f)
arrsplit(::IsArrow, f::Function, g) = _ArrSplit(f, g)
fanout(::IsArrow, f::Function, g) = _Fanout(f, g)
