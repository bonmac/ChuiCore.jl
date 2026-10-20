# ChuiCore's own `__init__` banner (docs/agent/BRIEF.md, "Name-conflict banner, like dplyr"):
# printed only in interactive sessions, silenced by CHUI_QUIET_CONFLICTS, and never able to break
# `using ChuiCore`. Each subprocess is a fresh `julia` on this test environment: `-i` makes
# `isinteractive()` true, and the script exits before the REPL would start.

@testmodule BannerChild begin
    # A planted module in `Main` that exports two of ChuiCore's exported names with its own bindings.
    const PLANT = "module ChuiPlantedClash; export chain, papply; chain() = 1; papply() = 2; end\n"

    # Run `script` in a fresh process; `quiet` is the CHUI_QUIET_CONFLICTS value (`nothing`: unset).
    function run_child(script; interactive::Bool, quiet = nothing, extra = Pair{String, String}[])
        env = copy(ENV)
        delete!(env, "CHUI_QUIET_CONFLICTS")
        delete!(env, "JULIA_DEBUG")
        quiet === nothing || (env["CHUI_QUIET_CONFLICTS"] = quiet)
        for (k, v) in extra
            env[k] = v
        end
        flags = interactive ? `-i --banner=no` : ``
        cmd = `$(Base.julia_cmd()) --startup-file=no --color=no $flags --project=$(Base.active_project()) -e $script`
        out, err = IOBuffer(), IOBuffer()
        p = run(pipeline(ignorestatus(setenv(cmd, env)); stdin = devnull, stdout = out, stderr = err))
        return (code = p.exitcode, out = String(take!(out)), err = String(take!(err)))
    end

    const LOAD = PLANT * "using ChuiCore\nprint(\"loaded \", isinteractive())\nexit()\n"
end

@testitem "banner init: prints in an interactive session with a planted clash" tags = [:unit] setup = [BannerChild] begin
    using Test
    r = BannerChild.run_child(BannerChild.LOAD; interactive = true)
    @test r.code == 0
    @test r.out == "loaded true"
    @test occursin("Conflicts with ChuiCore", r.err)
    @test occursin("chain", r.err) && occursin("papply", r.err)
    @test occursin("ChuiPlantedClash", r.err)
    @test occursin("CHUI_QUIET_CONFLICTS", r.err)     # tells the user how to silence it
end

@testitem "banner init: silent when CHUI_QUIET_CONFLICTS is set" tags = [:unit] setup = [BannerChild] begin
    using Test
    for v in ("1", "true")
        r = BannerChild.run_child(BannerChild.LOAD; interactive = true, quiet = v)
        @test r.code == 0
        @test r.out == "loaded true"
        @test !occursin("Conflicts", r.err)
    end
end

@testitem "banner init: silent in a non-interactive run" tags = [:unit] setup = [BannerChild] begin
    using Test
    r = BannerChild.run_child(BannerChild.LOAD; interactive = false)
    @test r.code == 0
    @test r.out == "loaded false"
    @test !occursin("Conflicts", r.err)
end

@testitem "banner init: a failing banner cannot break `using ChuiCore`" tags = [:unit] setup = [BannerChild] begin
    using Test
    # stderr is redirected to a read-only file, so the banner's first write throws. The positive
    # control (`rowrite=threw`) shows that writing to it does throw in this child.
    script = BannerChild.PLANT * """
        ro = open(@__FILE__, "r")
        orig = stderr
        redirect_stderr(ro)
        using ChuiCore
        redirect_stderr(orig)
        w = try
            print(ro, "x"); "ok"
        catch
            "threw"
        end
        print("loaded ", isinteractive(), " rowrite=", w)
        exit()
        """
    path, io = mktemp()
    write(io, script)
    close(io)
    # Warm the package cache first: a precompile inside the child would log to the broken stderr.
    @test BannerChild.run_child("using ChuiCore"; interactive = false).code == 0
    r = BannerChild.run_child("include($(repr(path)))"; interactive = true)
    @test r.code == 0
    @test r.out == "loaded true rowrite=threw"
    # With debug logging on, the failure is logged, and that log write to the same broken stderr
    # must not escape either.
    r = BannerChild.run_child("include($(repr(path)))"; interactive = true, extra = ["JULIA_DEBUG" => "ChuiCore"])
    @test r.code == 0
    @test r.out == "loaded true rowrite=threw"
end

@testitem "banner init: _init_banner swallows a throwing IO" tags = [:unit] begin
    using Test
    struct ChuiBrokenIO <: IO end
    Base.unsafe_write(::ChuiBrokenIO, ::Ptr{UInt8}, ::UInt) = error("broken io")
    Base.write(::ChuiBrokenIO, ::UInt8) = error("broken io")
    Core.eval(Main, Meta.parse("module ChuiBannerInitA; export clash_i; clash_i() = 1; end"))
    Core.eval(Main, Meta.parse("module ChuiBannerInitB; export clash_i; clash_i() = 2; end"))
    A = Main.ChuiBannerInitA
    withenv("CHUI_QUIET_CONFLICTS" => nothing) do
        @test_throws ErrorException ChuiCore.conflict_banner(ChuiBrokenIO(), A)   # control
        @test ChuiCore._init_banner(ChuiBrokenIO(), A) === nothing
        io = IOBuffer()
        @test ChuiCore._init_banner(io, A) === nothing
        @test occursin("clash_i", String(take!(io)))
    end
end
