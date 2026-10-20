# Planted violations, one per law (ADR-0007 §5): each kit runs on a deliberately unlawful instance
# inside a capturing test set, under both drivers (sample collection, then
# `Data.SampledFrom(samples)`), and the test asserts the exact set of failing laws.
# These run on Julia 1.10: never tag them :slow.

@testitem "planted violations: semigroup kit" tags = [:laws] setup = [LawCapture] begin
    using Test
    using Supposition: Data
    const CC = ChuiCore
    function both(kit, bad, samples; kw...)
        a = LawCapture.captured(() -> kit(bad, samples; kw...))
        b = LawCapture.captured(() -> kit(bad, Data.SampledFrom(samples); max_examples = 60, kw...))
        return a, b
    end
    samples = [[1], [2], [3, 4], Int[], [-5]]

    # associativity: combine is subtraction.
    struct MinusSG end
    CC.init(::MinusSG) = 0
    CC.partial(::MinusSG, acc, chunk) = acc + sum(chunk; init = 0)
    CC.combine(::MinusSG, a, b) = a - b
    for (failing, ran) in both(test_semigroup_laws, MinusSG(), samples)
        @test failing == Set(["associativity"])
        @test "associativity" in ran
    end
end

@testitem "planted violations: monoid kit" tags = [:laws] setup = [LawCapture] begin
    using Test
    using Supposition: Data
    const CC = ChuiCore
    function both(kit, bad, samples; kw...)
        a = LawCapture.captured(() -> kit(bad, samples; kw...))
        b = LawCapture.captured(() -> kit(bad, Data.SampledFrom(samples); max_examples = 60, kw...))
        return a, b
    end
    all_laws = Set(["associativity", "left identity", "right identity", "neutral matches init", "neutral is fresh"])
    samples = [[1], [2], [3, 4], Int[], [-5], [6]]

    # An Int carrier built by summing the chunk; each case changes one piece.
    abstract type IntCarrier end
    CC.init(::IntCarrier) = 0
    CC.neutral(::IntCarrier) = 0
    CC.partial(::IntCarrier, acc, chunk) = acc + sum(chunk; init = 0)

    # associativity: a ⊕ b = a + b + ab(a - b) has the two-sided identity 0 but is not associative.
    struct NonAssoc <: IntCarrier end
    CC.combine(::NonAssoc, a, b) = a + b + a * b * (a - b)
    # left identity: a ⊕ b = a is associative and has 0 as right identity only.
    struct LeftProj <: IntCarrier end
    CC.combine(::LeftProj, a, b) = a
    # right identity: a ⊕ b = b, the mirror image.
    struct RightProj <: IntCarrier end
    CC.combine(::RightProj, a, b) = b
    # neutral matches init: a lawful sum whose init starts at 1 instead of the neutral 0.
    struct OffInit <: IntCarrier end
    CC.init(::OffInit) = 1
    CC.combine(::OffInit, a, b) = a + b

    for (bad, law) in ((NonAssoc(), "associativity"), (LeftProj(), "left identity"), (RightProj(), "right identity"), (OffInit(), "neutral matches init"))
        for (failing, ran) in both(test_monoid_laws, bad, samples)
            @test failing == Set([law])
            @test ran == all_laws
        end
    end

    # neutral is fresh: `neutral` returns a cached vector, refreshed only by `partial` (a lazy
    # cache bug). A shared constant neutral would also break both identities and "neutral matches
    # init" (each mutating combine leaves it non-empty); the lazy cache keeps them lawful because
    # every law except "neutral is fresh" builds a carrier (refreshing the cache) before it reuses
    # a neutral that `combine` mutated.
    struct LazyNeutral end
    const NCACHE = Ref(Int[])
    CC.init(::LazyNeutral) = Int[]
    CC.neutral(::LazyNeutral) = NCACHE[]
    CC.partial(::LazyNeutral, acc, chunk) = (append!(acc, chunk); NCACHE[] = Int[]; acc)
    CC.combine(::LazyNeutral, a, b) = append!(a, b)
    for (failing, ran) in both(test_monoid_laws, LazyNeutral(), samples)
        @test failing == Set(["neutral is fresh"])
        @test ran == all_laws
    end
end

@testitem "planted violations: aggregator kit" tags = [:laws] setup = [LawCapture] begin
    using Test
    using Supposition: Data
    const CC = ChuiCore
    function both(kit, bad, samples; kw...)
        a = LawCapture.captured(() -> kit(bad, samples; kw...))
        b = LawCapture.captured(() -> kit(bad, Data.SampledFrom(samples); max_examples = 60, kw...))
        return a, b
    end
    all_laws = Set(["split invariance", "empty partition identity", "chunk concatenation", "commutativity", "init is fresh", "agrees with reference"])
    samples = [[1, 2, 3], Int[], [4, -1, 2, 7], [5], [3, 3, 8, 1, 2]]
    check(bad, expected; samples = samples, reference = sum) =
        for (failing, ran) in both(test_aggregator_laws, bad, samples; reference = reference)
        @test failing == Set(expected)
        @test ran == all_laws
    end

    abstract type IntAgg end
    CC.init(::IntAgg) = 0
    CC.partial(::IntAgg, acc, chunk) = acc + sum(chunk; init = 0)

    # split invariance: a ⊕ b = a + b + ab(a - b): 0 is still an identity, so empty chunks are fine.
    struct SplitBad <: IntAgg end
    CC.combine(::SplitBad, a, b) = a + b + a * b * (a - b)
    check(SplitBad(), ["split invariance"])

    # empty partition identity: combine adds 1 when the right side is empty. Split invariance
    # fails too, necessarily: its fixed splits include empty chunks, which go through the same
    # combine (lead's decision (d), 2026-10-20).
    struct EmptyBad end
    CC.init(::EmptyBad) = (0, 0)
    CC.partial(::EmptyBad, acc, chunk) = (acc[1] + sum(chunk; init = 0), acc[2] + count(_ -> true, chunk))
    CC.combine(::EmptyBad, a, b) = b[2] == 0 ? (a[1] + 1, a[2]) : (a[1] + b[1], a[2] + b[2])
    CC.final(::EmptyBad, acc) = acc[1]
    check(EmptyBad(), ["empty partition identity", "split invariance"])

    # chunk concatenation: a second `partial` on the same accumulator counts the chunk twice.
    # Every other law calls `partial` only on a fresh `init`.
    struct ConcatBad end
    CC.init(::ConcatBad) = (0, false)
    CC.partial(::ConcatBad, acc, chunk) = (acc[1] + (acc[2] ? 2 : 1) * sum(chunk; init = 0), true)
    CC.combine(::ConcatBad, a, b) = (a[1] + b[1], a[2] || b[2])
    CC.final(::ConcatBad, acc) = acc[1]
    check(ConcatBad(), ["chunk concatenation"])

    # commutativity: a lawful `first` that wrongly declares itself commutative.
    struct FirstC end
    CC.init(::FirstC) = nothing
    CC.partial(::FirstC, acc, chunk) =
        acc !== nothing ? acc : (y = iterate(chunk); y === nothing ? nothing : Some(y[1]))
    CC.combine(::FirstC, a, b) = a === nothing ? b : a
    CC.final(::FirstC, acc) = something(acc)
    CC.iscommutative(::FirstC) = true
    check(FirstC(), ["commutativity"]; samples = [[1, 2], [3], [4, 5, 6], [7, 8]], reference = first)

    # init is fresh: `init` returns a cached box, refreshed only by `partial` (a lazy cache bug).
    # Every other law calls `partial` right after each `init`, so only two `init`s taken before
    # any `partial` alias.
    mutable struct Box
        s::Int
    end
    struct InitBad end
    const ICACHE = Ref(Box(0))
    CC.init(::InitBad) = ICACHE[]
    CC.partial(::InitBad, acc, chunk) = (acc.s += sum(chunk; init = 0); ICACHE[] = Box(0); acc)
    CC.combine(::InitBad, a, b) = (a.s += b.s; a)
    CC.final(::InitBad, acc) = acc.s
    CC.iscommutative(::InitBad) = true
    check(InitBad(), ["init is fresh"])

    # agrees with reference: a lawful Sum checked against a wrong reference.
    check(CC.Sum(), ["agrees with reference"]; reference = v -> sum(v) + 1)

    # "agrees with reference" is absent without a reference; "commutativity" is always present.
    for (failing, ran) in both(test_aggregator_laws, CC.First(), samples)
        @test isempty(failing)
        @test ran == setdiff(all_laws, ["agrees with reference"])
    end
end
