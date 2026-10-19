# ADR-0003: The transducer substrate is struct-based, fail-closed for parallelism, and completes once

- **Status:** Accepted (2026-10-20, user at the ChuiCore phase-1 ★)
- **Date:** 2026-10-20
- **Deciders:** the user, at the phase-1 ★ checkpoint
- **Scope:** ChuiCore.jl

## Context

- Ecosystem ADR-0002 §4 (Accepted) decides the *location*: ChuiCore owns the one transducer
  substrate as its own code, with Transducers.jl interop only in `ChuiCoreTransducersExt`. This ADR
  designs it. Consumers: ChuiTypes streams (possibly unbounded) and ChuiFrames' partitioned
  execution (`chui-frames.md`, `source_partitions`) over the aggregator protocol (CC-004; CC-005:
  combine in partition order). ChuiFrames execution "uses only ChuiCore's names" (ecosystem ADR-0002 §2).
- Facts (`docs/research/transducers.md`, both 1.10.12 and 1.13.2):
  - Transducers.jl 0.4.85: 11 direct / 20 transitive registered deps; protocol
    `start`/`next`/`complete`/`combine`; state in the accumulator (`wrap`/`unwrap`); reducing
    functions are built with the adjoint `xf'(op)`, while calling a transducer on data gives an
    eduction; `foldxt` with `Take`/`Scan`/`Partition` errors depending on the data (R1, R2, F1).
  - Clojure: init/step/completion; completion runs once, also after early termination; a stateful
    transducer flushes on completion and discards pending state once its downstream has reduced
    (F2; quotes came through a summariser).
  - The prototype: no completion step; `Take`'s `Ref` counter breaks reuse (3, then 0); `foldxt`
    copies the input (8 MB per 10^6 `Float64`); its own `⨟` function (R3, F3).
  - The struct-based sketch (`mini.jl`) is `@inferred` and allocates 0 bytes for `foldxl` over
    `1:10^6` and a `Vector{Float64}`; `foldxt` on 4 threads allocates 2,048–2,672 B (R4, R5). Speed
    ranks are **not** established (machine load).
  - Exported `Map`/`Filter`/`foldxl` would clash with Transducers.jl's: 1.10 warns and then errors at the
    use, 1.13 errors only at the use; Transducers.jl also exports `Count` (R6).
  - Critic-C attacks on the sketch (scratch `critic-c/attacks.jl`, identical on both versions):
    calling transducers on reducing functions breaks CC-001 (`(Map(f) ⨟ Filter(p))(+)` folds to 12,
    `Filter(p)(Map(f)(+))` to 15); a fail-open `isstateless` lets an unlisted stateful `DropWhile`
    reach `foldxt` and throw only with `ntasks = 4`; per-chunk `TakeWhile` returns 9 instead of 3;
    `foldxt(+, …; init = () -> 100)` gives 155 / 255 / 455 for `ntasks` 1 / 2 / 4; a `nothing`
    accumulator collides with the sketch's skip sentinel (14 vs 7); a generator input is copied by
    `Iterators.partition` (≈ 46 MB for 10^6 `Int`).

## Decision

1. **Types.** `abstract type Transducer end`; transducers are immutable structs (`Map{F}`,
   `Filter{P}`, `MapCat{F}`, `Take`, `TakeWhile{P}`, `Scan`, `Partition`, `Composed{T<:Tuple}`; the
   v1 set is fixed in phase 3). **Transducers have no call method.** A reducing function is built
   by the public function `asrf(xf, op)`, returning a struct (`R{X,Inner}`, `Bottom{F}`), never a
   closure. So a transducer is not a callable and CC-001's law does not apply to `xf₁ ⨟ xf₂`; a
   test asserts, for an instance of **every** v1 transducer type including `Composed`, that it has
   no call method (`!hasmethod(xf, Tuple{Any})`). (If `xf(itr)` is ever added, it means an
   eduction, as in Transducers.jl.)
2. **Protocol** (generic functions owned by ChuiCore): `start(rf, acc)`, `next(rf, acc, x)`,
   `complete(rf, acc)`; early termination by `Reduced{T}` (`reduced`, `unreduced`, `isreduced`).
   - State **must** live in the accumulator, created by `start` once per fold and once per
     partition, never in a `Ref` captured at construction.
   - `complete` **must** run exactly once per fold, also after `Reduced`.
   - A stateful transducer **must not** flush into a downstream that has reduced: it either clears
     its buffer before calling downstream, or records a "downstream reduced" flag in its state and
     skips the flush. Each stateful transducer has a test of both orders
     (`Partition(3) ⨟ Take(1)` and `Take(2) ⨟ Partition(3)`).
3. **Composition.** `a ⨟ b` means "a, then b", through the CompositionsBase binding (ADR-0006);
   ChuiCore adds `Base.:∘(b::Transducer, a::Transducer)`, so `Map(f) ⨟ Filter(p) ==
   Filter(p) ∘ Map(f)`. ChuiCore defines no `⨟` function of its own. Composing a transducer with a
   plain function (`Map(f) ⨟ g`) is not supported; the docs say it builds a `ComposedFunction`.
4. **Parallel safety is fail-closed.** `isstateless(xf)` defaults to **`false`**; only `Map`,
   `Filter`, `MapCat` (and `Composed` of those) opt in. Early-terminating transducers (`TakeWhile`,
   `Take`) are not stateless. Only `isstateless` pipelines may be run per partition by any
   executor, ChuiCore's or downstream; all others run sequentially through `foldxl`.
5. **Folds.**
   - `foldxl(op, xf, itr; init)`: `start`, a `next` loop, `complete`; `init` is a value and is
     required in v1. A type-changing accumulator makes the loop type-unstable; the docs say so.
   - `foldparts(op, xf, parts; init, merge)`: the public primitive over **pre-partitioned** input
     (`parts` an `AbstractVector` of iterables, in order). `init` is a **factory** (a non-callable
     `init` throws an `ArgumentError`), `merge` is **required**. Caller obligations, documented as
     the conditions under which the result is defined: `merge` is associative on the accumulator
     type, and `init()` is an identity of `merge`. Partitions are merged strictly in order
     (CC-005); `complete` runs once on the merged accumulator; a partition that reduces stops all
     later partitions from being merged (an internal sentinel type, never `nothing`, marks
     skipped partitions; a test folds with a `nothing` accumulator).
   - A pipeline that is not `isstateless` given to `foldparts` runs as **one** sequential `foldxl`
     over the parts flattened in order, with a single `init()`.
   - `foldxt(op, xf, v::AbstractVector; init, merge, ntasks)` = `foldparts` over contiguous views
     of `v`. Other iterables are rejected with an `ArgumentError` (collect first, or use `foldxl`).
   - `foldparts`/`foldxt` **require pure** `xf` and `op`: partitions run concurrently and may run
     past a stop point. Effectful pipelines use `foldxl`.
6. **Aggregators.** `aggregate(agg, xf, parts)` (name provisional) folds with CC-004 unchanged:
   `init(agg)` as the factory, `partial` per element or per chunk (stateless prefixes only),
   `combine(agg, a, b)` as `merge`, then `final(agg, complete(rf, acc))`. It is a separate function,
   not a `foldxt` method, because aggregators need not subtype anything (ADR-0001 §2).
7. **Names.** No reducing-function methods are added to `ChuiCore.combine` in v1 (stateful merges
   would need a later ADR). The transducer types, `Reduced`, `asrf`, `foldxl`, `foldparts`,
   `foldxt`, `aggregate`, `isstateless`, `Composed` and the protocol functions are **public, not
   exported** (ADR-0005), used as `ChuiCore.Map` or `using ChuiCore: Map`.
8. **Interop.** `ChuiCoreTransducersExt` (weakdep `Transducers = "0.4"`) converts ChuiCore
   pipelines to Transducers.jl ones and adds `Transducers.foldxl`/`foldxt` methods for
   `ChuiCore.Transducer` arguments (an owned type). `ChuiCore.Map` never aliases `Transducers.Map`.
9. **Runtime cost (documented):** stateless pipelines over vectors: 0 bytes, no dynamic dispatch;
   stateful transducers: their state per fold (e.g. one buffer per `Partition`); `foldparts`: one
   task and one `init()` per partition. Phase 4 sets the time budget on a quiet machine.

## Alternatives rejected

| Alternative | Why rejected |
|---|---|
| Keep the prototype substrate | No completion, a reuse bug in `Take`, an input copy in `foldxt`, its own `⨟` (F3). |
| Transducers callable on reducing functions (`xf(rf)`, the prototype and sketch) | Makes transducers callables, and then `⨟` violates CC-001 (12 vs 15). |
| Closures as reducing functions | No `start`/`complete` protocol, not inspectable by the extension. |
| State in `Ref`s captured at construction | Breaks reuse and sharing across tasks (R3). |
| Fail-open `isstateless` (default `true`) | A downstream stateful transducer that forgets to opt out fails only with some `ntasks` (critic A5). |
| `TakeWhile` as stateless | Correct per partition only with a stop rule an executor may not know (per-chunk 9 vs 3). |
| `merge` defaulting to `op` | `push!`-style ops and non-identity `init` give results that depend on `ntasks`. |
| Transducers.jl's "error if stateful in `foldxt`" | Data-dependent failures (R2). |
| Accept any `HasLength`/`HasShape` input in `foldxt` | Ranges and generators are `HasShape`, sets are `HasLength`; non-arrays get copied into `Vector{Any}` partitions. |
| Export the transducer names | Clashes with Transducers.jl (R6), including `Count`. |
| Adopt Transducers.jl | Decided against by ecosystem ADR-0002 §4. |
| Optional `init` (InitialValues.jl or a `NoValue` sentinel) | One more dependency, or first-element peeling; deferred. |

## Consequences

- Contract: the PROVISIONAL "transducer substrate API" item gets these names after phase 3; notes for
  the lead: they stay qualified; ChuiFrames' executor should use `foldparts`/`aggregate` rather than
  re-implementing partition folding; and Decision 4's rule (only `isstateless` pipelines run per
  partition) binds downstream executors, so it belongs in the contract entry.
- Phase 3 turns critic C's reproducers (`attacks.jl` A1–A8) into test items, quoted red then green.
- ChuiTypes must not run `foldparts`/`foldxt` on unbounded or effectful streams.
- New work: `eduction` (a v1 candidate for ChuiTypes); `Enumerate`, `Completing`, `OnInit`, `foldxd`
  are out of v1; a typed `Partition{T}` buffer is a phase-3 point; `MapCat` vs CC-007's `MapM` need
  distinct docs.

## Verification

- `docs/research/transducers.md` R1–R7, F1–F4 (both versions; scratch `phase1/transducers/`);
  clojure.org/reference/transducers (fetched 2026-10-20 via a summariser); critic-C scratch
  `phase1/critic-c/attacks.jl` (A1–A8, both versions).
- UNVERIFIED: speed vs Transducers.jl and Base; TTFX; the extension's reverse constructors; Aqua
  piracy on the extension; JET; per-element vs chunked `partial` speed; exact Clojure wording.

## Revisit when

- Phase 4 puts stateless `foldxl` more than 1.3× slower than a hand-written loop, or slower than
  Transducers.jl, on a quiet machine.
- A consumer needs a no-`init` fold, parallel `Scan`, a stateful `merge`, or `foldxd`.
- Transducers.jl slims its dependencies (ecosystem ADR-0002's trigger).
