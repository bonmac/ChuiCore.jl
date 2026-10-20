# Changelog

All notable changes to this package are recorded here, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/).
Every PR adds a changelog entry (checked by `scripts/dod.jl`): a lane adds a new
`changelog.d/<lane>.md` fragment, which `julia scripts/changelog.jl fold` moves under
`## Unreleased` at release; a change outside lanes may edit `## Unreleased` directly. Breaking
changes carry migration notes.

## Unreleased

## [0.0.1] - 2026-10-20

First snapshot release (an ecosystem ADR-0004 0.0.x snapshot, registered in ChuiRegistry so that
downstream Chui packages can depend on a released ChuiCore; v0.1.0 follows). Entries are in the
order the work landed, from the scaffold through phases 1–5.

- Vendored the ecosystem factory template 0.2.1 (see `.factory-version`).
- The `ChuiCore` package scaffold (`julia = "1.10"`), MIT license.
- TestItemRunner test suite with a module-load item and Aqua / ExplicitImports quality items.
- Minimal Documenter skeleton in `docs/`.
- ChuiCore's own name-conflict banner (the brief's "Name-conflict banner, like dplyr"): in an
  interactive session, `using ChuiCore` prints the exported names that clash with Base or with
  already-loaded modules, to `stderr`. It fires on any interactive load of ChuiCore (also
  `import ChuiCore`, or as a dependency of another package). Silent in non-interactive runs and
  when `CHUI_QUIET_CONFLICTS` is `1`/`true`. A failing banner (for example a read-only `stderr`,
  even with `JULIA_DEBUG=ChuiCore` logging the failure to it) never breaks the load; Ctrl-C
  still interrupts it. `__init__` calls it
  through `invokelatest`, so non-interactive load time is unchanged (ADR-0009); an interactive
  load pays about 0.25–0.3 s to compile and run the banner.
- The `conflict_banner` docstring and the conflict-banner tutorial show the recommended
  downstream `__init__` (interactive only, `invokelatest`, inside `try`), and the tutorial
  documents ChuiCore's own banner and its load-time cost.
- The `binding_conflicts` docstring example passes when doctests run twice in one process
  (review nit N6): it no longer assumes that only its own modules are loaded.
- Synced the ecosystem factory template 0.2.1 -> 0.2.4 (see `.factory-version`): changelog
  fragments in `changelog.d/`, `scripts/check_claims.jl`, `scripts/evidence.jl`, the split
  `bash_guard` helpers, a wider T3 protected-path list in `risk.toml`, and a lane cap of 6.
- Refreshed `docs/agent/ECOSYSTEM.md` and `docs/agent/BRIEF.md` from coordinator commit ff0100a.
- Synced the ecosystem factory template 0.2.4 -> 0.2.5 (see `.factory-version`): checks that
  agree in a fresh clone (check_docs accepts gitignored paths, hermetic gen and hook tests) and
  Runic-formatted factory scripts, fixing the first GitHub CI runs of Guards and Runic.
- Synced the ecosystem factory template 0.2.5 -> 0.2.6 (see `.factory-version`): lanes that work in
  their own worktrees; `JuliaTestItems.toml` also excludes `.claude/worktrees/` and `.superpowers/`;
  testing notes for Supposition `record=false db=false`, the LTS manifest and a gitignored `test/SuppositionDB/`.
- Phase 1 (Research and ADRs): verified research notes in `docs/research/` and ADRs 0001–0007
  (Proposed) on the typeclass encoding, ADTs, the transducer substrate, optics, module layout and
  export tiers, the CompositionsBase dependency, and law-kit packaging; summary spec
  `docs/superpowers/specs/2026-10-20-phase1-research-design.md`. No code changes.
- ADRs 0001–0008 and the phase-1 spec accepted by the user at the phase-1 ★ (2026-10-20); ADRs
  0005, 0006 and 0007 depend on pending coordinator amendments (ecosystem ADR-0009, CC-001,
  ecosystem ADR-0007 §2).
- Phase 2 (traits and law kits): `⨟`/`opcompose` re-exported from CompositionsBase (ADR-0006);
  composition helpers `pipe`, `papply`, `flip` (exported) and `ChuiCore.curry`; the three name
  tiers of ADR-0005 with a clash-list check in its own environment (`test/exports/`).
- `neutral`, `curry`, `fmap`, `pure` and `ap` are public, not exported: the clash rule (ADR-0005
  §2) forbids exporting them because TypeClasses 1.1.0 exports `neutral`, `curry`, `pure`, `ap`
  (and `combine`, `Identity`) and Functors 0.4.12 exports `fmap` (probe on Julia 1.13.2; lead's
  decision 2026-10-20).
- Law kits (ADR-0007): 14 exported `test_*_laws` stubs, with `ChuiCoreTestExt` (sample collections)
  and `ChuiCoreSuppositionExt` (generators; `@check record=false db=false` plus an explicit
  `@test`), and a planted violation per law under both drivers, run on Julia 1.10.
- Aggregation protocol and monoid family (CC-004…CC-007, ADR-0001 §1–2): public `init`, `partial`,
  `combine` (3-argument only), `final`, `iscommutative`, `neutral` (fresh on every call),
  `default_monoid`, the dispatch-only trait `AlgebraClass` (`IsSemigroup`, `IsMonoid`,
  `NotAlgebra`) and its consumer `combineall`; the built-in aggregators `Sum`, `Prod`, `Count`,
  `CountTrue`, `AnyM`, `AllM`, `Max`, `Min`, `Extrema`, `First`, `Last`, `Mean`,
  `Moments(stat = :var; corrected = true)`, `ReduceM(op; neutral, commutative = false)` and
  `MapM(f, inner)`, with CC-006's empty-input results and exception types on every Julia;
  `default_eq` gives CC-004's float tolerance `≈ᵃ` for the built-ins.
- Constructor classes (ADR-0001 §3–4): `constructorclass` tags, dispatch-only `*Style` traits for
  Functor through Arrow, the operations (`fmap`, `ap`, `chain`, `alt`, `contramap`, `bimap`,
  `dimap`, `lmap`, `rmap`, `arrfirst`, `arrsecond`, `arrsplit`, `fanout`; tag-first `pure`,
  `zeroalt`, `idarrow`, `arr`, `traverse`, `sequence`), instances on Maybe (`Some`/`nothing`),
  `Array`, `Tuple`, `Dict`, `Pair` and `Function`, and the owned types `Identity`, `ZipVector`
  and `Predicate`.
- New dependencies: Compat, CompositionsBase; weak dependencies Test, Supposition.
  ConstructionBase (ADR-0008) is deferred to phase 3, when optics use it.
- Phase 3 (plan `docs/superpowers/plans/2026-10-20-phase3-schemes.md`): the transducer substrate,
  recursion schemes, data types à la carte and a freer monad, laziness, optics and the
  name-conflict banner. Every new name is public, not exported, except the two new law kits.
- Transducer substrate (ADR-0003; requests R3, R7), public and not exported:
  `ChuiCore.Transducer` and the v1 transducers `Map`, `Filter`, `MapCat`, `Take`, `TakeWhile`,
  `Scan(op, init)`, `Partition{T}(n)` (`Partition(n) = Partition{Any}(n)`; flushes its remainder on
  completion unless the downstream has stopped) and `Composed`; `a ⨟ b` means "a, then b" and
  equals `b ∘ a`. Transducers have no call method.
- Reducing functions are structs built by `asrf(xf, op)` (`R`, `Bottom`, public so downstream
  packages can write transducers), driven by the protocol `start`, `next`, `complete` (completion
  runs exactly once per fold, also after early termination); early termination by `Reduced`,
  `reduced`, `unreduced`, `isreduced`. Per-fold state lives in the accumulator, so a transducer
  such as `Take(3)` can be reused across folds.
- Folds: `foldxl(op, xf, itr; init)` (sequential, any iterable); `foldparts(op, xf, parts; init,
  merge)` over pre-partitioned input (`init` a factory, `merge` required, merged in partition
  order, one task per partition, waits for every task; a partition's exception surfaces as a
  `TaskFailedException`); `foldxt(op, xf, v::AbstractVector; init, merge, ntasks)` over contiguous
  views (no input copy; other iterables throw `ArgumentError`); `aggregate(agg, xf, parts)` over
  the CC-004 aggregator protocol. Per-partition results are defined only when a `Reduced` returned
  by `op` depends on the element alone, not on the accumulator.
- `isstateless(xf)` is fail-closed (`false` by default; `true` only for `Map`, `Filter`, `MapCat`
  and their compositions): any other pipeline runs sequentially in `foldparts`, `foldxt` and
  `aggregate` (ecosystem ADR-0012 P2).
- Stateless `foldxl` over a vector is inferred and allocates 0 bytes on Julia 1.10 and 1.13.
- Recursion schemes (request R6; public, not exported): `ChuiCore.cata`, `ana`, `hylo` (fused, no
  intermediate structure), `para` (each child is `(original, result)`, `original ===` the input
  subtree), `apo` (holes `Done(tree)` / `More(seed)`), `histo` (holes `Attr(value, layer)`),
  `futu` (holes `More(seed)` / `Emit(layer)`) and the monadic `cataM`, `anaM`, `hyloM` (the base
  functor must be Traversable). They run over any value whose type has a Functor instance,
  through `project(x)`: a downstream node type is its own base functor and is traversed without
  rewrapping; `Fix(layer)` (field `Any`, structural equality) wraps layers for generic code, and
  the unfolds take `embed = Fix` (or `identity`). Every docstring states its cost and the stack
  limit (recursive: a linear structure overflows between about 10^4 and 4×10^4 levels).
- Data types à la carte: `ChuiCore.Coproduct{F,G}` with `Inl`/`Inr`, `inj(S, x)` (reflexive,
  nested right; one method, no ambiguities) and `prj(T, x)` (`Some(x)` or `nothing`); a Functor
  and Traversable instance (`CoproductTag()`) delegating to the payload.
- A freer monad: `ChuiCore.Free` programs `Pure(x)` / `Impure(op, k)` with an O(1)-bind
  continuation tree, `liftF(op)` and `liftF(S, op)`, Functor/Applicative/Monad instances on
  `FreeTag()`; `interpret(handler, m)` is a loop (stack-safe at 10^6 instructions, linear in
  left-associated binds), `cohandler(hf, hg, ...)` combines handlers for a `Coproduct`
  signature, and `foldfree(tag, nt, m)` interprets into a target monad (recursive: documented
  stack depth). For describing programs, not inner loops.
- Optics (ADR-0004, ADR-0008), all public and not exported: `ChuiCore.Lens{:a}()` (property lens,
  also `Lens(:a)` and `Lens(Val(:a))`), `ChuiCore.IndexLens(i...)`, the `ChuiCore.@lens _.a.b[2]`
  macro, `ChuiCore.Prism(match, build)` and the variant prism `ChuiCore.Prism(T)` for closed sum
  types, `ChuiCore.preview`, `ChuiCore.review`, and `ChuiCore.set(x, optic, v)` /
  `ChuiCore.modify(f, x, optic)` in Accessors' argument order. Lenses compose with Base's `∘`/`⨟`;
  `set`/`modify` also accept compositions that contain a prism. Type-parameterised lenses get and
  set with 0 bytes allocated.
- ConstructionBase (`[compat] 1.6`) is a new hard dependency: structs are rebuilt through
  `ConstructionBase.setproperties`, the same hook Accessors uses. Types with a non-default inner
  constructor or a phantom type parameter need their owner to define
  `ConstructionBase.constructorof`.
- New exported law kits `test_lens_laws(lens, gen_s, gen_v)` (get-set, set-get, set-set) and
  `test_prism_laws(prism, gen_s, gen_v)` (review-preview, preview-review), for sample collections
  and Supposition generators, with planted violations under both drivers.
- New package extension `ChuiCoreAccessorsExt` (weak dependency Accessors, `[compat] 0.1.45`):
  ChuiCore lenses and prisms work in `Accessors.set`/`Accessors.modify` (lenses also inside
  Accessors compositions and `@set`; prisms only alone), and `ChuiCore.set`/`ChuiCore.modify`
  accept Accessors' `PropertyLens` and `IndexLens`, alone or composed with ChuiCore optics.
- Laziness (request R5): `ChuiCore.Thunk` (no memo) and `ChuiCore.Lazy{T}(f)` / `Lazy(f)`, a
  memoised deferred value that is thread-safe by default (the body runs at most once, also under
  concurrent `force`; a throwing body's exception is cached and rethrown; a body that forces its own
  `Lazy` throws an `ArgumentError`; the closure is dropped after evaluation). `ChuiCore.force`
  (the identity on non-lazy values), `ChuiCore.isforced`, `ChuiCore.@lazy expr`, and deferred
  Functor/Applicative/Monad instances on `ChuiCore.LazyTag()`. Works on Julia 1.10.
- Name-conflict banner (request R9): `ChuiCore.binding_conflicts(mod)` lists, per name `mod`
  exports, the other loaded modules that export a different binding of it (re-exports and `Base`
  method extensions are not conflicts); `ChuiCore.conflict_banner(io, mod)` prints them, silenced
  by `CHUI_QUIET_CONFLICTS=1` or `true`. Intended for
  `__init__() = isinteractive() && ChuiCore.conflict_banner(stderr, @__MODULE__)`; it covers
  modules loaded before the call.
- **Behaviour change** (phase-2 review nit N5): mismatched classes in `ap`/`alt`
  (`ap([f], Some(1))`) now throw an `ArgumentError` instead of a `MethodError`. Downstream instance
  methods must type the style argument (`ap(::IsApplicative, ff::T, fx::T)`): a method written
  with an untyped style is ambiguous with the new fallback.
- `Sum`, `Prod` and `Mean` document that they take scalar elements, with `ReduceM` for vectors
  (nit N2). N4 (`BifunctorStyle` on tuples that are not 2-tuples) is unchanged: a tag-level trait
  cannot see a tuple's length, and `bimap` throws a documented `ArgumentError`.
- A root `JuliaTestItems.toml` (`exclude = ["/.lanes/", "/.worktrees/"]`) keeps TestItemRunner
  out of lane scratch copies and nested worktrees: their files are never parsed, so a stale
  `@testmodule` there cannot shadow a real one and a malformed file there cannot abort the run
  (a test proves it on a toy package, with a control run that fails without the file).
  `test/Project.toml` requires `TestItemRunner = "1.3.2"`, the version verified to read it;
  `test/runtests.jl` also skips test items under those directories.
- Phase 4 (performance pass): JET clean at the `ci.jl jet` strictness (it already was at
  b4f1ca3; no source change needed). ADR-0009 (Proposed) sets the budgets: allocation budgets
  asserted in `test/perf_allocs_tests.jl` (aggregators, transducer folds, recursion schemes,
  composition: 0 B on the hot paths), per-version time budgets in `benchmark/budgets.toml`
  (`benchmark/run.jl --check`), and load/TTFX/precompile budgets (`benchmark/ttfx.jl --check`).
- New hard dependency PrecompileTools (`"1.2"`, ADR-0010, Proposed): a precompile workload in
  `src/precompile.jl` cuts load + first call from 230 to 47 ms on Julia 1.13.2 and from 247 to
  69 ms on 1.10.12 (interleaved A/B, loaded machine). Costs: `using ChuiCore` ≈23–26 ms slower,
  precompile ≈0.84 → 1.6 s (1.13) and 0.88 → 1.4 s (1.10). `test/precompile_tests.jl` (`:slow`)
  checks that the TTFX workload compiles no ChuiCore method after load.
- Benchmark suite `benchmark/benchmarks.jl` (a BenchmarkTools `SUITE`, runnable by
  AirspeedVelocity and `scripts/ci.jl bench`), with `benchmark/Project.toml`, and
  `benchmark/allocs.jl` printing the allocation figures; results, losses
  included, in the new docs page `docs/src/performance.md`.
- Phase 5 (docs): a Documenter site in the ecosystem ADR-0008 layout. Tutorials, each a worked,
  doctested example: composition; monoids and aggregators (with CC-006's empty-input semantics);
  typeclasses and writing your own instance (style-typed methods, rule N5); law kits for
  downstream packages (the Supposition `record=false db=false` rule and why); transducers (with
  `foldparts` and the S1 per-partition caveat); recursion schemes over your own node type; free
  monads and an interpreter; optics; laziness; the conflict banner. How-to recipes. Explanation
  pages: why ChuiCore, purity and effects, export tiers and the clash list (why `neutral`,
  `curry`, `pure`, `ap` and `fmap` are public but not exported), the runtime cost model, and the
  phase-4 performance page. The reference is split into eight pages, with contract IDs marked.
  A changelog page is generated from `CHANGELOG.md` at build time.
- Every exported and public name owned by ChuiCore has a docstring with a `jldoctest` and a
  runtime-cost statement; effectful functions carry an `Effects:` line (docstring edits only, no
  behaviour change).
- Tests: a `:doctest` item (`test/doctest_tests.jl`) runs `Documenter.doctest` over the
  docstrings and `docs/src` on stable Julia; a `:quality` item fails when an owned public name
  lacks a `jldoctest` (unless listed in `docs/doctest-exemptions.md`) or a cost statement.
  Documenter joins `test/Project.toml`; Accessors, Supposition and Test join `docs/Project.toml`.
  The cost check accepts only the cost forms the docstrings use (`Cost:`, `**Cost:**`,
  `Cost (indicative):`, `Cost as`, `Runtime cost:`), and the doctest check needs a
  ```` ```jldoctest ```` block, not just the word.
- Law-kit examples (the kit docstrings, the law-kits, monoids and typeclasses tutorials) send the
  test summary to `devnull` and show `Test.anynonpass(ts)` and the laws run, instead of filtering
  the summary out of the comparison: that filter also deleted the error, so a failing law passed
  its doctest. A failing law now fails the doctest (checked with planted broken instances).
- `ChuiCore.next` and `ChuiCore.complete` carry an `Effects:` line: a stateful layer such as
  `Partition` mutates the per-fold state inside the accumulator that `start` created.
- Error-message wording: the constructor-class errors now say "is not an Applicative",
  "an Alternative", "an Arrow" (they said "a Applicative" etc.); message text only, the
  exception type (`ArgumentError`) is unchanged.
- The tag and style docstrings of the constructor classes moved to a docstrings-only file,
  `src/classes/style_docs.jl` (with the internal tables `_TAG_DOCS` and `_CLASS_EXAMPLES` that
  generate their examples), keeping `src/classes/core.jl` under the 600-line ratchet; the type and
  method definitions stay in `core.jl`, unchanged.
- README: installation (ChuiRegistry once registered; by URL or local clone until then), a quick
  example, links.
- Test harness: `test/runtests.jl` skips the version-dependent `:doctest` and `:snapshot` items
  by Julia version (`STABLE_MIN = v"1.13"`, ecosystem ADR-0008 §3) when `CI_STABLE` is unset,
  so a plain `]test` of a fresh clone passes on Julia 1.10 too. `CI_STABLE=true`/`false` still
  overrides it either way, and CI is unchanged (it sets `CI_STABLE` on every job).
