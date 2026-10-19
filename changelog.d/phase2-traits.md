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
- New dependencies: Compat, CompositionsBase; weak dependencies Test, Supposition.
