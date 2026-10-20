# Planted violations of the optics kits (ADR-0007 §5): for every law of `test_lens_laws` and
# `test_prism_laws`, an unlawful optic that breaks exactly that law, run in a capturing test set
# under both drivers. Each test asserts the exact set of failing law names.

@testmodule PlantedOptics begin
    using ChuiCore: ChuiCore, Prism
    using Supposition: Data

    # A lens on the field `a` of `(a = …, n = …)` whose `set` is defective in the way `K` names.
    struct BadLens{K} end
    (::BadLens)(s) = s.a
    # get-set only: `set` also resets `n`.
    ChuiCore.set(s, ::BadLens{:getset}, v) = (a = v, n = 0)
    # set-get only: `set` stores `abs(v)` (the samples have `a ≥ 0`, so get-set holds).
    ChuiCore.set(s, ::BadLens{:setget}, v) = (a = abs(v), n = s.n)
    # set-set only: `set` remembers the previous focus in `n` (the samples have `n == a`).
    ChuiCore.set(s, ::BadLens{:setset}, v) = (a = v, n = s.a)
    const STATES = [(a = 1, n = 1), (a = 2, n = 2)]
    const VALUES = [-1, 3, 4]

    # review-preview only: `review` builds values the match rejects.
    const BAD_REVIEW = Prism(x -> x > 0 ? Some(x) : nothing, identity)
    # preview-review only: the match forgets the sign.
    const BAD_PREVIEW = Prism(x -> Some(abs(x)), identity)

    """
        both(captured, kit, optic, samples, gens...) -> ((failing, ran), (failing, ran))

    Run `kit` on `optic` inside `captured`, first with sample collections, then with
    `Data.SampledFrom(samples)` as the first generator (the Supposition driver).
    """
    function both(captured, kit, optic, samples, gens...)
        r1 = captured(() -> kit(optic, samples, gens...))
        r2 = captured(() -> kit(optic, Data.SampledFrom(samples), gens...; max_examples = 60))
        return r1, r2
    end
end

@testitem "planted: lens laws" tags = [:laws] setup = [LawCapture, PlantedOptics] begin
    using Test, Supposition
    P = PlantedOptics
    laws = ("get-set", "set-get", "set-set")
    defect = Dict("get-set" => :getset, "set-get" => :setget, "set-set" => :setset)
    for law in laws
        lens = P.BadLens{defect[law]}()
        for (failing, ran) in P.both(LawCapture.captured, test_lens_laws, lens, P.STATES, P.VALUES)
            @test failing == Set([law])
            @test ran == Set(laws)
        end
    end
end

@testitem "planted: prism laws" tags = [:laws] setup = [LawCapture, PlantedOptics] begin
    using Test, Supposition
    P = PlantedOptics
    laws = Set(["review-preview", "preview-review"])
    cases = (
        ("review-preview", P.BAD_REVIEW, [1, 2], [-1, 2]),
        ("preview-review", P.BAD_PREVIEW, [-1, 2], [1, 2]),
    )
    for (law, prism, states, values) in cases
        for (failing, ran) in P.both(LawCapture.captured, test_prism_laws, prism, states, values)
            @test failing == Set([law])
            @test ran == laws
        end
    end
end
