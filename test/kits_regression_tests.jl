# Regressions from the phase-2 review (B1, S1, S2, N3): each was RED before its fix.

@testitem "planted: a combine that always throws fails associativity (both drivers)" tags = [:laws] setup = [LawCapture] begin
    using Supposition: Data
    const CC = ChuiCore
    struct OffByOne end                         # combine indexes a[3] of a 2-tuple: BoundsError
    CC.init(::OffByOne) = (0.0, 0)
    CC.partial(::OffByOne, acc, chunk) = (acc[1] + sum(float, chunk; init = 0.0), acc[2] + length(chunk))
    CC.combine(::OffByOne, a, b) = (a[1] + b[1], a[2] + b[3])
    CC.final(::OffByOne, acc) = acc[1] / acc[2]
    samples = [[1.0], [2.0, 3.0], [4.0]]
    for gen in (samples, Data.SampledFrom(samples))
        failing, ran = LawCapture.captured(() -> test_semigroup_laws(OffByOne(), gen; max_examples = 30))
        @test failing == Set(["associativity"])
        @test ran == Set(["associativity"])
    end
end

@testitem "planted: a final that always throws fails the aggregator laws (both drivers)" tags = [:laws] setup = [LawCapture] begin
    using Supposition: Data
    const CC = ChuiCore
    struct AlwaysThrows end
    CC.init(::AlwaysThrows) = 0
    CC.partial(::AlwaysThrows, acc, chunk) = acc + sum(chunk; init = 0)
    CC.combine(::AlwaysThrows, a, b) = a + b
    CC.final(::AlwaysThrows, acc) = throw(ArgumentError("never a result"))
    samples = [[1], [2, 3], [4, 5, 6]]           # non-empty: a throw there is never agreement
    expected = Set(["split invariance", "empty partition identity", "chunk concatenation", "init is fresh"])
    for gen in (samples, Data.SampledFrom(samples))
        failing, _ = LawCapture.captured(() -> test_aggregator_laws(AlwaysThrows(), gen; max_examples = 30))
        @test failing == expected                 # commutativity: vacuous (not declared commutative)
    end
end

@testitem "an unknown name in `laws` throws (both drivers)" tags = [:unit] begin
    using Supposition: Data
    @test_throws ArgumentError test_aggregator_laws(ChuiCore.Sum(), [[1], [2]]; laws = ["comutativity"])
    @test_throws ArgumentError test_aggregator_laws(ChuiCore.Sum(), Data.SampledFrom([[1], [2]]); laws = ["comutativity"])
    @test_throws ArgumentError test_functor_laws(ChuiCore.MaybeTag(), [Some(1)], [abs]; laws = ["idenity"])
end

@testitem "Extrema on tuple elements agrees with Base" tags = [:unit] begin
    const CC = ChuiCore
    v = [(1, 2), (3, 0), (0, 5)]
    agg = CC.Extrema()
    @test CC.final(agg, CC.partial(agg, CC.init(agg), v)) == extrema(v)
    a = CC.partial(agg, CC.init(agg), v[1:1])
    b = CC.partial(agg, CC.init(agg), v[2:3])
    @test CC.final(agg, CC.combine(agg, a, b)) == extrema(v)
end

@testitem "ReduceM type parameters must be Bool" tags = [:unit] begin
    @test_throws ArgumentError ChuiCore.ReduceM{:yes, true}(+, 0)
    @test ChuiCore.iscommutative(ChuiCore.ReduceM(+; commutative = true)) === true
end
