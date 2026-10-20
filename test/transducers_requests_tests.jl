# Request reproducers (R3, R7), ADR-0012 P2, and the type-stability/allocation budget of
# ADR-0003 §9 (stateless pipelines over vectors: 0 bytes, inferred).

@testitem "R3 reproducer (verbatim)" tags = [:unit] begin
    const CC = ChuiCore
    f(xf, xs) = CC.foldxl(+, xf, xs; init = 0.0)
    alloc(xf, xs) = (f(xf, xs); @allocated f(xf, xs))
    xs = rand(1000)
    xf = CC.Map(abs) ⨟ CC.Filter(>(0.5))
    @test (@inferred f(xf, xs)) isa Float64
    @test alloc(xf, xs) == 0
    n = Ref(0)
    CC.foldxl(+, CC.Map(x -> (n[] += 1; x)) ⨟ CC.Take(3), 1:(10^6); init = 0)
    @test n[] == 3
end

@testitem "R7 reproducer (verbatim)" tags = [:unit] begin
    const CC = ChuiCore
    parts = [[1, 2], [3], Int[]]
    @test CC.isstateless(CC.Map(abs) ⨟ CC.Filter(>(0)))
    @test !CC.isstateless(CC.Take(1))
    struct MyXf <: CC.Transducer end
    @test !CC.isstateless(MyXf())
    @test CC.foldparts(+, CC.Map(identity), parts; init = () -> 0, merge = +) == 6
    @test CC.foldparts(+, CC.Take(2), parts; init = () -> 0, merge = +) == 3
    @test CC.foldxt(+, CC.Map(abs), [-1, 2, -3]; init = () -> 0, merge = +) == 6
    @test CC.aggregate(CC.Sum(), CC.Map(identity), parts) == 6
end

@testitem "ADR-0012 P2: isstateless for Map, Filter, composition; not Take, TakeWhile, user types" tags = [:unit] begin
    const CC = ChuiCore
    struct P2Xf <: CC.Transducer end
    @test CC.isstateless(CC.Map(abs))
    @test CC.isstateless(CC.Filter(>(0)))
    @test CC.isstateless(CC.Map(abs) ⨟ CC.Filter(>(0)))
    @test !CC.isstateless(CC.Take(1))
    @test !CC.isstateless(CC.TakeWhile(>(0)))
    @test !CC.isstateless(P2Xf())
end

@testitem "stateless foldxl over a vector: inferred and 0 bytes" tags = [:unit] begin
    const CC = ChuiCore
    f(xf, xs) = CC.foldxl(+, xf, xs; init = 0.0)
    alloc(xf, xs) = (f(xf, xs); @allocated f(xf, xs))
    xs = rand(1000)
    for xf in (CC.Map(abs), CC.Filter(>(0.5)), CC.Map(abs) ⨟ CC.Filter(>(0.5)))
        @test (@inferred f(xf, xs)) isa Float64
        @test alloc(xf, xs) == 0
    end
    ts = [(x, -x) for x in xs]
    xf = CC.MapCat(identity)
    @test (@inferred f(xf, ts)) isa Float64
    @test alloc(xf, ts) == 0
    @test f(xf, ts) ≈ 0.0 atol = 1.0e-9
    # Early-terminating and scanning pipelines stay inferred and allocation-free too.
    for xf in (CC.Map(abs) ⨟ CC.Take(10), CC.TakeWhile(<(2.0)), CC.Scan(+, 0.0))
        @test (@inferred f(xf, xs)) isa Float64
        @test alloc(xf, xs) == 0
    end
end
