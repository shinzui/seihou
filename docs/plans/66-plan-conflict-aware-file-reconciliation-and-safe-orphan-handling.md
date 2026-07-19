---
id: 66
slug: plan-conflict-aware-file-reconciliation-and-safe-orphan-handling
title: "Plan conflict-aware file reconciliation and safe orphan handling"
kind: exec-plan
created_at: 2026-07-19T16:27:06Z
intention: "intention_01kxxjwvf8e2e8r64feyk6r65b"
master_plan: "docs/masterplans/8-make-module-updates-seamless-and-conflict-aware.md"
---

# Plan conflict-aware file reconciliation and safe orphan handling

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, Seihou can turn a newly rendered composition into one safe,
application-scoped action per project path. Repeated patch operations such as four modules
contributing to `.gitignore` are materialized in order and shown as one file result. A
generated file edited only by the module updates automatically; a file edited only by the
user is preserved; non-overlapping changes on both sides use EP-65's three-way merge; only
overlapping changes require a decision.

Files removed from the new module version receive an explicit orphan policy. An unchanged
obsolete generated file is safe to delete. An edited orphan is retained and remains tracked
until the user explicitly deletes or detaches it. A file still owned by another recorded
application loses only the application being updated and is not deleted.

This plan supplies a pure `ReconciliationPlan`, resolution functions, rendering-neutral
summary data, and a managed apply layer with a recovery journal. It does not fetch modules,
resolve variables, or add CLI flags; EP-68 and EP-69 compose and expose it.


## Progress

- [ ] M1: Define desired-file and reconciliation domain types.
- [ ] M1: Materialize writes, copies, and ordered patches into one generated result per path.
- [ ] M1: Backfill a missing legacy baseline only when the current disk hash is trustworthy.
- [ ] M2: Classify creates, updates, automatic merges, true conflicts, shared ownership, and orphans.
- [ ] M2: Add explicit merge-conflict and orphan resolution functions and summary counts.
- [ ] M3: Apply a fully resolved plan with atomic per-file writes and a recovery journal.
- [ ] M3: Update applied hashes, new baseline references, and application ownership consistently.
- [ ] M3: Add pure, real-filesystem, interruption-recovery, and multi-application tests.
- [ ] M3: Run all validation and record a temporary-project reconciliation transcript.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

- Decision: Reconcile paths, not raw generation operations.
  Rationale: Users edit files, and the manifest tracks files. Showing or resolving four
  patch operations for one `.gitignore` path exposes implementation detail and can produce
  inconsistent per-operation choices.
  Date: 2026-07-19.

- Decision: Derive new generated content by replaying ordered patch operations against the
  prior generated baseline, not against the user's current file.
  Rationale: The baseline represents the module's previous side of the three-way merge.
  Applying new patches directly to current disk would mix user edits into the generated
  side before merge and make overlap detection meaningless.
  Date: 2026-07-19.

- Decision: Adopt a legacy file's current disk content as its first baseline only when its
  hash equals `FileRecord.hash`.
  Rationale: Equality proves the user has not changed the file since the old manifest was
  written. If hashes differ and no baseline blob exists, the common ancestor is unknown;
  conservative conflict is the only data-safe result.
  Date: 2026-07-19.

- Decision: Keep edited orphans tracked by default and make detachment explicit.
  Rationale: The current run path deletes the manifest record but leaves the file, silently
  abandoning it. Retaining ownership makes the unresolved state repeatable and visible on
  the next update.
  Date: 2026-07-19.

- Decision: A resolved `KeepCurrent` file conflict advances the generated baseline to the
  new module output while leaving the disk content and applied hash at the user's version.
  Rationale: The user has accepted the module update but chosen their side for this file.
  On the next update, their customization remains a change relative to the latest accepted
  generated baseline and can be merged again.
  Date: 2026-07-19.

- Decision: Reject a plan when a selected application would regenerate a path also owned
  by an unselected application.
  Rationale: The stored baseline is the combined generated ancestor, not a replayable
  per-application operation history. Rendering only one owner cannot prove that another
  owner's contribution is preserved. Selecting every owner permits one ordered batch;
  otherwise the safe result is an actionable preflight error.
  Date: 2026-07-19.

- Decision: Require every conflict to be resolved before applying any file action.
  Rationale: Publishing a new module version while some files remain based on the old
  version recreates the hybrid state this initiative exists to eliminate. A user may choose
  KeepCurrent or RetainTracked, but an undecided conflict aborts the apply phase.
  Date: 2026-07-19.

- Decision: Use a durable text-file recovery journal for managed project mutations.
  Rationale: Atomic rename protects one file, not a multi-file update. A journal lets the
  next invocation restore already-mutated managed paths after process failure. Shell
  command side effects remain outside this guarantee and are documented separately.
  Date: 2026-07-19.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This plan requires EP-64 and EP-65. Verify both are Complete in
`docs/masterplans/8-make-module-updates-seamless-and-conflict-aware.md`. EP-64 defines
application-scoped file ownership and baseline references. EP-65 provides
`BaselineStore`, `MergeOutcome`, and `threeWayMerge`.

`seihou-core/src/Seihou/Composition/Plan.hs` compiles every module instance and merges the
resulting operation lists. It collapses multiple complete writes to the same destination
using last-writer-wins or structured JSON/YAML merge. A `PatchFileOp` is folded into an
earlier in-memory `WriteFileOp`, but when the target exists only on disk, each patch remains
as an operation. Commands and directory creation remain in the list.

`seihou-core/src/Seihou/Engine/Diff.hs` currently converts planned file tuples to a map and
compares manifest hash, disk hash, and planned hash. Any user change to a non-patch file
becomes a whole-file `ConflictFile`; the old generated content is unavailable. Patch
operations bypass conflicts altogether. Orphans are any active-module manifest path missing
from the new plan. This model is appropriate for its historical hash-only manifest but is
not the update model after EP-65.

`seihou-core/src/Seihou/Engine/Execute.hs` writes every supplied operation and returns
records. `seihou-core/src/Seihou/Engine/Conflict.hs` prompts per conflict with accept, keep,
skip, or abort. Do not extend these types until they become a second update model. Add the
new update-specific engine alongside them, let EP-68 use it, and leave ordinary `seihou run`
behavior compatible. A later simplification may move run onto reconciliation after the
update path has shipped.

`Seihou.Engine.Section.applyTextPatch` applies AppendFile, PrependFile, AppendSection, and
AppendLineIfAbsent. Use this one implementation while materializing patch sequences. The
same module-defined order that appears in the composed operation list must be retained.

A **recovery journal** is a directory under `.seihou/transactions/<id>/` containing a JSON
description plus the previous text for every path that may be changed or deleted. It exists
before the first mutation and is removed only after the caller has made the new manifest
durable. Recovery restores old files or removes files that were absent before the update.
The journal covers Seihou-managed text paths and newly created directories, not arbitrary
command effects.


## Plan of Work

### Milestone 1: materialize one desired generated file per path

Create `seihou-core/src/Seihou/Engine/Reconcile.hs` and expose it from
`seihou-core/seihou-core.cabal`. Define rendering-neutral data types. The exact constructor
field layout may evolve during implementation, but these outcome distinctions must remain:

```haskell
data DesiredFile = DesiredFile
  { path :: FilePath
  , generatedContent :: Text
  , moduleName :: ModuleName
  , strategy :: Strategy
  }

data ReconciliationReason
  = MissingTrustedBaseline
  | MergeDriverUnavailable Text
  | OverlappingEdits

data FileReconciliation
  = FileCreate DesiredFile
  | FileUpdate DesiredFile
  | FileAutoMerge DesiredFile Text
  | FileUnchanged DesiredFile
  | FileConflict DesiredFile Text Text ReconciliationReason
  | FileDeleteSafe FilePath FileRecord
  | FileOrphanEdited FilePath FileRecord Text
  | FileReleaseSharedOwnership FilePath FileRecord
  | FileAlreadyAbsent FilePath FileRecord

data ReconciliationPlan = ReconciliationPlan
  { applicationIds :: Set ApplicationId
  , files :: Map FilePath FileReconciliation
  }
```

Add a materialization function that accepts the project root, current manifest, current
selected application IDs, composed operations, and owner map. A one-application update
passes a singleton set; a batch passes every selected ID. It must ignore commands and
collapse directory operations into a separate set of required directories. For every
destination, retain all file-producing operations in original order.

Before materializing, inspect each destination's existing `FileRecord.applicationIds`. If
the destination is owned by both a selected and an unselected application, return
`SharedPathRequiresApplications path owners` listing every required ID and make no plan.
The caller can select the full owner set or use the no-argument all-applications update.
This preflight applies when the selected batch still generates the path. If the selected
batch no longer generates it, the orphan logic below may release only selected ownership
and safely leave the unselected owner's file in place.

Choose the initial generated ancestor as follows. If `FileRecord.baseline` exists, load it
from the baseline store. If a legacy record lacks a baseline and disk hash equals
`FileRecord.hash`, treat disk content as a trusted synthetic baseline and persist it during
apply. If the path is untracked, a complete Write/Copy begins from empty because it replaces
content; a patch-only sequence begins from the current disk content (or empty if absent) so
preexisting user text is retained as the first ancestor. If a tracked path has no valid
baseline and the disk hash differs, preserve the current content and emit
`MissingTrustedBaseline` rather than guessing.

Replay operations: WriteFile replaces the generated buffer, CopyFile reads and replaces it,
and PatchFile calls `applyTextPatch` on the generated buffer. A failed patch is a planning
error naming the path, patch operation, and module; do not fall back to last-writer-wins.
Produce exactly one `DesiredFile` for the final buffer.

Add `seihou-core/test/Seihou/Engine/ReconcileSpec.hs` with pure-filesystem fixtures for four
patches on one path, write-followed-by-patch, patch-only tracked/untracked paths, legacy
baseline adoption/refusal, structured output already collapsed by composition, and
application scoping.

### Milestone 2: classify files and resolve decisions

For each desired path, compare trusted baseline, disk, and newly generated content. Use
fast cases before the merge driver: disk equals baseline is a direct `FileUpdate`; new
generated equals baseline preserves disk as unchanged from the module's perspective; all
three equal is `FileUnchanged`. If both sides changed, call EP-65's `threeWayMerge`.
`MergeClean` becomes `FileAutoMerge` with the merged applied content;
`MergeConflicted` becomes `FileConflict` with markers and `OverlappingEdits`;
`MergeUnavailable` becomes `FileConflict` with `MergeDriverUnavailable` and preserves disk.

Classify manifest records owned by the current application but absent from desired output.
If another application ID also owns the record, emit `FileReleaseSharedOwnership` and keep
the disk file. If the disk file is absent, emit `FileAlreadyAbsent`. If this is the last
application owner and disk hash equals `FileRecord.hash`, emit `FileDeleteSafe`. Otherwise
emit `FileOrphanEdited`. Never use `FileRecord.baseline` alone to decide deletion because an
automatic merge makes applied content legitimately differ from the generated baseline.

Define explicit resolution types and pure functions:

```haskell
data FileConflictChoice
  = AcceptGenerated
  | KeepCurrent
  | WriteConflictMarkers
  | AbortUpdate

data OrphanChoice
  = DeleteEditedOrphan
  | RetainTrackedOrphan
  | DetachAndKeepOrphan
  | AbortUpdate

resolveFileConflict
  :: FilePath -> FileConflictChoice -> ReconciliationPlan
  -> Either ReconciliationError ReconciliationPlan

resolveEditedOrphan
  :: FilePath -> OrphanChoice -> ReconciliationPlan
  -> Either ReconciliationError ReconciliationPlan
```

Resolved actions must carry both the new generated baseline content and the applied disk
content. AcceptGenerated uses new content for both. KeepCurrent uses new content as baseline
and current content as applied. WriteConflictMarkers uses new content as baseline and the
marker body as applied. RetainTrackedOrphan leaves record/content/application ownership
unchanged so the same issue remains visible later. DetachAndKeep removes this application
ID and removes the file record if no owners remain, but does not delete disk. Delete removes
disk and the ownership/record. Abort marks the whole plan unapplyable.

Add summary helpers that count unique paths by create, update, merged, unchanged, conflict,
safe delete, edited orphan, and shared ownership. EP-69 will render these counts.

### Milestone 3: apply resolved plans and recover interruptions

Create `seihou-core/src/Seihou/Engine/UpdateTransaction.hs`. It owns journal creation,
managed path mutation, rollback, and recovery. Keep it independent of remote fetching and
manifest publication. The public surface is:

```haskell
beginUpdateTransaction
  :: FilePath -> Set FilePath -> IO (Either TransactionError UpdateTransaction)

applyReconciliation
  :: UpdateTransaction
  -> ReconciliationPlan
  -> Manifest
  -> IO (Either TransactionError Manifest)

rollbackUpdateTransaction :: UpdateTransaction -> IO (Either TransactionError ())
completeUpdateTransaction :: UpdateTransaction -> IO (Either TransactionError ())
recoverIncompleteTransactions :: FilePath -> IO [Either TransactionError ()]
```

`beginUpdateTransaction` creates a unique explicit directory beneath the project-local
`.seihou/transactions`, validates every path as project-relative using
`Seihou.Core.Path.validateProjectRelativePath`, and records whether each target existed plus
its prior text. Write journal metadata atomically before returning. Do not accept `.seihou`
manifest, baselines, transaction directories, `.git`, absolute paths, or traversal as
generated target paths.

`applyReconciliation` refuses any unresolved conflict. It creates required parent
directories, writes each file through a same-directory temp file plus rename, and deletes
approved orphans. For every retained/generated path, write the new generated content to the
baseline store, set `FileRecord.baseline` to that reference, set `hash` from the applied
content, update application ownership, and preserve the correct module owner/strategy.
For releases/deletes/detaches, update ownership and remove empty records as defined above.
Return the candidate manifest but do not write it; EP-68 owns the durable success boundary.

If any managed mutation fails, immediately attempt rollback and return both the original
error and any rollback error. `completeUpdateTransaction` removes the journal only after the
caller has published durable metadata. `recoverIncompleteTransactions` restores every
well-formed incomplete journal oldest-first and quarantines malformed journal metadata
instead of deleting it.

Tests must inject a failure after at least one successful write and prove the original tree
is restored. A separate real-filesystem test should simulate process interruption by leaving
a journal and mutated file, then call recovery and observe the old content.


## Concrete Steps

Run from the repository root:

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
cabal test seihou-core-test
cabal test all
nix fmt
git diff --check
```

The end-of-plan disposable fixture should start with a generated file, edit one line as the
user, change a different template line, and reconcile. It should also remove an unchanged
generated file and an edited generated file from the new plan. The observed summary should
have this shape:

```text
Files: 1 merged; 1 deleted; 1 edited orphan retained; 0 conflicts
```

Verify the merged file contains both changes, the unchanged orphan is gone, the edited
orphan remains in both the filesystem and manifest, and no transaction journal remains.

Every implementation commit must include:

```text
MasterPlan: docs/masterplans/8-make-module-updates-seamless-and-conflict-aware.md
ExecPlan: docs/plans/66-plan-conflict-aware-file-reconciliation-and-safe-orphan-handling.md
Intention: intention_01kxxjwvf8e2e8r64feyk6r65b
```


## Validation and Acceptance

Acceptance requires these behaviors:

- an arbitrary ordered sequence of writes and patches targeting one path produces exactly
  one desired and one reconciliation entry;
- a clean generated update writes new content without invoking conflict resolution;
- a user-only edit is preserved, a generated-only edit is applied, non-overlapping dual
  edits merge, and overlapping edits remain unresolved until an explicit choice;
- a corrupt/missing baseline or unavailable merge driver never overwrites current disk;
- a selected application cannot regenerate a path jointly owned by an unselected
  application; the error identifies the missing owners before mutation;
- legacy baseline adoption happens only when disk equals the recorded applied hash;
- an unchanged last-owner orphan is deleted; an edited orphan is retained/tracked; a shared
  file loses only the updated application owner;
- KeepCurrent advances the baseline but preserves current applied content/hash;
- no file action begins while any conflict is unresolved;
- injected mid-apply failure restores every earlier managed mutation;
- startup recovery restores a well-formed leftover journal and does not destroy a malformed
  one;
- all destination validation rules prevent writes outside the project and into Seihou/Git
  control paths;
- all repository tests pass.


## Idempotence and Recovery

Planning is read-only and repeatable. A resolved plan is valid only for the disk hashes it
observed; `applyReconciliation` must verify current hashes immediately before the first
mutation and return a stale-plan error if they changed. Re-plan rather than applying stale
decisions.

Each transaction journal is unique. Retrying after a handled failure first calls
`recoverIncompleteTransactions`, then recomputes the plan. Never blindly remove the
transactions directory. A successful caller writes its manifest, then calls
`completeUpdateTransaction`; if it crashes between those steps, EP-68 must use journal
metadata to distinguish committed versus uncommitted metadata and recover consistently.

Baseline blobs are immutable and safe to leave behind after rollback. EP-65/EP-68 pruning
removes unreferenced blobs only after the durable manifest is known. Manual tests must run
inside an explicit temporary project directory.


## Interfaces and Dependencies

Hard dependencies are EP-64 and EP-65. Use their checked-in `ApplicationId`, `BaselineRef`,
file fields, `BaselineStore`, `MergeOutcome`, and `threeWayMerge` exactly.

Use existing `Seihou.Engine.Section.applyTextPatch`, `Seihou.Core.Path` validation,
`Seihou.Manifest.Hash`, Filesystem effects, and standard `containers`, `text`, `time`,
`directory`, and `filepath`. Do not add a second patch or merge implementation.

EP-68 consumes the selected-application set on `ReconciliationPlan`, its resolution
functions, summary helper,
`beginUpdateTransaction`, `applyReconciliation`, rollback/recovery, and completion. EP-69
maps terminal choices to `FileConflictChoice` and `OrphanChoice`. Constructor names are part
of the coordination contract; if implementation needs a richer error payload, extend the
fields without collapsing the user-visible distinctions.
