# ChuiCore phase 1 (Research and ADRs): design summary

- **Date:** 2026-10-20. **Branch:** `feat/phase1-research`. **Tier:** T2 (public API shape,
  dependencies). **Status:** Proposed; waiting for the ★ checkpoint. No code changes.
- **Inputs:** `docs/agent/BRIEF.md` (phase 1), the binding contract `contracts/chui-core.md` (in the
  coordinator), ecosystem ADRs 0002, 0006, 0007, 0009.
- **Evidence:** `docs/research/` (index: [README](../../research/README.md)); every runtime claim was
  run on Julia 1.10.12 and 1.13.2.

## Decisions (each Proposed, one ADR each)

| ADR | Decision in one line |
|---|---|
| [0001](../../adr/0001-typeclass-encoding-instance-values-and-holy-traits.md) | Semigroup/Monoid/aggregators are instance values passed explicitly (`combine(m, a, b)` only, fresh `neutral(m)`, `AlgebraClass` Holy trait); constructor classes are Holy traits on an owned constructor tag, with value-less operations taking the tag first; Maybe is Base `Some`/`nothing`. |
| [0002](../../adr/0002-adts-are-plain-structs-no-matching-library.md) | No Moshi/SumTypes/MLStyle: variants are plain structs, closed sums are owned `Union` aliases (with `isa` chains from 4 applicable methods), open sums are abstract types with documented dynamic-dispatch cost; an exhaustiveness helper. |
| [0003](../../adr/0003-transducer-substrate.md) | Own struct-based transducers (no call method; `asrf`), state in the accumulator, `complete` once, fail-closed `isstateless`, `foldxl`/`foldparts`/`foldxt`/`aggregate` with in-order merge; names public, not exported; Transducers.jl via extension. |
| [0004](../../adr/0004-optics-own-core-accessors-extension.md) | Own minimal `Lens`/`Prism` (public, not exported), Base `ComposedFunction` composition, ConstructionBase rebuild hook; Accessors.jl only as an extension. |
| [0005](../../adr/0005-one-module-no-public-submodules.md) | One module, no submodules; exported / public / internal tiers, with exports gated by a tested clash list. |
| [0006](../../adr/0006-dependency-compositionsbase.md) | Depend on CompositionsBase and re-export exactly `⨟`/`opcompose`; request a CC-001 wording amendment (the upstream method is variadic). |
| [0007](../../adr/0007-law-kits-as-stubs-plus-extensions.md) | Law kits are exported stubs; `ChuiCoreTestExt` (sample-based) and `ChuiCoreSuppositionExt` (property-based); instance-first; explicit `@test` on Supposition reports because of a 1.10 defect. |
| [0008](../../adr/0008-dependency-constructionbase.md) | Depend on ConstructionBase so struct optics rebuild through the same hook as Accessors. |

## Dependency ledger after phase 1

| Package | Kind | ADR | Compat |
|---|---|---|---|
| Compat | hard | ecosystem ADR-0006 §4 | `4.10` |
| CompositionsBase | hard | 0006 | `0.1.2` |
| ConstructionBase | hard | 0008 | `1.6` |
| Test | weak (`ChuiCoreTestExt`, `ChuiCoreSuppositionExt`) | 0007 | `1` |
| Supposition | weak (`ChuiCoreSuppositionExt`) | 0007, ecosystem ADR-0007 | `0.3` |
| Transducers | weak (`ChuiCoreTransducersExt`) | 0003, ecosystem ADR-0002 §4 | `0.4` |
| Accessors | weak (`ChuiCoreAccessorsExt`) | 0004 | `0.1.45` |

## Contract consistency

No ADR changes a stable entry. Items for the lead (contract changes are T3, coordinator-side):
1. **CC-001 wording** ("methods take exactly two arguments") conflicts with CompositionsBase's
   variadic method: ADR-0006 asks for an amendment.
2. **Ecosystem ADR-0009 Consequences** says ChuiCore exports `partial`; ADR-0005 proposes the whole
   aggregation protocol as public-only (★ Q2).
3. **ADR-0009 §5's example `neutral(::Type{T})`** becomes closed sugar; the primary form is
   `neutral(m)` (ADR-0001).
4. PROVISIONAL items that these ADRs can fill after phases 2–3: CompositionsBase binding, export
   list, typeclass encoding, law kits, transducer API, optics, ADT choice.
5. **Supposition on 1.10** (ecosystem ADR-0007 §2): failing `@check`s are not recorded on 1.10
   (★ Q4).

## Not decided here (later phases)

Final operation names (phase 2, checked by the clash test); Vector's default Applicative; the
`ReduceM` constructor; the transducer v1 set and `Partition{T}`; recursion-scheme encoding
(`Fix` vs `project`/`embed`; research favours plain dispatch on owned node types) and free-monad
encoding ("freer" is linear, classic is quadratic on left-nested binds); laziness (thread-safe
memoization needs a lock on 1.10, `OncePerProcess` is 1.12+); purity conventions
(`inspiration-effects.md`); the name-conflict banner API; performance budgets (phase 4).

## Not verified

Speed rankings (machines were loaded; allocations and inference are reliable); TTFX of a
precompiled ChuiCore; prism laws (not prototyped); Functors' `fmap` export at a tagged release
(seen on GitHub master); Bjarnason's thesis (secondary sources). Critic C's transducer reproducers
(A1–A8) cannot go green until phase 3 implements the substrate.

## Critique

Three read-only critics reviewed all eight ADRs in two passes. First pass: 8 blockers (ADR-0001 ×1,
ADR-0002 ×1, ADR-0003 ×3, ADR-0004 ×1, ADR-0005 ×2). All were fixed; the second pass found no
blockers, and its should-fixes and nits were applied. Each ADR's Verification section lists its own.
