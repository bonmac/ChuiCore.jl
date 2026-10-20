- Aggregation protocol and monoid family (CC-004…CC-007, ADR-0001 §1–2): public `init`, `partial`,
  `combine` (3-argument only), `final`, `iscommutative`, `neutral` (fresh on every call),
  `default_monoid`, the dispatch-only trait `AlgebraClass` (`IsSemigroup`, `IsMonoid`,
  `NotAlgebra`) and its consumer `combineall`; the built-in aggregators `Sum`, `Prod`, `Count`,
  `CountTrue`, `AnyM`, `AllM`, `Max`, `Min`, `Extrema`, `First`, `Last`, `Mean`,
  `Moments(stat = :var; corrected = true)`, `ReduceM(op; neutral, commutative = false)` and
  `MapM(f, inner)`, with CC-006's empty-input results and exception types on every Julia.
- Law tables for `test_semigroup_laws`, `test_monoid_laws` and `test_aggregator_laws`, and
  `default_eq` methods giving CC-004's float tolerance `≈ᵃ` for the built-ins.
