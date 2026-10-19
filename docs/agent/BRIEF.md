<!-- package brief: coordinator commit ff0100a, prompts/10-chui-core.md, copied 2026-10-19 -->

# Package brief: ChuiCore.jl (functional-programming core)

The lead session hands this brief to the agents working on **ChuiCore.jl**. It is the most upstream package in the ecosystem: everything else depends on it, and it depends on no other Chui package. Lanes for this package edit and commit only in `<root>/ChuiCore.jl`.

**Read first:**
- `docs/agent/ECOSYSTEM.md`: the shared rules. Follow them exactly.
- `<root>/contracts/chui-core.md`: your promise to downstream packages. You own its implementation; a change to it needs a meta ADR.
- `HANDOFF.md`.

## Scope

- **Composition:** `⨟` / `∘`, `pipe`, `curry` / `partial`, point-free helpers. Use the Ramda-style "data last" convention only where it fits Julia's style.
- **Algebraic structures as Holy traits** (not inheritance). Each has a reusable **law-test kit**, which you also export, so downstream packages can check their own instances:
  - Semigroup, Monoid;
  - Functor, Applicative, Monad, Alternative;
  - Foldable, Traversable;
  - Contravariant, Bifunctor, Profunctor;
  - Category/Arrow.
- **Monoids** live here, and ChuiFrames's aggregation engine reuses them. Each has a partial / associative combine / final split, plus a `Mean`-style "aggregate with a final step" pattern; see the prototype's monoid design in `<root>/reference/prototype/DESIGN.md` §3.6.
- **Recursion schemes:** `Fix`, cata, ana, hylo, para, apo, histo, futu, and their monadic variants. ChuiFrames's optimizer will use these for plan rewrites.
- **Data types à la carte:** coproducts of functors, injection and projection, free monads, and an interpreter pattern (a free monad separates describing a program from running it).
- **Laziness:** thunks, memoized lazy values, lazy structure combinators.
- **Purity and effects conventions:** document what "pure" means in Julia, and how effects are tracked (marked) or kept apart (isolated). ChuiTypes supplies the effect types themselves.
- **Algebraic data types and pattern matching:** evaluate building your own versus Moshi.jl, SumTypes.jl and MLStyle.jl. Benchmark type stability, allocations and compile latency for each, then decide in an ADR.
- **Optics:** lenses and prisms. Evaluate Accessors.jl and reuse it if it's good enough.
- **Transducers:** decide in an ADR whether the shared transducer substrate lives here (own implementation, or adopting Transducers.jl), since both ChuiTypes streams and ChuiFrames's execution use one. The prototype's minimal version is in `<root>/reference/prototype/Tidy.jl`.
- **Inspiration:**
  - Haskell `base` and `recursion-schemes`;
  - Rúnar Bjarnason (*Functional Programming in Scala*, free monads, "Constraints Liberate, Liberties Constrain");
  - Bartosz Milewski (*Category Theory for Programmers*);
  - John De Goes (functional effects, ZIO);
  - Scala cats.

  Make it Julian: prefer dispatch and broadcasting over transliterated Haskell, and give every abstraction a documented runtime cost.
- **Name-conflict banner, like dplyr:**
  - In `__init__`, when `isinteractive()`, print the exported names that create real binding conflicts with Base or with already-loaded packages.
  - First establish by experiment how Julia resolves these: adding methods to `Base.f` is not a conflict.
  - Ship the banner as a small reusable utility, so ChuiTypes and ChuiFrames can use the same mechanism, and include a way to silence it.

## Phases (each ends with a report and a `HANDOFF.md` update)

1. **Research and ADRs:** survey the inspiration sources with verified notes. Decide: the trait encoding, the ADT/pattern-matching choice, transducers, optics, and whether the package is split internally (submodules).
   - ★ Report to the lead, which takes it to the user, before implementing.
2. **Traits and law kits:** composition, Monoids.
3. **Recursion schemes**, à-la-carte/free monads, laziness, optics.
4. **Performance pass:** JET-clean, allocation and TTFX budgets, PrecompileTools.
5. **Docs** (Documenter site with tutorials). Then v0.1.0: tag and register only after the user confirms, and record it in `<root>/releases.md`.

## Done means
- Law tests pass for every instance; JET, Aqua and ExplicitImports are clean.
- The contract tests in the root repo's contract list (`<root>/contracts/`) pass against this repo.
- The benchmarks meet the ADR budget.
- `]test` passes from a fresh clone.
