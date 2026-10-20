# Built-in aggregators (CC-007): the monoids `Sum`, `Prod`, `Count`, `CountTrue`, `AnyM`, `AllM`
# and the semigroups `Max`, `Min`, `Extrema`, `First`, `Last`. `Mean`, `Moments`: statistics.jl;
# `ReduceM`, `MapM`: combinators.jl.

"""
    Sum()

Aggregator for `sum` (CC-007): Monoid, commutative, empty input `0`. `neutral(Sum(), T) = zero(T)`.
Elements must be scalars that add to the integer `0` (numbers): the accumulator starts at `0`, so
vector elements throw a `MethodError`; for those use `ReduceM(+; neutral = zeros(n),
commutative = true)`.

```jldoctest
julia> using ChuiCore: Sum, init, partial, combine, final

julia> a = partial(Sum(), init(Sum()), [1, 2, 3]);   # partition 1

julia> b = partial(Sum(), init(Sum()), (x for x in 4:5));   # partition 2, any iterable

julia> final(Sum(), combine(Sum(), a, b))
15

julia> final(Sum(), init(Sum()))   # empty input (CC-006)
0
```

Cost: one pass over each chunk; a non-empty `AbstractArray` chunk uses Base's pairwise `sum`;
`combine` is one `+`. No allocation for number elements (test item "perf allocs: built-in
aggregators partial/combine/final are 0 B").
"""
struct Sum end

"""
    Prod()

Aggregator for `prod` (CC-007): Monoid, commutative, empty input `1`. `neutral(Prod(), T) = one(T)`.
Elements must be scalars (numbers): the accumulator starts at `1`, so vector or matrix elements
throw a `MethodError`; use `ReduceM(*; neutral = …)` for those.

```jldoctest
julia> using ChuiCore: Prod, init, partial, combine, final

julia> final(Prod(), combine(Prod(), partial(Prod(), init(Prod()), [2, 3]), partial(Prod(), init(Prod()), [4])))
24

julia> final(Prod(), init(Prod()))
1
```

Cost: one pass over each chunk; a non-empty `AbstractArray` chunk uses Base's `prod`; `combine`
is one `*`. No allocation for number elements (same test item as [`ChuiCore.Sum`](@ref)).
"""
struct Prod end

"""
    Count()

Aggregator for `length` (CC-007): counts elements. Monoid, commutative, empty input `0`.

```jldoctest
julia> using ChuiCore: Count, init, partial, combine, final

julia> final(Count(), combine(Count(), partial(Count(), init(Count()), [:a, :b]), partial(Count(), init(Count()), "xyz")))
5
```

Cost: O(1) per `AbstractArray` chunk (`length`), one pass for other iterables; `combine` is one
`+`; no allocation.
"""
struct Count end

"""
    CountTrue()

Aggregator for `count` (CC-007): counts `true` elements; other elements throw, as in Base.
Monoid, commutative, empty input `0`.

```jldoctest
julia> using ChuiCore: CountTrue, init, partial, final

julia> final(CountTrue(), partial(CountTrue(), init(CountTrue()), [true, false, true]))
2
```

Cost: one pass over each chunk (Base's `count`); `combine` is one `+`; no allocation.
"""
struct CountTrue end

"""
    AnyM()

Aggregator for `any` (CC-007): Monoid under `|` (three-valued with `missing`, like Base), commutative,
empty input `false`.

```jldoctest
julia> using ChuiCore: AnyM, init, partial, combine, final

julia> final(AnyM(), combine(AnyM(), partial(AnyM(), init(AnyM()), [false]), partial(AnyM(), init(AnyM()), [false, true])))
true

julia> final(AnyM(), partial(AnyM(), init(AnyM()), [false, missing]))
missing
```

Cost: at most one pass over each chunk (Base's short-circuiting `any`); a chunk is not iterated
at all once the accumulator is `true`; `combine` is one `|`; no allocation.
"""
struct AnyM end

"""
    AllM()

Aggregator for `all` (CC-007): Monoid under `&` (three-valued with `missing`), commutative, empty
input `true`.

```jldoctest
julia> using ChuiCore: AllM, init, partial, final

julia> final(AllM(), partial(AllM(), init(AllM()), [true, false]))
false

julia> final(AllM(), init(AllM()))
true
```

Cost: at most one pass over each chunk (Base's short-circuiting `all`); a chunk is not iterated
at all once the accumulator is `false`; `combine` is one `&`; no allocation.
"""
struct AllM end

"""
    Max()

Aggregator for `maximum` (CC-007), using `max`: Semigroup (no `neutral`), commutative. Empty input
throws `ArgumentError` on every Julia (CC-006); an empty partition is the internal "no value yet"
state, an identity of `combine`.

```jldoctest
julia> using ChuiCore: Max, init, partial, combine, final

julia> e = partial(Max(), init(Max()), Int[]);   # an empty partition

julia> final(Max(), combine(Max(), e, partial(Max(), init(Max()), [3, 9, 4])))
9

julia> final(Max(), init(Max()))
ERROR: ArgumentError: Max(): empty input (an empty collection has no maximum)
Stacktrace:
[...]
```

Cost: one pass over each chunk, one `max` per element; `combine` is one `max`; no allocation. The
accumulator is a `Union{NoValue, T}` until the first element (ADR-0001 §7).
"""
struct Max end

"""
    Min()

Aggregator for `minimum` (CC-007), using `min`: Semigroup, commutative. Empty input throws
`ArgumentError` (CC-006).

```jldoctest
julia> using ChuiCore: Min, init, partial, final

julia> final(Min(), partial(Min(), init(Min()), [3.5, -1.0, 2.0]))
-1.0
```

Cost as [`ChuiCore.Max`](@ref): one pass, one `min` per element, no allocation.
"""
struct Min end

"""
    Extrema()

Aggregator for `extrema` (CC-007): the accumulator is `(min, max)`. Semigroup, commutative. Empty
input throws `ArgumentError` (CC-006).

```jldoctest
julia> using ChuiCore: Extrema, init, partial, combine, final

julia> final(Extrema(), combine(Extrema(), partial(Extrema(), init(Extrema()), [3, 1]), partial(Extrema(), init(Extrema()), [7])))
(1, 7)
```

Cost: one pass over each chunk, one `min` and one `max` per element; `combine` is one `min` and
one `max`; no allocation.
"""
struct Extrema end

"""
    First()

Aggregator for `first` (CC-007): Semigroup, **not** commutative (combine in partition order,
CC-005). Empty input throws `BoundsError` (CC-006).

```jldoctest
julia> using ChuiCore: First, init, partial, combine, final, iscommutative

julia> a = partial(First(), init(First()), [1, 2]); b = partial(First(), init(First()), [3]);

julia> final(First(), combine(First(), a, b)), final(First(), combine(First(), b, a))
(1, 3)

julia> iscommutative(First())
false

julia> final(First(), init(First()))
ERROR: BoundsError: attempt to access Tuple{} at index [1]
Stacktrace:
[...]
```

Cost: reads one element of the first non-empty chunk; once the accumulator holds a value, later
chunks are not iterated; `combine` is O(1); no allocation.
"""
struct First end

"""
    Last()

Aggregator for `last` (CC-007): Semigroup, not commutative. Empty input throws `BoundsError`
(CC-006).

```jldoctest
julia> using ChuiCore: Last, init, partial, combine, final

julia> final(Last(), combine(Last(), partial(Last(), init(Last()), [1, 2]), partial(Last(), init(Last()), Int[])))
2
```

Cost: O(1) per non-empty `AbstractArray` chunk (`last`), one pass for other iterables; `combine`
is O(1); no allocation.
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
