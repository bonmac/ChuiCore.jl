# ADR-0005 §2: a name may be exported by ChuiCore only if no module on the clash list exports a
# different binding of it. Run by the `:quality` item "ADR-0005 clash list" in a scratch copy of
# this environment; prints one line per clash and exits 1 if there is any.
using ChuiCore
using Accessors, CompositionsBase, ConstructionBase, DataFrames, Functors, Setfield, Transducers, TypeClasses
using Dates, LinearAlgebra, Random, Statistics, Test

const CLASH_LIST = (
    Base, Core, Base.Iterators, Dates, LinearAlgebra, Random, Statistics, Test,
    Accessors, CompositionsBase, ConstructionBase, DataFrames, Functors, Setfield, Transducers,
    TypeClasses,
)

exported = filter(n -> n !== :ChuiCore && Base.isexported(ChuiCore, n), names(ChuiCore))
clashes = Pair{Symbol, Module}[]
for n in exported, M in CLASH_LIST
    if Base.isexported(M, n) && isdefined(M, n) && getfield(M, n) !== getfield(ChuiCore, n)
        push!(clashes, n => M)
    end
end

# ADR-0006 Decision 5: a bare `⨟` resolves next to the packages that re-export CompositionsBase's.
for pkgs in (:(using ChuiCore, CompositionsBase), :(using ChuiCore, Accessors), :(using ChuiCore, Transducers))
    m = Module(:BareResolve)
    Core.eval(m, pkgs)
    ok = try
        Core.eval(m, :(⨟)) === ChuiCore.:⨟
    catch
        false
    end
    ok || push!(clashes, :⨟ => m)
    println("bare ⨟ after `", pkgs, "`: ", ok ? "resolves" : "FAILS")
end

println("checked ", length(exported), " exported names against ", length(CLASH_LIST), " modules")
for (n, M) in clashes
    println("CLASH: ", n, " (", M, ")")
end
exit(isempty(clashes) ? 0 : 1)
