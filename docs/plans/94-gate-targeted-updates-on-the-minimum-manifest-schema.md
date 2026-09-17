---
id: 94
slug: gate-targeted-updates-on-the-minimum-manifest-schema
title: "Gate targeted updates on the minimum manifest schema"
kind: exec-plan
created_at: 2026-09-17T14:17:05Z
intention: "intention_01m2qvd83ae0yt8e3h7ay430bg"
master_plan: "docs/masterplans/11-make-manifest-evolution-explicit-and-targeted-updates-upgrade-safe.md"
provenance:
  created_by:
    model: "gpt-5.6-sol"
    harness: "codex-cli"
    at: 2026-09-17T14:17:05Z
  revisions:
    - model: "gpt-5.6-sol"
      harness: "codex-cli"
      at: 2026-09-17T15:41:41Z
      mode: "update"
      note: "Linked ADR 0014 feature-minimum and lossless-upgrade requirements"
---

# Gate targeted updates on the minimum manifest schema

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

After this plan, `seihou update <target>` asks the manifest capability table which schema
it needs and repairs lossless schema/evidence gaps inside the update plan before enforcing
shared ownership. A schema-6 project whose co-owners all append safely to `.gitignore` can
update one requested module immediately: Seihou stages the co-owners only to certify the
path, upgrades the manifest to schema 7, and reconciles only the selected application's
files. The unrelated applications' files are not rewritten.

`--dry-run` shows the same intended schema/evidence change and writes nothing. A real apply
publishes the manifest change atomically with the selected update, so a failed update never
leaves a half-upgraded manifest. A path proven to contain a whole-file writer still fails
closed or expands only when the user explicitly passes `--include-shared-owners`. A schema
5-or-earlier manifest still stops with the explicit `seihou manifest upgrade` remedy,
because choosing an appropriate remote from machine-local paths is inference rather than a
lossless feature prerequisite.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] M1: Split target matching from evidence resolution and ownership-closure enforcement.
- [ ] M2: Stage the minimum schema/evidence upgrade inside update planning and publish it transactionally.
- [ ] M3: Prove dry-run, retry, rollback, unknown, additive, and genuinely non-additive behavior end to end.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Target matching happens before ownership closure, but no project mutation or
  candidate command execution happens before closure is satisfied.
  Rationale: Unknown evidence cannot be resolved until Seihou knows which paths and owners
  matter. Safety still requires closure before reconciliation or apply.
  Date: 2026-09-17

- Decision: A targeted update requires the `TargetedAdditiveSharedPathUpdate` capability,
  not a hard-coded schema number.
  Rationale: Future schema changes must be owned by the capability table rather than copied
  into each command.
  Date: 2026-09-17

- Decision: Lossless manifest preparation is part of `UpdatePlan` and the final update
  transaction, not a preflight write.
  Rationale: `--dry-run` must be read-only and an apply failure must roll the manifest back
  with the project files.
  Date: 2026-09-17

- Decision: An unresolved unknown mode produces a distinct evidence-unavailable error;
  `--include-shared-owners` is consulted only after a mode is known to require closure.
  Rationale: Expanding whole applications does not repair missing evidence and was the
  misleading workaround in BUG-1.
  Date: 2026-09-17


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

(To be filled during and after implementation.)


## Context and Orientation

This plan has hard dependencies on
`docs/plans/92-define-manifest-schema-capabilities-and-ordered-upgrade-steps.md` and
`docs/plans/93-upgrade-legacy-path-manifests-and-backfill-additive-facts.md`. EP-92 defines
schema 7 and `SharedWriteMode`; EP-93 supplies lossless upgrade planning and target-scoped
certification. Do not reproduce either API inside the update modules.

Run commands from
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`. The update service is a private CLI
library under `seihou-cli/src/Seihou/CLI/Update.hs` and its submodules. The executable
adapter under `seihou-cli/src-exe/Seihou/CLI/Update.hs` handles terminal interaction but
must remain thin.

The current planning order explains the bug. `planProjectUpdateIn` reads a typed manifest
and calls `selectAndSeedLegacy`. That calls `selectApplications` in
`seihou-cli/src/Seihou/CLI/Update/Selection.hs`. For a named selection,
`selectApplications` finds matching `AppliedComposition` values and immediately calls
`ensureOwnershipClosure`. Only after it succeeds does `planProjectUpdateIn` call
`stageCandidateSources`, compile applications, plan migrations, and reconcile files.
Because a schema-6 record without `additiveOnly` decodes conservatively, selection fails
before any operation exists that could establish the missing fact.

`ensureOwnershipClosure` currently has two Boolean outcomes. If `additiveOnly` is true, it
skips the path. If false, it either returns `SharedPathRequiresApplications` or
`expandToSharedOwners` adds every missing owner under `--include-shared-owners`. The latter
then updates each added application's complete file set, which is why one `.gitignore`
question can rewrite unrelated skill files. EP-92 changes the manifest to three modes;
this plan must give each a distinct transition.

`withProjectUpdate` owns the candidate-session lifetime. `UpdateSnapshot` in
`seihou-cli/src/Seihou/CLI/Update/Types.hs` records the original manifest and observed
project hashes. `applyProjectUpdate` revalidates that snapshot, runs migrations,
reconciles files through `Seihou.Engine.UpdateTransaction`, executes planned commands,
publishes candidates, and writes the final manifest. `buildFinalManifest` currently stamps
`currentManifestVersion`. After EP-92, the base passed to it must already contain explicit
mode evidence; this plan decides when unknown evidence is resolved and makes the prepared
manifest part of the snapshot and final build.

`isUpdateNoOp` in `Seihou.CLI.Update` and `planLooksUnchanged` in
`seihou-cli/src/Seihou/CLI/Update/Render.hs` already treat a changed `additiveOnly` value as
real work. Generalize that comparison to schema and `SharedWriteMode`: a manifest-only
upgrade is applied work, not “already up to date.” This follows
[ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md) and
[ADR 0007](../adr/0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md).

The ownership safety rule is
[ADR 0012](../adr/0012-an-additive-co-write-is-not-a-shared-path-conflict.md). Its two
layers remain: the preflight uses durable manifest evidence; reconciliation validates the
selected candidate's actual operations. [ADR 0005](../adr/0005-legacy-manifests-convert-through-an-explicit-command.md)
means schema 5 and earlier cannot be silently converted as part of update. The manifest is
the single applied-state record under
[ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md), so no sidecar
or cache may remember certification.
[ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md)
requires this feature to use the central minimum-version mapping and permits only
deterministic, lossless steps inside the update transaction. No cross-repository ADR
applies.


## Plan of Work

Milestone 1 separates matching from closure. Refactor
`seihou-cli/src/Seihou/CLI/Update/Selection.hs` so a pure `matchApplications` phase returns
the named ids in manifest order without expanding or enforcing shared ownership. Retain the
legacy no-application fallback as a separate result. Build renderer-neutral
`ApplicationRef` values from each matched or missing owner: stable `ApplicationId`, root
target, and the root instance's parent variables are enough for EP-95 to produce labels.

Add a second pure phase that examines the paths intersecting the matched ids. Certified
additive-only paths pass. Closure-required paths either return
`SharedPathRequiresApplications` with `ApplicationRef` sets or expand under
`--include-shared-owners`. Unknown paths return a request for certification, not a closure
error. Iterate after certification because resolving one path or expanding one owner can
expose another shared path. Unit tests must retain the current fixed-point behavior and
prove the new unknown branch.

Milestone 2 integrates minimum-schema preparation into
`Seihou.CLI.Update.planProjectUpdateIn`. Inspect the raw top-level version before treating a
decode failure as a generic unreadable manifest. Schema 5 and earlier return an explicit
upgrade-required error naming `seihou manifest upgrade`; a future schema still returns the
newer-version refusal. For schema 6, ask the EP-92 capability mapping for the targeted
feature's minimum and apply EP-93's lossless steps in memory. Match targets, stage their
candidate applications, ask EP-93 to certify only intersecting unknown paths using those
candidates plus recorded co-owner evidence, then rerun closure enforcement.

Share a `CandidateCatalog` or operation-evidence cache across certification and ordinary
planning so the selected target is not cloned or compiled twice. Evidence gathering may
load every owner of the relevant path, but its operations are filtered to certification;
only the originally matched ids enter migration, file reconciliation, command planning,
cache publication, and `updatedApplications`. If evidence remains unknown, return the
evidence-unavailable error with the path and unresolved owners. Do not suggest
`--include-shared-owners` for this case.

Extend `UpdatePlan` with a `ManifestPreparation` value containing the source and target
schema, changed path modes, and the prepared manifest. `UpdateSnapshot.originalManifest`
remains the on-disk pre-plan value for stale-plan and rollback checks; the reconciliation
and final-manifest builders use the prepared value. A dry run renders the preparation but
does not write it. A real apply includes `.seihou/manifest.json` in the existing observed
and journaled target set and publishes schema/evidence changes with the target update.
Generalize `isUpdateNoOp` and `planLooksUnchanged` so preparation alone prevents a no-op.

Milestone 3 locks the boundary with unit, transaction, and binary tests. Extend
`seihou-cli/test/Seihou/CLI/UpdateSpec.hs` for two-phase selection and no-op classification,
`seihou-cli/test/Seihou/CLI/UpdateE2ESpec.hs` for the reported behavior, and
`seihou-core/test/Seihou/Engine/UpdateTransactionSpec.hs` if journal behavior needs a
fixture. The successful schema-6 case must prove unrelated application files are
byte-identical. Add failure injection after a managed file mutation and prove both files
and manifest return to their original bytes. Keep a known whole-file co-owner case that
still refuses, then prove `--include-shared-owners` is considered only for that known mode.


## Concrete Steps

Map the current call order and tests before editing:

```bash
rg -n 'selectAndSeedLegacy|selectApplications|ensureOwnershipClosure|stageCandidateSources|isUpdateNoOp|buildFinalManifest' \
  seihou-cli/src seihou-cli/test
```

After Milestone 1, run the CLI test suite:

```bash
cabal test seihou-cli-test
```

The focused regression fixture starts with schema 6 and no `additiveOnly` key on a
`.gitignore` owned by one template target and two `append-line-if-absent` applications.
Its binary dry run is:

```bash
cabal run seihou -- update nix-haskell-flake --dry-run --json
```

The JSON remains an update plan, reports a manifest preparation from 6 to 7 and a
`.gitignore` certification, and does not contain
`shared_path_requires_applications`. Hash every unrelated skill file before and after the
real update in the test, then run:

```bash
cabal run seihou -- update nix-haskell-flake --json
```

Expected high-level behavior is:

```text
outcome: applied
manifest schema: 6 -> 7
.gitignore evidence: unknown -> additive-only
updated applications: nix-haskell-flake only
```

At completion run:

```bash
cabal build all
cabal test all
nix fmt -- --fail-on-change
nix flake check
```


## Validation and Acceptance

The primary acceptance test reproduces BUG-1. On a schema-6 manifest with an unknown
co-owned `.gitignore`, `seihou update nix-haskell-flake` succeeds when certification finds
every owner additive. The final manifest is schema 7 and records additive-only evidence.
Only the requested application's version, application state, files, and command receipts
may change. The exec-plan and master-plan skill files named in the bug report remain
byte-identical, and their application ids remain owners of `.gitignore`.

The same invocation with `--dry-run` leaves the manifest and all project files byte-for-byte
unchanged while returning a plan that is not marked already up to date. A forced failure
during apply restores the schema-6 manifest and target file. Retrying succeeds, and a third
run reports an ordinary no-op without attempting certification again.

A schema-7 unknown path whose co-owner artifact is unavailable fails with the distinct
evidence-unavailable code and names the path and owner. It does not expand under
`--include-shared-owners`. Installing the exact artifact and retrying can resolve it. A
schema-7 closure-required path retains the existing refusal; passing
`--include-shared-owners` expands to the required applications with fixed-point semantics.

A selected candidate that changed from an additive patch to a whole-file write is refused
by reconciliation even if prior manifest evidence was additive. This preserves ADR 0012's
defence in depth. A schema-5 fixture fails before source staging with the explicit manifest
upgrade remedy, while schema 6 takes the lossless in-plan path. All tests and Nix checks pass.


## Idempotence and Recovery

Planning is read-only. Candidate sources and certification artifacts live under the
existing temporary update session and are removed when `withProjectUpdate` returns. A dry
run never writes the prepared manifest.

Apply uses the existing update journal and stale-plan checks. Include the on-disk manifest
hash observed before preparation; if another process edits it before confirmation, return
`UpdatePlanStale` rather than overwriting the edit. Write the final manifest only after
managed file and command phases have succeeded according to the existing transaction
contract. Failure injection tests must prove rollback to the original schema and bytes.

Certification is monotonic only from unknown to a known value. Re-running it against an
already known path does nothing unless the normal selected candidate validation discovers
a non-additive operation, in which case the update fails rather than silently weakening a
certificate outside a successful transaction.


## Interfaces and Dependencies

`seihou-cli/src/Seihou/CLI/Update/Selection.hs` must expose phases equivalent to:

```haskell
data ApplicationRef = ApplicationRef
  { applicationId :: !ApplicationId
  , target :: !AppliedTarget
  , parentVars :: !ParentVars
  }

matchApplications ::
  UpdateSelection -> Manifest -> Either UpdateError MatchedApplications

enforceOwnershipClosure ::
  SelectionPolicy -> Manifest -> MatchedApplications -> Either ClosureRequirement SelectedApplications
```

The concrete names may vary, but matching must not enforce closure and unknown evidence
must be representable as a request rather than collapsed into `UpdateError` immediately.

`seihou-cli/src/Seihou/CLI/Update/Types.hs` must carry preparation explicitly:

```haskell
data ManifestPreparation = ManifestPreparation
  { fromVersion :: !ManifestSchemaVersion
  , toVersion :: !ManifestSchemaVersion
  , modeChanges :: !(Map FilePath (SharedWriteMode, SharedWriteMode))
  , preparedManifest :: !Manifest
  }
```

Add `manifestPreparation :: !(Maybe ManifestPreparation)` to `UpdatePlan`. Add distinct
error constructors for an inference-bearing explicit upgrade requirement and unresolved
shared-write evidence. Retain `SharedPathRequiresApplications` for a known closure
requirement, but replace bare id sets with renderer-neutral `ApplicationRef` values.

Consume `minimumManifestVersion`, `manifestSupports`, the EP-93 ordered-upgrade service,
and `certifySharedWriteModes`. Do not add dependencies beyond the existing CLI/core package
relationship. Do not move behavior into the executable adapter.


## Revision Notes

- 2026-09-17: Linked accepted ADR 0014 as the authority for the feature minimum and the
  restriction that only deterministic, lossless upgrades may be staged transactionally.
