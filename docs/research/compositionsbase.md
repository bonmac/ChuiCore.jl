# CompositionsBase.jl as the owner of `⨟`

- **Date:** 2026-10-20. **Author:** phase-1 researcher lane (optics + composition).
- **Julia:** 1.10.12 (`julia +lts`) and 1.13.2 (`julia +release`), Apple Silicon (aarch64-darwin).
- **Packages resolved:** CompositionsBase 0.1.2, Accessors 0.1.45, Aqua 0.8.18 (scratch environments only).
- **Scratch:** `/private/tmp/claude-501/-Users-bonmac-personal-projects-julia-data-analysis/5c1f011c-1151-4765-9a79-8eba6d64f4e6/scratchpad/phase1/optics/`
  (`cb.jl`, `own.jl`, `vararg.jl`, `env_cb_*`, `env_*`, `reg/`, `*.txt` outputs). Scratch is not kept; outputs are pasted below.
- **Context7:** no entry for CompositionsBase.jl (`resolve-library-id "CompositionsBase.jl"` returned only
  unrelated Julia libraries). Sources are therefore the General registry, the package source and running code.
- **Context:** ecosystem ADR-0009 rule 1 recommends that ChuiCore depend on CompositionsBase and re-export
  `⨟`/`opcompose`, so that `ChuiCore.:⨟ === CompositionsBase.:⨟`. Contract law: `(f ⨟ g)(x) == g(f(x))`.
  ChuiFrames adds `⨟(::Step, ::Step)` methods.

## Q1. Version, dependencies, maintenance, source

**Method.** Extract the registry entry from the local General registry
(`~/.julia/registries/General.tar.zst`, git-tree-sha1 `3909358a…`, file dated 2026-10-19) with
`tar --zstd -xf ... C/CompositionsBase`; read the installed source; read-only `gh api` GETs.

**Registry (`C/CompositionsBase/*.toml`):**
```
Versions: 0.1.0, 0.1.1, 0.1.2   (latest 0.1.2, git-tree-sha1 802bb88c…)
Deps.toml:        (empty)
Compat.toml:      [0] julia = "1"
WeakDeps.toml:    ["0.1.2-0"] InverseFunctions = "3587e190-…"
WeakCompat.toml:  ["0.1.2-0"] InverseFunctions = "0.1"
```

**GitHub (`gh api repos/JuliaFunctional/CompositionsBase.jl`, read 2026-10-20):**
```
{"archived":false,"default_branch":"master","license":"MIT","open_issues_count":0,
 "pushed_at":"2023-04-20T18:21:17Z","stargazers_count":13,"updated_at":"2024-07-23T16:11:40Z"}
commits: 9c80024 2023-04-20 Merge pull request #12 from aplavin/master
         7b13ecc 2023-04-20 fix naming
         a62b54b 2023-02-25 add inverses
         6fdd46b 2021-07-09 Merge pull request #9 from JuliaFunctional/decompose
tags:    v0.1.0 (only)
```

**Source (`~/.julia/packages/CompositionsBase/IN0VV/src/CompositionsBase.jl`, 0.1.2), the load-bearing lines:**
```julia
const compose = ∘
opcompose(fs...) = ∘(reverse(fs)...)
const var"⨟" = opcompose
export ∘, compose, opcompose
@eval export $(Symbol("⨟"))
# if isdefined(Base, :ComposedFunction):
export decompose, deopcompose
decompose(f) = (f,);  decompose(o::Base.ComposedFunction) = (decompose(o.outer)..., decompose(o.inner)...)
deopcompose(f) = (f,); deopcompose(o::Base.ComposedFunction) = (deopcompose(o.inner)..., deopcompose(o.outer)...)
```
Extension `CompositionsBaseInverseFunctionsExt` defines `InverseFunctions.inverse` for
`deopcompose`, `splat(opcompose)`, `decompose`, `splat(compose)` (functions CompositionsBase owns).

**Findings.**
- Latest registered version is **0.1.2**; **zero hard dependencies**; Julia compat `"1"` (covers 1.10 and 1.13);
  one weak dependency (InverseFunctions, extension only).
- `⨟` is **not a separate function**: it is a `const` alias of the generic function `opcompose`. So
  `CompositionsBase.:⨟ === CompositionsBase.opcompose` (verified below), and a method added to either name
  is a method of the same function.
- `opcompose` has exactly **one method**, the untyped vararg `opcompose(fs...)`, which delegates to `Base.∘`.
  CompositionsBase **adds no methods to `Base.∘`** (verified: `length(methods(Base.:∘, CompositionsBase)) == 0`);
  `compose` is just `const compose = ∘`.
- Export list on 0.1.2: `∘` (Base's binding, re-exported), `compose`, `opcompose`, `⨟`, `decompose`, `deopcompose`.
- Maintenance: last push and last code change 2023-04-20 (inverses + extension, PR #12); not archived; 0 open
  issues. The package is small and finished rather than active. The only git tag is `v0.1.0`; the 0.1.2 release
  date is inferred from the last commit (see UNVERIFIED).

## Q2. Re-export behaviour, ambiguity and downstream methods

**Method.** `cb.jl` run in env `env_<v>` (CompositionsBase, Accessors, Aqua):
`julia +<v> --startup-file=no --project=<scratch>/env_<v> <scratch>/cb.jl`. A module `M` does
`using CompositionsBase: ⨟, opcompose; export ⨟, opcompose`; `UseMCB` does `using ..M, CompositionsBase`;
`UseMAcc` does `using ..M, Accessors`; `Down` adds `M.:⨟(a::Step, b::Step)`; `Pirate` adds
`M.:⨟(::Int, ::Int)` as a contrast. `own.jl` checks a module that defines its *own* `⨟`.

**Output, Julia 1.10.12** (1.13.2 is line-for-line identical except the `which(...).module` line prints
`.var"module"`):
```
Julia 1.10.12  CompositionsBase 0.1.2  Accessors 0.1.45  Aqua 0.8.18
--- CompositionsBase facts
CompositionsBase.:⨟ === CompositionsBase.opcompose = true
names(CompositionsBase) = [:CompositionsBase, :compose, :decompose, :deopcompose, :opcompose, :∘, :⨟]
methods(CompositionsBase.opcompose) = # 1 method for generic function "opcompose" from CompositionsBase:
 [1] opcompose(fs...)
CompositionsBase.compose === Base.:∘ = true
length(methods(Base.:∘, CompositionsBase)) = 0
Base.operator_precedence(:⨟) = 12
Base.operator_precedence(:∘) = 12
Base.operator_associativity(:⨟) = :left
Meta.parse("a ⨟ b ⨟ c") = :((a ⨟ b) ⨟ c)
--- M re-exporting CompositionsBase binding
M.:⨟ === CompositionsBase.:⨟ = true
M.opcompose === CompositionsBase.opcompose = true
Base.binding_module(M, :⨟) = CompositionsBase
UseMCB.r == cos(sin(0.3)) = true
UseMAcc.r == cos(sin(0.3)) = true
UseMAcc.s = (a = (b = 2,),)
Accessors.:⨟ === M.:⨟ = true
--- generic fallback
h(3) == g(f(3)) = true
typeof(h) = ComposedFunction{typeof(g), typeof(f)}
h isa ComposedFunction = true
((f ⨟ g) ⨟ sin)(0.5) == sin(g(f(0.5))) = true
opcompose(f) === f = true
opcompose() threw MethodError
typeof(1 ⨟ 2) = ComposedFunction{Int64, Int64}
(1 ⨟ 2)(0) threw MethodError
--- downstream method on M.:⨟ for an owned type (ChuiFrames Step-like)
s.ops = [:a, :b]
((Down.Step([:a]) ⨟ Down.Step([:b])) ⨟ Down.Step([:c])).ops = [:a, :b, :c]
(which(M.:⨟, Tuple{Down.Step, Down.Step})).module = Main.Down
(f ⨟ g)(3) = 8
Aqua.test_piracies(Down) passed
r = Method[opcompose(a::Int64, b::Int64) @ Main.Pirate .../cb.jl:63]
```

**Variadic call with a downstream 2-argument method** (`vararg.jl`, env `env_cb_<v>`; both versions identical):
```
typeof((a ⨟ b) ⨟ c) = Step
typeof(⨟(a, b, c)) = ComposedFunction{ComposedFunction{Step, Step}, Step}
typeof(a ⨟ identity) = ComposedFunction{typeof(identity), Step}
```

**A module with its OWN `⨟` binding, used together with Accessors** (`own.jl`):
```
Julia 1.10.12
WARNING: both Accessors and Own export "⨟"; uses of it in module Client must be qualified
Client.run() threw UndefVarError: UndefVarError: `⨟` not defined
Own.:⨟ === Accessors.:⨟ = false

Julia 1.13.2
Client.run() threw UndefVarError: UndefVarError: `⨟` not defined in `Main.Client`
Hint: It looks like two or more modules export different bindings with this name, resulting in ambiguity. Try explicitly importing it from a particular module, or qualifying the name with the module it should come from.
Hint: a global variable of this name also exists in CompositionsBase.
    - Also exported by Accessors.
Own.:⨟ === Accessors.:⨟ = false
```

**Findings.**
- Re-exporting works as ADR-0009 wants: `M.:⨟ === CompositionsBase.:⨟` and `Base.binding_module(M, :⨟) ==
  CompositionsBase` on both versions.
- `using M, CompositionsBase` and `using M, Accessors` both resolve a bare `⨟` without warning or ambiguity,
  because all three export the same binding. **Accessors 0.1.45 re-exports `⨟`, `opcompose` and `∘`** from
  CompositionsBase (Accessors 0.1.45 src/optics.jl line 3: `export ∘, opcompose, var"⨟"`; verified `Accessors.:⨟ === M.:⨟`).
  This settles one entry of ADR-0009's UNVERIFIED item "which dependents re-export `⨟`" (Accessors does;
  AccessorsExtra re-exports Accessors via `@reexport using Accessors`).
- Generic fallback: `(f ⨟ g)(x) == g(f(x))` holds; `f ⨟ g` returns `Base.ComposedFunction{typeof(g), typeof(f)}`,
  i.e. `g ∘ f`. `⨟(f) === f`; `⨟()` is a `MethodError`.
- `⨟` is defined for **non-functions** too: `1 ⨟ 2` builds a `ComposedFunction{Int64, Int64}` lazily and only fails
  when called. Nothing checks callability at composition time.
- A downstream package adding `M.:⨟(a::Step, b::Step)` for its own `Step` type works, does not disturb the
  function fallback, and is **not piracy** (Aqua 0.8.18 `test_piracies(Down)` passes; the `Int, Int` contrast
  is flagged). The method lives on `CompositionsBase.opcompose` (the shared function), so it is visible to
  everyone who uses any of the re-exported names.
- **Gotcha for ChuiFrames:** infix `a ⨟ b ⨟ c` parses as `(a ⨟ b) ⨟ c` (left associative, precedence 12, same as
  `∘`) and uses the 2-argument method, giving a `Step`. But the prefix call `⨟(a, b, c)` / `opcompose(a, b, c)`
  hits the vararg fallback and returns a nested `ComposedFunction` of `Step`s, not a `Step`. A downstream type
  that wants closed composition should also define the vararg method (for example
  `opcompose(a::Step, b::Step, c::Step...) = foldl(opcompose, (a, b, c...))`) and a test for it.
  Mixed `Step ⨟ function` falls back to `ComposedFunction`.
- To add a method, the defining module must `import CompositionsBase` and write
  `CompositionsBase.opcompose(...) = ...` (or `M.:⨟(...)`); a bare `opcompose(a::T, b::T) = ...` after
  `using CompositionsBase: opcompose` is rejected at precompile time on both versions
  (observed while building the optics prototype: "function CompositionsBase.opcompose must be explicitly imported
  to be extended", see `optics.md` §5).
- A ChuiCore that defines its **own** `⨟` binding breaks bare `⨟` for anyone who also loads Accessors (or
  CompositionsBase, AccessorsExtra, ...): on 1.10 a `WARNING: both ... export "⨟"` at first use and then
  `UndefVarError`; on 1.13 no warning, an `UndefVarError` with an ambiguity hint. Either way the user must
  qualify. This confirms ADR-0009's rejected alternative "a fresh ChuiCore `⨟` binding".

## Q3. Load-time cost

**Method.** Fresh processes, env containing only CompositionsBase (`env_cb_<v>`):
`julia +<v> --startup-file=no --project=env_cb_<v> -e '@time using CompositionsBase'` (×3) and
`-e 't=@elapsed using CompositionsBase'` (×5), plus `@time_imports`.

**Output.**
```
== julia +lts @time using CompositionsBase (x3)
  0.018958 seconds (841 allocations: 105.570 KiB, 24.76% compilation time)
  0.013439 seconds (841 allocations: 105.570 KiB, 46.83% compilation time)
  0.006469 seconds (841 allocations: 105.570 KiB, 56.12% compilation time)
      1.7 ms  CompositionsBase                          (@time_imports)
@elapsed x5: 12.8, 5.3, 6.9, 7.8, 6.6 ms
== julia +release @time using CompositionsBase (x3)
  0.015144 seconds (945 allocations: 97.453 KiB)
  0.007699 seconds (945 allocations: 97.453 KiB)
  0.003285 seconds (945 allocations: 97.453 KiB)
      1.1 ms  CompositionsBase                          (@time_imports)
@elapsed x5: 4.3, 3.0, 1.6, 2.6, 2.4 ms
```
**Finding.** The package itself loads in about 1–2 ms (`@time_imports`); the whole `using` costs 3–19 ms
wall-clock in a fresh process, and that range is mostly machine noise: the host load average was about 60 to 200
during the runs (`uptime`: `load averages: 197.43 123.98 60.79`, later `58.06 71.54 61.31`). This is negligible
next to Accessors (see `optics.md` §1).

## Recommendation

Adopt ADR-0009 rule 1 as written: ChuiCore takes CompositionsBase 0.1.2 as its (first) hard dependency,
`[compat] CompositionsBase = "0.1.2"`, and re-exports exactly `⨟` and `opcompose` with
`using CompositionsBase: ⨟, opcompose; export ⨟, opcompose`. Reasons, all verified above: zero dependencies,
~1–2 ms load, `julia = "1"`, the same binding that Accessors and AccessorsExtra export, so no ambiguity; downstream `Step ⨟ Step` methods are legal and piracy-free. Do **not** re-export
`compose`, `∘`, `decompose`, `deopcompose` (not needed; `∘` is Base's anyway).

Things for the ChuiCore composition ADR and the contract (`contracts/chui-core.md`) to state:
1. To extend, write `CompositionsBase.opcompose(a::T, b::T)` (or `ChuiCore.:⨟`); this is a method on a shared
   function, so it must only be added for types the package owns.
2. Owners of closed-composition types (ChuiFrames `Step`) define the vararg method too, or document that only
   infix composition is closed.
3. Do not promise what `f ⨟ g` returns for plain functions (it is a `ComposedFunction` today, ADR-0009 says
   unpromised), and note that `⨟` accepts non-callables lazily.
4. Maintenance risk is low but real: the package last changed 2023-04-20. If it ever had to be replaced, the
   `const var"⨟" = opcompose` design means ChuiCore cannot swap bindings without breaking the
   `ChuiCore.:⨟ === CompositionsBase.:⨟` identity; that would be an ecosystem-level ADR.

## UNVERIFIED

- Exact release date of CompositionsBase 0.1.2: the registry stores no dates and the repo has only a `v0.1.0`
  tag; 2023-04-20 is the last commit (PR #12, which added the InverseFunctions extension that 0.1.2's
  registry entry lists), so the release is on or after that date.
- Whether Transducers.jl re-exports `⨟` (not loaded here; ADR-0009 E-03/E-28 is the source for its dependence).
- Load times are on a heavily loaded host; absolute numbers are indicative, not a benchmark.
