# Quality gates (ADR-0007 §3). Tag :quality: run by `julia scripts/ci.jl quality`.
# JET is not here: it has its own environment in test/jet/ (stable Julia only).

@testitem "Aqua" tags = [:quality] begin
    using Aqua
    Aqua.test_all(ChuiCore)
end

@testitem "ExplicitImports" tags = [:quality] begin
    using ExplicitImports
    @test check_no_implicit_imports(ChuiCore) === nothing
    @test check_no_stale_explicit_imports(ChuiCore) === nothing
    @test check_all_explicit_imports_via_owners(ChuiCore) === nothing
    @test check_all_qualified_accesses_via_owners(ChuiCore) === nothing
    # `public` exists from Julia 1.11; on 1.10 these checks misreport (ADR-0006, E-26).
    if VERSION >= v"1.11"
        @test check_all_explicit_imports_are_public(ChuiCore) === nothing
        # The law-kit drivers in ext/ are ChuiCore's own code and read its internal kit table.
        @test check_all_qualified_accesses_are_public(ChuiCore; ignore = (:_KITS,)) === nothing
    end
end

@testitem "ADR-0005 every exported and public name is documented" tags = [:quality] begin
    # `Docs.undocumented_names` is missing on 1.10 (law-kits-modules-names.md L-2 addendum).
    if isdefined(Base.Docs, :undocumented_names)
        @test Base.Docs.undocumented_names(ChuiCore) == Symbol[]
    else
        @info "Docs.undocumented_names is not available on Julia $VERSION: check skipped"
    end
end

@testitem "ADR-0005 three name tiers" tags = [:quality] begin
    exported = Set(filter(n -> Base.isexported(ChuiCore, n), names(ChuiCore)))
    # The aggregation protocol and the aggregators stay public, never exported (ADR-0005 §3,
    # ecosystem ADR-0009: `partial` is not exported).
    for n in (:init, :partial, :combine, :final, :iscommutative, :Sum, :Count, :Mean, :neutral)
        @test !(n in exported)
        VERSION >= v"1.11" && @test Base.ispublic(ChuiCore, n)
    end
    @test :papply in exported && :⨟ in exported && :opcompose in exported
    @test all(n -> startswith(string(n), "test_") || !occursin("_laws", string(n)), exported)
end

@testitem "ADR-0005 clash list" tags = [:quality] begin
    # Own environment (test/exports/), like JET's; stable Julia only (ADR-0005 §2).
    if VERSION < v"1.11"
        @info "clash-list check runs on stable Julia only: skipped on $VERSION"
    else
        # Two environments (see test/exports/check.jl): TypeClasses cannot be installed next to
        # ChuiCore, so step 1 records ChuiCore's exports and step 2 checks them without ChuiCore.
        src = joinpath(pkgdir(ChuiCore), "test", "exports")
        # Pkg.test's sandbox sets JULIA_LOAD_PATH to the test environment; the child processes
        # need the default load path (Pkg, their own --project) instead.
        julia = addenv(Base.julia_cmd(), "JULIA_LOAD_PATH" => "@:@stdlib", "JULIA_PROJECT" => nothing)
        function scratch_env(project_dir, develop)
            env = mktempdir()
            cp(joinpath(project_dir, "Project.toml"), joinpath(env, "Project.toml"))
            dev = develop ? "Pkg.develop(path = $(repr(pkgdir(ChuiCore))); io = devnull);" : ""
            run(`$julia --startup-file=no --project=$env -e "using Pkg; $dev Pkg.instantiate(; io = devnull)"`)
            return env
        end
        function step(env, mode, file)
            out = IOBuffer()
            cmd = `$julia --startup-file=no --project=$env $(joinpath(src, "check.jl")) $mode $file`
            proc = run(pipeline(ignorestatus(cmd); stdout = out))
            report = String(take!(out))
            print(report)
            return proc.exitcode, report
        end
        file = joinpath(mktempdir(), "exports.toml")
        code1, _ = step(scratch_env(joinpath(src, "chuicore"), true), "names", file)
        @test code1 == 0
        code2, report = step(scratch_env(src, false), "clashes", file)
        @test code2 == 0
        @test occursin(" 0 clashes", report)
    end
end
