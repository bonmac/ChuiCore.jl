# CC-004's float tolerance `≈ᵃ`: the `default_eq` of the built-in aggregators.

"""
    ApproxAggEq(agg)

Internal: CC-004's `≈ᵃ` for `agg`, called as `eq(r₁, r₂, v)` with `v` the whole input. True when
`isequal(r₁, r₂)`, or both are floats and `isapprox(r₁, r₂; atol = τ(agg, v), rtol = ε)` with
`ε = √eps(float(eltype(v)))`; tuples are compared componentwise. Cost: one pass over `v` for `τ`.
"""
struct ApproxAggEq{A}
    agg::A
end

"""
    MapEq(f, inner_eq)

Internal: the `default_eq` of `MapM(f, inner)`: `inner_eq(r₁, r₂, map(f, v))` (CC-004:
`τ(MapM(f, inner), v) = τ(inner, map(f, v))`).
"""
struct MapEq{F, E}
    f::F
    inner::E
end
(e::MapEq)(r₁, r₂, v) = e.inner(r₁, r₂, map(e.f, v))

# The other built-ins keep the fallback `ExactEq()` (CC-004: exact for Count, CountTrue, AnyM,
# AllM, Max, Min, Extrema, First, Last; ReduceM exact by default).
default_eq(agg::Union{Sum, Prod, Mean, Moments}) = ApproxAggEq(agg)
default_eq(m::MapM) = MapEq(m.f, default_eq(m.inner))

_epsof(::Type{T}) where {T <: Number} = (F = float(T); F <: AbstractFloat ? sqrt(eps(F)) : sqrt(eps(Float64)))
_epsof(::Type) = sqrt(eps(Float64))

_meanof(f, v) = isempty(v) ? 0.0 : sum(f, v) / length(v)

# τ(agg, v), CC-004's table.
_tau(::Sum, v, ε) = ε * (isempty(v) ? 0.0 : sum(abs, v))
_tau(::Mean, v, ε) = ε * _meanof(abs, v)
_tau(::Prod, v, ε) = 0.0
_tau(::Moments{:var}, v, ε) = ε * _meanof(abs2, v)
_tau(::Moments{:std}, v, ε) = sqrt(ε * _meanof(abs2, v))

function (e::ApproxAggEq)(r₁, r₂, v)
    ε = _epsof(eltype(v))
    return _approx(r₁, r₂, _tau(e.agg, v, ε), ε)
end

_approx(a, b, atol, rtol) = isequal(a, b)
_approx(a::AbstractFloat, b::AbstractFloat, atol, rtol) =
    isequal(a, b) || isapprox(a, b; atol = atol, rtol = rtol)
_approx(a::Tuple, b::Tuple, atol, rtol) =
    length(a) == length(b) && all(i -> _approx(a[i], b[i], atol, rtol), eachindex(a))
