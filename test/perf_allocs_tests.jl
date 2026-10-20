# Allocation budgets of the hot paths (ADR-0009 Decision §1). Each case is a zero-argument
# closure over local (never global) values, warmed up, measured as the minimum over a few runs.
# Coverage changes codegen, so every item skips its assertions when coverage is on.

@testmodule PerfAllocs begin
    using ChuiCore
    const CC = ChuiCore

    "True when this process runs with code coverage (allocation counts are not meaningful)."
    coverage_on() = Base.JLOptions().code_coverage != 0

    """
        minalloc(f)

    Bytes allocated by `f()`, the minimum over 5 runs after 2 warm-up calls. `f` is a closure with
    no arguments: passing functions through a generic varargs measure reports spurious bytes
    (Julia does not specialize Function-typed varargs passed through `Base.allocated`).
    """
    function minalloc(f::F) where {F}
        f()
        f()
        m = typemax(Int)
        for _ in 1:5
            m = min(m, @allocated f())
        end
        return m
    end

    "Record a visible skip of an item's allocation assertions under coverage."
    function skip_note(name)
        @info "perf_allocs: skipping allocation assertions under code coverage (ADR-0009 §1)" name
        return nothing
    end

    # An own node type with untyped child fields, its own Functor (as benchmark/benchmarks.jl).
    struct PLit
        v::Int
    end
    struct PAdd
        l::Any
        r::Any
    end
    struct PTag end
    CC.constructorclass(::Type{<:Union{PLit, PAdd}}) = PTag()
    CC.FunctorStyle(::PTag) = CC.IsFunctor()
    CC.fmap(::CC.IsFunctor, f, x::PLit) = x
    CC.fmap(::CC.IsFunctor, f, x::PAdd) = PAdd(f(x.l), f(x.r))
    peval(x::PLit) = x.v
    peval(x::PAdd) = x.l + x.r
    ppara(x::PLit) = 1
    ppara(x::PAdd) = x.l[2] + x.r[2]
    own(d) = d == 0 ? PLit(1) : PAdd(own(d - 1), own(d - 1))
    fix(d) = d == 0 ? CC.Fix(PLit(1)) : CC.Fix(PAdd(fix(d - 1), fix(d - 1)))
    nnodes(d) = 2^(d + 1) - 1
    # end of PerfAllocs: benchmark/allocs.jl extracts the module body up to this line.
end

@testitem "perf allocs: built-in aggregators partial/combine/final are 0 B" tags = [:unit] setup = [PerfAllocs] begin
    using Test
    const CC = ChuiCore
    const PA = PerfAllocs
    if PA.coverage_on()
        PA.skip_note("aggregators")
        @test_skip false
    else
        # `vb` is a BitVector, `vB` a Vector{Bool}: both are "Bool vectors" (ADR-0009 §1).
        let vf = collect(1.0:1000.0), vi = collect(1:1000), vb = isodd.(1:1000), vB = collect(vb)
            numeric = (
                CC.Sum(), CC.Prod(), CC.Count(), CC.Mean(), CC.Max(), CC.Min(), CC.Extrema(),
                CC.First(), CC.Last(), CC.Moments(:var), CC.Moments(:std),
            )
            boolean = (CC.CountTrue(), CC.AnyM(), CC.AllM())
            for (aggs, vs) in ((numeric, (vf, vi)), (boolean, (vb, vB)))
                for agg in aggs, v in vs
                    w = view(v, 1:500)
                    g = (x for x in v)
                    acc = CC.partial(agg, CC.init(agg), v)
                    @test PA.minalloc(() -> CC.partial(agg, CC.init(agg), v)) == 0
                    @test PA.minalloc(() -> CC.partial(agg, CC.init(agg), w)) == 0
                    @test PA.minalloc(() -> CC.partial(agg, CC.init(agg), g)) == 0
                    @test PA.minalloc(() -> CC.combine(agg, acc, acc)) == 0
                    @test PA.minalloc(() -> CC.final(agg, acc)) == 0
                end
            end
        end
    end
end

@testitem "perf allocs: foldxl with stateless and simple stateful transducers is 0 B" tags = [:unit] setup = [PerfAllocs] begin
    using Test
    const CC = ChuiCore
    const PA = PerfAllocs
    if PA.coverage_on()
        PA.skip_note("foldxl")
        @test_skip false
    else
        let v = collect(1.0:1000.0)
            w = view(v, 1:500)
            xfs = (
                CC.Map(abs), CC.Filter(>(1.0)), CC.MapCat(x -> (x, x)), CC.Take(10),
                CC.TakeWhile(<(100.0)), CC.Scan(+, 0.0), CC.Map(abs) ⨟ CC.Filter(>(1.0)),
                CC.Map(abs) ⨟ CC.Take(10), CC.Filter(>(1.0)) ⨟ CC.Scan(+, 0.0),
            )
            for xf in xfs, c in (v, w)
                @test PA.minalloc(() -> CC.foldxl(+, xf, c; init = 0.0)) == 0
            end
        end
    end
end

@testitem "perf allocs: foldxl with Partition{Float64}(n) is bounded per chunk" tags = [:unit] setup = [PerfAllocs] begin
    using Test
    const CC = ChuiCore
    const PA = PerfAllocs
    if PA.coverage_on()
        PA.skip_note("Partition")
        @test_skip false
    else
        for n in (10, 64), len in (100, 1000, 10_000)
            let v = collect(1.0:len), xf = CC.Partition{Float64}(n)
                chunks = cld(len, n)
                bytes = PA.minalloc(() -> CC.foldxl((a, p) -> a + length(p), xf, v; init = 0))
                @test bytes <= chunks * 2 * (64 + n * sizeof(Float64))
            end
        end
    end
end

@testitem "perf allocs: aggregate/foldparts/foldxt over k partitions" tags = [:unit] setup = [PerfAllocs] begin
    using Test
    const CC = ChuiCore
    const PA = PerfAllocs
    if PA.coverage_on()
        PA.skip_note("partitions")
        @test_skip false
    else
        # Every partition is a spawned task whatever Threads.nthreads() is, and foldxt is given
        # ntasks explicitly, so the counts below do not depend on the thread count.
        let v = collect(1.0:4096.0)
            for k in (1, 2, 4, 8)
                sz = 4096 ÷ k
                parts = [view(v, (1 + (i - 1) * sz):(i * sz)) for i in 1:k]
                budget = 1024 + 1024k
                @test PA.minalloc(() -> CC.aggregate(CC.Sum(), CC.Map(abs), parts)) <= budget
                @test PA.minalloc(
                    () -> CC.foldparts(+, CC.Map(abs), parts; init = () -> 0.0, merge = +),
                ) <= budget
                @test PA.minalloc(
                    () -> CC.foldxt(+, CC.Map(abs), v; init = () -> 0.0, merge = +, ntasks = k),
                ) <= budget
            end
        end
    end
end

@testitem "perf allocs: cata over an own node type is bounded per call" tags = [:unit] setup = [PerfAllocs] begin
    using Test
    const CC = ChuiCore
    const PA = PerfAllocs
    if PA.coverage_on()
        PA.skip_note("cata own")
        @test_skip false
    else
        let t4 = PA.own(4), t8 = PA.own(8)
            b4 = PA.minalloc(() -> CC.cata(PA.peval, t4))
            b8 = PA.minalloc(() -> CC.cata(PA.peval, t8))
            @test CC.cata(PA.peval, t8) == 2^8
            @test b4 <= 128
            @test b8 <= 128
            # 16x the nodes, no more bytes: the cost is per call, not per node.
            @test b8 <= b4
        end
    end
end

@testitem "perf allocs: cata over Fix and para over an own node type are bounded per node" tags = [:unit] setup = [PerfAllocs] begin
    using Test
    const CC = ChuiCore
    const PA = PerfAllocs
    if PA.coverage_on()
        PA.skip_note("cata Fix, para")
        @test_skip false
    else
        for d in (4, 8)
            let f = PA.fix(d), t = PA.own(d), n = PA.nnodes(d)
                @test CC.cata(PA.peval, f) == 2^d
                @test CC.para(PA.ppara, t) == 2^d
                @test PA.minalloc(() -> CC.cata(PA.peval, f)) <= 64n
                # ADR-0009 §1: `para` is ≤ 64 B/node from 1.11 and ≤ 96 B/node on 1.10 (measured
                # 2026-10-20: 1.10.12 76.4 B/node at depth 4, 79.8 at depth 8; 1.13.2 45.4 and
                # 47.8). The extra bytes on 1.10 are its boxing of the `(child, result)` hole
                # tuple: a callable struct in place of the closure measures the same.
                budget = VERSION < v"1.11" ? 96n : 64n
                @test PA.minalloc(() -> CC.para(PA.ppara, t)) <= budget
            end
        end
    end
end

@testitem "perf allocs: composition helpers on Float64 are 0 B" tags = [:unit] setup = [PerfAllocs] begin
    using Test
    using ChuiCore: ⨟, pipe, papply, flip
    const PA = PerfAllocs
    if PA.coverage_on()
        PA.skip_note("composition")
        @test_skip false
    else
        let x = 1.0, h = sin ⨟ cos ⨟ abs, p = papply(+, 1.0), q = flip(-)
            @test h(x) == abs(cos(sin(x)))
            @test PA.minalloc(() -> h(x)) == 0
            @test PA.minalloc(() -> pipe(x, sin, cos, abs)) == 0
            @test PA.minalloc(() -> p(2.0)) == 0
            @test PA.minalloc(() -> q(1.0, 2.0)) == 0
        end
    end
end
