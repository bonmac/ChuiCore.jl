- Phase 2 (traits and law kits): `⨟`/`opcompose` re-exported from CompositionsBase (ADR-0006);
  composition helpers `pipe`, `papply`, `flip` (exported) and `ChuiCore.curry`; the three name
  tiers of ADR-0005 with a clash-list check in its own environment (`test/exports/`).
- `neutral`, `curry`, `fmap`, `pure` and `ap` are public, not exported: the clash rule (ADR-0005
  §2) forbids exporting them because TypeClasses 1.1.0 exports `neutral`, `curry`, `pure`, `ap`
  (and `combine`, `Identity`) and Functors 0.4.12 exports `fmap` (probe on Julia 1.13.2; lead's
  decision 2026-10-20).
- Law kits (ADR-0007): 14 exported `test_*_laws` stubs, with `ChuiCoreTestExt` (sample collections)
  and `ChuiCoreSuppositionExt` (generators; `@check record=false db=false` plus an explicit
  `@test`), and a planted violation per law under both drivers, run on Julia 1.10.
- Aggregation protocol and monoid family (CC-004…CC-007, ADR-0001 §1–2): public `init`, `partial`,
  `combine` (3-argument only), `final`, `iscommutative`, `neutral` (fresh on every call),
  `default_monoid`, the dispatch-only trait `AlgebraClass` (`IsSemigroup`, `IsMonoid`,
  `NotAlgebra`) and its consumer `combineall`; the built-in aggregators `Sum`, `Prod`, `Count`,
  `CountTrue`, `AnyM`, `AllM`, `Max`, `Min`, `Extrema`, `First`, `Last`, `Mean`,
  `Moments(stat = :var; corrected = true)`, `ReduceM(op; neutral, commutative = false)` and
  `MapM(f, inner)`, with CC-006's empty-input results and exception types on every Julia;
  `default_eq` gives CC-004's float tolerance `≈ᵃ` for the built-ins.
- Constructor classes (ADR-0001 §3–4): `constructorclass` tags, dispatch-only `*Style` traits for
  Functor through Arrow, the operations (`fmap`, `ap`, `chain`, `alt`, `contramap`, `bimap`,
  `dimap`, `lmap`, `rmap`, `arrfirst`, `arrsecond`, `arrsplit`, `fanout`; tag-first `pure`,
  `zeroalt`, `idarrow`, `arr`, `traverse`, `sequence`), instances on Maybe (`Some`/`nothing`),
  `Array`, `Tuple`, `Dict`, `Pair` and `Function`, and the owned types `Identity`, `ZipVector`
  and `Predicate`.
- New dependencies: Compat, CompositionsBase; weak dependencies Test, Supposition.
  ConstructionBase (ADR-0008) is deferred to phase 3, when optics use it.
