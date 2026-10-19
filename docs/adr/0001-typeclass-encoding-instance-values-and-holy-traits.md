# ADR-0001: Monoid-like classes are passed as instance values; constructor classes are Holy traits on an owned constructor tag

- **Status:** Accepted (2026-10-20, user at the ChuiCore phase-1 ★)
- **Date:** 2026-10-20
- **Deciders:** the user, at the phase-1 ★ checkpoint (★ Q1: the reading of "Holy traits")
- **Scope:** ChuiCore.jl

## Context

- The brief: algebraic structures "as Holy traits (not inheritance)", each with an exported law
  kit: Semigroup, Monoid; Functor, Applicative, Monad, Alternative; Foldable, Traversable;
  Contravariant, Bifunctor, Profunctor; Category/Arrow. "Prefer dispatch and broadcasting over
  transliterated Haskell; give every abstraction a documented runtime cost."
- Contract (stable): CC-004 passes the aggregator as a **value** (`init(agg)`, `combine(agg, a, b)`,
  which may mutate `a`); CC-006 gives identity-less aggregators (the semigroups **and `Moments`**) a
  "no value yet" state; CC-007 classifies built-ins; CC-010 forbids colliding exports. Ecosystem
  ADR-0009 §5 names the neutral element `neutral`, signature open (example `neutral(::Type{T})`).
- Facts (`docs/research/trait-encoding.md`, `inspiration-typeclasses.md`, both 1.10.12 and 1.13.2):
  - F1: Holy traits, Bool+`Val`, SimpleTraits 0.9.6, WhereTraits 1.0.0, BinaryTraits 0.7.0 all
    fold to the primitive op (`Base.add_int`; for BinaryTraits the evidence is `mconcat`'s IR),
    `@inferred`, 0 bytes. A predicate using `in` over a tuple of types folds on 1.13.2, **not** on
    1.10.12; a runtime `Bool` never folds.
  - F2: a type-keyed encoding allows one monoid per type (Int under `*` needs a wrapper); instance
    values (`Sum()`, `Prod()`, `Max()`) allow many at zero cost: Scala cats' encoding (Context7
    `/typelevel/cats`, 2.13.0) without implicits, i.e. **explicit dictionary passing**.
  - F4: `Base.map` fails on `Some`, `nothing`, `Dict` (and on `Set`, a critic probe); adding Base
    methods there is piracy. F5: a 2-arg `combine(a, b)` beside CC-004's 3-arg form is
    dispatch-sound but semantically unsound. F7: supertypes cannot be retrofitted onto `Int`.
    F9: no trait package is worth a dependency (WhereTraits 1.0.0 loads in 2.3–3.6 s on 1.13.2;
    TypeClasses depends on Revise and adds 4 piracies).
  - Critic probes (scratch, both versions): `Base.typename(Union{Some{Int},Nothing})` throws, and
    `typename(Matrix{Int}).wrapper === Array`, so `typename` cannot key a Maybe instance; a shared
    `neutral` value (`Set()`) is corrupted by a mutating `combine`.
  - Names taken: `bind`, `first`, `empty`, `view` (Base), `second` (Dates), `flatmap`
    (`Base.Iterators`) (`law-kits-modules-names.md` L-2).

## Decision

1. **Semigroup, Monoid, aggregators: instance values (dictionary passing).** An instance is a value
   of a type its author owns (`Sum()`, `ReduceM(op)`, a downstream aggregator). Its **carrier** is
   its accumulator type; elements enter the carrier only through CC-004's `partial`.
   - `combine(m, a, b)` is the semigroup operation on the carrier. ChuiCore defines **no** 2-arg or
     variadic `combine` method (a test checks every method in `methods(ChuiCore.combine, ChuiCore)`
     has 3 arguments); infix sugar, if any, gets another name.
   - `neutral(m)` exists only for instances with a true identity on the carrier, and **must return
     a fresh value on every call** (it is a factory, like `init`, because `combine` may mutate).
     For those instances `init(m)` and `neutral(m)` are interchangeable:
     `isequal(final(m, init(m)), final(m, neutral(m)))`, checked by `test_monoid_laws`, which also
     checks freshness: it calls `combine(m, neutral(m), x)` and then re-checks that equivalence on a
     new `neutral(m)` (a shared, mutated identity fails it).
     Identity-less instances (`Max`, `First`, `Moments`, default `ReduceM`) have no `neutral`; their
     "no value yet" state is `init`'s (CC-006).
   - `neutral(m, ::Type{T})` is an optional refinement returning a concrete identity for element
     type `T` (default: `neutral(m)`).
   - `neutral(::Type{T}) = neutral(default_monoid(T), T)` is **closed sugar**: downstream code
     declares `default_monoid(::Type{T})`, never a `neutral(::Type{T})` method. No default for numbers.
2. **`AlgebraClass(::Type{M})`** (a Holy trait on the instance type; `IsSemigroup()`, `IsMonoid()`,
   default `NotAlgebra()`) describes the carrier algebra: `IsMonoid` iff `neutral(m)` exists.
   - **Consumer:** ChuiCore's generic folds over carriers (folding already-built accumulators with
     `combine`, e.g. a monoidal `foldmap`; not ADR-0003's `aggregate`, which always starts from
     `init`) and the law kits use it to choose between starting from
     `neutral(m)` and from the "no value yet" state. It **never gates** CC-004/CC-005 executors: an
     aggregator with the default `NotAlgebra` still works everywhere CC-004 is used.
   - It does not reproduce CC-007's "Aggregator" column ("has a non-trivial `final`"), which stays
     documentation. `ReduceM`'s user-declared class and commutativity must be type parameters, so the
     trait stays dispatch-only (constructor shape in phase 2).
3. **Functor, Applicative, Monad, Alternative, Foldable, Traversable, Contravariant, Bifunctor,
   Profunctor, Category/Arrow: Holy traits on an owned constructor tag.**
   - `constructorclass(::Type{T})` is a dispatch-only ChuiCore mapping from a concrete type to a
     singleton **tag** (`MaybeTag()` for `Some{T}` and `Nothing`, `ArrayTag()` for every `Array`,
     …); it never uses `Base.typename`. Its fallback is `constructorclass(::Type) = NoTag()`, whose
     styles are all `Not…` (e.g. `FunctorStyle(::NoTag) = NotFunctor()`), so an unregistered type
     reaches the documented `ArgumentError`, not a `MethodError`. Traits (`FunctorStyle(tag)`, …)
     are defined on the tag.
   - **ChuiCore's Maybe is Base's `Some{T}` / `nothing`**; ChuiCore defines no `Just`.
   - Operations that have a value dispatch through the trait:
     `fmap(f, x) = fmap(FunctorStyle(constructorclass(typeof(x))), f, x)`; a `NotFunctor` style
     throws an `ArgumentError` naming the type. `Base.map` is the implementation only for the types
     listed in phase 2 (Array, Tuple, ChuiCore-owned types); explicit methods cover `Some`/`Nothing`/`Dict`.
   - Operations with **no value to dispatch on** take the tag first: `pure(tag, x)`, the Alternative
     empty `zeroalt(tag)`-style, Category identity `idarrow(tag)`-style, `traverse(tag, f, xs)`.
   - Foldable is Base iteration (`iterate`, `foldl`, `mapreduce`); no new operation.
   - A second lawful instance (Vector's zip Applicative) is a **wrapper type** (`ZipVector(xs)`) with
     its own tag, never an extra leading instance argument (which would reopen F5's ambiguity).
   - On ChuiCore-owned types, Base functions get methods (`Base.map(f, ::Box)`); never Base methods
     on Base types.
   - Names must avoid Base/stdlib exports and the named clash list of ADR-0005: no new `bind`,
     `flatmap`, `first`, `second`, `empty`, `view` (bind candidates: `chain`, `andthen`). Final names
     are fixed in phase 2.
4. **Trait functions must be dispatch-only** (methods on `Type{…}` or tags returning constants),
   never computed with `in` over tuples of types or a runtime `Bool`. Check: each trait call passes
   `@inferred`, and `code_typed` of one representative caller shows no trait call left, on both
   supported versions (phase 2 tests).
5. **No dependency on a trait package.**
6. **Law kits** (ADR-0007) take the instance first: `test_monoid_laws(m, gen; eq)` for instance
   values, `test_functor_laws(tag, gen_fa, gen_f; eq)` (and likewise Applicative, Alternative,
   Traversable, Category) for constructor classes, so value-less laws (`ap(pure(tag, f), pure(tag, x))
   == pure(tag, f(x))`) are expressible.
7. **Runtime cost (documented):** trait dispatch and instance arguments: 0 over a direct call
   (F1, F2); a fold starting from "no value yet" returns a small `Union` (0 bytes, not `@inferred`);
   `neutral(m, T)` keeps folds concrete where an identity exists.

## Alternatives rejected

| Alternative | Why rejected |
|---|---|
| Type-keyed Holy traits for Monoid (`MonoidStyle(::Type{T})`, primary `neutral(::Type{T})`) | One monoid per type: `*`, `max`, `min` need wrappers around every element; a second mechanism beside CC-004's instance-first `combine` (F2, F6). Kept as closed sugar via `default_monoid`. |
| Abstract supertypes for algebra | Not retrofittable; one supertype per type; excluded by the brief (F7). |
| Abstract tag types on instances (`struct Sum <: Monoid`) | Forces downstream aggregators into ChuiCore's type tree; the trait classifies without that. |
| A 2-arg `combine(a, b)` | Semantically unsound next to CC-004 (F5). |
| `neutral(m)` as a "no value yet" sentinel for semigroups | Blurs CC-007's Monoid/Semigroup line; the sentinel is `init`'s (CC-006). |
| Keying constructor classes on `Base.typename(T).wrapper` | Throws on `Union` sums (Maybe), merges `Vector` and `Matrix` (critic probe). |
| Instance values for constructor classes (`ap(ZipA(), fs, xs)`) | Reopens F5's leading-argument ambiguity; wrapper types are used instead. |
| Trait packages (SimpleTraits, WhereTraits, BinaryTraits, TypeClasses) | No runtime gain; load time, macro surface, stale maintenance, piracy (F9). |
| Base `map` as Functor everywhere | Missing on `Some`/`Nothing`/`Dict`/`Set`; piracy to add (F4). |

## Consequences

- **Honest label:** the Monoid family is dictionary passing with a Holy-trait classifier, not
  "Holy traits" in the `IteratorSize` sense; ★ Q1 asks the user to accept that reading.
- The contract's PROVISIONAL "Typeclass trait encoding" item can be filled after phase 2; note for
  the lead: ecosystem ADR-0009 §5's example `neutral(::Type{T})` becomes sugar, not the primary form.
- Calls pass instances or tags explicitly: more verbose than Haskell, the price of no implicits.
- Optional Base integration (callable instances with `reduce`) would rely on the internal
  `Base.reduce_empty`: only with a test on every supported Julia.

## Verification

- `docs/research/trait-encoding.md` F1–F9 (scratch `core.jl`, `pkgs.jl`, `neutral.jl`, both
  versions; Context7 `/websites/julialang_en_v1` "Trait-based dispatch", `/typelevel/cats` 2.13.0);
  `inspiration-typeclasses.md` (laws from Hackage base 4.22.0.0 pages and GHC/profunctors master
  source; cats-laws/discipline 1.5.0); `law-kits-modules-names.md` L-2; critic-A probes
  (`typename` on a Union, `Matrix`→`Array`, shared-`neutral` aliasing), scratch `critic-a/`.
- UNVERIFIED: uniqueness of Functor instances by parametricity; Vector's default Applicative;
  stability of `Base.reduce_empty`; Bjarnason's thesis (secondary sources only); WhereTraits 1.1.2.

## Revisit when

- The user reads "Holy traits" as excluding instance values (★ Q1).
- Phase 2 finds a constructor class whose laws cannot be stated with an explicit tag.
- Julia adds a public replacement for `Base.reduce_empty`, or removes it.
