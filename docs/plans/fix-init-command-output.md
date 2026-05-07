---
slug: fix-init-command-output
title: "Fix Init Command Output"
kind: exec-plan
created_at: 2026-03-05T02:50:48Z
---


# Fix Init Command Output

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

The `seihou init` command sets up the user's configuration directory but its output does not match the design specification. After this change, running `seihou init` produces the structured output defined in the spec:

    Initialized Seihou configuration at ~/.config/seihou/
      Created: config.dhall (global defaults)
      Created: modules/ (user modules)
      Created: installed/ (git-installed modules)

Re-running `seihou init` reports which items already exist and which were newly created, using a consistent format. The output uses `~/` to abbreviate the user's home directory for readability. Filesystem errors exit with code 1.


## Progress

- [x] M1-1: Add `shortenHome` helper to `Shared.hs` (2026-03-04)
- [x] M1-2: Rewrite `handleInit` in `Init.hs` to produce spec-format output (2026-03-04)
- [x] M1-3: Build — `cabal build all` (2026-03-04)
- [x] M1-4: Manual verification — run `seihou init` and compare output to spec (2026-03-04)
- [x] M2-1: Add `InitSpec.hs` unit tests for output format (6 tests) (2026-03-04)
- [x] M2-1b: Add internal library and test suite to `seihou-cli.cabal` (2026-03-04)
- [x] M2-2: Create test runner `seihou-cli/test/Main.hs` (2026-03-04)
- [x] M2-3: Build and test — `cabal test all` passes (484 core + 6 cli = 490) (2026-03-04)


## Surprises & Discoveries

- `seihou-cli` had no test suite or internal library. Added `library seihou-cli-internal` (private, exposing `Init` and `Shared`) and `test-suite seihou-cli-test` to `seihou-cli.cabal`. The internal library needed `containers` added to its `build-depends` because `Shared.hs` imports `Data.Map.Strict`.
- The plan originally placed tests in `seihou-core/test/Seihou/CLI/InitSpec.hs`, but `formatInitOutput` lives in `seihou-cli` which `seihou-core` cannot depend on. Tests were placed in `seihou-cli/test/` instead.


## Decision Log

- Decision: Add `shortenHome` to `Shared.hs` rather than inline in `Init.hs`.
  Rationale: Other commands (e.g., `install`, `status`) display XDG config paths and would benefit from the same abbreviation. Placing it in `Shared.hs` follows the existing pattern of shared CLI utilities like `formatVarError` and `logIO`.
  Date: 2026-03-04

- Decision: Keep the `namespaces/` directory creation even though the design spec only lists `modules/` and `installed/`.
  Rationale: The `namespaces/` directory is used by the config-file-layering system (`readNamespaceConfig` in `ConfigReader`). Removing it would break namespace-scoped variable storage. However, we do not list it in the output since it is an internal detail. If the user runs init on a fresh system, `namespaces/` is created silently.
  Date: 2026-03-04

- Decision: Track per-item creation status (created vs already exists) rather than a single summary.
  Rationale: The design spec shows `Created:` for each item. On re-runs, showing `Exists:` for items that were already present gives the user clear feedback about what happened, which aligns with the idempotency requirement.
  Date: 2026-03-04


## Outcomes & Retrospective

All milestones completed. 490 tests pass (484 core + 6 new CLI tests).

**Changes made:**
- `Shared.hs`: Added `shortenHome :: FilePath -> IO Text` for `~/` path abbreviation
- `Init.hs`: Rewrote `handleInit` with per-item existence tracking, structured output matching design spec; added `formatInitOutput` pure function for testability
- `seihou-cli.cabal`: Added `library seihou-cli-internal` (private) and `test-suite seihou-cli-test`
- Created `seihou-cli/test/Main.hs` and `seihou-cli/test/Seihou/CLI/InitSpec.hs` (6 tests)

The init command now produces the exact output format from `docs/dev/design/proposed/cli-commands.md` lines 101–105, with idempotent `Created:`/`Exists:` status reporting.


## Context and Orientation

Seihou is a composable project scaffolding tool. The `init` command creates a configuration directory tree under the XDG config path (typically `~/.config/seihou/`) with subdirectories for user-authored modules, git-installed modules, and namespace config files, plus a default `config.dhall` file.

The init handler lives at `seihou-cli/src/Seihou/CLI/Init.hs`. It exports a single function `handleInit :: IO ()`. The function uses `System.Directory.getXdgDirectory XdgConfig "seihou"` to determine the base path, creates three subdirectories (`modules`, `installed`, `namespaces`), and writes `config.dhall` if it does not already exist.

The current output is a flat list of `"Created <absolute-path>"` lines — one per subdirectory and one for the config file. It always prints `"Created"` for directories even on re-runs (because `createDirectoryIfMissing` is silent), and prints `"Already exists: <path>"` only for the config file.

The design specification at `docs/dev/design/proposed/cli-commands.md` (lines 83–115) defines a different output format: a header line `"Initialized Seihou configuration at ~/.config/seihou/"`, followed by indented `"Created: <item> (<description>)"` lines for each resource. The spec uses `~/` notation rather than absolute paths.

The CLI command definition is in `seihou-cli/src/Seihou/CLI/Commands.hs`. `Init` is a nullary constructor in the `Command` ADT — it takes no flags or arguments. The dispatch in `seihou-cli/src/Main.hs` calls `handleInit` directly.

Shared CLI utilities live in `seihou-cli/src/Seihou/CLI/Shared.hs`, which exports helpers like `formatVarError`, `logIO`, and `toVarNameMap`.

There are no existing tests for the init command. The test suite is in `seihou-core/test/` using Tasty + Hspec, with a main runner at `seihou-core/test/Main.hs` that aggregates all `*Spec.tests` values.


## Plan of Work

### Milestone 1: Fix output format

This milestone rewrites `handleInit` to produce the design spec output. At the end, `seihou init` prints the structured format with `~/` path abbreviation, per-item status tracking, and the header line.

First, add a `shortenHome :: FilePath -> IO Text` helper to `seihou-cli/src/Seihou/CLI/Shared.hs`. This function calls `getHomeDirectory` and replaces the home prefix with `~/` in the given path for display purposes. Export it from the module.

Then rewrite `handleInit` in `seihou-cli/src/Seihou/CLI/Init.hs`. The new implementation tracks what was created vs what already existed. For each of the three spec-visible items (config.dhall, modules/, installed/), it checks existence and records the status. The `namespaces/` directory is still created but not reported in output. After all operations, it prints the header line with the abbreviated base path, then the indented item lines. Each item line shows either `Created:` or `Exists:` followed by the item name and its description in parentheses.

The item order matches the spec: config.dhall first, then modules/, then installed/. The descriptions are: `(global defaults)`, `(user modules)`, `(git-installed modules)`.


### Milestone 2: Add tests

This milestone adds unit tests for the init command's output logic. Since `handleInit` performs IO (filesystem + stdout), the tests will extract the output-formatting logic into a pure function that can be tested without side effects.

Add a pure function `formatInitOutput :: Text -> [(Text, Text, Bool)] -> Text` to `Init.hs` that takes the abbreviated base path and a list of `(item, description, wasCreated)` triples, and returns the formatted output string. `handleInit` calls this function and prints the result. Tests verify the formatting logic.

Create `seihou-core/test/Seihou/CLI/InitSpec.hs` with tests for `formatInitOutput`: header line content, item ordering, `Created:` vs `Exists:` labels, indentation. Register it in the test main runner.


## Concrete Steps

**Working directory**: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

**Step 1** (M1-1): Edit `seihou-cli/src/Seihou/CLI/Shared.hs`:
- Add `shortenHome` to the export list
- Add `import System.Directory (getHomeDirectory)`
- Add the function:

        shortenHome :: FilePath -> IO Text
        shortenHome path = do
          home <- getHomeDirectory
          pure $ if home `isPrefixOf` path
            then "~/" <> T.pack (drop (length home + 1) path)
            else T.pack path

  (Also add `import System.FilePath (isPrefixOf)` — actually `Data.List (isPrefixOf)` since it is a string prefix check.)

**Step 2** (M1-2): Rewrite `seihou-cli/src/Seihou/CLI/Init.hs`:
- Add `formatInitOutput` as a pure function and export it
- Rewrite `handleInit` to:
  1. Determine base path via `getXdgDirectory XdgConfig "seihou"`
  2. Create base directory
  3. For config.dhall: check existence, write if missing, record status
  4. For modules/: check existence, create if missing, record status
  5. For installed/: check existence, create if missing, record status
  6. Create namespaces/ silently (no output)
  7. Call `formatInitOutput` and print the result
- `formatInitOutput basePath items` produces:

        Initialized Seihou configuration at <basePath>
          Created: config.dhall (global defaults)
          Created: modules/ (user modules)
          Exists:  installed/ (git-installed modules)

  Items with `wasCreated = True` show `Created:`, others show `Exists: ` (with extra space for alignment).

**Step 3** (M1-3): Build:

    cabal build all

Expected: compiles cleanly.

**Step 4** (M1-4): Manual test:

    cabal run seihou -- init

Expected output (first run):

    Initialized Seihou configuration at ~/.config/seihou/
      Created: config.dhall (global defaults)
      Created: modules/ (user modules)
      Created: installed/ (git-installed modules)

Second run:

    Initialized Seihou configuration at ~/.config/seihou/
      Exists:  config.dhall (global defaults)
      Exists:  modules/ (user modules)
      Exists:  installed/ (git-installed modules)

**Step 5** (M2-1): Create `seihou-core/test/Seihou/CLI/InitSpec.hs`:
- Test `formatInitOutput` with all-created, all-existing, and mixed scenarios
- Verify header line, indentation, label alignment

**Step 6** (M2-2): Register in `seihou-core/test/Main.hs`:
- Add `import Seihou.CLI.InitSpec qualified` and include in `tests` list

**Step 7** (M2-3): Build and test:

    cabal build all && cabal test all

Expected: all tests pass.


## Validation and Acceptance

### Automated

    cabal test all

All existing tests pass unchanged. New `InitSpec` tests verify `formatInitOutput` produces correct header, labels, and alignment for created, existing, and mixed item sets.

### Manual acceptance

First run on a clean system (or after removing `~/.config/seihou/`):

    seihou init

Expected:

    Initialized Seihou configuration at ~/.config/seihou/
      Created: config.dhall (global defaults)
      Created: modules/ (user modules)
      Created: installed/ (git-installed modules)

Second run (idempotent):

    seihou init

Expected:

    Initialized Seihou configuration at ~/.config/seihou/
      Exists:  config.dhall (global defaults)
      Exists:  modules/ (user modules)
      Exists:  installed/ (git-installed modules)

Exit code should be 0 in both cases.


## Idempotence and Recovery

All steps are safe to repeat. The init command itself is idempotent — it creates resources only if missing and reports status accurately. If implementation fails partway, `git checkout` on affected files restores the previous state.


## Interfaces and Dependencies

No new external dependencies.

In `seihou-cli/src/Seihou/CLI/Shared.hs`, the new function:

    shortenHome :: FilePath -> IO Text

In `seihou-cli/src/Seihou/CLI/Init.hs`, the updated exports:

    module Seihou.CLI.Init
      ( handleInit,
        formatInitOutput,
      )

The pure formatting function:

    formatInitOutput :: Text -> [(Text, Text, Bool)] -> Text

`handleInit` signature remains unchanged:

    handleInit :: IO ()
