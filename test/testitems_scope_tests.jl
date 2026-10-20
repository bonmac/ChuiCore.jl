# The root `JuliaTestItems.toml` keeps TestItemRunner out of `.lanes/` and `.worktrees/` (phase-3
# review S3): a malformed file there must not abort the run, and a `@testmodule` there must not
# shadow ours. Proved on a toy package that carries ChuiCore's own config file, run in a child
# process; the control run without the config must fail, so the check cannot pass vacuously.

@testitem "JuliaTestItems.toml excludes .lanes/ and .worktrees/ (review S3)" tags = [:unit] begin
    using Test
    config = joinpath(pkgdir(ChuiCore), "JuliaTestItems.toml")
    @test isfile(config)

    function toy(withconfig::Bool)
        dir = mktempdir()
        mkpath(joinpath(dir, "src"))
        mkpath(joinpath(dir, "test"))
        write(joinpath(dir, "Project.toml"), "name = \"ScopeToy\"\nuuid = \"5c0b7c4e-3f0e-4a57-9a7e-2d0c1b6a9e11\"\n")
        write(joinpath(dir, "src", "ScopeToy.jl"), "module ScopeToy end\n")
        write(joinpath(dir, "test", "runtests.jl"), "using TestItemRunner\n@run_package_tests\n")
        write(
            joinpath(dir, "test", "fx.jl"),
            "@testmodule ToyFx begin\n    const X = 1\nend\n" *
                "@testitem \"uses the real fixture\" setup = [ToyFx] begin\n    using Test\n    @test ToyFx.X == 1\nend\n",
        )
        # Planted under both excluded directories: a shadowing fixture and a malformed file.
        for sub in (".lanes/scratch/stale/test", ".worktrees/old/test")
            mkpath(joinpath(dir, sub))
            write(joinpath(dir, sub, "fx.jl"), "@testmodule ToyFx begin\n    const X = 2\nend\n")
            write(joinpath(dir, sub, "broken.jl"), "function oops(\n")
        end
        withconfig && cp(config, joinpath(dir, "JuliaTestItems.toml"))
        return dir
    end

    # The child loads TestItemRunner and Test from this test environment's load path.
    sep = Sys.iswindows() ? ";" : ":"
    loadpath = join(["@"; Base.load_path()], sep)
    function run_toy(dir)
        cmd = addenv(
            `$(Base.julia_cmd()) --startup-file=no --project=$dir $(joinpath(dir, "test", "runtests.jl"))`,
            "JULIA_LOAD_PATH" => loadpath, "JULIA_PROJECT" => nothing,
        )
        out = IOBuffer()
        proc = run(pipeline(ignorestatus(cmd); stdout = out, stderr = out))
        return proc.exitcode, String(take!(out))
    end

    code, out = run_toy(toy(true))
    code == 0 || print(out)
    @test code == 0
    # Control: without the config, the planted files break the same run.
    code0, _ = run_toy(toy(false))
    @test code0 != 0
end
