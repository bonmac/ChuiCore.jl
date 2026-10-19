# Purity and effects: what Julia offers, what the inspirations do, and a ChuiCore convention

Recorded 2026-10-20 by the phase-1 `researcher` lane (ChuiCore, Research and ADRs). Status: research
note, input to an ADR; the convention below is a proposal. **ChuiTypes owns the effect runtime**
(effect types, IO, interpreters); ChuiCore only documents what "pure" means and how code marks or
isolates effects.

Julia versions: `julia +lts` = 1.10.12, `julia +release` = 1.13.2 (juliaup, `--startup-file=no`).
The prototype script (`lazy_effects.jl`) ran from the lane's session scratchpad, which is not kept;
the test functions are reproduced below.

## Question

What does "pure" mean in Julia? (`Base.@assume_effects` settings and `Base.infer_effects` on 1.10 vs
1.13.) What are the functional-effect models of John De Goes / ZIO, cats-effect `IO` and Bjarnason's
free monads? What should ChuiCore's convention be for marking vs isolating effects?

## 1. Julia: purity is a compiler-inferred effect lattice, not a type

### `Base.@assume_effects` settings

Source: Julia manual, `Base.@assume_effects` (Context7 `/websites/julialang_en_v1`, i.e.
docs.julialang.org/en/v1, fetched 2026-10-20), plus the local docstrings.

- Settings listed in the current docs: `:consistent`, `:effect_free`, `:nothrow`,
  `:terminates_globally`, `:terminates_locally`, `:notaskstate`, `:inaccessiblememonly`, `:noub`,
  `:noub_if_noinbounds`, `:nortcall`, and the composites `:foldable`, `:removable`, `:total`. A `!`
  prefix negates a setting (`:total !:nothrow`).
- `:consistent`: for egal (`===`) inputs, the method terminates the same way every time and returns
  egal results. This implies it must not return freshly allocated mutable objects and must not
  depend on global or heap state that varies within the world-age range. Fastmath is *not*
  consistent.
- `:effect_free`: no externally visible side effects. The docs give an incomplete list: changing a
  global, mutating the heap, changing the method table (`eval`), I/O, task switching.
- `:noub`: no undefined behaviour. `:terminates_locally` covers only the method's own control flow;
  `:terminates_globally` implies it.
- Version notes from the docs: the macro needs 1.8; use inside a function body needs 1.10; on a
  code block it needs 1.11. Warning: "Improper use of this macro causes undefined behavior …
  minimize the strength of the effect assertion."

Which settings each version **accepts** (command: `eval(Meta.parse("Base.@assume_effects :$s g_$s() = 1"))`
for each `s`):

```
1.10.12: :noub REJECTED, :nortcall REJECTED, :noub_if_noinbounds REJECTED;
         :foldable :removable :total :notaskstate :inaccessiblememonly accepted
1.13.2:  :noub accepted, :noub_if_noinbounds accepted, :nortcall REJECTED
         ("`@assume_effects :nortcall` not supported");
         :foldable :removable :total :notaskstate :inaccessiblememonly accepted
```

(`:terminates_globally` was used in the effects run below and accepted on both.) Setting names
scraped from the local docstring: 1.10.12 lists total, nothrow, consistent, effect_free,
terminates_globally, terminates_locally, notaskstate, inaccessiblememonly, foldable, removable;
1.13.2 adds noub, noub_if_noinbounds, nortcall. On 1.13.2 `:nortcall` appears in the docstring but
the method-annotation form rejects it.

Public status (1.13.2, `Base.ispublic`): `@assume_effects` → `true`; `infer_effects` → **`false`**.
`Base.ispublic` does not exist on 1.10. `infer_effects` is therefore a reflection tool for tests and
investigation, not an API to build on.

### `Base.infer_effects`, 1.10.12 vs 1.13.2

Test functions: `const G = Ref(1)`; `gread() = G[]`; `gwrite!(x) = (G[] = x; nothing)`;
`mysum(v) = sum(v)`; `fib(n) = n < 2 ? n : fib(n-1) + fib(n-2)`;
`Base.@assume_effects :terminates_globally fib_assumed(n) = …same…`. Command:
`Base.infer_effects(f, argtypes)`, `-t 4`. Output:

```
call                     1.10.12 (c,e,n,t,s,m,i)     1.13.2 (c,e,n,t,s,m,u,o,r)
+(Int,Int)               (+c,+e,+n,+t,+s,+m,+i)      (+c,+e,+n,+t,+s,+m,+u,+o,+r)
sin(Float64)             (+c,+e,!n,+t,+s,+m,+i)      (+c,+e,!n,+t,+s,+m,+u,+o,+r)
div(Int,Int)             (+c,+e,!n,+t,+s,+m,+i)      (+c,+e,!n,+t,+s,+m,+u,+o,+r)
push!(Vector{Int},Int)   (?c,?e,!n,+t,+s,?m,+i)      (!c,!e,!n,+t,+s,!m,+u,+o,!r)
gread()                  (!c,+e,+n,+t,+s,!m,+i)      (!c,+e,+n,+t,+s,!m,+u,+o,+r)
gwrite!(Int)             (+c,!e,+n,+t,+s,!m,+i)      (+c,!e,+n,+t,+s,!m,+u,+o,+r)
sum(Vector{Float64})     (!c,+e,!n,!t,+s,!m,+i)      (!c,+e,!n,!t,+s,?m,!u,+o,+r)
fib(Int)                 (+c,+e,+n,!t,+s,+m,+i)      (+c,+e,+n,!t,+s,+m,+u,+o,+r)
fib_assumed(Int)         (+c,+e,+n,+t,+s,+m,+i)      (+c,+e,+n,+t,+s,+m,+u,+o,+r)
rand()                   (!c,!e,!n,!t,!s,!m,+i)      (!c,!e,!n,!t,!s,!m,!u,+o,!r)
```

Flag key: `fieldnames(Core.Compiler.Effects)` on 1.10.12 is `(consistent, effect_free, nothrow,
terminates, notaskstate, inaccessiblememonly, nonoverlayed, noinbounds)`. On 1.13.2
(`Base.Compiler.Effects`) it is `(…, inaccessiblememonly, noub, nonoverlayed, nortcall)`. The 1.13.2
docstring of `infer_effects` gives the printed order c, e, n, t, s, m, u, o, r, with `+` = always
true, `!`/`-` = false, `?` = conditional (e.g. `?m` = inaccessible-or-argument-memory-only). The
1.10 printer's trailing `i` is presumably `noinbounds` (inferred from `fieldnames`; UNVERIFIED).

Findings:

- Julia's notion of "pure" is **several independent bits** inferred per call signature. Arithmetic
  is `consistent + effect_free + terminates` but `div`/`sin` may throw (`!n`). A global read is
  `effect_free` but not `consistent`. A recursive function is not proven to terminate (`fib`: `!t`)
  until annotated, and the annotation is an unchecked promise.
- The results **change between versions** (`push!`: conditional `?c,?e,?m` on 1.10, `!c,!e,!m` on
  1.13; `sum` gains `!u` on 1.13). Effect bits are compiler internals and are not stable enough to
  encode a library contract.
- The Julia-wide marker for mutation is a **naming convention**, not a type. Style guide (Context7,
  docs.julialang.org/en/v1/manual/style-guide, 2026-10-20): "Append `!` to names of functions that
  modify their arguments". By convention the mutated argument comes first. IO and RNG functions are
  exceptions: `rand(x)` advances the RNG without a `!`, and `rand!(x)` also mutates `x`.

## 2. The inspirations (verified, short)

- **John De Goes / ZIO.** "A functional effect, it turns out, is just an immutable data structure
  that describes an effect"; programs "merely build a data structure that describes effectful
  operations". In `ZIO[R, E, A]`, R is "the type of the environment required to run the effect",
  E "the type of error the effect may fail with", A "the type of value the effect may succeed
  with". Testability argument: the environment `R` lets the same program run against a production
  or a test `Console`. Source: J. A. De Goes, "Beautiful, Simple, Testable Functional Effects for
  Scala", 2019-02-26, <https://degoes.net/articles/zio-environment> (fetched 2026-10-20).
  The ZIO docs (Context7 `/websites/zio_dev`, 2026-10-20) add: `R = Any` means no requirements,
  `E = Nothing` means the effect cannot fail, `A = Nothing` means it runs forever. Aliases:
  `UIO[A] = ZIO[Any, Nothing, A]`, `URIO[R, A]`, `Task[A] = ZIO[Any, Throwable, A]`, `RIO[R, A]`,
  `IO[E, A]`.
- **cats-effect `IO`.** "`IO` values are pure, immutable values and thus preserve referential
  transparency … a data structure that represents just a description of a side effectful
  computation." Effects are not evaluated until the "end of the world" (`unsafe*` methods), and
  results are not memoized, so the same `IO` can run many times. Side effects are suspended with
  `IO(…)`/`IO.delay`/`IO.blocking`. `IO` is stack-safe under `flatMap`. Source: typelevel/cats-effect
  `series/3.x`, `IO.scala` class doc and the upstream docs pages "concepts" and "tutorial"
(<https://github.com/typelevel/cats-effect/tree/series/3.x/docs>; Context7
  `/typelevel/cats-effect`, 2026-10-20).
- **Bjarnason / free monads.** Describe a program as data (a free monad over an instruction
  functor), interpret it later; trampolining (`Done`/`More`/`FlatMap` with reassociation) makes the
  interpreter stack-safe; `Trampoline = Free[Function0, _]`. Source: R. Ó. Bjarnason, "Stackless
  Scala With Free Monads", Scala Workshop 2012, <https://blog.higher-order.com/assets/trampolines.pdf>.
  cats-free's `foldMap(FunctionK)` is stack-safe "as long as your natural transformation is
  stack-safe" (Context7 `/typelevel/cats`, <https://github.com/typelevel/cats/blob/main/docs/datatypes/freemonad.md>, 2026-10-20). Julia
  measurements of both encodings: `recursion-schemes-free-laziness.md` §4.

The common idea: **an effect is a value that describes work; running it is a separate, explicit,
late step.** Julia has no such type in Base. Its effect information is inferred by the compiler
(above), and mutation is marked by name.

## 3. Proposed ChuiCore convention (for the ADR; ChuiTypes owns the runtime)

Mark effects by convention, and isolate them by construction where an effect value is used.

1. **Definition of pure** (documentation, normative for ChuiCore's own API): a function is *pure*
   if, for `===`-equal arguments, it returns `==`-equal results, and it does not mutate its
   arguments, globals or I/O. This is deliberately weaker than Julia's `:consistent`, which demands
   `===` results and so forbids returning a fresh `Vector`. Every exported ChuiCore function is pure
   unless its name ends in `!` or its docstring has an **Effects:** line.
2. **Mark mutation with `!`** exactly as Base does (mutated argument first; IO/RNG exceptions as in
   the style guide). No new marker for mutation.
3. **No purity trait for now.** A `ispure(f)` Holy trait cannot be checked, and
   `Base.infer_effects` is non-public and its output changed between 1.10 and 1.13 (table above).
   Instead, ChuiCore's **law kits may optionally assert inferred effects in tests**, e.g. a test
   helper that checks `+e` (effect-free) for a function, guarded per Julia version. This tests
   rather than declares. Cost: zero at runtime; one `infer_effects` call per test.
4. **Do not use `Base.@assume_effects` in ChuiCore** except with a written justification per site
   and the weakest setting that works. It is an unchecked promise whose misuse is undefined
   behaviour, and the accepted settings differ by version (`:noub` rejected on 1.10).
5. **Isolate effects as values.** Effectful work that a ChuiCore abstraction must carry, such as a
   free-monad program or a lazy value, is represented as a value that is interpreted explicitly
   (the freer-monad pattern with a loop interpreter; cost about 0.5–1.2 µs per instruction measured)
   or forced explicitly (`Lazy`, thread-safe, about 6 ns per forced read). ChuiCore defines no
   `IO`/`ZIO`-like type and no runtime: the `R/E/A` effect type, its interpreter, cancellation and
   resource safety belong to ChuiTypes. ChuiCore supplies the Monad/Traversable traits and
   free-monad building blocks those types instantiate.
6. **Name what is interpreted:** a function that *runs* an effect description (an interpreter) is
   named `run…`/`interpret…`, or ends in `!` if it mutates a handler state. This is the "end of the
   world" boundary from cats-effect, made visible in the name.

## UNVERIFIED

- The meaning of the trailing `i` flag in the 1.10 `Effects` printout (inferred to be `noinbounds`
  from `fieldnames`, not from 1.10 docs).
- Why 1.13.2 rejects `:nortcall` as a method annotation although its docstring lists it (perhaps
  valid only in other positions; not investigated).
- Bjarnason's full paper beyond pages 1–3; ZIO 2.x behaviour beyond the quoted docs.
- Whether a weaker `==`-based purity definition (proposal item 1) is acceptable to downstream
  packages: a design question for the ADR, not a fact.

## Also noticed

- `Base.ScopedValues` (present on 1.13.2, absent on 1.10.12 by `isdefined`) is the Julia-native
  analogue of a reader environment (ZIO's `R`). ChuiTypes may want it, with a fallback for 1.10
  (the ScopedValues.jl package; not checked here).
