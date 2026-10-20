# Law tables of the monoid-family kits (ADR-0007): `test_semigroup_laws`, `test_monoid_laws`,
# `test_aggregator_laws`. Each returns `Law`s over ONE generator (samples, or chunks); the drivers
# in ext/ run them. Carrier values are always fresh thunks, `partial(m, init(m), collect(x))`,
# rebuilt at every use, because `partial` and `combine` may mutate (CC-004).

# A fresh accumulator holding the chunk `x`.
_acc(m, x) = partial(m, init(m), collect(x))

# CC-004's `R`: the result of `agg` on the ordered chunks.
function _R(agg, chunks)
    a = _acc(agg, first(chunks))
    for x in Iterators.drop(chunks, 1)
        a = combine(agg, a, _acc(agg, x))
    end
    return final(agg, a)
end

# CC-006's empty-input exceptions are outcomes too: an empty sample makes both sides of a law
# throw the same type, which is agreement. Any other exception propagates (the law then errors).
struct _Threw
    type::DataType
end
function _outcome(f)
    return try
        f()
    catch e
        e isa Union{ArgumentError, BoundsError} || rethrow()
        _Threw(typeof(e))
    end
end
_eqo(eq, r₁, r₂, v) = r₁ isa _Threw || r₂ isa _Threw ? isequal(r₁, r₂) : eq(r₁, r₂, v)

_flat(xs...) = collect(Iterators.flatten(map(collect, xs)))

# CC-004 law 1's fixed ordered splits of `v`: an empty first, middle and last chunk, halves,
# thirds, and singletons.
function _splits(v)
    n = length(v)
    e = v[1:0]
    h, i, j = n ÷ 2, n ÷ 3, (2n) ÷ 3
    s = Any[
        [e, v], [v, e], [v[1:h], v[(h + 1):n]], [v[1:h], e, v[(h + 1):n]],
        [v[1:i], v[(i + 1):j], v[(j + 1):n]], [e, v[1:h], e, v[(h + 1):n], e],
    ]
    n >= 1 && push!(s, [v[k:k] for k in 1:n])
    return s
end

"""
    _semigroup_laws(m, eq)

Law table of [`test_semigroup_laws`](@ref): `associativity` of `combine(m, ·, ·)` on carriers built
from three chunks, compared after `final` with `eq(r₁, r₂, v)`, `v` the concatenated chunks.
"""
function _semigroup_laws(m, eq)
    assoc = function (x, y, z)
        l = _outcome(() -> final(m, combine(m, combine(m, _acc(m, x), _acc(m, y)), _acc(m, z))))
        r = _outcome(() -> final(m, combine(m, _acc(m, x), combine(m, _acc(m, y), _acc(m, z)))))
        return _eqo(eq, l, r, _flat(x, y, z))
    end
    return (Law("associativity", (1, 1, 1), assoc),)
end

"""
    _monoid_laws(m, eq)

Law table of [`test_monoid_laws`](@ref): the semigroup laws plus `left identity`, `right identity`
(`combine` with `neutral(m)` on either side finalizes like the carrier alone), `neutral matches
init` (`isequal(final(m, init(m)), final(m, neutral(m)))`; its sample argument is unused) and
`neutral is fresh` (combining into one `neutral(m)` leaves a later `neutral(m)`'s `final`
unchanged).
"""
function _monoid_laws(m, eq)
    left = function (x)
        n = neutral(m)
        a = _acc(m, x)
        return _eqo(eq, _outcome(() -> final(m, combine(m, n, a))), _outcome(() -> final(m, _acc(m, x))), _flat(x))
    end
    right = function (x)
        a = _acc(m, x)
        n = neutral(m)
        return _eqo(eq, _outcome(() -> final(m, combine(m, a, n))), _outcome(() -> final(m, _acc(m, x))), _flat(x))
    end
    matches = _ -> isequal(_outcome(() -> final(m, init(m))), _outcome(() -> final(m, neutral(m))))
    fresh = function (x)
        a = _acc(m, x)
        before = deepcopy(_outcome(() -> final(m, neutral(m))))
        combine(m, neutral(m), a)
        return isequal(_outcome(() -> final(m, neutral(m))), before)
    end
    return (
        _semigroup_laws(m, eq)...,
        Law("left identity", (1,), left),
        Law("right identity", (1,), right),
        Law("neutral matches init", (1,), matches),
        Law("neutral is fresh", (1,), fresh),
    )
end

"""
    _aggregator_laws(agg, eq; reference = nothing)

Law table of [`test_aggregator_laws`](@ref), over one generator of sample inputs `v`:

- `split invariance` (CC-004 law 1): `R(agg, split) ≈ R(agg, [v])` for fixed ordered splits of `v`
  (an empty first, middle and last chunk, halves, thirds, singletons);
- `empty partition identity` (law 2): an accumulator of an empty chunk on either side of `combine`;
- `chunk concatenation` (law 3), on two samples `x`, `y`: `partial` of `y` into the accumulator of
  `x` equals `partial` of `Iterators.flatten((x, y))` into `init(agg)`;
- `commutativity` (CC-005), on two samples: always in the table, vacuously `true` unless
  `iscommutative(agg)`;
- `init is fresh`: two `init(agg)` taken before any `partial` do not alias;
- `agrees with reference` (only when `reference !== nothing`), on non-empty `v`:
  `R(agg, [v]) ≈ reference(v)`. CC-004 law 4 (`R(agg, split) ≈` Base) is the conjunction of this law
  and `split invariance`: this one checks Base agreement, the other covers the splits (lead's
  decision, 2026-10-20).

Results are finalized and compared with `eq(r₁, r₂, v)`. When both sides throw the same CC-006
exception type (`ArgumentError`, `BoundsError`), they agree.
"""
function _aggregator_laws(agg, eq; reference = nothing)
    split = function (x)
        v = collect(x)
        whole = _outcome(() -> _R(agg, (v,)))
        return all(s -> _eqo(eq, _outcome(() -> _R(agg, s)), whole, v), _splits(v))
    end
    empty_identity = function (x)
        v = collect(x)
        E() = _acc(agg, similar(v, 0))
        A() = _acc(agg, v)
        alone = _outcome(() -> final(agg, A()))
        l = _outcome(() -> final(agg, combine(agg, E(), A())))
        r = _outcome(() -> final(agg, combine(agg, A(), E())))
        return _eqo(eq, l, alone, v) && _eqo(eq, r, alone, v)
    end
    concat = function (x, y)
        l = _outcome(() -> final(agg, partial(agg, _acc(agg, x), collect(y))))
        r = _outcome(() -> final(agg, partial(agg, init(agg), Iterators.flatten((collect(x), collect(y))))))
        return _eqo(eq, l, r, _flat(x, y))
    end
    commutes = function (x, y)
        iscommutative(agg) || return true
        l = _outcome(() -> final(agg, combine(agg, _acc(agg, x), _acc(agg, y))))
        r = _outcome(() -> final(agg, combine(agg, _acc(agg, y), _acc(agg, x))))
        return _eqo(eq, l, r, _flat(x, y))
    end
    init_fresh = function (x)
        v = collect(x)
        a, b = init(agg), init(agg)
        partial(agg, a, collect(v))
        l = _outcome(() -> final(agg, partial(agg, b, collect(v))))
        return _eqo(eq, l, _outcome(() -> _R(agg, (v,))), v)
    end
    laws = (
        Law("split invariance", (1,), split),
        Law("empty partition identity", (1,), empty_identity),
        Law("chunk concatenation", (1, 1), concat),
        Law("commutativity", (1, 1), commutes),
        Law("init is fresh", (1,), init_fresh),
    )
    reference === nothing && return laws
    agrees = function (x)
        v = collect(x)
        isempty(v) && return true
        return _eqo(eq, _outcome(() -> _R(agg, (v,))), _outcome(() -> reference(collect(v))), v)
    end
    return (laws..., Law("agrees with reference", (1,), agrees))
end
