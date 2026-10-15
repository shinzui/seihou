---
slug: add-list-command
title: "Add seihou list Command"
kind: exec-plan
created_at: 2026-03-05T23:05:12Z
---


# Add `seihou list` Command

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, running `seihou list` shows all available modules across the three search paths: project-local (`.seihou/modules/`), user modules (`~/.config/seihou/modules/`), and installed modules (`~/.config/seihou/installed/`). Each module is displayed with its name, description, and source location. Modules that fail to load are listed with an error indicator so the user knows they exist but are broken.

Output example:

    Available modules:

      haskell-base      Haskell project boilerplate       (user)
      nix-flake         Nix flake configuration           (installed)
      my-template       TODO: Describe this module        (project)
      broken-mod        [error: Dhall evaluation failed]  (installed)

    4 modules found (3 sources searched)

Output when no modules are found:

    No modules found.

    Searched:
      .seihou/modules/
      ~/.config/seihou/modules/
      ~/.config/seihou/installed/


## Progress

- [x] M1-1: Add `discoverAllModules` function to `seihou-core/src/Seihou/Core/Module.hs` (2026-03-05)
- [x] M1-2: Add `List` constructor to `Command` ADT in `Commands.hs` (2026-03-05)
- [x] M1-3: Add `list` subcommand parser in `Commands.hs` (2026-03-05)
- [x] M1-4: Create `seihou-cli/src/Seihou/CLI/List.hs` with `handleList` and `formatListOutput` (2026-03-05)
- [x] M1-5: Add dispatch case for `List` in `Main.hs` (2026-03-05)
- [x] M1-6: Add `Seihou.CLI.List` to `seihou-cli.cabal` executable `other-modules` (2026-03-05)
- [x] M1-7: Build — `cabal build all` (2026-03-05)
- [x] M1-8: Manual verification — no-modules and help output correct (2026-03-05)
- [x] M2-1: Add tests for `discoverAllModules` in `seihou-core/test/` (2026-03-05)
- [x] M2-2: Add `List.hs` to `seihou-cli-internal` library exposed modules (2026-03-05)
- [x] M2-3: Create `seihou-cli/test/Seihou/CLI/ListSpec.hs` with unit tests for `formatListOutput` (2026-03-05)
- [x] M2-4: Register test specs in test runners (2026-03-05)
- [x] M2-5: Build and test — `cabal test all` — 509 tests pass (489 core + 20 CLI) (2026-03-05)


## Surprises & Discoveries

- `DiscoveredModule` doesn't derive `Eq` (the `Either ModuleLoadError Module` inside doesn't have `Eq`), so `shouldBe []` fails at compile time. Fixed by using `length result` instead.
  Date: 2026-03-05


## Decision Log

- Decision: Add a `discoverAllModules` function to `seihou-core` rather than implementing directory scanning in the CLI handler.
  Rationale: Module discovery is a core concern. The existing `discoverModule` finds a single module by name; `discoverAllModules` enumerates all modules across search paths. Placing it in `Seihou.Core.Module` keeps the discovery logic co-located and makes it testable independently of the CLI.
  Date: 2026-03-05

- Decision: Load each discovered module to extract metadata (name, description) rather than just listing directory names.
  Rationale: Directory names are not always meaningful (e.g., installed modules may have been renamed). Loading the module gives us the canonical name from `module.dhall` and the description field. Modules that fail to load are still listed with an error message, so the user sees everything.
  Date: 2026-03-05

- Decision: Group output by source with a tag rather than section headers.
  Rationale: A flat list with `(project)`, `(user)`, `(installed)` tags is more compact and scannable than three separate sections. Most users will have few modules. The tag tells them where the module lives without needing headers.
  Date: 2026-03-05

- Decision: Show modules that fail to load with `[error: ...]` instead of silently skipping them.
  Rationale: Silent skipping would hide broken modules. The user should know that a module exists but has a problem (e.g., invalid Dhall). This matches the principle of least surprise.
  Date: 2026-03-05

- Decision: Use plain IO for directory listing (not the Filesystem effect) since this command only reads the filesystem and doesn't need effect-based testing for the IO layer.
  Rationale: The `discoverAllModules` function uses `System.Directory` directly, consistent with how `discoverModule`, `defaultSearchPaths`, and `loadModule` already work in `Seihou.Core.Module`. The pure formatting function `formatListOutput` is tested separately.
  Date: 2026-03-05


## Outcomes & Retrospective

Implementation complete. `seihou list` scans all three search paths, loads each module, and prints a formatted table with name, description, and source tag. Failed modules show an error indicator. The command is read-only and requires no manifest.

- **Core**: `discoverAllModules` in `Seihou.Core.Module` with `DiscoveredModule`/`ModuleSource` types. 5 tests cover discovery, source tagging, error capture, and directory filtering.
- **CLI**: `handleList`/`formatListOutput` in `Seihou.CLI.List`. 7 tests cover empty output, headers, module display, source tags, error indicators, and count summary.
- **Total**: 509 tests pass (489 core + 20 CLI), up from 484 + 13 before this plan.
- No new external dependencies added.
- Smooth implementation with one minor surprise (missing `Eq` instance on `DiscoveredModule`).


## Context and Orientation

Seihou is a composable project scaffolding system. Modules are the central unit — each is a directory containing a `module.dhall` definition file. Modules are discovered from three search paths in priority order:

1. **Project-local**: `.seihou/modules/` relative to the current working directory
2. **User modules**: `~/.config/seihou/modules/` (created by `seihou init`, populated by the user)
3. **Installed modules**: `~/.config/seihou/installed/` (populated by `seihou install`)

### Key existing code

**`seihou-core/src/Seihou/Core/Module.hs`** exports:
- `defaultSearchPaths :: IO [FilePath]` — returns the three search paths
- `discoverModule :: [FilePath] -> ModuleName -> IO (Either ModuleLoadError FilePath)` — finds a single module by name
- `loadModule :: [FilePath] -> ModuleName -> IO (Either ModuleLoadError Module)` — discovers, evaluates, and validates a module

The module discovery pattern: for each search path, look for `<searchPath>/<moduleName>/module.dhall`. A directory is a module candidate if it contains `module.dhall`.

**`seihou-core/src/Seihou/Core/Types.hs`** defines:
- `Module` with fields `moduleName :: ModuleName`, `moduleDescription :: Maybe Text`, `moduleVars :: [VarDecl]`, `moduleDependencies :: [ModuleName]`, etc.
- `ModuleLoadError` with constructors `ModuleNotFound`, `DhallEvalError`, `DhallDecodeError`, `ValidationError`, `MissingSourceFile`

**`seihou-core/src/Seihou/Dhall/Eval.hs`** exports `evalModuleFromFile :: FilePath -> IO (Either ModuleLoadError Module)` which evaluates a `module.dhall` file.

**`seihou-cli/src/Seihou/CLI/Commands.hs`** defines the `Command` ADT. Currently has 9 constructors: `Init`, `Run`, `Vars`, `Install`, `Status`, `Diff`, `NewModule`, `ValidateModule`, `Config`.

**`seihou-cli/src/Main.hs`** dispatches commands via a case expression.

**`seihou-cli/seihou-cli.cabal`** has three components: `library seihou-cli-internal` (private), `executable seihou`, `test-suite seihou-cli-test`.

**`seihou-cli/src/Seihou/CLI/Shared.hs`** exports `shortenHome :: FilePath -> IO Text` for `~/` path abbreviation.


## Plan of Work

### Milestone 1: Implement the list command

This milestone adds `seihou list` as a new subcommand. At the end, `seihou list` scans all search paths, loads each discovered module, and prints a formatted table of available modules with names, descriptions, and source tags.

**Step 1** (M1-1): Add `discoverAllModules` to `seihou-core/src/Seihou/Core/Module.hs`. This function enumerates all module directories across the search paths, attempts to load each one via `evalModuleFromFile` and `validateModule`, and returns a list of results tagged with their source category. Modules that fail to load are included with the error.

Define a result type:

```haskell
data ModuleSource = SourceProject | SourceUser | SourceInstalled
  deriving stock (Eq, Show, Generic)

data DiscoveredModule = DiscoveredModule
  { discoveredResult :: Either ModuleLoadError Module
  , discoveredSource :: ModuleSource
  , discoveredDir :: FilePath
  }
  deriving stock (Show)
```

The function:

```haskell
discoverAllModules :: [FilePath] -> IO [DiscoveredModule]
```

For each search path, list subdirectories that contain `module.dhall`, attempt to evaluate and validate each one, and tag with the source. The three search paths from `defaultSearchPaths` map to `SourceProject`, `SourceUser`, `SourceInstalled` respectively.

**Step 2** (M1-2): Add `List` as a nullary constructor to the `Command` ADT in `Commands.hs`.

**Step 3** (M1-3): Add `command "list" listInfo` to the `commandParser`. Define `listInfo` with `progDesc "List available modules"`.

**Step 4** (M1-4): Create `seihou-cli/src/Seihou/CLI/List.hs` with `handleList :: IO ()` and `formatListOutput :: Bool -> [DiscoveredModule] -> [FilePath] -> Text`.

`handleList`:
1. Get search paths via `defaultSearchPaths`
2. Call `discoverAllModules searchPaths`
3. Call `useColor`, `shortenHome` on each path
4. Format and print

`formatListOutput color modules searchPaths`:
- If no modules: "No modules found.\n\nSearched:\n  <path1>\n  <path2>\n  <path3>\n"
- Otherwise: "Available modules:\n\n" followed by formatted lines, then a count summary

Each module line: `"  <name>  <description>  (<source>)"`
- Name padded to align descriptions
- Description padded to align source tags
- Source tag: `project`, `user`, or `installed`
- For failed modules: name from directory, description is `[error: <brief>]`
- Color: dim for source tags, red for errors

**Step 5** (M1-5): Add `import Seihou.CLI.List (handleList)` and `List -> handleList` in `Main.hs`.

**Step 6** (M1-6): Add `Seihou.CLI.List` to executable `other-modules` in `seihou-cli.cabal`.

**Step 7** (M1-7): Build with `cabal build all`.

**Step 8** (M1-8): Manual test with `seihou list`.

### Milestone 2: Add tests

This milestone adds tests for both the core `discoverAllModules` function and the CLI `formatListOutput` function.

**Step 1** (M2-1): Create `seihou-core/test/Seihou/Core/ListSpec.hs` with tests for `discoverAllModules` using temporary directories containing valid and invalid module.dhall files. Register in `seihou-core/test/Main.hs`.

**Step 2** (M2-2): Add `Seihou.CLI.List` to `seihou-cli-internal` `exposed-modules`.

**Step 3** (M2-3): Create `seihou-cli/test/Seihou/CLI/ListSpec.hs` with tests for `formatListOutput`:
1. "shows no-modules message when list is empty"
2. "shows available modules header"
3. "shows module name and description"
4. "shows source tag in parentheses"
5. "shows error indicator for failed modules"
6. "shows count summary"

**Step 4** (M2-4): Register `ListSpec` in both test runners.

**Step 5** (M2-5): Build and test with `cabal build all && cabal test all`.


## Concrete Steps

**Working directory**: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

**Step 1** (M1-1): Edit `seihou-core/src/Seihou/Core/Module.hs`:
- Add to exports: `discoverAllModules`, `DiscoveredModule(..)`, `ModuleSource(..)`
- Add import: `System.Directory (listDirectory)`
- Add types and function (see Plan of Work above)

**Step 2** (M1-2): Edit `seihou-cli/src/Seihou/CLI/Commands.hs`:
- Add `| List` to `Command` data type

**Step 3** (M1-3): In the same file:
- Add `<> command "list" listInfo` to `commandParser`
- Add `listInfo` definition

**Step 4** (M1-4): Create `seihou-cli/src/Seihou/CLI/List.hs`

**Step 5** (M1-5): Edit `seihou-cli/src/Main.hs`:
- Add import: `import Seihou.CLI.List (handleList)`
- Add case: `List -> handleList`

**Step 6** (M1-6): Edit `seihou-cli/seihou-cli.cabal`:
- Add `Seihou.CLI.List` to executable `other-modules`

**Step 7** (M1-7): Build:
```
cabal build all
```

**Step 8** (M1-8): Manual test:
```
cabal run seihou -- list
```

**Step 9** (M2-1): Create `seihou-core/test/Seihou/Core/ListSpec.hs` and register in `seihou-core/test/Main.hs`.

**Step 10** (M2-2): Edit `seihou-cli/seihou-cli.cabal`:
- Add `Seihou.CLI.List` to `seihou-cli-internal` `exposed-modules`

**Step 11** (M2-3): Create `seihou-cli/test/Seihou/CLI/ListSpec.hs`

**Step 12** (M2-4): Register `ListSpec` in `seihou-cli/test/Main.hs`

**Step 13** (M2-5): Build and test:
```
cabal build all && cabal test all
```


## Validation and Acceptance

### Automated

    cabal test all

All existing tests pass unchanged. New tests verify:
- `discoverAllModules` finds modules in temporary directories, handles missing dirs, handles invalid modules
- `formatListOutput` produces correct output for empty, single, multiple, and error cases

### Manual acceptance

With modules available:
```
seihou list
```
Expected (example):
```
Available modules:

  haskell-base   Haskell project boilerplate   (user)

1 module found (3 sources searched)
```

With no modules:
```
seihou list
```
Expected:
```
No modules found.

Searched:
  .seihou/modules/
  ~/.config/seihou/modules/
  ~/.config/seihou/installed/
```


## Idempotence and Recovery

All steps are safe to repeat. The list command is read-only — it never modifies any files or state. If implementation fails partway, `git checkout` on affected files restores the previous state.


## Interfaces and Dependencies

No new external dependencies.

In `seihou-core/src/Seihou/Core/Module.hs`, the new exports:

```haskell
data ModuleSource = SourceProject | SourceUser | SourceInstalled
  deriving stock (Eq, Show, Generic)

data DiscoveredModule = DiscoveredModule
  { discoveredResult :: Either ModuleLoadError Module
  , discoveredSource :: ModuleSource
  , discoveredDir :: FilePath
  }
  deriving stock (Show)

discoverAllModules :: [FilePath] -> IO [DiscoveredModule]
```

In `seihou-cli/src/Seihou/CLI/List.hs`, the exports:

```haskell
module Seihou.CLI.List
  ( handleList,
    formatListOutput,
  )

handleList :: IO ()

formatListOutput :: Bool -> [DiscoveredModule] -> [Text] -> Text
```

In `seihou-cli/src/Seihou/CLI/Commands.hs`, the new constructor:

```haskell
| List
```
