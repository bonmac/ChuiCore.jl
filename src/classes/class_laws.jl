# Constructor classes, part 4: the law tables of the class kits (ADR-0007). Each `_<class>_laws`
# is a pure function of `(tag, eq)` returning a tuple of `Law(name, args, pred)`; `args` indexes
# the kit's generators in the order of its docstring in `src/laws.jl`. Law names are the ones the
# kit docstrings list. Callable classes are compared extensionally on the `gen_x` inputs.

# Curried composition for the Applicative composition law: `pure(∘) <*> u <*> v <*> w`.
_curried_compose(f) = g -> f ∘ g
# `id *** g` and Haskell's `first f` as named callables (the Arrow laws lift them with `arr`).
struct _SecondOf{G} <: Function
    g::G
end
(s::_SecondOf)(p) = (p[1], s.g(p[2]))
struct _FirstOf{F} <: Function
    f::F
end
(s::_FirstOf)(p) = (s.f(p[1]), p[2])
# The applicative transformation Maybe → Vector of the Traversable naturality law.
_maybe_to_vector(::Nothing) = Union{}[]
_maybe_to_vector(x::Some) = [x.value]

# test_functor_laws(tag, gen_fa, gen_f)
function _functor_laws(tag, eq)
    return (
        Law("identity", (1,), fa -> eq(fmap(identity, fa), fa)),
        Law("composition", (1, 2, 2), (fa, f, g) -> eq(fmap(g ∘ f, fa), fmap(g, fmap(f, fa)))),
    )
end

# test_applicative_laws(tag, gen_fa, gen_f, gen_x)
function _applicative_laws(tag, eq)
    return (
        Law("identity", (1,), v -> eq(ap(pure(tag, identity), v), v)),
        Law(
            "composition", (1, 2, 1, 2, 1), function (fa1, f, fa2, g, w)
                u = fmap(_ -> f, fa1)
                v = fmap(_ -> g, fa2)
                return eq(ap(ap(ap(pure(tag, _curried_compose), u), v), w), ap(u, ap(v, w)))
            end
        ),
        Law("homomorphism", (2, 3), (f, x) -> eq(ap(pure(tag, f), pure(tag, x)), pure(tag, f(x)))),
        Law(
            "interchange", (1, 2, 3), function (fa, f, y)
                u = fmap(_ -> f, fa)
                return eq(ap(u, pure(tag, y)), ap(pure(tag, h -> h(y)), u))
            end
        ),
        Law("fmap agrees with ap", (1, 2), (fa, f) -> eq(fmap(f, fa), ap(pure(tag, f), fa))),
    )
end

# test_monad_laws(tag, gen_m, gen_k, gen_x)
function _monad_laws(tag, eq)
    return (
        Law("left identity", (2, 3), (k, x) -> eq(chain(k, pure(tag, x)), k(x))),
        Law("right identity", (1,), m -> eq(chain(x -> pure(tag, x), m), m)),
        Law(
            "associativity", (1, 2, 2),
            (m, k, h) -> eq(chain(x -> chain(h, k(x)), m), chain(h, chain(k, m))),
        ),
        Law(
            "ap agrees with chain", (1, 1), function (m1, m2)
                mf = fmap(a -> (b -> (a, b)), m1)
                return eq(ap(mf, m2), chain(f -> chain(x -> pure(tag, f(x)), m2), mf))
            end
        ),
    )
end

# test_alternative_laws(tag, gen_fa)
function _alternative_laws(tag, eq)
    return (
        Law("left identity", (1,), a -> eq(alt(zeroalt(tag), a), a)),
        Law("right identity", (1,), a -> eq(alt(a, zeroalt(tag)), a)),
        Law("associativity", (1, 1, 1), (a, b, c) -> eq(alt(alt(a, b), c), alt(a, alt(b, c)))),
    )
end

# Elements in iteration order, by calling `iterate` directly.
function _by_iteration(t)
    out = Any[]
    st = iterate(t)
    while st !== nothing
        push!(out, st[1])
        st = iterate(t, st[2])
    end
    return out
end
_snoc_any(acc, x) = vcat(acc, Any[x])

# test_foldable_laws(tag, gen_fa). The operations build lists, which is not commutative.
function _foldable_laws(tag, eq)
    return (
        Law("foldl matches iteration", (1,), t -> eq(foldl(_snoc_any, t; init = Any[]), _by_iteration(t))),
        Law(
            "foldr matches foldl", (1,),
            t -> eq(foldr((x, acc) -> vcat(Any[x], acc), t; init = Any[]), foldl(_snoc_any, t; init = Any[])),
        ),
        Law(
            "mapreduce matches foldl", (1,),
            t -> eq(mapreduce(x -> Any[x], vcat, t; init = Any[]), foldl(_snoc_any, t; init = Any[])),
        ),
    )
end

# Julia 1.10's `isequal` compares `Some` with `===` (so `Some([1]) != Some([1])`); the Traversable
# laws therefore pass both sides through `_unsome`, which turns every `Some(v)` (inside Base arrays
# and tuples and ChuiCore's own wrappers) into the tuple `(:Some, v)`, before calling `eq`.
_unsome(x) = x
_unsome(x::Some) = (:Some, _unsome(x.value))
_unsome(x::Identity) = Identity(_unsome(x.value))
_unsome(x::Compose{F, G}) where {F, G} = Compose{F, G}(_unsome(x.value))
_unsome(x::Array) = map(_unsome, x)
_unsome(x::Tuple) = map(_unsome, x)

# test_traversable_laws(tag, gen_ta, gen_f); `gen_f` yields element -> Maybe.
function _traversable_laws(tag, eq_)
    MM = ComposeTag{MaybeTag, MaybeTag}
    eq = (a, b) -> eq_(_unsome(a), _unsome(b))
    return (
        Law("identity", (1,), t -> eq(traverse(IdentityTag(), Identity, t), Identity(t))),
        Law(
            "naturality", (1, 2),
            (t, f) -> eq(
                _maybe_to_vector(traverse(MaybeTag(), f, t)),
                traverse(ArrayTag(), _maybe_to_vector ∘ f, t),
            ),
        ),
        Law(
            "composition", (1, 2, 2),
            (t, f, g) -> eq(
                traverse(MM(), x -> Compose{MaybeTag, MaybeTag}(fmap(g, f(x))), t),
                Compose{MaybeTag, MaybeTag}(fmap(y -> traverse(MaybeTag(), g, y), traverse(MaybeTag(), f, t))),
            ),
        ),
    )
end

# test_contravariant_laws(tag, gen_p, gen_f, gen_x)
function _contravariant_laws(tag, eq)
    return (
        Law("identity", (1, 3), (p, x) -> eq(contramap(identity, p)(x), p(x))),
        Law(
            "composition", (1, 2, 2, 3),
            (p, f, g, x) -> eq(contramap(f ∘ g, p)(x), contramap(g, contramap(f, p))(x)),
        ),
    )
end

# test_bifunctor_laws(tag, gen_p, gen_f)
function _bifunctor_laws(tag, eq)
    return (
        Law("identity", (1,), p -> eq(bimap(identity, identity, p), p)),
        Law(
            "composition", (1, 2, 2, 2, 2),
            (p, f, g, h, i) -> eq(bimap(f ∘ g, h ∘ i, p), bimap(f, h, bimap(g, i, p))),
        ),
    )
end

# test_profunctor_laws(tag, gen_p, gen_f, gen_x)
function _profunctor_laws(tag, eq)
    return (
        Law("identity", (1, 3), (p, x) -> eq(dimap(identity, identity, p)(x), p(x))),
        Law(
            "composition", (1, 2, 2, 2, 2, 3),
            (p, f, g, h, i, x) -> eq(dimap(f ∘ g, h ∘ i, p)(x), dimap(g, h, dimap(f, i, p))(x)),
        ),
        Law(
            "dimap agrees with lmap and rmap", (1, 2, 2, 3),
            (p, f, g, x) -> eq(dimap(f, g, p)(x), lmap(f, rmap(g, p))(x)),
        ),
    )
end

# Category laws with the arrows at generator `ia` and the inputs at `ix`. "left identity" has the
# identity on the left of `⨟` (`idarrow ⨟ a ≡ a`), "right identity" on its right.
function _category_laws_at(tag, eq, ia::Int, ix::Int)
    return (
        Law("left identity", (ia, ix), (a, x) -> eq((idarrow(tag) ⨟ a)(x), a(x))),
        Law("right identity", (ia, ix), (a, x) -> eq((a ⨟ idarrow(tag))(x), a(x))),
        Law(
            "associativity", (ia, ia, ia, ix),
            (a, b, c, x) -> eq(((a ⨟ b) ⨟ c)(x), (a ⨟ (b ⨟ c))(x)),
        ),
    )
end

# test_category_laws(tag, gen_a, gen_x)
_category_laws(tag, eq) = _category_laws_at(tag, eq, 1, 2)

# test_arrow_laws(tag, gen_a, gen_f, gen_x): the Category laws plus Haskell's Arrow laws; pairs
# are built from `gen_x`.
function _arrow_laws(tag, eq)
    A = arr
    return (
        _category_laws_at(tag, eq, 1, 3)...,
        Law("arr identity", (3,), x -> eq(A(tag, identity)(x), idarrow(tag)(x))),
        Law(
            "arr composition", (2, 2, 3),
            (f, g, x) -> eq(A(tag, f ⨟ g)(x), (A(tag, f) ⨟ A(tag, g))(x)),
        ),
        Law(
            "first of arr", (2, 3, 3),
            (f, x, y) -> eq(arrfirst(A(tag, f))((x, y)), A(tag, _FirstOf(f))((x, y))),
        ),
        Law(
            "first of composition", (1, 1, 3, 3),
            (a, b, x, y) -> eq(arrfirst(a ⨟ b)((x, y)), (arrfirst(a) ⨟ arrfirst(b))((x, y))),
        ),
        Law(
            "first then fst", (1, 3, 3),
            (a, x, y) -> eq((arrfirst(a) ⨟ A(tag, _fst))((x, y)), (A(tag, _fst) ⨟ a)((x, y))),
        ),
        Law(
            "first commutes with second", (1, 2, 3, 3),
            (a, g, x, y) -> eq(
                (arrfirst(a) ⨟ A(tag, _SecondOf(g)))((x, y)),
                (A(tag, _SecondOf(g)) ⨟ arrfirst(a))((x, y)),
            ),
        ),
        Law(
            "first associates", (1, 3, 3, 3),
            (a, x, y, z) -> eq(
                (arrfirst(arrfirst(a)) ⨟ A(tag, _assoc))(((x, y), z)),
                (A(tag, _assoc) ⨟ arrfirst(a))(((x, y), z)),
            ),
        ),
    )
end
