@testitem "module loads" tags = [:unit] begin
    @test ChuiCore isa Module
    @test nameof(ChuiCore) === :ChuiCore
    @test !isempty(string(@doc ChuiCore))
end

@testitem "CC-011 loading ChuiCore loads neither Test nor Supposition" tags = [:unit] begin
    using TOML
    proj = TOML.parsefile(joinpath(pkgdir(ChuiCore), "Project.toml"))
    deps = keys(get(proj, "deps", Dict()))
    @test !("Test" in deps) && !("Supposition" in deps)
    @test "Test" in keys(proj["weakdeps"]) && "Supposition" in keys(proj["weakdeps"])
    code = """
    using ChuiCore
    loaded = [nameof(m) for m in values(Base.loaded_modules)]
    print(any(in((:Test, :Supposition)), loaded), " ", length(methods(ChuiCore.test_monoid_laws)))
    """
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -e $code`
    @test readchomp(cmd) == "false 0"
end

@testitem "CC-010 no export collides with Base, Core or a standard library" tags = [:unit] begin
    using Statistics, LinearAlgebra, Dates, Random, Test
    others = (Base, Core, Base.Iterators, Statistics, LinearAlgebra, Dates, Random, Test)
    # `names` also lists `public` names on Julia ≥ 1.11; CC-010 is about exports.
    exported = filter(n -> Base.isexported(ChuiCore, n), names(ChuiCore))
    collisions = [
        n for n in exported if n !== :ChuiCore && any(
                O -> Base.isexported(O, n) && isdefined(O, n) && getfield(O, n) !== getfield(ChuiCore, n),
                others,
            )
    ]
    @test collisions == Symbol[]
    # No single-letter export (`⨟` is one character but an operator, not a letter).
    single_letter(n) = (s = string(n); length(s) == 1 && isletter(only(s)))
    @test !any(single_letter, exported)
end

@testitem "every exported and public name is defined" tags = [:unit] begin
    @test filter(n -> !isdefined(ChuiCore, n), names(ChuiCore)) == Symbol[]
end
