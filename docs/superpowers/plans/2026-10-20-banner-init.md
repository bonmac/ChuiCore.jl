# Banner-init plan: ChuiCore's own `__init__` name-conflict banner

- **Date:** 2026-10-20. **Branch:** `feat/banner-init` (from main a8404ca). **Tier:** T1 (behaviour
  of this package at load; no new public name, no dependency, no contract change).
- **Binding inputs:** `docs/agent/BRIEF.md` "Name-conflict banner, like dplyr" (in `__init__`,
  when `isinteractive()`; a way to silence it); ADR-0009 (load-time budgets); phase-3
  `binding_conflicts`/`conflict_banner` (`src/banner.jl`); phase-5 review nit N6.
- **File scope:** `src/**`, `test/**`, `docs/**`, `HANDOFF.md`, `changelog.d/banner-init.md`.

## Tasks

1. **Tests first** (`test/banner_init_tests.jl`): fresh `julia -i` subprocesses with a planted
   module in `Main` that exports `chain` and `papply`: the banner prints; silent with
   `CHUI_QUIET_CONFLICTS=1|true` and in a non-interactive run; a read-only `stderr` (with and
   without `JULIA_DEBUG=ChuiCore`) does not break `using ChuiCore`; `_init_banner` swallows a
   throwing `IO`. Children drop the parent's `CHUI_QUIET_CONFLICTS` and `JULIA_DEBUG`.
2. **Implement:** `__init__` in `src/ChuiCore.jl` calls `_init_banner(stderr, ChuiCore)` only when
   `isinteractive()`; `_init_banner` (`src/banner.jl`) wraps `conflict_banner` in `try`, logs the
   failure at debug level inside its own `try`, and rethrows only `InterruptException` (Ctrl-C).
3. **Budgets:** `benchmark/ttfx.jl --check` on 1.13 and 1.10; a fresh-process A/B against main for
   non-interactive and interactive loads. If the banner's code lands in the package image and
   costs measurable non-interactive load time, put an inference barrier (`invokelatest`) in
   `__init__` and record the trade-off.
4. **N6:** make the `binding_conflicts` docstring example independent of other modules in `Main`;
   check by running `Documenter.doctest(ChuiCore; manual = false)` twice in one process.
5. **Docs:** the conflict-banner tutorial (ChuiCore's own banner, when it fires, silencing, the
   recommended downstream `__init__`, the load cost with evidence); `conflict_banner`'s docstring;
   HANDOFF; `changelog.d/banner-init.md`.

## Definition of done

`ci.jl test` on 1.13 and 1.10, `test -- slow`, `quality`, `docs`, `format`, `guards`, `jet`, ttfx
`--check` on both versions, `dod.jl --base main`, with evidence files in `.lanes/evidence/`; the
reviewer's FINAL verdict. Not merged by the lane.
