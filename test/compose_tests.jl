@testitem "CC-001 ⨟ composes left to right" tags = [:unit] begin
    import CompositionsBase
    inc(x) = x + 1
    dbl(x) = 2x
    @test ChuiCore.opcompose === ChuiCore.:⨟
    @test ChuiCore.:⨟ === CompositionsBase.:⨟
    @test ChuiCore.opcompose === CompositionsBase.opcompose
    for x in (-3, 0, 1, 2.5, 10)
        @test (inc ⨟ dbl)(x) == dbl(inc(x))
        @test opcompose(inc, dbl)(x) == dbl(inc(x))
        @test (abs ⨟ sqrt)(x) == sqrt(abs(x))
        @test ((inc ⨟ dbl) ⨟ abs)(x) == (inc ⨟ (dbl ⨟ abs))(x) == abs(dbl(inc(x)))
        @test (identity ⨟ inc)(x) == inc(x) == (inc ⨟ identity)(x)
    end
    @test (inc ⨟ dbl)(3) == 8
    @test Meta.parse("c.x .> 3 ⨟ g") == :(c.x .> (3 ⨟ g))
    @test Meta.parse("x |> f ⨟ g") == :(x |> (f ⨟ g))
    @test Meta.parse("f ⨟ g ∘ h") == :((f ⨟ g) ∘ h)
    @test Meta.parse("a ⨟ b ⨟ c").args == Any[:⨟, :(a ⨟ b), :c]
end

@testitem "ChuiCore re-exports only ⨟ and opcompose from CompositionsBase" tags = [:unit] begin
    import CompositionsBase
    cb = setdiff(names(CompositionsBase), [:CompositionsBase])
    @test Set(intersect(cb, names(ChuiCore))) == Set([:⨟, :opcompose])
    @test Base.isexported(ChuiCore, :⨟) && Base.isexported(ChuiCore, :opcompose)
    for n in (:compose, :decompose, :deopcompose, :∘)
        @test !Base.isexported(ChuiCore, n)
    end
end

@testitem "bare ⨟ resolves with CompositionsBase also loaded" tags = [:unit] begin
    # In a fresh module: `using ChuiCore, CompositionsBase` must not make `⨟` ambiguous (E-37:
    # checked by resolving the name, never by the absence of a warning).
    m = Module(:BareCheck)
    Core.eval(m, :(using ChuiCore, CompositionsBase))
    @test Core.eval(m, :(⨟)) === ChuiCore.:⨟
    @test Core.eval(m, :((abs ⨟ string)(-2))) == "2"
end

@testitem "pipe" tags = [:unit] begin
    @test pipe(3) == 3
    @test pipe(3, x -> x + 1) == 4
    @test pipe(3, x -> x + 1, x -> 2x) == 8
    @test pipe([3, 1, 2], sort, first) == 1
    @test (@inferred pipe(2, abs, float, string)) == "2.0"
    fs = (x -> x + 1, x -> 2x, string)
    @test pipe(1, fs...) == "4"
end

@testitem "curry" tags = [:unit] begin
    @test ChuiCore.curry(+, 1)(5) == 5
    @test ChuiCore.curry(+, 2)(1)(2) == 3
    @test ChuiCore.curry((a, b, c) -> a - b * c, 3)(10)(2)(3) == 4
    c2 = ChuiCore.curry(*, Val(2))
    @test (@inferred c2("a")("b")) == "ab"
    partial1 = c2("x")
    @test partial1("y") == "xy" && partial1("z") == "xz"   # reusable: no hidden state
    @test_throws ArgumentError ChuiCore.curry(+, 0)
    @test_throws ArgumentError ChuiCore.curry(+, -1)
end

@testitem "papply" tags = [:unit] begin
    @test papply(-, 10)(3) == 7
    @test papply(+)(1, 2) == 3
    @test papply(+, 1, 2)(3, 4) == 10
    @test papply(+, 1, 2)() == 3
    f(a, b; scale = 1, shift = 0) = (a - b) * scale + shift
    @test papply(f, 10; scale = 2)(4) == 12
    @test papply(f, 10; scale = 2)(4; scale = 3) == 18          # call-site keywords win
    @test papply(f, 10; scale = 2)(4; shift = 1) == 13
    g = papply(push!, [1])
    @test g(2) == [1, 2]                                        # fixed values are shared, as in Base.Fix1
    @test (@inferred papply(+, 1)(2)) == 3
    @test !isdefined(ChuiCore, :partial) || ChuiCore.partial !== papply
    @test !Base.isexported(ChuiCore, :partial)
end

@testitem "flip" tags = [:unit] begin
    @test flip(-)(1, 10) == 9
    @test flip(string)("a", "b", "c") == "bac"
    @test flip(flip(-))(10, 1) == 9
    @test (@inferred flip(/)(2, 1)) == 0.5
end
