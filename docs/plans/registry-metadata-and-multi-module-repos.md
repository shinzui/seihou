# Registry Metadata and Multi-Module Repository Support

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

Today, `seihou install <git-url>` assumes every git repository contains exactly one module defined by a `module.dhall` at the repository root. This is limiting: a template author who maintains several related modules (say, `haskell-base`, `nix-flake`, and `cabal-project`) must publish each in a separate repository.

After this change, a single git repository can contain any number of seihou modules. A small metadata file at the repository root, `seihou-registry.dhall`, declares which modules the repo offers and where they live. The CLI discovers this file automatically during install and presents the available modules to the user, who can pick one, several, or all of them. A new `seihou browse <git-url>` command lets users inspect a remote repo's offerings without installing anything.

A user will be able to run:

    seihou browse https://github.com/user/haskell-templates.git

and see a table of modules with names, descriptions, and tags. They can then install selectively:

    seihou install https://github.com/user/haskell-templates.git --module haskell-base
    seihou install https://github.com/user/haskell-templates.git --all

Or, if the repo has no registry file, the current single-module behavior continues unchanged.


## Progress

- [x] M1: Define the `seihou-registry.dhall` schema and Haskell types (2026-03-06)
- [x] M1: Add Dhall decoder for `RegistryEntry` and `Registry` (2026-03-06)
- [x] M1: Write unit tests for registry decoding (valid, missing fields, empty list) (2026-03-06)
- [ ] M2: Add `discoverRegistry` function to detect and parse registry in a cloned repo
- [ ] M2: Add `discoverModulesInRepo` fallback for repos without registry
- [ ] M2: Write unit tests for registry discovery (with registry, without registry, malformed)
- [ ] M3: Update `seihou install` to handle multi-module repos
- [ ] M3: Add `--module` and `--all` flags to install command
- [ ] M3: Interactive module selection when registry exists and no flag given
- [ ] M3: Write integration test for multi-module install
- [ ] M4: Implement `seihou browse <git-url>` command
- [ ] M4: Write integration test for browse command
- [ ] M5: Update `seihou list` to show registry origin for installed modules
- [ ] M5: Update documentation and help text
- [ ] M5: End-to-end manual test with a real multi-module repo


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Use a dedicated `seihou-registry.dhall` file rather than overloading `module.dhall` at the root.
  Rationale: A repo root `module.dhall` already means "this repo IS a single module." Using a distinct filename avoids ambiguity and allows a repo to be both a single module (root `module.dhall`) and a registry (if the author later adds more modules). The registry file is purely additive.
  Date: 2026-03-06

- Decision: Registry is optional; absence means legacy single-module behavior.
  Rationale: Backwards compatibility is non-negotiable. Existing single-module repos must keep working without changes. The CLI detects registry presence and branches accordingly.
  Date: 2026-03-06

- Decision: Use Dhall for the registry file rather than JSON or TOML.
  Rationale: The entire seihou ecosystem uses Dhall for configuration. Keeping registry metadata in Dhall is consistent, allows type-checking, and lets authors use Dhall features (imports, let-bindings) to reduce duplication across entries.
  Date: 2026-03-06

- Decision: Modules in a registry are referenced by relative directory path, not by convention.
  Rationale: Requiring explicit paths in the registry (e.g., `path = "modules/haskell-base"`) rather than inferring from directory structure means authors can organize their repo however they like. A flat layout, a `modules/` subdirectory, or any other structure all work.
  Date: 2026-03-06

- Decision: `seihou browse` clones shallowly to a temp directory, reads registry, then discards.
  Rationale: This matches the existing `seihou install` pattern (shallow clone to temp dir). No persistent state is needed for browsing. Future optimization (e.g., fetching only the registry file via sparse checkout) can be added later without changing the interface.
  Date: 2026-03-06

- Decision: Tags in registry entries are free-form text, not an enum.
  Rationale: Tags serve as a lightweight filtering and discovery aid. Constraining them to a fixed set would limit authors unnecessarily. The CLI can display them but does not need to validate or interpret them beyond string matching.
  Date: 2026-03-06


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Seihou is a composable, type-safe project scaffolding tool. Users define "modules" (template bundles) that generate files in a target project. The system is built in Haskell (GHC 9.12.2, GHC2024) using the `effectful` library for effects, Dhall for configuration, and `optparse-applicative` for CLI parsing.

The repository is a multi-package Cabal workspace with two packages: `seihou-core` (library with all domain logic) and `seihou-cli` (executable with CLI handlers).

Key files and their roles:

`seihou-core/src/Seihou/Core/Types.hs` defines the core domain types. A `Module` has a name (`ModuleName`, a newtype over `Text` matching `[a-z][a-z0-9-]*`), an optional description, variable declarations, exports, prompts, generation steps, shell commands, and dependencies on other modules.

`seihou-core/src/Seihou/Core/Module.hs` handles module discovery and validation. The function `discoverModule` searches a list of directories for a subdirectory containing `module.dhall`. The function `discoverAllModules` enumerates all modules across all search paths, returning `[DiscoveredModule]` where each entry carries the load result (success or error), a `ModuleSource` tag (`SourceProject | SourceUser | SourceInstalled`), and the directory path. The function `validateModule` runs nine validation rules against a decoded module.

`seihou-core/src/Seihou/Dhall/Eval.hs` bridges Haskell and Dhall. The function `evalModuleFromFile` reads a `.dhall` file, evaluates it, and decodes it into a `Module` value. It uses `Dhall.input` with a custom `moduleDecoder`.

`seihou-core/src/Seihou/Core/Install.hs` contains only `parseModuleName`, which extracts a module name from a git URL by taking the last path segment and stripping `.git`.

`seihou-cli/src/Seihou/CLI/Install.hs` implements `handleInstall`. It shallow-clones a git repo to a temp directory, evaluates `module.dhall` at the clone root, validates it, and copies the result (excluding `.git`) to `~/.config/seihou/installed/<name>/`. It assumes exactly one module per repo.

`seihou-cli/src/Seihou/CLI/Commands.hs` defines the CLI command tree using `optparse-applicative`. The `InstallOpts` record has two fields: `installSource :: Text` (the git URL) and `installName :: Maybe Text` (optional name override). The `Command` sum type lists all subcommands: `Init`, `Run`, `Vars`, `Install`, `Status`, `Diff`, `List`, `NewModule`, `ValidateModule`, `Config`.

`seihou-cli/src/Seihou/CLI/List.hs` implements `handleList`, which calls `discoverAllModules` and formats the output as a table showing name, description, and source tag.

Modules are installed to `~/.config/seihou/installed/<name>/` as flat directories. The search path priority is: `.seihou/modules/` (project-local), `~/.config/seihou/modules/` (user), `~/.config/seihou/installed/` (git-installed). Each module directory must contain a `module.dhall` file and typically a `files/` subdirectory with template files.


## Plan of Work

The work is divided into five milestones. Each builds on the previous and is independently verifiable.


### Milestone 1: Registry Schema and Dhall Decoder

This milestone defines the data model for registry metadata and the Dhall decoder that parses it.

A new file `seihou-core/src/Seihou/Core/Registry.hs` will define two types:

`RegistryEntry` represents one module listing in the registry. It has fields: `name :: ModuleName` (the module's name, same rules as existing module names), `path :: FilePath` (relative directory path within the repo, e.g., `"modules/haskell-base"`), `description :: Maybe Text` (human-readable summary), and `tags :: [Text]` (free-form labels like `"haskell"`, `"nix"`, `"starter"`).

`Registry` represents the entire registry file. It has fields: `repoName :: Text` (human-readable name for the collection, e.g., `"Haskell Templates"`), `repoDescription :: Maybe Text` (optional longer description), and `modules :: [RegistryEntry]` (the list of available modules).

The Dhall schema for `seihou-registry.dhall` will look like this:

    { repoName = "Haskell Templates"
    , repoDescription = Some "A collection of Haskell project templates"
    , modules =
      [ { name = "haskell-base"
        , path = "modules/haskell-base"
        , description = Some "Minimal Haskell project with cabal"
        , tags = [ "haskell", "starter" ]
        }
      , { name = "nix-flake"
        , path = "modules/nix-flake"
        , description = Some "Nix flake overlay for Haskell projects"
        , tags = [ "nix", "haskell" ]
        }
      ]
    }

In `seihou-core/src/Seihou/Dhall/Eval.hs`, add two new functions: `registryEntryDecoder` (a `Dhall.Decoder RegistryEntry`) and `registryDecoder` (a `Dhall.Decoder Registry`). Also add `evalRegistryFromFile :: FilePath -> IO (Either ModuleLoadError Registry)` which reads and decodes a `.dhall` file into a `Registry`. The error type `ModuleLoadError` in `seihou-core/src/Seihou/Core/Types.hs` will gain a new constructor `RegistryEvalError Text Text` (file path and error message) so registry-specific failures are distinguishable.

Add `Registry` and `RegistryEntry` to the module's export list. Expose `evalRegistryFromFile` from `Seihou.Dhall.Eval`.

At the end of this milestone, the types exist and a Dhall file like the example above can be decoded into Haskell values. Unit tests in `seihou-core/test/` will verify decoding of a valid registry, a registry with an empty module list, and a malformed registry (missing required field).

To verify, run:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal test seihou-core

All new tests should pass. Existing tests must remain green.


### Milestone 2: Registry Discovery Logic

This milestone adds the logic that detects whether a cloned repo is a multi-module registry or a single module, and extracts the available modules either way.

In `seihou-core/src/Seihou/Core/Registry.hs`, add two functions:

`discoverRegistry :: FilePath -> IO (Maybe Registry)` takes the root of a cloned repo and checks for `seihou-registry.dhall`. If the file exists, it evaluates and decodes it, returning `Just registry` on success. If the file does not exist, it returns `Nothing`. If the file exists but fails to decode, it returns `Nothing` (the caller will handle the error path).

`discoverRepoModules :: FilePath -> IO RepoContents` examines a cloned repo and determines what it offers. The result type `RepoContents` is a sum:

    data RepoContents
      = SingleModule FilePath          -- repo root contains module.dhall
      | MultiModule Registry           -- repo contains seihou-registry.dhall
      | EmptyRepo                      -- neither found

The function first checks for `seihou-registry.dhall`. If found and valid, it returns `MultiModule`. Otherwise it checks for `module.dhall` at the repo root. If found, it returns `SingleModule`. Otherwise `EmptyRepo`.

Add a validation function `validateRegistry :: FilePath -> Registry -> IO [Text]` that checks each registry entry: the `name` field must be a valid module name (reuse `isValidModuleName` from `Seihou.Core.Module`), the `path` must be a relative path without `..`, and the directory at `path` must exist within the repo and contain a `module.dhall` file.

Unit tests will cover: a directory with only `seihou-registry.dhall`, a directory with only `module.dhall`, a directory with both (registry takes precedence), a directory with neither, and a registry whose entry points to a nonexistent path.

To verify:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal test seihou-core


### Milestone 3: Update Install Command for Multi-Module Repos

This milestone changes `seihou install` to handle multi-module repos. The CLI parser and the install handler both need updates.

In `seihou-cli/src/Seihou/CLI/Commands.hs`, extend `InstallOpts` with two new fields:

    data InstallOpts = InstallOpts
      { installSource :: Text
      , installName :: Maybe Text
      , installModules :: [Text]       -- NEW: --module flags (repeatable)
      , installAll :: Bool             -- NEW: --all flag
      }

Add the corresponding `optparse-applicative` parsers: `--module MODULE` (repeatable via `many`, selecting specific modules by name) and `--all` (a switch to install every module in the registry).

In `seihou-cli/src/Seihou/CLI/Install.hs`, rewrite `handleInstall` to follow this logic:

1. Shallow-clone the repo to a temp directory (unchanged).
2. Call `discoverRepoContents` on the clone root.
3. If `SingleModule`: behave exactly as today (validate, copy to installed dir). The `--module` and `--all` flags are ignored with a warning if provided.
4. If `MultiModule registry`:
   a. If `--all` is set, select all entries from the registry.
   b. If one or more `--module` names are given, select matching entries. Error if any name does not match a registry entry.
   c. If neither flag is given, print the registry contents as a numbered list and prompt the user to pick (comma-separated numbers, or `all`). This uses standard `hGetLine stdin` since the interactive prompt system is only for variable prompts during `seihou run`.
   d. For each selected entry: evaluate `module.dhall` at the entry's path, validate, copy to `~/.config/seihou/installed/<entry-name>/`.
5. If `EmptyRepo`: print an error and exit.

The install handler should also store a small metadata file `.seihou-origin.json` inside each installed module directory, recording the source URL and registry name. This will be useful for `seihou list` (Milestone 5) and future update commands. The file has three fields: `sourceUrl` (the git URL), `repoName` (from registry, or null for single-module), and `installedAt` (ISO 8601 timestamp).

Integration test: create a temporary git repo with a `seihou-registry.dhall` pointing to two module subdirectories, run `seihou install <path> --all`, verify both modules appear in `~/.config/seihou/installed/`.

To verify:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal test seihou-cli
    cabal run seihou -- install --help

The help text should show the new `--module` and `--all` flags.


### Milestone 4: Browse Command

This milestone adds `seihou browse <git-url>`, a read-only command that clones a repo, reads its registry (or single module), and prints a summary without installing anything.

In `seihou-cli/src/Seihou/CLI/Commands.hs`, add a new constructor to `Command`:

    | Browse BrowseOpts

    data BrowseOpts = BrowseOpts
      { browseSource :: Text
      , browseTag :: Maybe Text        -- optional --tag filter
      }

Add the subparser under `command "browse"`.

Create `seihou-cli/src/Seihou/CLI/Browse.hs` with `handleBrowse :: BrowseOpts -> IO ()`. The handler:

1. Shallow-clones the repo to a temp directory.
2. Calls `discoverRepoContents`.
3. If `MultiModule registry`: prints the repo name, description, and a formatted table of modules (name, description, tags). If `--tag` is given, filters to entries whose `tags` list contains the given tag.
4. If `SingleModule`: evaluates and prints the single module's name and description.
5. If `EmptyRepo`: prints an error.
6. The temp directory is cleaned up automatically (it is inside `withSystemTempDirectory`).

Expected output for a multi-module repo:

    Haskell Templates
    A collection of Haskell project templates

    Available modules:

      haskell-base   Minimal Haskell project with cabal   [haskell, starter]
      nix-flake      Nix flake overlay for Haskell        [nix, haskell]
      cabal-project  Multi-package cabal workspace        [haskell, cabal]

    3 modules available. Install with:
      seihou install <url> --module <name>
      seihou install <url> --all

To verify:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal run seihou -- browse --help


### Milestone 5: Polish and Integration

This milestone updates `seihou list` to show registry origin, updates help text, and performs end-to-end testing.

In `seihou-cli/src/Seihou/CLI/List.hs`, when formatting installed modules, check for `.seihou-origin.json` in the module directory. If present, include the repo name in the source column, e.g., `(installed: Haskell Templates)` instead of just `(installed)`.

Update the help text for `install` in `Commands.hs` to document multi-module behavior and the new flags.

Update the help text for `browse` with usage examples.

Write an end-to-end test that creates a temporary git repo with a registry, runs `seihou browse`, runs `seihou install --all`, runs `seihou list`, and verifies all modules appear with correct origin metadata.

To verify:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal test
    cabal run seihou -- list


## Concrete Steps

All commands assume a working directory of `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` unless stated otherwise.

Build the project at any point with:

    cabal build all

Run all tests with:

    cabal test all

Run a specific test suite:

    cabal test seihou-core
    cabal test seihou-cli

Run the CLI:

    cabal run seihou -- <command> [args]


## Validation and Acceptance

The feature is accepted when all of the following hold:

1. A git repo containing `seihou-registry.dhall` with two module entries can be browsed:

       seihou browse <url>

   Output shows the repo name, description, and both modules with their tags.

2. The same repo can be installed selectively:

       seihou install <url> --module haskell-base

   Only `haskell-base` appears in `~/.config/seihou/installed/`. The other module is not installed.

3. The same repo can be installed in bulk:

       seihou install <url> --all

   Both modules appear in `~/.config/seihou/installed/`.

4. A repo without `seihou-registry.dhall` (just a root `module.dhall`) still installs correctly via the existing flow:

       seihou install <url>

5. `seihou list` shows installed modules with their registry origin when available.

6. All existing tests continue to pass. No regressions.

7. `seihou install --help` and `seihou browse --help` show accurate, informative help text.


## Idempotence and Recovery

`seihou install` already overwrites an existing installation of the same module name (with a warning). This behavior extends naturally to multi-module installs: each module is installed independently, so re-running `seihou install <url> --all` is safe and idempotent.

`seihou browse` is purely read-only and leaves no persistent state.

If a multi-module install fails partway (e.g., the second of three modules has a validation error), the modules that were already installed remain in place. The user receives an error listing which modules failed and can retry with `--module` targeting specific entries.

The `.seihou-origin.json` metadata file is informational only. If it is missing or corrupt, `seihou list` falls back to showing `(installed)` without the registry name.


## Interfaces and Dependencies

All new code uses existing dependencies: `dhall` (for Dhall evaluation and decoding), `optparse-applicative` (for CLI parsing), `aeson` (for `.seihou-origin.json` serialization), `directory` and `process` (for filesystem and git operations), and `temporary` (for temp directories).

In `seihou-core/src/Seihou/Core/Registry.hs`, define:

    data RegistryEntry = RegistryEntry
      { name        :: ModuleName
      , path        :: FilePath
      , description :: Maybe Text
      , tags        :: [Text]
      }

    data Registry = Registry
      { repoName        :: Text
      , repoDescription :: Maybe Text
      , modules         :: [RegistryEntry]
      }

    data RepoContents
      = SingleModule FilePath
      | MultiModule Registry
      | EmptyRepo

    discoverRepoContents :: FilePath -> IO RepoContents
    validateRegistry     :: FilePath -> Registry -> IO [Text]

In `seihou-core/src/Seihou/Dhall/Eval.hs`, add:

    evalRegistryFromFile :: FilePath -> IO (Either ModuleLoadError Registry)

In `seihou-core/src/Seihou/Core/Types.hs`, extend `ModuleLoadError`:

    | RegistryEvalError Text Text

In `seihou-cli/src/Seihou/CLI/Commands.hs`, extend:

    data InstallOpts = InstallOpts
      { installSource  :: Text
      , installName    :: Maybe Text
      , installModules :: [Text]
      , installAll     :: Bool
      }

    data BrowseOpts = BrowseOpts
      { browseSource :: Text
      , browseTag    :: Maybe Text
      }

    -- Command gains: | Browse BrowseOpts

In `seihou-cli/src/Seihou/CLI/Browse.hs`, define:

    handleBrowse :: BrowseOpts -> IO ()

In `seihou-cli/src/Seihou/CLI/Install.hs`, the existing `handleInstall` is rewritten to use `discoverRepoContents` and handle the three cases.
