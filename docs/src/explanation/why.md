# Why ChuiCore

ChuiCore is the shared functional-programming vocabulary of the Chui packages. ChuiTypes (data
types, effects, streams) and ChuiFrames (data frames) build on it, and their contracts name its
functions: ChuiFrames' aggregation engine runs ChuiCore's monoids over partitions, its planned
optimizer will rewrite plans with ChuiCore's recursion schemes, and both packages are to fold
through the same transducer substrate. Keeping these in one small upstream package means one definition of
"combine two partial results", one composition operator and one set of laws, tested once and
reused everywhere.

## What it gives you

- **Composition** that reads left to right (`f ⨟ g` is "f, then g"), plus `pipe`, `papply`,
  `curry` and `flip`.
- **Algebraic structures with laws you can test.** Semigroups, monoids and aggregators; Functor,
  Applicative, Monad, Alternative, Foldable, Traversable, Contravariant, Bifunctor, Profunctor,
  Category and Arrow; and for each, an exported **law kit** (`test_monoid_laws`,
  `test_functor_laws`, …) that downstream packages run against their own instances.
- **Aggregators built for partitions**: `init` / `partial` / `combine` / `final`, with defined
  empty-input behaviour (contract CC-006), so a parallel or out-of-core executor gets the same
  answer as a sequential one.
- **A transducer substrate**: composable, allocation-free `Map`, `Filter`, `Take`, … with folds
  over one sequence, over partitions, and over threads.
- **Recursion schemes** (`cata`, `ana`, `hylo`, `para`, `apo`, `histo`, `futu` and monadic
  variants), **data types à la carte** and a **freer monad** with interpreters.
- **Optics** (lenses and prisms) that interoperate with Accessors.jl, **laziness** (`Thunk`,
  thread-safe memoised `Lazy`), and a dplyr-style **name-conflict banner** other packages reuse.

## Design choices, and why

Each choice has an ADR in the repository (`docs/adr/`); the short reasons:

| Choice | Why | ADR |
|---|---|---|
| Monoids are **instance values** (`combine(Sum(), a, b)`), not methods on the element type | numbers have several monoids (sum, product, max); a value picks one explicitly and carries parameters (`ReduceM(op)`) | 0001 |
| Constructor classes are **Holy traits** on a tag (`constructorclass(typeof(x))`) | dispatch picks the instance at compile time, so the abstraction is free; a type opts in with a few methods, without inheritance | 0001 |
| ADTs are **plain structs** with `Union` aliases; no pattern-matching library | no extra dependency or macro layer; small unions dispatch statically; the cost of open sums is measured and documented | 0002 |
| An **own transducer substrate**, struct-based, state in the accumulator | type-stable and allocation-free folds; safe partitioned execution (only `isstateless` pipelines run per partition); Transducers.jl's ≈20 transitive dependencies are not needed by every Chui package | 0003 |
| An **own minimal Lens/Prism core**; Accessors.jl as an extension | Accessors as a hard dependency added 22–41 ms to every `using` and has no prisms; the extension keeps interop | 0004 |
| **One module**, names in three tiers, a tested **clash list** | `using ChuiCore` next to DataFrames, Functors, TypeClasses, Accessors or Transducers never breaks a bare name; see [export tiers](export-tiers.md) | 0005 |
| `⨟` is **CompositionsBase's binding** | one `⨟` in the whole Julia ecosystem, so `using ChuiCore, Accessors` or `…, Transducers` does not clash | 0006 |
| Law kits are **stubs plus extensions** on Test and Supposition | loading ChuiCore never loads a test framework (CC-011) | 0007 |
| **ConstructionBase** for struct rebuilding | the same rebuild hook as Accessors, so a type behaves the same under both | 0008 |
| **Budgets** for allocations, load time and time to first call; a **precompile workload** | the core package is loaded by everything, so its load and first-call time are everyone's; see [performance](../performance.md) | 0009, 0010 |

## Julian, not transliterated Haskell

The inspirations are Haskell's `base` and `recursion-schemes`, Rúnar Bjarnason (*Functional
Programming in Scala*, free monads), Bartosz Milewski (*Category Theory for Programmers*), John De
Goes (functional effects, ZIO) and Scala's cats. ChuiCore keeps their laws and drops what does not
fit Julia:

- Dispatch and traits instead of typeclass resolution; broadcasting and `Base.Iterators` remain the
  first tool for element-wise and lazy-sequence work. `ChuiCore.fmap` exists for generic code over
  any Functor, not to replace `map` or `.`.
- The function comes first (`chain(f, m)`), so Julia's `do` blocks work: `chain(m) do x … end`.
- No operator zoo: `⨟` is the one operator ChuiCore relies on.
- Every abstraction states its **runtime cost** (see the [cost model](cost-model.md)): where it is
  free (trait dispatch, stateless transducers) and where it is not (free-monad interpretation,
  `Lazy` construction, open-sum dispatch).

## What ChuiCore is not

- **Not an effect system.** It defines what "pure" means and how effects are marked or isolated
  ([purity and effects](purity-effects.md)); the effect types and their runtime are ChuiTypes'.
- **Not a data-frame or statistics package.** Its aggregators are the building blocks; ChuiFrames
  and the later ChuiStats use them.
- **Not a replacement for Transducers.jl or Accessors.jl** in general use: it covers what the Chui
  packages need, with interop where it matters.
