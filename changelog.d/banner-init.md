- ChuiCore's own name-conflict banner (the brief's "Name-conflict banner, like dplyr"): in an
  interactive session, `using ChuiCore` prints the exported names that clash with Base or with
  already-loaded modules, to `stderr`. It fires on any interactive load of ChuiCore (also
  `import ChuiCore`, or as a dependency of another package). Silent in non-interactive runs and
  when `CHUI_QUIET_CONFLICTS` is `1`/`true`. A failing banner (for example a read-only `stderr`,
  even with `JULIA_DEBUG=ChuiCore` logging the failure to it) never breaks the load; Ctrl-C
  still interrupts it. `__init__` calls it
  through `invokelatest`, so non-interactive load time is unchanged (ADR-0009); an interactive
  load pays about 0.25–0.3 s to compile and run the banner.
- The `conflict_banner` docstring and the conflict-banner tutorial show the recommended
  downstream `__init__` (interactive only, `invokelatest`, inside `try`), and the tutorial
  documents ChuiCore's own banner and its load-time cost.
- The `binding_conflicts` docstring example passes when doctests run twice in one process
  (review nit N6): it no longer assumes that only its own modules are loaded.
