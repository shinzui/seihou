# Preserve manifest state across independent module runs

Intention: intention_01kmzj9vx8en3t4b08eb4eytjq

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

When a user runs `seihou run module-a` and later `seihou run module-b` (independently, not
as a composition), the manifest should preserve file records, variables, and module entries
from both runs. Currently, the second run classifies module-a's files as "orphaned" and
removes them from the manifest, leaving only module-b's files tracked.

After this change, running multiple modules independently in the same project will result in
a manifest that faithfully tracks every generated file, which module owns it, and all resolved
variables — regardless of how many separate `seihou run` invocations produced them.

**Observable outcome:** Run two independent modules in sequence. Inspect `.seihou/manifest.json`
and confirm that files from both modules are recorded in the `files` map with correct ownership.


## Progress

- [x] Milestone 1: Scope orphan detection to active modules in `computeDiff` (2026-03-30)
  - [x] Add `Set ModuleName` parameter to `computeDiff` for active modules
  - [x] Filter manifest files to active-module scope before building diff paths
  - [x] Update `Run.hs` to pass composed module names
  - [x] Update `DiffSpec.hs` test helper and existing tests
  - [x] Add unit test: files from inactive modules are NOT classified as orphaned
  - [x] Add unit test: files from active modules ARE still classified as orphaned
  - [x] Verify existing tests pass (657 core + 95 CLI tests pass)
- [x] Milestone 2: Preserve variables from inactive modules (2026-03-30)
  - [x] Merge current variables with preserved manifest variables in `Run.hs`
  - [x] Variable preservation verified in end-to-end test (2026-03-30)
- [x] Milestone 3: End-to-end validation (2026-03-30)
  - [x] Run `exec-plan`, then `claude-gitignore` independently — manifest preserves all 3 files from both modules
  - [x] Plan view for `claude-gitignore` shows zero orphaned files from `exec-plan`
  - [x] Variables (`intentions.enabled`, `skill.name`) preserved across independent runs


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Scope the fix at the `computeDiff` level rather than filtering orphans in `Run.hs`
  Rationale: Fixing at the diff level ensures the plan view shown to the user also excludes
  irrelevant orphans. Filtering only in `Run.hs` would still show confusing "orphaned" entries
  in the dry-run and preview output.
  Date: 2026-03-30

- Decision: Filter `allPaths` by active-module manifest files rather than adding guards to
  individual classification branches.
  Rationale: This is the minimal change — `classifyFile` logic stays untouched. Paths from
  inactive modules simply don't enter the diff pipeline. If the plan targets a path owned by
  an inactive module, it enters via `planMap` and is correctly classified as Conflict (on-disk
  file exists but no manifest record in scope) or New (not on disk).
  Date: 2026-03-30

- Decision: Merge variables with `Map.union` (left-biased) instead of full replacement.
  Rationale: Current composition's resolved values take priority, but variables from
  previously-run modules are preserved. This matches the module-list behavior where
  `updateAllModules` already preserves entries from inactive modules.
  Date: 2026-03-30


## Outcomes & Retrospective

All three milestones completed. The fix required minimal changes (two files, ~10 lines of
production code) with no new types or modules:

- `computeDiff` gained a `Set ModuleName` parameter to scope orphan detection
- `Run.hs` passes composed module names and uses `Map.union` for variable preservation
- 2 new unit tests confirm the scoping behavior; all 752 existing tests pass
- End-to-end: running `exec-plan` then `claude-gitignore` independently preserves all files,
  modules, and variables from both runs


## Context and Orientation

### The Manifest

The manifest (`.seihou/manifest.json`) records the state of all generated files for
incremental re-generation and conflict detection.

**Type definition** — `seihou-core/src/Seihou/Core/Types.hs` lines 296–302:

```haskell
data Manifest = Manifest
  { version :: Int,         -- Schema version (currently 1)
    genAt :: UTCTime,       -- Timestamp of last generation
    modules :: [AppliedModule],  -- All modules ever applied
    vars :: Map VarName Text,    -- Resolved variable values
    files :: Map FilePath FileRecord  -- Generated files with hashes
  }
```

Each `FileRecord` tracks `hash`, `moduleName` (which module owns this file), `strategy`,
and `generatedAt`.

### The Three-State Diff Engine

`computeDiff` in `seihou-core/src/Seihou/Engine/Diff.hs` compares three states for each
file path: manifest (what was last generated), plan (what the current run would generate),
and disk (what's actually on the filesystem).

**Current signature** (line 28):

```haskell
computeDiff ::
  (Filesystem :> es) =>
  Manifest ->
  [(FilePath, Text, ModuleName, Maybe PatchOp)] ->
  Eff es DiffResult
```

The function builds `allPaths` from the union of ALL manifest file keys and ALL plan file
keys, then classifies each path into: New, Modified, Unchanged, Conflict, or Orphaned.

**The bug**: When `allPaths` includes manifest files from modules NOT in the current
composition, those files have no entry in `planMap` and are classified as Orphaned (lines
158–162). The caller in `Run.hs` (line 248) then removes them:

```haskell
let orphanedPaths = map (.path) diff.orphaned
    cleanedFiles = foldr Map.delete manifest.files orphanedPaths
```

### The Run Pipeline

`handleRun` in `seihou-cli/src/Seihou/CLI/Run.hs` orchestrates the full execution:

1. Load composed modules (primary + dependencies)
2. Resolve variables
3. Compile composed plan
4. Compute diff against existing manifest
5. Preview, confirm, resolve conflicts
6. Execute plan, update manifest

The manifest module-list update (`updateAllModules`, line 397) already correctly preserves
modules from prior runs — it filters out only the modules in the current composition and
re-adds them with updated timestamps. But the `files` and `vars` fields do not follow this
same preservation pattern.

### Relevant Files

| File | Role |
|------|------|
| `seihou-core/src/Seihou/Engine/Diff.hs` | `computeDiff` — three-state diff |
| `seihou-cli/src/Seihou/CLI/Run.hs` | `handleRun` — orchestration, manifest update |
| `seihou-core/src/Seihou/Core/Types.hs` | `Manifest`, `FileRecord`, `DiffResult` types |
| `seihou-core/test/Seihou/Engine/DiffSpec.hs` | Unit tests for `computeDiff` |
| `seihou-core/test/Seihou/Integration/ExecutionSpec.hs` | Integration tests |


## Plan of Work

### Milestone 1: Scope orphan detection to active modules

**Scope:** Modify `computeDiff` to accept a set of active module names and only consider
manifest files from those modules when computing diffs. Files from other modules are
invisible to the diff — neither orphaned nor classified in any way.

**What exists at the end:** `computeDiff` has a new `Set ModuleName` parameter. The run
pipeline passes the composed module names. Orphan detection is scoped. All existing tests
pass with the updated signature.

#### Step 1.1: Update `computeDiff` signature and filtering

In `seihou-core/src/Seihou/Engine/Diff.hs`:

1. Add `import Data.Set (Set)` alongside the existing qualified import.

2. Add a `Set ModuleName` parameter to `computeDiff` (between `Manifest` and the planned
   list):

   ```haskell
   computeDiff ::
     (Filesystem :> es) =>
     Manifest ->
     Set ModuleName ->
     [(FilePath, Text, ModuleName, Maybe PatchOp)] ->
     Eff es DiffResult
   computeDiff manifest activeModules planned = do
   ```

3. After `manifestFiles'`, add a filtered view and use it for `allPaths`:

   ```haskell
   let manifestFiles' = manifest.files
       activeManifestFiles =
         Map.filter (\r -> r.moduleName `Set.member` activeModules) manifestFiles'
       planMap = ...
       allPaths =
         Set.toList $
           Set.union
             (Map.keysSet activeManifestFiles)  -- was: manifestFiles'
             (Map.keysSet planMap)
   ```

4. Pass `activeManifestFiles` instead of `manifestFiles'` to `classifyFile`:

   ```haskell
   results <- mapM (classifyFile activeManifestFiles planMap) allPaths
   ```

No changes to `classifyFile` itself — it operates on whatever map it receives.

#### Step 1.2: Update `Run.hs` to pass active modules

In `seihou-cli/src/Seihou/CLI/Run.hs`, at line 179:

Change:
```haskell
d <- computeDiff m planned
```

To:
```haskell
let composedNames = Set.fromList (map ((.name) . fst) modulesInOrder)
d <- computeDiff m composedNames planned
```

The `modulesInOrder` binding is already in scope (from the composition loading step).
`Set` is already imported qualified as `Set`.

#### Step 1.3: Update test helper in `DiffSpec.hs`

In `seihou-core/test/Seihou/Engine/DiffSpec.hs`:

1. Add `import Data.Set (Set)` and `import Data.Set qualified as Set`.

2. Update `runDiff` helper to accept and pass the active modules set:

   ```haskell
   runDiff :: PureFS -> Manifest -> Set ModuleName
           -> [(FilePath, Text, ModuleName, Maybe PatchOp)] -> DiffResult
   runDiff fs manifest activeModules planned =
     fst $ runPureEff $ runFilesystemPure fs $ computeDiff manifest activeModules planned
   ```

3. Update all existing test call sites. Most tests use a single module (`modName = "test-module"`),
   so pass `Set.singleton modName` as the active modules set. For the "empty manifest and empty
   plan" test, pass `Set.empty`.

#### Step 1.4: Add new tests

Add two new tests to `DiffSpec.hs`:

```haskell
it "does not classify files from inactive modules as orphaned" $ do
  let otherMod = ModuleName "other-module"
      content = "from other module"
      record = FileRecord
        { hash = hashContent content
        , moduleName = otherMod
        , strategy = Template
        , generatedAt = fixedTime
        }
      manifest = manifestWithFiles (Map.singleton "other.txt" record)
      planned = [("new.txt", "new content", modName, Nothing)]
      activeModules = Set.singleton modName  -- "test-module", NOT "other-module"
      fs = PureFS (Map.fromList [("other.txt", content)]) mempty
      result = runDiff fs manifest activeModules planned
  length (result.orphaned) `shouldBe` 0
  length (result.new) `shouldBe` 1

it "classifies files from active modules as orphaned" $ do
  let content = "active module content"
      manifest = manifestWithFiles (Map.singleton "old.txt" (mkRecord content))
      planned = [("new.txt", "new content", modName, Nothing)]
      activeModules = Set.singleton modName  -- file belongs to active module
      fs = PureFS (Map.singleton "old.txt" content) mempty
      result = runDiff fs manifest activeModules planned
  length (result.orphaned) `shouldBe` 1
  (head result.orphaned).path `shouldBe` "old.txt"
```

#### Step 1.5: Update integration tests

In `seihou-core/test/Seihou/Integration/ExecutionSpec.hs`:

1. Add `import Data.Set qualified as Set`.

2. Update all `computeDiff manifest planned` calls to `computeDiff manifest activeModules planned`
   where `activeModules = Set.singleton modul.name` (the fixture module being tested).

#### Acceptance

Run `cabal test` from the workspace root. All tests pass, including the two new ones.


### Milestone 2: Preserve variables from inactive modules

**Scope:** Change the manifest variable update in `Run.hs` to merge rather than replace.

**What exists at the end:** Variables from previously-run modules are preserved in the
manifest. Current composition's values take precedence for overlapping keys.

#### Step 2.1: Merge variables

In `seihou-cli/src/Seihou/CLI/Run.hs`, at the manifest update block (around line 257):

Change:
```haskell
vars = Map.map varValueToText allResolvedVals,
```

To:
```haskell
vars = Map.union (Map.map varValueToText allResolvedVals) manifest.vars,
```

`Map.union` is left-biased: current values override old ones for the same keys, but old
keys from inactive modules are preserved.

#### Acceptance

Run `cabal test`. Build succeeds. Manual verification in Milestone 3.


### Milestone 3: End-to-end validation

**Scope:** Verify the fix works with real modules.

1. Pick two independent modules (e.g., `exec-plan` and `update-docs`).
2. Run `seihou run exec-plan` — inspect `.seihou/manifest.json`.
3. Run `seihou run update-docs` — inspect `.seihou/manifest.json`.
4. Confirm that:
   - The `files` map contains entries from BOTH modules.
   - The `modules` list contains both modules.
   - The `variables` map contains variables from both runs.
   - The plan view for the second run does NOT show exec-plan's files as orphaned.

#### Acceptance

The manifest after two independent runs contains file records from both modules.


## Concrete Steps

All commands run from the workspace root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

### Build and test after each milestone

```
cabal build all
cabal test all
```

Expected: all tests pass, no warnings related to the changed modules.


## Validation and Acceptance

1. **Unit tests** (`cabal test seihou-core`):
   - Existing `computeDiff` tests pass with updated signature.
   - New test "does not classify files from inactive modules as orphaned" passes.
   - New test "classifies files from active modules as orphaned" passes.
   - Integration tests pass with updated `computeDiff` calls.

2. **End-to-end** (manual):
   - Run module A, then module B independently.
   - `.seihou/manifest.json` contains files from both A and B.
   - Dry-run (`seihou run module-b --dry-run`) does not list A's files as orphaned.


## Idempotence and Recovery

All changes are to source files and tests. The build and test cycle (`cabal build all &&
cabal test all`) can be repeated safely. If a test fails, fix the code and re-run — no
external state is modified.

The manifest file (`.seihou/manifest.json`) is the only persistent artifact affected at
runtime. If it gets into a bad state during manual testing, delete it and re-run the modules.


## Interfaces and Dependencies

No new dependencies. No new modules. No new types.

**Modified interfaces:**

In `seihou-core/src/Seihou/Engine/Diff.hs`:

```haskell
computeDiff ::
  (Filesystem :> es) =>
  Manifest ->
  Set ModuleName ->   -- NEW: modules in the current composition
  [(FilePath, Text, ModuleName, Maybe PatchOp)] ->
  Eff es DiffResult
```

In `seihou-cli/src/Seihou/CLI/Run.hs`, manifest update (line ~257):

```haskell
vars = Map.union (Map.map varValueToText allResolvedVals) manifest.vars
```

No other modules import or call `computeDiff` in production code.
