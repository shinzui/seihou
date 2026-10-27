---
id: 12
slug: seed-files-module-outputs-created-once-and-owned-by-the-project
title: "Seed files: module outputs created once and owned by the project"
kind: master-plan
created_at: 2026-09-19T13:59:13Z
intention: "intention_01m2wz5ww3ezmvpf0aenfbgcjx"
provenance:
  created_by:
    model: "claude-opus-5[1m]"
    harness: "claude-code"
    at: 2026-09-19T13:59:13Z
  revisions:
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-15T16:10:15Z
      mode: "update"
      note: "Record completed seed declaration and schema prerequisites and checkout integration constraints"
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-27T00:43:50Z
      mode: "update"
      note: "Correct shared ownership, safe creation and transitions, milestone ordering, ordinary adoption and delivery gates"
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-27T02:11:07Z
      mode: "implement"
      note: "Resume ownership prerequisite and runtime implementation in declared dependency order"
  reviews:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-27T00:43:50Z
      verdict: "approved"
      note: "Reviewed revised plan against current source and cross-plan contracts; approval is for implementation design, not runtime delivery"
---

# Seed files: module outputs created once and owned by the project

This MasterPlan is a living coordination document. Child plans own implementation milestones;
this document owns dependencies, shared contracts, and delivery acceptance.

## Vision & Scope

Modules generate starting files such as changelogs, Cabal files, and application sources that
projects immediately edit. Keeping those files managed creates permanent drift noise and lets
later module updates change content the project should own. A seed step declares that ownership:

```dhall
S.Step::{
, strategy = "template"
, src = "CHANGELOG.md.tpl"
, dest = "CHANGELOG.md"
, lifecycle = Some "seed"
}
```

Omitted lifecycle remains managed. Seed supports copy, template, and dhall-text whole files;
patches, structured merges, and symlink strategies are excluded. Checkout remains the separate
lifecycle for reproducible local outputs. A seed is created only when absent and not previously
settled; a pre-existing regular file is kept. A content-free manifest receipt remembers first
settlement and active application/module-instance claims. While that receipt exists, edits and
deletion belong to the project. Last-claim retirement forgets settlement without touching disk;
later reintroduction may seed an absent path again. No reseed or general untrack command is added.

The ordinary acceptance workflow is designed before implementation. A fresh user installs the
registry once, runs a module with normal variable prompts, and edits its starting files. Re-run,
force, status, diff, update, and remove preserve those files. An existing remote-backed project
with saved inputs and edited files adopts with one command:

```bash
seihou update haskell-cli-app
```

Update owns remote candidate/dependency fetching and lossless manifest preparation. Its normal
preview includes `release to project`; accepting that update drops managed tracking and baseline
references while preserving bytes or deliberate absence. There is no prerequisite install/upgrade,
per-file release prompt, manual JSON/index edit, or transitive target list. A second unchanged
update is a no-op. Clones/worktrees use committed receipts, including intentional deletion;
checkout setup remains `seihou sync`. Receipt retirement works through ordinary remove, including
a seed-only module with no custom removal specification. Ambiguous selection uses the existing
application/qualified-instance selector and gives an exact supported command.

Seihou's declarative operations must not overwrite, patch, migrate, or delete a settled seed.
Seed-to-managed adoption is an explicit keep/accept transition in update, never implied by force.
Arbitrary shell commands are not sandboxed by lifecycle semantics; adopting producers must be
audited and documented accordingly. No new module minimum-client-version schema is introduced,
but a runtime-supporting release and documented minimum version are required before publishing
seed-producing modules. Older clients ignoring lifecycle can overwrite seeds; this is not a safe
fallback. Delivery includes the runtime release, producers, and installed-binary acceptance.

## Decomposition Strategy

Keep six functional concerns. EP-1 declares and validates the field; it is complete. EP-2 owns
receipts and versioning; its original schema-8 work and schema-11 exact
application/instance claim correction are complete before runtime production. A first supplier plus application set
cannot represent two modules seeding the same path within one recipe. EP-3 owns first creation,
composition, common classification, and no-replace filesystem effects. EP-4 owns reporting and
instance-aware removal. EP-5 owns lifecycle evolution within the existing update transaction.
EP-6 owns real producer classification, adoption, release, and installed developer acceptance.

This keeps update's reconciliation/recovery risk separate from run, without permitting unsafe
intermediate behavior. EP-3 refuses update of selected seed candidates/owners until EP-5 lands;
it must never convert seeds to managed writes. A tiny early producer candidate and real consumer
proof run before broad reconciliation variants, instead of postponing all usability checks to
EP-6. No additional plan or generic resource framework is needed.

Relevant local decisions are [ADR 0001](../adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md)
(portable state), [ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md)
(one record), [ADR 0012](../adr/0012-an-additive-co-write-is-not-a-shared-path-conflict.md)
(managed ownership), [ADR 0013](../adr/0013-status-is-a-bounded-summary-the-manifest-is-the-record.md)
(bounded reporting), [ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md)
(version semantics), [ADR 0015](../adr/0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md)
(diagnostics), [ADR 0017](../adr/0017-a-seed-file-is-created-once-and-belongs-to-the-project.md)
(seed contract), and [ADR 0018](../adr/0018-checkout-outputs-are-observable-portable-declarations.md)
(checkout compatibility). The relevant producer record is in `mori://shinzui/seihou-modules`,
project-relative `docs/adr/2-separate-keiro-project-seeds-from-domain-implementation.md`
(artifact-level URI pending); it already defines Keiro starters as project-owned implementation
seeds. The local ADR corpus has no OKF profile, verified with `mori show --full`.

## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft / Integration Deps | Status |
|---|-------|------|-----------|-------------------------|--------|
| 1 | Declare seed steps and validate them | docs/plans/99-declare-seed-steps-in-the-module-schema-and-validate-them.md | None | None | Complete |
| 2 | Record seed receipts; correct exact ownership before runtime use | docs/plans/100-record-seed-receipts-in-manifest-schema-8.md | None | EP-1 vocabulary | Complete |
| 3 | Create seed files once during run | docs/plans/101-create-seed-files-once-during-seihou-run.md | EP-1, EP-2 including M4 | EP-5 consumes common APIs | Not Started |
| 4 | Report and remove seed ownership | docs/plans/102-keep-seed-files-out-of-status-diff-and-remove.md | EP-2 including M4 | EP-3 real-command acceptance | Not Started |
| 5 | Reconcile seeds and release managed files | docs/plans/103-reconcile-seed-steps-during-seihou-update-and-release-managed-files-to-seeds.md | EP-1, EP-2 including M4, EP-3; M2 also needs EP-6 M1 candidate | EP-4 status acceptance | Not Started |
| 6 | Adopt producers and verify delivery | docs/plans/104-adopt-seed-steps-in-seihou-modules-and-document-seed-authoring.md | M1: none; M2–M4: EP-3, EP-4, EP-5 | EP-5 M2 consumer proof | In Progress |

Status values are Not Started, In Progress, Complete, Cancelled. EP-2 includes the accepted
original receipt foundation and the completed schema-11 ownership correction. M1/M2/M4 refer to the named milestones in the linked child, not whole-plan completion.

## Dependency Graph

The graph is acyclic at milestone granularity. Complete EP-2 M4, then EP-3. EP-4 can implement
reporting/removal once EP-2 completes; its final producer-command proof waits for EP-3. EP-6 M1
can classify the current producers and prepare a disposable candidate now. EP-5 M1 consumes the
completed EP-3 APIs; EP-5 M2 uses EP-6 M1's candidate for an ordinary existing-consumer update.
Only after that early proof expand EP-5 M3/M4. Complete EP-4/EP-5 integration before EP-6 M2–M4
publish/adopt and verify released behavior. Whole-child states remain In Progress until all their
acceptance criteria pass; no dependency is silently weakened.

EP-2 M4 is implemented and accepted in source. The next implementation work is EP-3. EP-6 M1 is ready independent preparation. Release
readiness requires EP-3, EP-4, and EP-5 together; the interim refusal is a safe development
boundary, not a delivered seed workflow. A source build and a candidate checkout do not close
the delivery gate.

## Integration Points

**Declaration and validation — EP-1 foundation, EP-3 runtime extension.** Existing `Step.lifecycle`
is `Managed | Seed | Checkout`; existing `Strategy` includes `Symlink`. `Core.Module.checkSeedSteps`
is consumed by validation and compilation. EP-3 extends unsupported-strategy/removal checks and
validates resolved active paths; literal Dhall destination comparisons cannot establish collision
safety. Preserve checkout APIs and existing schema pins. EP-6 authors only supported seed steps.

**Receipts and ownership — EP-2.** `Manifest.seeds` remains a separate content-free path map.
`SeedRecord.moduleName`, `outcome`, and `settledAt` describe first settlement. Active ownership
is `SeedOwnership = LegacySeedOwners (Set ApplicationId) | KnownSeedOwners (Map ApplicationId
(Set ModuleName))`, with qualified instance names. EP-2 owns codec, exact merge/drop/replace
helpers, legacy evidence preparation, and invariant checks; EP-3/EP-4/EP-5 use those helpers.
Do not use supplier provenance as an ownership index. Last exact claim removal drops the receipt;
unknown legacy owners are retained until evidence resolves them.

Schema 11 now implements this contract. Preserve historical `SeedReceipts = 8`, add `SeedOwnerClaims` at the next
adjacent schema (11 absent intervening changes), and wrap old application-only ownership in an
explicit legacy variant losslessly. Exact historical instance inference is separate and never
faked by the structural upgrade. EP-2 tests that service with injected evidence; EP-3 connects
compiled seed claims, preventing a dependency cycle. Normal commands own evidence lookup when
needed, using exact recorded origins/versions and saved inputs. New writers emit known claims.

**Composition and common engine — EP-3.** `SeedFileOp` carries destination, rendered content,
strategy, and explicit supplier. `ComposedPlan` replaces the positional tuple with named
operations, warnings, managed-owner and seed-owner fields. First seed in composition execution
order supplies bytes; every qualified seeder is recorded. Across applications EP-5 preserves
manifest application order. Mixed seed/managed/checkout claims and path overlaps refuse before
mutation, including retained manifest claims. EP-3 updates all compile consumers together.

`Seihou.Engine.Seed.classifySeed :: Maybe SeedRecord -> Maybe FileRecord -> PathEntry ->
Either SeedError SeedDecision` is shared by run and update. Managed record means release;
receipt means already-settled or respect-deletion; otherwise missing means create, regular file
means keep, and symlink/directory means refuse. Planned seeds retain the explicit supplier and
owners; effectful helpers take project root explicitly. Existing `PathEntry`/`inspectPath`
replace a Boolean existence test. EP-3 owns exclusive no-replace creation and pure/IO interpreter
contracts. A check followed by ordinary write/rename is not sufficient.

**Update/recovery — EP-5.** Owns `FileSeedCreate/Settle/Release/Abandon`, explicit reverse-adoption
choices, content-free metadata actions, exclusive-create transaction mutation, and recovery
journal changes. Seed releases cannot enter orphan deletion or generated baselines. A released
baseline blob is pruned only when unreferenced. Snapshot verification is not exclusive creation.
Rollback only removes an unchanged object the transaction actually created; metadata-only paths
are never restored. Preserve checkout snapshots/index recovery, declarations, commands, and
current schema. Seed claims do not constitute additive managed-write evidence. Every declarative
migration/staging mutation and automatic commit path selection must honor project ownership.

**Removal/reporting — EP-4.** Generalize existing recorded checkout instance selection instead
of adding another algorithm; seed-only retirement works without custom removal. All declarative
mutation forms preserve seed paths, including other owners' paths. One receipt count line does
not assert files exist. Status/diff never read seed content. EP-5/EP-6 consume these summaries;
normal use does not require JSON inspection.

**Producer/consumer proof and delivery — EP-6 with EP-5.** EP-6 M1 owns a minimal current producer
candidate; EP-5 M2 owns first ordinary existing-consumer execution before variant expansion.
EP-6 owns final published-registry and installed-runtime evidence for all three producers:
`mori://shinzui/seihou-modules/templates/haskell-cli-app`,
`mori://shinzui/seihou-modules/templates/haskell-library`, and
`mori://shinzui/seihou-modules/templates/haskell-keiro-project`. Empty caches and older supported
manifest state are part of acceptance. Local fixture preparation is disclosed, never treated as
a user-facing feature. No code or producer release is performed by this planning update.

**Documentation/ADRs.** Each child owns documentation for its command and root changelog entry.
EP-2 owns manifest/version docs; EP-3 run docs; EP-4 status/diff/remove; EP-5 update/automation;
EP-6 author guidance/user release notes and producer docs. ADR 0017 carries shared ownership,
creation, transition, and shell boundaries; ADR 0014 records actual version implementation when
it lands. Child plans amend evidence, without claiming proposed APIs are already implemented.

## Progress

EP-1 and EP-2 are complete. Schema 11 now preserves exact application/qualified-instance
seed claims and explicit legacy uncertainty. All three test suites and flake checks pass;
a built binary verified ordinary schema-8 upgrade and repeat no-op. EP-3–EP-5 runtime work is not started; EP-6 M1 audit/candidate preparation is in progress. Next: prove run and ordinary existing-consumer update. EP-6 producer classification has
been recorded and a disposable CLI seed candidate prepared; candidate validation and the
pre-seed consumer remain before accepting EP-6 M1. The final cross-plan gate is released
runtime plus published producers verified through the installed executable, including fresh use,
existing edits, deletion, repeated use, clone/worktree setup, removal, and recovery.

## Surprises & Discoveries

The 2026-10-26 review verified these mismatches against the working tree: schema 10 and checkout
selection/recovery have superseded the old schema-8-only assumptions; `checkSeedSteps` moved to
`Core.Module`; `buildFinalManifest` already preserves seeds; remote update fetches dependencies;
producer versions and destination lists changed. More seriously, original ownership loses
co-seeders in one application, the temporary managed adapter violates seed guarantees, and
check-then-write cannot prevent replacement. Original removal guarded delete but not section
writes; original adoption left missing-file behavior unspecified. These are required corrections
within the initiative, not additional optional follow-up plans.

## Decision Log

Decision (2026-10-26): retain six concerns but reopen EP-2 and specify an interleaved early
producer/consumer check. This preserves the intended outcome and API ownership while finding
workflow failures before expanding tests and releasing producers.

Decision (2026-10-26): separate immutable first-settlement provenance from exact live claims;
represent legacy uncertainty explicitly and version the semantic change. This corrects the
original schema-8 design without rewriting history or guessing lost information.

Decision (2026-10-26): remove the original `seedAsManagedWrite` decision. Unsupported intermediate
update refuses before mutation; runtime seed support ships only with run/report/remove/update
accepted together. Older-client compatibility is a release constraint, not permission to overwrite.

Decision (2026-10-26): run refuses lifecycle transitions before publishing candidate metadata;
update owns managed release and explicit reverse adoption. Normal release requires no additional
per-file confirmation beyond ordinary update acceptance.

Historical foundation: EP-1 and EP-2 M1–M3 landed on 2026-10-15 in commit `66466b4` as prerequisites
of plan 105. Their completion did not implement runtime seeds. The original lifecycle-as-text,
content-free receipt, and six-concern decomposition decisions remain; the unsafe fallback and
application-only ownership assumptions are superseded above.

## Outcomes & Retrospective

Current implementation: EP-1 and EP-2 are complete in source, including the schema-11
correction and ordinary upgrade proof. Runtime, adoption, and release gates remain open.

The preceding planning update reviewed all six child plans against source, current producer declarations, and
relevant ADRs, and reconciled the shared contracts and developer workflow. That review changed plans and
ADR 0017 only; runtime code, releases, and installations remain open work. Original authorship is
`claude-opus-5[1m]` for the MasterPlan and all children; prior `gpt-6.1-sol` revisions cover the
MasterPlan and EP-1/EP-2. None had recorded review entries before this pass.

Revision note (2026-10-26): correct unsafe intermediate writes, receipt ownership and race
semantics; preserve current checkout/schema APIs; schedule early real adoption and require
published/installed delivery evidence. Reopened EP-2 is reflected consistently in the registry.
