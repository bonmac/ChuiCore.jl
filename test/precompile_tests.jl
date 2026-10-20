# The precompile workload covers the TTFX workload (ADR-0009 §3, ADR-0010): in a fresh process
# that loads the package image, the first call of benchmark/ttfx.jl's workload compiles no
# ChuiCore method. Deterministic (it reads `--trace-compile`, not a clock). Tag :slow (it starts
# a Julia process): `julia scripts/ci.jl test -- slow` or `-- all`.

@testitem "precompile workload covers the TTFX workload" tags = [:slow] begin
    include(joinpath(dirname(@__DIR__), "benchmark", "ttfx.jl"))
    # The same flags as this process (Pkg.test's --check-bounds, coverage), so the subprocess
    # loads the package image this test run built instead of compiling its own.
    function traced(code)
        script = "using ChuiCore\n" * TTFX.SETUP * code
        cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) --trace-compile=stderr -e $script`
        err = IOBuffer()
        run(pipeline(cmd; stdout = devnull, stderr = err))
        return filter(l -> occursin("ChuiCore.", l), split(String(take!(err)), '\n'))
    end
    compiled = traced(TTFX.WORKLOAD)
    # Positive control: a call the workload does not cover must show up, so an empty `compiled`
    # cannot come from a change in the trace format or a filter that never matches.
    control = traced("C.foldxl(+, C.Scan(+, 0), vi; init = 0)\n")
    @test !isempty(control)
    if Base.JLOptions().code_coverage != 0
        # Coverage instruments codegen and is part of the cache flags (UNVERIFIED that the
        # package image's native code is used under it), so the check runs without coverage only.
        @info "coverage is on: the trace-compile check is skipped" length(compiled)
        @test_skip isempty(compiled)
    else
        isempty(compiled) || @info "compiled on first call" compiled
        @test isempty(compiled)
    end
end
