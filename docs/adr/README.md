# Architecture Decision Records

Package-level decisions for this repo. Ecosystem-wide decisions live in the coordinator's
`adr/`. New ADRs start from [`0000-template.md`](0000-template.md); one decision per file,
about 60–120 lines, titled as a claim. Keep this index current in the same commit.

| # | Title | Status |
|---|---|---|
| 0000 | [Template](0000-template.md) | — |
| 0001 | [Monoid-like classes are passed as instance values; constructor classes are Holy traits on an owned constructor tag](0001-typeclass-encoding-instance-values-and-holy-traits.md) | Accepted (2026-10-20, user at the ChuiCore phase-1 ★) |
| 0002 | [ADTs are plain structs with `Union` aliases; no pattern-matching library](0002-adts-are-plain-structs-no-matching-library.md) | Accepted (2026-10-20, user at the ChuiCore phase-1 ★) |
| 0003 | [The transducer substrate is struct-based, threads state through the accumulator, and completes once](0003-transducer-substrate.md) | Accepted (2026-10-20, user at the ChuiCore phase-1 ★) |
| 0004 | [ChuiCore owns a minimal Lens/Prism core; Accessors.jl is an extension, not a dependency](0004-optics-own-core-accessors-extension.md) | Accepted (2026-10-20, user at the ChuiCore phase-1 ★) |
| 0005 | [ChuiCore is one module with no public submodules; names are tiered exported / public / internal by a tested clash rule](0005-one-module-no-public-submodules.md) | Accepted (2026-10-20, user at the ChuiCore phase-1 ★); ecosystem ADR-0009 amendment pending |
| 0006 | [Depend on CompositionsBase for the one `⨟` binding](0006-dependency-compositionsbase.md) | Accepted (2026-10-20, user at the ChuiCore phase-1 ★); CC-001 amendment pending |
| 0007 | [Law kits are exported stubs whose methods live in extensions on Test and Supposition](0007-law-kits-as-stubs-plus-extensions.md) | Accepted (2026-10-20, user at the ChuiCore phase-1 ★); ecosystem ADR-0007 §2 amendment pending |
| 0008 | [Depend on ConstructionBase for struct rebuilding in optics](0008-dependency-constructionbase.md) | Accepted (2026-10-20, user at the ChuiCore phase-1 ★) |
| 0009 | [ChuiCore's performance budgets: zero-allocation hot paths, a load-plus-first-call budget, a fixed benchmark set](0009-performance-budgets.md) | Accepted (2026-10-20, user at the ChuiCore phase-4 ★) |
| 0010 | [Depend on PrecompileTools for a precompile workload that calls one function on opaque inputs](0010-dependency-precompiletools.md) | Accepted (2026-10-20, user at the ChuiCore phase-4 ★) |

Package ADRs cite coordinator ADRs as "ecosystem ADR-NNNN"; a bare "ADR-NNNN" means this repo's.
