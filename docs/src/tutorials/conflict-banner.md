# The conflict banner

```@meta
DocTestSetup = :(using ChuiCore)
```

When two packages you `using` both export a name and mean different things by it, Julia makes the
bare name ambiguous: you get an error (or, on older versions, a warning) only when you use it.
The banner tells you up front, at load time, like dplyr's "The following objects are masked"
notice. ChuiCore prints it for its own exports when you load it in an interactive session, and
other Chui packages do the same from their `__init__`.

Two public functions do the work: `ChuiCore.binding_conflicts(mod)` computes the conflicts and
`ChuiCore.conflict_banner(io, mod)` prints them.

## What counts as a conflict

A conflict is a name that `mod` exports while another loaded module exports a **different
binding** of the same name. The examples below define small modules on the spot (at the REPL
they would live in `Main`), so the output does not depend on what else is loaded.

```jldoctest banner
julia> module Stats; export summarise, mean_of; summarise(x) = sum(x); mean_of(x) = sum(x) / length(x); end;

julia> module Reports; export summarise; summarise(x) = "report on $(length(x)) values"; end;

julia> ChuiCore.binding_conflicts(Stats)
1-element Vector{Pair{Symbol, Vector{Module}}}:
 :summarise => [Reports]
```

(Typed at the REPL, the modules live in `Main` and print as `Main.Reports`.)

`mean_of` is exported by `Stats` alone, so it is not listed. Not conflicts either:

- **Adding methods to a Base function** and exporting its name. The binding is still Base's, so
  there is nothing to disambiguate; this is how packages extend `show`, `length` or `sum`.
- **Re-exporting** another module's binding (`using ..A: f; export f`), as ChuiCore does with
  CompositionsBase's `⨟`.

```jldoctest banner
julia> module Extends; export sum; Base.sum(::Val{:banner_demo}) = 0; end;

julia> ChuiCore.binding_conflicts(Extends)
Pair{Symbol, Vector{Module}}[]

julia> module Reexports; using ..Stats: summarise; export summarise; end;

julia> [p.first for p in ChuiCore.binding_conflicts(Reexports)]   # same binding as Stats'
1-element Vector{Symbol}:
 :summarise
```

`Reexports` passes on `Stats.summarise`, which is the same binding, so `Stats` is not listed
against it; it still clashes with `Reports`, whose `summarise` is a different function:

```jldoctest banner
julia> only(ChuiCore.binding_conflicts(Reexports)).second
1-element Vector{Module}:
 Reports
```

Defining a function of your own with a Base name, instead of adding a method to Base's, *is* a
conflict, with `Base`:

```jldoctest banner
julia> module OwnMap; export map; map(f, x) = "my map"; end;

julia> r = ChuiCore.binding_conflicts(OwnMap);

julia> [p.first for p in r], Base in only(r).second
([:map], true)
```

The modules searched are `Base`, `Core`, every loaded top-level package and every module reachable
from `Main`. Only modules loaded **before** the call are seen.

## The printed banner

`conflict_banner(io, mod)` prints each conflicting name with the modules that also export it, and
how to disambiguate. It prints nothing when there is no conflict, and returns the conflicts.

```jldoctest banner; filter = r" ─+$"m => " ──"
julia> withenv("CHUI_QUIET_CONFLICTS" => nothing) do
           ChuiCore.conflict_banner(stdout, Stats)
       end;
── Conflicts with Stats ──────────────────────────────
✖ summarise  also exported by Reports
ℹ Where both are `using`ed, these names are ambiguous: qualify them, e.g. `Stats.summarise` or `Reports.summarise`.
  Silence this notice with ENV["CHUI_QUIET_CONFLICTS"] = "1".

julia> module Clean; export clean_only_here; clean_only_here() = 1; end;

julia> withenv(() -> ChuiCore.conflict_banner(stdout, Clean), "CHUI_QUIET_CONFLICTS" => nothing)
Pair{Symbol, Vector{Module}}[]
```

(`withenv` only makes the example independent of your own setting of the variable.)

## ChuiCore's own banner

`using ChuiCore` in an interactive session (the REPL, or `julia -i`) runs the banner for
ChuiCore's own exports and prints it to `stderr`. With a module of yours that exports `chain` and
`papply` loaded first:

```julia
julia> module MyTools; export chain, papply; chain() = 1; papply() = 2; end;

julia> using ChuiCore
── Conflicts with ChuiCore ────────────────────────────────
✖ chain   also exported by Main.MyTools
✖ papply  also exported by Main.MyTools
ℹ Where both are `using`ed, these names are ambiguous: qualify them, e.g. `ChuiCore.chain` or `Main.MyTools.chain`.
  Silence this notice with ENV["CHUI_QUIET_CONFLICTS"] = "1".
```

It runs whenever ChuiCore is *loaded* in an interactive session: `__init__` cannot tell `using`
from `import`, so it also prints on `import ChuiCore`, and when ChuiCore loads as a dependency of
another package (`using ChuiTypes`). In those cases ChuiCore's exports are not brought into
`Main`, so the listed names are not actually ambiguous there; set `CHUI_QUIET_CONFLICTS` if
that notice is noise for you. Scripts, tests and CI (non-interactive runs) never see it, and
neither does a session with `CHUI_QUIET_CONFLICTS` set (below). It cannot break the load: if printing the banner fails (a
closed or read-only `stderr`, say), `using ChuiCore` still succeeds, and the error is logged at
debug level (`JULIA_DEBUG=ChuiCore` shows it).

## Calling it from a package

A downstream package (ChuiTypes, ChuiFrames, or your own) calls it from its `__init__`, the way
ChuiCore does: only in interactive sessions, so that scripts, tests and CI logs stay quiet, and
inside a `try`, so that a failing banner cannot break `using MyPackage`:

```julia
module MyPackage

using ChuiCore

export summarise

function __init__()
    isinteractive() || return nothing
    try
        # `invokelatest` keeps the banner's code out of the package image (see the costs below).
        Base.invokelatest(ChuiCore.conflict_banner, stderr, @__MODULE__)
    catch
    end
    return nothing
end

end
```

`__init__` runs once, when the package loads, so the banner covers only the modules loaded before
it. A package loaded afterwards is not reported; call
`ChuiCore.conflict_banner(stdout, MyPackage)` again to check the current session.

## Silencing it

Set the environment variable `CHUI_QUIET_CONFLICTS` to `"1"` or `"true"` (any case), for example
in `~/.julia/config/startup.jl` or your shell profile. The banner then prints nothing, does not
compute the conflicts, and returns `nothing`:

```jldoctest banner
julia> withenv("CHUI_QUIET_CONFLICTS" => "true") do
           ChuiCore.conflict_banner(stdout, Stats)
       end === nothing
true
```

```julia
ENV["CHUI_QUIET_CONFLICTS"] = "1"   # in startup.jl, before `using` any Chui package
```

The conflicts themselves remain: a silenced banner just stops reminding you to write
`Stats.summarise` or `Reports.summarise`.

## What it costs

- **`binding_conflicts`:** one `Base.isexported` check per exported name per loaded module, plus a
  walk of `Main`'s submodules: O(exports × loaded modules). For ChuiCore's 35 exported names (36
  with the module name) against 32 loaded modules, about 36 μs and 18 KB after compilation on
  Julia 1.13.2; about 46 μs
  against 56 modules on 1.10.12 (BenchmarkTools medians, Apple silicon, loaded machine;
  indicative; evidence `.lanes/evidence/p5-optics-costs-{release,lts}-8fbb53f.txt`). No budget
  is set for it.
- **`conflict_banner`:** that, plus printing; one environment-variable read and nothing else when
  silenced.
- Both read global state (what is loaded) and are meant for package load or an occasional check,
  not for loops.
- **ChuiCore's `__init__`:** a non-interactive `using ChuiCore` pays one `isinteractive()` read;
  its load time is the same as before ChuiCore had an `__init__`, and it is what ADR-0009's
  load budgets measure. An interactive load compiles and runs the banner: about 0.25–0.3 s more
  than a non-interactive one on Julia 1.13.2 and 1.10.12 (about 0.33 s in all, over the
  non-interactive `load_ms` budgets of 75 ms on 1.13 and 100 ms on 1.10; ADR-0009 sets no interactive budget). A direct call from
  `__init__` (no `invokelatest`) would cut that to about 0.1 s but would compile the banner into
  the package image (about 0.33 MB more native code) and add about 3–5 ms to *every* load on
  1.10, interactive or not (within noise on 1.13). (Fresh-process medians, Apple silicon, loaded
  machine, 2026-10-20; indicative; evidence
  `.lanes/evidence/banner-init-load-{release,lts}-d150a86.txt` and
  `.lanes/evidence/banner-init-imagesize-{release,lts}-aaf9daf.txt`.)

Reference: [`ChuiCore.binding_conflicts`](@ref ChuiCore.binding_conflicts),
[`ChuiCore.conflict_banner`](@ref ChuiCore.conflict_banner).
