# Law kits (ADR-0007): method-less exported stubs, laws as data, drivers in the extensions.
#
# Each kit `test_<class>_laws` has a law table `_<class>_laws(instance, eq; kwargs...)` (internal,
# defined next to the class) returning a tuple or vector of `Law`s. `ChuiCoreTestExt` runs a table
# over finite sample collections; `ChuiCoreSuppositionExt` runs it over Supposition generators.

"""
    Law(name, args, pred)

One law of a kit: `name` names the inner `@testset`; `args` is a tuple of generator indices, one per
argument of `pred` (`(1, 2, 2)` draws the first argument from the kit's first generator and the
other two from its second); `pred(xs...)::Bool` is `true` when the law holds for those arguments.

Public so downstream packages can read what a kit checks; constructing kits from `Law`s is
internal.
"""
struct Law{A <: Tuple, P}
    name::String
    args::A
    pred::P
end

"""
    ExactEq()

The default equality of a law kit: `isequal`, accepting either two results, or two results and
the input they were computed from (the aggregator kits' 3-argument form, ADR-0007 §3).
"""
struct ExactEq end
(::ExactEq)(a, b) = isequal(a, b)
(::ExactEq)(a, b, _) = isequal(a, b)

"""
    default_eq(instance_or_tag)

The equality a law kit uses when the caller passes no `eq` (ADR-0007 §3). For the built-in
aggregators it is CC-004's float tolerance `≈ᵃ`, called as `eq(r₁, r₂, v)` with `v` the whole input;
otherwise [`ChuiCore.ExactEq`](@ref)`()`, which is `isequal`. Instance owners may add methods.
"""
default_eq(_) = ExactEq()

const _KIT_DOC_COMMON = """
Each law is recorded as an inner `@testset "<law name>"` holding one `@test`, in the caller's
test set; a failing `@test` shows the first counterexample. Methods exist only after `using Test`
(sample collections, `ChuiCoreTestExt`) or `using Test, Supposition` (generators,
`ChuiCoreSuppositionExt`): loading ChuiCore never loads either (CC-011).

- **Sample collections:** each generator is any iterable of samples; a law with `k` arguments uses
  at most 12 samples per argument and at most 1,728 combinations.
- **Supposition:** when the first generator is a `Supposition.Data.Possibility`, every law runs as
  `@check record=false db=false` and its report is asserted with `@test` (ecosystem ADR-0007 §2: a
  failing `@check` alone is not recorded on Julia 1.10). `db=false`: Supposition otherwise writes
  counterexamples to the caller's `test/SuppositionDB`, and a database written by a newer Julia
  makes a later 1.10 run throw ("Cannot read stream serialized with a newer version of Julia").
  Other generators may then be collections,
  which are sampled with `Data.SampledFrom`. Keyword `max_examples` (default 200).
- Keyword `laws`: a collection of law names to run (default: all).
"""

"""
    test_semigroup_laws(m, chunks; eq = default_eq(m), laws, max_examples)

Check the Semigroup laws of the instance value `m` (ADR-0001 §1). Carrier values are built from
the samples (`chunks`, each an iterable of elements) as fresh accumulators
`partial(m, init(m), x)` and compared after `final` with `eq(r₁, r₂, v)`, where `v` is the
concatenated input. Law: `associativity` of `ChuiCore.combine`.

$_KIT_DOC_COMMON
"""
function test_semigroup_laws end

"""
    test_monoid_laws(m, chunks; eq = default_eq(m), laws, max_examples)

The Semigroup laws plus: `left identity` and `right identity` of `neutral(m)`, `neutral matches
init` (`final(m, init(m))` and `final(m, neutral(m))` are `isequal`), and `neutral is fresh` (a
`neutral(m)` mutated by `combine` does not change a later `neutral(m)`). Conventions as in
[`test_semigroup_laws`](@ref).

$_KIT_DOC_COMMON
"""
function test_monoid_laws end

"""
    test_aggregator_laws(agg, samples; eq = default_eq(agg), reference = nothing, laws, max_examples)

Check CC-004's aggregator laws on each sample input `v` (an iterable): `split invariance` (fixed
ordered splits, empty chunks included), `empty partition identity`, `chunk concatenation`,
`commutativity` (only if `ChuiCore.iscommutative(agg)`, CC-005), `init is fresh` (two `init(agg)`
do not alias), and, when `reference` is a function, `agrees with reference` on non-empty `v`
(CC-004 law 4, e.g. `reference = sum` for `ChuiCore.Sum()`). `eq(r₁, r₂, v)` compares finalized
results.

$_KIT_DOC_COMMON
"""
function test_aggregator_laws end

"""
    test_functor_laws(tag, gen_fa, gen_f; eq = default_eq(tag), laws, max_examples)

Functor laws for the constructor class `tag` (ADR-0001 §3): `identity`
(`fmap(identity, fa) == fa`) and `composition` (`fmap(g ∘ f, fa) == fmap(g, fmap(f, fa))`).
`gen_fa` yields values of the class, `gen_f` unary functions.

$_KIT_DOC_COMMON
"""
function test_functor_laws end

"""
    test_applicative_laws(tag, gen_fa, gen_f, gen_x; eq = default_eq(tag), laws, max_examples)

Applicative laws for `tag`: `identity`, `composition`, `homomorphism`, `interchange`, and
`fmap agrees with ap`. `gen_fa` yields values of the class, `gen_f` unary functions, `gen_x` plain
values; values holding functions are built as `fmap(_ -> f, fa)` and `pure(tag, f)`.

$_KIT_DOC_COMMON
"""
function test_applicative_laws end

"""
    test_monad_laws(tag, gen_m, gen_k, gen_x; eq = default_eq(tag), laws, max_examples)

Monad laws for `tag`: `left identity` (`chain(k, pure(tag, x)) == k(x)`), `right identity`,
`associativity`, and `ap agrees with chain`. `gen_m` yields monadic values, `gen_k` functions
from a plain value to a monadic value, `gen_x` plain values.

$_KIT_DOC_COMMON
"""
function test_monad_laws end

"""
    test_alternative_laws(tag, gen_fa; eq = default_eq(tag), laws, max_examples)

Alternative laws for `tag` (the monoid laws of `alt` and `zeroalt(tag)`, as Haskell `base` states
them): `left identity`, `right identity`, `associativity`.

$_KIT_DOC_COMMON
"""
function test_alternative_laws end

"""
    test_foldable_laws(tag, gen_fa; eq = default_eq(tag), laws, max_examples)

Foldable is Base iteration (ADR-0001 §3); the laws relate Base's folds to iteration order:
`foldl matches iteration`, `foldr matches foldl` (on a non-commutative operation), and
`mapreduce matches foldl`.

$_KIT_DOC_COMMON
"""
function test_foldable_laws end

"""
    test_traversable_laws(tag, gen_ta, gen_f; eq = default_eq(tag), laws, max_examples)

Traversable laws for the traversable values `gen_ta` of class `tag`: `identity`
(`traverse(IdentityTag(), Identity, t) == Identity(t)`), `naturality` (for the applicative
transformation from Maybe to `Vector`), and `composition` (Maybe inside Maybe). `gen_f` yields
functions from an element to a Maybe (`Some(y)` or `nothing`).

$_KIT_DOC_COMMON
"""
function test_traversable_laws end

"""
    test_contravariant_laws(tag, gen_p, gen_f, gen_x; eq = default_eq(tag), laws, max_examples)

Contravariant laws for callable values `gen_p` of class `tag`, compared extensionally on the
inputs `gen_x`: `identity` and `composition` (`contramap(f ∘ g, p) ≡ contramap(g, contramap(f, p))`).

$_KIT_DOC_COMMON
"""
function test_contravariant_laws end

"""
    test_bifunctor_laws(tag, gen_p, gen_f; eq = default_eq(tag), laws, max_examples)

Bifunctor laws for `tag`: `identity` (`bimap(identity, identity, p) == p`) and `composition`
(`bimap(f ∘ g, h ∘ i, p) == bimap(f, h, bimap(g, i, p))`).

$_KIT_DOC_COMMON
"""
function test_bifunctor_laws end

"""
    test_profunctor_laws(tag, gen_p, gen_f, gen_x; eq = default_eq(tag), laws, max_examples)

Profunctor laws for callable values `gen_p`, compared extensionally on `gen_x`: `identity`,
`composition`, and `dimap agrees with lmap and rmap`.

$_KIT_DOC_COMMON
"""
function test_profunctor_laws end

"""
    test_category_laws(tag, gen_a, gen_x; eq = default_eq(tag), laws, max_examples)

Category laws for callable arrows `gen_a`, composed with `⨟` and compared extensionally on
`gen_x`: `left identity`, `right identity`, `associativity` (identity is `idarrow(tag)`).

$_KIT_DOC_COMMON
"""
function test_category_laws end

"""
    test_arrow_laws(tag, gen_a, gen_f, gen_x; eq = default_eq(tag), laws, max_examples)

The Category laws plus Haskell's Arrow laws for `arr` and `arrfirst`, compared extensionally on
`gen_x` (and on pairs built from it): `arr identity`, `arr composition`, `first of arr`,
`first of composition`, `first then fst`, `first commutes with second`, `first associates`.

$_KIT_DOC_COMMON
"""
function test_arrow_laws end

# A misspelled name in a kit's `laws` keyword would otherwise run nothing and pass silently.
function _check_selected(laws, selected)
    selected === nothing && return nothing
    known = [law.name for law in laws]
    unknown = [s for s in selected if !(s in known)]
    isempty(unknown) ||
        throw(ArgumentError("unknown law name(s) $(repr(unknown)); this kit's laws are $(repr(known))"))
    return nothing
end

# kit name => law-table function (defined by each area's file). The drivers iterate this.
const _KITS = (
    :test_semigroup_laws => :_semigroup_laws,
    :test_monoid_laws => :_monoid_laws,
    :test_aggregator_laws => :_aggregator_laws,
    :test_functor_laws => :_functor_laws,
    :test_applicative_laws => :_applicative_laws,
    :test_monad_laws => :_monad_laws,
    :test_alternative_laws => :_alternative_laws,
    :test_foldable_laws => :_foldable_laws,
    :test_traversable_laws => :_traversable_laws,
    :test_contravariant_laws => :_contravariant_laws,
    :test_bifunctor_laws => :_bifunctor_laws,
    :test_profunctor_laws => :_profunctor_laws,
    :test_category_laws => :_category_laws,
    :test_arrow_laws => :_arrow_laws,
)
