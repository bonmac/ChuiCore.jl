# A real multi-thread run of foldxt/foldparts/aggregate: the test process may have one thread,
# so a child `julia -t 4` runs the checks against this ChuiCore (developed into a scratch env).

@testitem "foldxt/foldparts/aggregate on 4 threads (child process)" tags = [:unit] begin
    # Pkg.test's sandbox sets JULIA_LOAD_PATH to the test environment; the child needs the
    # default load path and its own --project (as in the clash-list item).
    julia = addenv(Base.julia_cmd(), "JULIA_LOAD_PATH" => "@:@stdlib", "JULIA_PROJECT" => nothing)
    env = mktempdir()
    dev = "using Pkg; Pkg.develop(path = $(repr(pkgdir(ChuiCore))); io = devnull); Pkg.instantiate(; io = devnull)"
    run(`$julia --startup-file=no --project=$env -e $dev`)
    script = """
    using ChuiCore
    const CC = ChuiCore
    check(name, got, want) = (got == want || error(name * ": got " * repr(got) * ", want " * repr(want)); println("ok ", name))
    println("nthreads=", Threads.nthreads())
    Threads.nthreads() == 4 || error("expected 4 threads")
    v = collect(1:10^6)
    xf = CC.Map(x -> 2x) ⨟ CC.Filter(x -> x % 3 == 0)
    want = CC.foldxl(+, xf, v; init = 0)
    check("foldxt stateless", CC.foldxt(+, xf, v; init = () -> 0, merge = +, ntasks = 4), want)
    # Which threads ran the partitions (more than one when the scheduler spreads them).
    tids = CC.foldxt((s, x) -> push!(s, Threads.threadid()), CC.Map(identity), v;
        init = () -> Set{Int}(), merge = union!, ntasks = 4)
    println("threads used=", length(tids))
    check("foldxt order (append!)", CC.foldxt(push!, CC.Map(identity), v; init = () -> Int[], merge = append!, ntasks = 4), v)
    check("foldxt stateful Take", CC.foldxt(+, CC.Filter(isodd) ⨟ CC.Take(5000), v; init = () -> 0, merge = +, ntasks = 4), 5000^2)
    check("foldxt TakeWhile", CC.foldxt(+, CC.TakeWhile(<(11)), v; init = () -> 0, merge = +, ntasks = 4), 55)
    check("foldxt early stop", CC.foldxt((a, x) -> x == 600_000 ? CC.reduced(x) : a, CC.Map(identity), v; init = () -> 0, merge = (a, b) -> b, ntasks = 4), 600_000)
    parts = [v[1:250_000], v[250_001:500_000], v[500_001:750_000], v[750_001:end]]
    check("foldparts stateless", CC.foldparts(+, xf, parts; init = () -> 0, merge = +), want)
    check("foldparts Scan", CC.foldparts(max, CC.Scan(+, 0), parts; init = () -> 0, merge = max), sum(v))
    check("aggregate Sum", CC.aggregate(CC.Sum(), xf, parts), want)
    check("aggregate First (non-commutative)", CC.aggregate(CC.First(), CC.Filter(>(500)), parts), 501)
    check("aggregate Last", CC.aggregate(CC.Last(), CC.Filter(<(500_000)), parts), 499_999)
    println("ALL OK")
    """
    out = IOBuffer()
    proc = run(pipeline(ignorestatus(`$julia --startup-file=no -t 4 --project=$env -e $script`); stdout = out, stderr = out))
    report = String(take!(out))
    print(report)
    @test proc.exitcode == 0
    @test occursin("nthreads=4", report)
    @test occursin("ALL OK", report)
end

@testitem "foldxt/foldparts in this process (any thread count)" tags = [:unit] begin
    const CC = ChuiCore
    v = collect(1:(10^5))
    xf = CC.Map(x -> 2x) ⨟ CC.Filter(x -> x % 3 == 0)
    want = CC.foldxl(+, xf, v; init = 0)
    for n in (1, 2, 4, 8)
        @test CC.foldxt(+, xf, v; init = () -> 0, merge = +, ntasks = n) == want
    end
end
