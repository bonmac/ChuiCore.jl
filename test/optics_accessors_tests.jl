# ChuiCoreAccessorsExt (ADR-0004 §4): ChuiCore optics inside Accessors, Accessors optics inside
# ChuiCore's `set`/`modify`, and one rebuild rule for both (ADR-0008).

@testitem "optics: Accessors interop" tags = [:unit] setup = [OpticsFixtures] begin
    using Test
    using Accessors: Accessors, PropertyLens, @set, @optic
    using ChuiCore: Lens, IndexLens, Prism, set, modify
    F = OpticsFixtures
    @test Base.get_extension(ChuiCore, :ChuiCoreAccessorsExt) !== nothing
    b = F.Box(1, "x")
    # One rebuild rule: the owner's `constructorof` (ADR-0008).
    @test set(b, Lens{:a}(), 5) == Accessors.set(b, PropertyLens{:a}(), 5)
    @test set(b, Lens{:b}(), "y") === F.Box(1, "y")
    # ChuiCore optics in Accessors.
    @test Accessors.set(b, Lens{:a}(), 2) == F.Box(2, "x")
    @test Accessors.modify(x -> x * 10, b, Lens{:a}()) == F.Box(10, "x")
    @test Accessors.set((1, 2), IndexLens(1), 0) == (0, 2)
    @test Accessors.modify(x -> x + 1, [1, 2], IndexLens(2)) == [1, 3]
    pc = Prism(F.Circle)
    @test Accessors.modify(c -> F.Circle(c.r + 1), F.Circle(1.0), pc) == F.Circle(2.0)
    @test Accessors.modify(c -> F.Circle(c.r + 1), F.Rect(1.0, 1.0), pc) == F.Rect(1.0, 1.0)
    @test Accessors.set(F.Circle(1.0), pc, F.Circle(9.0)) == F.Circle(9.0)
    # Accessors optics in ChuiCore.
    @test set(b, PropertyLens{:a}(), 3) == F.Box(3, "x")
    @test modify(uppercase, b, PropertyLens{:b}()) == F.Box(1, "X")
    @test set((1, 2, 3), Accessors.IndexLens((2,)), 0) == (1, 0, 3)
    @test modify(x -> -x, [1, 2], Accessors.IndexLens((1,))) == [-1, 2]
    # Mixed compositions with ∘, both ways.
    o = F.Outer(F.Inner(1, 2.0), :t)
    mixed = Lens{:x}() ∘ PropertyLens{:a}()
    @test set(o, mixed, 7) == F.Outer(F.Inner(7, 2.0), :t)
    @test Accessors.set(o, mixed, 7) == F.Outer(F.Inner(7, 2.0), :t)
    mixed2 = PropertyLens{:y}() ∘ Lens{:a}()
    @test modify(y -> 2y, o, mixed2) == F.Outer(F.Inner(1, 4.0), :t)
    @test Accessors.modify(y -> 2y, o, mixed2) == F.Outer(F.Inner(1, 4.0), :t)
    @test (@set o.a.x = 3) == set(o, Lens{:x}() ∘ Lens{:a}(), 3)
    @test set(o, @optic(_.a.x), 4) == F.Outer(F.Inner(4, 2.0), :t)
    # A prism composed with Accessors lenses: through ChuiCore's set/modify.
    s = (shape = F.Circle(1.0),)
    po = PropertyLens{:r}() ∘ pc ∘ PropertyLens{:shape}()
    @test modify(r -> r + 1, s, po) == (shape = F.Circle(2.0),)
    @test modify(r -> r + 1, (shape = F.Rect(1.0, 2.0),), po) == (shape = F.Rect(1.0, 2.0),)
    @test set(s, po, 5.0) == (shape = F.Circle(5.0),)
    # Composed ChuiCore lenses in @set-style Accessors chains.
    nt = (a = (b = 1, c = 2),)
    lb = Lens{:b}()
    @test (@set nt.a |> lb = 9) == (a = (b = 9, c = 2),)
    @test (@set nt |> lb ∘ Lens{:a}() = 8) == (a = (b = 8, c = 2),)
end

@testitem "optics: Accessors extension has no piracy" tags = [:quality] begin
    using Test, Aqua
    using Accessors: Accessors
    ext = Base.get_extension(ChuiCore, :ChuiCoreAccessorsExt)
    @test ext !== nothing
    own = [ChuiCore.set, ChuiCore.modify, ChuiCore.Lens, ChuiCore.IndexLens, ChuiCore.Prism]
    Aqua.test_piracies(ext; treat_as_own = own)
end
