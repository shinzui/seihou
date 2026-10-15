---
slug: enhance-status-command
title: "Enhance Status Command with File State Classification"
kind: exec-plan
created_at: 2026-03-04T15:26:19Z
---


# Enhance Status Command with File State Classification

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

The `seihou status` command currently reads the manifest and dumps raw metadata: module names with source paths, variable key-value pairs, and bare file paths. It does not tell the user whether generated files have been modified on disk since generation. After this change, `seihou status` will compare each tracked file's content hash against the manifest, classify files as unchanged, modified by user, or deleted by user, and display the results with ANSI color in a format matching the design specification. A user running `seihou status` in a project where they hand-edited a generated file will see that file flagged as "modified by user" in yellow, while untouched files show as "unchanged" in dim text. The command remains read-only and exits 0 in all non-error cases (including "no manifest").


## Progress

- [x] M1-1: Add `TrackedFileStatus` and `TrackedFile` types to `Seihou.Core.Types` (2026-03-04)
- [x] M1-2: Create `Seihou.Core.Status` module with `computeTrackedFileStatuses` (2026-03-04)
- [x] M1-3: Register `Seihou.Core.Status` in `seihou-core/seihou-core.cabal` (2026-03-04)
- [x] M1-4: Build — `cabal build seihou-core` (2026-03-04)
- [x] M2-1: Rewrite `handleStatus` in `seihou-cli/src/Seihou/CLI/Status.hs` with file classification and color (2026-03-04)
- [x] M2-2: Build — `cabal build all` (2026-03-04)
- [x] M2-3: Manual verification — all three states verified: unchanged, modified by user, deleted by user (2026-03-04)
- [x] M3-1: Create `seihou-core/test/Seihou/Core/StatusSpec.hs` with 5 unit tests (2026-03-04)
- [x] M3-2: Register `Seihou.Core.StatusSpec` in `seihou-core/seihou-core.cabal` (2026-03-04)
- [x] M3-3: Wire `StatusSpec` into `seihou-core/test/Main.hs` (2026-03-04)
- [x] M3-4: Build and test — all 467 tests pass (462 existing + 5 new) (2026-03-04)


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Create a dedicated `Seihou.Core.Status` module rather than inlining the computation in the CLI handler.
  Rationale: The CLI package (`seihou-cli`) is an executable, so its modules cannot be imported by `seihou-core`'s test suite. Placing the file-status computation in seihou-core makes it testable with the pure filesystem interpreter, following the same pattern used for `Seihou.Core.Scaffold`.
  Date: 2026-03-04

- Decision: Introduce new types `TrackedFileStatus` and `TrackedFile` rather than reusing `FileStatus` from `Preview.hs` or `DiffResult` from `Diff.hs`.
  Rationale: The existing `FileStatus` (`FsNew`, `FsModified`, `FsUnchanged`, `FsConflict`, `FsOrphaned`, `FsUnknown`) is designed for the dry-run preview, where "modified" means "the plan will update this file." In the status context, "modified" means "the user changed the disk copy since generation." These are semantically different. The three-state diff engine (`computeDiff`) requires a plan as input, but `seihou status` has no plan — it only compares manifest vs disk. A simpler two-state comparison with its own types avoids coupling status to the plan engine.
  Date: 2026-03-04

- Decision: Format module applied-at dates as `YYYY-MM-DD` matching the design spec, not as full UTC timestamps.
  Rationale: The design specification in `docs/dev/design/proposed/cli-commands.md` shows `(applied 2026-03-01)` — a short date without time. Full timestamps would clutter the status output. The `time` library's `formatTime` with `"%Y-%m-%d"` handles this.
  Date: 2026-03-04


## Outcomes & Retrospective

### Outcomes

All objectives met:

1. **File state classification works.** `seihou status` now compares each tracked file's disk content hash against the manifest hash and correctly reports unchanged, modified by user, and deleted by user statuses.

2. **Output matches the design spec.** The display format follows `docs/dev/design/proposed/cli-commands.md`: header, applied modules with YYYY-MM-DD dates, tracked files with path/module/status columns, and a variable count summary.

3. **ANSI color support.** Status labels are colored when stdout supports ANSI: dim for unchanged, yellow for modified, red for deleted. Falls back to plain text when color is unavailable.

4. **5 automated tests added.** `StatusSpec` verifies all three classifications plus mixed scenarios and the empty-manifest edge case. All 467 tests pass.

5. **Clean separation.** The computation logic lives in `Seihou.Core.Status` (testable with the pure filesystem interpreter), while the rendering lives in the CLI handler.


## Context and Orientation

Seihou is a composable project scaffolding tool. When a user runs `seihou run <module>`, the tool generates files from templates and records what it did in a manifest file at `.seihou/manifest.json`. The `seihou status` command reads this manifest and reports on the project's state.

The manifest is a JSON file defined by the `Manifest` type in `seihou-core/src/Seihou/Core/Types.hs` (lines 239–262). Its key fields are:

    manifestVersion  :: Int                -- Schema version (currently 1)
    manifestGenAt    :: UTCTime            -- When the manifest was last generated
    manifestModules  :: [AppliedModule]    -- Which modules were applied
    manifestVars     :: Map VarName Text   -- Snapshot of resolved variables
    manifestFiles    :: Map FilePath FileRecord  -- Per-file tracking

Each `FileRecord` (lines 254–262) stores a SHA256 content hash, the originating module name, the generation strategy, and a timestamp. The hash enables detecting whether the user has modified a generated file: if the current disk content hashes to a different value than what the manifest recorded, the file was modified.

Content hashing is implemented in `seihou-core/src/Seihou/Manifest/Hash.hs`. The function `hashContent :: Text -> SHA256` UTF-8-encodes text, computes a SHA256 digest, and returns a hex-encoded `SHA256` newtype.

The manifest is read and written through the `ManifestStore` effect (`seihou-core/src/Seihou/Effect/ManifestStore.hs`) which provides `readManifest :: Eff es (Either Text (Maybe Manifest))` and `writeManifest :: Manifest -> Eff es ()`. The IO interpreter (`ManifestStoreInterp.hs`) reads `.seihou/manifest.json` via the `Filesystem` effect. A pure interpreter (`ManifestStorePure.hs`) exists for tests.

The current status handler lives at `seihou-cli/src/Seihou/CLI/Status.hs`. It runs `readManifest`, then pattern-matches on the result: `Left err` (corrupt manifest, exit 1), `Right Nothing` (no manifest, prints a message, exit 0), or `Right (Just manifest)` (prints metadata). Currently it just lists file paths without any disk comparison.

The file system is abstracted by the `Filesystem` effect (`seihou-core/src/Seihou/Effect/Filesystem.hs`) with operations like `doesFileExist`, `readFileText`, etc. A pure interpreter (`FilesystemPure.hs`) backed by an in-memory `Map FilePath Text` enables deterministic tests — this is used extensively in `DiffSpec.hs` and other test modules.

ANSI color output is handled by `seihou-cli/src/Seihou/CLI/Style.hs`, which provides helper functions (`green`, `yellow`, `red`, `dim`, `bold`, `cyan`, `magenta`) that wrap text in ANSI SGR codes. The `useColor :: IO Bool` function checks whether stdout supports ANSI. The pattern used throughout the CLI is: check `useColor`, then conditionally apply color functions.

The existing three-state diff engine in `seihou-core/src/Seihou/Engine/Diff.hs` compares manifest vs plan vs disk, classifying files into New, Modified, Unchanged, Conflict, and Orphaned. This engine requires a plan (the set of operations a module would produce). The status command does not generate a plan — it only inspects the manifest against the current disk, so a simpler two-state comparison is appropriate.

The test infrastructure uses Tasty with Hspec wrappers. Each test module exports `tests :: IO TestTree`. Tests are registered in `seihou-core/seihou-core.cabal` under `other-modules` in the test suite and wired into `seihou-core/test/Main.hs`. The current test count is 462.

The design specification for the status command is in `docs/dev/design/proposed/cli-commands.md`. It specifies this output format when a manifest exists:

    Seihou Status:

    Applied modules:
      haskell-base    (applied 2026-03-01)
      nix-flake       (applied 2026-03-01)

    Tracked files: 6
      README.md           haskell-base   unchanged
      my-app.cabal        haskell-base   unchanged
      src/Lib.hs          haskell-base   modified by user
      app/Main.hs         haskell-base   unchanged
      flake.nix           nix-flake      unchanged
      .gitignore          nix-flake      unchanged

    Variables: 4 resolved


## Plan of Work

### Milestone 1: Core status computation

This milestone adds the data types and computation function to seihou-core. At the end, a new module `Seihou.Core.Status` exists that takes a `Manifest` and returns a list of tracked files with their disk status (unchanged, modified by user, or deleted by user). The module compiles and is registered in the cabal file.

In `seihou-core/src/Seihou/Core/Types.hs`, add two new types after the existing manifest-related types:

    data TrackedFileStatus
      = TfsUnchanged      -- disk hash matches manifest hash
      | TfsModified        -- disk hash differs from manifest hash
      | TfsDeleted         -- file not present on disk
      deriving stock (Eq, Show)

    data TrackedFile = TrackedFile
      { trackedPath   :: FilePath
      , trackedModule :: ModuleName
      , trackedStatus :: TrackedFileStatus
      }
      deriving stock (Eq, Show)

These go in `Types.hs` rather than the new module so they are available to both the core status computation and the CLI rendering layer without circular imports.

Create `seihou-core/src/Seihou/Core/Status.hs` with a single public function:

    computeTrackedFileStatuses :: (Filesystem :> es) => Manifest -> Eff es [TrackedFile]

The implementation iterates over `manifestFiles manifest` (a `Map FilePath FileRecord`), and for each entry checks whether the file exists on disk. If it does not exist, the status is `TfsDeleted`. If it does exist, read the file content, compute `hashContent`, and compare against `fileHash record`. If equal, `TfsUnchanged`; otherwise `TfsModified`. Return the list sorted by file path.

Register `Seihou.Core.Status` in `seihou-core/seihou-core.cabal` under `exposed-modules`.


### Milestone 2: Enhanced CLI status handler

This milestone rewrites the `handleStatus` function to use the new status computation and produce colored output matching the design spec. At the end, running `seihou status` in a project with a manifest shows applied modules with dates, tracked files with status classification and color, and a variable count summary.

Rewrite `seihou-cli/src/Seihou/CLI/Status.hs`. The new handler will:

1. Read the manifest via the effectful stack (same as now).
2. On `Right (Just manifest)`, run `computeTrackedFileStatuses` inside the same effectful block to get the file statuses.
3. Check `useColor` from `Style.hs`.
4. Print the output in the design format:
   - Header: `"Seihou Status:"` (or just `"Seihou Status"`).
   - Applied modules section: each module on its own line with `appliedAt` formatted as YYYY-MM-DD.
   - Tracked files section: file count header, then each file with path (left-aligned), module name, and status label. Color the status: green/dim for unchanged, yellow for modified by user, red for deleted by user.
   - Variables section: count of resolved variables.

The effectful block needs both `ManifestStore` and `Filesystem` in the effect stack. Currently the handler runs `runEff $ runFilesystem $ runManifestStore manifestPath readManifest`. The enhanced version will run the manifest read and status computation together inside the same effect block, then return the results to IO for rendering.

Import `Seihou.Core.Status (computeTrackedFileStatuses)` and `Seihou.CLI.Style` for color helpers. Import `Data.Time.Format` for formatting the applied-at dates.


### Milestone 3: Tests

This milestone adds unit tests for `computeTrackedFileStatuses` using the pure filesystem interpreter. At the end, the tests verify all three classifications (unchanged, modified, deleted) plus the empty-manifest edge case. All existing tests continue to pass.

Create `seihou-core/test/Seihou/Core/StatusSpec.hs`. The tests set up a `Manifest` with known `FileRecord` entries (using `hashContent` to compute correct hashes), create a `PureFS` with matching or differing file content, run `computeTrackedFileStatuses`, and assert the classification of each file.

Test cases:
1. File on disk matching manifest hash → `TfsUnchanged`
2. File on disk with different content → `TfsModified`
3. File in manifest but not on disk → `TfsDeleted`
4. Mixed scenario: multiple files with different statuses
5. Empty manifest → empty result list

Register the test in the cabal file and wire it into `Main.hs`.


## Concrete Steps

**Working directory**: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

**Step 1** (M1): Add `TrackedFileStatus` and `TrackedFile` types to `seihou-core/src/Seihou/Core/Types.hs`, after the `FileRecord` type (around line 262). Export them from the module.

**Step 2** (M1): Create `seihou-core/src/Seihou/Core/Status.hs` with `computeTrackedFileStatuses`.

**Step 3** (M1): Add `Seihou.Core.Status` to the `exposed-modules` list in `seihou-core/seihou-core.cabal` (after `Seihou.Core.Scaffold`, around line 21).

**Step 4** (M1): Build:

    cabal build seihou-core

Expected: compiles cleanly.

**Step 5** (M2): Rewrite `seihou-cli/src/Seihou/CLI/Status.hs` to use `computeTrackedFileStatuses` and render colored output.

**Step 6** (M2): Build:

    cabal build all

Expected: compiles cleanly.

**Step 7** (M2): Manual verification. First, run status without a manifest:

    cd /tmp && mkdir seihou-status-test && cd seihou-status-test
    cabal run seihou -- status

Expected output:

    No manifest found. Run 'seihou run <module>' first.

Then create a fake manifest and test files to verify the display. This can be done by running `seihou run` on a test module with a fixture, or by writing a manifest file manually. The simplest approach is to use a real module if one is installed, or to scaffold one:

    cd /tmp/seihou-status-test
    cabal run seihou -- new-module test-mod --path /tmp/seihou-status-test/test-mod
    cabal run seihou -- run /tmp/seihou-status-test/test-mod --var project.name=hello

If `run` creates a manifest, then:

    cabal run seihou -- status

Should show the tracked files as unchanged. Then edit a generated file and run status again — the modified file should show as "modified by user" in yellow.

If the run command does not yet write manifests in the current working directory, manual verification can be deferred to integration testing. The unit tests in M3 provide the primary validation.

    rm -rf /tmp/seihou-status-test

**Step 8** (M3): Create `seihou-core/test/Seihou/Core/StatusSpec.hs`.

**Step 9** (M3): Add `Seihou.Core.StatusSpec` to `other-modules` in `seihou-core/seihou-core.cabal` test suite (after `Seihou.Core.ScaffoldSpec`, around line 90).

**Step 10** (M3): Wire `StatusSpec` into `seihou-core/test/Main.hs`: add the qualified import, call `StatusSpec.tests` in main, and include the result in the `testGroup` list.

**Step 11** (M3): Build and run tests:

    cabal build all && cabal test all

Expected: all 462 existing tests pass plus the new `StatusSpec` tests (approximately 5 new tests, total ~467).


## Validation and Acceptance

### Automated

    cabal test all

All existing 462 tests pass, plus the new `StatusSpec` tests. The new tests verify:
- A file whose disk content matches the manifest hash is classified as `TfsUnchanged`.
- A file whose disk content differs from the manifest hash is classified as `TfsModified`.
- A file in the manifest but absent from disk is classified as `TfsDeleted`.
- A manifest with multiple files produces correct mixed classifications.
- An empty manifest produces an empty tracked-file list.

### Manual acceptance

Run `seihou status` in a directory without `.seihou/manifest.json`:

    Expected: "No manifest found. Run 'seihou run <module>' first." and exit code 0.

Run `seihou status` in a directory with a valid manifest (after running a module):

    Expected: displays "Seihou Status:" header, applied modules with dates, tracked files with status classification and color, variable count.

Edit a generated file and run `seihou status` again:

    Expected: the edited file shows as "modified by user" in yellow.


## Idempotence and Recovery

All steps are safe to repeat. The status command is read-only and does not modify any files. The types added to `Types.hs` are additive. The `Status.hs` rewrite replaces the existing handler entirely, so re-running the edit produces the same result. If a step fails partway, `git checkout` the affected files and retry.


## Interfaces and Dependencies

No new external dependencies. All required libraries (`effectful-core`, `time`, `text`, `containers`, `ansi-terminal`) are already dependencies of both `seihou-core` and `seihou-cli`.

In `seihou-core/src/Seihou/Core/Types.hs`, add:

    data TrackedFileStatus = TfsUnchanged | TfsModified | TfsDeleted
    data TrackedFile = TrackedFile
      { trackedPath   :: FilePath
      , trackedModule :: ModuleName
      , trackedStatus :: TrackedFileStatus
      }

In `seihou-core/src/Seihou/Core/Status.hs`, define:

    computeTrackedFileStatuses :: (Filesystem :> es) => Manifest -> Eff es [TrackedFile]

In `seihou-cli/src/Seihou/CLI/Status.hs`, the rewritten handler uses:

    handleStatus :: IO ()

The function signature does not change; only the implementation grows to include file-status computation and colored rendering.

In `seihou-core/test/Seihou/Core/StatusSpec.hs`, define:

    tests :: IO TestTree
    spec :: Spec
