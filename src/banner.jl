# The name-conflict banner (request R9; ADR-0005 §1 places it here). Compares bindings, never
# Julia's own "both … export" warning, which 1.13 does not print. Behaviour verified on 1.10.12
# and 1.13.2: `which(m, n)` gives the binding's owner (a re-export resolves to the original owner;
# `Base.sum` extended by a method stays owned by Base); an exported but undefined name is owned by
# the exporting module.

"""
    binding_conflicts(mod::Module) -> Vector{Pair{Symbol,Vector{Module}}}

For each name that `mod` exports (other than its own module name), the other modules that export
a **different binding** of that name: `using` both makes the name ambiguous, so users must
qualify it (`Mod.f`). Sorted by name; each module list sorted by `fullname`. Empty when there is
no conflict.

Not a conflict: a re-export of the same binding (`using ..A: f; export f`), a module that adds
methods to `Base.f` and exports `f` (it is still Base's binding), and two `const` bindings with
the identical (`===`) value, which Julia also resolves without ambiguity. An own `map` exported
next to Base's is a conflict with `Base`.

"Other modules" are `Base`, `Core`, every module in `Base.loaded_modules` (top-level packages),
and every module reachable from `Main` through its submodules (e.g. `module A … end` typed at the
REPL), except `mod` itself. Only modules loaded **before** the call are seen.

Cost: one pass over the other modules per exported name (`Base.isexported` checks), plus one
walk of `Main`'s submodules, so O(exports × loaded modules): about 36 μs and 18 KB for ChuiCore's
35 exported names (36 with the module name) against 32 loaded modules on Julia 1.13.2, about 46 μs
and 71 KB against 56 on 1.10.12 (BenchmarkTools medians, Apple silicon, loaded machine,
2026-10-20; indicative, after compilation; `docs/src/tutorials/conflict-banner.md` cites the
evidence). No budget is set for it. Meant for package load, not
for loops.

**Effects:** reads global state (the loaded modules and `Main`'s submodules), so the result
depends on what was loaded before the call; it changes nothing.

```jldoctest
julia> module DocA; export f, only_a; f() = 1; only_a() = 0; end;

julia> module DocB; export f; f() = 2; end;

julia> module DocC; export sum; Base.sum(::Val{:doc}) = 1; end;   # a method on Base.sum

julia> r = Dict(ChuiCore.binding_conflicts(DocA));   # name => the other modules

julia> DocB in r[:f]                        # `f` clashes with DocB's `f`
true

julia> DocB in get(r, :only_a, Module[])    # `only_a` does not
false

julia> ChuiCore.binding_conflicts(DocC)   # still Base's binding: not a conflict
Pair{Symbol, Vector{Module}}[]
```
"""
function binding_conflicts(mod::Module)
    others = _other_modules(mod)
    out = Pair{Symbol, Vector{Module}}[]
    own = nameof(mod)
    for n in sort!(filter(n -> n !== own && Base.isexported(mod, n), names(mod)))
        ms = Module[m for m in others if Base.isexported(m, n) && _different_binding(mod, m, n)]
        isempty(ms) || push!(out, n => sort!(ms; by = fullname))
    end
    return out
end

_owner(m::Module, n::Symbol) = isdefined(m, n) ? which(m, n) : m

function _different_binding(a::Module, b::Module, n::Symbol)
    _owner(a, n) === _owner(b, n) && return false
    # Julia treats two const bindings with the same value as the same import.
    if isdefined(a, n) && isdefined(b, n) && isconst(a, n) && isconst(b, n)
        getglobal(a, n) === getglobal(b, n) && return false
    end
    return true
end

function _other_modules(mod::Module)
    seen = Set{Module}()
    push!(seen, Base, Core)
    for m in values(Base.loaded_modules)
        push!(seen, m)
    end
    _submodules!(seen, Main)
    delete!(seen, mod)
    return collect(seen)
end

# Main and its submodules (a module whose parent is the module that binds it), with a visited set.
function _submodules!(seen::Set{Module}, m::Module)
    push!(seen, m)
    for n in names(m; all = true)
        (isdefined(m, n) && isconst(m, n)) || continue
        v = getglobal(m, n)
        v isa Module && v !== m && parentmodule(v) === m && !(v in seen) && _submodules!(seen, v)
    end
    return seen
end

"""
    conflict_banner(io::IO, mod::Module) -> Union{Vector{Pair{Symbol,Vector{Module}}}, Nothing}

Print a short, dplyr-style notice of [`ChuiCore.binding_conflicts`](@ref)`(mod)` to `io`: each
conflicting name with the other modules that export it, and the advice to qualify (`Mod.f`).
Prints nothing when there are no conflicts. Returns the conflicts vector.

Silenced when the environment variable `CHUI_QUIET_CONFLICTS` is `"1"` or `"true"` (any case):
it then prints nothing, does not compute the conflicts, and returns `nothing`.

Intended use, in a package's module (ChuiCore's own `__init__` does the same for its exports):

```julia
function __init__()
    isinteractive() || return nothing
    try   # a failing banner must not break `using MyPackage`
        Base.invokelatest(ChuiCore.conflict_banner, stderr, @__MODULE__)   # keeps it out of the image
    catch
    end
    return nothing
end
```

`__init__` runs once, so the banner covers only modules loaded **before** the call; a package
loaded afterwards is not reported (call `ChuiCore.conflict_banner(stdout, Mod)` again to check).

Cost: that of `binding_conflicts` plus printing; one environment-variable read when silenced.

**Effects:** reads the environment variable `CHUI_QUIET_CONFLICTS` and the set of loaded modules
(as `binding_conflicts`), and prints to `io` when there are conflicts.

```jldoctest
julia> module DocQ; export q; q() = 1; end;

julia> module DocR; export q; q() = 2; end;

julia> io = IOBuffer();

julia> r = withenv("CHUI_QUIET_CONFLICTS" => nothing) do
           ChuiCore.conflict_banner(io, DocQ)
       end;

julia> [p.first for p in r]
1-element Vector{Symbol}:
 :q

julia> occursin("✖ q  also exported by", String(take!(io)))
true

julia> withenv("CHUI_QUIET_CONFLICTS" => "1") do
           ChuiCore.conflict_banner(io, DocQ)
       end === nothing
true
```
"""
function conflict_banner(io::IO, mod::Module)
    lowercase(strip(get(ENV, "CHUI_QUIET_CONFLICTS", ""))) in ("1", "true") && return nothing
    conflicts = binding_conflicts(mod)
    isempty(conflicts) && return conflicts
    width = maximum(p -> textwidth(string(p.first)), conflicts)
    println(io, "── Conflicts with ", mod, " ", "─"^max(4, 40 - textwidth(string(mod))))
    for (n, ms) in conflicts
        println(io, "✖ ", rpad(string(n), width), "  also exported by ", join(string.(ms), ", "))
    end
    n, ms = first(conflicts)
    println(io, "ℹ Where both are `using`ed, these names are ambiguous: qualify them, e.g. `", mod, ".", n, "` or `", first(ms), ".", n, "`.")
    println(io, "  Silence this notice with ENV[\"CHUI_QUIET_CONFLICTS\"] = \"1\".")
    return conflicts
end

# ChuiCore's own banner, from `__init__` (in ChuiCore.jl) in interactive sessions only. A banner
# failure must never break `using ChuiCore`: it is caught and logged at debug level
# (`JULIA_DEBUG=ChuiCore` shows it). The log write is guarded too: when the banner failed because
# stderr is broken, the logger writes to that same stderr and would throw again.
function _init_banner(io::IO, mod::Module)
    try
        conflict_banner(io, mod)
    catch err
        try
            @debug "ChuiCore: the name-conflict banner failed" exception = (err, catch_backtrace())
        catch
        end
    end
    return nothing
end
