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

Cost: one pass over the other modules per exported name (`Base.isexported` checks), so
O(exports × loaded modules), well under a millisecond for typical sessions after compilation
(phase 4 records the measured budget). Meant for package load, not for loops.
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

Intended use, in a package's module:

```julia
__init__() = isinteractive() && ChuiCore.conflict_banner(stderr, @__MODULE__)
```

`__init__` runs once, so the banner covers only modules loaded **before** the call; a package
loaded afterwards is not reported (call `ChuiCore.conflict_banner(stdout, Mod)` again to check).

Cost: that of `binding_conflicts` plus printing.
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
