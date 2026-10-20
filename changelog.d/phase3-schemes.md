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
- `test/runtests.jl` no longer runs test items from `.lanes/` or `.worktrees/` below the package
  root.
