---
id: 101
slug: create-seed-files-once-during-seihou-run
title: "Create seed files once during seihou run"
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
      note: "Specify named composition API, exclusive creation, exact claims and safe transition refusal"
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-27T02:25:43Z
      mode: "implement"
      note: "Implement seed operations, shared planning, exclusive creation and run integration"
  reviews:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-27T00:43:50Z
      verdict: "approved"
      note: "Reviewed revised plan against current source and cross-plan contracts; approval is for implementation design, not runtime delivery"
---

# Create seed files once during seihou run

This ExecPlan is a living document. Maintain Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective as work proceeds.

This is EP-3 of [MasterPlan 12](../masterplans/12-seed-files-module-outputs-created-once-and-owned-by-the-project.md).
Hard prerequisites are [plan 99](99-declare-seed-steps-in-the-module-schema-and-validate-them.md)
and [plan 100](100-record-seed-receipts-in-manifest-schema-8.md), including its ownership correction
in Milestone 4. EP-5 consumes the APIs defined here. Runtime seed support is not released until
[plan 103](103-reconcile-seed-steps-during-seihou-update-and-release-managed-files-to-seeds.md)
and [plan 102](102-keep-seed-files-out-of-status-diff-and-remove.md) pass together.

## Purpose / Big Picture

A seed is a starting file that belongs to the project after its first settlement. A module
marks a whole-file step `lifecycle = Some "seed"`; no user flag is required. In an empty
project, `seihou run haskell-cli-app` creates its seeds. An existing regular file is kept.
Editing a seed and repeating the command, including with `--force`, preserves its bytes.
Deleting it and repeating the command preserves its absence while its receipt exists.
`seihou agent run` must use exactly the same behavior for blueprint baseline modules.

Preview says `seed: create` or `seed: keep existing`. Settled paths are omitted from the
ordinary work list; a bounded summary may explain that they are project-owned. Dry-run writes
nothing, including receipts, parent directories, baselines, and caches governed by the existing
command dry-run contract. A receipt is settlement history, not evidence that a file still exists.

## Progress

- [x] (2026-10-27) Milestone 1: compile and compose seed operations with named results and lifecycle collision checks; interim update refuses unsupported seed transitions before mutation.
- [x] (2026-10-27) Milestone 2: common classification and exclusive creation preserve existing objects and deliberate deletion in native and pure filesystem checks.
- [x] (2026-10-27) Milestone 3: run and agent run share receipt handling, previews, and real-binary acceptance; ordinary managed behavior remains intact.

## Surprises & Discoveries

Early ordinary-path evidence (2026-10-27): built 0.10.1.0 executable ran a
project-local seed module without special preparation after fixture creation.
It created the starting file, preserved an edit on forced rerun, then respected
deletion without recreating the now-absent parent directory. Receipts contained
exact claims and no managed record. Native macOS tests also passed complete-byte
publication, occupied regular files/directories/dangling links, partial-write
cleanup, and eighty concurrent creator attempts. Linux native verification also passed against the identical standalone helper in
`haskell:9.12.4-slim-bookworm`, digest
`sha256:49aed9a48b0eb4a00dce6bc5e2ad33766f2371f570a019b47ba48f5070c1be15`.

The `unix` dependency was absent from the Mori corpus (registry search returned
no matching package). Hackage and upstream tag `v2.8.8.0` agree on the current
release; source verifies `System.Posix.Files.createLink` calls native `link`.
The bound remains `>=2.8 && <2.9`, compatible with the pinned compiler's boot library.

Review (2026-10-26): `StepLifecycle` already includes `Checkout`; `Operation` includes
`CheckoutOutputOp`; `PathEntry` and `inspectPath` already exist. The manifest is currently
schema 10, while `SeedReceipts` still means schema 8. `checkSeedSteps` lives in
`Seihou.Core.Module` and is already called by `compilePlan`. The original check-then-write
proposal cannot enforce create-only semantics, and a `Set ModuleName` cannot identify the
first module in execution order.

## Decision Log

Decision (2026-10-26): replace the proposed `seedAsManagedWrite` adapter with an explicit
unsupported-transition error until EP-5 lands. Converting a seed to a managed write can
claim or overwrite project-owned bytes. Before EP-5, update must refuse if selected candidate
operations contain seeds or selected applications own seed receipts; certification treats
seeds as non-managed evidence. It must not silently omit seeds and orphan their prior files.

Decision (2026-10-26): preserve first-writer content selection within a composition, but
carry the supplier explicitly and record every qualified module-instance claim. Use one named
composition result instead of extending the existing positional tuple. Do not create a generic
resource framework for three lifecycles.

Decision (2026-10-26): `run` refuses any managed/seed lifecycle transition before execution
and points to ordinary `seihou update <recorded target>`. It must not publish the candidate
module version while retaining the old managed record: doing so could make update miss the
release. Reapplication is for the recorded lifecycle; update owns evolution.

## Outcomes & Retrospective

All three milestones are accepted in source. The pinned GHC 9.12.4 shell passed
`cabal test all`; focused seed tests and `nix flake check` also passed. Real-binary
coverage includes ordinary creation, pre-existing files without force, forced edits,
deletion without parent resurrection, immutable previews, both lifecycle refusals,
two parameterized instances plus their root in one application, a second application,
false-condition retirement/reintroduction, and agent blueprint baselines. Native
macOS/Linux checks cover occupied entry kinds, partial-write cleanup and concurrent
creators. No additional friction entries were recorded under this child.

The common publication helper is independent of the effect stack so precisely the
same implementation runs in both native environments. Portable case aliases are
refused before mutation; actual native spelling/ancestor checks complement that
logical check. ADR 0017 records these durable boundaries. Update deliberately
refuses seed candidates/selected owners until plan 103 integrates reconciliation;
this checkpoint is not a runtime-ready seed release.

## Context and Orientation

Read `CLAUDE.md`: strict record fields, `generic-lens` labels, explicit imports, and CLI
library placement apply. `seihou-core/src/Seihou/Engine/Plan.hs` compiles one module;
`seihou-core/src/Seihou/Composition/Plan.hs` composes qualified `ModuleInstance`s and currently
returns operations, warnings, and managed owners as a tuple. The module instance's
`qualifiedName` is the owner identity, not just its bare module name.

`seihou-cli/src-exe/Seihou/CLI/Run.hs` and `AgentRun.hs` compile, diff, preview, execute,
record baselines, attach an `ApplicationId`, and publish a manifest. Seed handling must be
shared in `seihou-core/src/Seihou/Engine/Seed.hs` and a small CLI adapter if needed.
`Seihou.Engine.Diff` and `Seihou.Engine.Execute` currently assume managed byte writes;
keep seed operations out of those writes, conflict resolution, baseline generation, and
orphan cleanup. The update consumers are `seihou-cli/src/Seihou/CLI/Update.hs` and
`ManifestCapabilityUpgrade.hs`; every caller of `compileComposedPlan` must migrate together.

[ADR 0017](../adr/0017-a-seed-file-is-created-once-and-belongs-to-the-project.md) defines settlement
and precise ownership; [ADR 0018](../adr/0018-checkout-outputs-are-observable-portable-declarations.md)
defines existing checkout collision and filesystem rules. [ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md)
requires capability-based version staging. Plan 100's Milestone 4 provides exact owner maps
and explicit legacy ownership, preserving schema-8 receipt decoding.

## Plan of Work

### Milestone 1 — distinguish operations and owners

Add `SeedFileOp { dest :: !FilePath, content :: !Text, strategy :: !Strategy,
moduleName :: !ModuleName }` to `Operation` in `Seihou.Core.Types`. After condition evaluation,
compile supported copy/template/dhall-text whole writes into this constructor. Do not retain
unconditional seed-only `CreateDirOp`s: only actual seed creation needs its parents. Preserve
checkout dispatch. Extend `Core.Module.checkSeedSteps` and runtime validation to reject every
unsupported strategy, patch, and declarative removal action targeting a seed, including
remove-section and rewrite-file. Literal declaration validation cannot detect variable aliases;
validate resolved active destinations before any writes.

Introduce in `Seihou.Composition.Plan`:

```haskell
data ComposedPlan = ComposedPlan
  { operations :: ![Operation],
    warnings :: ![CompositionWarning],
    managedOwners :: !(Map FilePath ModuleName),
    seedOwners :: !(Map FilePath (Set ModuleName))
  }
  deriving stock (Eq, Show, Generic)
```

`compileComposedPlan` returns `IO (Either [Text] ComposedPlan)`;
`mergeOperations` returns `Either [Text] ComposedPlan`. Keep the first seed operation for a
path (its `moduleName` is the content supplier), union all qualified claims into `seedOwners`,
and give conflicting proposed seed contents a bounded explanatory warning. Across applications,
EP-5 uses recorded manifest application order, never map/set sort order, to select the supplier.

Refuse a seed combined with a managed write, copy, patch, or checkout destination, in either
order, including file/descendant collisions. Use canonical project-relative paths and existing
checkout overlap rules; do not confuse a required parent-directory operation with a file claim.
Check candidate claims against retained manifest managed, seed, and checkout claims too.
A managed candidate overlapping any existing seed receipt is a transition and cannot bypass
protection through `--force`. Reject unsafe ancestors and conflicting path aliases consistently.

Audit all operation consumers with `rg 'WriteFileOp|PatchFileOp|CopyFileOp|CheckoutOutputOp'
seihou-core/src seihou-cli/src seihou-cli/src-exe`. Use explicit cases at semantic dispatch
points. Add the interim refusal to update before staging/migration execution and exclude seeds
from managed certification. Test that managed-only updates still work and seed transitions
cannot orphan, claim, or overwrite a file. Update all composition callers and tests together.

### Milestone 2 — share classification and checked creation

Use `PathEntry` from `Seihou.Effect.Filesystem`, not a Boolean from `doesFileExist` (which
misses dangling links and directories). Define in `Seihou.Engine.Seed`:

```haskell
data SeedDecision
  = SeedWrite | SeedKeepExisting | SeedRespectDeletion | SeedAlreadySettled
  | SeedReleaseManaged
  deriving stock (Eq, Show, Generic)

classifySeed :: Maybe SeedRecord -> Maybe FileRecord -> PathEntry
             -> Either SeedError SeedDecision
```

Validate incompatible claims separately before classification. With a managed record, classify
as release without reading content, even when missing; `run` refuses it, update releases it.
With a receipt, classify missing as respect-deletion and any occupied final entry as already-settled,
without reading or following it. Without either, a missing entry is write, a regular file is
keep-existing, and a directory or symlink is a named refusal. No refusal authorizes replacement.
Validate ancestors before inspection or creation; never traverse symlink ancestors.

`PlannedSeed` carries canonical path, content, strategy, explicit supplier, qualified owner
set, observed `PathEntry`, and decision. `planSeeds` accepts an explicit project root, manifest,
seed owner map, and operations and returns `Either [SeedError] [PlannedSeed]` in `Filesystem`.
Do not assume the caller changed working directory. Pure receipt planning and IO outcomes are
separate: preview never manufactures a successful creation receipt.

Add an exclusive create primitive to `Seihou.Effect.Filesystem`, its IO interpreter, and
`FilesystemPure`. Its result distinguishes created, already occupied, and IO failure; it must
not replace an existing entry or expose a partial destination after a failed content write.
Prepare complete content before no-replace publication and clean up private temporary state. A second `exists` check followed by `writeFileText` or an
ordinary replacing rename is insufficient. Choose the native implementation after Mori source
lookup of the existing filesystem dependencies, and prove its no-replace behavior on macOS
and Linux. Recheck ancestors; this is not a hostile-filesystem sandbox guarantee.

`executeSeeds` accepts project root, application ID, settlement time, planned seeds, and
manifest; returns a typed success or error with actual outcomes. It calls the exclusive primitive
only for `SeedWrite`, records a concurrently appearing regular file as found-existing, and
refuses an appearing link/directory without touching it. Settle receipts through plan 100's
helpers with exact application/instance claims, preserving first supplier/outcome/time. Never
create a `FileRecord` or baseline. A failed write publishes no receipt. A partial run can leave
a newly created file; retry keeps it and records found-existing.

Acceptance uses unit tests for every decision and owner merge, plus native tests for appearing
files, dangling links, directories, unsafe parents, failed content writes, and exclusive creation. Test that settled
seeds need no content read and that deleted nested seeds do not recreate parent directories.

### Milestone 3 — ordinary commands

In run and agent run, plan all lifecycle refusals before execution. Partition operations once;
feed only managed operations to diff/execution/baselines. Receipt transitions must not be
orphans. Apply seed results using the real application ID and reconcile that application's entire candidate
claim set through `replaceSelectedSeedClaims`, including false-condition/removed-step retirement.
Preserve unselected claims and original settlement metadata in one pass, rather than merging
owners forever or deleting and recreating surviving receipts. Attach the final application/instance
records before validating references, then publish one invariant-checked manifest at the current schema. Retain checkout outputs and command declarations. Rendering
uses the same decisions as execution; `--diff` shows new seed content only for planned creation.

Add `seihou-cli/test/Seihou/CLI/SeedRunE2ESpec.hs` and register it in the cabal suite and
`test/Main.hs`. Using the built binary and a local module, verify first creation, pre-existing
file without force, edited rerun with force, intentional deletion, and dry-run immutability.
Also cover two instances in one application sharing a path, two applications, agent baseline
application, managed-to-seed refusal without metadata advancement, seed-to-managed refusal,
checkout collisions, false conditions, and failure before manifest publication followed by retry.
Use existing `PlanSpec`, composition tests, and `FilesystemPure` for focused contracts.

Document previews and transition recovery in `docs/cli/run.md`; update root `CHANGELOG.md`
and ADR 0017 with implementation evidence. No runtime-ready release claim before EP-4/EP-5.

## Concrete Steps

From the repository root, in its Nix development shell:

```bash
cabal build all
cabal test seihou-core-test --test-options='-p Seed'
cabal test seihou-cli-test --test-options='-p SeedRun'
cabal test all
nix flake check
```

Resolve the test executable with `cabal list-bin exe:seihou` from this checkout and use its
absolute path in temporary projects; do not use unsupported `cabal --project-dir` examples.
Record its version and source revision. Tests use disposable fixtures; the first real
producer/consumer migration is scheduled in EP-5 Milestone 2.

## Validation and Acceptance

The normal command creates once, preserves edits and deletions, and explains occupied-object
or lifecycle refusals before any mutation. Seed receipts contain every exact claim; no seed is
in managed hashing or baselines. Existing checkout tests and managed behavior remain green.

## Idempotence and Recovery

Settlement is idempotent while a receipt remains. Removal of the last claim or retirement of
the last seed step forgets settlement; a later application may create an absent path again.
After a run failure without a receipt, retry preserves any surviving file. Exclusive creation
closes the final-entry overwrite race; arbitrary shell commands remain outside this guarantee.

## Interfaces and Dependencies

EP-3 owns `ComposedPlan`, `SeedFileOp`, `SeedDecision`, `SeedError`, `PlannedSeed`, common
classification/execution, and exclusive creation. EP-5 consumes these and removes only the
interim refusal; EP-4 consumes plan 100's receipt model. No new dependency is chosen by this plan.

Revision note (2026-10-26): replace unsafe fallback and check-then-write APIs; carry explicit
supplier/instance claims; preserve checkout behavior and route lifecycle evolution to update.
