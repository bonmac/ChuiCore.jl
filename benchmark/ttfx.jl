#!/usr/bin/env julia
# ttfx.jl: load time, time to first X (TTFX) and precompile time for ChuiCore (ADR-0009).
#
#   julia +release benchmark/ttfx.jl [--runs N] [--out FILE] [--check]
#   julia +lts     benchmark/ttfx.jl [--runs N] [--out FILE] [--check]
#
# `--check` compares the warm medians with benchmark/budgets.toml and exits 1 over budget.
#
# Each sample is a fresh `julia --startup-file=no --project=<scratch env>` process, so the timings are
# process-level, as a user sees them:
#   startup     `julia -e 'nothing'` wall time (the floor every other number sits on)
#   load        `using ChuiCore` timed inside the process (Julia's own startup excluded)
#   first call  the TTFX workload below, run once after `using` and its Base-only SETUP
#   precompile  `@elapsed Base.compilecache` of ChuiCore after its cache files are removed
# "cold" is the first process after the precompile (OS file cache as the compile left it); "warm"
# is the median of the next `--runs` processes, with the min and max as the spread.
# Stdlib only: it runs on both Julia versions without an environment of its own.
module TTFX

    using TOML: TOML

    median(xs) = (s = sort(xs); n = length(s); isodd(n) ? s[(n + 1) ÷ 2] : (s[n ÷ 2] + s[n ÷ 2 + 1]) / 2)

    const ROOT = normpath(joinpath(@__DIR__, ".."))

    # The TTFX workload: the first call of each hot path a downstream package hits at once.
    # It mirrors `src/precompile.jl` on purpose (ADR-0009 §3); test/precompile_tests.jl checks
    # with `--trace-compile` that it compiles no ChuiCore method. SETUP (Base only: the inputs)
    # runs before the timer starts, so "first call" times ChuiCore's calls alone.
    const SETUP = raw"""
    C = ChuiCore
    v = collect(1.0:1000.0); vi = collect(1:1000)
    parts = [view(v, 1:500), view(v, 501:1000)]
    """
    const WORKLOAD = raw"""
    C.final(C.Sum(), C.combine(C.Sum(), C.partial(C.Sum(), C.init(C.Sum()), v), 1.0))
    C.final(C.Mean(), C.combine(C.Mean(), C.partial(C.Mean(), C.init(C.Mean()), v), (1.0, 1)))
    C.final(C.Max(), C.partial(C.Max(), C.init(C.Max()), vi))
    C.foldxl(+, C.Map(abs) ⨟ C.Filter(>(1.0)), v; init = 0.0)
    C.aggregate(C.Sum(), C.Map(abs), parts)
    (sin ⨟ cos)(1.0)
    """

    const SCRIPT = """
    t0 = time_ns(); using ChuiCore; t1 = time_ns()
    $SETUP
    t2 = time_ns()
    $WORKLOAD
    t3 = time_ns()
    println((t1 - t0) / 1e9, " ", (t3 - t2) / 1e9)
    """

    julia() = Base.julia_cmd().exec[1]
    # A user's environment: a scratch project that `Pkg.develop`s this checkout (nothing in the
    # repo is written; no Manifest lands next to Project.toml).
    # A scratch depot is stacked in front of the user's depot: ChuiCore's cache files are written
    # (and removed for the precompile timing) there only. Dependencies' caches are reused from the
    # user depot when they match; otherwise they are compiled once into the scratch depot and kept.
    const ENV_DIR = Ref("")
    const DEPOT = Ref("")
    function jl(args...)
        cmd = `$(julia()) --startup-file=no --project=$(ENV_DIR[]) $args`
        return addenv(cmd, "JULIA_DEPOT_PATH" => DEPOT[] * ":" * join(DEPOT_PATH, ":"))
    end
    function make_env()
        ENV_DIR[] = mktempdir()
        DEPOT[] = mktempdir()
        run(pipeline(jl("-e", "using Pkg; Pkg.develop(path = ARGS[1]); Pkg.instantiate()", ROOT); stdout = devnull, stderr = devnull))
        return nothing
    end

    function sample()
        out = readchomp(jl("-e", SCRIPT))
        a, b = parse.(Float64, split(last(split(out, '\n'))))
        return a, b
    end

    startup() = @elapsed run(`$(julia()) --startup-file=no -e nothing`)

    function precompile_time()
        # Remove ChuiCore's cache files from the scratch depot, then time `compilecache` alone
        # (its output process, without loading the result into the timing process).
        # Only ChuiCore's own directory: dependencies compiled into the scratch depot (when the
        # user depot had no matching cache) stay, so the timing never includes compiling them.
        v = "v$(VERSION.major).$(VERSION.minor)"
        rm(joinpath(DEPOT[], "compiled", v, "ChuiCore"); force = true, recursive = true)
        cdir = joinpath(DEPOT[], "compiled", v)
        deps = isdir(cdir) ? filter(!=("ChuiCore"), readdir(cdir)) : String[]
        isempty(deps) || println("ttfx.jl: note: dependency caches NOT reused from the user depot (compiled once into the scratch depot, kept): ", join(deps, ", "))
        code = """
        id = Base.identify_package("ChuiCore")
        print(@elapsed Base.compilecache(id))
        """
        return parse(Float64, last(split(readchomp(pipeline(jl("-e", code); stderr = devnull)), '\n')))
    end

    stats(xs) = (median = median(xs), min = minimum(xs), max = maximum(xs))
    fmt(x) = string(round(x * 1000; digits = 1), " ms")
    fmt(s::NamedTuple) = string(fmt(s.median), " [", fmt(s.min), ", ", fmt(s.max), "]")

    # Budgets: benchmark/budgets.toml [ttfx.<major.minor>] (ADR-0009 §3), in milliseconds.
    function budgets()
        all = TOML.parsefile(joinpath(ROOT, "benchmark", "budgets.toml"))["ttfx"]
        return get(all, "$(VERSION.major).$(VERSION.minor)", get(all, "default", Dict()))
    end

    function check(io, name, measured_s, budget_ms)
        ok = measured_s * 1000 <= budget_ms
        println(io, rpad(name, 27), ": ", fmt(measured_s), " (budget ", budget_ms, " ms) ", ok ? "OK" : "OVER BUDGET")
        return ok
    end

    function main(args)
        runs = 10
        out = nothing
        docheck = false
        i = 1
        while i <= length(args)
            args[i] == "--runs" && (runs = parse(Int, args[i + 1]); i += 2; continue)
            args[i] == "--out" && (out = args[i + 1]; i += 2; continue)
            args[i] == "--check" && (docheck = true; i += 1; continue)
            error("ttfx.jl: unknown argument $(args[i])")
        end
        make_env()
        run(pipeline(jl("-e", "using ChuiCore"); stderr = devnull))   # caches of the deps exist
        pre = [precompile_time() for _ in 1:3]
        cold = sample()                       # the first process after the last compile
        warm = [sample() for _ in 1:runs]
        st = [startup() for _ in 1:runs]
        load = stats(first.(warm))
        call = stats(last.(warm))
        tot = stats(first.(warm) .+ last.(warm))
        io = IOBuffer()
        println(
            io, "julia ", VERSION, " | ", Sys.cpu_info()[1].model, " ", length(Sys.cpu_info()), " cores | ",
            "load average ", round.(Sys.loadavg(); digits = 2), " | runs ", runs
        )
        println(io, "startup (julia -e nothing) : ", fmt(stats(st)))
        println(io, "precompile (ChuiCore only) : ", fmt(stats(pre)), "  (3 compiles)")
        println(io, "cold  load + first call    : ", fmt(cold[1]), " + ", fmt(cold[2]))
        println(io, "warm  load                 : ", fmt(load))
        println(io, "warm  first call           : ", fmt(call))
        println(io, "warm  load + first call    : ", fmt(tot))
        ok = true
        if docheck
            b = budgets()
            println(io, "budgets (benchmark/budgets.toml, warm medians):")
            ok &= check(io, "  load", load.median, b["load_ms"])
            ok &= check(io, "  load + first call", tot.median, b["load_first_call_ms"])
            ok &= check(io, "  precompile", stats(pre).median, b["precompile_ms"])
        end
        s = String(take!(io))
        print(s)
        out === nothing || write(out, s)
        return ok ? 0 : 1
    end

end # module

abspath(PROGRAM_FILE) == @__FILE__() && exit(TTFX.main(ARGS))
