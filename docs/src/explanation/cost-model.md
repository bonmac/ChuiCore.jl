# Runtime cost model

The brief asks that every abstraction have a documented runtime cost. Each docstring states its
own, in a `Cost:` line, and a `:quality` test fails when an exported or public name owned by
ChuiCore has no cost statement. This page summarises those lines by area. The docstrings carry
the detail and say where a number comes from. Measured figures are from Julia 1.13.2 (and
1.10.12 where stated) on a shared, loaded machine, so treat them as indicative. The phase-4
budgets and measurements are on the [performance](../performance.md) page.

Three kinds of statement appear:

- **structural**: passes, calls, allocations and dispatch, read from the code (most lines);
- **measured**: a figure with its source: the allocation test items, `benchmark/allocs.jl`, the
  performance page, or a phase-5 measurement described in the docstring;
- **research**: a figure carried over from a research prototype (`docs/research/`), labelled as
  such in the docstring, and not re-measured on ChuiCore's code.

## Free (compile time only)

These cost nothing at run time once the types are known, because dispatch on a singleton or a
type folds to a constant:

- the typeclass encoding: `constructorclass`, every `…Style` trait, `AlgebraClass`,
  `iscommutative`, `isstateless`, `isreduced`, `default_monoid` (code inspection with
  `code_typed` shows no trait call left in `fmap` over a `Vector`);
- the export tiers ([export tiers](export-tiers.md)): a qualified call compiles to the same code
  as a bare one;
- the purity conventions (`!` names, `Effects:` lines).

## Composition

| Abstraction | Cost |
|---|---|
| `⨟`, `opcompose` | a `ComposedFunction`; calling it is the two calls |
| `pipe` | one call per function; the recursion unrolls for a tuple of functions |
| `papply`, `curry`, `flip` | one small immutable struct (no closures); the call splats the stored arguments |

## Monoids and aggregators

| Abstraction | Cost |
|---|---|
| `init`, `neutral` | a constant for every built-in; `ReduceM` with a mutable declared neutral pays one `deepcopy` per call |
| `partial` | at most one pass over the chunk; `Sum`/`Prod`/`Mean` use Base's pairwise `sum`/`prod` on a non-empty array; `Count`/`Last` are O(1) on arrays; `First` reads one element |
| `combine`, `final` | O(1): one operation on the accumulators |
| built-in aggregators | **0 bytes** for `partial`, `combine`, `final` on number elements (measured: the allocation test items) |
| `combineall` | one `combine` per accumulator |
| law kits | per law, at most 1,728 predicate calls over sample collections, or `max_examples` plus shrinking under Supposition: test-time only |

## Typeclasses

| Abstraction | Cost |
|---|---|
| dispatch to an instance | free (above) |
| `fmap`, `ap`, `chain`, `alt` on Maybe, `Identity`, tuples, pairs | no heap allocation for isbits values (measured with `@allocated`) |
| the same on `Array` | one new `Vector`; `ap`/`chain` grow it while filling (its length is not known up front) |
| `traverse`, `sequence` on vectors | O(n²) element copies (measured: 1,664 B for 10 elements, 53,968 B for 100) |
| `ZipVector` | one new `Vector` per construction and per operation |
| function Profunctor/Arrow ops | one small immutable callable, no heap allocation for isbits functions |

## Transducers

| Abstraction | Cost |
|---|---|
| `Map`, `Filter`, `MapCat`, `TakeWhile`, `Take`, `Scan` and their compositions under `foldxl` | **0 bytes** over vectors, no dynamic dispatch for concretely typed functions (measured: allocation test items) |
| `Partition(n)` | one buffer per fold plus one vector per chunk (≈112–126 B per chunk of 10 `Float64`) |
| `foldparts`, `aggregate` | one task and one `init()` per partition (992 B for 1 partition, 2,496 B for 4) |
| `foldxt` | one task, one view and one `init()` per partition, no input copy (1,088 / 2,720 / 4,880 B at 1 / 4 / 8 tasks) |

A type-changing accumulator (an `init` of a different type than the step returns) makes any fold
type-unstable: slower, not wrong.

## Recursion schemes

| Abstraction | Cost |
|---|---|
| `cata` over your own node type | ≈18 ns and 0 B per node (1023-node tree) |
| `cata` over `Fix` | ≈77 ns and ≈47 B per node: one box and one dynamic `fmap` per node |
| `ana` | one layer and one `embed` per node (≈72 B/node with `Fix`) |
| `para` | as `cata` plus one 2-tuple per child (≈45–48 B/node on 1.13.2) |
| `histo` | one `Attr` per node, kept until the end; the result does not infer (`Any`) |
| `hylo` | no intermediate tree (research figures in the docstring) |
| monadic variants | as the plain scheme plus one `traverse` and one `chain` per node |

The schemes recurse on the Julia stack: a very deep structure can overflow it. A stack-safe
`cata` is deferred (see `HANDOFF.md`).

## Free monads and à la carte

| Abstraction | Cost |
|---|---|
| `Inl`, `Inr`, `inj` | one box (an `Any` field) per coproduct level; dispatch on the payload is dynamic |
| `liftF`, `chain` on a program | one heap object per instruction plus one continuation node; binding is O(1) in either association |
| `interpret` | ≈0.16–0.5 µs and ≈130–270 B per interpreted instruction (phase-5 measurement, 1.13.2 and 1.10.12); nothing infers |
| `foldfree` | as the target monad's `chain` per instruction; recurses (no trampoline) |

Use free monads to describe programs and plans, not for inner loops.

## Optics

| Abstraction | Cost |
|---|---|
| `Lens{:a}` (property in the type) | get is one field access, set one constructor call: type-stable, 0 bytes |
| `Lens(:a)` with a runtime `Symbol` | type-unstable unless the symbol is a compile-time constant |
| `IndexLens` | get is one `getindex`; set rebuilds a tuple (0 bytes for a constant index) or copies an array, O(length) |
| `Prism` | one `match` call (an `isa` test for a variant prism); `set`/`modify` also call `build` |

## Laziness

| Abstraction | Cost |
|---|---|
| `Thunk` | a struct holding a function; each `force` is one call of it |
| `Lazy` | construction allocates the cell and a `ReentrantLock`; a forced read is one acquire load plus a field read, no allocation |
| deferred `fmap`/`chain` on `Lazy` | one new `Lazy` cell per operation |

For lazy sequences, `Base.Iterators` is fused at compile time and is the better tool.

## The conflict banner

`binding_conflicts` is O(exported names × loaded modules), run once at package load;
`conflict_banner` adds printing, and costs nothing when silenced (`CHUI_QUIET_CONFLICTS=1`).
