"""
    ChuiCoreSuppositionExt

Law-kit driver over Supposition generators (ADR-0007 §2, §4). Loaded with `using Test, Supposition`.

Every law runs as `@check record=false db=false` and the report is asserted with an explicit
`@test` (ecosystem ADR-0007 §2): on Julia 1.10 a failing `@check` inside a `@testset` is not
recorded. `db=false` keeps Supposition from writing a counterexample database into the caller's
`test/` directory (a database written by a newer Julia cannot be read by 1.10).
"""
module ChuiCoreSuppositionExt

using ChuiCore: ChuiCore
using Supposition: Supposition, @check, Data
using Test: @test, @testset

_gen(g::Data.Possibility) = g
_gen(g) = Data.SampledFrom(collect(g))

# One generator of argument tuples.
_tuplegen(gs::Tuple{Any}) = map(tuple, gs[1])
_tuplegen(gs::Tuple) = map(p -> (p[1], p[2]...), Data.Pairs(gs[1], _tuplegen(Base.tail(gs))))

# The report's pass state, as Supposition's own `results(sr).ispass` computes it (a pass that was
# not expected to be broken; the kits never set `broken`). Reads Supposition internals: pinned by
# `Supposition = "0.3"`, covered by the planted violations.
function _passed(report)
    res = report.result
    res isa Some || return false
    return something(res) isa Supposition.Pass && !report.config.broken
end

function _check(law::ChuiCore.Law, gens::Tuple, max_examples::Int)
    tg = _tuplegen(map(i -> gens[i], law.args))
    pred = law.pred
    report = @check record = false db = false max_examples = max_examples function chui_law(t = tg)
        pred(t...)
    end
    return report
end

function _run(title::String, laws, gens::Tuple, selected, max_examples::Int)
    ChuiCore._check_selected(laws, selected)
    @testset "$title" begin
        for law in laws
            (selected === nothing || law.name in selected) || continue
            @testset "$(law.name)" begin
                @test _passed(_check(law, gens, max_examples))
            end
        end
    end
    return nothing
end

for (kit, table) in ChuiCore._KITS
    @eval function ChuiCore.$kit(
            instance, gen1::Data.Possibility, gens...;
            eq = ChuiCore.default_eq(instance), laws = nothing, max_examples::Integer = 200, kwargs...
        )
        laws_ = ChuiCore.$table(instance, eq; kwargs...)
        title = string($(QuoteNode(kit)), "(", repr(instance), ")")
        return _run(title, laws_, map(_gen, (gen1, gens...)), laws, Int(max_examples))
    end
end

end # module ChuiCoreSuppositionExt
