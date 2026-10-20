# Phase 2 plan: traits, law kits, composition, monoids

- **Date:** 2026-10-20. **Branch:** `feat/phase2-traits` (from main 3054d7c). **Tier:** T2 (public
  API, dependencies). **Spec:** the accepted phase-1 design,
  `docs/superpowers/specs/2026-10-20-phase1-research-design.md`, and ADRs 0001–0008.
- **Binding inputs:** `contracts/chui-core.md` (coordinator; CC-001…CC-011), the pending coordinator
  amendments (CC-001 binary-methods wording; ecosystem ADR-0009: `papply`, no exported `partial`;
  ecosystem ADR-0007 §2: `@check record=false` + explicit `@test`, a planted violation per law on LTS).
- **Out of scope (phase 3):** recursion schemes, free monads, laziness, optics, transducers,
  the `aggregate` fold, the name-conflict banner. ConstructionBase (ADR-0008) is only used by optics,
  so it is added in phase 3 (an unused hard dependency fails Aqua's stale-deps check).

## Layout (ADR-0005: one module, files by area)

| File | Owner | Content |
|---|---|---|
| `src/ChuiCore.jl` | lane lead | module, imports, includes, `export`s |
| `src/names.jl` | lane lead | the `@compat public` list |
| `src/compose.jl` | lane lead | `pipe`, `curry`, `papply`, `flip` |
| `src/laws.jl` | lane lead | `Law`, kit stubs and docstrings, `default_eq`, `ExactEq` |
| `src/algebra/*.jl` | sub-lane `p2-algebra` | protocol, `AlgebraClass`, `neutral`, aggregators, monoid-family law tables |
| `src/classes/*.jl` | sub-lane `p2-classes` | tags, styles, operations, Base instances, owned types, class law tables |
| `ext/ChuiCoreTestExt.jl`, `ext/ChuiCoreSuppositionExt.jl` | lane lead | the two law drivers |
| `test/exports/` | lane lead | clash-list environment (ADR-0005 §2) |

## Names

**Exported** (pass the clash list; verified by `test/exports`): `⨟`, `opcompose`, `papply`, `pipe`,
`flip`, `chain`, `alt`, `zeroalt`, `contramap`, `bimap`, `dimap`, `lmap`, `rmap`, `idarrow`, `arr`,
`arrfirst`, `arrsecond`, `arrsplit`, `fanout`, and the 13 kit stubs `test_semigroup_laws`,
`test_monoid_laws`, `test_aggregator_laws`, `test_functor_laws`, `test_applicative_laws`,
`test_monad_laws`, `test_alternative_laws`, `test_foldable_laws`, `test_traversable_laws`,
`test_contravariant_laws`, `test_bifunctor_laws`, `test_profunctor_laws`, `test_category_laws`,
`test_arrow_laws` (14 with the arrow kit).

**Public, not exported:** `neutral`, `curry`, `fmap`, `pure`, `ap`, `traverse`, `sequence` (each
exported by Functors 0.4.12 or TypeClasses 1.1.0, so the clash rule forbids exporting them; see the
lead's decision, 2026-10-20: follow ADR-0005 rule 2; rule 3's listing of `neutral` as exported is
to be corrected), `init`, `partial`, `combine`, `final`, `iscommutative`, `combineall`,
`default_monoid`, `AlgebraClass`, `IsSemigroup`, `IsMonoid`, `NotAlgebra`, the aggregators `Sum`,
`Prod`, `Count`, `CountTrue`, `AnyM`, `AllM`, `Max`, `Min`, `Extrema`, `First`, `Last`, `Mean`,
`Moments`, `ReduceM`, `MapM`; `constructorclass`, the tags (`NoTag`, `MaybeTag`, `ArrayTag`,
`TupleTag`, `DictTag`, `PairTag`, `FunctionTag`, `IdentityTag`, `ZipVectorTag`, `PredicateTag`), the
`*Style` functions and their `Is*`/`Not*` values, the owned types `Identity`, `ZipVector`,
`Predicate`; `default_eq`, `ExactEq`, `Law`.

**Clash evidence** (Julia 1.13.2, fresh scratch environment, 2026-10-20; `Base.isexported(M, n)`
over the candidate names):
```
DataFrames 1.3.6   => [:combine]
Functors 0.4.12    => [:fmap]
TypeClasses 1.1.0  => [:pure, :ap, :neutral, :combine, :curry, :Identity]
(Transducers 0.4.85, Accessors 0.1.45, Setfield 1.1.2, ConstructionBase 1.6.0,
 CompositionsBase 0.1.2, Base, Core, Base.Iterators: none of the candidates)
```

**Internal:** everything else (`NoValue`, law tables `_semigroup_laws` …, drivers).

## API decisions fixed here (ADR-0001 left them to phase 2)

- `pipe(x, f, g) == g(f(x))` (any number of functions, applied left to right); `curry(f, n)` (also `curry(f, Val(n))`): `curry(f, 2)(a)(b)
  == f(a, b)`; `papply(f, args...; kw...)` returns a `PApply` callable appending later arguments
  (own struct: `Base.Fix1` takes one argument on 1.10 and varargs on ≥ 1.12); `flip(f)(a, b, c...)
  == f(b, a, c...)`. Base's `∘`, `Returns`, `splat`, `identity` complete the point-free set.
- Monoid family: as ADR-0001 §1–2. Kits for it take 3-argument `eq(r₁, r₂, v)`; `default_eq(m)` is
  CC-004's `≈ᵃ` for built-ins and `ExactEq()` (accepts 2 or 3 arguments, `isequal`) otherwise.
  `ReduceM(op; neutral, commutative = false)`: class and commutativity are type parameters.
  `Moments(stat = :var; corrected = true)` with `stat ∈ (:var, :std)` as a type parameter.
- Constructor classes (ADR-0001 §3): value operations `fmap(f, x)`, `ap(ff, fx)`, `chain(f, m)`,
  `alt(a, b)`, `contramap(f, p)`, `bimap(f, g, p)`, `dimap(f, g, h)`, `lmap(f, h)`, `rmap(g, h)`,
  `arrfirst(a)`, `arrsecond(a)`, `arrsplit(a, b)`, `fanout(a, b)`; tag-first `pure(tag, x)`,
  `zeroalt(tag)`, `idarrow(tag)`, `arr(tag, f)`, `traverse(tag, f, xs)`, `sequence(tag, xs)`.
  Category composition is `⨟` (functions only in phase 2; no new `⨟` method). Instances: Maybe
  (`Some`/`nothing`), `Array`, `Tuple`, `Dict` (Functor on values), `Pair`/2-`Tuple` (Bifunctor),
  `Function` (Profunctor, Category, Arrow), owned `Identity`, `ZipVector`, `Predicate`.

## Law kits (ADR-0007)

- A kit's laws live in `src` as an internal table of `Law(name, args, pred)`; `args` says which
  generator feeds each argument. The Test driver uses ≤ 12 samples per argument and ≤ 1,728
  combinations per law; the Supposition driver uses `@check record=false db=false` and `@test`s the
  report. Each law is an inner `@testset "<law>"` holding one `@test`.
- Planted violations: one unlawful instance per law, run in a capturing test set under both drivers;
  the test asserts the exact set of failing laws. Runs on 1.10 (no `:slow` tag).

## Tasks (test-first)

1. Lead: Project.toml (Compat, CompositionsBase; weakdeps Test, Supposition), skeleton, compose,
   law infrastructure, drivers, capture test helper. Commit.
2. Sub-lanes in parallel (disjoint files, own worktrees from task 1's commit): `p2-algebra`,
   `p2-classes`. Each: failing tests, implementation, law tests for every instance, planted
   violations, conformance tests for the contract entries in its area.
3. Lead: merge the sub-lane branches (reviewed), clash-list test, quality/JET/format, docs, changelog,
   HANDOFF. Reviewer sub-agent on the whole diff; fix blockers.
