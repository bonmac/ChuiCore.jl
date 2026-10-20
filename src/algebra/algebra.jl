# Monoid family and aggregators (ADR-0001 §1–2, CC-004…CC-007). Owned by sub-lane p2-algebra;
# this entry file includes the area's other files.

include("protocol.jl")     # init, partial, combine, final, iscommutative, NoValue, neutral, AlgebraClass, combineall
include("aggregators.jl")  # Sum, Prod, Count, CountTrue, AnyM, AllM, Max, Min, Extrema, First, Last
include("statistics.jl")   # Mean, Moments
include("combinators.jl")  # ReduceM, MapM
include("tolerance.jl")    # default_eq: CC-004's ≈ᵃ
include("lawtables.jl")    # _semigroup_laws, _monoid_laws, _aggregator_laws
