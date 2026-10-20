# Transducers

```@meta
DocTestSetup = :(using ChuiCore)
```

A transducer describes one step of a reduction (map, filter, take, …) apart from the input it
reads and the accumulator it writes. You compose transducers into a pipeline once, then fold any
iterable through it, sequentially or per partition. ChuiCore's transducers are plain immutable
structs (ADR-0003, "transducer substrate"): no closures, so a pipeline has a concrete,
inspectable type and stateless pipelines over vectors allocate nothing.

The names are public, not exported, so this page imports the ones it uses:

```jldoctest transducers
julia> using ChuiCore: foldxl, foldparts, foldxt, aggregate, Map, Filter, MapCat, Take, TakeWhile, Scan, Partition, reduced, Reduced, isreduced, unreduced, isstateless
```

## A pipeline, left to right

`a ⨟ b` reads "a, then b": data flows through `a` first. (It equals `b ∘ a`.) Fold with
[`ChuiCore.foldxl`](@ref ChuiCore.foldxl), giving the binary step `op`, the pipeline, the input and an
initial value:

```jldoctest transducers
julia> xf = Map(x -> x^2) ⨟ Filter(isodd);   # square, then keep the odd squares

julia> foldxl(+, xf, 1:6; init = 0)          # 1 + 9 + 25
35

julia> foldxl(push!, xf, 1:6; init = Int[])
3-element Vector{Int64}:
  1
  9
 25
```

`MapCat` maps one input to any number of outputs (a flat map); `Scan` emits the running
accumulation; `Partition` groups inputs into chunks and flushes the last, shorter one at the end:

```jldoctest transducers
julia> foldxl(push!, MapCat(x -> 1:x), 1:3; init = Int[])'
1×6 adjoint(::Vector{Int64}) with eltype Int64:
 1  1  2  1  2  3

julia> foldxl(push!, Scan(+, 0), [3, 1, 4, 1, 5]; init = Int[])'
1×5 adjoint(::Vector{Int64}) with eltype Int64:
 3  4  8  9  14

julia> foldxl(push!, Partition{Int}(2), 1:5; init = Vector{Int}[])
3-element Vector{Vector{Int64}}:
 [1, 2]
 [3, 4]
 [5]
```

`Take(n)` and `TakeWhile(p)` stop the fold. They stop it for real: no further input is read, so
they work on unbounded iterables:

```jldoctest transducers
julia> foldxl(push!, Map(x -> 2x) ⨟ Take(4), Iterators.countfrom(1); init = Int[])'
1×4 adjoint(::Vector{Int64}) with eltype Int64:
 2  4  6  8

julia> foldxl(+, TakeWhile(<(10)), Iterators.countfrom(1); init = 0)   # 1 + … + 9
45
```

Everything composes. Here: the running sum of 1, 2, 3, … in chunks of three, the first two
chunks only:

```jldoctest transducers
julia> foldxl(push!, Scan(+, 0) ⨟ Partition{Int}(3) ⨟ Take(2), Iterators.countfrom(1); init = Vector{Int}[])
2-element Vector{Vector{Int64}}:
 [1, 3, 6]
 [10, 15, 21]
```

Pass an `init` of the result type: `init = 0` with `Float64` steps changes the accumulator's type
mid-loop and makes the fold type-unstable (slower, not wrong).

## Early termination from the step: `reduced`

The step `op` can stop the fold too, by returning [`ChuiCore.reduced`](@ref ChuiCore.reduced)`(acc)`,
a [`ChuiCore.Reduced`](@ref ChuiCore.Reduced) wrapper. The fold stops reading input and returns
the unwrapped value:

```jldoctest transducers
julia> upto7(a, x) = x > 7 ? reduced(a) : a + x;

julia> foldxl(upto7, Map(identity), 1:100; init = 0)   # 1 + … + 7
28

julia> isreduced(reduced(1)), unreduced(Reduced(1)), unreduced(1)
(true, 1, 1)
```

## The reducing-function protocol (for authors of a new transducer)

A fold turns the pipeline into a reducing function with [`ChuiCore.asrf`](@ref ChuiCore.asrf)
(nested [`ChuiCore.R`](@ref ChuiCore.R) structs around a [`ChuiCore.Bottom`](@ref ChuiCore.Bottom)
holding `op`) and drives it with three functions:

- [`ChuiCore.start`](@ref ChuiCore.start)`(rf, init)`: the first accumulator; a stateful
  transducer creates its per-fold state here, wrapping the inner accumulator;
- [`ChuiCore.next`](@ref ChuiCore.next)`(rf, acc, x)`: one step, returning the new accumulator or a
  `Reduced` to stop;
- [`ChuiCore.complete`](@ref ChuiCore.complete)`(rf, acc)`: run exactly once at the end, also after
  a stop; a stateful transducer flushes and unwraps its state here.

```jldoctest transducers
julia> rf = ChuiCore.asrf(Map(x -> 10x) ⨟ Take(2), +);

julia> a = ChuiCore.next(rf, ChuiCore.start(rf, 0), 1);

julia> a = ChuiCore.next(rf, a, 2); isreduced(a)
true

julia> ChuiCore.complete(rf, unreduced(a))
30
```

A new transducer is a subtype of [`ChuiCore.Transducer`](@ref ChuiCore.Transducer) with a `next`
method for `R{<:YourType}`. A stateful one keeps its state in its own wrapper around the inner
accumulator (created by `start`, never in a `Ref` captured when the transducer is built, so one
value can be reused across folds), and when the downstream stops it returns `Reduced(wrapper)`,
keeping `Reduced` outermost. Here is `Dedupe`, which drops consecutive repeats:

```jldoctest transducers
julia> struct Dedupe <: ChuiCore.Transducer end

julia> struct DedupeState{A}
           prev::Any        # the last input seen, `nothing` before the first
           acc::A
       end

julia> ChuiCore.start(rf::ChuiCore.R{Dedupe}, acc) = DedupeState(nothing, ChuiCore.start(rf.inner, acc));

julia> function ChuiCore.next(rf::ChuiCore.R{Dedupe}, w::DedupeState, x)
           isequal(w.prev, x) && return w
           a = ChuiCore.next(rf.inner, w.acc, x)
           return a isa Reduced ? Reduced(DedupeState(x, a.value)) : DedupeState(x, a)
       end

julia> ChuiCore.complete(rf::ChuiCore.R{Dedupe}, w::DedupeState) = ChuiCore.complete(rf.inner, w.acc);

julia> foldxl(push!, Dedupe() ⨟ Take(3), [1, 1, 2, 2, 2, 3, 1, 1]; init = Int[])'
1×3 adjoint(::Vector{Int64}) with eltype Int64:
 1  2  3
```

## `isstateless`: what may run per partition

A parallel fold runs the pipeline separately on each partition. That is only correct for a
pipeline with no state across elements, and [`ChuiCore.isstateless`](@ref ChuiCore.isstateless)
says which ones those are. It is **fail-closed**: only `Map`, `Filter`, `MapCat` and their
compositions say `true`. `Take` and `TakeWhile` say `false` (per partition they would stop each
partition separately), as do `Scan`, `Partition` and every user transducer that does not opt in:

```jldoctest transducers
julia> isstateless(Map(abs) ⨟ Filter(iseven) ⨟ MapCat(x -> (x, x)))
true

julia> isstateless(Map(abs) ⨟ TakeWhile(<(5))), isstateless(Scan(+, 0)), isstateless(Dedupe())
(false, false, false)
```

A pipeline that is not stateless is still accepted by the parallel folds below: they run it
sequentially, with one `init()`, so the result is right and only the speed-up is lost.

## Folding partitions: `foldparts` and `foldxt`

[`ChuiCore.foldparts`](@ref ChuiCore.foldparts) folds input that is already split into
partitions, in order. Each partition starts from its own accumulator, so `init` is a **factory**
(a zero-argument function), and `merge` combines the partition results, strictly in partition
order:

```jldoctest transducers
julia> parts = [1:4, 5:8, 9:12];

julia> foldparts(+, Map(x -> x^2), parts; init = () -> 0, merge = +)
650

julia> foldxl(+, Map(x -> x^2), 1:12; init = 0)
650

julia> foldparts(push!, Filter(isodd), parts; init = () -> Int[], merge = append!)'
1×6 adjoint(::Vector{Int64}) with eltype Int64:
 1  3  5  7  9  11
```

The result is defined when `merge` is associative, `init()` is its identity, and `op` and the
pipeline are pure. A non-callable `init` is rejected:

```jldoctest transducers
julia> foldparts(+, Map(abs), parts; init = 0, merge = +)
ERROR: ArgumentError: `init` must be a zero-argument factory (e.g. `init = () -> 0`), got 0; foldxl takes a value
[...]
```

[`ChuiCore.foldxt`](@ref ChuiCore.foldxt) splits a vector into at most `ntasks` contiguous views
(no copy) and calls `foldparts` on them, one task per view. For a stateless pipeline, an identity
`init` and a pure `op`, the result does not depend on `ntasks`:

```jldoctest transducers
julia> v = collect(1:1000);

julia> [foldxt(+, Map(x -> x % 7) ⨟ Filter(iseven), v; init = () -> 0, merge = +, ntasks = n) for n in (1, 2, 3, 8)]
4-element Vector{Int64}:
 1716
 1716
 1716
 1716
```

`foldxt` accepts only an `AbstractVector` (ranges included); collect a generator first, or use
`foldxl`, which takes any iterable.

## Aggregators: `aggregate`

[`ChuiCore.aggregate`](@ref ChuiCore.aggregate) folds partitions into one of ChuiCore's
aggregators (`ChuiCore.Sum`, `ChuiCore.Mean`, `ChuiCore.Count`, `ChuiCore.Extrema`, …), using the
aggregator's own `init`, `partial`, `combine` and `final`, so you give no `op`, `init` or
`merge`:

```jldoctest transducers
julia> using ChuiCore: Sum, Mean, Count, Extrema

julia> parts = [[3, -1, 4], [-1, 5], [9, -2, 6]];

julia> aggregate(Sum(), Map(abs), parts)
31

julia> aggregate(Mean(), Filter(>(0)) ⨟ Map(float), parts)
5.4

julia> aggregate(Count(), Filter(<(0)), parts)
3

julia> aggregate(Extrema(), Map(identity), parts)
(-2, 9)
```

## The per-partition caveat: a stop decided by `op`

A `Reduced` returned by `op` stops **only its own partition** (and stops later partitions from
being merged). Each partition starts from its own `init()`, so `op` only sees that partition's
accumulator. The parallel folds therefore agree with `foldxl` only when the stop depends on the
**element alone**, not on the accumulator. (This is the "review S1" case of
`test/transducers_attacks_tests.jl`.)

A stop that depends on the element alone agrees with `foldxl` for every partitioning:

```jldoctest transducers
julia> byelem(a, x) = x > 7 ? reduced(a) : a + x;   # stop at the first element above 7

julia> foldxl(byelem, Map(identity), 1:10; init = 0)
28

julia> [foldxt(byelem, Map(identity), collect(1:10); init = () -> 0, merge = +, ntasks = n) for n in 1:4]
4-element Vector{Int64}:
 28
 28
 28
 28
```

A stop that depends on the accumulator is decided per partition, so the result depends on the
partitioning:

```jldoctest transducers
julia> byacc(a, x) = a + x > 10 ? reduced(a) : a + x;   # stop before the total passes 10

julia> foldxl(byacc, Map(identity), 1:10; init = 0)
10

julia> foldparts(byacc, Map(identity), [1:3, 4:10]; init = () -> 0, merge = +)   # 6, then 4 + 5, merged
15
```

The remedy is to move the stop into the pipeline, as a `Take` or `TakeWhile`. That makes the
pipeline stateful, so `foldparts` and `foldxt` run it sequentially and agree with `foldxl`. For a
stop on the running total, compute the total with `Scan` and stop on it with `TakeWhile`; the step
then keeps the last total:

```jldoctest transducers
julia> xf = Scan(+, 0) ⨟ TakeWhile(<=(10));

julia> isstateless(xf)
false

julia> foldparts((_, s) -> s, xf, [1:3, 4:10]; init = () -> 0, merge = +)
10

julia> foldparts(+, TakeWhile(<=(4)), [1:3, 4:10]; init = () -> 0, merge = +)   # 1 + 2 + 3 + 4
10
```

Partitions run concurrently, so after a stop the later partitions may already have run (their
effects happened; their results are discarded). Effectful pipelines belong in `foldxl`.

## What it costs

Measured on Julia 1.13.2 and 1.10.12 (`docs/src/performance.md`, printed by
`benchmark/allocs.jl`; one thread, a loaded shared machine):

- `foldxl` through `Map`, `Filter`, `MapCat`, `Take`, `TakeWhile`, `Scan` and their compositions
  allocates **0 bytes**, with no dynamic dispatch for concretely typed functions. A
  `Map ⨟ Filter` pipeline runs at ≈1.4 ns per element.
- `Partition{Float64}(10)` allocates one buffer per fold and one vector per chunk: ≈112–126 B per
  chunk on 1.13.2, ≈144–160 B on 1.10.12.
- `foldparts` and `aggregate` pay one task and one `init()` per partition: 992, 1504, 2496 and
  4480 B for 1, 2, 4 and 8 partitions on 1.13.2 (≈0.5–0.66 kB per partition). `foldxt` adds
  one view per partition (1088 B for `ntasks = 1`, 2720 B for 4). Use few, large partitions.
- `isstateless` is a constant (dispatch only).

The parallel folds also spawn tasks (`Threads.@spawn`): `op`, `merge`, `init` and the pipeline
must be pure, or at least thread-safe. Errors in a partition come back as a
`TaskFailedException` after every task has finished.
