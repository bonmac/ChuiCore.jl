# The aggregation protocol (CC-004, CC-005), the "no value yet" state (CC-006), `neutral`,
# `AlgebraClass` and `combineall` (ADR-0001 §1–2, §4, §7).

"""
    init(agg)

A fresh accumulator for the aggregator `agg` (CC-004): a **factory**, so every call returns a new
accumulator that shares no mutable state with any other. It may be the internal "no value yet"
state (CC-006) for aggregators without an identity (`Max`, `First`, `Moments`, `ReduceM` with no
neutral).

```jldoctest
julia> using ChuiCore: init, Sum, Mean, Max

julia> init(Sum()), init(Mean())
(0, (0.0, 0))

julia> init(Max())   # the internal "no value yet" state
ChuiCore.NoValue()
```

Cost: a constant for every built-in (all their accumulators are immutable), so no allocation;
`ReduceM(op; neutral = x)` with a mutable `x` pays one `deepcopy(x)` per call.
"""
function init end

"""
    partial(agg, acc, chunk)

Fold every element of `chunk` (any iterable: a vector, a generator, an `Iterators.flatten`, an
empty one) into the accumulator `acc` and return the updated accumulator (CC-004). It **may mutate
`acc`**; callers always use the return value.

```jldoctest
julia> using ChuiCore: partial, init, Sum

julia> acc = partial(Sum(), init(Sum()), [1, 2]);

julia> partial(Sum(), acc, Iterators.flatten(([3], [4, 5])))   # keep folding into acc
15

julia> partial(Sum(), acc, Int[])   # an empty chunk leaves the accumulator as it was
3
```

Cost: at most one pass over `chunk`. Built-in fast paths on a non-empty `AbstractArray`: `Sum`,
`Prod` and `Mean` call Base's `sum`/`prod`; `Count` and `Last` are O(1); `First` reads one
element. No built-in allocates (test item "perf allocs: built-in aggregators
partial/combine/final are 0 B").

Effects: may mutate `acc` (CC-004 allows it); no built-in does, since their accumulators are
immutable, but `ReduceM` with a mutating `op` and a declared neutral does.
"""
function partial end

"""
    combine(agg, a, b)

Merge the accumulator `a` of an earlier partition with the accumulator `b` of a later one (CC-004).
It may mutate and return `a`; do not reuse `a` or `b` afterwards. The "no value yet" state is an
identity on either side. ChuiCore defines **no** 2-argument or variadic method (ADR-0001 §1).

```jldoctest
julia> using ChuiCore: combine, partial, init, final, Max

julia> a = partial(Max(), init(Max()), [4, 1]); b = partial(Max(), init(Max()), [6]);

julia> combine(Max(), a, b)
6

julia> combine(Max(), a, init(Max()))   # "no value yet" is an identity
4
```

Cost: one operation on the two accumulators for every built-in (`+`, `max`, a tuple merge, a
Chan merge for `Moments`, one `op` call for `ReduceM`); O(1) and no allocation for number
elements.

Effects: may mutate `a` (CC-004 allows it); no built-in does, but `ReduceM` with a mutating `op`
does.
"""
function combine end

"""
    final(agg, acc)

Turn an accumulator into the user-visible result (CC-004). Fallback: `final(agg, acc) = acc`.
Aggregators without an identity throw CC-007's exception type on the "no value yet" state.

```jldoctest
julia> using ChuiCore: final, Sum, Mean, Last, init

julia> final(Sum(), 15), final(Mean(), (6.0, 3))
(15, 2.0)

julia> final(Last(), init(Last()))
ERROR: BoundsError: attempt to access Tuple{} at index [0]
Stacktrace:
[...]
```

Cost: O(1) for every built-in: the identity fallback, one division for `Mean`, one division and
an optional `sqrt` for `Moments`.
"""
final(agg, acc) = acc

"""
    iscommutative(agg)::Bool

Whether `combine(agg, a, b)` and `combine(agg, b, a)` finalize to equal results (CC-005). Default
`false`: executors then combine accumulators in partition order.

```jldoctest
julia> using ChuiCore: iscommutative, Sum, First, ReduceM

julia> iscommutative(Sum()), iscommutative(First()), iscommutative(ReduceM(max; commutative = true))
(true, false, true)

julia> iscommutative(:my_aggregator)   # nothing declared: false
false
```

Cost: dispatch-only for the built-ins (a constant, or a type parameter for `ReduceM`), so it
folds to a constant at compile time and costs nothing at run time.
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

```jldoctest
julia> ChuiCore.AlgebraClass(ChuiCore.Max()) === ChuiCore.IsSemigroup()
true
```

Cost: none at run time; a singleton value that trait dispatch folds away at compile time.
"""
struct IsSemigroup end

"""
    IsMonoid()

`AlgebraClass` value of an instance with a true identity: `neutral(m)` exists (ADR-0001 §2).

```jldoctest
julia> ChuiCore.AlgebraClass(ChuiCore.Sum()) === ChuiCore.IsMonoid()
true
```

Cost: none at run time; a singleton value that trait dispatch folds away at compile time.
"""
struct IsMonoid end

"""
    NotAlgebra()

The default `AlgebraClass`: nothing is declared. Such an aggregator still works everywhere CC-004
is used; only `combineall` and the law kits read the class.

```jldoctest
julia> struct Tally end   # an aggregator that declares no class

julia> ChuiCore.AlgebraClass(Tally())
ChuiCore.NotAlgebra()
```

Cost: none at run time; a singleton value that trait dispatch folds away at compile time.
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

```jldoctest
julia> using ChuiCore: AlgebraClass, Sum, First, Moments, ReduceM

julia> AlgebraClass(Sum()), AlgebraClass(First()), AlgebraClass(Moments())
(ChuiCore.IsMonoid(), ChuiCore.IsSemigroup(), ChuiCore.IsSemigroup())

julia> AlgebraClass(ReduceM(+; neutral = 0)), AlgebraClass(typeof(Sum()))
(ChuiCore.IsMonoid(), ChuiCore.IsMonoid())
```

Cost: none at run time (see above).
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
`true`, `Mean` → `(0.0, 0)`, `ReduceM(op; neutral = x)` → a copy of `x`.

```jldoctest
julia> using ChuiCore: neutral, Sum, Prod, AllM, ReduceM

julia> neutral(Sum()), neutral(Sum(), Float64), neutral(Prod(), Float32), neutral(AllM())
(0, 0.0, 1.0f0, true)

julia> r = ReduceM(append!; neutral = Int[]);

julia> v = neutral(r); push!(v, 1); neutral(r)   # a fresh copy every call
Int64[]
```

Cost: a constant for the built-ins; one `deepcopy` per call for a mutable neutral declared to
`ReduceM`; `neutral(T)` adds one `default_monoid(T)` dispatch.
"""
function neutral end
neutral(m, ::Type{T}) where {T} = neutral(m)
neutral(::Type{T}) where {T} = neutral(default_monoid(T), T)

"""
    default_monoid(::Type{T})

The monoid instance that `neutral(T)` uses for element type `T`. There is no default, not even for
numbers (which have several monoids): the fallback throws an `ArgumentError`. Downstream code adds
methods for its own types.

```jldoctest
julia> struct Bag
           n::Int
       end

julia> ChuiCore.default_monoid(::Type{Bag}) = ChuiCore.Count()

julia> ChuiCore.neutral(Bag)
0

julia> ChuiCore.neutral(Int)
ERROR: ArgumentError: no default monoid for Int64: define ChuiCore.default_monoid(::Type{Int64})
Stacktrace:
[...]
```

Cost: one dispatch on the type, resolved at compile time when `T` is known; the methods return
constants.
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

```jldoctest
julia> using ChuiCore: combineall, partial, init, final, Sum, Max

julia> accs = [partial(Sum(), init(Sum()), c) for c in ([1, 2], Int[], [3])];

julia> final(Sum(), combineall(Sum(), accs))
6

julia> combineall(Sum(), Int[])   # IsMonoid: the identity
0

julia> combineall(Max(), Int[])   # IsSemigroup: "no value yet"
ChuiCore.NoValue()
```

Cost: one `combine` per accumulator; the trait dispatch is free. From "no value yet" the result
is a small `Union` (ADR-0001 §7).
"""
combineall(m, accs) = _combineall(AlgebraClass(m), m, accs)
_combineall(::IsMonoid, m, accs) = foldl((a, b) -> combine(m, a, b), accs; init = neutral(m))
_combineall(::IsSemigroup, m, accs) = foldl((a, b) -> combine(m, a, b), accs; init = init(m))
_combineall(::NotAlgebra, m, accs) = reduce((a, b) -> combine(m, a, b), accs)
