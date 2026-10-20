# `Mean` and `Moments` (CC-007): aggregators with a non-trivial `final`.

"""
    Mean()

Aggregator for `Statistics.mean` (CC-007). The accumulator is `(float sum, count)`, a monoid with
`neutral` `(0.0, 0)`; `final` divides, so empty input gives `NaN`. The sum is a float sum (`float(x)`
per element), so `typemax(Int)`-sized integers never overflow and the result is a float. Commutative.
Elements must be real scalars: vector elements throw a `MethodError` (`float` of a vector added to a
`Float64`); v1 has no built-in element-wise mean of vectors.
Cost: one pass; a non-empty `AbstractArray` chunk uses Base's pairwise `sum(float, chunk)`.
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
does a single element with `corrected = true`, as in Statistics. Cost: one pass, a few flops per
element; the accumulator is a small `Union` until the first element (ADR-0001 §7).
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
