# Doctests and their coverage (ecosystem ADR-0008 §3).
# - :doctest runs every jldoctest in the docstrings and in docs/src (tutorials included). Printed
#   types and errors differ between Julia versions, so runtests.jl skips :doctest when
#   CI_STABLE=false (the lts and pre CI jobs); `julia scripts/ci.jl docs` runs them too.
# - :quality checks that every exported and public name owned by ChuiCore has a jldoctest (or a
#   row in docs/doctest-exemptions.md) and states its runtime cost (the brief: "give every
#   abstraction a documented runtime cost").

@testitem "doctests: docstrings and docs/src (ADR-0008 §3)" tags = [:doctest] begin
    using Documenter
    DocMeta.setdocmeta!(ChuiCore, :DocTestSetup, :(using ChuiCore); recursive = true)
    doctest(ChuiCore; manual = true)
end

@testitem "ADR-0008 every exported and public name has a doctest and a cost" tags = [:quality] begin
    M = ChuiCore
    texts = Dict{Symbol, String}()
    for (b, md) in Docs.meta(M)
        b.mod === M || continue
        texts[b.var] = join((join(string.(d.text)) for d in values(md.docs)), "\n")
    end
    exempt = Set{Symbol}()
    for line in eachline(joinpath(pkgdir(M), "docs", "doctest-exemptions.md"))
        m = match(r"^\|\s*`(?:ChuiCore\.)?([^`]+)`", line)
        m === nothing || push!(exempt, Symbol(m[1]))
    end
    # `⨟` and `opcompose` are CompositionsBase's bindings (ADR-0006): their docstrings live there.
    owned = [n for n in names(M) if n !== :ChuiCore && Docs.Binding(M, n).mod === M]
    @test issubset(exempt, Set(owned))
    no_doctest = sort!([n for n in owned if !(n in exempt) && !occursin("jldoctest", get(texts, n, ""))])
    @test no_doctest == Symbol[]
    no_cost = sort!([n for n in owned if !occursin(r"\bcost"i, get(texts, n, ""))])
    @test no_cost == Symbol[]
end
