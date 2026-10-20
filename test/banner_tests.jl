# The name-conflict banner (request R9): `binding_conflicts` and `conflict_banner`.
# Test modules are defined in `Main` (unique names, from source strings) because the banner looks
# for other modules reachable from `Main`; a test item's own module is not.

@testitem "banner: R9 reproducer (A and B both export f)" tags = [:unit] begin
    using Test
    Core.eval(Main, Meta.parse("module ChuiBannerR9A; export f; f() = 1; end"))
    Core.eval(Main, Meta.parse("module ChuiBannerR9B; export f; f() = 2; end"))
    A = Main.ChuiBannerR9A
    B = Main.ChuiBannerR9B
    r = ChuiCore.binding_conflicts(A)
    @test r isa Vector{Pair{Symbol, Vector{Module}}}
    @test any(p -> p.first === :f && B in p.second, r)
    @test !any(p -> A in p.second, r)          # never lists the module itself
    io = IOBuffer()
    withenv("CHUI_QUIET_CONFLICTS" => nothing) do
        ChuiCore.conflict_banner(io, A)
    end
    s = String(take!(io))
    @test occursin("f", s)
    @test occursin("ChuiBannerR9B", s)
end

@testitem "banner: a re-export of the same binding is not a conflict" tags = [:unit] begin
    using Test
    Core.eval(Main, Meta.parse("module ChuiBannerReA; export g; g() = 1; end"))
    Core.eval(Main, Meta.parse("module ChuiBannerReB; using ..ChuiBannerReA: g; export g; end"))
    # Same value, different owners, both const: Julia resolves these without ambiguity too.
    Core.eval(Main, Meta.parse("module ChuiBannerReC; const g = Main.ChuiBannerReA.g; export g; end"))
    A = Main.ChuiBannerReA
    @test ChuiCore.binding_conflicts(A) == Pair{Symbol, Vector{Module}}[]
    @test ChuiCore.binding_conflicts(Main.ChuiBannerReB) == Pair{Symbol, Vector{Module}}[]
    io = IOBuffer()
    withenv("CHUI_QUIET_CONFLICTS" => nothing) do
        @test ChuiCore.conflict_banner(io, A) == Pair{Symbol, Vector{Module}}[]
    end
    @test isempty(take!(io))                   # prints nothing when there are no conflicts
end

@testitem "banner: adding methods to Base.f and exporting f is not a conflict" tags = [:unit] begin
    using Test
    Core.eval(Main, Meta.parse("module ChuiBannerExt; export sum; Base.sum(::Val{:chui}) = 1; end"))
    Core.eval(Main, Meta.parse("module ChuiBannerExt2; import Base: sum; export sum; sum(::Val{:chui2}) = 2; end"))
    @test ChuiCore.binding_conflicts(Main.ChuiBannerExt) == Pair{Symbol, Vector{Module}}[]
    @test ChuiCore.binding_conflicts(Main.ChuiBannerExt2) == Pair{Symbol, Vector{Module}}[]
end

@testitem "banner: an own map clashes with Base's export" tags = [:unit] begin
    using Test
    Core.eval(Main, Meta.parse("module ChuiBannerMap; export map, zzz_only_here; map(x) = x; zzz_only_here() = 0; end"))
    M = Main.ChuiBannerMap
    r = ChuiCore.binding_conflicts(M)
    @test [p.first for p in r] == [:map]
    @test Base in only(r).second
    @test issorted(only(r).second; by = fullname)
end

@testitem "banner: exported but undefined names, sorting, own module name" tags = [:unit] begin
    using Test
    Core.eval(Main, Meta.parse("module ChuiBannerSortA; export zeta, alpha, undefd_chui; zeta() = 1; alpha() = 1; end"))
    Core.eval(Main, Meta.parse("module ChuiBannerSortB; export zeta, alpha, undefd_chui; zeta() = 2; alpha() = 2; end"))
    Core.eval(Main, Meta.parse("module ChuiBannerSortC; export alpha; alpha() = 3; end"))
    A = Main.ChuiBannerSortA
    r = ChuiCore.binding_conflicts(A)
    ns = [p.first for p in r]
    @test issorted(ns)
    @test :alpha in ns && :zeta in ns
    @test !(:ChuiBannerSortA in ns)
    alpha = r[findfirst(p -> p.first === :alpha, r)].second
    @test alpha == [Main.ChuiBannerSortB, Main.ChuiBannerSortC]
    # Exported, never defined in either module: two owners, so reported, without throwing.
    @test :undefd_chui in ns
end

@testitem "banner: CHUI_QUIET_CONFLICTS silences it" tags = [:unit] begin
    using Test
    Core.eval(Main, Meta.parse("module ChuiBannerQA; export q; q() = 1; end"))
    Core.eval(Main, Meta.parse("module ChuiBannerQB; export q; q() = 2; end"))
    A = Main.ChuiBannerQA
    for v in ("1", "true", "TRUE", "True")
        io = IOBuffer()
        r = withenv(() -> ChuiCore.conflict_banner(io, A), "CHUI_QUIET_CONFLICTS" => v)
        @test r === nothing
        @test isempty(take!(io))
    end
    for v in ("0", "false", "")
        io = IOBuffer()
        r = withenv(() -> ChuiCore.conflict_banner(io, A), "CHUI_QUIET_CONFLICTS" => v)
        @test r isa Vector && !isempty(r)
        @test occursin("q", String(take!(io)))
    end
end
