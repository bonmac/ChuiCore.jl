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
`Thunk` does not escape); each `force` is one call of `f`, about 1.2–1.5 ns plus `f`'s work
(research §5). Fully inferred: `force(Thunk(f))` has `f`'s return type.
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

Cost (indicative): construction allocates the cell and a `ReentrantLock` (a few small heap
objects). A forced read is one acquire load plus a field read, no allocation: about 0.7 ns per
read when inlined in a hot loop (this implementation, 1.10.12 and 1.13.2), and 5.7–6.2 ns per
non-inlined call in the research prototype (`median(@benchmark force(x))`), against about 2 ns for
an unsynchronised cell that is provably racy (research §5). `force(::Lazy{T})` infers `T`. The
first force takes the lock once.
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

Cost: one atomic load.
"""
isforced(l::Lazy) = (@atomic :acquire l.state) in (_DONE, _FAILED)

"""
    @lazy expr

`Lazy(() -> expr)`: a memoised, thread-safe deferred value of `expr` (see
[`ChuiCore.Lazy`](@ref)). `expr` is evaluated at most once, by the first
[`ChuiCore.force`](@ref).

Cost: as `Lazy`; `T` comes from inference of `expr`.
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
