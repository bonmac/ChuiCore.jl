# Optics law kits (ADR-0004 §2, ADR-0007): every optic passes its kit with sample collections and
# once through the Supposition driver.

@testitem "laws: lenses" tags = [:laws] setup = [OpticsFixtures] begin
    using Test
    using ChuiCore: Lens, IndexLens, @lens
    F = OpticsFixtures
    test_lens_laws(Lens{:a}(), [F.Point(1, 2), F.Point(-3, 0)], [0, 7, -1])
    test_lens_laws(Lens{:b}(), [(a = 1, b = "x"), (a = 2, b = "")], ["y", "", "zz"])
    test_lens_laws(IndexLens(2), [(1, 2, 3), (0, -1, 5)], [10, -10])
    test_lens_laws(IndexLens(2), [[1, 2, 3], [4, 5]], [0, 9])
    os = [F.Outer(F.Inner(1, 2.0), :t), F.Outer(F.Inner(-1, 0.5), :u)]
    test_lens_laws(Lens{:x}() ∘ Lens{:a}(), os, [3, 4, -5])
    test_lens_laws(@lens(_.a.y), os, [1.5, -2.0])
    test_lens_laws(@lens(_.a[2]), [(a = (1, 2),), (a = (3, 4),)], [:p, :q])
end

@testitem "laws: prisms" tags = [:laws] setup = [OpticsFixtures] begin
    using Test
    using ChuiCore: Prism
    F = OpticsFixtures
    shapes = F.Shape[F.Circle(1.0), F.Rect(1.0, 2.0), F.Circle(0.5)]
    test_prism_laws(Prism(F.Circle), shapes, [F.Circle(2.0), F.Circle(-1.0)])
    test_prism_laws(Prism(F.Rect), shapes, [F.Rect(3.0, 4.0)])
    pos = Prism(x -> x > 0 ? Some(x) : nothing, identity)
    test_prism_laws(pos, [-2, 0, 1, 5], [1, 2, 30])
end

@testitem "laws: optics through Supposition" tags = [:laws, :property] setup = [OpticsFixtures] begin
    using Test, Supposition
    using Supposition: Data
    using ChuiCore: Lens, IndexLens, Prism
    F = OpticsFixtures
    ints = Data.Integers(-100, 100)
    points = map(t -> F.Point(t...), Data.Pairs(ints, ints))
    test_lens_laws(Lens{:a}(), points, ints; max_examples = 50)
    tuples = map(t -> (t[1], t[2], 0), Data.Pairs(ints, ints))
    test_lens_laws(IndexLens(2), tuples, ints; max_examples = 50)
    outers = map(t -> F.Outer(F.Inner(t[1], float(t[2])), :t), Data.Pairs(ints, ints))
    test_lens_laws(Lens{:x}() ∘ Lens{:a}(), outers, ints; max_examples = 50)
    shapes = Data.OneOf(
        map(r -> F.Circle(float(r)), ints),
        map(t -> F.Rect(float(t[1]), float(t[2])), Data.Pairs(ints, ints)),
    )
    circles = map(r -> F.Circle(float(r)), ints)
    test_prism_laws(Prism(F.Circle), shapes, circles; max_examples = 50)
    pos = Prism(x -> x > 0 ? Some(x) : nothing, identity)
    test_prism_laws(pos, ints, Data.Integers(1, 100); max_examples = 50)
end
