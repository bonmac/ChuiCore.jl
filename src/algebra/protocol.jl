# The aggregation protocol (CC-004, CC-005), the "no value yet" state (CC-006), `neutral`,
# `AlgebraClass` and `combineall` (ADR-0001 §1–2, §4, §7).

"""
    init(agg)

A fresh accumulator for the aggregator `agg` (CC-004): a **factory**, so every call returns a new
accumulator that shares no mutable state with any other. It may be the internal "no value yet"
state (CC-006) for aggregators without an identity (`Max`, `First`, `Moments`, `ReduceM` with no
neutral). Cost: one small allocation at most for the built-ins (none for immutable accumulators).
"""
function init end

"""
    partial(agg, acc, chunk)

Fold every element of `chunk` (any iterable: a vector, a generator, an `Iterators.flatten`, an
empty one) into the accumulator `acc` and return the updated accumulator (CC-004). It **may mutate
`acc`**; callers always use the return value. Cost: one pass over `chunk`; the built-ins take a
`sum`-based fast path on a non-empty `AbstractArray`.
"""
function partial end

"""
    combine(agg, a, b)

Merge the accumulator `a` of an earlier partition with the accumulator `b` of a later one (CC-004).
It may mutate and return `a`; do not reuse `a` or `b` afterwards. The "no value yet" state is an
identity on either side. ChuiCore defines **no** 2-argument or variadic method (ADR-0001 §1).
Cost: O(1) for every built-in (one operation on the accumulators).
"""
function combine end

"""
    final(agg, acc)

Turn an accumulator into the user-visible result (CC-004). Fallback: `final(agg, acc) = acc`.
Aggregators without an identity throw CC-007's exception type on the "no value yet" state.
"""
final(agg, acc) = acc

"""
    iscommutative(agg)::Bool

Whether `combine(agg, a, b)` and `combine(agg, b, a)` finalize to equal results (CC-005). Default
`false`: executors then combine accumulators in partition order. Dispatch-only for the built-ins
(a constant, or a type parameter for `ReduceM`), so it costs nothing at run time.
"""
iscommutative(_) = false

"""
    NoValue()

Internal: the "no value yet" accumulator of the aggregators without an identity (CC-006).
`combine` treats it as an identity on either side; `final` turns it into CC-007's empty-input
result (an exception for `Max`, `First`, …; `NaN` for `Moments`).
"""
struct NoValue end

# `op` with `NoValue` as an identity on either side. Each identity-less aggregator calls this from
# its own `combine` method: a generic `combine(::Any, ::NoValue, ::Any)` would be ambiguous with
# every downstream `combine(::MyAgg, a, b)` method.
_nv(op::F, a, b) where {F} = op(a, b)
_nv(::F, ::NoValue, b) where {F} = b
_nv(::F, a, ::NoValue) where {F} = a
_nv(::F, ::NoValue, ::NoValue) where {F} = NoValue()

# Left fold of `op` over `chunk` starting from `acc`; from `NoValue` the first element starts it.
# Returns `Union{NoValue, T}` when the chunk may be empty (ADR-0001 §7).
_fold(op::F, acc, chunk) where {F} = foldl(op, chunk; init = acc)
function _fold(op::F, ::NoValue, chunk) where {F}
    y = iterate(chunk)
    y === nothing && return NoValue()
    return foldl(op, Iterators.rest(chunk, y[2]); init = y[1])
end

# A fresh copy of a user-declared neutral element (a factory, ADR-0001 §1).
_fresh(x) = isbits(x) ? x : deepcopy(x)

"""
    IsSemigroup()

`AlgebraClass` value of an instance whose `combine` is associative but has no identity: its empty
state is `init`'s "no value yet" (CC-006).
"""
struct IsSemigroup end

"""
    IsMonoid()

`AlgebraClass` value of an instance with a true identity: `neutral(m)` exists (ADR-0001 §2).
"""
struct IsMonoid end

"""
    NotAlgebra()

The default `AlgebraClass`: nothing is declared. Such an aggregator still works everywhere CC-004
is used; only `combineall` and the law kits read the class.
"""
struct NotAlgebra end

"""
    AlgebraClass(::Type{M})
    AlgebraClass(m) = AlgebraClass(typeof(m))

The carrier algebra of the instance type `M` (ADR-0001 §2): `IsMonoid()` iff `neutral(m)` exists,
`IsSemigroup()` for an associative `combine` without identity, `NotAlgebra()` by default. It is a
dispatch-only Holy trait (methods on `Type{…}` returning constants), so a caller's trait call
folds away at compile time: zero run-time cost. Its consumer is [`ChuiCore.combineall`](@ref); it
never gates CC-004/CC-005 executors.
"""
AlgebraClass(::Type) = NotAlgebra()
AlgebraClass(m) = AlgebraClass(typeof(m))

"""
    neutral(m)
    neutral(m, ::Type{T})
    neutral(::Type{T})

The identity element of the monoid instance `m` on its carrier (ADR-0001 §1). Defined only for
instances with a true identity (`AlgebraClass(m) === IsMonoid()`); semigroups have no method.
It is a **factory**: every call returns a fresh value, because `combine` may mutate.

- `neutral(m, T)` is an optional refinement returning a concrete identity for element type `T`
  (default: `neutral(m)`); `neutral(Sum(), T) = zero(T)`, `neutral(Prod(), T) = one(T)`. It keeps
  folds type-stable where an identity exists.
- `neutral(T)` is closed sugar for `neutral(default_monoid(T), T)`: declare
  [`ChuiCore.default_monoid`](@ref), never a `neutral(::Type{T})` method.

Built-ins: `Sum` → `0`, `Prod` → `1`, `Count`, `CountTrue` → `0`, `AnyM` → `false`, `AllM` →
`true`, `Mean` → `(0.0, 0)`, `ReduceM(op; neutral = x)` → a copy of `x`. Cost: a constant, or a
`deepcopy` of a mutable declared neutral.
"""
function neutral end
neutral(m, ::Type{T}) where {T} = neutral(m)
neutral(::Type{T}) where {T} = neutral(default_monoid(T), T)

"""
    default_monoid(::Type{T})

The monoid instance that `neutral(T)` uses for element type `T`. There is no default, not even for
numbers (which have several monoids): the fallback throws an `ArgumentError`. Downstream code adds
methods for its own types.
"""
default_monoid(::Type{T}) where {T} =
    throw(ArgumentError("no default monoid for $T: define ChuiCore.default_monoid(::Type{$T})"))

"""
    combineall(m, accs)

Fold already-built accumulators `accs` (any iterable, in partition order) with `combine(m, ·, ·)`
and return the merged **accumulator** (not `final`ized). The start depends on
`AlgebraClass(m)` (ADR-0001 §2):

- `IsMonoid`: starts from `neutral(m)`, so empty `accs` gives the identity;
- `IsSemigroup`: starts from `init(m)`, the "no value yet" state;
- `NotAlgebra`: `reduce` without an initial value, which throws on empty `accs`.

Cost: one `combine` per accumulator; the trait dispatch is free. From "no value yet" the result
is a small `Union` (ADR-0001 §7).
"""
combineall(m, accs) = _combineall(AlgebraClass(m), m, accs)
_combineall(::IsMonoid, m, accs) = foldl((a, b) -> combine(m, a, b), accs; init = neutral(m))
_combineall(::IsSemigroup, m, accs) = foldl((a, b) -> combine(m, a, b), accs; init = init(m))
_combineall(::NotAlgebra, m, accs) = reduce((a, b) -> combine(m, a, b), accs)
