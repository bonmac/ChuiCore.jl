"""
    ChuiCoreTestExt

Law-kit driver over finite sample collections (ADR-0007 §2). Loaded with `using Test`.
"""
module ChuiCoreTestExt

using ChuiCore: ChuiCore
using Test: @test, @testset

# At most 12 samples per argument and at most 1,728 combinations per law (ADR-0007 §2).
_per_arg(k::Int) = min(12, max(1, floor(Int, 1728^(1 / k) + 1.0e-9)))

_take(gen, n) = collect(Iterators.take(gen, n))

"First argument tuple for which `law` fails, or `nothing`."
function _first_counterexample(law::ChuiCore.Law, gens::Tuple)
    n = _per_arg(length(law.args))
    pools = map(i -> _take(gens[i], n), law.args)
    for xs in Iterators.product(pools...)
        law.pred(xs...) || return xs
    end
    return nothing
end

function _run(title::String, laws, gens::Tuple, selected)
    ChuiCore._check_selected(laws, selected)
    @testset "$title" begin
        for law in laws
            (selected === nothing || law.name in selected) || continue
            @testset "$(law.name)" begin
                counterexample = _first_counterexample(law, gens)
                @test counterexample === nothing
            end
        end
    end
    return nothing
end

for (kit, table) in ChuiCore._KITS
    @eval function ChuiCore.$kit(
            instance, gens...;
            eq = ChuiCore.default_eq(instance), laws = nothing, max_examples::Integer = 200, kwargs...
        )
        laws_ = ChuiCore.$table(instance, eq; kwargs...)
        return _run(string($(QuoteNode(kit)), "(", repr(instance), ")"), laws_, gens, laws)
    end
end

end # module ChuiCoreTestExt
