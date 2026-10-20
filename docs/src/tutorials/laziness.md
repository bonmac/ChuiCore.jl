# Laziness

```@meta
DocTestSetup = :(using ChuiCore)
```

Julia evaluates eagerly. ChuiCore adds two small tools for deferring a computation until its value
is needed: `Thunk`, which re-runs its body on every force, and `Lazy`, which runs it at most once
and remembers the result, safely across threads. Both are public, not exported:

```jldoctest lazy
julia> using ChuiCore: Thunk, Lazy, force, isforced, @lazy, LazyTag
```

## `Thunk`: deferred, not remembered

`Thunk(f)` holds a zero-argument function. `force(t)` calls it, every time.

```jldoctest lazy
julia> runs = Ref(0);

julia> t = Thunk(() -> (runs[] += 1; 2 + 2));

julia> runs[]                  # building it ran nothing
0

julia> force(t), force(t)
(4, 4)

julia> runs[]                  # one run per force
2
```

Use a `Thunk` when the body is cheap, or when you *want* it re-evaluated (it reads something that
changes), and there is no sharing to protect.

## `Lazy`: deferred and memoised

`Lazy(f)` runs `f()` on the first `force` and stores the value; later forces return the stored
value. `@lazy expr` is `Lazy(() -> expr)`. `isforced` tells whether the body has run, without
running it, and `show` never forces.

```jldoctest lazy
julia> runs = Ref(0);

julia> x = @lazy (runs[] += 1; sum(abs2, 1:10))
Lazy{Int64}(<unevaluated>)

julia> isforced(x)
false

julia> force(x), force(x)
(385, 385)

julia> runs[]                  # the body ran once
1

julia> x
Lazy{Int64}(385)
```

The element type comes from inference of the body. A body that is not type-stable gives a
non-concrete cell; name the type with `Lazy{T}(f)` then:

```jldoctest lazy
julia> Lazy(() -> rand() < 2 ? 1 : 1.0)
Lazy{Union{Float64, Int64}}(<unevaluated>)

julia> Lazy{Float64}(() -> rand() < 2 ? 1 : 1.0)    # converted to Float64 when forced
Lazy{Float64}(<unevaluated>)
```

### Thread-safe, at most once

The body runs at most once even when several tasks force the same `Lazy` at the same time: the
first takes the cell's lock and runs the body, the others wait and read its result.

```jldoctest lazy
julia> runs = Threads.Atomic{Int}(0);

julia> shared = Lazy(() -> (Threads.atomic_add!(runs, 1); 42));

julia> results = fetch.([Threads.@spawn force(shared) for _ in 1:8]);

julia> all(==(42), results), runs[]
(true, 1)
```

### Exceptions and cycles are cached

If the body throws, the exception is stored and rethrown by this and every later `force`: running
the body again would repeat its side effects and could give different tasks different answers.
A body that forces its own cell is a cycle, reported as an `ArgumentError` (and cached the same
way). Build a fresh `Lazy` to retry.

```jldoctest lazy
julia> boom = Lazy{Int}(() -> error("no data"));

julia> force(boom)
ERROR: no data
[...]

julia> isforced(boom), boom
(true, Lazy{Int64}(<threw ErrorException>))

julia> loop = Lazy{Int}(() -> force(loop) + 1);

julia> force(loop)
ERROR: ArgumentError: cycle: the body of a Lazy forced the same Lazy
[...]
```

After evaluation the cell drops its closure, so data the body captured can be garbage-collected.

### `force` on anything

`force` of a value that is not lazy is the value itself, so code can accept "maybe lazy" inputs:

```jldoctest lazy
julia> force(7), force(Thunk(() -> 7)), force(@lazy 7)
(7, 7, 7)
```

## Mapping and chaining without forcing: `LazyTag`

`Lazy` is a Functor, an Applicative and a Monad (its constructor-class tag is `LazyTag()`), and
every operation is **deferred**: `ChuiCore.fmap`, `ChuiCore.ap` and `chain` return a new `Lazy`
that forces its inputs only when it is forced itself. `ChuiCore.pure(LazyTag(), v)` is an
already-forced cell.

```jldoctest lazy
julia> runs = Ref(0);

julia> raw = @lazy (runs[] += 1; [3, 1, 2]);

julia> sorted = ChuiCore.fmap(sort, raw);

julia> top = chain(v -> @lazy(last(v)), sorted);

julia> runs[], isforced(raw)   # nothing has run
(0, false)

julia> force(top)
3

julia> force(sorted), runs[]   # raw ran once, shared by both
([1, 2, 3], 1)

julia> two = ChuiCore.pure(LazyTag(), 2)
Lazy{Int64}(2)

julia> force(ChuiCore.ap(ChuiCore.pure(LazyTag(), x -> 10x), two))
20
```

The law kits compare lazy values by what they force to:
`eq = (a, b) -> isequal(force(a), force(b))`.

## Lazy sequences: use `Base.Iterators`

`Lazy` is for one shared value, or a structure computed on demand. For lazy *sequences* use
`Base.Iterators` and generators: they are fused at compile time, allocate nothing per element,
and need no cells at all.

```jldoctest lazy
julia> using Base.Iterators: countfrom, take

julia> squares_of_evens = (n^2 for n in countfrom(1) if iseven(n));   # infinite, nothing computed

julia> collect(take(squares_of_evens, 4))
4-element Vector{Int64}:
  4
 16
 36
 64
```

A vector of `Lazy` cells, one per element, would pay a lock and a heap cell per element for
nothing.

## What it costs

Measured with BenchmarkTools medians on Apple silicon, Julia 1.13.2 and 1.10.12, the cell behind
a `Ref` so the compiler cannot fold the read away, on a loaded machine; indicative only
(evidence `.lanes/evidence/p5-optics-costs-{release,lts}-8fbb53f.txt`).

- **`Thunk`:** a struct holding the function, no allocation when it does not escape; each `force`
  is one call of the body, about 1.1 ns plus the body's own work.
- **`Lazy`, construction:** the cell and its `ReentrantLock`: 4 allocations, 160 bytes, about
  14 ns. The first `force` takes the lock once and runs the body.
- **`Lazy`, forced reads:** one atomic acquire load and a field read, no allocation: about
  2–2.6 ns inlined, 2.4–3.1 ns through a non-inlined call. An unsynchronised cell would be a little
  cheaper and is not thread-safe (the phase-1 research measured repeated initialisation under
  four threads).
- **`isforced`:** one atomic load, about 2 ns.
- **`fmap`, `ap`, `chain`:** one new `Lazy` cell each; forcing a chain of `n` operations forces
  `n` cells, nested (stack depth `n`), so build deep chains with a loop over values, not cells.
- **`Base.Iterators`:** no cells, no locks; the cheapest way to be lazy over a sequence.

Reference: [`ChuiCore.Thunk`](@ref ChuiCore.Thunk), [`ChuiCore.Lazy`](@ref ChuiCore.Lazy),
[`ChuiCore.force`](@ref ChuiCore.force), [`ChuiCore.isforced`](@ref ChuiCore.isforced),
[`ChuiCore.@lazy`](@ref ChuiCore.@lazy), [`ChuiCore.LazyTag`](@ref ChuiCore.LazyTag).
