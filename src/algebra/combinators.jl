# `ReduceM` and `MapM` (CC-007): aggregators built from a user operation or another aggregator.

"""
    ReduceM(op; neutral = <none>, commutative::Bool = false)

Aggregator for `reduce(op, v)` on non-empty `v` (CC-007). `op` must be associative (Julia's `reduce`
contract). Commutativity (`C`) and whether a neutral was declared (`N`) are type parameters of
`ReduceM{C, N}`, so `AlgebraClass` and `iscommutative` stay dispatch-only (ADR-0001 §2, §4).

- Without `neutral`: a Semigroup; `init` is the "no value yet" state, and empty input throws
  `ArgumentError` (CC-006). Within a chunk, the first element starts the fold, so an `op` that
  mutates its first argument would mutate the input: declare a neutral for such operations.
- With `neutral = x`: a Monoid; `init` and `neutral` return a fresh copy of `x` (`deepcopy` unless
  `isbits`), and empty input returns it. It is not compared with Base (CC-006 exemption).

The default `default_eq` is exact (`isequal`). Cost: one `op` call per element; a `deepcopy` per
`init` for a mutable neutral.
"""
struct ReduceM{C, N, F, E}
    op::F
    neutral::E
    function ReduceM{C, N}(op::F, neutral::E) where {C, N, F, E}
        C isa Bool && N isa Bool || throw(ArgumentError("ReduceM{C, N}: C and N must be Bool, got $(repr(C)), $(repr(N))"))
        return new{C, N, F, E}(op, neutral)
    end
end
function ReduceM(op; neutral = NoValue(), commutative::Bool = false)
    return ReduceM{commutative, !(neutral isa NoValue)}(op, neutral)
end

AlgebraClass(::Type{<:ReduceM{C, true}}) where {C} = IsMonoid()
AlgebraClass(::Type{<:ReduceM{C, false}}) where {C} = IsSemigroup()
iscommutative(::ReduceM{C}) where {C} = C
init(::ReduceM{C, false}) where {C} = NoValue()
init(m::ReduceM{C, true}) where {C} = _fresh(m.neutral)
neutral(m::ReduceM{C, true}) where {C} = _fresh(m.neutral)
partial(m::ReduceM, acc, chunk) = _fold(m.op, acc, chunk)
combine(m::ReduceM, a, b) = _nv(m.op, a, b)
final(::ReduceM, ::NoValue) = throw(ArgumentError("ReduceM: empty input and no declared neutral element"))

"""
    MapM(f, inner)

Aggregator for the `inner` aggregation of `map(f, v)` (CC-007): `partial` applies `f` lazily
(`Iterators.map`, no intermediate array); `init`, `combine`, `final`, `AlgebraClass`,
`iscommutative` and `neutral` are `inner`'s. Empty input behaves as `inner` on empty input. Its
`default_eq` is `inner`'s tolerance on `map(f, v)`. Cost: `inner`'s, plus one `f` call per element;
`inner`'s `AbstractArray` fast paths do not apply.
"""
struct MapM{F, I}
    f::F
    inner::I
end

AlgebraClass(::Type{MapM{F, I}}) where {F, I} = AlgebraClass(I)
iscommutative(m::MapM) = iscommutative(m.inner)
init(m::MapM) = init(m.inner)
neutral(m::MapM) = neutral(m.inner)
partial(m::MapM, acc, chunk) = partial(m.inner, acc, Iterators.map(m.f, chunk))
combine(m::MapM, a, b) = combine(m.inner, a, b)
final(m::MapM, acc) = final(m.inner, acc)
