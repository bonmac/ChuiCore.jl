# ADTs and pattern matching: hand-rolled vs Moshi.jl vs SumTypes.jl vs MLStyle.jl

Date: 2026-10-20. Lane: phase1-research (researcher). Status: evidence for an ADR, not a decision.

## Question

For ChuiCore's algebraic data types and pattern matching, which option is best:

- hand-rolled (abstract type + concrete structs + dispatch, or a `Union` of plain structs,
  optionally behind a small macro of our own),
- Moshi.jl,
- SumTypes.jl,
- MLStyle.jl?

The ADTs carry Maybe/Either-style values in examples, the base functors of recursion schemes
(`ListF`, and `ExprF` for the plan-rewrite optimizer in ChuiFrames), free-monad instruction sets,
and coproducts of functors (data types à la carte). ChuiCore's dependency budget is tiny
because every ecosystem package loads it. Julia floor 1.10 (1.10.12), stable 1.13 (1.13.2).

## Method

- Docs: Context7 first. MLStyle resolved to `/thautwarm/mlstyle.jl` and was queried (ADT
  syntax, type parameters). Moshi.jl and SumTypes.jl are **not indexed in Context7**: three
  `resolve-library-id` attempts each returned only unrelated libraries (a Kotlin JSON library
  and a speech model for "Moshi"; CUDA.jl and others for "SumTypes"). For those two the source
  is the README and docs shipped in the installed package
  (`~/.julia/packages/Moshi/Gh4gp/{README.md,docs/src/content/docs/**}`,
  `~/.julia/packages/SumTypes/ebJeN/README.md`) and the package source.
- Registry facts: the local General registry snapshot `~/.julia/registries/General.tar.zst`
  (file dated 2026-10-19, tree `3909358acc0fb535d4cb67fa03ee5836ad28b0f2`), decompressed into
  scratch and read (`Package.toml`, `Versions.toml`, `Compat.toml`, `Deps.toml`).
  Transitive dependencies from `Pkg.dependencies()` in a fresh env containing only that package.
- Maintenance: `gh api repos/<owner>/<repo>`, `.../releases?per_page=1`, `.../commits?per_page=1`
  (read-only GET), run 2026-10-20.
- Same program written five ways (scratch dir
  `/private/tmp/claude-501/-Users-bonmac-personal-projects-julia-data-analysis/5c1f011c-1151-4765-9a79-8eba6d64f4e6/scratchpad/phase1/adt/`,
  below `$S`):
  - `Shape` with 3 variants `Circle(Float64)`, `Rect(Float64,Float64)`, `Tri(Float64,Float64)`
    and `area`; `sumarea` over a `Vector` of 10^6 values.
  - `Op6` with 6 one-field variants and `val6`; `sum6` over 10^6 values (to cross Julia's
    union-splitting limit of 4 and `max_methods` of 3; both defaults verified on 1.10.12 and
    1.13.2 with `Core.Compiler.InferenceParams()`: `max_union_splitting=4 max_methods=3`).
  - base functor `ExprF{A}` = `Lit(Int) | Add(A,A) | Neg(A)`, `fmap`, a fixpoint `Fix`, `cata`,
    an `Int` algebra, evaluated over a deterministic tree of depth 16 (`build(16)`, result 1473).
  - Files: `$S/defs/{hand_abstract,hand_union,hand_union_isa,moshi,sumtypes,mlstyle}.jl`,
    shared loop code `$S/defs/common.jl`, driver `$S/defs/bench.jl`.
- Inference: `Base.return_types`, `Test.@inferred`, and a crude count of `code_warntype`
  lines containing `::Any` or `Union{`. Allocations: `@allocated` after warm-up, plus
  BenchmarkTools `@benchmark` median. BenchmarkTools 1.x in each env (exact version not recorded).
- TTFX two ways, 5 fresh processes each, median reported:
  1. script: `using Pkg` time, then define + first call (macro expansion and compile at run time),
     `$S/defs/ttfx.jl`, runner `$S/run_ttfx.sh`, output `$S/out/ttfx.txt`;
  2. package: each option wrapped as a tiny scratch package `$S/pkgs/AdtB*`, precompiled
     (`Base.compilecache`, one run), then `using` time and first-call time,
     runner `$S/run_pkgttfx.sh`, output `$S/out/pkg_ttfx.txt`. This is the realistic number
     for ChuiCore, since macro expansion happens at precompile time.
- Machine: Apple M3 Pro; load averages during the run were 15 to 48 (other agents running),
  so absolute timings are noisy. Treat timings as order-of-magnitude; allocation counts and
  inference results are deterministic.
- Commands: `julia +lts --startup-file=no --project=$S/envs/<env> ...` (1.10.12) and
  `julia +release ...` (1.13.2). Raw benchmark output: `$S/out/bench_<lts|rel>_<option>.txt`.

## Package facts (registry snapshot 2026-10-19; GitHub 2026-10-20)

| | Moshi.jl | SumTypes.jl | MLStyle.jl |
|---|---|---|---|
| Latest registered | 0.3.13 | 0.5.9 | 0.4.17 |
| Repo | Roger-luo/Moshi.jl | MasonProtter/SumTypes.jl | thautwarm/MLStyle.jl |
| Julia compat (latest) | `1.10.0 - 1` | `1.6.0 - 1` | `1` |
| Direct deps | ExproniconLite 0.10.10-0.10, Jieko 0.2 | MacroTools 0.5, PrecompileTools 1 | none |
| Transitive (both 1.10 and 1.13 envs) | ExproniconLite 0.10.14, Jieko 0.2.1 (2 registered, 0 stdlib) | MacroTools 0.5.16, PrecompileTools 1.2.1 (1.10) / 1.3.4 (1.13), Preferences 1.6.1 (3 registered) + stdlibs TOML, Dates, Printf, Unicode | none |
| Last release | v0.3.13, 2026-09-27 | v0.5.9, 2026-09-03 | v0.4.17, 2023-02-13 |
| Last commit | 2026-09-27 | 2026-09-03 | 2025-09-09 |
| Open issues / stars | 8 / 114 | 8 / 122 | 53 / 422 |
| License | MIT | MIT | MIT |
| Self-described status | "early stage of development ... API and features are subject to change" (README) | stable API, `@cases` "falls far short of a full on pattern matching system" (README) | none |

Sources: registry files `M/Moshi`, `S/SumTypes`, `M/MLStyle` in the snapshot; `Pkg.dependencies()`
output from `$S/setup.jl`; `gh api` output:

```
== Roger-luo/Moshi.jl   {"archived":false,"license":"MIT","open_issues_count":8,"pushed_at":"2026-09-27T19:59:28Z","stargazers_count":114}
                        {"published_at":"2026-09-27T19:59:28Z","tag_name":"v0.3.13"}  last commit 2026-09-27T19:58:41Z
== MasonProtter/SumTypes.jl {"open_issues_count":8,"pushed_at":"2026-09-03T19:13:19Z","stargazers_count":122}
                        {"published_at":"2026-09-03T19:13:20Z","tag_name":"v0.5.9"}   last commit 2026-09-03T18:53:32Z
== thautwarm/MLStyle.jl {"open_issues_count":53,"pushed_at":"2025-09-09T10:28:31Z","stargazers_count":422}
                        {"published_at":"2023-02-13T04:03:06Z","tag_name":"v0.4.17"} last commit 2025-09-09T10:28:31Z
```

All three install and run on both 1.10.12 and 1.13.2 (envs `$S/envs/{lts,rel}_*`).

## What each option generates (representation)

| Option | Value type of a variant | Container `Vector{Shape}` | Bytes/elem (`summarysize/N`) |
|---|---|---|---|
| hand, abstract | its own struct `Circle <: Shape` | abstract eltype, boxed pointers | 21.3 |
| hand, `Union` alias | its own struct `Circle` | `Vector{Union{Circle,Rect,Tri}}`, isbits-union inline | 17.0 |
| Moshi | every variant is `Shape.Type` (one concrete struct wrapping a `Union` of storage structs) | concrete | 24.0 |
| SumTypes | every variant is `Shape` (concrete) | concrete | 24.0 |
| MLStyle | its own struct `Circle <: Shape` (abstract supertype) | abstract eltype, boxed | 21.3 |

Sources: `eltype(v)`, `isconcretetype`, `summarysize` lines in `$S/out/bench_*.txt`; Moshi's
docs page data/understand.mdx, in the installed package ("we can just use it, and generate our ADT as
`struct Type; data::Union{...} end`"); probe output
`fieldtypes(ExprF.Type{Int}) = (Union{...Storage#Add{Int64}, ...Storage#Lit{Int64}, ...Storage#Neg{Int64}},)`
and SumTypes `fieldtypes(Defs.ExprF{Int}) = (Union{SumTypes.Variant{:Lit,...}, ...},)`.
MLStyle: Context7 `/thautwarm/mlstyle.jl` (its syntax/adt.md docs page: `@data T` expands to
`abstract type T end; struct C1 <: T ...`).

## Results: Julia 1.10.12

Command: `julia +lts --startup-file=no --project=$S/envs/lts_<pkg> $S/defs/bench.jl <option>`.

| Option | infer `sumarea` (3 var) | infer `sum6` (6 var) | infer `evaltree` | allocs `sumarea` 1e6 | allocs `sum6` 1e6 | allocs `evaltree` d16 | median `sumarea` | median `sum6` | median `evaltree` |
|---|---|---|---|---|---|---|---|---|---|
| hand, abstract + dispatch | Float64 | **Any** | Int64 | 0 | **2,000,000 (30.5 MiB)** | **15,079 (424 KiB)** | 2.53 ms | **249 ms** | 512 µs |
| hand, `Union` + dispatch | Float64 | **Any** | Int64 | 0 | **3,000,000 (45.8 MiB)** | 0 | 1.59 ms | **166 ms** | 197 µs |
| hand, `Union` + `isa` chain | Float64 | Float64 | Int64 | 0 | 0 | 0 | 0.97 ms | 1.91 ms | 123 µs |
| Moshi 0.3.13 | Float64 | Float64 | Int64 | 0 | 0 | 0 | 1.87 ms | 2.32 ms | 365 µs |
| SumTypes 0.5.9 | Float64 | Float64 | Int64 | 0 | 0 | 0 | 1.66 ms | 2.47 ms | 288 µs |
| MLStyle 0.4.17 | Float64 | Float64 | Int64 | 0 | 0 | **27,166 (613 KiB)** | 2.92 ms | 4.59 ms | **4.98 ms** |

Allocation counts are BenchmarkTools medians. `@allocated` at global scope reported 16 bytes for
every zero-allocation case on 1.10 (all options, including hand-rolled); this is a measurement
artefact of the top-level call, not allocation in the loop.

Excerpt (`$S/out/bench_lts_hand_union.txt`):

```
== hand_union on Julia 1.10.12
return_types sumarea=Any[Float64] sum6=Any[Any] evaltree=Any[Int64]
@inferred sum6: NOT inferred: return type Float64 does not match inferred return type Any
bench sumarea 3-variant N=1e6: median 1.592 ms, allocs 0, memory 0 bytes
bench sum6 6-variant N=1e6: median 166.068 ms, allocs 3000000, memory 45.78 MiB
bench evaltree depth16: median 197.020 μs, allocs 0, memory 0 bytes
```

Excerpt (`$S/out/bench_lts_mlstyle.txt`):

```
bench evaltree depth16: median 4.977 ms, allocs 27166, memory 613.31 KiB
```

## Results: Julia 1.13.2

Command: `julia +release --startup-file=no --project=$S/envs/rel_<pkg> $S/defs/bench.jl <option>`.

| Option | infer `sumarea` | infer `sum6` | infer `evaltree` | allocs `sumarea` | allocs `sum6` | allocs `evaltree` | median `sumarea` | median `sum6` | median `evaltree` |
|---|---|---|---|---|---|---|---|---|---|
| hand, abstract + dispatch | Float64 | **Any** | Int64 | 0 | **2,000,000 (30.5 MiB)** | **15,079 (424 KiB)** | 2.82 ms | **267 ms** | 527 µs |
| hand, `Union` + dispatch | Float64 | Float64 | Int64 | 0 | 0 | 0 | 1.65 ms | 2.06 ms | 194 µs |
| hand, `Union` + `isa` chain | Float64 | Float64 | Int64 | 0 | 0 | 0 | 0.95 ms | 1.38 ms | 110 µs |
| Moshi 0.3.13 | Float64 | Float64 | Int64 | 0 | 0 | 0 | 1.95 ms | 1.99 ms | 153 µs |
| SumTypes 0.5.9 | Float64 | Float64 | Int64 | 0 | 0 | 0 | 1.78 ms | 2.50 ms | 194 µs |
| MLStyle 0.4.17 | Float64 | Float64 | Int64 | 0 | 0 | 0 | 3.07 ms | 2.16 ms | 123 µs |

Excerpt (`$S/out/bench_rel_moshi.txt`):

```
== moshi on Julia 1.13.2
eltype(v)=Main.Defs.Shape.var"typeof(Shape)" isconcretetype=true isbitstype=false summarysize(v)/N=24.0 B
return_types sumarea=Any[Float64] sum6=Any[Float64] evaltree=Any[Int64]
@allocated makevec(N) = 24002624
bench sumarea 3-variant N=1e6: median 1.952 ms, allocs 0, memory 0 bytes
bench sum6 6-variant N=1e6: median 1.986 ms, allocs 0, memory 0 bytes
bench evaltree depth16: median 153.083 μs, allocs 0, memory 0 bytes
```

Building the 10^6 vector (`@allocated makevec(N)`, both versions): hand abstract and MLStyle
about 34.7 MB (boxing), hand `Union` 17.0 MB, Moshi and SumTypes 24.0 MB.

## Compile latency / TTFX (median of 5 fresh processes, seconds)

| Option | 1.10 `using Pkg` (script) | 1.10 define+first run (script) | 1.10 precompile tiny pkg | 1.10 `using` tiny pkg | 1.10 first call in pkg | 1.13 `using Pkg` | 1.13 define+first (script) | 1.13 precompile | 1.13 `using` pkg | 1.13 first call |
|---|---|---|---|---|---|---|---|---|---|---|
| hand, abstract | 0 | 0.34 | 0.68 | 0.004 | 0.092 | 0 | 0.31 | 0.55 | 0.005 | 0.028 |
| hand, `Union` | 0 | 0.24 | 0.61 | 0.007 | 0.056 | 0 | 0.28 | 0.52 | 0.004 | 0.000 |
| Moshi | 0.27 | 4.13 | 2.42 | 0.19 | 0.000 | 0.29 | 7.90 | 3.49 | 0.10 | 0.000 |
| SumTypes | 0.20 | 1.88 | 1.59 | 0.085 | 0.000 | 0.11 | 1.16 | 0.85 | 0.21 | 0.000 |
| MLStyle | 0.22 | 2.69 | 2.55 | 0.28 | 0.043 | 0.12 | 3.69 | 2.05 | 0.16 | 0.012 |

Precompile is one run per cell. Individual runs: `$S/out/ttfx.txt`, `$S/out/pkg_ttfx.txt`.
Excerpt:

```
lts Moshi precompile_s=2.424
lts Moshi using_s=0.6474 first_run_s=0.0
lts Moshi using_s=0.3501 first_run_s=0.0
rel HandUnion precompile_s=0.518
rel HandUnion using_s=0.5253 first_run_s=0.0001
rel HandUnion using_s=0.0041 first_run_s=0.0
moshi 1.13.2 load_s=0.2881 define+first_run_s=7.8983
```

Reading: inside a precompiled package the macro libraries cost about 0.1 to 0.3 s of `using`
for every downstream load, and 1 to 3 s more precompile time for a module this small. The
hand-rolled module loads in under 10 ms. Moshi has the highest define-time cost (macro
expansion of `@data`/`@match`). Spread between runs is large (load averages 15 to 48).

## Capabilities (probes `$S/defs/probe_*.jl`, same results on 1.10.12 and 1.13.2)

| | hand-rolled | Moshi | SumTypes | MLStyle |
|---|---|---|---|---|
| Parametric ADT (`Maybe{T}`, `ExprF{A}`) | yes, ordinary parametric structs | yes, `@data ExprF{A}` | yes, `@sum_type ExprF{A}`, variants declare their params `Add{A}(::A,::A)` | yes, `@data ExprF{A}` |
| Variant that ignores the parameter (`Lit(Int)` in `ExprF{A}`) | `struct Lit; n::Int; end` needs no parameter at all | `ExprF.Lit(3)` -> `MethodError` ("0 methods for type constructor"); must write `ExprF.Lit{B}(3)` | `Lit(1)` gives `ExprF{Uninit}`, converted later with `convert(ExprF{Int}, ...)` | `Lit(3)` -> 0 methods; must write `Lit{B}(3)` |
| Nullary variant in a generic ADT | singleton struct | `None()` -> `Maybe.Type{Union{}}`, converts | `Nothing_` works | bare `Nothing_` errors: "Defining generic enum Nothing_ <: Maybe{T} is invalid"; `Nothing_()` works |
| Methods on the generated type (`fmap`) | yes | yes, on `ExprF.Type` | yes, on `ExprF` | yes |
| **Dispatch on an individual variant** (`fmap(f, ::Add)`) | **yes** | **no**: every value is `ExprF.Type{A}`; `x isa ExprF.Add` is `false`. A trampoline `_g(variant_type(x), x)` works but `variant_type` infers to a 3-way `Union{Type{Add{Int}},...}` | **no**: every value is `ExprF{A}`; only the (non-exported) `SumTypes.get_tag(x)::Symbol` | **yes**: `Add{Int} <: ExprF{Int}`; `h(::Add)` dispatches |
| Holy trait on the sum type | yes | yes (`FunctorStyle(::Type{<:E.Type})` returned `IsFunctor()`) | yes (ordinary struct) | yes |
| Two-parameter coproduct `Sum{F,G} = Inl(F) \| Inr(G)` | yes | yes, concrete `Sum.Type{Int,Float64}` | yes, concrete `Sum{Int,Float64}` | yes per docs (`@data B{T}` examples), not probed |
| Exhaustiveness check | none (a generated `isa` chain can end in `error`) | runtime only: `ErrorException("matching non-exhaustive")` when an unmatched value arrives | yes: a `@cases` missing a variant throws `Inexhaustive @cases specification ...` on the **first call of the method**, even for a matched value; definition itself succeeds | runtime only: `ErrorException("matching non-exhaustive, at ...")` |
| Recursive fixpoint `struct Fix; un::ExprF{Fix}; end` | yes (`Union` field) | yes, concrete | yes, concrete | yes, but field is abstract `ExprF{Fix}` |
| Open extension (downstream adds a variant) | yes for abstract; no for `Union` alias | no (closed) | no (closed) | yes (abstract supertype) |

Sources: the probe outputs pasted below; SumTypes README ("`@cases` can automatically detect if
you didn't give an exhaustive set of cases (with no runtime penalty) and throw an error");
Moshi's docs page data/syntax.mdx ("A singleton name is a type, not a value") and
Moshi's source match/emit/entry.jl line 31 (`Base.error("matching non-exhaustive")`); Context7
`/thautwarm/mlstyle.jl`, its syntax/adt.md docs page.

```
# probe_moshi.jl (1.13.2; 1.10.12 identical)
# 0 methods for type constructor            <- methods(ExprF.Lit)
y = MethodError(Main.ExprF.Lit, (3,), ...)
typeof(n) = Main.Maybe.var"typeof(Maybe)"{Union{}}
supertype(ExprF.Add) = Main.ExprF.Variant
x isa ExprF.Add = false
... = ErrorException("matching non-exhaustive")
# probe_dispatch_moshi.jl
Base.return_types(variant_type, (E.Type{Int},)) = Any[Union{Type{...Add{Int64}}, Type{...Lit{Int64}}, Type{...Neg{Int64}}}]
FunctorStyle(typeof(x)) = IsFunctor()
# probe_sumtypes.jl / probe_sumtypes2.jl
typeof(Defs.Lit(1)) = Main.Defs.ExprF{Uninit}
definition OK (no error at definition)
err = ErrorException("Inexhaustive @cases specification. Got cases (:X, :Y), expected (:X, :Y, :Z)")
# probe_mlstyle.jl
typeof(Defs.Add(1, 2)) = Main.Defs.Add{Int64}
h(Defs.Add(1, 2)) = :add
ERROR: ... Defining generic enum Nothing_ <: Maybe{T} is invalid, as Julia does not support generic value.
```

Recursion-scheme note (measured, Moshi): with `Lit` needing an explicit parameter, an `fmap`
that computes the target as `Base.promote_op(f, A)` produced `ExprF.Type{Union{}}` inside the
recursive `cata` closure and failed with `MethodError: no method matching evalalg(::ExprF.Type{Union{}})`.
The working encoding passes the carrier type explicitly: `cata(alg, ::Type{B}, x)` and
`fmap(f, ::Type{B}, e)`. MLStyle needs the same. SumTypes avoids it through `Uninit` plus
`convert`. Hand-rolled avoids it because `Lit` has no parameter and each `fmap` method returns
its own concrete struct.

## Findings

1. **Performance is a wash among the closed representations, and the hand-rolled `Union` +
   `isa` chain is at least as fast as any library on both versions.** Zero allocations and
   concrete inference for all three workloads, with the lowest medians in this run
   (1.10: 0.97 / 1.91 ms / 123 µs; 1.13: 0.95 / 1.38 ms / 110 µs). Source: tables above.
2. **Plain multiple dispatch over many variants is the trap, not hand-rolling as such.**
   With 6 variants, dispatch over an abstract supertype infers `Any` and boxes on both versions
   (2,000,000 allocs, about 250 ms vs 2 ms), consistent with `max_methods=3`. Dispatch over a
   6-way `Union` boxes on 1.10.12 (3,000,000 allocs, 166 ms) but not on 1.13.2. The same
   `Union` with an `isa` chain is clean on both. The 3-variant case was clean everywhere, so
   small examples hide the cliff. Why 1.13 handles the 6-way `Union` with the same
   `max_union_splitting=4`: UNVERIFIED.
3. **Moshi and SumTypes give a concrete container type**, 24 B per element here, with no
   boxing even through abstract-looking code, and zero allocations on both versions. That is
   their real advantage. The hand `Union` vector is also inline (17 B per element).
4. **MLStyle's `@match` compiles to type tests**, so even over an abstract container it did
   not allocate for 3 or 6 variants. But its recursive fold allocated on 1.10.12
   (27,166 allocs, 4.98 ms) and not on 1.13.2 (cause UNVERIFIED). Its last release is
   2023-02-13 with 53 open issues, and generic nullary variants need the `Nothing_()` form.
5. **Only hand-rolled and MLStyle let you dispatch on a variant.** Moshi and SumTypes values all
   share one Julia type, so `fmap(f, ::Add)` cannot be written. Every operation on them must be
   a `@match`/`@cases` over the whole sum. ChuiCore's typeclasses are Holy-trait plus dispatch,
   and data types à la carte needs open, per-functor instances (`fmap` for each injected
   functor), so this matters more than raw speed.
6. **Exhaustiveness checking exists only in SumTypes**, and fires at the first call of the
   method, not at definition. Moshi and MLStyle check only at runtime when an unmatched value
   arrives. Hand-rolled has none unless our macro generates it.
7. **Cost on every downstream load:** `using` the tiny packages took about 0.1 to 0.3 s with a
   library and under 10 ms hand-rolled, and precompile rose from about 0.5 s to 0.85 to 3.5 s.
   Moshi was the most expensive at define/precompile time. Dependency counts: MLStyle 0,
   Moshi 2, SumTypes 3 registered plus 4 stdlibs.
8. **Stability:** Moshi is the most active (release 2026-09-27) but its README says the API is
   "subject to change", and it already deprecated the bare singleton syntax (issue #22, per its
   docs). SumTypes is active (2026-09-03) and small. MLStyle is effectively in maintenance.

## Recommendation

**Hand-rolled in ChuiCore, with no ADT/pattern-matching dependency.** Concretely:

- Each variant is a plain (possibly parametric) struct. A variant that ignores the functor's
  parameter takes none (`struct Lit; n::Int; end`), so `fmap(f, ::Add)` and other typeclass
  instances are ordinary methods, which is what Holy traits and data types à la carte need.
- A closed sum is a `const ExprF{A} = Union{Lit, Add{A}, Neg{A}}`-style alias where a closed,
  inline, zero-allocation container matters. Use an abstract supertype only where downstream
  extension is the point.
- Hot matches over more than three or four variants are written, or generated by a small
  in-house macro, as an `isa` chain ending in an `error` branch. Plain dispatch is fine for
  small sums and for typeclass instances. A thin macro could also emit a variant list for a
  test-time exhaustiveness helper. Whether the macro is worth writing is a phase-2 call. It
  should be tested on 1.10 because of finding 2.
- ChuiFrames' optimizer, or any downstream package, may still choose Moshi or SumTypes for its
  own `@match`-heavy rewrite rules. ChuiCore should not force that cost on every package.

Trade-offs accepted:

- No library-grade nested pattern syntax (`Add(Lit(0), x) => x`). Rewrite rules are
  written as nested `isa` checks or dispatch. Moshi gives the best syntax for that and would be
  the choice if this ever moves into ChuiCore.
- No built-in exhaustiveness checking. SumTypes is the only option with it.
- Union-alias sums are closed. Open extension uses the abstract-supertype form and gives up
  concrete containers.
- If a concrete single-type container is required (for example many variants in one
  `Vector`), the cheapest library is SumTypes: smallest define/precompile cost of the three,
  converts phantom parameters for you, checks exhaustiveness. Its drawback is losing
  per-variant dispatch.

## UNVERIFIED

- Why a 6-way `Union` + dispatch boxes on 1.10.12 but not on 1.13.2, when both report
  `max_union_splitting=4, max_methods=3`.
- Why MLStyle's recursive `cata` allocated on 1.10.12 and not on 1.13.2.
- Why Moshi and SumTypes first calls inside a precompiled package took about 0 s (likely
  code compiled during precompile and cached in the pkgimage; not checked).
- MLStyle two-parameter coproduct: taken from docs, not run.
- Moshi issue #22 content: cited from Moshi's own docs, issue not opened.
- BenchmarkTools exact version in the scratch envs (not recorded).
- Moshi and SumTypes docs could not be fetched via Context7 (not indexed); claims about them
  come from installed README/docs/source and probes, not from the hosted docs sites.
- Absolute timings: load average 15 to 48 during the runs, so timings carry large noise.
  Allocation and inference results are not affected.

## Not run

- JET analysis of the variants.
- A larger `ExprF` (10+ variants, as a real plan optimizer would have) and a free-monad
  interpreter benchmark. The 6-variant `Op6` is the proxy.
- An actual in-house `@adt` macro prototype (only its expected output, the `isa` chain, was
  benchmarked as `hand_union_isa`).
- Invalidation counts (`SnoopCompile`) for loading each library.
