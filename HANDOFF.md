# Handoff

The one handoff file for this repo. Update it before stopping, before a compaction, and at
every checkpoint. Keep it short; history lives in git and in ADRs.

## State

- Branch: `feat/phase1-research` (worktree `.worktrees/phase1-research`), from main 06d2ae6.
  Not merged: **★ checkpoint, waiting for the user** via the lead.
- Factory 0.2.5, package profile (`.factory-version`). Contracts binding since 2026-10-19.
- Remote: none yet.
- Phase: **phase 1 (Research and ADRs) done, at ★.** No code changes.
  - Research: `docs/research/` (9 notes, index in its README).
  - ADRs 0001–0008, all Proposed (`docs/adr/README.md`).
  - Summary spec: `docs/superpowers/specs/2026-10-20-phase1-research-design.md`.

## ★ Decisions waiting for the user

1. **Q1 (ADR-0001):** may the Monoid family be instance values (dictionary passing) classified by a
   Holy trait, with constructor classes as Holy traits on owned tags? Recommended: yes.
2. **Q2 (ADR-0005):** export tiers (protocol, aggregators, transducers, optics and recursion schemes
   public-only); amend ecosystem ADR-0009's "ChuiCore exports `partial`". Recommended: tiers as
   proposed and amend ADR-0009; the alternative is an opt-in `ChuiCore.Prelude`.
3. **Q3 (ADR-0004, ADR-0008):** no Accessors hard dependency (it would add 3 packages and +22–41 ms
   per `using`); own Lens/Prism; ConstructionBase as a hard dependency. Recommended: yes.
4. **Q4 (ecosystem ADR-0007 §2):** Supposition 0.3.5 on Julia 1.10 does not record failing
   `@check`s (exit 0). Recommended: amend ADR-0007 §2 to require `@check record=false` plus an
   explicit `@test`; no upstream issue (the cause is 1.10's `Test`).
5. **Q5 (ADR-0006):** amend CC-001's "methods take exactly two arguments" (CompositionsBase's
   method is variadic) through a contract ADR. Recommended: yes.

## Open lanes

| Lane | Agent | File scope | Status | Report |
|---|---|---|---|---|
| phase1-research | the lead's teammate (this lane) | `docs/adr/**`, `docs/research/**`, `docs/superpowers/**`, `HANDOFF.md`, `changelog.d/phase1-research.md` | at ★, committed, not merged | sent to the lead |

All subagents of this lane (5 researchers, 3 critics) reported and are closed.

## Evidence

`subagent_mode: actual` (2026-10-20, Julia 1.10.12 and 1.13.2). Research runs are pasted in each
note. Gate results are in the lane's report to the lead.

## Checks NOT run, and why

- Unit tests, JET, Runic: no code changed in this phase.
- Speed rankings: machines were heavily loaded during research; allocations and inference only.

## Next action

- After the user answers the ★ questions: the lead merges this lane, then phase 2 (traits and law
  kits, composition, monoids).
