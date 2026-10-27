---
id: 102
slug: keep-seed-files-out-of-status-diff-and-remove
title: "Keep seed files out of status, diff, and remove"
kind: exec-plan
created_at: 2026-09-19T13:59:13Z
intention: "intention_01m2wz5ww3ezmvpf0aenfbgcjx"
master_plan: "docs/masterplans/12-seed-files-module-outputs-created-once-and-owned-by-the-project.md"
provenance:
  created_by:
    model: "claude-opus-5[1m]"
    harness: "claude-code"
    at: 2026-09-19T13:59:13Z
  revisions:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-27T00:43:50Z
      mode: "update"
      note: "Specify precise removal, all declarative mutation protection and bounded reporting"
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-27T02:42:58Z
      mode: "implement"
      note: "Integrate bounded receipt reporting and exact recorded-instance removal with seed preservation"
  reviews:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-27T00:43:50Z
      verdict: "approved"
      note: "Reviewed revised plan against current source and cross-plan contracts; approval is for implementation design, not runtime delivery"
---

# Keep seed files out of status, diff, and remove

This ExecPlan is a living document. Maintain its Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective.

This is EP-4 of [MasterPlan 12](../masterplans/12-seed-files-module-outputs-created-once-and-owned-by-the-project.md).
Its hard dependency is [plan 100](100-record-seed-receipts-in-manifest-schema-8.md), including
Milestone 4's precise claim model. [Plan 101](101-create-seed-files-once-during-seihou-run.md)
is an integration dependency for the final real-command scenario; pure rendering/removal
work can use valid manifest fixtures before that plan completes.

## Purpose / Big Picture

Editing or deleting a project-owned starting file should not make `seihou status` report drift.
Status and diff compare managed files only. Status shows one bounded line, `Seed files: N
(created once; owned by the project, not tracked)`, counting recorded receipts rather than
files found on disk. Diff says how many seeds were not compared. Neither command reads seed
content or checks whether it exists.

`seihou remove MODULE` leaves seed objects untouched and retires only the selected module
instance's claims. A module with seed ownership needs no custom removal spec to relinquish
those claims. Existing `--application ID` selection handles ambiguity; ordinary unambiguous
removal stays one command. If other claims remain, retain the receipt; when the last claim
leaves, forget settlement without deleting the file.

## Progress

- [x] (2026-10-27) Milestone 1: bounded status/diff summaries omit seed content and preserve checkout reporting.
- [x] (2026-10-27) Milestone 2: instance-aware removal works without a custom spec, preserves co-owners and all seed bytes, and explains retained files.
- [x] (2026-10-27) Milestone 3: real-command acceptance, documentation, and integration with EP-3 pass.

## Surprises & Discoveries

Review (2026-10-26): removal now has `selectCheckoutRemoval` and `--application`, so the
original instruction to drop every application containing a module was both stale and lossy.
`RemoveSectionAction` also writes files; guarding only `RemoveFileAction` cannot promise seed
preservation. The old `seedsOwnedByModule` helper finds the first supplier, not every owner.

## Decision Log

Decision (2026-10-26): generalize recorded application/instance selection used by checkout
removal for seed ownership too. Do not add a second seed-specific CLI selection algorithm or
treat the receipt supplier as its sole owner. Seed-only cleanup without a removal specification
authorizes only metadata retirement, never unrelated managed deletion or shell execution.

Decision (2026-10-26): every declarative removal action overlapping a seed is kept/skipped,
including delete, strip-section, and rewrite. Inspect the original full manifest before
subtracting owners. Force cannot bypass preservation. Arbitrary removal shell is not sandboxed;
producer commands must honor ownership, and docs must state that boundary.

## Outcomes & Retrospective

All three milestones are accepted in source. `cabal test all` and `nix flake
check` passed; focused seed tests exercise the real run/status/diff/remove sequence,
including seed-only retirement without a custom spec, retained edited bytes, dry-run
immutability and later reseeding after receipt retirement. Core tests cover all
removal action forms, direct-operation defense, exact co-seeder retention and legacy
refusal. Reporting tests use an empty filesystem with populated receipts to prove
no seed content is requested. Existing checkout tests pass. ADR 0017 records the
shared selection and preservation policy. No friction entries were recorded under
this child; update/released delivery remain the next integration gates.

## Context and Orientation

Read `CLAUDE.md` for Haskell conventions. `seihou-core/src/Seihou/Core/Status.hs` already
iterates `Manifest.files`; seeds remain outside this map. CLI rendering is in
`seihou-cli/src/Seihou/CLI/StatusRender.hs` and `Diff.hs`; status's executable adapter is in
`src-exe/Seihou/CLI/Status.hs`. Core removal is `seihou-core/src/Seihou/Engine/Remove.hs`;
its adapter is `seihou-cli/src-exe/Seihou/CLI/Remove.hs`. Read both legacy removal and current
checkout selection paths; neither may bypass seed checks.

Plan 100 adds `SeedOwnership`, with exact `Map ApplicationId (Set ModuleName)` claims or
explicit legacy application-only claims. `moduleName` in a receipt is immutable first-supplier
provenance. Precise claims use qualified instance names from `Seihou.Composition.Instance`.
Helpers in `Seihou.Core.Seed` select/drop exact claims and preserve unknown ownership until
resolved, rather than guessing from a module's membership in an application.

Relevant ADRs: [0017](../adr/0017-a-seed-file-is-created-once-and-belongs-to-the-project.md)
(seed settlement), [0013](../adr/0013-status-is-a-bounded-summary-the-manifest-is-the-record.md)
(bounded status), [0018](../adr/0018-checkout-outputs-are-observable-portable-declarations.md)
(existing instance selection and checkout cleanup), and
[0015](../adr/0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md)
(actionable labels). This repository has no profiled ADR bundle.

## Plan of Work

### Milestone 1 — read-only reporting

Add `seedSection :: Manifest -> [Text]` to `StatusRender.hs`; empty maps render no line,
nonempty maps render one count line after tracked files. Keep managed and checkout summaries
unchanged. Change `formatDiffOutput` to accept the receipt count explicitly and append `N seed
files not compared` to changed and no-change summaries. Adapt all callers and any structured
output so human and machine reports do not invent content drift.

Extend `StatusSpec.hs`, core `StatusSpec.hs`, and `DiffSpec.hs`: mixed maps, zero seeds,
deleted/edited seeds, and a filesystem reader that fails if asked to inspect seed content.
The count is number of receipts, not active claims or existing objects. The full manifest is
a diagnostic record; routine use must not require `jq`.

### Milestone 2 — safe owner retirement

Extract/generalize `selectCheckoutRemoval` into shared recorded removal selection in
`Engine.Remove`. Select by application and qualified instance across seed, checkout, and
command ownership. Keep existing ambiguous-selection diagnostics and supported concrete
`seihou remove <qualified> --application <id>` remedies. Resolve legacy seed ownership from
exact recorded artifacts only when precise removal requires it; if unavailable, fail before
mutation with a useful evidence diagnostic, preserving claims.

Use plan 100's exact owner subtraction. Removing one seeder must preserve another seeder
within the same application, a seeder in a different application, and unrelated receipts in
the selected application. Update the application/instance and module lists consistently with
remaining managed, seed, checkout, and command claims. Reuse checkout's candidate-manifest
workflow; avoid parallel cleanup passes that overwrite each other's results. A seed-only owner
can retire with `removal = None`; any managed files require their existing explicit policy.

Add `KeepSeedOp FilePath` (or the equivalent explicit preservation action in a shared removal
plan) and render `Keep <path> (seed file; owned by the project)`. Classify all declarative
removal destinations against canonical seed paths and overlaps before execution, not just
remove-file. Protect receipts belonging to any owner, including the last owner being removed.
The execution path must also defend against a directly supplied removal operation bypassing
planning. `--force` does not change these rules. Do not read seed bytes to decide to keep them.

Print one bounded success summary such as `Retired N seed claims; project files were kept`,
with at most five path examples. Do not claim N physical files exist when some were deleted.
Seed-only removal dry-run displays retained paths even without custom steps.

Extend `RemoveSpec.hs` and CLI removal tests for all mutation actions, no-spec removal,
multiple instances in one application, multiple applications, shared checkout/seed selection,
ambiguity, legacy ownership refusal, unrelated receipts, and force. Test that last-owner
retirement permits a later application to seed an absent path again; this makes receipt lifetime
explicit rather than implying deletion memory lasts forever.

### Milestone 3 — ordinary workflow and docs

Use a built-binary fixture produced by EP-3: seed `CHANGELOG.md`, manage `LICENSE`, edit the
seed, run status/diff, then remove its owner. Verify status/diff omit seed drift, the retained
file is byte-identical, and the correct claims disappear. Repeat with a deleted seed and with
no custom removal spec. Before EP-3 completes, pure tests may use valid manifests; final
acceptance must use the real producer command.

Update `docs/cli/status.md`, `docs/cli/diff.md`, and `docs/cli/remove.md` (including its old
blanket claim that removal always requires a specification). Add root changelog and ADR 0017
implementation evidence. Coordinate the same summary wording with EP-5 and EP-6.

## Concrete Steps

From the repository root in its Nix development shell:

```bash
cabal build all
cabal test seihou-core-test --test-options='-p Remove'
cabal test seihou-cli-test --test-options='-p Status'
cabal test seihou-cli-test --test-options='-p Diff'
cabal test all
nix flake check
```

Use `cabal list-bin exe:seihou` to select the current executable for temporary-project
`run`, `status`, `diff`, and `remove` checks; record its revision/version.

## Validation and Acceptance

Status/diff require no seed filesystem reads. Remove keeps every seed object, even with
custom section removal and force, retires exactly the selected instance's claims, and leaves
checkout/managed behavior intact. The final scenario uses real run-produced receipts.

## Idempotence and Recovery

Reporting writes nothing. Seed removal changes only metadata; failure cannot justify deleting
seed content. Keep the existing command's manifest publication and checkout recovery behavior.
Repeating removal of an absent owner gives the existing not-applied diagnostic.

## Interfaces and Dependencies

EP-4 owns seed reporting and shared removal selection, and consumes EP-2's exact claim API.
It must not use `seedsOwnedByModule` as an ownership query unless that helper has been replaced
with a correctly named exact-claim implementation. EP-5/EP-6 consume the human output contract.

Revision note (2026-10-26): use current instance-aware removal, protect all declarative mutation
forms, permit no-spec seed retirement, and distinguish receipt counts from files on disk.
