# Handoff

The one handoff file for this repo. Update it before stopping, before a compaction, and at
every checkpoint. Keep it short; history lives in git and in ADRs.

## State

- main a8404ca: phases 1–5 merged (phase 5 reviewer FINAL VERDICT: APPROVE WITH NITS).
- Branch `feat/banner-init` (worktree `.worktrees/banner-init`), from main a8404ca: ChuiCore's
  own `__init__` banner and review nit N6. Committed, not merged; review status in the lane
  report to the lead.
- Factory 0.2.6, package profile. Contracts binding since 2026-10-19.
- Version still 0.0.1. **v0.1.0 is not tagged or registered**: that waits for the user (checklist
  below).

## What phase 5 delivered

- Documenter site, ecosystem ADR-0008 layout: `docs/src/index.md`; ten tutorials in
  `docs/src/tutorials/` (composition, monoids, typeclasses, law-kits, transducers,
  recursion-schemes, free-monads, optics, laziness, conflict-banner); `howto/recipes.md`;
  `explanation/` (why, purity-effects, export-tiers, cost-model) plus `performance.md` (kept at its
  phase-4 path, cited by ADR-0009/0010 and `benchmark/allocs.jl`); `reference/` split into eight
  pages with contract IDs marked; `changelog.md` generated from `CHANGELOG.md` by `docs/make.jl`.
- Every owned exported/public name: a `jldoctest` and a cost statement (checked by the new
  `:quality` item in `test/doctest_tests.jl`); effectful ones carry an `Effects:` line.
  `docs/doctest-exemptions.md` is empty (no exemption needed).
- `:doctest` item runs `Documenter.doctest(ChuiCore; manual = true)` (stable only).
- Costs re-measured where docstrings quoted research-prototype figures (free monad, `Lazy`,
  `cata`/`ana`/`para` over `Fix`, banner); remaining research figures are labelled "research".
  Evidence: `.lanes/evidence/` (gitignored; copied from the sub-lane worktrees).
- One message-text fix (lead-approved): "an Applicative/Alternative/Arrow" in class errors.

## Decisions waiting (★, for the lead to take to the user)

1. Release v0.1.0 (checklist below): tag, register in ChuiRegistry, record in `<root>/releases.md`.
2. Pushing the repo and enabling docs deployment (`CHUI_DOCS_REPO`, a deploy key): outward actions.

## v0.1.0 release checklist (for the lead; `/release-check 0.1.0`)

1. Merge `feat/banner-init` into main after the reviewer's FINAL verdict (reviewed merge).
2. On main: `julia scripts/changelog.jl fold --dry-run`, then `fold` (moves every
   `changelog.d/*.md` under `## Unreleased`, deletes the fragments).
3. Bump `Project.toml` `version = "0.1.0"`; move `## Unreleased` under `## [0.1.0] - <date>`.
   0.0.1 → 0.1.0 is a minor bump of a pre-1.0 package: no contract ADR needed unless a contract
   entry changed (none did in phase 5).
4. Gates, pasting the last lines, counts saved with `julia scripts/evidence.jl tests -- …`:
   `ci.jl guards`, `ci.jl test -- all`, `ci.jl quality`, `ci.jl format`, `ci.jl docs`,
   `ci.jl contracts` (expected `NOT RUN (waiting)`: no upstreams), `ci.jl jet`; LTS:
   `CI_STABLE=false julia +lts scripts/ci.jl test`; ADR-0009's release-time budgets:
   `benchmark/ttfx.jl --check` and `benchmark/run.jl --check` on `+release` and `+lts`,
   `ci.jl test -- slow`.
5. Check: every dependency has a `[compat]` bound (Project.toml, test/, docs/, benchmark/); the
   working tree is clean; `changelog.d/` is empty.
6. Coordinator: the `releases.md` row and `compat-matrix.md` (release-manager drafts them);
   `integration/` against the released version.
7. **User confirmation needed** for: creating/pushing the GitHub repo (redact private names per
   the coordinator's rule first), tagging `v0.1.0`, registering in ChuiRegistry, enabling
   `deploydocs`. The README's install section already names ChuiRegistry and the URL.

## Open review nits (round 2; none blocks the merge)

- N6 (the `binding_conflicts` docstring example failed when doctests ran twice in one process):
  fixed on `feat/banner-init`.
- N7: the law-kit tutorials use `Test.anynonpass` / `ts.results`, Test internals (fine for
  stable-only doctests); add a note.
- N8: the traverse-allocation evidence came from a scratch script, not in the repo.
- N9: the schemes.jl header says costs cite `performance.md`; `hylo` and the stack-depth note
  still quote labelled research figures.

## Deferred (with reasons)

- Factory blind spot: `scripts/check_docs.jl` reads a Documenter cross-reference link whose
  target is a bare `@ref` (no explicit target) in Markdown as a stale path; pages use the
  explicit-target form `@ref ChuiCore.x`. A factory fix (T3).
- `ChuiCoreTransducersExt`; prisms inside Accessors compositions; `eduction`; a stack-safe `cata`;
  a typed `Cofree` (unchanged from phase 4).
- Factory nit N6 (`dod.jl`/`lane audit` read a stale `origin/main`): factory lane's.

## Open lanes

| Lane | Agent | File scope | Status | Report |
|---|---|---|---|---|
| banner-init | the lead's teammate (this lane) | `src/**`, `test/**`, `docs/**`, `HANDOFF.md`, `changelog.d/banner-init.md` | committed, not merged | to the lead |

phase5-docs and its sub-lanes are merged (a8404ca) and closed.

## The `__init__` banner (feat/banner-init)

- `__init__` (end of `src/ChuiCore.jl`): `isinteractive() && Base.invokelatest(_init_banner, stderr, @__MODULE__)`;
  `_init_banner` (`src/banner.jl`) catches any error, and guards its own `@debug` log too.
- Why `invokelatest`: a direct call compiled the banner into the package image (+0.3 MB native
  code, about +3–5 ms on every 1.10 load). With the barrier, non-interactive load equals main's;
  the price is about 0.25–0.3 s to compile the banner in interactive sessions (direct call: about
  0.1 s). **Lead's call** if a faster interactive banner is worth the per-load cost. Evidence:
  `.lanes/evidence/banner-init-load-{release,lts}-d150a86.txt` (script `banner-init-load-script.jl`
  beside them; gitignored).
- Tests: `test/banner_init_tests.jl` (fresh `julia -i` subprocesses: prints with a planted
  clash; silent with `CHUI_QUIET_CONFLICTS` and when non-interactive; a read-only `stderr`, with and
  without `JULIA_DEBUG=ChuiCore`, does not break `using`).

## Evidence

`subagent_mode: actual`. Julia 1.13.2 and 1.10.12, Apple M3 Pro, machine loaded. Gate outputs at
0f542b8 (clean tree) in `.lanes/evidence/{docs,tests-release,tests-lts,quality,format,guards,jet,dod}-0f542b8.txt`
(gitignored), pasted in the lane report; the sub-lanes' measurement evidence was copied there too.

## Checks NOT run, and why

- `ci.jl contracts`: NOT RUN (waiting): ChuiCore is the root package and has no upstreams.
- Doctests on LTS: by design (ADR-0008 §3, stable only).
- Benchmarks/TTFX budgets: no engine change in phase 5 (docstrings only); run at release.

## Next action

- Reviewer FINAL verdict, then the lead merges `feat/phase5-docs` and runs the v0.1.0 checklist
  with the user.
