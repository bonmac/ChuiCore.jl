# Architecture Decision Records

Package-level decisions for this repo. Ecosystem-wide decisions live in the coordinator's
`adr/`. New ADRs start from [`0000-template.md`](0000-template.md); one decision per file,
about 60–120 lines, titled as a claim. Keep this index current in the same commit.

| # | Title | Status |
|---|---|---|
| 0000 | [Template](0000-template.md) | — |
| 0001 | [Monoid-like classes are passed as instance values; constructor classes are Holy traits on an owned constructor tag](0001-typeclass-encoding-instance-values-and-holy-traits.md) | Proposed |
| 0002 | [ADTs are plain structs with `Union` aliases; no pattern-matching library](0002-adts-are-plain-structs-no-matching-library.md) | Proposed |
| 0003 | [The transducer substrate is struct-based, threads state through the accumulator, and completes once](0003-transducer-substrate.md) | Proposed |
| 0004 | [ChuiCore owns a minimal Lens/Prism core; Accessors.jl is an extension, not a dependency](0004-optics-own-core-accessors-extension.md) | Proposed |
| 0005 | [ChuiCore is one module with no public submodules; names are tiered exported / public / internal by a tested clash rule](0005-one-module-no-public-submodules.md) | Proposed |
| 0006 | [Depend on CompositionsBase for the one `⨟` binding](0006-dependency-compositionsbase.md) | Proposed |
| 0007 | [Law kits are exported stubs whose methods live in extensions on Test and Supposition](0007-law-kits-as-stubs-plus-extensions.md) | Proposed |
| 0008 | [Depend on ConstructionBase for struct rebuilding in optics](0008-dependency-constructionbase.md) | Proposed |

Package ADRs cite coordinator ADRs as "ecosystem ADR-NNNN"; a bare "ADR-NNNN" means this repo's.
