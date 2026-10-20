# Law kits on every built-in instance (ADR-0007): the Test driver over fixed samples, and each
# built-in once through the Supposition driver. Float samples stay in CC-004's domain (finite,
# no overflow or underflow).

@testitem "aggregator, semigroup and monoid laws of the built-ins (samples)" tags = [:laws] begin
    using Test, Statistics
    const CC = ChuiCore
    ints = ([3, -1, 4], Int[], [1, -5, 9, 2], [7], [0, 0, 6])
    floats = ([0.5, -2.25, 3.0], Float64[], [1.0e-3, 7.5], [1.0, 1.0e16, -1.0e16], [0.1, 0.1, 0.1])
    bools = ([true, false], Bool[], [true, true, false], [false], [true])
    nums = (ints..., floats...)
    rows = (
        (CC.Sum(), sum, nums), (CC.Prod(), prod, (ints..., floats[1:3]...)),
        (CC.Count(), length, nums), (CC.CountTrue(), count, bools), (CC.AnyM(), any, bools),
        (CC.AllM(), all, bools), (CC.Max(), maximum, nums), (CC.Min(), minimum, nums),
        (CC.Extrema(), extrema, nums), (CC.First(), first, nums), (CC.Last(), last, nums),
        (CC.Mean(), mean, nums), (CC.Moments(), var, nums), (CC.Moments(:std), std, nums),
        (CC.Moments(; corrected = false), v -> var(v; corrected = false), nums),
        (CC.ReduceM(min), v -> reduce(min, v), ints),
        # Associative, not commutative: string concatenation.
        (CC.ReduceM(*), v -> reduce(*, v), (["a", "b"], String[], ["c"], ["de", "f", "g"])),
        (CC.ReduceM(*; neutral = 1, commutative = true), v -> reduce(*, v), ints),
        # `Int[]` is an identity on the carrier, not on elements: the reference must start from it
        # (on Julia 1.10, `reduce(vcat, [7])` is `7`, not `[7]`).
        (CC.ReduceM(vcat; neutral = Int[]), v -> reduce(vcat, v; init = Int[]), ints),
        (CC.MapM(abs2, CC.Sum()), v -> sum(abs2, v), nums),
        (CC.MapM(abs, CC.Max()), v -> maximum(abs, v), nums),
    )
    for (agg, ref, samples) in rows
        test_aggregator_laws(agg, samples; reference = ref)
        test_semigroup_laws(agg, samples)
        CC.AlgebraClass(agg) isa CC.IsMonoid && test_monoid_laws(agg, samples)
    end
end

@testitem "aggregator, semigroup and monoid laws of the built-ins (Supposition)" tags = [:property] begin
    using Test, Statistics
    using Supposition: Data
    const CC = ChuiCore
    # CC-004's tolerance holds only without intermediate overflow or underflow: arbitrary floats
    # in [-1e6, 1e6] include subnormal-squaring values (Moments(:std) on [0.0, 2.2e-162] failed
    # "split invariance"), so draw multiples of 2^-10 instead.
    floats = Data.Vectors(map(x -> x / 1024, Data.Integers(-10^9, 10^9)); max_size = 20)
    small = Data.Vectors(map(Float64, Data.Integers(-3, 3)); max_size = 12)
    ints = Data.Vectors(Data.Integers(-1000, 1000); max_size = 20)
    bools = Data.Vectors(Data.Booleans(); max_size = 20)
    rows = (
        (CC.Sum(), sum, floats), (CC.Prod(), prod, small), (CC.Count(), length, floats),
        (CC.CountTrue(), count, bools), (CC.AnyM(), any, bools), (CC.AllM(), all, bools),
        (CC.Max(), maximum, floats), (CC.Min(), minimum, floats), (CC.Extrema(), extrema, floats),
        (CC.First(), first, floats), (CC.Last(), last, floats), (CC.Mean(), mean, floats),
        (CC.Moments(), var, floats), (CC.Moments(:std), std, floats),
        (CC.ReduceM(max), v -> reduce(max, v), ints),
        (CC.ReduceM(+; neutral = 0, commutative = true), v -> reduce(+, v), ints),
        (CC.MapM(abs2, CC.Sum()), v -> sum(abs2, v), floats),
    )
    for (agg, ref, gen) in rows
        test_aggregator_laws(agg, gen; reference = ref, max_examples = 30)
        test_semigroup_laws(agg, gen; max_examples = 30)
        CC.AlgebraClass(agg) isa CC.IsMonoid && test_monoid_laws(agg, gen; max_examples = 30)
    end
end
