# Critic C's attacks A1–A8 on the phase-1 sketch (ADR-0003 Context), as regression tests.

@testitem "A1: transducers are not callables, so CC-001 does not apply to ⨟" tags = [:unit] begin
    const CC = ChuiCore
    f(x) = x + 1
    p(x) = iseven(x)
    xf = CC.Map(f) ⨟ CC.Filter(p)
    # The sketch's `(Map(f) ⨟ Filter(p))(+)` folded to 12 and `Filter(p)(Map(f)(+))` to 15.
    @test !hasmethod(xf, Tuple{Any})
    @test_throws MethodError xf(+)
    @test_throws MethodError CC.Map(f)(+)
    # The only way to a reducing function is asrf, and it agrees with data order.
    @test CC.foldxl(+, xf, 1:6; init = 0) == 12
    @test CC.foldxl(+, CC.Filter(p) ∘ CC.Map(f), 1:6; init = 0) == 12
end

@testitem "A2: merge is required (no default merge = op)" tags = [:unit] begin
    const CC = ChuiCore
    @test_throws UndefKeywordError CC.foldxt(push!, CC.Map(identity), collect(1:8); init = () -> Any[], ntasks = 4)
    @test CC.foldxt(push!, CC.Map(identity), collect(1:8); init = () -> Any[], merge = append!, ntasks = 4) == 1:8
end

@testitem "A3: with an identity init, foldxt does not depend on ntasks" tags = [:unit] begin
    const CC = ChuiCore
    v = collect(1:10)
    # The sketch's non-identity init = () -> 100 gave 155 / 255 / 455.
    rs = [CC.foldxt(+, CC.Map(identity), v; init = () -> 0, merge = +, ntasks = n) for n in (1, 2, 4)]
    @test rs == [55, 55, 55]
end

@testitem "A4: a nothing accumulator does not collide with the skip sentinel" tags = [:unit] begin
    const CC = ChuiCore
    lastmatch(a, x) = x % 7 == 0 ? x : a
    keep(a, b) = b === nothing ? a : b
    v = [7, 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 14]
    parts = [v[1:4], v[5:8], v[9:12]]
    @test CC.foldxl(lastmatch, CC.Map(identity), v; init = nothing) == 14
    @test CC.foldparts(lastmatch, CC.Map(identity), parts; init = () -> nothing, merge = keep) == 14
    @test CC.foldxt(lastmatch, CC.Map(identity), v; init = () -> nothing, merge = keep, ntasks = 3) == 14
    # Every partition yields nothing: the result is nothing, not a sentinel.
    @test CC.foldparts((a, x) -> a, CC.Map(identity), parts; init = () -> nothing, merge = keep) === nothing
    # A reduced nothing.
    @test CC.foldparts((a, x) -> CC.reduced(nothing), CC.Map(identity), parts; init = () -> nothing, merge = keep) === nothing
end

@testitem "A5: a user stateful transducer without isstateless runs sequentially" tags = [:unit] begin
    const CC = ChuiCore
    struct DropWhile{P} <: CC.Transducer
        p::P
    end
    struct DWState{A}
        dropping::Bool
        acc::A
    end
    CC.start(rf::CC.R{<:DropWhile}, acc) = DWState(true, CC.start(rf.inner, acc))
    function CC.next(rf::CC.R{<:DropWhile}, w, x)
        w.dropping && rf.xf.p(x) && return w
        a = CC.next(rf.inner, w.acc, x)
        return a isa CC.Reduced ? CC.reduced(DWState(false, CC.unreduced(a))) : DWState(false, a)
    end
    CC.complete(rf::CC.R{<:DropWhile}, w) = CC.complete(rf.inner, w.acc)
    xf = DropWhile(<(3))
    @test !CC.isstateless(xf)
    @test CC.foldxl(+, xf, 1:8; init = 0) == 33
    for n in (1, 2, 4, 8)
        @test CC.foldxt(+, xf, collect(1:8); init = () -> 0, merge = +, ntasks = n) == 33
    end
    @test CC.foldparts(+, xf, [1:2, 3:5, 6:8]; init = () -> 0, merge = +) == 33
    @test CC.aggregate(CC.Sum(), xf, [1:2, 3:5, 6:8]) == 33
end

@testitem "A6: TakeWhile is not stateless; per-chunk gives 3, not 9" tags = [:unit] begin
    const CC = ChuiCore
    w = [1, 2, 9, 1, 2, 3]
    tw = CC.TakeWhile(<(5))
    @test !CC.isstateless(tw)
    @test CC.foldxl(+, tw, w; init = 0) == 3
    for n in (1, 2, 3, 6)
        @test CC.foldxt(+, tw, w; init = () -> 0, merge = +, ntasks = n) == 3
    end
    @test CC.foldparts(+, tw, [[1, 2, 9], [1, 2, 3]]; init = () -> 0, merge = +) == 3
    @test CC.aggregate(CC.Sum(), tw, [[1, 2, 9], [1, 2, 3]]) == 3
end

@testitem "A7: foldxt rejects non-vector input (no hidden copy)" tags = [:unit] begin
    const CC = ChuiCore
    g = (x for x in 1:(10^6))
    @test_throws ArgumentError CC.foldxt(+, CC.Map(identity), g; init = () -> 0, merge = +, ntasks = 4)
    @test_throws ArgumentError CC.foldxt(+, CC.Map(identity), zip(1:3, 1:3); init = () -> 0, merge = +)
    @test_throws ArgumentError CC.foldxt(+, CC.Map(identity), Set(1:3); init = () -> 0, merge = +)
    # The documented ways out.
    @test CC.foldxl(+, CC.Map(identity), g; init = 0) == sum(1:(10^6))
    @test CC.foldxt(+, CC.Map(identity), collect(1:10); init = () -> 0, merge = +) == 55
    # A range is an AbstractVector: accepted, and its views copy nothing.
    @test CC.foldxt(+, CC.Map(identity), 1:10; init = () -> 0, merge = +, ntasks = 3) == 55
end

@testitem "A8: init is a value in foldxl and a factory in foldparts/foldxt" tags = [:unit] begin
    const CC = ChuiCore
    @test_throws ArgumentError CC.foldxt(+, CC.Map(identity), collect(1:10); init = 0, merge = +)
    @test_throws ArgumentError CC.foldparts(+, CC.Map(identity), [1:10]; init = 0, merge = +)
    @test CC.foldxl(+, CC.Map(identity), 1:10; init = 0) == 55
    # One init() per partition: a mutable accumulator is never shared between partitions.
    @test CC.foldparts(push!, CC.Map(identity), [1:2, 3:4]; init = () -> Int[], merge = append!) == 1:4
end

@testitem "Take reuse (R3; the prototype gave 3, then 0)" tags = [:unit] begin
    const CC = ChuiCore
    xf = CC.Take(3)
    @test CC.foldxl(+, xf, 1:10; init = 0) == 6
    @test CC.foldxl(+, xf, 1:10; init = 0) == 6
    rf = CC.asrf(xf, +)
    run(rf) = (
        acc = CC.start(rf, 0); for x in 1:10
            r = CC.next(rf, acc, x)
            CC.isreduced(r) && return CC.complete(rf, CC.unreduced(r))
            acc = r
        end; CC.complete(rf, acc)
    )
    @test run(rf) == run(rf) == 6
end
