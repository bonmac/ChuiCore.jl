#!/usr/bin/env julia
# allocs.jl: print the measured allocations behind ADR-0009 §1 (the numbers in
# docs/src/performance.md). The assertions are test/perf_allocs_tests.jl; this script reuses its
# `@testmodule PerfAllocs` (fixtures and `minalloc`) so both measure the same way.
#
#   julia +release benchmark/allocs.jl
#   julia +lts     benchmark/allocs.jl
#
# Develops this checkout into a temporary environment; writes no tracked file.
const ROOT = normpath(joinpath(@__DIR__, ".."))
using Pkg
Pkg.activate(; temp = true, io = devnull)
Pkg.develop(path = ROOT, io = devnull)
using ChuiCore
const CC = ChuiCore
let src = read(joinpath(ROOT, "test", "perf_allocs_tests.jl"), String)
    i = findfirst("@testmodule PerfAllocs begin", src)
    j = findfirst("# end of PerfAllocs", src)   # a sentinel line in the test file, not the first `end`
    j === nothing && error("allocs.jl: the `# end of PerfAllocs` sentinel is missing from test/perf_allocs_tests.jl")
    Core.eval(Main, Meta.parse("module PerfAllocs\n" * src[(last(i) + 1):first(j)] * "\nend"))
end
const PA = PerfAllocs

function main()
    println("julia ", VERSION, " threads ", Threads.nthreads())
    vf = collect(1.0:1000.0)
    vi = collect(1:1000)
    vb = isodd.(1:1000)                  # BitVector
    vB = collect(vb)                     # Vector{Bool}
    mx = 0
    monoids = (CC.Sum(), CC.Prod(), CC.Count(), CC.Mean(), CC.Max(), CC.Min(), CC.Extrema(), CC.First(), CC.Last(), CC.Moments(:var), CC.Moments(:std))
    for (aggs, vs) in ((monoids, (vf, vi)), ((CC.CountTrue(), CC.AnyM(), CC.AllM()), (vb, vB)))
        for agg in aggs, v in vs
            w = view(v, 1:500)
            g = (x for x in v)
            acc = CC.partial(agg, CC.init(agg), v)
            mx = max(
                mx, PA.minalloc(() -> CC.partial(agg, CC.init(agg), v)),
                PA.minalloc(() -> CC.partial(agg, CC.init(agg), w)),
                PA.minalloc(() -> CC.partial(agg, CC.init(agg), g)),
                PA.minalloc(() -> CC.combine(agg, acc, acc)), PA.minalloc(() -> CC.final(agg, acc))
            )
        end
    end
    println("aggregators (partial/combine/final, all containers) max bytes: ", mx)
    v2 = collect(1.0:1000.0)
    w2 = view(v2, 1:500)
    mx = 0
    xfs = (
        CC.Map(abs), CC.Filter(>(1.0)), CC.MapCat(x -> (x, x)), CC.Take(10), CC.TakeWhile(<(100.0)),
        CC.Scan(+, 0.0), CC.Map(abs) ⨟ CC.Filter(>(1.0)), CC.Map(abs) ⨟ CC.Take(10), CC.Filter(>(1.0)) ⨟ CC.Scan(+, 0.0),
    )
    for xf in xfs, c in (v2, w2)
        mx = max(mx, PA.minalloc(() -> CC.foldxl(+, xf, c; init = 0.0)))
    end
    println("foldxl (stateless and stateful, vector and view) max bytes: ", mx)
    for n in (10, 64), len in (100, 1000, 10_000)
        u = collect(1.0:len)
        xf = CC.Partition{Float64}(n)
        b = PA.minalloc(() -> CC.foldxl((a, p) -> a + length(p), xf, u; init = 0))
        println("Partition n=$n len=$len: $b B = $(round(b / cld(len, n); digits = 1)) B/chunk (budget $(2 * (64 + 8n)))")
    end
    v4 = collect(1.0:4096.0)
    for k in (1, 2, 4, 8)
        sz = 4096 ÷ k
        parts = [view(v4, (1 + (i - 1) * sz):(i * sz)) for i in 1:k]
        a = PA.minalloc(() -> CC.aggregate(CC.Sum(), CC.Map(abs), parts))
        f = PA.minalloc(() -> CC.foldparts(+, CC.Map(abs), parts; init = () -> 0.0, merge = +))
        t = PA.minalloc(() -> CC.foldxt(+, CC.Map(abs), v4; init = () -> 0.0, merge = +, ntasks = k))
        println("k=$k aggregate $a foldparts $f foldxt $t (budget $(1024 + 1024k))")
    end
    for d in (4, 8)
        t = PA.own(d)
        fx = PA.fix(d)
        n = PA.nnodes(d)
        println(
            "d=$d nodes=$n cata own $(PA.minalloc(() -> CC.cata(PA.peval, t))) B/call; ",
            "cata Fix $(round(PA.minalloc(() -> CC.cata(PA.peval, fx)) / n; digits = 1)) B/node; ",
            "para own $(round(PA.minalloc(() -> CC.para(PA.ppara, t)) / n; digits = 1)) B/node"
        )
    end
    x = 1.0
    h = sin ⨟ cos ⨟ abs
    p = papply(+, 1.0)
    q = flip(-)
    println(
        "compose $(PA.minalloc(() -> h(x))) pipe $(PA.minalloc(() -> pipe(x, sin, cos, abs))) ",
        "papply $(PA.minalloc(() -> p(2.0))) flip $(PA.minalloc(() -> q(1.0, 2.0)))"
    )
    return nothing
end
main()
