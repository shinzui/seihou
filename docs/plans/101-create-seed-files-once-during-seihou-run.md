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
---

# Create seed files once during seihou run

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.

This plan is EP-3 of the MasterPlan
`docs/masterplans/12-seed-files-module-outputs-created-once-and-owned-by-the-project.md`.
Hard dependencies: `docs/plans/99-declare-seed-steps-in-the-module-schema-and-validate-them.md`
(EP-1, provides `Step.lifecycle`) and `docs/plans/100-record-seed-receipts-in-manifest-schema-8.md`
(EP-2, provides `SeedRecord` and `Manifest.seeds`). Both must be Complete before starting.


## Purpose / Big Picture

A *seed file* is a file a module creates once, when the path is absent, and then hands to
the project: Seihou never overwrites, content-tracks, merges into, reports, or deletes it.
Module authors declare one with `lifecycle = Some "seed"` on a step in `module.dhall`
(EP-1), and the manifest can record a *seed receipt* for it in its `seeds` map (EP-2). This
plan makes `seihou run` — the command that applies modules to a project — act on that
declaration.

After this plan, running a module whose `CHANGELOG.md` step is a seed:

- creates `CHANGELOG.md` when it does not exist and records a receipt with outcome `created`;
- when `CHANGELOG.md` already exists and Seihou has no record of it, leaves it untouched,
  does **not** report a conflict (today it does, and `--force` would overwrite it), and records
  a receipt with outcome `found-existing`;
- on every later run, leaves the file alone whether or not it was edited, and does not
  re-create it if the developer deleted it;
- never puts the file into the manifest's `files` map, so it has no hash and no baseline.

The plan view (`seihou run --dry-run`) shows each seed path with a distinct tag, for example
`seed` for a file that will be created and `seed: kept` for one left alone.


## Progress

- [ ] Milestone 1: `SeedFileOp` in `Seihou.Core.Types`; `compileStep` emits it for seed
      steps; `mergeOperations` merges seeds and refuses seed/managed mixes; all `Operation`
      matches reviewed.
- [ ] Milestone 1: interim guard so `seihou update` and shared-write certification treat a
      `SeedFileOp` as a managed write until EP-5 lands.
- [ ] Milestone 2: `Seihou.Engine.Seed` with `SeedDecision`, `classifySeed`, `planSeeds`,
      and `executeSeeds`; unit tests against the pure filesystem.
- [ ] Milestone 3: wire seeds into `seihou run` and `seihou agent run` (diff input, plan view,
      execution, manifest receipts, schema 8); preview tags.
- [ ] Milestone 3: end-to-end test with the real binary; `docs/cli/run.md`; ADR 0017
      amendment; root `CHANGELOG.md`.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Represent a compiled seed step as a new `Operation` constructor `SeedFileOp`
  rather than a flag on `WriteFileOp`.
  Rationale: Many functions pattern-match `WriteFileOp` to mean "a managed whole-file write"
  (diff input, conflict exclusion, execution, update grouping, certification). A new
  constructor makes each of them either handle seeds explicitly or ignore them; a flag would
  silently be treated as managed everywhere it was forgotten.
  Date: 2026-09-19

- Decision: A composition in which one module seeds a path and another module writes or
  patches the same path is a compile error, reported before anything is written.
  Rationale: The MasterPlan's invariant is that a path is tracked or seeded, never both.
  No real module needs the mix, and refusing is explicit.
  Date: 2026-09-19

- Decision: When two modules in one composition seed the same path, the first in execution
  order supplies the content and both are recorded as owners of the receipt.
  Rationale: Seeds never overwrite, so "first writer wins" is the only consistent rule, and
  recording both owners lets `seihou remove` of either module leave the receipt in place for
  the other.
  Date: 2026-09-19

- Decision: A path already recorded as a managed file (in `files`) whose step is now a seed
  is *not* released by `seihou run`; run keeps it managed and prints a note directing the user
  to `seihou update`.
  Rationale: Releasing a managed file is an evolution of applied state that belongs to
  `seihou update` (EP-5), which has the transaction, baseline pruning, and ownership closure
  machinery. `seihou run` re-applying an already-applied module is the less common path.
  Date: 2026-09-19

- Decision: Until EP-5 is complete, `seihou update` and shared-write certification convert a
  `SeedFileOp` back to the equivalent `WriteFileOp`.
  Rationale: Without this, those code paths' wildcard matches would drop seed operations,
  and `seihou update` would classify the file as an orphan of the module and could delete it.
  Treating seeds as managed there is exactly today's behavior and is safe.
  Date: 2026-09-19


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

The repository is a Haskell (GHC 9.12) Cabal workspace: `seihou-core/` is the domain
library; `seihou-cli/src/` is the `seihou-cli-internal` library and `seihou-cli/src-exe/` the
`seihou` executable. Read the repository `CLAUDE.md`: records have strict fields, fields are
accessed only through `generic-lens` labels (`op ^. #dest`, `m & #seeds . at p ?~ r`), there
is no record dot or record update syntax, and each module using labels imports
`Data.Generics.Labels ()`. New CLI code goes in `seihou-cli/src/` unless it needs
`Options.Applicative` (see `CLAUDE.md`, "CLI Module Placement"); `Run.hs` and `AgentRun.hs`
are already in `src-exe/`.

Terms. A *module* is a directory with `module.dhall`; its *steps* each produce one file. A
*composition* is the set of modules one `seihou run` applies together (a module plus its
dependencies, or a recipe). An *application* is the manifest's record of one such run,
identified by an `ApplicationId`. The *manifest* is `.seihou/manifest.json`. A *managed* file
has a `FileRecord` in `Manifest.files` (content hash, owning module, strategy, baseline,
applications). A *seed* is described above.

What EP-1 and EP-2 provide (verify these exist before starting):

- `Seihou.Core.Types.StepLifecycle = Managed | Seed` and the field
  `Step.lifecycle :: StepLifecycle` (EP-1).
- `Seihou.Core.Types.SeedOutcome = SeedCreated | SeedFoundExisting | SeedReleasedFromManaged`,
  `SeedRecord { moduleName, applicationIds, outcome, settledAt }`,
  `Manifest.seeds :: Map FilePath SeedRecord`, and `ManifestCapability`'s `SeedReceipts`
  (EP-2).
- `Seihou.Core.Seed.mergeSeedRecord :: FilePath -> SeedRecord -> Manifest -> Manifest`
  (adds an application to a receipt, keeping the first outcome and time) and
  `validateManifestInvariants :: Manifest -> Either ManifestInvariantError ()` (a path in
  both `files` and `seeds` is an error) (EP-2).
- `Seihou.Manifest.Types.currentManifestVersion == ManifestSchemaVersion 8`; the encoder only
  writes `seeds` at version 8 or later (EP-2).

How `seihou run` works today (file `seihou-cli/src-exe/Seihou/CLI/Run.hs`, `handleRun`):

1. It loads the composition and resolves variables, then calls
   `Seihou.Composition.Plan.compileComposedPlan` (`seihou-core/src/Seihou/Composition/Plan.hs`,
   around line 36). That calls `Seihou.Engine.Plan.compilePlan` per module instance, whose
   `compileStep` (`seihou-core/src/Seihou/Engine/Plan.hs`, around line 98) evaluates the
   step's `when` condition and dispatches on strategy: `compileCopyStep`,
   `compileTemplateStep`, and `compileDhallTextStep` all produce `WriteFileOp dest content strategy`
   (plus `CreateDirOp`s for parent directories), `compileStructuredStep` too, and a step with
   a patch goes to `compilePatchStep`, producing `PatchFileOp`. `Operation` is defined in
   `seihou-core/src/Seihou/Core/Types.hs` (around line 427) with constructors `WriteFileOp`,
   `CreateDirOp`, `CopyFileOp`, `RunCommandOp`, `PatchFileOp`.
2. `mergeOperations` (`Composition/Plan.hs`, around line 75) merges the modules' operations:
   for two whole-file writes to one path the later module wins and a `FileOverwritten`
   warning is recorded; a patch is applied on top of an earlier write. It returns the merged
   operations, warnings, and an owner map `Map FilePath ModuleName`.
3. `Run.hs` (around line 259) builds the diff input `planned` from `WriteFileOp` and
   `PatchFileOp` only, reads the manifest, and calls `Seihou.Engine.Diff.computeDiff`
   (`seihou-core/src/Seihou/Engine/Diff.hs`, around line 35). `classifyFile` compares
   manifest, plan, and disk: a path in the plan but neither in the manifest nor on disk is
   *New*; in the plan and on disk but not in the manifest is a *Conflict* (for non-patch
   operations) — this is the behavior seeds must not have; manifest-and-plan is Modified,
   Unchanged, or Conflict depending on hashes; manifest-only is *Orphaned* (the manifest
   entry is dropped; the file is not deleted by `run`).
4. The plan view is `Seihou.Engine.Preview.buildPreview` (`seihou-core/src/Seihou/Engine/Preview.hs`,
   around line 44) rendered by `formatPlanViewColor` (`seihou-cli/src/Seihou/CLI/Style.hs`);
   `statusTag` (Preview.hs around line 145) turns a `FileStatus` into the bracketed tag.
   `--dry-run` prints it and stops; `--diff` prints `formatDiff`.
5. Conflicts are resolved by `Seihou.Engine.Conflict.resolveConflicts` (with `--force`,
   interactively, or by failing). Then `Seihou.Engine.Execute.executePlan`
   (`seihou-core/src/Seihou/Engine/Execute.hs`, around line 31) writes files and returns a
   `FileRecord` per written path; `Seihou.Engine.Baseline.recordGeneratedBaselines` stores
   baselines; and `Run.hs` (around lines 422–476) builds the new `Manifest` (dropping orphans,
   merging records, attaching the application with `attachApplication`, setting
   `version = currentManifestVersion`) and writes it.

`seihou agent run` (`seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`) applies a blueprint's
baseline modules with a copy of the same pipeline (its own `planned` list around line 421,
`computeDiff` around 437, `executePlan` around 482, and an `opTargetsPath` around 568). It
must get the same seed handling.

Other code that pattern-matches `Operation` and will see the new constructor:
`Seihou.Engine.Execute.operationDestination` and `executeOp`,
`Seihou.Engine.Reconcile.operationDestination` (around line 342; wildcard returns `Nothing`)
and `applyGenerationOperation`, `Seihou.Engine.Preview.opToPreview`,
`seihou-cli/src/Seihou/CLI/Update.hs` (a local `operationDestination` around line 777, and
`compileComposedPlan` around line 531), `seihou-cli/src/Seihou/CLI/ManifestCapabilityUpgrade.hs`
(a local `operationDestination` around line 229; `compileComposedPlan` around line 298), and
`isAdditiveOperation` in `Types.hs`. Find all with:

```bash
grep -rn 'WriteFileOp\|PatchFileOp\|CopyFileOp' seihou-core/src seihou-cli/src seihou-cli/src-exe
```

Tests: `seihou-core/test/Seihou/Engine/PlanSpec.hs`, `DiffSpec.hs`, `ExecuteSpec.hs`
(in-memory filesystem via `Seihou.Effect.FilesystemPure`, `runFilesystemPure`),
`seihou-core/test/Seihou/Composition/*Spec.hs` (merge rules), and the end-to-end suites in
`seihou-cli/test/Seihou/CLI/*E2ESpec.hs`, which run the real binary located by
`SeihouBinary.seihouBinary`; `SharedManifestE2ESpec.hs` shows how to run `seihou run` in a
temporary project against a fixture module. Register new specs in the relevant cabal
`other-modules` and in `test/Main.hs`.

Relevant ADRs: [ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md)
(receipts belong in the manifest), [ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md)
(a command that writes a schema-8 fact must write a schema-8 document; `seihou run` already
stamps `currentManifestVersion`), [ADR 0012](../adr/0012-an-additive-co-write-is-not-a-shared-path-conflict.md)
(shared-write evidence concerns managed paths only; a seed path must never get a `FileRecord`),
and ADR 0017 (`docs/adr/0017-a-seed-file-is-created-once-and-belongs-to-the-project.md`,
written by EP-1), which this plan amends.


## Plan of Work

### Milestone 1 — compile seed steps into `SeedFileOp`

Scope: seed steps become distinguishable operations all the way through composition, and no
existing command misbehaves because of the new constructor. At the end, `compilePlan` on a
module with a seed step yields a `SeedFileOp`, and `mergeOperations` merges and refuses as
decided.

Add to `Operation` in `seihou-core/src/Seihou/Core/Types.hs`:

```haskell
  | -- | A seed: write @content@ to @dest@ only if the path is absent, then
    -- hand the file to the project. Never tracked by hash. See
    -- docs/adr/0017-a-seed-file-is-created-once-and-belongs-to-the-project.md.
    SeedFileOp
      { dest :: !FilePath,
        content :: !Text,
        strategy :: !Strategy,
        moduleName :: !ModuleName
      }
```

In `Seihou.Engine.Plan.compileStep`, after the condition check and after the strategy's
compile function produced its operations, when `step ^. #lifecycle == Seed` rewrite each
resulting `WriteFileOp d c s` into `SeedFileOp d c s <module name>` and keep `CreateDirOp`s.
EP-1's validation already rejects seed + patch and seed + structured, but `compileStep` must
not rely on validation having run: return a compile error (`Left [...]`) with the same wording
as EP-1's finding if it meets either combination.

In `mergeOperations`, handle `SeedFileOp`:

- If no operation yet targets the path, add it and record the owner.
- If an earlier `SeedFileOp` targets the path, keep the earlier one (seeds never overwrite)
  and add the later module as an additional seed owner. Because the existing owner map is
  `Map FilePath ModuleName`, return an additional value from `mergeOperations`:
  `Map FilePath (Set ModuleName)` of *seed owners*, and thread it through
  `compileComposedPlan`'s result. Update every caller (the compiler lists them: `Run.hs`,
  `AgentRun.hs`, `Update.hs`, `ManifestCapabilityUpgrade.hs`).
- If a `WriteFileOp`, `CopyFileOp`, or `PatchFileOp` targets the same path before or after a
  `SeedFileOp`, fail composition with
  `module '<a>' seeds '<path>' but module '<b>' manages it; a path is either seeded or managed`.
  `mergeOperations` is pure and returns a tuple today; change its result to `Either [Text] (…)`
  or collect a new `CompositionWarning`-like error list that `compileComposedPlan` turns into
  `Left`. Prefer the smallest change that makes `compileComposedPlan` return `Left` with that
  message.

Review every `Operation` match found by the grep in Context. Make each explicit rather than
relying on a wildcard: `Execute.operationDestination` returns `Just dest` for seeds;
`isAdditiveOperation` returns `False`; `Preview.opToPreview` handles it (Milestone 3 refines
the tag). For the interim guard, add to `seihou-core/src/Seihou/Engine/Seed.hs` (created in
Milestone 2; create the module now with just this function):

```haskell
-- | Until `seihou update` understands seeds, it and shared-write
-- certification treat a seed as the managed write it used to be.
seedAsManagedWrite :: Operation -> Operation
seedAsManagedWrite (SeedFileOp d c s _) = WriteFileOp d c s
seedAsManagedWrite other = other
```

and apply it with `map seedAsManagedWrite` to the compiled operations in
`seihou-cli/src/Seihou/CLI/Update.hs` and `seihou-cli/src/Seihou/CLI/ManifestCapabilityUpgrade.hs`
immediately after `compileComposedPlan` returns, with a comment naming EP-5
(`docs/plans/103-reconcile-seed-steps-during-seihou-update-and-release-managed-files-to-seeds.md`),
which removes it.

Tests: `PlanSpec.hs` — a seed template step yields a `SeedFileOp` with the rendered content
and the module name; a managed step still yields `WriteFileOp`. Composition merge tests — two
seeds on one path keep the first content and report both seed owners; a seed and a managed
write on one path fail with the message above, in either order.

Acceptance: `cabal build all` and `cabal test all` pass; every existing test is unaffected.

### Milestone 2 — the seed engine

Scope: one pure-ish module decides and performs what a seed step does, so `run` and (later)
`update` agree. At the end, it is fully unit-tested against the in-memory filesystem.

In `seihou-core/src/Seihou/Engine/Seed.hs` (add to `exposed-modules`), define:

```haskell
data SeedDecision
  = -- | Path absent and never settled: write it; outcome 'SeedCreated'.
    SeedWrite
  | -- | Path present and never settled: leave it; outcome 'SeedFoundExisting'.
    SeedKeepExisting
  | -- | A receipt exists and the file is gone: the project deleted it; do
    -- not re-create it, keep the receipt.
    SeedRespectDeletion
  | -- | A receipt exists and the file is present: nothing to do.
    SeedAlreadySettled
  | -- | The path is a managed file in 'files'. `seihou run` keeps it managed
    -- and points at `seihou update`; EP-5's update releases it.
    SeedReleaseManaged
  deriving stock (Eq, Show, Generic)

classifySeed :: Maybe SeedRecord -> Maybe FileRecord -> Bool -> SeedDecision
```

where the `Bool` is "the path exists on disk". The rules, in priority order: a `FileRecord`
present → `SeedReleaseManaged`; a receipt present → `SeedAlreadySettled` if the file exists,
else `SeedRespectDeletion`; otherwise `SeedWrite` if absent, `SeedKeepExisting` if present.

Also define a plan record and two effectful helpers over the `Filesystem` effect used by
`Seihou.Engine.Diff`:

```haskell
data PlannedSeed = PlannedSeed
  { path :: !FilePath,
    content :: !Text,
    strategy :: !Strategy,
    owners :: !(Set ModuleName),
    decision :: !SeedDecision
  }
  deriving stock (Eq, Show, Generic)

-- | Classify every seed operation against the manifest and disk.
planSeeds :: (Filesystem :> es) => Manifest -> Map FilePath (Set ModuleName) -> [Operation] -> Eff es [PlannedSeed]

-- | Write the 'SeedWrite' paths (creating parent directories) and return
-- the manifest with receipts merged for every decision except
-- 'SeedReleaseManaged'. Re-checks existence immediately before writing and
-- downgrades to 'SeedKeepExisting' if the file appeared meanwhile, so a
-- seed never overwrites.
executeSeeds :: (Filesystem :> es) => ApplicationId -> UTCTime -> [PlannedSeed] -> Manifest -> Eff es Manifest
```

`executeSeeds` records receipts through `mergeSeedRecord`: `SeedWrite` → outcome
`SeedCreated`; `SeedKeepExisting` → `SeedFoundExisting`; `SeedAlreadySettled` and
`SeedRespectDeletion` → merge the application into the existing receipt (no change to outcome
or time). The receipt's `moduleName` is the first owner in execution order (the module that
supplied the content).

Add `seihou-core/test/Seihou/Engine/SeedSpec.hs` with one case per decision, the
"appeared meanwhile" downgrade, two owners, and a check that `executeSeeds` never adds to
`files`.

Acceptance: `cabal test seihou-core-test` passes.

### Milestone 3 — `seihou run` and `seihou agent run`

Scope: the commands act on seeds. At the end, the observable behavior in Purpose is true.

In `Run.hs`:

1. Partition the compiled operations into seeds (`SeedFileOp`) and the rest. Keep building
   `planned` for `computeDiff` from the rest only, so a seed path can never be a diff
   conflict. Pass the composed module names so `computeDiff` still treats manifest files of
   these modules that are no longer planned as orphans — but exclude from orphaning any path
   that is now a seed with decision `SeedReleaseManaged` (it stays managed; its `FileRecord`
   must be kept, not dropped). The simplest way is to add those paths' `FileRecord`s back
   after the orphan cleanup, or to filter them out of `diff ^. #orphaned` before the cleanup.
2. Call `planSeeds` after reading the manifest. Include the planned seeds in the plan view
   (see Preview below). For every `SeedReleaseManaged`, print one note after the plan view:
   `note: <path> is now a seed in module '<m>', but it is tracked here; run 'seihou update <m>' to hand it to the project`.
3. After `executePlan` and baselines succeed, call `executeSeeds` on the new manifest before
   `writeManifest`, using the application's `applicationId`. Ensure the written manifest's
   `version` is `currentManifestVersion` (already the case) and assert
   `validateManifestInvariants` before writing; on failure print the error and exit non-zero
   without writing.
4. `opTargetsPath` and the conflict exclusion logic must ignore seeds (they were never
   conflicts).

Apply the same four changes to `AgentRun.hs`. If the duplication is large, extract a helper
into `seihou-cli/src/Seihou/CLI/RunSeeds.hs` (library side; it needs no
`Options.Applicative`) and call it from both.

Preview: extend `Seihou.Engine.Preview` so a `SeedFileOp` renders with its strategy and a tag
derived from its `SeedDecision`: `seed` (will be created), `seed: kept` (exists, not
settled), `seed` omitted entirely for `SeedAlreadySettled` and `SeedRespectDeletion` (nothing
to do; keep the plan view about work), and `seed: tracked` for `SeedReleaseManaged`. The
simplest implementation passes the `[PlannedSeed]` into `buildPreview` alongside the diff.
Update `formatDiff` so `--diff` shows the content of `SeedWrite` files as new files and
nothing for the others.

End-to-end test: add `seihou-cli/test/Seihou/CLI/SeedRunE2ESpec.hs` with a fixture module
under `seihou-cli/test/fixtures/` (follow the fixture pattern `SharedManifestE2ESpec.hs` uses)
that seeds `CHANGELOG.md` and manages `LICENSE`. Cases:

1. First run in an empty project creates both; the manifest has `LICENSE` in `files`,
   `CHANGELOG.md` in `seeds` with outcome `created`, and no `CHANGELOG.md` in `files`.
2. Edit `CHANGELOG.md`, run again with `--force`: the edit survives byte-for-byte.
3. Delete `CHANGELOG.md`, run again: it is not re-created; the receipt remains.
4. A fresh project that already contains a hand-written `CHANGELOG.md`: a run without
   `--force` in a non-interactive shell succeeds (no conflict), leaves it untouched, and
   records outcome `found-existing`.
5. `--dry-run` output contains `CHANGELOG.md` with the `seed` tag on a first run.

Documentation: in `docs/cli/run.md`, add a "Seed files" subsection: what a seed is, the four
behaviors above, the plan-view tags, and the note printed for a tracked path. Amend ADR 0017
with a dated paragraph: `seihou run` creates a seed only when absent, records a receipt,
never reports a seed as a conflict, respects deletion, refuses seed/managed mixes in a
composition, and leaves managed-to-seed release to `seihou update`. Add a root `CHANGELOG.md`
entry.

Acceptance: all five E2E cases pass; `cabal test all` and `nix flake check` pass.


## Concrete Steps

From `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` in the Nix dev shell:

```bash
cabal build all
cabal test seihou-core-test
cabal test seihou-cli-test --test-options='-p SeedRun'
cabal test all
nix flake check
```

Manual demonstration (after Milestone 3) with a scratch module:

```bash
mkdir -p "$TMPDIR/seed-run/mod/files" "$TMPDIR/seed-run/proj"
printf '# Changelog\n\n## [Unreleased]\n' > "$TMPDIR/seed-run/mod/files/CHANGELOG.md.tpl"
# write $TMPDIR/seed-run/mod/module.dhall with one template step for CHANGELOG.md
# carrying lifecycle = Some "seed" (see seihou-core/test/fixtures/seed-step from EP-1)
cd "$TMPDIR/seed-run/proj" && git init -q
seihou run "$TMPDIR/seed-run/mod" --force
jq '.version, .seeds, (.files | keys)' .seihou/manifest.json
```

Expected:

```text
8
{
  "CHANGELOG.md": {
    "module": "seed-demo",
    "applications": ["…"],
    "outcome": "created",
    "settledAt": "…"
  }
}
[]
```

(Use `cabal run -v0 --project-dir <repo> seihou --` in place of `seihou` if the new binary is
not on `PATH`; check `seihou run --help` for how a module is named on the command line.)


## Validation and Acceptance

Before this plan, running a module with a seed step writes and tracks the file like any other
(the seed is ignored), and a pre-existing `CHANGELOG.md` produces
`Conflicts detected (use --force to overwrite)`. After it, the E2E cases above hold, the
`files` map never contains a seed path, and `seihou status` (unchanged by this plan) lists
only managed files because seeds were never added to `files`. `cabal test all` and
`nix flake check` pass.


## Idempotence and Recovery

`seihou run` is designed to be re-run; with seeds, a second run is a no-op for every seed
path. The seed engine re-checks existence before writing, so a crash between planning and
writing cannot cause an overwrite. If a run fails after writing files but before writing the
manifest, the next run sees the created seed files as present with no receipt and records
`found-existing`, which is accurate enough and harmless. The interim update guard is removed
by EP-5; if EP-5 is abandoned, the guard keeps `seihou update` at today's behavior.


## Interfaces and Dependencies

At the end of this plan:

- `Seihou.Core.Types.Operation` has `SeedFileOp { dest, content, strategy, moduleName }`.
- `Seihou.Composition.Plan.compileComposedPlan` returns seed owners
  (`Map FilePath (Set ModuleName)`) in addition to its previous results, and fails on a
  seed/managed mix.
- `Seihou.Engine.Seed`: `SeedDecision (..)`, `classifySeed`, `PlannedSeed (..)`,
  `planSeeds`, `executeSeeds`, and the interim `seedAsManagedWrite`.
- `Seihou.Engine.Preview.buildPreview` renders seeds.

EP-5 (`docs/plans/103-reconcile-seed-steps-during-seihou-update-and-release-managed-files-to-seeds.md`)
must reuse `classifySeed`, `SeedDecision`, and `executeSeeds` (extending `SeedDecision` in this
module if it needs a new case) and must delete `seedAsManagedWrite` and its two call sites.
No new library dependency.
