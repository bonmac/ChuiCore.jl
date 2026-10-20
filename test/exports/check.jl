# ADR-0005 §2: a name may be exported by ChuiCore only if no module on the clash list exports a
# different binding of it. Run by the `:quality` item "ADR-0005 clash list", in two steps,
# because TypeClasses 1.x needs Compat ≤ 3 and cannot be installed next to ChuiCore:
#
#   julia --project=<copy of test/exports/chuicore> check.jl names  <out.toml>
#       (ChuiCore developed in) writes each exported name and the module that owns its binding,
#       and checks that a bare `⨟` resolves next to CompositionsBase, Accessors and Transducers
#       (ADR-0006 Decision 5);
#   julia --project=<copy of test/exports> check.jl clashes <out.toml>
#       (the clash-list packages, without ChuiCore) reports every listed module that exports one
#       of those names as a binding owned by a different module.
# Each step prints its findings and exits 1 on a problem.
using TOML

const mode, file = ARGS
# Load at top level (not with `@eval` inside a function): on Julia ≥ 1.12 a binding created by a
# later `using` is not visible to an already running function (world age).
if mode == "names"
    using ChuiCore, Accessors, CompositionsBase, Transducers
else
    using Accessors, CompositionsBase, ConstructionBase, DataFrames, Functors, Setfield
    using Transducers, TypeClasses, Dates, LinearAlgebra, Random, Statistics, Test
end

"The full name of the module that owns the binding `M.n` (e.g. `CompositionsBase` for `⨟`)."
owner(M::Module, n::Symbol) = join(fullname(Base.binding_module(M, n)), ".")

function names_step(out)
    CC = getfield(Main, :ChuiCore)
    exported = filter(n -> n !== :ChuiCore && Base.isexported(CC, n), names(CC))
    open(out, "w") do io
        TOML.print(io, Dict(string(n) => owner(CC, n) for n in exported))
    end
    ok = true
    for pkgs in (:(using ChuiCore, CompositionsBase), :(using ChuiCore, Accessors), :(using ChuiCore, Transducers))
        m = Module(:BareResolve)
        Core.eval(m, pkgs)
        resolves = try
            Core.eval(m, :(⨟)) === CC.:⨟
        catch
            false
        end
        println("bare ⨟ after `", pkgs, "`: ", resolves ? "resolves" : "FAILS")
        ok &= resolves
    end
    println("recorded ", length(exported), " exported names")
    return ok
end

function clashes_step(file)
    mods = [Base, Core, Base.Iterators]
    for s in (
            :Dates, :LinearAlgebra, :Random, :Statistics, :Test, :Accessors, :CompositionsBase,
            :ConstructionBase, :DataFrames, :Functors, :Setfield, :Transducers, :TypeClasses,
        )
        push!(mods, getfield(Main, s))
    end
    recorded = TOML.parsefile(file)
    found = 0
    for (name, own) in recorded, M in mods
        n = Symbol(name)
        if Base.isexported(M, n) && isdefined(M, n) && owner(M, n) != own
            println("CLASH: ", n, " is exported by ", M, " as ", owner(M, n), ", by ChuiCore as ", own)
            found += 1
        end
    end
    println("checked ", length(recorded), " names against ", length(mods), " modules: ", found, " clashes")
    return found == 0
end

exit((mode == "names" ? names_step(file) : clashes_step(file)) ? 0 : 1)
