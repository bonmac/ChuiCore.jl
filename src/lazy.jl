# Laziness (plan "Laziness (R5)"; research recursion-schemes-free-laziness.md §5, recommendation 7):
# `Thunk` (no memo), the memoised thread-safe `Lazy`, `force`, `isforced`, `@lazy`, and the
# deferred Functor/Applicative/Monad instances on `LazyTag()`. Works on Julia 1.10: no
# `OncePerProcess` (1.12+) or `Lockable` (1.11+).

"""
    Thunk(f)

A deferred computation without memoisation: [`ChuiCore.force`](@ref)`(t)` calls `f()` on every
force, so a side effect in `f` happens once per force. Use [`ChuiCore.Lazy`](@ref) to evaluate at
most once.

Cost: a struct holding `f` (no allocation when `f` captures nothing or only bits values and the
`Thunk` does not escape); each `force` is one call of `f`, about 1.1–1.5 ns plus `f`'s work
(BenchmarkTools medians on Apple silicon: 1.17 / 1.54 ns on Julia 1.10.12 / 1.13.2 in the
phase-1 research, 1.1 ns re-measured on 1.13.2 on 2026-10-20; indicative). Fully inferred:
`force(Thunk(f))` has `f`'s return type.

**Effects:** none of its own; each `force` runs `f`, so `f`'s effects happen once per force.

```jldoctest
julia> using ChuiCore: Thunk, force

julia> calls = Ref(0);

julia> t = Thunk(() -> (calls[] += 1; 42));

julia> force(t), force(t)
(42, 42)

julia> calls[]                 # no memo: the body ran twice
2
```
"""
struct Thunk{F}
    f::F
end

# State of a `Lazy` cell. `_RUNNING` is seen only by the task that holds the lock (a cycle).
const _PENDING = 0x00
const _RUNNING = 0x01
const _DONE = 0x02
const _FAILED = 0x03

struct _Forced end   # constructor marker for an already-evaluated `Lazy`

"""
    Lazy{T}(f)
    Lazy(f)

A memoised deferred value: `f()` is evaluated by the first [`ChuiCore.force`](@ref), converted to
`T` and stored, and every later `force` returns the stored value. `Lazy(f)` takes `T` from
`Base.promote_op(f)`, i.e. from inference: a type-unstable body gives a non-concrete `T` (for
`f() = rand() < 2 ? 1 : 1.0`, `T == Union{Float64, Int64}`), and a body that always throws gives
`T == Union{}`. Prefer `Lazy{T}(f)` when the body is not type-stable. [`ChuiCore.@lazy`](@ref)` expr`
is `Lazy(() -> expr)`.

Semantics (thread-safe by default):

- **At most once.** The body runs at most once, also when several tasks or threads `force` the
  same `Lazy` at the same time: an `@atomic` state field and a `ReentrantLock`, with
  double-checked locking. The others wait for the first and read its result.
- **A throwing body is cached.** If `f()` throws, the exception is stored and rethrown by this
  and every later `force` (the original backtrace is not kept). Re-running the body would break
  the at-most-once promise (its side effects would repeat) and could give different tasks
  different answers for the same cell; Haskell's thunks behave the same way. Build a fresh `Lazy`
  to retry.
- **A cycle is an error, not a recursion.** A body that forces its own `Lazy` (on the same task;
  the lock is reentrant) throws an `ArgumentError`, which is then cached like any exception.
- **The closure is dropped** after evaluation (successful or not), so data it captured can be
  garbage-collected.

[`ChuiCore.isforced`](@ref) tells whether the body has run. `show` never forces. The tag is
[`ChuiCore.LazyTag`](@ref)`()`: Functor, Applicative, Monad, all deferred.

For lazy *sequences*, use `Base.Iterators` (fused at compile time, no allocation); `Lazy` is for
a shared value or structure computed on demand.

Cost (indicative): construction allocates the cell and a `ReentrantLock` (4 allocations,
160 bytes, about 14 ns for a body that captures nothing, on Julia 1.13.2). A forced read is one
acquire load plus a field read, no allocation: about 2–2.5 ns inlined and 2.5–3 ns through a
`@noinline` call, on Julia 1.10.12 and 1.13.2 (BenchmarkTools medians, Apple silicon,
re-measured on 2026-10-20 with the cell behind a `Ref` so the read is not constant-folded; the
phase-1 research prototype, on a loaded machine, gave 5.7–6.2 ns). `force(::Lazy{T})` infers
`T`. The first force takes the lock once.

**Effects:** the first `force` runs the body once, under the cell's lock, and stores its value
(or its exception) in the cell; the body's own effects happen then. Construction runs nothing.

```jldoctest
julia> using ChuiCore: Lazy, force, isforced

julia> calls = Ref(0);

julia> l = Lazy(() -> (calls[] += 1; 6 * 7))
Lazy{Int64}(<unevaluated>)

julia> force(l), force(l)
(42, 42)

julia> calls[]                 # memoised: the body ran once
1

julia> l
Lazy{Int64}(42)

julia> bad = Lazy{Int}(() -> error("boom"));

julia> force(bad)
ERROR: boom
[...]

julia> isforced(bad), bad      # the exception is cached
(true, Lazy{Int64}(<threw ErrorException>))
```
"""
mutable struct Lazy{T, F}
    @atomic state::UInt8
    f::Union{F, Nothing}
    const lock::ReentrantLock
    value::T
    err::Any
    Lazy{T}(f::F) where {T, F} = new{T, F}(_PENDING, f, ReentrantLock())
    Lazy{T}(::_Forced, x) where {T} = new{T, Nothing}(_DONE, nothing, ReentrantLock(), x, nothing)
end

Lazy(f) = Lazy{Base.promote_op(f)}(f)

"""
    force(x)

The value of a deferred computation: for a [`ChuiCore.Thunk`](@ref), `f()` (every time); for a
[`ChuiCore.Lazy`](@ref), the memoised value (the body runs at most once; a cached exception is
rethrown). For any other value, `force(x) === x`, so code can force values that may or may not be
lazy.

Cost: see `Thunk` and `Lazy`; on a plain value it is the identity (0 ns after inlining).

**Effects:** forcing a `Thunk` runs its body (every time); the first force of a `Lazy` runs its
body once under the cell's lock and memoises the result; on any other value, none.

```jldoctest
julia> using ChuiCore: Thunk, force, @lazy

julia> force(3)                # not lazy: returned as is
3

julia> force(Thunk(() -> 1 + 1))
2

julia> force(@lazy 2^10)
1024
```
"""
force(x) = x
force(t::Thunk) = t.f()

function force(l::Lazy{T}) where {T}
    s = @atomic :acquire l.state
    s === _DONE && return l.value::T
    return _force_slow(l)::T
end

@noinline function _force_slow(l::Lazy{T}) where {T}
    lock(l.lock)
    return try
        s = @atomic :monotonic l.state
        if s === _PENDING
            @atomic :monotonic l.state = _RUNNING
            f = l.f
            v = try
                convert(T, f())
            catch e
                l.err = e
                l.f = nothing
                @atomic :release l.state = _FAILED
                rethrow()
            end
            l.value = v
            l.f = nothing
            @atomic :release l.state = _DONE
            return v
        elseif s === _DONE
            return l.value
        elseif s === _RUNNING
            throw(ArgumentError("cycle: the body of a Lazy forced the same Lazy"))
        else
            throw(l.err)
        end
    finally
        unlock(l.lock)
    end
end

"""
    isforced(l::Lazy) -> Bool

Whether the body of `l` has run, whether it returned a value or threw (a cached exception counts
as forced). Never forces.

Cost: one atomic load (about 2 ns, Julia 1.13.2, Apple silicon; indicative).

```jldoctest
julia> using ChuiCore: Lazy, force, isforced

julia> l = Lazy(() -> 1);

julia> isforced(l)
false

julia> force(l);

julia> isforced(l)
true
```
"""
isforced(l::Lazy) = (@atomic :acquire l.state) in (_DONE, _FAILED)

"""
    @lazy expr

`Lazy(() -> expr)`: a memoised, thread-safe deferred value of `expr` (see
[`ChuiCore.Lazy`](@ref)). `expr` is evaluated at most once, by the first
[`ChuiCore.force`](@ref).

Cost: as `Lazy`; `T` comes from inference of `expr`.

**Effects:** as `Lazy`: nothing runs at `@lazy`; the first `force` evaluates `expr` once, under
the cell's lock, and memoises it.

```jldoctest
julia> using ChuiCore: force, isforced, @lazy

julia> x = @lazy sum(1:100)
Lazy{Int64}(<unevaluated>)

julia> force(x)
5050

julia> isforced(x)
true
```
"""
macro lazy(ex)
    return :(Lazy(() -> $(esc(ex))))
end

function Base.show(io::IO, l::Lazy{T}) where {T}
    print(io, "Lazy{", T, "}(")
    s = @atomic :acquire l.state
    if s === _DONE
        show(io, l.value)
    elseif s === _FAILED
        print(io, "<threw ", typeof(l.err), ">")
    else
        print(io, "<unevaluated>")
    end
    return print(io, ")")
end

# ---------------------------------------------------------------------------------------------
# Constructor classes (ADR-0001 §3): every operation is deferred.

"""
    LazyTag()

Constructor-class tag (ADR-0001 §3) for [`ChuiCore.Lazy`](@ref): Functor, Applicative, Monad, all
deferred. `fmap(f, l)` returns a new `Lazy` that forces `l` only when it is itself forced;
`pure(LazyTag(), x)` is an already-forced `Lazy`; `ap(lf, lx)` and `chain(k, l)` are deferred the
same way. Law tests compare with `(a, b) -> isequal(force(a), force(b))`. A singleton: dispatch on
it costs nothing at run time.

Cost: each deferred operation allocates one new `Lazy` cell; forcing a chain of `n` operations
forces `n` cells (stack depth `n`).

```jldoctest
julia> using ChuiCore: LazyTag, force, isforced, @lazy

julia> base = @lazy 10;

julia> y = ChuiCore.fmap(x -> x + 1, base);

julia> z = chain(x -> @lazy(2x), y);

julia> isforced(base)          # nothing has run yet
false

julia> force(z)
22

julia> force(ChuiCore.pure(LazyTag(), 5))
5
```
"""
struct LazyTag end

constructorclass(::Type{<:Lazy}) = LazyTag()
FunctorStyle(::LazyTag) = IsFunctor()
ApplicativeStyle(::LazyTag) = IsApplicative()
MonadStyle(::LazyTag) = IsMonad()

fmap(::IsFunctor, f, l::Lazy) = Lazy(() -> f(force(l)))
pure(::LazyTag, x::T) where {T} = Lazy{T}(_Forced(), x)
ap(::IsApplicative, ff::Lazy, fx::Lazy) = Lazy(() -> force(ff)(force(fx)))
chain(::IsMonad, f, m::Lazy) = Lazy(() -> force(f(force(m))))
