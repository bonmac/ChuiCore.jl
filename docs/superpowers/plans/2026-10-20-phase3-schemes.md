# Phase 3 plan: transducers, recursion schemes, free monads, laziness, optics, banner

- **Date:** 2026-10-20. **Branch:** `feat/phase3-schemes` (from main 20f5c14). **Tier:** T2 (public
  API, a new hard dependency). **Spec:** the accepted phase-1 design
  (`docs/superpowers/specs/2026-10-20-phase1-research-design.md`) and ADRs 0001–0008.
- **Binding inputs:** ADR-0003 (transducers), ADR-0004 (optics), ADR-0008 (ConstructionBase now),
  ADR-0002 (ADTs), ADR-0005 (tiers); ecosystem ADR-0012 (P2 `isstateless` obligation, P6);
  `docs/research/{transducers,optics,recursion-schemes-free-laziness}.md`; the open requests R3, R5,
  R6, R7, R9 (coordinator `requests/`).
- **Out of scope (deferred, reported):** `ChuiCoreTransducersExt` (ADR-0003 §8; needs Transducers.jl
  in the test environment, 20 transitive deps; no consumer asks for it yet), `eduction`, a
  stack-safe iterative `cata`, a typed `Cofree` for `histo`. Phase 4: time budgets, TTFX.

## Layout (ADR-0005: one module, files by area; every new name public, not exported)

| File | Owner | Content |
|---|---|---|
| `src/ChuiCore.jl`, `src/names.jl`, `src/laws.jl`, `Project.toml`, `test/Project.toml` | lane lead | includes, imports, `@compat public` list, kit stubs, deps |
| `src/transducers/{transducers,folds}.jl`, `test/transducers_*.jl` | sub-lane `p3-xf` | ADR-0003 |
| `src/schemes/{schemes,free}.jl`, `test/schemes_*.jl`, `test/free_*.jl` | sub-lane `p3-schemes` | recursion schemes; Coproduct, free monad |
| `src/optics/optics.jl`, `ext/ChuiCoreAccessorsExt.jl`, `test/optics_*.jl` | sub-lane `p3-optics` | ADR-0004, ADR-0008 |
| `src/lazy.jl`, `src/banner.jl`, `test/lazy_*.jl`, `test/banner_*.jl` | sub-lane `p3-lazy` | laziness; the conflict banner |
| `src/classes/core.jl`, `src/algebra/*.jl` docs | lane lead | review nits N2, N4, N5 |

Sub-lanes build in scratch copies of the branch under `.lanes/scratch/<lane>/` (gitignored), so a
half-written file in one lane never breaks another lane's test run. The lead copies each lane's new
files back and merges the shared files (`ChuiCore.jl`, `names.jl`, `laws.jl`, `Project.toml`,
`test/Project.toml`) by hand.

## API fixed here (the ADRs left these to phase 3)

### Transducers (ADR-0003)

- v1 set: `Map{F}`, `Filter{P}`, `MapCat{F}`, `Take`, `TakeWhile{P}`, `Scan{F,T}(op, init)`,
  `Partition{T}(n)` (`Partition(n) = Partition{Any}(n)`; emits `Vector{T}` copies, flushes the
  remainder on `complete` unless downstream reduced), `Composed{T<:Tuple}`. No call methods.
- `asrf(xf, op)` → `R{X,Inner}` / `Bottom{F}` structs. Protocol `start`, `next`, `complete`;
  `Reduced{T}`, `reduced`, `unreduced`, `isreduced`. State in the accumulator (an internal wrapper).
- `a ⨟ b` through `Base.:∘(b::Transducer, a::Transducer)`, flattening into one `Composed`.
- `isstateless(_) = false`; `true` for `Map`, `Filter`, `MapCat` and `Composed` of only those.
- `foldxl(op, xf, itr; init)`; `foldparts(op, xf, parts; init, merge)`;
  `foldxt(op, xf, v::AbstractVector; init, merge, ntasks = Threads.nthreads())`;
  `aggregate(agg, xf, parts)` (the name stays; R7 uses it).

### Recursion schemes

- Encoding (R6 "still open", decided here): schemes run over **any value whose type has a Functor
  instance** (`fmap` registered through `constructorclass`), via `project(x)` (default: `x` itself,
  so a downstream node type is its own base functor and is never rewrapped) and an `embed` keyword
  (default `Fix`). `Fix(layer)` wraps a layer (field `Any`, never concrete: research A1);
  `project(::Fix)` unwraps.
- `cata(alg, x)`, `ana(coalg, seed; embed = Fix)`, `hylo(alg, coalg, seed)`, `para(alg, x)` (each
  child is the tuple `(original, result)`, `original === ` the input subtree), `apo(coalg, seed;
  embed = Fix)` (holes `Done(tree)` or `More(seed)`), `histo(alg, x)` (holes `Attr(value, layer)`),
  `futu(coalg, seed; embed = Fix)` (holes `More(seed)` or `Emit(layer)`); monadic `cataM(tag, alg,
  x)`, `anaM(tag, coalg, seed; embed = Fix)`, `hyloM(tag, alg, coalg, seed)` (base functor must be
  Traversable).

### Free monads and data types à la carte

- `Coproduct{F,G}` with variants `Inl{F,G}`, `Inr{F,G}`; `inj(::Type{S}, x)`, `prj(::Type{T}, x)`
  (`Some(x)` / `nothing`). Swierstra's names, not `project`, which the recursion schemes use.
- Freer encoding (research recommendation 5): `Pure(x)`, `Impure(op, k)` with a continuation tree;
  `liftF(op)`; Functor/Applicative/Monad instances on `FreeTag()`; the interpreter
  `interpret(handler, m)` is a loop (trampoline); `foldfree(tag, nt, m)` into a target monad.

### Laziness (R5)

- `Thunk(f)` (no memo); `Lazy{T}(f)` / `Lazy(f)` memoised and thread-safe (at most one evaluation,
  also under concurrent `force`; a throwing body is cached and rethrown); `force`, `isforced`,
  `@lazy expr`; Functor/Applicative/Monad instances on `LazyTag()` (deferred).

### Optics (ADR-0004)

- `Lens{L}()` (property; `Lens(:a)` is the type-unstable runtime form), `IndexLens`, `@lens`,
  `Prism(match, build)`, `Prism(T)` (variant prism), `preview`, `review`, `set`, `modify`.
- New kits `test_lens_laws(lens, gen_s, gen_v)`, `test_prism_laws(prism, gen_s, gen_v)`, exported
  (kit stubs are the exported tier), with planted violations under both drivers.
- ConstructionBase "1.6" is a hard dependency; `ChuiCoreAccessorsExt` (Accessors "0.1.45").

### Banner (R9)

- `binding_conflicts(mod)::Vector{Pair{Symbol,Vector{Module}}}`, `conflict_banner(io, mod)`,
  silenced by `CHUI_QUIET_CONFLICTS=1|true`; covers modules loaded before the call.

## Review nits carried from phase 2

- N5: mismatched classes in `alt`/`ap`/`chain` give an `ArgumentError` (fallback methods on the `Is…`
  style). N2: document that `Sum`/`Prod`/`Mean` take scalar elements. N4: carried (a tag-level
  trait cannot see tuple length; `bimap` throws an `ArgumentError`, documented).

## Tasks (test-first)

1. Lead: this plan; scratch copies; dispatch four sub-lanes in parallel.
2. Sub-lanes: failing tests, implementation, laws (phase-2 kits where they apply), request
   reproducers as test items.
3. Lead: merge, nits, clash list, quality/JET/format/guards/docs, changelog, HANDOFF; reviewer on
   the full diff until its final verdict.
