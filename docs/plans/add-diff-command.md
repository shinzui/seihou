# Add `seihou diff` Command

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, running `seihou diff` shows what has changed on disk since the last generation — without loading modules, resolving variables, or running any pipeline. The user sees a categorized summary of tracked files (unchanged, modified by user, deleted by user) plus a count summary. This provides a quick "what did I change?" view that is lighter than `seihou status` (which also shows applied modules, variables, etc.) and lighter than `seihou run --diff` (which requires the full module loading and variable resolution pipeline).

The command reads only `.seihou/manifest.json` and the tracked files on disk. No module loading, no Dhall evaluation, no variable resolution. It is purely a manifest-vs-disk comparison.

Output for a project with modified and unchanged files:

    Seihou Diff:

      modified   src/Lib.hs          (haskell-base)
      deleted    app/Main.hs         (haskell-base)

      1 unchanged, 1 modified, 1 deleted

Output when no manifest exists:

    No Seihou manifest found. Run 'seihou run <module>' to generate a project.


## Progress

- [x] M1-1: Add `Diff` constructor to `Command` ADT in `Commands.hs` (2026-03-04)
- [x] M1-2: Add `diff` subcommand parser in `Commands.hs` (2026-03-04)
- [x] M1-3: Create `seihou-cli/src/Seihou/CLI/Diff.hs` with `handleDiff` and `formatDiffOutput` (2026-03-04)
- [x] M1-4: Add dispatch case for `Diff` in `Main.hs` (2026-03-04)
- [x] M1-5: Add `Seihou.CLI.Diff` to `seihou-cli.cabal` executable `other-modules` (2026-03-04)
- [x] M1-6: Build — `cabal build all` (2026-03-04)
- [x] M1-7: Manual verification — `seihou diff` shows no-manifest message correctly (2026-03-04)
- [x] M2-1: Add `Diff.hs` to `seihou-cli-internal` library exposed modules (2026-03-04)
- [x] M2-1b: Add `Seihou.CLI.Style` to internal library other-modules + `ansi-terminal` dep (2026-03-04)
- [x] M2-1c: Add `seihou-core` to test suite build-depends (2026-03-04)
- [x] M2-2: Create `seihou-cli/test/Seihou/CLI/DiffSpec.hs` with 7 unit tests for `formatDiffOutput` (2026-03-04)
- [x] M2-3: Register `DiffSpec` in `seihou-cli/test/Main.hs` (2026-03-04)
- [x] M2-4: Build and test — 497 tests pass (484 core + 13 cli) (2026-03-04)


## Surprises & Discoveries

- The `seihou-cli-internal` library needed `Seihou.CLI.Style` added to `other-modules` because `Diff.hs` imports color functions from it. This also required adding `ansi-terminal` to the internal library's `build-depends`.
- The test suite needed `seihou-core` added to `build-depends` because `DiffSpec.hs` imports `TrackedFile` and `TrackedFileStatus` directly from `Seihou.Core.Types`.


## Decision Log

- Decision: Make `seihou diff` a manifest-vs-disk comparison only, not a re-generation diff.
  Rationale: The design spec says "Show what would change without the full run flow." Re-generating content would require module loading and plan compilation, which IS a significant part of the run flow. A pure manifest-vs-disk comparison is truly lightweight: read the manifest, hash each tracked file on disk, compare hashes. This also avoids the problem that modules may have been updated or deleted since last run, which would cause confusing errors in a diff command.
  Date: 2026-03-04

- Decision: Only show changed files (modified + deleted) in the main output, with a summary count line that includes unchanged.
  Rationale: Showing all unchanged files would be noisy. The user runs `diff` to see what changed, not what stayed the same. The summary line `1 unchanged, 1 modified, 1 deleted` gives the full picture. This matches `git diff` behavior (only shows changes, not unchanged files).
  Date: 2026-03-04

- Decision: Reuse existing `computeTrackedFileStatuses` from `Seihou.Core.Status` rather than writing new comparison logic.
  Rationale: This function already compares manifest hashes to disk content and returns `TrackedFile` with `TfsUnchanged`/`TfsModified`/`TfsDeleted` status. It uses the effectful `Filesystem` effect, enabling pure testing. No need to duplicate this logic.
  Date: 2026-03-04

- Decision: Extract `formatDiffOutput` as a pure function for testability, following the pattern established by `formatInitOutput` in `Init.hs`.
  Rationale: Consistent with the project's approach to separating IO from formatting logic. Tests verify formatting without needing filesystem access.
  Date: 2026-03-04


## Outcomes & Retrospective

All milestones completed. 497 tests pass (484 core + 13 CLI: 7 diff + 6 init).

**Changes made:**
- `Commands.hs`: Added `Diff` constructor to `Command` ADT, `diff` subcommand parser with `diffInfo`
- `Diff.hs`: New module with `handleDiff` (IO handler) and `formatDiffOutput` (pure formatter)
- `Main.hs`: Added import and dispatch case for `Diff -> handleDiff`
- `seihou-cli.cabal`: Added `Seihou.CLI.Diff` to executable other-modules, internal library exposed-modules; added `Seihou.CLI.Style` to internal library other-modules; added `ansi-terminal` to internal library build-depends; added `seihou-core` to test suite build-depends; added `DiffSpec` to test other-modules
- `test/Main.hs`: Registered `DiffSpec.tests`
- `test/Seihou/CLI/DiffSpec.hs`: 7 tests for `formatDiffOutput`

The diff command provides a lightweight manifest-vs-disk comparison without loading modules or resolving variables.


## Context and Orientation

Seihou is a composable, type-safe project scaffolding system. After running `seihou run <module>`, it creates a `.seihou/manifest.json` file that tracks which files were generated, their SHA256 content hashes, and which module produced them.

### Relevant existing code

**`seihou-core/src/Seihou/Core/Status.hs`** exports `computeTrackedFileStatuses :: (Filesystem :> es) => Manifest -> Eff es [TrackedFile]`. This function iterates over `manifestFiles` in the manifest, reads each file from disk, computes its SHA256 hash, and classifies it as `TfsUnchanged`, `TfsModified`, or `TfsDeleted`. It returns a sorted list of `TrackedFile` records.

**`seihou-core/src/Seihou/Core/Types.hs`** defines:
- `TrackedFile` with fields `trackedPath :: FilePath`, `trackedModule :: ModuleName`, `trackedStatus :: TrackedFileStatus`
- `TrackedFileStatus` with constructors `TfsUnchanged`, `TfsModified`, `TfsDeleted`

**`seihou-cli/src/Seihou/CLI/Status.hs`** implements `handleStatus :: IO ()` which uses `computeTrackedFileStatuses` and displays full status (modules, files, variables). The `diff` command will use the same core function but with a focused, diff-oriented output.

**`seihou-cli/src/Seihou/CLI/Commands.hs`** defines the `Command` ADT. Currently has: `Init`, `Run RunOpts`, `Vars VarsOpts`, `Install InstallOpts`, `Status`, `NewModule NewModuleOpts`, `ValidateModule ValidateOpts`, `Config ConfigOpts`. The `commandParser` function registers all subcommands.

**`seihou-cli/src/Main.hs`** dispatches commands: `case cmd of Init -> handleInit; Run runOpts -> handleRun runOpts; ...`.

**`seihou-cli/seihou-cli.cabal`** has three components: `library seihou-cli-internal` (private, exposes `Init` and `Shared`), `executable seihou`, and `test-suite seihou-cli-test`.

**`seihou-cli/src/Seihou/CLI/Style.hs`** provides colored output functions: `dim`, `green`, `yellow`, `red`, `magenta`, `bold`, `useColor`.

### Effect stack for manifest reading

The `handleStatus` function shows the pattern for reading the manifest and computing file statuses:

```haskell
result <- runEff $ runFilesystem $ runManifestStore manifestPath $ do
  mResult <- readManifest
  case mResult of
    Left err -> pure (Left err)
    Right Nothing -> pure (Right Nothing)
    Right (Just manifest) -> do
      tracked <- computeTrackedFileStatuses manifest
      pure (Right (Just (manifest, tracked)))
```


## Plan of Work

### Milestone 1: Implement the diff command

This milestone adds the `seihou diff` command as a new subcommand. At the end, `seihou diff` reads the manifest, compares tracked files to disk, and prints a focused diff summary showing only changed files with a count line.

**Step 1** (M1-1): Edit `seihou-cli/src/Seihou/CLI/Commands.hs`. Add `Diff` as a nullary constructor to the `Command` ADT (no flags or arguments needed).

**Step 2** (M1-2): In the same file, add `command "diff" diffInfo` to the `commandParser` subparser list. Define `diffInfo` with `progDesc "Show changes since last generation"` and a footer explaining the command.

**Step 3** (M1-3): Create `seihou-cli/src/Seihou/CLI/Diff.hs`. This module exports `handleDiff :: IO ()` and `formatDiffOutput :: Bool -> [TrackedFile] -> Text`.

`handleDiff`:
1. Set `manifestPath = ".seihou" </> "manifest.json"`
2. Run effectful block: `readManifest`, handle errors
3. If no manifest: print the standard no-manifest message and exit 0
4. If manifest found: call `computeTrackedFileStatuses manifest`
5. Call `useColor` to check color support
6. Call `formatDiffOutput colorEnabled tracked` and print

`formatDiffOutput color tracked`:
1. Separate tracked files into unchanged, modified, deleted lists
2. If no modified or deleted files: return `"No changes since last generation.\n"`
3. Otherwise: output header `"Seihou Diff:\n"`, then for each modified/deleted file print a line like `"  modified   src/Lib.hs          (haskell-base)"`, then a blank line, then the summary count line `"  1 unchanged, 1 modified, 1 deleted\n"`
4. Pad file paths to align module names in parentheses
5. Apply color if enabled: yellow for modified, red for deleted, dim for the module attribution

**Step 4** (M1-4): Edit `seihou-cli/src/Main.hs`. Add `import Seihou.CLI.Diff (handleDiff)` and dispatch case `Diff -> handleDiff`.

**Step 5** (M1-5): Edit `seihou-cli/seihou-cli.cabal`. Add `Seihou.CLI.Diff` to the executable's `other-modules` list.

**Step 6** (M1-6): Build with `cabal build all`.

**Step 7** (M1-7): Manual test in a project with a manifest.

### Milestone 2: Add tests

This milestone adds unit tests for `formatDiffOutput` to the `seihou-cli-test` suite.

**Step 1** (M2-1): Edit `seihou-cli/seihou-cli.cabal`. Add `Seihou.CLI.Diff` to the `seihou-cli-internal` library's `exposed-modules`.

**Step 2** (M2-2): Create `seihou-cli/test/Seihou/CLI/DiffSpec.hs` with tests:
1. "shows no-changes message when all files unchanged"
2. "shows modified files with yellow label"
3. "shows deleted files with red label"
4. "shows summary count line"
5. "includes header line"
6. "shows module attribution in parentheses"
7. "hides unchanged files from main listing"

**Step 3** (M2-3): Edit `seihou-cli/test/Main.hs` to import and register `DiffSpec`.

**Step 4** (M2-4): Build and test with `cabal build all && cabal test all`.


## Concrete Steps

**Working directory**: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

**Step 1** (M1-1): Edit `seihou-cli/src/Seihou/CLI/Commands.hs`:
- Add `Diff` after `Status` in the `Command` data type:
  ```haskell
  | Diff
  ```

**Step 2** (M1-2): In the same file:
- Add to `commandParser`'s subparser list:
  ```haskell
  <> command "diff" diffInfo
  ```
- Add `diffInfo`:
  ```haskell
  diffInfo :: ParserInfo Command
  diffInfo =
    info
      (pure Diff <**> helper)
      ( fullDesc
          <> progDesc "Show changes since last generation"
          <> footerDoc
            ( Just $
                vsep
                  [ pretty ("Compares tracked files in .seihou/manifest.json against the current" :: String),
                    pretty ("disk state. Shows files that have been modified or deleted since the" :: String),
                    pretty ("last 'seihou run'. Does not load modules or resolve variables." :: String)
                  ]
            )
      )
  ```

**Step 3** (M1-3): Create `seihou-cli/src/Seihou/CLI/Diff.hs`:
```haskell
module Seihou.CLI.Diff
  ( handleDiff,
    formatDiffOutput,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Effectful
import Seihou.CLI.Shared (logIO)
import Seihou.CLI.Style (dim, red, useColor, yellow)
import Seihou.Core.Status (computeTrackedFileStatuses)
import Seihou.Core.Types
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.Logger (logError)
import Seihou.Effect.ManifestStore (readManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import System.Exit (exitFailure)
import System.FilePath ((</>))

handleDiff :: IO ()
handleDiff = do
  let manifestPath = ".seihou" </> "manifest.json"

  result <- runEff $ runFilesystem $ runManifestStore manifestPath $ do
    mResult <- readManifest
    case mResult of
      Left err -> pure (Left err)
      Right Nothing -> pure (Right Nothing)
      Right (Just manifest) -> do
        tracked <- computeTrackedFileStatuses manifest
        pure (Right (Just tracked))

  colorEnabled <- useColor

  case result of
    Left err -> do
      logIO LogNormal (logError $ "Error reading manifest: " <> err)
      exitFailure
    Right Nothing ->
      TIO.putStrLn "No Seihou manifest found. Run 'seihou run <module>' to generate a project."
    Right (Just tracked) ->
      TIO.putStr (formatDiffOutput colorEnabled tracked)

formatDiffOutput :: Bool -> [TrackedFile] -> Text
formatDiffOutput color tracked =
  let modified = filter (\t -> trackedStatus t == TfsModified) tracked
      deleted = filter (\t -> trackedStatus t == TfsDeleted) tracked
      unchanged = filter (\t -> trackedStatus t == TfsUnchanged) tracked
      nMod = length modified
      nDel = length deleted
      nUnch = length unchanged
      changed = modified ++ deleted
   in if null changed
        then "No changes since last generation.\n"
        else
          let maxPathLen = maximum (map (length . trackedPath) changed)
              header = "Seihou Diff:\n"
              fileLines = map (formatLine color maxPathLen) changed
              summary =
                "  "
                  <> T.pack (show nUnch)
                  <> " unchanged, "
                  <> T.pack (show nMod)
                  <> " modified, "
                  <> T.pack (show nDel)
                  <> " deleted\n"
           in header <> "\n" <> T.unlines fileLines <> "\n" <> summary

formatLine :: Bool -> Int -> TrackedFile -> Text
formatLine color maxPathLen tf =
  let (label, colorFn) = case trackedStatus tf of
        TfsModified -> ("modified", yellow)
        TfsDeleted -> ("deleted ", red)
        TfsUnchanged -> ("unchanged", dim)
      path = T.pack (trackedPath tf)
      modName = unModuleName (trackedModule tf)
      paddedLabel = if color then colorFn label else label
      paddedPath = path <> T.replicate (maxPathLen - T.length path + 3) " "
      modAttr = if color then dim ("(" <> modName <> ")") else "(" <> modName <> ")"
   in "  " <> paddedLabel <> "   " <> paddedPath <> modAttr
```

**Step 4** (M1-4): Edit `seihou-cli/src/Main.hs`:
- Add import: `import Seihou.CLI.Diff (handleDiff)`
- Add case: `Diff -> handleDiff`

**Step 5** (M1-5): Edit `seihou-cli/seihou-cli.cabal`:
- Add `Seihou.CLI.Diff` to executable `other-modules`

**Step 6** (M1-6): Build:
```
cabal build all
```
Expected: compiles cleanly.

**Step 7** (M1-7): Manual test:
```
cd /tmp && mkdir diff-test && cd diff-test
cabal run seihou -- diff
```
Expected: `No Seihou manifest found. Run 'seihou run <module>' to generate a project.`

In an existing project with a manifest, modify a file and run `seihou diff` to see the diff output.

**Step 8** (M2-1): Edit `seihou-cli/seihou-cli.cabal`:
- Add `Seihou.CLI.Diff` to `seihou-cli-internal` `exposed-modules`

**Step 9** (M2-2): Create `seihou-cli/test/Seihou/CLI/DiffSpec.hs` with tests for `formatDiffOutput`.

**Step 10** (M2-3): Edit `seihou-cli/test/Main.hs`:
- Add `import Seihou.CLI.DiffSpec qualified as DiffSpec`
- Add `DiffSpec.tests` to the test list

**Step 11** (M2-4): Build and test:
```
cabal build all && cabal test all
```
Expected: all tests pass.


## Validation and Acceptance

### Automated

    cabal test all

All existing tests pass unchanged. New `DiffSpec` tests verify `formatDiffOutput` produces correct output for: no changes, modified files, deleted files, mixed scenarios, summary counts, and module attribution.

### Manual acceptance

In a project with no manifest:
```
seihou diff
```
Expected:
```
No Seihou manifest found. Run 'seihou run <module>' to generate a project.
```
Exit code 0.

In a project with a manifest and no changes:
```
seihou diff
```
Expected:
```
No changes since last generation.
```

In a project with modified files:
```
seihou diff
```
Expected (example):
```
Seihou Diff:

  modified   src/Lib.hs          (haskell-base)

  3 unchanged, 1 modified, 0 deleted
```


## Idempotence and Recovery

All steps are safe to repeat. The diff command is read-only — it never modifies the manifest or any files. If implementation fails partway, `git checkout` on affected files restores the previous state.


## Interfaces and Dependencies

No new external dependencies.

In `seihou-cli/src/Seihou/CLI/Commands.hs`, the new constructor:

    | Diff

In `seihou-cli/src/Seihou/CLI/Diff.hs`, the exports:

    module Seihou.CLI.Diff
      ( handleDiff,
        formatDiffOutput,
      )

The handler:

    handleDiff :: IO ()

The pure formatting function:

    formatDiffOutput :: Bool -> [TrackedFile] -> Text
