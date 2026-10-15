---
slug: cli-dry-run-preview-with-color
title: "Add Colored Dry-Run Preview with Diff Status"
kind: exec-plan
created_at: 2026-03-03T03:12:57Z
---


# Add Colored Dry-Run Preview with Diff Status

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

Running `seihou run haskell-base --dry-run` currently prints a flat list of operations
with no indication of whether a file is new, already exists, has been modified, or would
conflict with user edits. The output is monochrome, making it hard to scan for the
important items among a long list of `mkdir` and `write` lines.

After this change the dry-run preview becomes a rich, colored summary that shows each
file's diff status relative to the manifest and disk. New files appear in green with a `+`
prefix, modified files in yellow with `~`, unchanged files in dim gray with `=`, conflicts
in bold red with `!`, and orphaned files (no longer produced by the plan) in magenta with
`-`. Directory and command operations retain their current format but gain consistent
styling. When stdout is not a terminal (piped to a file, CI log, etc.) the output falls
back to plain text automatically.

The user can verify the change by running:

    cd seihou
    cabal run seihou -- run haskell-base --var project.name=demo --dry-run

and observing colored, status-annotated output on a terminal.


## Progress

- [x] M1-1: Add `ansi-terminal` dependency to `seihou-cli.cabal` (2026-03-02)
- [x] M1-2: Create `Seihou.CLI.Style` module with color helper functions (2026-03-02)
- [x] M1-3: Register `Seihou.CLI.Style` in `seihou-cli.cabal` `other-modules` (2026-03-02)
- [x] M1-4: Build to verify dependency resolves and module compiles (2026-03-02)
- [x] M2-1: Create `Seihou.Engine.Preview` module in seihou-core with `PreviewLine` type and `buildPreview` (2026-03-02)
- [x] M2-2: Register `Seihou.Engine.Preview` in `seihou-core.cabal` `exposed-modules` (2026-03-02)
- [x] M2-3: Add unit tests for `buildPreview` in `PreviewSpec.hs` — 15 tests (2026-03-02)
- [x] M2-4: Register `PreviewSpec` in `seihou-core.cabal` and test `Main.hs` (2026-03-02)
- [x] M2-5: Build and run all tests — 377 pass (2026-03-02)
- [x] M3-1: Update `handleRun` in `Seihou.CLI.Run` to compute diff for dry-run path (2026-03-02)
- [x] M3-2: Replace `dryRunPlan` call with `buildPreview` + `renderPreviewColor` in dry-run branch (2026-03-02)
- [x] M3-3: Update `formatDiff` to accept `Bool` for color when rendering `--diff` output (2026-03-02)
- [x] M3-4: Build and run all tests — 377 pass, `nix fmt` clean (2026-03-02)
- [x] M3-5: Manual verification — dry-run shows preview with status symbols, piped output has no ANSI codes (2026-03-02)


## Surprises & Discoveries

- M2-1 and M2-2 had to be completed during M1 because `Seihou.CLI.Style` imports `Seihou.Engine.Preview`. Both modules needed to exist for the build to succeed. This was a harmless reordering — both belong to M1/M2 conceptually.
- The refactored `handleRun` opens and closes the `runFilesystem`/`runManifestStore` effect stack twice: once for diff computation (shared by all paths) and once for execution (when not dry-run). This is clean and the manifest store handles it correctly since the manifest path is the same.


## Decision Log

- Decision: Use `ansi-terminal` rather than raw ANSI escape codes.
  Rationale: `ansi-terminal` is the standard Haskell library for portable terminal colors (BSD3, no transitive C dependencies, works on Windows/macOS/Linux). It provides `hSupportsANSIColor` for TTY detection and `setSGRCode` for generating escape sequences as `String`, which we convert to `Text`. Using raw `"\ESC[32m"` strings would bypass Windows terminal compatibility and TTY detection.
  Date: 2026-03-02

- Decision: Color formatting lives in seihou-cli, not seihou-core.
  Rationale: seihou-core is a pure library with no terminal dependencies. Adding `ansi-terminal` there would pollute the library's dependency tree. The preview data structure (`PreviewLine`) lives in seihou-core as a pure type; the rendering with ANSI codes happens in seihou-cli's `Seihou.CLI.Style` module. This maintains the library/CLI separation.
  Date: 2026-03-02

- Decision: Dry-run now computes the three-state diff (like the non-dry-run path) to show file status.
  Rationale: The current dry-run path exits before computing the diff, so it cannot distinguish new from modified files. Computing the diff requires loading the manifest and reading the filesystem, which is a small cost compared to actually executing operations. The diff computation is read-only and safe for a preview.
  Date: 2026-03-02

- Decision: `buildPreview` returns a list of `PreviewLine` values rather than `Text`, so the CLI layer can decide whether to add color.
  Rationale: Keeps the core library free of ANSI concerns. Tests can assert on `PreviewLine` fields without parsing escape codes.
  Date: 2026-03-02


## Outcomes & Retrospective

All three milestones completed. The dry-run preview now shows each file's diff status (new/modified/unchanged/conflict/orphaned) with colored output on terminals and plain text when piped.

Key outcomes:
- `Seihou.Engine.Preview` (seihou-core): Pure module with `FileStatus`, `PreviewLine`, `buildPreview`, `renderPreviewPlain`. 15 unit tests cover all status classifications, operation types, orphan handling, and plain text rendering.
- `Seihou.CLI.Style` (seihou-cli): Color helpers using `ansi-terminal` with `useColor` TTY detection and `renderPreviewColor` for ANSI rendering with a colored summary line.
- `handleRun` refactored: Diff computation moved before the dry-run check so all three paths (dry-run, diff, execute) share the same manifest loading and diff. Dry-run uses `buildPreview` + `renderPreviewColor`. `formatDiff` now accepts a `Bool` for color mode.
- All 377 tests pass. `dryRunPlan` remains available for backward compatibility (still used in ExecuteSpec and ExecutionSpec tests).
- The `ansi-terminal` dependency resolved via cabal without changes to the Nix flake.


## Context and Orientation

### Repository Structure

The project is a Haskell workspace with two packages:

    seihou/
    ├── seihou-core/          # Pure library (types, engine, effects)
    │   ├── seihou-core.cabal
    │   └── src/Seihou/
    │       ├── Core/Types.hs        # All domain types
    │       ├── Engine/Execute.hs    # dryRunPlan, executePlan
    │       ├── Engine/Diff.hs       # computeDiff, planToFileMap
    │       └── Effect/Filesystem.hs # Filesystem effect (has pure interpreter)
    └── seihou-cli/           # CLI executable
        ├── seihou-cli.cabal
        └── src/Seihou/CLI/
            ├── Commands.hs          # RunOpts, flag parsing
            └── Run.hs               # handleRun (orchestrates the run command)

### Current Dry-Run Behavior

The `--dry-run` flag is defined on the `run` subcommand in `seihou-cli/src/Seihou/CLI/Commands.hs` (line 263) as `switch (long "dry-run" <> help "Show plan without executing")`. The flag sets `runDryRun :: Bool` in `RunOpts`.

In `seihou-cli/src/Seihou/CLI/Run.hs`, `handleRun` orchestrates the entire run command. The dry-run branch (lines 97-101) exits early:

    if runDryRun runOpts
      then do
        TIO.putStrLn "Dry run — operations that would be performed:"
        TIO.putStr (dryRunPlan ops)

The `dryRunPlan` function in `seihou-core/src/Seihou/Engine/Execute.hs` (lines 93-110) formats a flat list of `Operation` values as plain text. Each line is two-space indented with a verb prefix (`write`, `mkdir`, `copy`, `run`, `patch`) and the file path. No color, no diff status.

### Three-State Diff Model

The diff engine in `seihou-core/src/Seihou/Engine/Diff.hs` classifies each file into one of five states by comparing the manifest (last known generation state), the plan (what would be generated now), and the disk (actual file contents). The result is a `DiffResult` containing lists of `PlannedFile` (new), `ModifiedFile` (changed), `FilePath` (unchanged), `ConflictFile` (user-edited), and `OrphanedFile` (removed from plan).

Currently, diff information is only computed and displayed in the non-dry-run execution path (lines 123-128 of `Run.hs`) and behind the separate `--diff` flag. The dry-run branch bypasses this entirely. This plan wires the diff computation into the dry-run path so the preview can show file statuses.

### Existing Output Formatting

The `formatDiff` function (lines 197-216 of `Run.hs`) formats the diff as plain text using symbols: `+` (new), `~` (modified), `=` (unchanged), `!` (conflict), `-` (orphaned). This function will be updated to optionally emit color.

### Terminal Dependencies

Neither `seihou-core.cabal` nor `seihou-cli.cabal` currently depend on any terminal color library. The `ansi-terminal` package (version 1.1.5, BSD3 license) is available from Hackage and will be added to `seihou-cli.cabal` only.

### Key Types

`Operation` (in `seihou-core/src/Seihou/Core/Types.hs`, line 155) has five constructors: `WriteFileOp`, `CreateDirOp`, `CopyFileOp`, `RunCommandOp`, `PatchFileOp`.

`DiffResult` (line 259) groups files into five categories: `diffNew`, `diffModified`, `diffUnchanged`, `diffConflict`, `diffOrphaned`.

`Strategy` (line 117) is one of `Copy`, `Template`, `DhallText`, `Structured`.


## Plan of Work

### Milestone 1: Style Module and ANSI Dependency

This milestone adds the `ansi-terminal` dependency and creates a thin `Seihou.CLI.Style` module in the CLI package that provides helper functions for colored text output. At the end, the module compiles and the dependency resolves. No behavior changes yet.

The `Seihou.CLI.Style` module provides two categories of functions. First, color wrappers that take `Text` and return `Text` with embedded ANSI escape codes: `green`, `yellow`, `red`, `magenta`, `dim`, `bold`. Second, a TTY detection function `useColor :: IO Bool` that checks whether stdout supports ANSI color. Each color wrapper uses `setSGRCode` from `System.Console.ANSI` to generate escape sequences, concatenates them around the input, and appends a reset code.

Acceptance: `cabal build all` succeeds with the new dependency.

### Milestone 2: Preview Data Structure and Builder

This milestone creates a pure `Seihou.Engine.Preview` module in seihou-core that builds a structured preview from operations and an optional `DiffResult`. The module defines a `PreviewLine` type representing one line of the preview (with a status tag, verb, path, and optional annotation). A `buildPreview` function takes the list of `Operation` values and a `Maybe DiffResult` and produces `[PreviewLine]`. A `renderPreviewPlain` function renders the lines as plain `Text` (no ANSI codes) for use in tests and piped output.

The `PreviewLine` type has the following shape:

    data FileStatus = FsNew | FsModified | FsUnchanged | FsConflict | FsOrphaned | FsUnknown

    data PreviewLine
      = FilePreview
          { previewStatus :: FileStatus
          , previewVerb :: Text       -- "write", "copy", "patch"
          , previewPath :: FilePath
          , previewAnnotation :: Text  -- e.g. "(template)", "(append-section from nix-flake)"
          }
      | DirPreview FilePath
      | CommandPreview Text
      | OrphanPreview FilePath ModuleName

`buildPreview` works by iterating over operations and looking up each file-producing operation's destination in the `DiffResult` to determine its status. Operations that do not produce files (`CreateDirOp`, `RunCommandOp`) get their own `PreviewLine` variants. If no `DiffResult` is provided (first-ever run, no manifest), all file operations get status `FsNew`.

After the diff-aware operations, `buildPreview` also appends `OrphanPreview` lines for any files in `diffOrphaned` that are no longer produced by the plan.

The pure `renderPreviewPlain` function formats each `PreviewLine` as a single text line using the existing symbol convention: `+` for new, `~` for modified, `=` for unchanged, `!` for conflict, `-` for orphaned, no symbol for dirs and commands.

Unit tests in `seihou-core/test/Seihou/Engine/PreviewSpec.hs` verify: all five file statuses map correctly, directory ops produce `DirPreview`, command ops produce `CommandPreview`, orphaned files appear, and `renderPreviewPlain` matches expected format.

Acceptance: `cabal test all` passes with new tests.

### Milestone 3: Wire Into CLI with Color

This milestone updates `handleRun` to compute the diff in the dry-run path and replaces the `dryRunPlan` call with `buildPreview` + colored rendering. It also updates `formatDiff` to use color.

The changes to `handleRun` are:

1. Move the manifest loading and diff computation to happen before the dry-run check, so both the dry-run and non-dry-run paths have access to `DiffResult`. The manifest loading is read-only and safe. If no manifest exists (first run), use `Nothing` so `buildPreview` treats all files as new.

2. In the dry-run branch, call `buildPreview ops (Just diff)` to get `[PreviewLine]`, then render each line with color using a new `renderPreviewColor :: Bool -> [PreviewLine] -> Text` function in `Seihou.CLI.Style`. The `Bool` controls whether ANSI codes are emitted (based on `useColor`).

3. Update `formatDiff` to accept a `Bool` for color mode and wrap file paths in the appropriate color.

The `renderPreviewColor` function in `Seihou.CLI.Style` maps each `PreviewLine` to a colored text line: green for new, yellow for modified, default (no color) for unchanged, bold red for conflict, magenta for orphaned, cyan for directories, dim for commands.

A summary line at the bottom shows counts: "N new, N modified, N unchanged, N conflicts, N orphaned" with each count colored to match its category.

Acceptance: `cabal test all` passes. Running `cabal run seihou -- run haskell-base --var project.name=demo --dry-run` on a terminal shows colored output with diff status annotations. Piping the same command to `cat` shows plain text without escape codes.


## Concrete Steps

All commands run from `seihou/` (the workspace root).

### Build command

    cabal build all 2>&1

Expected: no errors.

### Test command

    cabal test all 2>&1

Expected: `All N tests passed.`

### Format command

    nix fmt 2>&1

Expected: no output (already formatted).

### Manual verification

    cabal run seihou -- run haskell-base --var project.name=demo --dry-run

Expected output (with ANSI colors on a terminal):

    Dry run — plan preview:
      + write  README.md  (template)
      + write  src/Lib.hs  (template)
      + write  LICENSE  (copy)
      + write  demo.cabal  (template)
      + write  cabal.project  (dhall-text)
        mkdir  src

    Summary: 5 new, 0 modified, 0 unchanged, 0 conflicts, 0 orphaned

The `+` prefix and file names appear in green because this is a first run (no manifest, all files are new). Directories show without a status prefix. The summary line colors each count.

### Piped output verification

    cabal run seihou -- run haskell-base --var project.name=demo --dry-run | cat

Expected: same content but without ANSI escape codes (plain text fallback).


## Validation and Acceptance

### Unit Tests

New tests in `seihou-core/test/Seihou/Engine/PreviewSpec.hs` verify:

1. `buildPreview` with no DiffResult treats all file ops as `FsNew`.
2. `buildPreview` with a DiffResult classifies files correctly (new, modified, unchanged, conflict).
3. Orphaned files from DiffResult appear as `OrphanPreview` lines.
4. `CreateDirOp` produces `DirPreview`.
5. `RunCommandOp` produces `CommandPreview`.
6. `PatchFileOp` maps to `FilePreview` with correct verb and annotation.
7. `renderPreviewPlain` produces expected text format.

### Existing Tests

All 362 existing tests continue to pass. The `dryRunPlan` function remains available (not deleted) — it is still called in existing `ExecuteSpec` and `ExecutionSpec` tests. No existing behavior is broken.

### Manual Test

Running `seihou run haskell-base --dry-run --var project.name=demo` on a terminal shows colored output. Piping to `cat` shows no escape codes. Running after a previous `seihou run` shows mixed statuses (unchanged files in gray, modified in yellow).


## Idempotence and Recovery

All milestones are additive. The new `Seihou.CLI.Style` and `Seihou.Engine.Preview` modules are new files. The `handleRun` changes restructure the dry-run flow but do not change non-dry-run execution behavior. Each milestone can be re-run safely; if partially completed, the progress checklist identifies exactly where to resume.

If the `ansi-terminal` dependency causes resolution issues with the Nix flake, the fallback is to use raw ANSI escape codes (portable across macOS and Linux) with manual TTY detection via `hIsTerminalDevice stdout` from `System.IO`. The `ansi-terminal` library is a thin wrapper around exactly this, so the fallback requires minimal code changes.


## Interfaces and Dependencies

### New External Dependency

`ansi-terminal` version `>=1.1 && <2` added to `seihou-cli.cabal` only. Provides `System.Console.ANSI` with `setSGRCode`, `SGR(..)`, `ConsoleLayer(..)`, `ColorIntensity(..)`, `Color(..)`, and `hSupportsANSIColor`.

### New Module in seihou-cli

In `seihou-cli/src/Seihou/CLI/Style.hs`, define:

    useColor :: IO Bool
    green :: Text -> Text
    yellow :: Text -> Text
    red :: Text -> Text
    magenta :: Text -> Text
    dim :: Text -> Text
    bold :: Text -> Text
    renderPreviewColor :: Bool -> [PreviewLine] -> Text

### New Module in seihou-core

In `seihou-core/src/Seihou/Engine/Preview.hs`, define:

    data FileStatus = FsNew | FsModified | FsUnchanged | FsConflict | FsOrphaned | FsUnknown

    data PreviewLine
      = FilePreview FileStatus Text FilePath Text
      | DirPreview FilePath
      | CommandPreview Text
      | OrphanPreview FilePath ModuleName

    buildPreview :: [Operation] -> Maybe DiffResult -> [PreviewLine]
    renderPreviewPlain :: [PreviewLine] -> Text

### Modified Functions

In `seihou-cli/src/Seihou/CLI/Run.hs`:

    handleRun :: RunOpts -> IO ()
    -- Modified: compute diff before dry-run check, use buildPreview + renderPreviewColor
    -- in dry-run branch. Non-dry-run path unchanged.

    formatDiff :: Bool -> DiffResult -> Text
    -- Modified: accepts Bool for color mode, wraps paths in ANSI when True.
