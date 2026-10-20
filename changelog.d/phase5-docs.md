- Phase 5 (docs): a Documenter site in the ecosystem ADR-0008 layout. Tutorials, each a worked,
  doctested example: composition; monoids and aggregators (with CC-006's empty-input semantics);
  typeclasses and writing your own instance (style-typed methods, rule N5); law kits for
  downstream packages (the Supposition `record=false db=false` rule and why); transducers (with
  `foldparts` and the S1 per-partition caveat); recursion schemes over your own node type; free
  monads and an interpreter; optics; laziness; the conflict banner. How-to recipes. Explanation
  pages: why ChuiCore, purity and effects, export tiers and the clash list (why `neutral`,
  `curry`, `pure`, `ap` and `fmap` are public but not exported), the runtime cost model, and the
  phase-4 performance page. The reference is split into eight pages, with contract IDs marked.
  A changelog page is generated from `CHANGELOG.md` at build time.
- Every exported and public name owned by ChuiCore has a docstring with a `jldoctest` and a
  runtime-cost statement; effectful functions carry an `Effects:` line (docstring edits only, no
  behaviour change).
- Tests: a `:doctest` item (`test/doctest_tests.jl`) runs `Documenter.doctest` over the
  docstrings and `docs/src` on stable Julia; a `:quality` item fails when an owned public name
  lacks a `jldoctest` (unless listed in `docs/doctest-exemptions.md`) or a cost statement.
  Documenter joins `test/Project.toml`; Accessors, Supposition and Test join `docs/Project.toml`.
- Error-message wording: the constructor-class errors now say "is not an Applicative",
  "an Alternative", "an Arrow" (they said "a Applicative" etc.); message text only, the
  exception type (`ArgumentError`) is unchanged.
- The reference has a new internal constant `_CLASS_EXAMPLES` in `src/classes/core.jl`, used
  only to generate the style docstrings' examples.
- README: installation (ChuiRegistry once registered; by URL or local clone until then), a quick
  example, links.
