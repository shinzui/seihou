---
id: 103
slug: reconcile-seed-steps-during-seihou-update-and-release-managed-files-to-seeds
title: "Reconcile seed steps during seihou update and release managed files to seeds"
kind: exec-plan
created_at: 2026-09-19T13:59:13Z
intention: "intention_01m2wz5ww3ezmvpf0aenfbgcjx"
master_plan: "docs/masterplans/12-seed-files-module-outputs-created-once-and-owned-by-the-project.md"
provenance:
  created_by:
    model: "claude-opus-5[1m]"
    harness: "claude-code"
    at: 2026-09-19T13:59:13Z
---

# Reconcile seed steps during seihou update and release managed files to seeds

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.

This plan is EP-5 of the MasterPlan
`docs/masterplans/12-seed-files-module-outputs-created-once-and-owned-by-the-project.md`.
Hard dependencies, all of which must be Complete:
`docs/plans/99-declare-seed-steps-in-the-module-schema-and-validate-them.md` (EP-1),
`docs/plans/100-record-seed-receipts-in-manifest-schema-8.md` (EP-2), and
`docs/plans/101-create-seed-files-once-during-seihou-run.md` (EP-3). Soft dependency:
`docs/plans/102-keep-seed-files-out-of-status-diff-and-remove.md` (EP-4), whose status line the
acceptance scenario observes.


## Purpose / Big Picture

A *seed file* is a file a module creates once, when the path is absent, and then hands to the
project: Seihou never overwrites, content-tracks, merges into, reports, or deletes it. Module
authors mark a step `lifecycle = Some "seed"`; `seihou run` already creates seeds and records a
*seed receipt* in the manifest's `seeds` map.

`seihou update` is the command that re-applies newer releases of the modules a project already
uses, merging module changes into files with a three-way merge. This plan teaches it seeds. The
most important case is every project that exists today: its `CHANGELOG.md`, `README.md`, and
`.cabal` files are *managed* because they were generated before seeds existed. When the module
releases a version that marks those steps as seeds, `seihou update` must *release* each file to
the project: remove its content record and baseline from the manifest, keep the bytes on disk
exactly as they are (edited or not, with no prompt), and record a receipt with outcome
`released-from-managed`. After that, `seihou status` stops reporting those files as
`modified by user`.

After this plan, for a module applied to a project:

- A seed step whose file exists is never written, merged, or reported as a conflict.
- A seed step newly added by a module release creates its file when absent.
- A seed the developer deleted is not re-created.
- A managed file whose step became a seed is released as described, exactly once.
- A seed whose step disappeared from the module loses the application from its receipt; the
  file is never deleted.
- A path that was a seed but whose step became managed again is *adopted*: the developer must
  choose, interactively, whether to keep their file (recording it as managed with its current
  content) or accept the generated version; `--force` does not choose for them.

The update plan (`seihou update --dry-run`, and `--json`) lists each seed action.


## Progress

- [ ] Milestone 1: seed reconciliations in `Seihou.Engine.Reconcile` (create, settle, release,
      abandon, adopt-as-conflict); orphan classification excludes released paths; ownership
      validation for seeds; unit tests.
- [ ] Milestone 2: transaction apply and final manifest (`UpdateTransaction`,
      `buildFinalManifest`), including baselines and rollback; schema-8 staging via
      `SeedReceipts`; no-op detection; unit tests.
- [ ] Milestone 3: remove the EP-3 interim guard; certification and agent-upgrade diagnosis
      ignore seed operations; text and JSON rendering; interaction rules for adoption.
- [ ] Milestone 4: end-to-end release scenario; `docs/cli/update.md`; ADR 0017 amendment;
      root `CHANGELOG.md`.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Model seed actions as new `FileReconciliation` constructors inside the existing
  `ReconciliationPlan`, rather than as a parallel plan.
  Rationale: The update transaction already snapshots every planned path, verifies the
  snapshots before the first mutation, journals writes, and rolls back on failure. Seed
  creation needs all of that (a seed must never overwrite a file that appeared after
  planning), and releases must commit atomically with the rest of the manifest.
  Date: 2026-09-19

- Decision: A release never prompts and ignores the file's edit state.
  Rationale: The module author has declared that the project owns the file. Asking the
  developer to confirm keeping their own changelog is noise; deleting or resetting it would
  destroy work.
  Date: 2026-09-19

- Decision: Adopting a seed back into management is a conflict that `--force` does not
  resolve.
  Rationale: `--force` means "accept the generated version" for managed conflicts, which here
  would overwrite a file the project has owned, possibly for years. The case is rare (a module
  reverting a seed); requiring an explicit choice is the safe default.
  Date: 2026-09-19

- Decision: A release or seed step on a path that an application outside the selection still
  manages is refused with a named error; expansion with `--include-shared-owners` is allowed
  but the expanded candidate must not manage the path either.
  Rationale: The manifest invariant is one lifecycle per path. Releasing on behalf of one
  application while another still manages it would be undone by that application's next
  update.
  Date: 2026-09-19


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

The repository is a Haskell (GHC 9.12) Cabal workspace: `seihou-core/` (domain library),
`seihou-cli/src/` (library `seihou-cli-internal`), `seihou-cli/src-exe/` (the `seihou`
executable). Read `CLAUDE.md` first: strict record fields, `generic-lens` labels for every
field access and update, no record dot or record update syntax, `import Data.Generics.Labels ()`
per module, library-first placement for new CLI modules.

**Vocabulary.** A *module* is a directory with `module.dhall` whose *steps* each generate a
file. An *application* (`ApplicationId`) is the manifest's record of one `seihou run` of a
module or recipe; `seihou update` re-plans selected applications against newer module
releases (the *candidate*). A *managed* file has a `FileRecord` in `Manifest.files`: content
`hash`, `moduleName`, `strategy`, `generatedAt`, `baseline` (reference to the exact generated
bytes under `.seihou/baselines/`), `applicationIds`, `sharedWriteMode`. The *baseline* is the
common ancestor for the three-way merge. The *ownership closure* is the rule that if any
selected application owns a managed path, every application that owns it must be selected
([ADR 0012](../adr/0012-an-additive-co-write-is-not-a-shared-path-conflict.md) exempts paths
all owners patch additively).

**What EP-1, EP-2, EP-3 provide** (verify before starting):

- `Step.lifecycle :: StepLifecycle` (`Managed | Seed`) in `Seihou.Core.Types`.
- `SeedRecord { moduleName, applicationIds, outcome, settledAt }`, `SeedOutcome`
  (`SeedCreated | SeedFoundExisting | SeedReleasedFromManaged`), `Manifest.seeds`, capability
  `SeedReceipts` (minimum schema 8), and in `Seihou.Core.Seed`: `mergeSeedRecord`,
  `dropSeedOwner`, `validateManifestInvariants`.
- `Operation`'s `SeedFileOp { dest, content, strategy, moduleName }`, produced by
  `compileComposedPlan` for seed steps, which also returns seed owners
  (`Map FilePath (Set ModuleName)`) and refuses a seed/managed mix within one composition.
- `Seihou.Engine.Seed`: `SeedDecision` (`SeedWrite | SeedKeepExisting | SeedRespectDeletion | SeedAlreadySettled | SeedReleaseManaged`),
  `classifySeed :: Maybe SeedRecord -> Maybe FileRecord -> Bool -> SeedDecision`,
  `PlannedSeed`, `planSeeds`, `executeSeeds`, and the interim
  `seedAsManagedWrite :: Operation -> Operation`, which EP-3 applied in
  `seihou-cli/src/Seihou/CLI/Update.hs` and `seihou-cli/src/Seihou/CLI/ManifestCapabilityUpgrade.hs`
  right after `compileComposedPlan` so that update treats seeds as managed until this plan.
  This plan removes it.

**How `seihou update` works.** Entry: `handleUpdate` in `seihou-cli/src-exe/Seihou/CLI/Update.hs`;
service: `seihou-cli/src/Seihou/CLI/Update.hs` — `planProjectUpdateIn` (around line 121)
selects applications (`Seihou.CLI.Update.Selection`: `enforceOwnershipClosure`,
`expandToSharedOwners`), stages candidate sources, and per application calls `planApplication`
(around line 511), which runs `compileComposedPlan` and builds a `PlannedApplication`
(`operations`, `desiredOwners :: Map FilePath DesiredFileOwner`). It materializes a staged
project (around line 760; note its local `operationDestination`, around line 777, which today
has a wildcard), plans migrations, then calls `Seihou.Engine.Reconcile.planReconciliation`
(`seihou-core/src/Seihou/Engine/Reconcile.hs`, around line 185 → `planReconciliationWith`
around 216). `UpdatePlan` (`seihou-cli/src/Seihou/CLI/Update/Types.hs`, around line 204)
carries `reconciliation :: ReconciliationPlan` and `manifestPreparation :: Maybe ManifestPreparation`
(an in-memory, lossless schema upgrade a feature stages when the on-disk manifest is older than
its minimum schema; see `ManifestPreparation` around line 175 and ADR 0014).
`applyProjectUpdate` (around line 419) resolves conflicts (`Seihou.CLI.Update.Interaction`:
`forceResolveUpdatePlan` around line 61, `resolveInteractively` around 72), then
`Seihou.Engine.UpdateTransaction.applyReconciliation` (around line 157) writes files through
`mutationFor` (around line 397: `WriteMutation`, `DeleteMutation`, `NoMutation`), with a
journal and `rollbackUpdateTransaction`. `prepareCandidateManifest` (around line 242) and
`applyOrphanManifestAction` (around line 290) compute the new `files` map;
`buildFinalManifest` (`Update.hs`, around line 1033) assembles the final `Manifest` with
`version = currentManifestVersion`. `isUpdateNoOp` (around line 1344) decides whether a plan
is a *deliberate no-op* ([ADR 0007](../adr/0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md)):
a plan that changes any recorded fact is not a no-op.

**Reconciliation today.** `planReconciliationWith` validates inputs (`validateInputs`,
`validateOwner` — the defence-in-depth ownership check), groups file operations by path
(`groupFileOperations`, using `operationDestination`, whose wildcard returns `Nothing` for any
operation it does not know — a `SeedFileOp` would be silently dropped), materializes each path
(`materializeOne`), classifies it (`classifyDesired`: create, update, auto-merge, unchanged,
or `FileConflict` with a `ReconciliationReason` of `MissingTrustedBaseline`,
`CurrentFileMissing`, `MergeDriverUnavailable`, `OverlappingEdits`), and classifies orphans
(`classifyOrphans`, around line 513): every manifest file owned by a selected application that
is **not** among the desired paths becomes `FileReleaseSharedOwnership` (other owners remain),
`FileAlreadyAbsent`, `FileDeleteSafe` (unchanged → **deleted**), or `FileOrphanEdited` (needs an
`OrphanChoice`). This last rule is why a release must be planned explicitly: a managed path
whose step became a seed is not a desired managed path, so without this plan it would be
classified as an orphan and, if unedited, deleted. `FileReconciliation` (around line 99) is the
sum type of all per-path actions.

**Certification.** `seihou-cli/src/Seihou/CLI/ManifestCapabilityUpgrade.hs`
(`certifySharedWriteModes` around line 172, `gatherApplicationEvidence` around line 248)
recompiles each co-owner of a shared managed path from its recorded version to learn how it
writes that path (ADR 0012). It has its own `operationDestination` (around line 229). A seed
operation is not a write to a managed path and must not count as evidence.

**Agent upgrade diagnosis.** `seihou-cli/src/Seihou/CLI/UpgradeDiagnosis.hs` runs
`seihou update --dry-run` internally and summarizes the plan into an *upgrade brief* for a
coding agent ([ADR 0016](../adr/0016-agent-assisted-upgrade-diagnoses-read-only-and-never-fails.md)).
Its rendering of the plan must mention releases so the agent does not "fix" them.

Tests: `seihou-core/test/Seihou/Engine/ReconcileSpec.hs` (uses `planReconciliationWith` with
map-backed readers), `UpdateTransactionSpec.hs`, `seihou-cli/test/Seihou/CLI/UpdateSpec.hs`,
`UpdateRenderSpec.hs`, `UpdateInteractionSpec.hs`, `ManifestCapabilityUpgradeSpec.hs`,
`UpgradeDiagnosisSpec.hs`, and the end-to-end `UpdateE2ESpec.hs` with fixtures from
`seihou-cli/test/Seihou/CLI/UpdateFixture.hs` (which builds a project, applies version A of a
fixture module, installs version B, and runs `seihou update`).

Relevant ADRs: [ADR 0012](../adr/0012-an-additive-co-write-is-not-a-shared-path-conflict.md)
(ownership closure and shared-write evidence apply to managed paths only),
[ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md) (stage
the minimum schema through the capability mapping, never by ad hoc version comparison),
[ADR 0007](../adr/0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md) (a plan that
records a new fact is not a no-op), [ADR 0015](../adr/0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md)
(errors name applications by label and lead with the repair),
[ADR 0016](../adr/0016-agent-assisted-upgrade-diagnoses-read-only-and-never-fails.md) (the
diagnosis stays read-only), and ADR 0017
(`docs/adr/0017-a-seed-file-is-created-once-and-belongs-to-the-project.md`), which this plan
amends with the release rule.


## Plan of Work

### Milestone 1 — plan seed actions in reconciliation

Scope: `planReconciliationWith` produces an explicit action for every seed path and never
treats a released path as an orphan. At the end, `ReconcileSpec` covers each case with
map-backed readers.

In `seihou-core/src/Seihou/Engine/Reconcile.hs`:

1. Add an explicit `SeedFileOp` case to `operationDestination` returning `Nothing`, with a
   comment that seeds are grouped separately, and remove the wildcard (list every constructor)
   so a future constructor fails the build here.
2. Partition `operations` into seed operations and the rest before `validateInputs`. For the
   rest, behave exactly as today, except as noted in step 5.
3. Add constructors to `FileReconciliation`:

   ```haskell
   | -- | Create a seed at an absent path.
     FileSeedCreate FilePath SeedAction ObservedFile
   | -- | Record or extend a receipt without touching disk (the file exists
     -- and is left alone, or the project deleted it).
     FileSeedSettle FilePath SeedAction ObservedFile
   | -- | Hand a managed file to the project: drop its record and baseline,
     -- keep the bytes, record 'SeedReleasedFromManaged'.
     FileSeedRelease FilePath FileRecord SeedAction ObservedFile
   | -- | The step no longer seeds this path: drop the selected applications
     -- from the receipt; never delete the file.
     FileSeedAbandon FilePath SeedRecord ObservedFile
   ```

   where `SeedAction` is a new record `{ content :: !Text, moduleName :: !ModuleName, applicationIds :: !(Set ApplicationId), decision :: !SeedDecision }`.
   Classify each seed path with EP-3's `classifySeed` (prior receipt, prior `FileRecord`,
   exists on disk): `SeedWrite` → `FileSeedCreate`; `SeedKeepExisting`, `SeedAlreadySettled`,
   `SeedRespectDeletion` → `FileSeedSettle`; `SeedReleaseManaged` → `FileSeedRelease`.
4. Ownership for seeds: for `FileSeedRelease`, if the prior `FileRecord`'s `applicationIds`
   include an application outside `selected`, return a new
   `ReconciliationError`: `SeedReleaseBlockedByOwners FilePath (Set ApplicationId)`. For any
   seed path, if a managed desired operation of another selected application targets it,
   return `SeedPathAlsoManaged FilePath` (this can happen across applications, which
   `compileComposedPlan` cannot see). Add both to the error rendering in
   `seihou-cli/src/Seihou/CLI/Update/Render.hs` with ADR 0015 wording, for example:
   `CHANGELOG.md is a seed in haskell-cli-app 0.3.0, but application "rei-cli" still manages it; update that application too (--include-shared-owners) or keep the path managed`.
   Give them stable error codes next to the existing ones (search `Render.hs` for
   `shared_path_requires_applications` to see the convention).
5. Orphans: pass the set of seed paths to `classifyOrphans` and exclude them from its
   candidates (a released path is handled by `FileSeedRelease`, never orphaned). Separately,
   produce `FileSeedAbandon` for every receipt in `manifest ^. #seeds` whose `applicationIds`
   intersect `selected` and whose path has no seed operation in this plan and no managed
   operation either.
6. Adoption (seed → managed): when a managed desired path has a receipt owned by selected
   applications and no `FileRecord`, classify it as a `FileConflict` with a new
   `ReconciliationReason` constructor `AdoptingSeedFile`, current content as the disk bytes and
   generated content as the candidate's. The resolved manifest must drop the receipt. If the
   receipt has owners outside `selected`, return `SeedPathAlsoManaged`.

Tests in `ReconcileSpec.hs`, one per case: create; settle (exists, no receipt); settle
(receipt, deleted); settle (receipt, present); release of an **unedited** managed file (no
delete, no write); release of an edited file (no prompt required, no write); release blocked by
an unselected owner; abandon; adoption yields a conflict with `AdoptingSeedFile`; and a guard
test proving a managed path whose step became a seed is **not** in the orphan set.

Acceptance: `cabal test seihou-core-test` passes.

### Milestone 2 — apply, manifest, schema staging, no-op

Scope: an update actually performs seed actions atomically and records them. At the end,
`UpdateTransactionSpec` proves creation, rollback, and manifest effects.

In `seihou-core/src/Seihou/Engine/UpdateTransaction.hs`: `mutationFor` returns
`WriteMutation content` for `FileSeedCreate` and `NoMutation` for the other seed constructors.
Snapshot verification must treat `FileSeedCreate` as requiring the path to be still absent at
apply time (the observed snapshot recorded `existed = False`), so a file created after
planning fails the update instead of being overwritten. In `prepareCandidateManifest` (and
`applyOrphanManifestAction` if that is where per-path manifest effects live), implement the
manifest effects: create/settle → `mergeSeedRecord` with the action's outcome
(`SeedCreated`, `SeedFoundExisting`, or unchanged for already-settled/deleted); release →
delete the `files` entry and `mergeSeedRecord` with `SeedReleasedFromManaged`; abandon →
`dropSeedOwner selected path`; resolved adoption → drop the receipt and record the `FileRecord`
as the chosen side dictates. The released path's baseline becomes unreferenced and is pruned
by the existing pruning of unreferenced baselines (confirm by reading how the update path
prunes, and add a test).

In `buildFinalManifest` (`seihou-cli/src/Seihou/CLI/Update.hs`), carry `seeds` from the
files-manifest (EP-2 made the field exist; make sure it is taken from the manifest the
transaction produced, not from the pre-update manifest). Before writing, assert
`validateManifestInvariants`.

Schema staging: when the reconciliation plan contains any seed action and the prepared (or
on-disk) manifest does not satisfy `manifestSupports SeedReceipts`, stage
`upgradeDocumentLosslessly (minimumManifestVersion SeedReceipts)` into `ManifestPreparation`,
exactly as the targeted additive update does (search `TargetedAdditiveSharedPathUpdate` in
`Update.hs` for the pattern). The 7 → 8 step is lossless, so this never requires the explicit
`seihou manifest upgrade`.

No-op: extend `isUpdateNoOp` so a plan is not a no-op when it contains `FileSeedCreate`,
`FileSeedRelease`, `FileSeedAbandon`, or a `FileSeedSettle` that would add an application or
create a receipt. A settle that changes nothing (receipt exists, application already an owner)
is compatible with a no-op.

Tests: `UpdateTransactionSpec.hs` — creation writes the file and the receipt; a file appearing
between planning and apply aborts and leaves disk and manifest unchanged; rollback after a
later failure deletes a created seed; release removes the `files` entry and adds the receipt
with the bytes on disk unchanged; abandon keeps the file. `UpdateSpec.hs` — `isUpdateNoOp`
cases.

### Milestone 3 — remove the interim guard; certification, diagnosis, rendering, interaction

Delete `seedAsManagedWrite` from `seihou-core/src/Seihou/Engine/Seed.hs` and its call sites in
`Update.hs` and `ManifestCapabilityUpgrade.hs`. In `Update.hs`, make the local
`operationDestination` explicit for every constructor and decide deliberately whether staging
should copy seed paths into the staged project (the staged project exists so migrations and
commands see the candidate tree; include a seed path only when it will be created, and
otherwise copy the project's current file if present, which the existing loop already does for
destinations). In `ManifestCapabilityUpgrade.hs`, exclude `SeedFileOp` from the operations
counted as writing a managed path, and make its `operationDestination` explicit. Add a
`ManifestCapabilityUpgradeSpec` case: an owner whose recorded version seeds a shared path is
reported as not writing it (a gap), never as an additive or whole-file writer.

Rendering (`seihou-cli/src/Seihou/CLI/Update/Render.hs`): in the text plan, a `Seed files`
block with one line per action — `create`, `keep (exists)`, `keep (deleted by you)` (omit
already-settled no-change lines), `release to project`, `no longer seeded (file kept)`; the
adoption conflict shows with the reason text
`was a seed; the module manages it again — choose keep (your file becomes tracked) or accept (the generated version replaces it)`.
In the JSON plan, add a `seeds` array of `{ "path", "module", "action" }` with actions
`create`, `settle`, `release`, `abandon`, and include adoption conflicts in the existing
conflicts list with reason `adopting-seed-file`. Update `UpdateRenderSpec.hs`.

Interaction (`seihou-cli/src/Seihou/CLI/Update/Interaction.hs`): `forceResolveUpdatePlan`
must leave `AdoptingSeedFile` conflicts unresolved (like `MergeDriverUnavailable`), so a
non-interactive `--force` run fails with `InteractionRequired` naming the path; the
interactive prompt for it offers keep and accept. Update `UpdateInteractionSpec.hs`.

Diagnosis (`seihou-cli/src/Seihou/CLI/UpgradeDiagnosis.hs`): where the brief summarizes the
dry-run plan, list releases under a short heading stating they are expected and must not be
reverted. Add an `UpgradeDiagnosisSpec` case.

### Milestone 4 — end to end, documentation, ADR

Add to `seihou-cli/test/Seihou/CLI/UpdateE2ESpec.hs` (or a new `SeedUpdateE2ESpec.hs` using
`UpdateFixture.hs`) a scenario: version A of a fixture module manages `CHANGELOG.md` and
`LICENSE`; apply A; edit `CHANGELOG.md`; install version B, which marks `CHANGELOG.md` as a seed
and adds a new seed `docs/NOTES.md`; run `seihou update --dry-run` and assert the plan shows
`release to project` for `CHANGELOG.md` and `create` for `docs/NOTES.md`; run
`seihou update --force` non-interactively and assert: exit 0; `CHANGELOG.md` bytes unchanged
(with the edit); `docs/NOTES.md` exists; the manifest has `CHANGELOG.md` and `docs/NOTES.md`
in `seeds` (outcomes `released-from-managed` and `created`), neither in `files`, version 8;
the old `CHANGELOG.md` baseline blob is gone from `.seihou/baselines/`; `seihou status` does
not list `CHANGELOG.md` and prints `Seed files: 2`; a second `seihou update` reports already up
to date. Add a second scenario for an unedited `CHANGELOG.md` proving it is not deleted.

Update `docs/cli/update.md`: a "Seed files" section describing each action, the release of
formerly managed files, adoption, and the two new errors. Amend ADR 0017 with a dated
paragraph recording the release rule (never prompts, never deletes, keeps bytes, idempotent),
adoption requiring an explicit choice, and the ownership refusals. Add a root `CHANGELOG.md`
entry.


## Concrete Steps

From `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`, in the Nix dev shell:

```bash
cabal build all
cabal test seihou-core-test --test-options='-p Reconcile'
cabal test seihou-core-test --test-options='-p UpdateTransaction'
cabal test seihou-cli-test --test-options='-p Update'
cabal test all
nix flake check
```

Expected dry-run excerpt for the release scenario:

```text
Seed files:
  release to project  CHANGELOG.md   (haskell-cli-app; your edits are kept, no longer tracked)
  create              docs/NOTES.md  (haskell-cli-app)
```

(Exact layout follows the existing plan renderer; the words `release to project` and `create`
are what the tests assert.)


## Validation and Acceptance

Before this plan (with EP-3's guard), updating to a release that marks `CHANGELOG.md` as a seed
keeps it managed and `seihou status` keeps reporting `modified by user`. After this plan, the
end-to-end scenario above holds, including the byte-identical edited file, the absent `files`
entry, the pruned baseline, and the idempotent second update. All tests pass; the new ones
fail before this plan.


## Idempotence and Recovery

A second update after a release is a no-op, because the path now has a receipt and no
`FileRecord` (`SeedAlreadySettled`). Seed creation goes through the update transaction, so an
interrupted update is recovered by the existing `recoverIncompleteTransactions` and a failure
rolls back created seeds. Releases write nothing to disk; if the manifest write fails the
release simply did not happen and the next update plans it again.


## Interfaces and Dependencies

At the end of this plan:

- `Seihou.Engine.Reconcile.FileReconciliation` gains `FileSeedCreate`, `FileSeedSettle`,
  `FileSeedRelease`, `FileSeedAbandon`; `SeedAction` record; `ReconciliationReason` gains
  `AdoptingSeedFile`; `ReconciliationError` gains `SeedReleaseBlockedByOwners` and
  `SeedPathAlsoManaged`.
- `Seihou.Engine.UpdateTransaction.mutationFor` and the candidate-manifest builder handle
  them.
- `Seihou.CLI.Update.isUpdateNoOp`, `buildFinalManifest`, schema staging via `SeedReceipts`.
- JSON plan `seeds` array and `adopting-seed-file` reason.
- `seedAsManagedWrite` no longer exists.

EP-6 (`docs/plans/104-adopt-seed-steps-in-seihou-modules-and-document-seed-authoring.md`)
relies on the release behavior to migrate real projects. No new library dependency.
