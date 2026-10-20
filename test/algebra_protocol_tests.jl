# The aggregation protocol (CC-004, CC-005), `neutral`, `AlgebraClass` and `combineall`
# (ADR-0001 §1–2, §4, §7).

@testitem "combine has only 3-argument methods" tags = [:unit] begin
    ms = collect(methods(ChuiCore.combine, ChuiCore))
    @test !isempty(ms)
    # `nargs` counts the function itself.
    @test all(m -> m.nargs == 4 && !m.isva, ms)
end

@testitem "protocol fallbacks: final and iscommutative" tags = [:unit] begin
    struct NoTraitsAgg end
    @test ChuiCore.final(NoTraitsAgg(), 42) === 42
    @test ChuiCore.iscommutative(NoTraitsAgg()) === false
    @test ChuiCore.AlgebraClass(NoTraitsAgg) === ChuiCore.NotAlgebra()
    @test ChuiCore.AlgebraClass(NoTraitsAgg()) === ChuiCore.NotAlgebra()
end

@testitem "neutral, refinement and default_monoid sugar" tags = [:unit] begin
    const CC = ChuiCore
    @test CC.neutral(CC.Sum()) === 0
    @test CC.neutral(CC.Prod()) === 1
    @test CC.neutral(CC.Count()) === 0
    @test CC.neutral(CC.CountTrue()) === 0
    @test CC.neutral(CC.AnyM()) === false
    @test CC.neutral(CC.AllM()) === true
    @test CC.neutral(CC.Mean()) === (0.0, 0)
    @test CC.neutral(CC.Sum(), Float32) === 0.0f0
    @test CC.neutral(CC.Prod(), Float64) === 1.0
    @test CC.neutral(CC.Count(), Float64) === 0          # default refinement: neutral(m)
    @test CC.neutral(CC.ReduceM(+; neutral = 0)) === 0
    # No default monoid, not even for numbers.
    @test_throws ArgumentError CC.default_monoid(Int)
    @test_throws ArgumentError CC.neutral(Int)
    # Semigroups have no neutral method.
    for m in (CC.Max(), CC.Min(), CC.Extrema(), CC.First(), CC.Last(), CC.Moments(), CC.ReduceM(+))
        @test !hasmethod(CC.neutral, Tuple{typeof(m)})
    end
    # Closed sugar through a downstream `default_monoid` method.
    struct Money
        cents::Int
    end
    Base.zero(::Type{Money}) = Money(0)
    ChuiCore.default_monoid(::Type{Money}) = ChuiCore.Sum()
    @test CC.neutral(Money) === Money(0)
end

@testitem "neutral and init are fresh for a mutable ReduceM neutral" tags = [:unit] begin
    const CC = ChuiCore
    m = CC.ReduceM(append!; neutral = Int[])
    n1 = CC.neutral(m)
    push!(n1, 99)
    @test CC.neutral(m) == Int[]
    @test CC.neutral(m) !== CC.neutral(m)
    @test CC.init(m) !== CC.init(m)
    @test CC.final(m, CC.init(m)) == Int[]
    @test CC.final(m, CC.partial(m, CC.init(m), [[1], [2, 3]])) == [1, 2, 3]
    @test CC.neutral(m) == Int[]
end

@testitem "AlgebraClass is dispatch-only" tags = [:unit] begin
    const CC = ChuiCore
    monoids = (CC.Sum(), CC.Prod(), CC.Count(), CC.CountTrue(), CC.AnyM(), CC.AllM(), CC.Mean())
    semigroups = (CC.Max(), CC.Min(), CC.Extrema(), CC.First(), CC.Last(), CC.Moments(), CC.Moments(:std))
    for m in monoids
        @test (@inferred CC.AlgebraClass(m)) === CC.IsMonoid()
        @test (@inferred CC.AlgebraClass(typeof(m))) === CC.IsMonoid()
    end
    for m in semigroups
        @test (@inferred CC.AlgebraClass(m)) === CC.IsSemigroup()
    end
    @test (@inferred CC.AlgebraClass(CC.ReduceM(+))) === CC.IsSemigroup()
    @test (@inferred CC.AlgebraClass(CC.ReduceM(+; neutral = 0))) === CC.IsMonoid()
    @test (@inferred CC.AlgebraClass(CC.MapM(abs, CC.Sum()))) === CC.IsMonoid()
    @test (@inferred CC.AlgebraClass(CC.MapM(abs, CC.Max()))) === CC.IsSemigroup()
    @test (@inferred CC.iscommutative(CC.ReduceM(+; commutative = true))) === true
    @test (@inferred CC.iscommutative(CC.ReduceM(+))) === false
    @test (@inferred CC.iscommutative(CC.MapM(abs, CC.First()))) === false
    @test (@inferred CC.iscommutative(CC.MapM(abs, CC.Sum()))) === true
    # One representative caller: the trait call is folded away (ADR-0001 §4).
    ismonoidal(m) = CC.AlgebraClass(m) isa CC.IsMonoid
    for (m, expected) in ((CC.Sum(), true), (CC.MapM(abs, CC.Max()), false), (CC.ReduceM(*; neutral = 1), true))
        ci, rt = only(code_typed(ismonoidal, (typeof(m),)))
        @test ismonoidal(m) === expected
        @test !occursin("AlgebraClass", string(ci))
        @test rt === Bool
    end
end

@testitem "combineall uses the trait" tags = [:unit] begin
    const CC = ChuiCore
    built(m, xs) = [CC.partial(m, CC.init(m), x) for x in xs]
    # IsMonoid: starts from neutral, so empty input gives the identity.
    @test CC.combineall(CC.Sum(), built(CC.Sum(), [[1, 2], [3], Int[]])) == 6
    @test CC.combineall(CC.Sum(), Int[]) === 0
    @test CC.final(CC.Mean(), CC.combineall(CC.Mean(), built(CC.Mean(), [[1, 2], [3, 4]]))) == 2.5
    # IsSemigroup: starts from "no value yet"; empty input stays "no value yet".
    @test CC.combineall(CC.Max(), built(CC.Max(), [[1, 5], Int[], [3]])) == 5
    @test CC.combineall(CC.Max(), Any[]) isa CC.NoValue
    @test_throws ArgumentError CC.final(CC.Max(), CC.combineall(CC.Max(), Any[]))
    @test CC.combineall(CC.First(), built(CC.First(), [Int[], [7, 8], [9]])) == 7
    # NotAlgebra: reduce without an initial value, so empty input throws.
    struct PlainSum end
    CC.init(::PlainSum) = 0
    CC.partial(::PlainSum, acc, chunk) = acc + sum(chunk; init = 0)
    CC.combine(::PlainSum, a, b) = a + b
    @test CC.combineall(PlainSum(), [1, 2, 3]) == 6
    @test_throws Exception CC.combineall(PlainSum(), Int[])
end

@testitem "NoValue is an identity of combine" tags = [:unit] begin
    const CC = ChuiCore
    nv = CC.NoValue()
    for m in (CC.Max(), CC.Min(), CC.First(), CC.Last(), CC.ReduceM(-))
        @test CC.combine(m, nv, 3) == 3
        @test CC.combine(m, 3, nv) == 3
        @test CC.combine(m, nv, nv) isa CC.NoValue
    end
    @test CC.combine(CC.Extrema(), nv, (1, 2)) == (1, 2)
    @test CC.combine(CC.Extrema(), (1, 2), nv) == (1, 2)
    @test CC.combine(CC.Moments(), nv, (2, 1.5, 0.5)) == (2, 1.5, 0.5)
    @test CC.combine(CC.Moments(), (2, 1.5, 0.5), nv) == (2, 1.5, 0.5)
    @test CC.init(CC.Max()) isa CC.NoValue
    @test CC.init(CC.Moments()) isa CC.NoValue
    @test CC.init(CC.ReduceM(+)) isa CC.NoValue
end

@testitem "constructors validate their arguments" tags = [:unit] begin
    const CC = ChuiCore
    @test CC.Moments() isa CC.Moments{:var}
    @test CC.Moments(:std) isa CC.Moments{:std}
    @test CC.Moments(:var; corrected = false).corrected === false
    @test_throws ArgumentError CC.Moments(:mean)
    @test CC.iscommutative(CC.ReduceM(+; commutative = true, neutral = 0))
    @test CC.AlgebraClass(CC.ReduceM(+; commutative = true, neutral = 0)) === CC.IsMonoid()
end

@testitem "partial accepts any iterable chunk" tags = [:unit] begin
    const CC = ChuiCore
    run(m, chunk) = CC.final(m, CC.partial(m, CC.init(m), chunk))
    gen = (x for x in [3, 1, 2])
    empty_gen = (x for x in Int[])
    for (m, r) in (
            (CC.Sum(), 6), (CC.Prod(), 6), (CC.Count(), 3), (CC.Max(), 3), (CC.Min(), 1),
            (CC.Extrema(), (1, 3)), (CC.First(), 3), (CC.Last(), 2), (CC.Mean(), 2.0),
            (CC.Moments(), 1.0), (CC.ReduceM(+), 6), (CC.MapM(x -> 2x, CC.Sum()), 12),
        )
        @test isequal(run(m, gen), r)
        @test isequal(run(m, (x for x in [3, 1, 2] if true)), r)
    end
    @test run(CC.Sum(), empty_gen) === 0
    @test run(CC.Count(), empty_gen) === 0
    @test isequal(run(CC.Mean(), empty_gen), NaN)
    @test_throws ArgumentError run(CC.Max(), empty_gen)
    @test_throws BoundsError run(CC.First(), empty_gen)
    @test run(CC.AnyM(), (x for x in [false, true])) === true
    @test run(CC.AllM(), (x for x in [true, false])) === false
    @test run(CC.CountTrue(), Iterators.filter(identity, [true, false, true])) === 2
end
