# Built-in aggregators (CC-007): the monoids `Sum`, `Prod`, `Count`, `CountTrue`, `AnyM`, `AllM`
# and the semigroups `Max`, `Min`, `Extrema`, `First`, `Last`. `Mean`, `Moments`: statistics.jl;
# `ReduceM`, `MapM`: combinators.jl.

"""
    Sum()

Aggregator for `sum` (CC-007): Monoid, commutative, empty input `0`. `neutral(Sum(), T) = zero(T)`.
Elements must be scalars that add to the integer `0` (numbers): the accumulator starts at `0`, so
vector elements throw a `MethodError`; for those use `ReduceM(+; neutral = zeros(n),
commutative = true)`. Cost: one pass; a non-empty `AbstractArray` chunk uses Base's pairwise `sum`.
"""
struct Sum end

"""
    Prod()

Aggregator for `prod` (CC-007): Monoid, commutative, empty input `1`. `neutral(Prod(), T) = one(T)`.
Elements must be scalars (numbers): the accumulator starts at `1`, so vector or matrix elements
throw a `MethodError`; use `ReduceM(*; neutral = …)` for those. Cost: one pass; a non-empty `AbstractArray` chunk uses Base's `prod`.
"""
struct Prod end

"""
    Count()

Aggregator for `length` (CC-007): counts elements. Monoid, commutative, empty input `0`.
Cost: O(1) per `AbstractArray` chunk, one pass for other iterables.
"""
struct Count end

"""
    CountTrue()

Aggregator for `count` (CC-007): counts `true` elements; other elements throw, as in Base.
Monoid, commutative, empty input `0`. Cost: one pass.
"""
struct CountTrue end

"""
    AnyM()

Aggregator for `any` (CC-007): Monoid under `|` (three-valued with `missing`, like Base), commutative,
empty input `false`. Cost: one pass, skipped once the accumulator is `true`.
"""
struct AnyM end

"""
    AllM()

Aggregator for `all` (CC-007): Monoid under `&` (three-valued with `missing`), commutative, empty
input `true`. Cost: one pass, skipped once the accumulator is `false`.
"""
struct AllM end

"""
    Max()

Aggregator for `maximum` (CC-007), using `max`: Semigroup (no `neutral`), commutative. Empty input
throws `ArgumentError` on every Julia (CC-006). Cost: one pass; the accumulator is a
`Union{NoValue, T}` until the first element (ADR-0001 §7).
"""
struct Max end

"""
    Min()

Aggregator for `minimum` (CC-007), using `min`: Semigroup, commutative. Empty input throws
`ArgumentError` (CC-006). Cost as [`ChuiCore.Max`](@ref).
"""
struct Min end

"""
    Extrema()

Aggregator for `extrema` (CC-007): the accumulator is `(min, max)`. Semigroup, commutative. Empty
input throws `ArgumentError` (CC-006). Cost: one pass, two comparisons per element.
"""
struct Extrema end

"""
    First()

Aggregator for `first` (CC-007): Semigroup, **not** commutative (combine in partition order,
CC-005). Empty input throws `BoundsError` (CC-006). Cost: reads one element of the first non-empty
chunk; later chunks are not iterated.
"""
struct First end

"""
    Last()

Aggregator for `last` (CC-007): Semigroup, not commutative. Empty input throws `BoundsError`
(CC-006). Cost: O(1) per non-empty `AbstractArray` chunk, one pass for other iterables.
"""
struct Last end

const _Monoids = Union{Sum, Prod, Count, CountTrue, AnyM, AllM}
const _Semigroups = Union{Max, Min, Extrema, First, Last}

AlgebraClass(::Type{<:_Monoids}) = IsMonoid()
AlgebraClass(::Type{<:_Semigroups}) = IsSemigroup()
iscommutative(::Union{_Monoids, Max, Min, Extrema}) = true

# Sum, Prod
init(::Sum) = 0
init(::Prod) = 1
neutral(::Sum) = 0
neutral(::Prod) = 1
neutral(::Sum, ::Type{T}) where {T} = zero(T)
neutral(::Prod, ::Type{T}) where {T} = one(T)
partial(::Sum, acc, chunk) = foldl(+, chunk; init = acc)
partial(::Sum, acc, chunk::AbstractArray) = isempty(chunk) ? acc : acc + sum(chunk)
partial(::Prod, acc, chunk) = foldl(*, chunk; init = acc)
partial(::Prod, acc, chunk::AbstractArray) = isempty(chunk) ? acc : acc * prod(chunk)
combine(::Sum, a, b) = a + b
combine(::Prod, a, b) = a * b

# Count, CountTrue
init(::Union{Count, CountTrue}) = 0
neutral(::Union{Count, CountTrue}) = 0
function partial(::Count, acc, chunk)
    for _ in chunk
        acc += 1
    end
    return acc
end
partial(::Count, acc, chunk::AbstractArray) = acc + length(chunk)
partial(::CountTrue, acc, chunk) = acc + count(identity, chunk)
combine(::Union{Count, CountTrue}, a, b) = a + b

# AnyM, AllM (`|` and `&` give Base's three-valued logic with `missing`)
init(::AnyM) = false
init(::AllM) = true
neutral(::AnyM) = false
neutral(::AllM) = true
partial(::AnyM, acc, chunk) = acc === true ? acc : acc | any(chunk)
partial(::AllM, acc, chunk) = acc === false ? acc : acc & all(chunk)
combine(::AnyM, a, b) = a | b
combine(::AllM, a, b) = a & b

# Max, Min, Extrema
init(::_Semigroups) = NoValue()
partial(::Max, acc, chunk) = _fold(max, acc, chunk)
partial(::Min, acc, chunk) = _fold(min, acc, chunk)
combine(::Max, a, b) = _nv(max, a, b)
combine(::Min, a, b) = _nv(min, a, b)
# Two step functions: merging two (lo, hi) accumulators, and folding one element into one. One
# method each, so a Tuple ELEMENT is never mistaken for an accumulator (extrema([(1, 2), (3, 0)])).
_minmax(a::Tuple, b::Tuple) = (min(a[1], b[1]), max(a[2], b[2]))
_minmax_el(a, x) = (min(a[1], x), max(a[2], x))
partial(::Extrema, acc, chunk) = foldl(_minmax_el, chunk; init = acc)
function partial(::Extrema, ::NoValue, chunk)
    y = iterate(chunk)
    y === nothing && return NoValue()
    return foldl(_minmax_el, Iterators.rest(chunk, y[2]); init = (y[1], y[1]))
end
combine(::Extrema, a, b) = _nv(_minmax, a, b)

# First, Last
_left(a, _) = a
_right(_, b) = b
function partial(::First, ::NoValue, chunk)
    y = iterate(chunk)
    return y === nothing ? NoValue() : y[1]
end
partial(::First, acc, chunk) = acc
partial(::Last, acc, chunk) = foldl(_right, chunk; init = acc)
partial(::Last, acc, chunk::AbstractArray) = isempty(chunk) ? acc : last(chunk)
combine(::First, a, b) = _nv(_left, a, b)
combine(::Last, a, b) = _nv(_right, a, b)

final(agg::Union{Max, Min, Extrema}, ::NoValue) =
    throw(ArgumentError("$(nameof(typeof(agg)))(): empty input (an empty collection has no $(_what(agg)))"))
_what(::Max) = "maximum"
_what(::Min) = "minimum"
_what(::Extrema) = "extrema"
final(::First, ::NoValue) = throw(BoundsError((), 1))
final(::Last, ::NoValue) = throw(BoundsError((), 0))
