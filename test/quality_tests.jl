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
        @test check_all_qualified_accesses_are_public(ChuiCore) === nothing
    end
end
