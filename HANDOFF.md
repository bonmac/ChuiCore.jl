# Handoff

The one handoff file for this repo. Update it before stopping, before a compaction, and at
every checkpoint. Keep it short; history lives in git and in ADRs.

## State

- Branch: `feat/phase1-research` (worktree `.worktrees/phase1-research`), from main 06d2ae6.
  Not merged: ★ answered; **waiting for the lead to merge**.
- Factory 0.2.5, package profile (`.factory-version`). Contracts binding since 2026-10-19.
- Remote: none yet.
- Phase: **phase 1 (Research and ADRs) done and accepted.** No code changes.
  - Research: `docs/research/` (9 notes, index in its README).
  - ADRs 0001–0008, all Accepted 2026-10-20 (`docs/adr/README.md`).
  - Summary spec: `docs/superpowers/specs/2026-10-20-phase1-research-design.md` (Accepted).

## ★ Decisions (answered by the user, 2026-10-20; all recommendations accepted)

1. **Q1 (ADR-0001):** dictionary passing (instance values) with a Holy-trait classifier; constructor
   classes as Holy traits on owned tags. Accepted.
2. **Q2 (ADR-0005):** the three name tiers (aggregation protocol, aggregators, transducers, optics
   and recursion schemes are public, not exported). Accepted. Ecosystem ADR-0009 is amended in the
   coordinator by another lane (pending).
3. **Q3 (ADR-0004, ADR-0008):** own Lens/Prism; Accessors as an extension only; ConstructionBase as
   a hard dependency. Accepted.
4. **Q4 (ecosystem ADR-0007 §2):** amended to `@check record=false` plus an explicit `@test`, and a
   planted violation on the LTS job; no upstream issue. Accepted; the coordinator lane writes it
   (pending).
5. **Q5 (ADR-0006):** CC-001 amended through a contract ADR (Chui-added methods stay binary; the
   upstream fallback and a downstream closing varargs method may be variadic). Accepted; the
   coordinator lane writes it (pending).

## Open contract follow-ups

- The PROVISIONAL items in `contracts/chui-core.md` (coordinator): CompositionsBase binding, export
  list, typeclass trait encoding, law kits, name-conflict banner, composition helpers, the
  transducer substrate API, recursion schemes. Each ADR's Consequences says when its item can
  become stable. The coordinator's eco-amend lane drafts the contract text; applying it is T3
  (the user).
- ADR-0003 Decision 4: only `isstateless` pipelines may run per partition; proposed for the
  contract.

## Open lanes

| Lane | Agent | File scope | Status | Report |
|---|---|---|---|---|
| phase1-research | the lead's teammate (this lane) | `docs/adr/**`, `docs/research/**`, `docs/superpowers/**`, `HANDOFF.md`, `changelog.d/phase1-research.md` | ★ answered, ADRs accepted, committed, not merged | sent to the lead |

All subagents of this lane (5 researchers, 3 critics) reported and are closed.

## Evidence

`subagent_mode: actual` (2026-10-20, Julia 1.10.12 and 1.13.2). Research runs are pasted in each
note. Gate results are in the lane's report to the lead.

## Checks NOT run, and why

- Unit tests, JET, Runic: no code changed in this phase.
- Speed rankings: machines were heavily loaded during research; allocations and inference only.

## Next action

- The lead merges this lane; then phase 2 per `docs/agent/BRIEF.md` (traits and law kits,
  composition, monoids).
