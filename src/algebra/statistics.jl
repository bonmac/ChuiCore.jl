# `Mean` and `Moments` (CC-007): aggregators with a non-trivial `final`.

"""
    Mean()

Aggregator for `Statistics.mean` (CC-007). The accumulator is `(float sum, count)`, a monoid with
`neutral` `(0.0, 0)`; `final` divides, so empty input gives `NaN`. The sum is a float sum (`float(x)`
per element), so `typemax(Int)`-sized integers never overflow and the result is a float. Commutative.
Elements must be real scalars: vector elements throw a `MethodError` (`float` of a vector added to a
`Float64`); v1 has no built-in element-wise mean of vectors.

```jldoctest
julia> using ChuiCore: Mean, init, partial, combine, final

julia> a = partial(Mean(), init(Mean()), [1, 2, 3])   # the accumulator: (float sum, count)
(6.0, 3)

julia> final(Mean(), combine(Mean(), a, partial(Mean(), init(Mean()), [10])))
4.0

julia> final(Mean(), init(Mean()))   # empty input, as Statistics.mean(Float64[])
NaN
```

Cost: one pass over each chunk, one `float` and one `+` per element; a non-empty `AbstractArray`
chunk uses Base's pairwise `sum(float, chunk)`; `combine` is two `+`, `final` one `/`; no
allocation (test item "perf allocs: built-in aggregators partial/combine/final are 0 B").
"""
struct Mean end

AlgebraClass(::Type{Mean}) = IsMonoid()
iscommutative(::Mean) = true
init(::Mean) = (0.0, 0)
neutral(::Mean) = (0.0, 0)
function partial(::Mean, acc, chunk)
    s, n = acc
    for x in chunk
        s += float(x)
        n += 1
    end
    return (s, n)
end
partial(::Mean, acc, chunk::AbstractArray) =
    isempty(chunk) ? acc : (acc[1] + sum(float, chunk), acc[2] + length(chunk))
combine(::Mean, a, b) = (a[1] + b[1], a[2] + b[2])
final(::Mean, acc) = acc[1] / acc[2]

"""
    Moments(stat::Symbol = :var; corrected::Bool = true)

Aggregator for `Statistics.var` (`stat = :var`) or `Statistics.std` (`stat = :std`), with
Statistics' `corrected` (divide by `n - 1`, or by `n` when `false`). `stat` is a type parameter
(`Moments{:var}`, `Moments{:std}`); any other value throws an `ArgumentError`.

The accumulator is `(n, mean, M2)` (Welford within a chunk, Chan's parallel merge in `combine`) or
the "no value yet" state, which is `init`'s: `Moments` is a Semigroup with no `neutral` (CC-006),
**approximately** associative (CC-004's tolerance), and commutative. Empty input gives `NaN`, and so
does a single element with `corrected = true`, as in Statistics.

```jldoctest
julia> using ChuiCore: Moments, init, partial, combine, final

julia> m = Moments();   # Moments(:var; corrected = true)

julia> a = partial(m, init(m), [1.0, 2.0]); b = partial(m, init(m), [3.0, 4.0]);

julia> final(m, combine(m, a, b))   # Statistics.var([1.0, 2.0, 3.0, 4.0])
1.6666666666666667

julia> s = Moments(:std; corrected = false); final(s, partial(s, init(s), [1.0, 3.0]))
1.0

julia> final(m, init(m))
NaN
```

Cost: one pass over each chunk (Welford: one division and a few multiply-adds per element);
`combine` is one Chan merge (a handful of flops); `final` one division (and a `sqrt` for
`:std`); no allocation (same test item as [`ChuiCore.Mean`](@ref)). The accumulator is a small
`Union` until the first element (ADR-0001 §7).
"""
struct Moments{S}
    corrected::Bool
    function Moments{S}(corrected::Bool) where {S}
        S isa Symbol && S in (:var, :std) ||
            throw(ArgumentError("Moments: stat must be :var or :std, got $(repr(S))"))
        return new{S}(corrected)
    end
end
Moments(stat::Symbol = :var; corrected::Bool = true) = Moments{stat}(corrected)

AlgebraClass(::Type{<:Moments}) = IsSemigroup()
iscommutative(::Moments) = true
init(::Moments) = NoValue()

# Welford's update: Chan's merge with a one-element right side.
_welford(::NoValue, x) = (1, float(x), zero(float(x)))
function _welford((n, m, M2), x)
    n += 1
    δ = x - m
    m += δ / n
    return (n, m, M2 + δ * (x - m))
end
partial(::Moments, acc, chunk) = foldl(_welford, chunk; init = acc)

function _chan((na, ma, Ma), (nb, mb, Mb))
    n = na + nb
    δ = mb - ma
    return (n, ma + δ * nb / n, Ma + Mb + δ^2 * na * nb / n)
end
combine(::Moments, a, b) = _nv(_chan, a, b)

_variance(m::Moments, ::NoValue) = NaN
_variance(m::Moments, (n, _, M2)) = M2 / (m.corrected ? n - 1 : n)
final(m::Moments{:var}, acc) = _variance(m, acc)
final(m::Moments{:std}, acc) = sqrt(_variance(m, acc))
