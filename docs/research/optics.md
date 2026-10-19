# Optics: Accessors.jl evaluation and ChuiCore options

- **Date:** 2026-10-20. **Author:** phase-1 researcher lane (optics + composition).
- **Julia:** 1.10.12 (`julia +lts`) and 1.13.2 (`julia +release`), Apple Silicon (aarch64-darwin).
- **Packages resolved:** Accessors 0.1.45, AccessorsExtra 0.1.102, CompositionsBase 0.1.2,
  ConstructionBase 1.6.0, InverseFunctions 0.1.18, MacroTools 0.5.16, BenchmarkTools 1.8.0, Aqua 0.8.18
  (scratch environments only).
- **Scratch:** `/private/tmp/claude-501/-Users-bonmac-personal-projects-julia-data-analysis/5c1f011c-1151-4765-9a79-8eba6d64f4e6/scratchpad/phase1/optics/`
  (`api.jl`, `prism.jl`, `perf2.jl`, `ext_test.jl`, `ChuiLike/` prototype package, `env_*`, `reg/`, `*.txt`).
  Scratch is not kept; outputs are pasted below.
- **Context7:** no entry for Accessors.jl (`resolve-library-id` for "Accessors.jl" and "JuliaObjects Accessors"
  returned only unrelated libraries). Sources are the General registry, package source, GitHub metadata and
  running code.
- **Brief:** "Optics: lenses and prisms. Evaluate Accessors.jl and reuse it if it's good enough."
  Constraints: ADR-0002 (no heavy hard dependencies; ChuiCore's budget is tiny), ADR-0009 (CompositionsBase owns `⨟`;
  see `compositionsbase.md`).

## 1. Accessors.jl: version, compat, dependencies, load time

**Method.** Registry entries extracted from `~/.julia/registries/General.tar.zst` (git-tree-sha1 `3909358a…`,
file dated 2026-10-19) with `tar --zstd -xf … A/Accessors C/ConstructionBase I/InverseFunctions M/MacroTools …`;
then `Pkg.add("Accessors")` in a fresh scratch env per Julia version and `Pkg.status(mode=PKGMODE_MANIFEST)`.
GitHub: `gh api repos/JuliaObjects/Accessors.jl` and `/releases` (read-only GET).

**Registry, Accessors (latest 0.1.45):**
```
Deps  [0]            CompositionsBase, ConstructionBase, MacroTools
      ["0.1.12 - 0"] Dates (stdlib)
      ["0.1.13 - 0"] InverseFunctions
Compat ["0.1.43 - 0"] ConstructionBase = "1.5.0 - 1", InverseFunctions = "0.1.5 - 0.1", julia = "1.10.0 - 1"
       ["0.1.32 - 0"] MacroTools = "0.5";  [0] CompositionsBase = "0.1";  ["0.1.38 - 0"] Dates = "1"
WeakDeps (current): StaticArrays, AxisKeys, IntervalSets, StructArrays, Unitful, Test, LinearAlgebra
Transitive: ConstructionBase 1.6.0 -> no hard deps (IntervalSets, StaticArrays, LinearAlgebra weak);
            InverseFunctions 0.1.18 -> no hard deps (Dates, Test weak); MacroTools 0.5.16 -> no hard deps;
            CompositionsBase 0.1.2 -> no hard deps (InverseFunctions weak).
```
**Resolved manifest (identical on 1.10.12 and 1.13.2):**
```
[7d9f7c33] Accessors v0.1.45
[a33af91c] CompositionsBase v0.1.2
[187b0558] ConstructionBase v1.6.0
[3587e190] InverseFunctions v0.1.18
[1914dd2f] MacroTools v0.5.16
[ade2ca70] Dates   [de0858da] Printf   [4ec0a83e] Unicode
```
**GitHub:** `JuliaObjects/Accessors.jl`, not archived, 234 stars, 31 open issues, last push 2026-08-30;
releases v0.1.45 (2026-06-26), v0.1.44 (2026-03-22), v0.1.43 (2025-12-02). Actively maintained, still 0.1.x.

**Load time.** Fresh process per run, env with only Accessors (`env_acc_<v>`):
```
== julia +lts @time using Accessors (x3)
  0.504806 seconds (208.25 k allocations: 16.903 MiB, 72.64% compilation time)
  0.474678 seconds (208.25 k allocations: 16.903 MiB, 59.51% compilation time)
  0.167680 seconds (208.25 k allocations: 16.903 MiB, 61.80% compilation time)
   @elapsed x5: 275.2, 218.5, 236.8, 449.0, 211.6 ms
== julia +lts @time_imports
     40.0 ms  MacroTools
    401.3 ms  InverseFunctions 93.12% compilation time
     11.5 ms  InverseFunctions → InverseFunctionsDatesExt
      3.0 ms  ConstructionBase
      1.1 ms  ConstructionBase → ConstructionBaseLinearAlgebraExt
      1.4 ms  CompositionsBase
      1.3 ms  CompositionsBase → CompositionsBaseInverseFunctionsExt
     96.1 ms  Accessors
      5.9 ms  Accessors → LinearAlgebraExt
== julia +release @time using Accessors (x3)
  0.496364 seconds (28.73 k allocations: 2.343 MiB)
  0.210146 seconds (28.73 k allocations: 2.343 MiB)
  0.264693 seconds (28.73 k allocations: 2.343 MiB)
   @elapsed x5: 231.8, 78.9, 58.1, 306.6, 149.3 ms
== julia +release @time_imports
      5.4 ms  MacroTools
    254.1 ms  InverseFunctions 83.40% compilation time
      3.6 ms  ConstructionBase
      8.0 ms  ConstructionBase → ConstructionBaseLinearAlgebraExt
      1.4 ms  CompositionsBase
      1.1 ms  CompositionsBase → CompositionsBaseInverseFunctionsExt
      2.5 ms  Printf
    145.0 ms  Dates
     87.1 ms  InverseFunctions → InverseFunctionsDatesExt
     17.4 ms  Accessors
      2.4 ms  Accessors → LinearAlgebraExt
```
Comparison (same method): `using CompositionsBase` 3–19 ms, `@time_imports` 1.1–1.7 ms; `using ConstructionBase`
5 ms on 1.13.2 (×3: 5.6, 4.6, 4.7 ms) and 36–123 ms on 1.10.12 (70–91 % compilation time).

**Findings.**
- Latest **0.1.45**; supports Julia 1.10 (`julia = "1.10.0 - 1"` since 0.1.42), so the floor matches ChuiCore's.
- **5 registered hard deps** (CompositionsBase, ConstructionBase, InverseFunctions, MacroTools + Dates stdlib),
  none with further registered hard deps. Small by package standards; seven weak deps are extensions only.
- `using Accessors` costs roughly **0.06–0.5 s** in a fresh process versus ~2–19 ms for CompositionsBase, i.e.
  one to two orders of magnitude more. The cost is dominated by **InverseFunctions** (250–400 ms, 83–93 %
  compilation, likely invalidation-driven; not investigated) and, on 1.13, by loading the `Dates` stdlib
  (145 ms) that Accessors and InverseFunctions' extension pull in. The host was heavily loaded (load average
  60–200 during runs), so treat absolute numbers as indicative; the ratio is consistent across all runs.
- InverseFunctions is a hard dep because Accessors' default `set` for an arbitrary function uses
  `InverseFunctions.inverse` (Accessors src/optics.jl, `_set(obj, optic, val, ::SetBased)`): `set(2.0, log, 1.0) == e`.

## 2. API, composition and lens laws (run on both versions)

**Method.** `api.jl` in `env_<v>`: `julia +<v> --startup-file=no --project=<scratch>/env_<v> <scratch>/api.jl`.
Nested immutable structs `Outer(a::Inner, tag)`, `Inner(x::Int, y::Float64)`, a nested NamedTuple and a Tuple.

**Output, Julia 1.10.12** (1.13.2 prints identical values; `#= file:line =#` macro-expansion noise trimmed):
```
Julia 1.10.12  Accessors 0.1.45  CompositionsBase 0.1.2
--- @set / set / modify / @reset / @optic
@set(o.a.x = 10) = Outer(Inner(10, 2.0), :t)
l = (@o _.a.x)
typeof(l) = ComposedFunction{PropertyLens{:x}, PropertyLens{:a}}
l(o) = 1
set(o, l, 99) = Outer(Inner(99, 2.0), :t)
modify(x -> x + 1, o, l) = Outer(Inner(2, 2.0), :t)
p = Outer(Inner(1, 5.5), :t)                      # after @reset p.a.y = 5.5
@modify(x -> 2x, o.a.y) = Outer(Inner(1, 4.0), :t)
--- composition: ⨟ and ∘ come from CompositionsBase
c1 = (@o _.a.x)
typeof(c1) = ComposedFunction{PropertyLens{:x}, PropertyLens{:a}}
c1 == c2 = true                                   # c1 = la ⨟ lx, c2 = lx ∘ la
c1(o) = 1
Accessors.:⨟ === CompositionsBase.:⨟ = true
Accessors.opcompose === CompositionsBase.opcompose = true
parentmodule(Accessors.opcompose) = CompositionsBase
set(o, c1, -1) = Outer(Inner(-1, 2.0), :t)
--- NamedTuple / Tuple
@set(nt.b.d[2] = 40) = (a = 1, b = (c = 2, d = (3, 40)))
@insert(nt.z = 0) = (a = 1, b = (c = 2, d = (3, 4)), z = 0)
@delete(nt.a) = (b = (c = 2, d = (3, 4)),)
@set(t[2] = :two) = (1, :two, 3)
@insert(t[2] = 1.5) = (1, 1.5, 2, 3)
@delete(t[1]) = (2, 3)
set(t, last, 30) = (1, 2, 30)
set(t, first, 10) = (10, 2, 3)
--- getall / setall / Elements / Properties / If / Recursive
getall(nt, @optic(_.b.d |> Elements())) = (3, 4)
setall(nt, @optic(_.b.d |> Elements()), (30, 40)) = (a = 1, b = (c = 2, d = (30, 40)))
modify(x -> 10x, (1, 2, 3, 4), @optic((_ |> Elements()) |> If(iseven))) = (1, 20, 3, 40)
getall((1, 2, 3, 4), @optic((_ |> Elements()) |> If(iseven))) = (2, 4)
set((a = 1, b = 2), Properties(), 0) = (a = 0, b = 0)
modify(x -> 100x, (1, 2, (3, (4, 5), 6)), Recursive(x -> x isa Tuple, Elements())) = (100, 200, (300, (400, 500), 600))
set(2.0, log, 1.0) = 2.718281828459045
--- lens laws
laws(o, @optic(_.a.x), 7, 8) = (getset = true, setget = true, setset = true)
laws(nt, @optic(_.b.d[1]), 7, 8) = (getset = true, setget = true, setset = true)
laws(t, @optic(_[3]), :a, :b) = (getset = true, setget = true, setset = true)
laws(o, la ⨟ lx, 7, 8) = (getset = true, setget = true, setset = true)
Accessors.test_getset_laws passed
getall(setall(t, Elements(), (7, 8, 9)), Elements()) == (7, 8, 9) = true
```
(`laws` checks get-set `set(o, l, l(o)) == o`, set-get `l(set(o, l, v)) == v`,
set-set `set(set(o, l, v1), l, v2) == set(o, l, v2)`.)

**Findings.**
- The API the brief asks about all exists and works on 1.10 and 1.13: `@set`, `@reset`, `@modify`, `@optic`/`@o`,
  `set`, `modify`, `getall`, `setall`, `insert`/`@insert`, `delete`/`@delete`, plus `Elements`, `Properties`,
  `If`, `Recursive` (exports in Accessors src/optics.jl lines 1–6 and src/sugar.jl line 1).
- **An Accessors optic is just a callable.** Composition is `Base.ComposedFunction` (`const ComposedOptic =
  ComposedFunction` for back-compat); `⨟`/`opcompose`/`∘` are CompositionsBase's, imported and **re-exported**
  by Accessors. So Accessors and an ADR-0009 ChuiCore share one `⨟`. Plain functions (`first`, `last`, `log`, …)
  are optics too, via per-function `set` methods or `InverseFunctions.inverse`.
- Extension point: a new optic needs `(o::MyOptic)(obj)` and `Accessors.set(obj, ::MyOptic, v)` (default
  `OpticStyle` is `SetBased`, and `modify` is derived as `set(obj, o, f(o(obj)))`); traversals declare
  `OpticStyle(::Type{MyOptic}) = ModifyBased()` and implement `modify` (Accessors src/optics.jl lines 144–212).
- Lens laws hold on all tested lenses, including composed ones; Accessors ships `test_getset_laws`,
  `test_modify_law`, `test_getsetall_laws`, `test_insertdelete_laws` in a `Test` extension.
- Struct rebuild uses ConstructionBase (`constructorof`, `setproperties`), so it works on any plain immutable
  struct with a default constructor.

## 3. Prisms and sum-type optics

**Method.** Source search (`grep -rni "prism\|maybe"` over the Accessors 0.1.45 and AccessorsExtra 0.1.102 trees)
and `prism.jl` run in `env_<v>` with AccessorsExtra loaded.

**Output** (identical on both versions apart from the version line; macro-expansion noise trimmed):
```
Julia 1.10.12  AccessorsExtra 0.1.102
modify(a -> a + 100, v1, o) = (x = 101, y = nothing)      # o = @optic _.x |> If(!isnothing)
modify(a -> a + 100, v2, o) = (x = nothing, y = 2)
getall(v1, o) = (1,)
getall(v2, o) = ()
o(v2) threw MethodError                                    # If is not a getter
m((a = 1,)) = nothing                                      # m = maybe(@optic _.z)
m((z = 5,)) = 5
set((a = 1,), m, 7) = (a = 1, z = 7)
set((z = 5,), m, 7) = (z = 7,)
set((z = 5,), m, nothing) = NamedTuple()
getall((a = 1,), m) = ()
getall((z = 5,), m) = (5,)
os((b = 2,)) = 2                                           # os = osomething(@optic(_.a), @optic(_.b))
set((b = 2,), os, 20) = (b = 20,)
modify via something(_) threw: This should be unreachable. You probably need to overload ...
getall((a = 1, b = (2, "x", 3.0)), r) = (1, 2, 3.0)        # r = RecursiveOfType(Number)
isdefined(Accessors, :Prism) = false
isdefined(AccessorsExtra, :Prism) = false
```
The grep found no occurrence of "prism" in either package (source, tests, README).

**Findings.**
- **Accessors has no prism type and no prism concept.** The nearest thing is `If(pred)`: a *filter traversal*
  (`ModifyBased`, usable with `modify`/`getall`/`setall`), not a getter — `o(obj)` is a `MethodError` — and it has
  no `review`/`build` direction (cannot construct the sum value from the focus). `Elements`, `Properties`,
  `Recursive` are traversals.
- **AccessorsExtra** (separate package) adds optional/affine-style optics: `maybe(o; default)` (present → focus,
  absent → `default`; `set` *inserts* when absent, `set(…, nothing)` deletes), `osomething` (first present optic),
  `RecursiveOfType`, `@oget`. These are presence-based (via `hasoptic`), not variant-based: none matches on
  which branch of a `Union`/ADT a value is, and none can build a variant. So "prism coverage" for Chui's ADTs
  (`Option`/`Either`/user sum types) is **none** in either package.
- `something` (unwrap `Some`) is not an optic: `modify(f, s, @optic something(_.val))` errors asking for an
  `Accessors.set(::Some, ::typeof(something), val)` overload.
- AccessorsExtra is not a candidate dependency: hard deps include Accessors, DataPipes, Reexport,
  ConstructionBase, InverseFunctions, CompositionsBase, LinearAlgebra; ~12 weak deps (Distributions,
  StaticArrays, Dictionaries, …); it `@reexport`s Accessors and ConstructionBase, and its src/overrides.jl adds
  a method to Accessors' internal `Accessors.opticmacro(::Function, ex)`, changing `@optic` parsing globally
  once loaded (piracy of an Accessors internal). Julia compat `1.9.0 - 1`.

## 4. Performance: Accessors vs a hand-written lens

**Method.** `perf2.jl` in `env_<v>`. Three-level immutable struct `Outer(mid::Mid(inner::Inner(x::Int, y::Float64),
s::String), tag::Symbol)`. Hand-written `struct Lens{G,S}; get::G; set::S; end` with closures, composed by a
`CompositionsBase.opcompose(::Lens, ::Lens)` method. `Test.@inferred` on each call; `@allocated` behind a function
barrier after warm-up; BenchmarkTools `@benchmark $f($R[])` with the object behind a `Ref` to prevent constant
folding.

**Output, Julia 1.10.12:**
```
set_(hand, obj, 5) == set(obj, acc, 5) = true
--- @inferred
all @inferred passed      # set, modify, getter for Accessors and hand lens; set(obj, @optic(_.tag), :u)
--- @allocated (after warm-up, inside a function)
f_acc_set    allocated = 0 bytes
f_acc_mod    allocated = 0 bytes
f_hand_set   allocated = 0 bytes
f_hand_mod   allocated = 0 bytes
f_macro      allocated = 0 bytes
f_direct     allocated = 0 bytes
--- BenchmarkTools (min time; object behind a Ref so it is not constant-folded)
accessors set      min 1.333 ns  allocs 0  memory 0
accessors modify   min 1.333 ns  allocs 0  memory 0
hand set           min 1.334 ns  allocs 0  memory 0
hand over          min 1.334 ns  allocs 0  memory 0
@set macro         min 1.333 ns  allocs 0  memory 0
direct ctor        min 1.333 ns  allocs 0  memory 0
```
**Output, Julia 1.13.2:** same lines; every `@allocated` is 0 bytes and every min time is `1.875 ns`, allocs 0.

**Findings.**
- `set`, `modify` and `@set` through Accessors are **type-stable and allocation-free** on both versions, and as
  fast as the hand-written lens and as direct constructor calls (all at the same timer floor).
- A first version of the script measured `@allocated` from a top-level loop over the functions and reported
  48 bytes on 1.10.12 for *every* variant including the hand lens; with a function barrier it is 0. That 48 is a
  measurement artifact of dynamic dispatch at top level, not an Accessors cost.
- A hand-written lens is equally fast **only if the field name lives in the type**. In the prototype (§5) a lens
  built from a runtime `Symbol` (`field_dyn(:a)`) fails `@inferred`; built from `Val(:a)` it passes. Accessors
  gets this for free from `PropertyLens{:a}`.

## 5. Options for ChuiCore

**Prototype for option (b).** Scratch package `ChuiLike` (deps: CompositionsBase; weakdep: Accessors;
extension `ChuiLikeAccessorsExt`). Core: `struct Lens{G,S}`, callable as getter, verbs `view`/`set`/`over`,
`CompositionsBase.opcompose(::Lens, ::Lens)`. Extension: (1) `Accessors.set(obj, l::ChuiLike.Lens, v) =
l.set(obj, v)`, (2) `ChuiLike.view/set/over` methods for `Union{Accessors.PropertyLens, IndexLens, Elements,
If, Properties, ComposedFunction}`. Driver `ext_test.jl`, `Pkg.develop`ed into `env_ext_<v>`.

Output (identical values on both versions; noise trimmed):
```
Base.get_extension(ChuiLike, :ChuiLikeAccessorsExt) === nothing = true    # before `using Accessors`
ext !== nothing = true                                                    # after
ChuiLike.set(nt, a ⨟ b, 10) = (a = (b = 10, c = 2), z = 0)
typeof(mixed) = ComposedFunction{PropertyLens{:c}, Lens{…{:a}, …{:a}}}     # mixed = a ⨟ @optic(_.c)
Accessors.set(nt, mixed, 20) = (a = (b = 1, c = 20), z = 0)
Accessors.modify(x -> x + 1, nt, mixed) = (a = (b = 1, c = 3), z = 0)
@set(nt |> a |> _.b = 99) = (a = (b = 99, c = 2), z = 0)
ChuiLike.view(nt, @optic(_.a.c)) = 2
ChuiLike.set(nt, @optic(_.a.c), 5) = (a = (b = 1, c = 5), z = 0)
ChuiLike.over(x -> 2x, nt, @optic(_.a.b)) = (a = (b = 2, c = 2), z = 0)
laws ok                                                                   # Accessors.test_getset_laws(a ⨟ b, …)
field_dyn (Symbol at runtime) @inferred fails: ErrorException
Aqua piracies(ChuiLike) ok
Aqua piracies(ext; treat_as_own = ChuiLike types/functions) ok
WARNING: both Accessors and ChuiLike export "set"; uses of it in module ClashCheck must be qualified   # 1.10 only
unqualified `set` with using ChuiLike, Accessors: UndefVarError                                          # both
```
Notes from building it: extending `opcompose` needs `import CompositionsBase` and a qualified
`CompositionsBase.opcompose(...)` definition (both versions reject the unqualified form at precompile);
`Aqua.test_piracies(ext_module)` without `treat_as_own` flags every extension method, because the extension
module owns neither the functions nor the types; with `treat_as_own` set to the parent's types/functions it
passes.

**Facts per option.**

| | (a) hard-depend on Accessors, re-export/extend | (b) own minimal Lens/Prism + `ChuiCoreAccessorsExt` | (c) own only |
|---|---|---|---|
| Hard deps added | +4 registered (ConstructionBase, InverseFunctions, MacroTools; CompositionsBase is already planned) + Dates stdlib | none beyond CompositionsBase (+ ConstructionBase if struct setters are wanted, §1: ~5 ms on 1.13, 36–123 ms on 1.10) | same as (b) |
| `using` cost added to every Chui package | ~0.06–0.5 s (InverseFunctions + Dates dominate) | ~0 (extension loads only when the user loads Accessors) | ~0 |
| Lenses, traversals, macros | full, mature, law-tested, zero-overhead (§2, §4) | ChuiCore writes a small lens set; full Accessors power when the user loads it | ChuiCore writes and maintains everything incl. macros |
| Prisms | none (§3); ChuiCore must write them anyway | ChuiCore's own `Prism` for its ADTs; interoperates through the extension | own |
| Interop with Accessors users | native | verified both directions: Chui lenses inside `@set`/`set`/`modify` and composed with Accessors optics; Accessors optics accepted by Chui verbs | none |
| `⨟` | same binding (Accessors re-exports CompositionsBase's) | same binding | same binding |
| Name clashes | none if ChuiCore re-exports Accessors' names; conflicts if it exports its own `set`/`modify` | ChuiCore exporting `set`/`modify`/`delete`/`insert` makes bare names ambiguous with `using Accessors` (verified for `set`) | same |
| Stability risk | Accessors is 0.1.x; its breaking changes become ChuiCore's | only the extension tracks Accessors | none |
| Piracy | n/a | none (Aqua, with `treat_as_own` on the extension) | n/a |

**Recommendation: option (b).**
1. Accessors is good, fast and law-abiding, and it already shares ChuiCore's `⨟`, but as a hard dependency it costs
   every Chui package roughly 0.1–0.5 s of `using` time and four more registered packages (Accessors,
   ConstructionBase, InverseFunctions, MacroTools), against ADR-0002's
   budget, while still lacking prisms, which ChuiCore must write anyway.
2. ChuiCore owns a minimal optic core: `Lens` (field name in the type, e.g. built from `Val`/a macro), `Prism`
   for ChuiCore's sum types (match + build), composition via methods on `CompositionsBase.opcompose`, and law
   kits (get-set, set-get, set-set; prism review-preview laws). Optics are callables, like Accessors', so the
   extension is thin.
3. `ChuiCoreAccessorsExt` (weakdep Accessors, `[compat] Accessors = "0.1.43"` or later; 0.1.42 is the first with
   `julia ≥ 1.10`) makes ChuiCore optics Accessors optics (`Accessors.set`, plus `OpticStyle`/`modify` for prisms)
   and lets ChuiCore's verbs take Accessors optics.
4. **Naming:** do not export a `set` (or `modify`/`delete`/`insert`) that differs from Accessors' binding; pick
   distinct verb names (e.g. `view`-like names that avoid `Base.view`) or leave them unexported. This is a naming
   decision for the ChuiCore names ADR.
5. Whether struct setters justify ConstructionBase as a second hard dependency is a separate dependency-ADR
   question; ConstructionBase 1.6.0 has no hard deps but showed 36–123 ms `using` on 1.10.12 here.

Option (a) remains the fallback if the ecosystem later accepts the load cost (for example if ChuiFrames needs
Accessors anyway). Option (c) gives up free interop for no saving over (b).

## Addendum (2026-10-20, after critic review)

- Load times above were taken on a heavily loaded host. Re-measured at load average ~7 in
  `law-kits-modules-names.md` L-6: `using Accessors` 66–74 ms (1.10.12) and 25–36 ms (1.13.2);
  ConstructionBase 16–23 / 2–8 ms; CompositionsBase 4–6 / 1.3 ms. Use those figures.
- A critic showed (scratch runs, both versions) that Accessors' struct rebuild is ConstructionBase's
  `constructorof(T) = Base.typename(T).wrapper`, so Accessors fails on the same custom-constructor
  types a default-constructor rule fails on (`@set Interval(0.0).hi = 5.0` → `MethodError`), unless
  the type's owner defines `ConstructionBase.constructorof`.
- Only Accessors 0.1.45 was resolved and run; the lower bound 0.1.43 is not tested.

## UNVERIFIED

- Why InverseFunctions takes 250–400 ms with 83–93 % compilation time on load (invalidation suspected, not traced
  with SnoopCompile). Also why ConstructionBase shows 70–91 % compilation on 1.10.12.
- Load times were taken on a heavily loaded host (load average 58–197); absolute times are indicative only;
  BenchmarkTools minima sit at the timer floor, so "equal" means "not distinguishable here".
- Prism laws and a prism design were not prototyped; only lenses were.
- AccessorsExtra's other optics (`PartsOf`, `concat`, `keyed`, regex optics) were not run.
- Whether ChuiFrames will need Accessors anyway (which would change the cost side of option (a)).
- The exact behaviour of Accessors `@set` on structs with inner constructors that differ from the default one
  (depends on `ConstructionBase.constructorof`; not tested).

## Also noticed

- Accessors loads the `Dates` stdlib unconditionally (`include("../ext/DatesExt.jl")` in Accessors src/Accessors.jl,
  issue #192 referenced in a comment), part of its 1.13 load cost.
- `LinearAlgebra` extensions of Accessors and ConstructionBase triggered in a plain `julia --startup-file=no`
  session on both versions (LinearAlgebra was already loaded), so they add a few ms too.
