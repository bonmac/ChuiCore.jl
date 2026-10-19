# Research notes (phase 1, 2026-10-20)

Verified notes behind the phase-1 ADRs. Each note states its method, pastes command output, and
ends with an UNVERIFIED list. All runtime claims were checked on Julia 1.10.12 (`julia +lts`) and
1.13.2 (`julia +release`) in scratch environments outside the repo; the scratch code was not kept
in the repo. Timings were taken on a heavily loaded machine: treat absolute numbers as indicative;
allocation counts, inference results and pass/fail are reliable.

| Note | Question | Verified by | Feeds |
|---|---|---|---|
| [trait-encoding.md](trait-encoding.md) | Which typeclass encoding: Holy traits, trait packages, supertypes, instance values? | prototypes on both versions (`@code_typed`, `@inferred`, `@allocated`), registry, `gh api`, Context7 `/websites/julialang_en_v1`, `/typelevel/cats` | ADR-0001 |
| [inspiration-typeclasses.md](inspiration-typeclasses.md) | Classes and laws in Haskell base, profunctors, cats/discipline; Bjarnason's thesis | fetched Hackage and cats docs; Bjarnason from secondary sources (UNVERIFIED) | ADR-0001, ADR-0007 |
| [adt-pattern-matching.md](adt-pattern-matching.md) | Hand-rolled vs Moshi, SumTypes, MLStyle | benchmarks and probes on both versions, registry, `gh api`, Context7 `/thautwarm/mlstyle.jl`, installed sources | ADR-0002 |
| [recursion-schemes-free-laziness.md](recursion-schemes-free-laziness.md) | Recursion schemes, free monads, à la carte, laziness in Julia | prototypes on both versions; Hackage `recursion-schemes` 5.2.3, `data-fix` 0.3.4; Milewski ch. 24; Swierstra 2008 (citation only) | ADR-0002; phase 3 |
| [inspiration-effects.md](inspiration-effects.md) | What "pure" means in Julia; ZIO, cats-effect, free monads; a ChuiCore convention | Julia manual, `Base.infer_effects` on both versions, Context7 ZIO/cats-effect/cats docs | phase 3 (purity conventions) |
| [transducers.md](transducers.md) | The substrate design; Transducers.jl API; interop and name clashes | installed Transducers 0.4.85 source and runs (no Context7 entry), clojure.org, a scratch extension package | ADR-0003, ADR-0005 |
| [optics.md](optics.md) | Is Accessors.jl good enough to reuse? Prisms? | registry, source, `gh api`, runs on both versions, scratch `ChuiLike` extension + Aqua; addendum with quiet-host load times | ADR-0004, ADR-0008 |
| [compositionsbase.md](compositionsbase.md) | CompositionsBase as the `⨟` binding | registry, `gh api`, source, scratch modules on both versions, Aqua | ADR-0006 |
| [law-kits-modules-names.md](law-kits-modules-names.md) | Law-kit packaging; Supposition on 1.10; submodules; candidate names vs Base/stdlib | scratch packages and scripts on both versions | ADR-0001, ADR-0005, ADR-0007 |
