# Optics (ADR-0004, ADR-0008): lenses, index lenses, `@lens`, prisms, `set`/`modify`, composition.

@testitem "optics: property lens get/set/modify" tags = [:unit] setup = [OpticsFixtures] begin
    using Test
    using ChuiCore: Lens, set, modify
    F = OpticsFixtures
    p = F.Point(1, 2)
    @test Lens{:a}()(p) == 1
    @test set(p, Lens{:a}(), 10) == F.Point(10, 2)
    @test modify(x -> x + 1, p, Lens{:b}()) == F.Point(1, 3)
    @test Lens(:a) === Lens{:a}()
    @test Lens(Val(:b)) === Lens{:b}()
    @test sizeof(Lens{:a}()) == 0
    nt = (a = 1, b = "x")
    @test Lens{:b}()(nt) == "x"
    @test set(nt, Lens{:a}(), 2.5) == (a = 2.5, b = "x")
    @test modify(uppercase, nt, Lens{:b}()) == (a = 1, b = "X")
    @test_throws ArgumentError Lens{1}()
    # The input is never mutated.
    @test p == F.Point(1, 2)
end

@testitem "optics: index lens" tags = [:unit] begin
    using Test
    using ChuiCore: IndexLens, set, modify
    t = (1, "two", 3.0)
    @test IndexLens(2)(t) == "two"
    @test set(t, IndexLens(2), :two) == (1, :two, 3.0)
    @test modify(x -> 2x, t, IndexLens(3)) == (1, "two", 6.0)
    @test_throws BoundsError set(t, IndexLens(4), 0)
    nt = (a = 1, b = 2)
    @test set(nt, IndexLens(2), 20) == (a = 1, b = 20)
    @test set(nt, IndexLens(:a), 10) == (a = 10, b = 2)
    v = [1, 2, 3]
    w = set(v, IndexLens(2), 20)
    @test w == [1, 20, 3]
    @test v == [1, 2, 3]                     # a copy: the input is not mutated
    @test set(v, IndexLens(1), 1.5) == [1.5, 2, 3]   # the element type widens
    m = [1 2; 3 4]
    @test IndexLens(2, 1)(m) == 3
    @test set(m, IndexLens(2, 1), 30) == [1 2; 30 4]
    d = Dict(:k => 1)
    @test set(d, IndexLens(:k), 2) == Dict(:k => 2)
    @test d == Dict(:k => 1)
    # A single tuple index is an index, not the index tuple.
    @test IndexLens((1, 2)).indices == ((1, 2),)
end

@testitem "optics: composition with ∘ and ⨟" tags = [:unit] setup = [OpticsFixtures] begin
    using Test
    using ChuiCore: Lens, IndexLens, set, modify, ⨟
    F = OpticsFixtures
    o = F.Outer(F.Inner(1, 2.0), :t)
    l = Lens{:x}() ∘ Lens{:a}()
    @test l isa ComposedFunction
    @test l(o) == 1
    @test set(o, l, 99) == F.Outer(F.Inner(99, 2.0), :t)
    @test modify(x -> x + 1, o, Lens{:a}() ⨟ Lens{:y}()) == F.Outer(F.Inner(1, 3.0), :t)
    nt = (a = (b = (10, 20),),)
    l3 = IndexLens(2) ∘ Lens{:b}() ∘ Lens{:a}()
    @test l3(nt) == 20
    @test set(nt, l3, 0) == (a = (b = (10, 0),),)
end

@testitem "optics: @lens" tags = [:unit] setup = [OpticsFixtures] begin
    using Test
    using ChuiCore: Lens, IndexLens, set, @lens
    F = OpticsFixtures
    @test (@lens _.a) === Lens{:a}()
    @test (@lens _.a.b) === Lens{:b}() ∘ Lens{:a}()
    @test (@lens _[2]) === IndexLens(2)
    i = 3
    @test (@lens _.a[i]) === IndexLens(3) ∘ Lens{:a}()
    nt = (a = (b = (1, 2, 3),),)
    l = @lens _.a.b[2]
    @test l(nt) == 2
    @test set(nt, l, 20) == (a = (b = (1, 20, 3),),)
    @test (@lens _[1, 2]) === IndexLens(1, 2)
    @test_throws Exception eval(:(ChuiCore.@lens x.a))
    @test_throws Exception eval(:(ChuiCore.@lens _))
end

@testitem "optics: prisms" tags = [:unit] setup = [OpticsFixtures] begin
    using Test
    using ChuiCore: Prism, Lens, preview, review, set, modify
    F = OpticsFixtures
    pc = Prism(F.Circle)
    c = F.Circle(1.0)
    r = F.Rect(2.0, 3.0)
    @test preview(pc, c) == Some(c)
    @test preview(pc, r) === nothing
    @test review(pc, c) === c
    @test_throws ArgumentError review(pc, r)
    @test modify(s -> F.Circle(2 * s.r), c, pc) == F.Circle(2.0)
    @test modify(s -> F.Circle(2 * s.r), r, pc) === r
    @test set(r, pc, F.Circle(5.0)) === r
    @test set(c, pc, F.Circle(5.0)) == F.Circle(5.0)
    # Not callable: getting through a prism is `preview`.
    @test_throws MethodError pc(c)
    # A match/build prism: a positive Int inside a `Some`.
    pos = Prism(x -> x isa Integer && x > 0 ? Some(x) : nothing, identity)
    @test preview(pos, 3) == Some(3)
    @test preview(pos, -3) === nothing
    @test review(pos, 4) == 4
    @test modify(x -> x + 1, 3, pos) == 4
    @test modify(x -> x + 1, -3, pos) == -3
    # prism then lens, and lens then prism.
    shapes = (s = c,)
    @test modify(x -> 3x, c, Lens{:r}() ∘ pc) == F.Circle(3.0)
    @test modify(x -> 3x, r, Lens{:r}() ∘ pc) === r
    @test set(c, pc ⨟ Lens{:r}(), 7.0) == F.Circle(7.0)
    @test modify(s -> F.Circle(s.r + 1), shapes, pc ∘ Lens{:s}()) == (s = F.Circle(2.0),)
    @test set((s = r,), pc ∘ Lens{:s}(), F.Circle(0.0)) == (s = r,)
end

@testitem "optics: phantom parameter needs constructorof" tags = [:unit] setup = [OpticsFixtures] begin
    using Test
    using ChuiCore: Lens, set
    F = OpticsFixtures
    @test_throws MethodError set(F.Tagged{:m}(1), Lens{:x}(), 2)
    @test set(F.TaggedOk{:m}(1), Lens{:x}(), 2) === F.TaggedOk{:m}(2)
end

@testitem "optics: inferred and allocation-free" tags = [:unit] setup = [OpticsFixtures] begin
    using Test
    using ChuiCore: Lens, set, modify
    F = OpticsFixtures
    o = F.Outer(F.Inner(1, 2.0), :t)
    la = Lens{:a}()
    lx = Lens{:x}() ∘ Lens{:a}()
    inner = F.Inner(5, 6.0)
    @test @inferred(la(o)) === o.a
    @test @inferred(set(o, la, inner)) == F.Outer(inner, :t)
    @test @inferred(modify(F.bump, o, la)) == F.Outer(F.Inner(2, 2.0), :t)
    @test @inferred(lx(o)) === 1
    @test @inferred(set(o, lx, 7)) == F.Outer(F.Inner(7, 2.0), :t)
    @test @inferred(modify(x -> x + 1, o, lx)) == F.Outer(F.Inner(2, 2.0), :t)
    # `l::L where {L}`: a composed lens is a `Function`, which Julia does not specialize on when
    # it is only passed on (see the docstring of `ChuiCore.set`).
    get_a(o, l::L) where {L} = @allocated l(o)
    set_a(o, l::L, v) where {L} = @allocated set(o, l, v)
    mod_a(o, l::L) where {L} = @allocated modify(x -> x, o, l)
    for _ in 1:2   # the first round compiles
        get_a(o, la); set_a(o, la, inner); mod_a(o, la)
        get_a(o, lx); set_a(o, lx, 3); mod_a(o, lx)
    end
    @test get_a(o, la) == 0
    @test set_a(o, la, inner) == 0
    @test mod_a(o, la) == 0
    @test get_a(o, lx) == 0
    @test set_a(o, lx, 3) == 0
    @test mod_a(o, lx) == 0
end
