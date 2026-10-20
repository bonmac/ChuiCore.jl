# Contract conformance for the aggregators: CC-004, CC-005, CC-006, CC-007
# (coordinator contracts/chui-core.md). Item names start with the contract ID.

@testmodule AggHelpers begin
    using ChuiCore: ChuiCore
    const CC = ChuiCore
    "A fresh accumulator per call (CC-004 thunks)."
    acc(agg, x) = () -> CC.partial(agg, CC.init(agg), collect(x))
    "CC-004's `R`: the result of `agg` on the ordered chunks."
    function R(agg, chunks)
        a = acc(agg, chunks[1])()
        for x in chunks[2:end]
            a = CC.combine(agg, a, acc(agg, x)())
        end
        return CC.final(agg, a)
    end
    "Three splits of `v`, each with an empty chunk."
    splits(v) = (
        [v[1:0], v],
        [v[1:min(2, end)], v[1:0], v[(min(2, end) + 1):end]],
        [v[1:(end - 1)], v[end:end], v[1:0]],
    )
end

@testitem "CC-004 aggregator protocol" tags = [:unit] setup = [AggHelpers] begin
    using Statistics
    const CC = ChuiCore
    using .AggHelpers: acc, R, splits
    ints = [3, -1, 4, 1, -5, 9]
    floats = [0.5, -2.25, 3.0, 1.0e-3, 7.5]
    bools = [true, false, true, true]
    rows = (
        (CC.Sum(), sum, (ints, floats, bools)),
        (CC.Prod(), prod, (ints, floats, bools)),
        (CC.Count(), length, (ints, floats, bools)),
        (CC.CountTrue(), count, (bools,)),
        (CC.AnyM(), any, (bools,)),
        (CC.AllM(), all, (bools,)),
        (CC.Max(), maximum, (ints, floats, bools)),
        (CC.Min(), minimum, (ints, floats, bools)),
        (CC.Extrema(), extrema, (ints, floats, bools)),
        (CC.First(), first, (ints, floats, bools)),
        (CC.Last(), last, (ints, floats, bools)),
        (CC.Mean(), mean, (ints, floats, bools)),
        (CC.Moments(), var, (ints, floats)),
        (CC.Moments(:std), std, (ints, floats)),
        (CC.ReduceM(min), v -> reduce(min, v), (ints, floats)),
        (CC.MapM(abs2, CC.Sum()), v -> sum(abs2, v), (ints, floats)),
    )
    for (agg, base, vs) in rows, v in vs
        eq = CC.default_eq(agg)
        for chunks in splits(v)
            @test eq(R(agg, chunks), R(agg, [v]), v)                    # law 1
            @test eq(R(agg, chunks), base(v), v)                        # law 4 (values only)
        end
        x, y = v[1:2], v[3:end]
        E = acc(agg, eltype(v)[])
        A = acc(agg, x)
        @test eq(CC.final(agg, CC.combine(agg, E(), A())), CC.final(agg, A()), v)   # law 2
        @test eq(CC.final(agg, CC.combine(agg, A(), E())), CC.final(agg, A()), v)
        lhs = CC.final(agg, CC.partial(agg, acc(agg, x)(), y))                 # law 3
        rhs = CC.final(agg, CC.partial(agg, CC.init(agg), Iterators.flatten((x, y))))
        @test eq(lhs, rhs, v)
        # Two `init`s do not alias: mutating one through `partial` leaves the other unchanged.
        a, b = CC.init(agg), CC.init(agg)
        CC.partial(agg, a, collect(v))
        @test eq(CC.final(agg, CC.partial(agg, b, collect(v))), R(agg, [v]), v)
    end
    # `Sum` on [1.0, 1e16, -1e16]: the split gives 1.0, the whole 0.0; the tolerance accepts it.
    v1 = [1.0, 1.0e16, -1.0e16]
    s_split = R(CC.Sum(), [v1[1:1], v1[2:3]])
    s_whole = sum(v1)
    @test (s_whole, sum(v1[1:1]) + sum(v1[2:3])) == (0.0, 1.0)
    @test CC.default_eq(CC.Sum())(s_whole, s_split, v1)
    @test CC.default_eq(CC.Sum())(sum(v1), 1.0, v1)
    @test !isapprox(0.0, 1.0)
    # The contract's `var` counterexamples (E-36).
    v2 = fill(0.1, 10)
    eqv = CC.default_eq(CC.Moments())
    eqs = CC.default_eq(CC.Moments(:std))
    @test !isapprox(2.139922160430262e-34, 2.1185229388259596e-34)
    @test eqv(2.139922160430262e-34, 2.1185229388259596e-34, v2)
    @test eqv(var(v2), R(CC.Moments(), [v2[1:3], v2[4:10]]), v2)
    @test eqs(std(v2), R(CC.Moments(:std), [v2[1:3], v2[4:10]]), v2)
    @test eqs(std(v2), sqrt(2.1185229388259596e-34), v2)
    # Tuples compare componentwise; non-floats exactly.
    @test CC.default_eq(CC.Mean())((1.0, 2), (1.0 + 1.0e-12, 2), [1.0, 2.0])
    @test !CC.default_eq(CC.Mean())((1.0, 2), (1.0, 3), [1.0, 2.0])
    @test !CC.default_eq(CC.Sum())(1, 2, [1, 1])
    @test CC.default_eq(CC.Max()) isa CC.ExactEq
    @test CC.default_eq(CC.ReduceM(+)) isa CC.ExactEq
    # MapM: τ(inner, map(f, v)).
    @test CC.default_eq(CC.MapM(x -> 1.0e16x, CC.Sum()))(0.0, 1.0e16, v1)
    @test !CC.default_eq(CC.Sum())(0.0, 1.0e16, v1)
end

@testitem "CC-005 iscommutative" tags = [:unit] setup = [AggHelpers] begin
    using Test
    const CC = ChuiCore
    commutative = (
        CC.Sum(), CC.Prod(), CC.Count(), CC.CountTrue(), CC.AnyM(), CC.AllM(), CC.Max(), CC.Min(),
        CC.Extrema(), CC.Mean(), CC.Moments(), CC.Moments(:std), CC.MapM(abs, CC.Sum()),
        CC.ReduceM(+; commutative = true),
    )
    ordered = (CC.First(), CC.Last(), CC.ReduceM(+), CC.MapM(abs, CC.Last()))
    for agg in commutative
        @test CC.iscommutative(agg) === true
    end
    for agg in ordered
        @test CC.iscommutative(agg) === false
    end
    # The commutativity law for those declared true.
    chunks = ([3, 1], Int[], [4, -1, 5], [9])
    bchunks = ([true, false], Bool[], [true])
    for agg in commutative
        samples = agg isa Union{CC.CountTrue, CC.AnyM, CC.AllM} ? bchunks : chunks
        test_aggregator_laws(agg, samples; laws = ["commutativity"])
    end
    # A type with no `iscommutative` method gets the default.
    struct OrderedConcat end
    CC.init(::OrderedConcat) = String[]
    CC.partial(::OrderedConcat, acc, chunk) = append!(acc, chunk)
    CC.combine(::OrderedConcat, a, b) = append!(a, b)
    @test CC.iscommutative(OrderedConcat()) === false
    @test which(CC.iscommutative, Tuple{OrderedConcat}).sig == Tuple{typeof(CC.iscommutative), Any}
end

@testitem "CC-006 empty input" tags = [:unit] setup = [AggHelpers] begin
    using Statistics
    const CC = ChuiCore
    using .AggHelpers: acc
    e = Float64[]
    empty_final(agg) = CC.final(agg, CC.init(agg))
    values = (
        (CC.Sum(), sum), (CC.Prod(), prod), (CC.Count(), length), (CC.CountTrue(), count),
        (CC.AnyM(), any), (CC.AllM(), all), (CC.Mean(), mean), (CC.Moments(), var),
        (CC.Moments(:std), std), (CC.Moments(; corrected = false), v -> var(v; corrected = false)),
    )
    for (agg, base) in values
        @test isequal(empty_final(agg), base(e))
    end
    @test empty_final(CC.Sum()) === 0
    for (agg, T, base) in (
            (CC.Max(), ArgumentError, maximum), (CC.Min(), ArgumentError, minimum),
            (CC.Extrema(), ArgumentError, extrema), (CC.First(), BoundsError, first),
            (CC.Last(), BoundsError, last),
        )
        @test_throws T empty_final(agg)
        @test_throws Exception base(e)
    end
    @test_throws ArgumentError empty_final(CC.ReduceM(+))
    @test empty_final(CC.ReduceM(+; neutral = 0)) === 0
    @test empty_final(CC.MapM(abs, CC.Sum())) === 0
    @test_throws ArgumentError empty_final(CC.MapM(abs, CC.Max()))
    # n == 1 with `corrected`: NaN, as in Statistics.
    @test isequal(CC.final(CC.Moments(), CC.partial(CC.Moments(), CC.init(CC.Moments()), [2.0])), var([2.0]))
    @test CC.final(CC.Moments(; corrected = false), CC.partial(CC.Moments(; corrected = false), CC.init(CC.Moments()), [2.0])) == 0.0
    # Law 2 with an empty partition on the left and on the right, for Max and First.
    for agg in (CC.Max(), CC.First())
        E = acc(agg, Float64[])
        A = acc(agg, [2.0, 5.0, 1.0])
        @test isequal(CC.final(agg, CC.combine(agg, E(), A())), CC.final(agg, A()))
        @test isequal(CC.final(agg, CC.combine(agg, A(), E())), CC.final(agg, A()))
        @test CC.combine(agg, E(), E()) isa CC.NoValue
    end
end

@testitem "CC-007 built-in classification" tags = [:unit] setup = [AggHelpers] begin
    using Statistics
    const CC = ChuiCore
    using .AggHelpers: R, splits
    M, S = CC.IsMonoid(), CC.IsSemigroup()
    ints = [3, -1, 4, 1, -5, 9]
    floats = [0.5, -2.25, 3.0, 1.0e-3, 7.5]
    bools = [true, false, true, true]
    nums = (ints, floats, bools)
    # agg, Base equivalent, class, iscommutative, inputs, empty-input value or exception type
    table = (
        (CC.Sum(), sum, M, true, nums, 0),
        (CC.Prod(), prod, M, true, nums, 1),
        (CC.Count(), length, M, true, nums, 0),
        (CC.CountTrue(), count, M, true, (bools,), 0),
        (CC.AnyM(), any, M, true, (bools,), false),
        (CC.AllM(), all, M, true, (bools,), true),
        (CC.Max(), maximum, S, true, nums, ArgumentError),
        (CC.Min(), minimum, S, true, nums, ArgumentError),
        (CC.Extrema(), extrema, S, true, nums, ArgumentError),
        (CC.First(), first, S, false, nums, BoundsError),
        (CC.Last(), last, S, false, nums, BoundsError),
        (CC.Mean(), mean, M, true, nums, NaN),
        (CC.Moments(), var, S, true, (ints, floats), NaN),
        (CC.Moments(:std), std, S, true, (ints, floats), NaN),
        (CC.ReduceM(max), v -> reduce(max, v), S, false, nums, ArgumentError),
        (CC.ReduceM(+; neutral = 0, commutative = true), v -> reduce(+, v), M, true, nums, 0),
        (CC.MapM(abs2, CC.Sum()), v -> sum(abs2, v), M, true, nums, 0),
        (CC.MapM(abs, CC.Max()), v -> maximum(abs, v), S, true, nums, ArgumentError),
    )
    for (agg, base, class, comm, inputs, empty) in table
        @test CC.AlgebraClass(agg) === class
        @test CC.iscommutative(agg) === comm
        eq = CC.default_eq(agg)
        for v in inputs, chunks in splits(v)
            @test eq(R(agg, chunks), base(v), v)
        end
        if empty isa Type
            @test_throws empty CC.final(agg, CC.init(agg))
        else
            @test isequal(CC.final(agg, CC.init(agg)), empty)
        end
    end
    # CountTrue throws on non-Bool elements, like Base's `count`.
    @test_throws Exception CC.partial(CC.CountTrue(), CC.init(CC.CountTrue()), [1, 2])
    @test_throws Exception count([1, 2])
    # Mean accumulates a float sum: typemax(Int)-sized integers do not overflow.
    big = fill(typemax(Int), 4)
    @test sum(big) < 0                                       # Base's integer sum wraps
    r = R(CC.Mean(), [big[1:2], big[3:4]])
    @test r isa AbstractFloat
    @test r ≈ Float64(typemax(Int))
    @test CC.final(CC.Mean(), CC.partial(CC.Mean(), CC.init(CC.Mean()), big)) ≈ Float64(typemax(Int))
end
