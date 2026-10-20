# Folds over the transducer substrate (ADR-0003 §5–6): foldxl (sequential), foldparts
# (pre-partitioned, parallel for stateless pipelines), foldxt (contiguous views of a vector) and
# aggregate (the CC-004 aggregator protocol).

"""
    foldxl(op, xf, itr; init)

Left fold of `itr` through the transducer `xf` into the binary `op`, starting from the value
`init` (required): `start`, a `next` loop, then `complete` exactly once (also after early
termination by `Reduced`). Works on any iterable, including unbounded ones that some step stops.
This is the fold for effectful pipelines.

```jldoctest
julia> using ChuiCore: foldxl, Map, Filter, Take

julia> foldxl(+, Map(abs) ⨟ Filter(>(1)), [-1, 2, -3]; init = 0)
5

julia> foldxl(+, Map(x -> x^2) ⨟ Take(3), Iterators.countfrom(1); init = 0)   # unbounded input
14
```

An accumulator whose type changes (`init = 0` with `Float64` steps) makes the loop type-unstable;
pass an `init` of the result type.

Cost: stateless pipelines over vectors allocate 0 bytes with no dynamic dispatch (for concretely
typed functions); stateful transducers add their state once per fold (an `Int` for `Take`, one
buffer plus one vector per chunk for `Partition`).
"""
function foldxl(op::OP, xf::Transducer, itr; init) where {OP}
    rf = asrf(xf, op)
    return complete(rf, unreduced(_loop(rf, start(rf, init), itr)))
end

# The `next` loop without completion: the unreduced accumulator, or a `Reduced` on early stop.
function _loop(rf::RF, acc, itr) where {RF}
    for x in itr
        r = next(rf, acc, x)
        r isa Reduced && return r
        acc = r
    end
    return acc
end

# Marks a partition skipped after an earlier partition reduced (never `nothing`, which is a valid
# accumulator).
struct _Skipped end

function _check_factory(init)
    applicable(init) && return nothing
    throw(ArgumentError("`init` must be a zero-argument factory (e.g. `init = () -> 0`), got $(repr(init)); foldxl takes a value"))
end

"""
    foldparts(op, xf, parts; init, merge)

Fold pre-partitioned input: `parts` is an `AbstractVector` of iterables, in order. `init` is a
**factory** (`init = () -> 0`; a non-callable `init` throws an `ArgumentError`) and `merge` is
**required**.

- When [`ChuiCore.isstateless`](@ref)`(xf)`: one task (`Threads.@spawn`) and one `init()` per
  partition, each running the `next` loop without completion; the accumulators are merged
  **strictly in partition order** (CC-005) with `merge(a, b)`; `complete` runs once on the merged
  accumulator. A partition whose fold ends in `Reduced` stops all later partitions from being
  merged: a later partition that has not started skips its work, one that has started runs to
  its end and its result is discarded. `foldparts` **waits for every task** before it returns,
  so no task outlives the call.
- Errors: if any partition throws, also one after a `Reduced`, `foldparts` throws Base's
  `TaskFailedException` for the first failing partition in partition order (the original
  exception is its `task.exception`). The sequential path below throws the original exception.
- Otherwise: one sequential [`ChuiCore.foldxl`](@ref) over the parts flattened in order, with a
  single `init()`; `merge` is not called.

The result is defined when `merge` is associative on the accumulator type, `init()` is an identity
of `merge`, `xf` and `op` are **pure**, and **a `Reduced` returned by `op` depends only on the
element, not on the accumulator**. Each partition starts from its own `init()`, so a stop that
depends on the accumulator (`op(a, x) = a + x > 10 ? reduced(a) : a + x`, a "first `n` rows"
`op`) is decided per partition, and the result then depends on the partitioning (pinned by a test:
`[1:3, 4:10]` gives `15`, `foldxl` over `1:10` gives `10`). Use `foldxl`, or a `Take`/`TakeWhile`
transducer (which makes the pipeline stateful and so sequential), for such stops. Partitions run
concurrently and may run past a stop point (their effects happen, their results are discarded). Effectful pipelines use `foldxl`. ChuiTypes must not run `foldparts`/`foldxt` on unbounded
or effectful streams.

**Effects:** on the parallel path it spawns one task per partition (`Threads.@spawn`), so `op`,
`merge`, `init` and `xf` run concurrently and must be pure (or at least thread-safe); every task
is waited for before it returns, and a partition's exception surfaces as a `TaskFailedException`.

Cost: one task and one `init()` per partition (measured ≈0.5–0.66 kB per partition, 992 B for 1
and 2496 B for 4 partitions on Julia 1.13.2: `docs/src/performance.md`, `benchmark/allocs.jl`),
plus the per-element cost of `foldxl`.

```jldoctest
julia> using ChuiCore: foldparts, Filter, TakeWhile

julia> foldparts(+, Filter(iseven), [1:4, 5:8]; init = () -> 0, merge = +)
20

julia> foldparts(+, TakeWhile(<=(4)), [1:3, 4:10]; init = () -> 0, merge = +)   # stateful: sequential
10
```
"""
function foldparts(op::OP, xf::Transducer, parts::AbstractVector; init, merge) where {OP}
    _check_factory(init)
    isstateless(xf) || return foldxl(op, xf, Iterators.flatten(parts); init = init())
    rf = asrf(xf, op)
    isempty(parts) && return complete(rf, start(rf, init()))
    stop = Threads.Atomic{Int}(typemax(Int))
    tasks = map(enumerate(parts)) do (k, p)
        Threads.@spawn begin
            k > $stop[] && return _Skipped()
            r = _loop($rf, start($rf, $init()), p)
            r isa Reduced && Threads.atomic_min!($stop, k)
            r
        end
    end
    # Wait for every task first, so none outlives the call; then `fetch` in partition order
    # rethrows the first failure (as a `TaskFailedException`), also from a partition after a stop.
    foreach(_waitquiet, tasks)
    results = map(fetch, tasks)
    acc = first(results)
    for r in Iterators.drop(results, 1)
        acc isa Reduced && break
        r isa _Skipped && break
        acc = r isa Reduced ? Reduced(merge(acc, r.value)) : merge(acc, r)
    end
    return complete(rf, unreduced(acc))
end

# Wait for a task; its failure is rethrown later by `fetch`, in partition order.
function _waitquiet(t::Task)
    try
        wait(t)
    catch e
        e isa TaskFailedException || rethrow()
    end
    return nothing
end

"""
    foldxt(op, xf, v::AbstractVector; init, merge, ntasks = Threads.nthreads())

[`ChuiCore.foldparts`](@ref) over at most `ntasks` contiguous `view`s of `v` (no copy of the
input), with the same rules: `init` a factory, `merge` required, in-order merging, and a single
sequential fold when `xf` is not [`ChuiCore.isstateless`](@ref). Any input other than an
`AbstractVector` (a range is one) throws an `ArgumentError`: generators, sets and zips are
rejected rather than copied (collect first, or use `foldxl`). `xf` and `op` must
be pure. With an identity `init`, and no `Reduced` from `op` that depends on the accumulator
(see `foldparts`), the result does not depend on `ntasks`. Like `foldparts`, it
waits for every task before returning, and a partition's exception (also after a `Reduced`)
surfaces as a `TaskFailedException`.

**Effects:** spawns up to `ntasks` tasks (`Threads.@spawn`, through `foldparts`) when `xf` is
stateless, so `op`, `merge`, `init` and `xf` run concurrently and must be pure (or at least
thread-safe); every task is waited for, and an exception surfaces as a `TaskFailedException`.

Cost: one task, one view and one `init()` per partition, no input copy (measured 1088 B at
`ntasks = 1`, 2720 B at `ntasks = 4`, 4880 B at `ntasks = 8` on Julia 1.13.2 with 1 thread,
`benchmark/allocs.jl`).

```jldoctest
julia> using ChuiCore: foldxt, foldxl, Map

julia> v = collect(-50:50);

julia> foldxt(+, Map(abs), v; init = () -> 0, merge = +, ntasks = 4) == foldxl(+, Map(abs), v; init = 0)
true

julia> foldxt(+, Map(abs), v; init = () -> 0, merge = +, ntasks = 3)
2550
```
"""
function foldxt(op::OP, xf::Transducer, v::AbstractVector; init, merge, ntasks::Integer = Threads.nthreads()) where {OP}
    ntasks >= 1 || throw(ArgumentError("foldxt: ntasks must be ≥ 1, got $ntasks"))
    n = length(v)
    sz = max(1, cld(n, ntasks))
    lo, hi = firstindex(v), lastindex(v)
    parts = [view(v, i:min(i + sz - 1, hi)) for i in lo:sz:hi]
    return foldparts(op, xf, parts; init, merge)
end
function foldxt(op, xf::Transducer, itr; kwargs...)
    throw(ArgumentError("foldxt needs an AbstractVector, got $(typeof(itr)); collect it first, or use foldxl"))
end

# The aggregator protocol as a reducing step, a factory and a merge (structs, not closures).
struct _AggStep{A}
    agg::A
end
(s::_AggStep)(acc, x) = partial(s.agg, acc, (x,))
struct _AggInit{A}
    agg::A
end
(s::_AggInit)() = init(s.agg)
struct _AggMerge{A}
    agg::A
end
(s::_AggMerge)(a, b) = combine(s.agg, a, b)

"""
    aggregate(agg, xf, parts)

Fold the pre-partitioned `parts` (an `AbstractVector` of iterables, in order) through `xf` into
the aggregator `agg`, with CC-004 unchanged: `init(agg)` as the factory, `partial(agg, acc, (y,))`
per element, `combine(agg, a, b)` as the in-order merge (CC-005), then `final(agg, acc)` on the
completed accumulator. A stateless `xf` runs per partition (as [`ChuiCore.foldparts`](@ref)); any
other runs sequentially over the flattened parts with one `init(agg)`. `xf` must be pure. On the
parallel path it waits for every task, and a partition's exception surfaces as a
`TaskFailedException` (as in `foldparts`).

**Effects:** as [`ChuiCore.foldparts`](@ref): for a stateless `xf` it spawns one task per
partition, so `xf` and the aggregator's methods run concurrently and must be pure (or at least
thread-safe); every task is waited for, and an exception surfaces as a `TaskFailedException`.

Cost: one task and one `init(agg)` per partition (measured 992 B for 1 and 2496 B for 4
partitions on Julia 1.13.2, `docs/src/performance.md`), one `partial` call per element.

```jldoctest
julia> using ChuiCore: aggregate, Map, Filter, Sum, Mean

julia> aggregate(Sum(), Map(abs), [[-1, 2], [-3, 4]])
10

julia> aggregate(Mean(), Filter(isodd) ⨟ Map(float), [1:4, 5:8])
4.0
```
"""
function aggregate(agg, xf::Transducer, parts::AbstractVector)
    acc = foldparts(_AggStep(agg), xf, parts; init = _AggInit(agg), merge = _AggMerge(agg))
    return final(agg, acc)
end
