# Purity and effects

```@meta
DocTestSetup = :(using ChuiCore)
```

What "pure" means for ChuiCore's API, how an effect is **marked** (so a reader sees it) or
**isolated** (so it happens only when something runs it explicitly), and where the effect runtime
lives. ChuiCore supplies conventions and building blocks; **ChuiTypes owns the effect types
themselves** (an `IO`/ZIO-like value, its interpreter, cancellation, resource safety).

The evidence behind this page, including the `Base.infer_effects` runs on Julia 1.10.12 and
1.13.2, is the research note `docs/research/inspiration-effects.md` in the repository. The
convention is that note's proposal (§3); no ADR has changed it.

## Julia has no "pure" type

Julia's compiler infers several independent *effect bits* per call signature: `:consistent`,
`:effect_free`, `:nothrow`, `:terminates_globally` and others. Arithmetic is consistent,
effect-free and terminating, but `div` and `sin` may throw; a global read is effect-free but not
consistent; a recursive `fib` is not proven to terminate. Two facts make these bits unsuitable as a
library contract:

- `Base.infer_effects` is not public (1.13.2: `Base.ispublic(Base, :infer_effects) == false`).
- Its results change between versions: `push!` on a `Vector{Int}` infers conditional bits on 1.10
  and plain "no" on 1.13; `sum` gains a `!u` (may have undefined behaviour) bit on 1.13.

`Base.@assume_effects` goes the other way: an **unchecked promise** to the compiler, whose misuse
is undefined behaviour, and whose accepted settings differ by version (`:noub` is rejected on 1.10).

## ChuiCore's definition

A function is **pure** if, for `===`-equal arguments, it returns `==`-equal results, and it mutates
none of its arguments, no global state and no I/O.

This is deliberately weaker than the compiler's `:consistent`, which requires `===` results and so
rules out returning a fresh `Vector`: `ChuiCore.fmap(f, [1, 2])` allocates a new vector on every
call and is still pure here.

## Marking effects

1. **Every exported or public ChuiCore function is pure unless its name ends in `!` or its
   docstring has an `Effects:` line.** The `Effects:` lines in this package say, for example, that
   the `test_*_laws` kits record results in the current testset, that `foldxt` spawns tasks, that
   `conflict_banner` prints, and that the first `force` of a `Lazy` runs its thunk.
2. **Mutation is marked with `!`**, exactly as in Base (the mutated argument comes first; IO and
   RNG functions keep Base's exceptions, such as `rand`). There is no second marker.
3. **There is no purity trait.** An `ispure(f)` trait could not be checked, and the compiler's
   effect bits are internal and version-dependent. A downstream test may still assert an inferred
   effect for a specific function, guarded per Julia version: that tests a property rather than
   declaring one.
4. **ChuiCore itself does not use `Base.@assume_effects`.** Any future use needs a written
   justification at the site and the weakest setting that works.

A function argument keeps its own effects: `ChuiCore.fmap(f, xs)` is pure when `f` is. The
`Effects:` line describes what ChuiCore's code does, not what your callbacks do.

## Isolating effects

The common idea of the inspirations (John De Goes's ZIO, cats-effect's `IO`, Rúnar Bjarnason's free
monads) is that **an effect is a value that describes work, and running it is a separate,
explicit, late step**. ChuiCore applies that idea in two places, without defining an `IO` type.

**Deferred values.** A `Thunk` or `Lazy` holds work that runs only when `force`d. A `Thunk` runs it
on every `force`; a `Lazy` runs it once and memoises the result (thread-safe):

```jldoctest purity
julia> t = ChuiCore.Thunk(() -> (println("working"); 42));   # nothing printed yet

julia> ChuiCore.force(t)
working
42

julia> ChuiCore.force(t)    # a Thunk runs again
working
42

julia> l = ChuiCore.Lazy(() -> (println("once"); 1));

julia> ChuiCore.isforced(l)
false

julia> ChuiCore.force(l)
once
1

julia> ChuiCore.force(l)    # memoised: no second "once"
1
```

**Programs as data.** A free-monad program built with `ChuiCore.liftF` and `chain` performs no
effect; an interpreter (`ChuiCore.interpret`) runs it with handlers you choose, so the same program
can run against real I/O or against a pure test handler. See
[free monads and interpreters](../tutorials/free-monads.md).

**Name the boundary.** A function that *runs* an effect description is named `run…` or
`interpret…`, or ends in `!` if it mutates handler state: the "end of the world" from cats-effect,
made visible in the name.

## What it costs

- Marking (names, `Effects:` lines) costs nothing at run time.
- A `Thunk` is a struct holding a function; forcing it is one call.
- A `Lazy` allocates a cell and a lock when built; a forced read is an atomic load plus a field
  read. Measured figures are on each docstring ([`ChuiCore.Lazy`](@ref ChuiCore.Lazy)).
- An interpreted free-monad program pays per instruction (an allocation per instruction plus
  dynamic dispatch); see [`ChuiCore.Free`](@ref ChuiCore.Free) and the [cost model](cost-model.md).

## Where the rest lives

| Concern | Package |
|---|---|
| The definition of pure, `!`, `Effects:` lines, deferred values, free monads, Monad/Traversable traits | ChuiCore |
| Effect types (environment, error, result), their runtime and interpreters, cancellation, resources | ChuiTypes |
| I/O of data frames, built on ChuiTypes' effects | ChuiFrames |
