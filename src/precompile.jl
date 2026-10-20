# The precompile workload (ADR-0010): one function, called from `@compile_workload`, so the
# package image caches the hot paths a downstream package hits first (ADR-0009 §3). It covers the
# TTFX workload of benchmark/ttfx.jl; a `:slow` test checks that with `--trace-compile`. Only
# ChuiCore's types plus Float64/Int, their vectors and views: user types cannot be precompiled here.
# Users can turn it off with PrecompileTools' `precompile_workload = false` preference.

const _WORKLOAD_AGGREGATORS = (
    Sum(), Prod(), Count(), Mean(), Max(), Min(), Extrema(), First(), Last(),
    Moments(:var), Moments(:std),
)

# Inputs pass through `_opaque` (inferred `Any`), so each call below is dispatched at run time,
# as a user's top-level call is, and its method instance is compiled on its own. Without it the
# entry points (`foldxl`'s keyword call, `aggregate`, …) are inlined into this function and a
# top-level call still compiles them (caught by test/precompile_tests.jl).
_opaque(x) = Ref{Any}(x)[]

function _precompile_workload()
    v = _opaque(collect(1.0:8.0))
    vi = _opaque(collect(1:8))
    parts = _opaque([view(v, 1:4), view(v, 5:8)])
    for c in (v, view(v, 1:4))
        for g in _WORKLOAD_AGGREGATORS
            agg = _opaque(g)
            a = partial(agg, init(agg), c)
            final(agg, combine(agg, a, a))
        end
    end
    for g in (Sum(), Count(), Max(), Min())
        agg = _opaque(g)
        a = partial(agg, init(agg), vi)
        final(agg, combine(agg, a, a))
    end
    # On 1.13 the run-time call above lands in a widened `final(::Max, ::Any)` instance, and a
    # top-level `final(Max(), 3)` then still compiles (test/precompile_tests.jl): name it.
    for T in (Max, Min)
        precompile(final, (T, Int))
    end
    foldxl(+, Map(abs) ⨟ Filter(>(1.0)), v; init = 0.0)
    aggregate(Sum(), Map(abs), parts)
    aggregate(Mean(), Map(abs), parts)
    (sin ⨟ cos)(1.0)
    return nothing
end

@setup_workload begin
    @compile_workload _precompile_workload()
end
