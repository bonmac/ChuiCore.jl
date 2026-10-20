# The precompile workload covers the TTFX workload (ADR-0009 §3, ADR-0010): in a fresh process
# that loads the package image, the first call of benchmark/ttfx.jl's workload compiles no
# ChuiCore method. Deterministic (it reads `--trace-compile`, not a clock). Tag :slow (it starts
# a Julia process): `julia scripts/ci.jl test -- slow` or `-- all`.

@testitem "precompile workload covers the TTFX workload" tags = [:slow] begin
    include(joinpath(dirname(@__DIR__), "benchmark", "ttfx.jl"))
    script = "using ChuiCore\n" * TTFX.SETUP * TTFX.WORKLOAD
    # The same flags as this process (Pkg.test's --check-bounds, coverage), so the subprocess
    # loads the package image this test run built instead of compiling its own.
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) --trace-compile=stderr -e $script`
    err = IOBuffer()
    run(pipeline(cmd; stdout = devnull, stderr = err))
    compiled = filter(l -> occursin("ChuiCore.", l), split(String(take!(err)), '\n'))
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
