---
slug: module-version-comparison
title: "Add module version tracking and outdated detection"
kind: exec-plan
created_at: 2026-03-16T03:46:01Z
---


# Add module version tracking and outdated detection

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, module authors can declare a version string in their `module.dhall` files and in registry entries. When a user installs a module, seihou records which version was installed. The user can then run `seihou outdated` to compare their installed modules against their remote registries and see which modules have newer versions available. This closes the gap between "I installed this module months ago" and "has the author published updates?"

The user-visible behavior: running `seihou outdated` prints a table showing each installed module, its installed version, and the latest version available in its source registry. Modules without version information are shown as "unversioned." The `seihou list` command also gains a version column for installed modules.


## Progress

- [x] M1: Add `version` field to `Module` type, Dhall schema, and decoder (2026-03-15)
- [x] M1: Add `version` field to `RegistryEntry` type and decoder (2026-03-15)
- [x] M1: Add `version` field to `OriginMeta` (write) and `OriginInfo` (read) (2026-03-15)
- [x] M1: Update `seihou list` to display version for installed modules (2026-03-15)
- [x] M1: Update existing tests for new optional fields (2026-03-15)
- [x] M1: Verify build and tests pass (2026-03-15)
- [x] M2: Add `Version` type with parsing and `Ord` instance (2026-03-15)
- [x] M2: Add version comparison logic (2026-03-15)
- [x] M2: Unit tests for version parsing and comparison (2026-03-15)
- [x] M3: Add `Outdated` command variant and CLI parser (2026-03-15)
- [x] M3: Implement `handleOutdated` — clone, compare, render (2026-03-15)
- [x] M3: Wire into `Main.hs` dispatcher (2026-03-15)
- [x] M3: Add CLI help text (2026-03-15)
- [x] M3: End-to-end validation with live installed modules (2026-03-15)


## Surprises & Discoveries

- Adding `version :: Maybe Text` to `Module` caused an ambiguous record update in `ManifestTypesSpec.hs` line 136 where `(emptyManifest fixedTime) {version = 99}` was ambiguous between `Module.version` and `Manifest.version` under `DuplicateRecordFields`. Fixed by using explicit `Manifest` constructor.
- `Validate.hs` had a `dummyModule` constructor that also needed the new field.
- `BrowseFormatSpec.hs` in seihou-cli tests also constructs `RegistryEntry` values and needed updating.
- Inline Dhall strings in `EvalSpec.hs` and `ListSpec.hs` needed the `version = None Text` field added.


## Decision Log

- Decision: Use simple text-based version strings (e.g. "1.2.0") rather than Haskell's `Data.Version` or PVP.
  Rationale: Module authors are not necessarily Haskell developers. A simple `major.minor.patch` scheme is universally understood and keeps the Dhall schema approachable. The version field is `Optional Text` in Dhall, so existing modules without versions continue to work unchanged. Internally, seihou parses these into a structured `Version` type for ordered comparison.
  Date: 2026-03-15

- Decision: The `version` field is optional everywhere — on `Module`, `RegistryEntry`, and `OriginMeta`.
  Rationale: Backward compatibility. Existing modules and registries must continue to work without modification. Unversioned modules are shown as "unversioned" in output and are always considered "up to date" (since there is no basis for comparison).
  Date: 2026-03-15

- Decision: `seihou outdated` re-clones remote registries at check time rather than maintaining a local cache.
  Rationale: Keeps the architecture simple and consistent with how `browse` and `install` already work (shallow clone into temp dir). A caching layer can be added later if performance becomes a concern. The shallow clone is fast (--depth 1) and the temp directory is cleaned up automatically.
  Date: 2026-03-15

- Decision: Version comparison uses simple numeric ordering on dotted segments (e.g. 1.2.3 < 1.10.0), not lexicographic.
  Rationale: Lexicographic ordering produces wrong results ("1.10.0" < "1.2.0"). Parsing into `[Natural]` and using list comparison gives correct semantic versioning behavior.
  Date: 2026-03-15

- Decision: Do not add an `upgrade` command in this plan.
  Rationale: Upgrade semantics (what happens to user modifications, how to handle breaking changes between versions) are complex. This plan focuses on version tracking and outdated detection. A future plan can build `seihou upgrade` on top of this foundation. For now, the user runs `seihou install <url>` to reinstall, which already overwrites the installed module.
  Date: 2026-03-15


## Outcomes & Retrospective

All three milestones completed in a single session:

- M1: Added optional `version :: Maybe Text` to Module, RegistryEntry, OriginMeta/OriginInfo. Updated Dhall schema, decoders, scaffold, install handler, list handler, and all 39 affected files. All 568+48 tests pass.
- M2: Created `Seihou.Core.Version` with `Version` newtype, custom `Eq`/`Ord` (trailing-zero padding), `parseVersion`, `renderVersion`. 18 new tests, all pass.
- M3: Added `seihou outdated` command with `OutdatedOpts`, `handleOutdated`, CLI parser, and help text. Handles single-module and multi-module registries, unreachable sources, JSON output, and color-coded table rendering. Verified live against 3 installed modules.

The implementation followed the plan closely. No new dependencies required. The `version` field is backward compatible — existing modules without it continue to work unchanged.


## Context and Orientation

Seihou is a composable project scaffolding tool. Users write module definitions in Dhall (a typed configuration language) and run them to generate project files. Modules can be shared via git repositories, either as single-module repos (containing a `module.dhall` at the root) or multi-module registries (containing a `seihou-registry.dhall` that lists multiple modules).

The codebase is a Haskell workspace with two packages: `seihou-core` (library) and `seihou-cli` (executable). It uses `effectful-core` for effects and `optparse-applicative` for CLI parsing. Tests use `hspec`.

Key files and types involved in this change:

**Module type** — `seihou-core/src/Seihou/Core/Types.hs` line 178. The `Module` record is the central data structure. It currently has fields: `name`, `description`, `vars`, `exports`, `prompts`, `steps`, `commands`, `dependencies`. We will add an optional `version` field.

**Module Dhall schema** — `schema/Module.dhall` line 35. The Dhall type definition for `Module`. We will add `version : Optional Text`.

**Module decoder** — `seihou-core/src/Seihou/Dhall/Eval.hs` line 103. The `moduleDecoder` function uses applicative-style Dhall record decoding to parse `module.dhall` files into `Module` values. We will add a field for `version`.

**Registry types** — `seihou-core/src/Seihou/Core/Registry.hs` line 17. `RegistryEntry` has `name`, `path`, `description`, `tags`. We will add an optional `version` field. The `registryEntryDecoder` at `seihou-core/src/Seihou/Dhall/Eval.hs` line 320 must be updated to decode it.

**Origin metadata** — `seihou-cli/src/Seihou/CLI/Install.hs` line 283. `OriginMeta` is written to `.seihou-origin.json` when a module is installed. Currently stores `sourceUrl`, `repoName`, `installedAt`. We will add `version`. The corresponding read type `OriginInfo` is at `seihou-cli/src/Seihou/CLI/List.hs` line 21.

**Install handler** — `seihou-cli/src/Seihou/CLI/Install.hs` line 41. `handleInstall` clones a git repo, discovers its contents, validates modules, and copies them to `~/.config/seihou/installed/<name>/`. After installation, it writes origin metadata. We will extend it to include the version in origin metadata.

**List handler** — `seihou-cli/src/Seihou/CLI/List.hs` line 29. `handleList` discovers all modules from search paths and displays them with origin info. We will add a version column.

**Browse handler** — `seihou-cli/src/Seihou/CLI/Browse.hs` line 21. `handleBrowse` clones a remote repo and displays its contents without installing. We will reuse its clone-and-discover pattern for the outdated command.

**CLI commands** — `seihou-cli/src/Seihou/CLI/Commands.hs` line 33. The `Command` ADT lists all CLI commands. We will add `Outdated OutdatedOpts`.

**Main dispatcher** — `seihou-cli/src/Main.hs` line 23. Dispatches parsed commands to handlers. We will add a case for `Outdated`.

**Search paths** — Modules are discovered from three locations: `.seihou/modules/` (project-local), `~/.config/seihou/modules/` (user), `~/.config/seihou/installed/` (installed from remote). The outdated command only checks modules from the installed search path.


## Plan of Work

The work is organized into three milestones. The first adds the version field throughout the data model without changing any user-facing behavior beyond what `seihou list` displays. The second adds a `Version` type with parsing and comparison. The third adds the `seihou outdated` command.


### Milestone 1: Version field in data model

This milestone adds an optional `version` field to `Module`, `RegistryEntry`, and `OriginMeta`, along with the Dhall schema change and decoder updates. At the end, existing modules continue to work unchanged, and `seihou list` shows version information for installed modules that have it.

**Step 1.1: Add `version` to `Module` in `seihou-core/src/Seihou/Core/Types.hs`.**

Add `version :: Maybe Text` as the second field of the `Module` record (after `name`, before `description`). Update the export list if needed (it already exports `Module (..)`).

    data Module = Module
      { name :: ModuleName,
        version :: Maybe Text,
        description :: Maybe Text,
        ...
      }

**Step 1.2: Update the Dhall schema in `schema/Module.dhall`.**

Add `version : Optional Text` to the `Module` record type, after `name`.

    let Module =
          { name : Text
          , version : Optional Text
          , description : Optional Text
          ...
          }

**Step 1.3: Update `moduleDecoder` in `seihou-core/src/Seihou/Dhall/Eval.hs`.**

Add `<*> field "version" (maybe strictText)` after the `name` field line.

    moduleDecoder :: Decoder Module
    moduleDecoder =
      record
        ( Module
            <$> field "name" moduleNameDecoder
            <*> field "version" (maybe strictText)
            <*> field "description" (maybe strictText)
            ...
        )

**Step 1.4: Add `version` to `RegistryEntry` in `seihou-core/src/Seihou/Core/Registry.hs`.**

Add `version :: Maybe Text` after `name`.

    data RegistryEntry = RegistryEntry
      { name :: ModuleName,
        version :: Maybe Text,
        path :: FilePath,
        ...
      }

**Step 1.5: Update `registryEntryDecoder` in `seihou-core/src/Seihou/Dhall/Eval.hs`.**

Add `<*> field "version" (maybe strictText)` after the `name` field.

    registryEntryDecoder :: Decoder RegistryEntry
    registryEntryDecoder =
      record
        ( RegistryEntry
            <$> field "name" moduleNameDecoder
            <*> field "version" (maybe strictText)
            <*> field "path" string
            ...
        )

**Step 1.6: Add `version` to `OriginMeta` in `seihou-cli/src/Seihou/CLI/Install.hs`.**

Add `version :: Maybe Text` to the `OriginMeta` record and its `ToJSON` instance. Update the two call sites that construct `OriginMeta` values: `installModuleDir` (line 277-280) must now pass the module's version. This means `installModuleDir` needs to receive the version, which means `installSingleModule` and `installRegistryEntry` must pass it through.

The signature of `installModuleDir` changes to accept an additional `Maybe Text` for version:

    installModuleDir :: FilePath -> String -> Text -> Maybe Text -> Maybe Text -> IO ()
    installModuleDir moduleDir name source registryName moduleVersion = do
      ...
      let origin = OriginMeta source registryName (T.pack (iso8601Show now)) moduleVersion
      ...

In `installSingleModule` (line 116), pass `modul.version`:

    installModuleDir rootDir name source registryName modul.version

In `installRegistryEntry` (line 259), the version can come from the registry entry or from the decoded module. Prefer the registry entry version since it is the authoritative source for multi-module repos:

    let ver = entry.version <|> modul.version
    installModuleDir moduleDir name source (Just repoName) ver

**Step 1.7: Add `version` to `OriginInfo` in `seihou-cli/src/Seihou/CLI/List.hs`.**

Add `originVersion :: Maybe Text` and update the `FromJSON` instance:

    data OriginInfo = OriginInfo
      { originRepoName :: Maybe Text,
        originVersion :: Maybe Text
      }

    instance FromJSON OriginInfo where
      parseJSON = withObject "OriginInfo" $ \v ->
        OriginInfo <$> v .:? "repoName" <*> v .:? "version"

**Step 1.8: Update `seihou list` to show version.**

In `seihou-cli/src/Seihou/CLI/List.hs`, update the `sourceLabelWithOrigin` function to include version in the display. When an installed module has version info, show it:

    sourceLabelWithOrigin SourceInstalled Nothing Nothing = "installed"
    sourceLabelWithOrigin SourceInstalled (Just rn) Nothing = "installed: " <> rn
    sourceLabelWithOrigin SourceInstalled (Just rn) (Just v) = "installed: " <> rn <> " v" <> v
    sourceLabelWithOrigin SourceInstalled Nothing (Just v) = "installed v" <> v

This requires threading the version through `toEntryWithOrigin`.

**Step 1.9: Update test fixtures and tests.**

Any test that constructs `Module` values directly must now provide the `version` field (typically `Nothing`). Any test that constructs `RegistryEntry` values must also include `version`. Search for `Module {` and `RegistryEntry {` patterns in test files to find all sites. The Dhall test fixtures under `seihou-core/test/` that contain `module.dhall` examples must add `version = None Text` to remain valid.

**Verification:** Run `cabal build all` and `cabal test all` from the repository root. All tests should pass. Run `seihou list` in a project with installed modules; the output should now show version info for modules whose `module.dhall` declares one.


### Milestone 2: Version parsing and comparison

This milestone introduces a `Version` type that can be parsed from text strings and compared with proper numeric ordering. This is the foundation for the outdated command.

**Step 2.1: Create `seihou-core/src/Seihou/Core/Version.hs`.**

Define a `Version` newtype wrapping `[Natural]` with `Eq`, `Ord`, and `Show` instances. The `Ord` instance should compare segment-by-segment, treating missing trailing segments as zero (so "1.2" equals "1.2.0").

    module Seihou.Core.Version
      ( Version (..),
        parseVersion,
        renderVersion,
      )
    where

    import Data.Text qualified as T
    import Numeric.Natural (Natural)
    import Seihou.Prelude

    newtype Version = Version { segments :: [Natural] }
      deriving stock (Show, Generic)

    instance Eq Version where
      Version a == Version b = normalize a == normalize b

    instance Ord Version where
      compare (Version a) (Version b) = compare (normalize a) (normalize b)

    normalize :: [Natural] -> [Natural]
    normalize xs =
      let len = max (length xs) 0
          padded = xs ++ replicate (3 - len) 0
       in padded

The `normalize` function is actually not quite right for arbitrary lengths. A better approach: pad both lists to the same length with zeros, then compare element-wise. This is what the derived `Ord` for lists already does if both lists have the same length. So:

    instance Ord Version where
      compare (Version a) (Version b) =
        let maxLen = max (length a) (length b)
            pad xs = xs ++ replicate (maxLen - length xs) 0
         in compare (pad a) (pad b)

Provide a parser:

    parseVersion :: Text -> Maybe Version
    parseVersion t =
      let parts = T.splitOn "." t
       in case traverse (readNatural . T.unpack) parts of
            Just ns@(_ : _) -> Just (Version ns)
            _ -> Nothing

    readNatural :: String -> Maybe Natural
    readNatural s = case reads s of
      [(n, "")] | n >= 0 -> Just (fromIntegral (n :: Integer))
      _ -> Nothing

    renderVersion :: Version -> Text
    renderVersion (Version ns) = T.intercalate "." (map (T.pack . show) ns)

**Step 2.2: Add `Seihou.Core.Version` to `seihou-core.cabal`.**

Add the module to the `exposed-modules` list in `seihou-core.cabal`.

**Step 2.3: Write tests in `seihou-core/test/Seihou/Core/VersionSpec.hs`.**

Test cases:
- `parseVersion "1.0.0"` produces `Just (Version [1,0,0])`
- `parseVersion "1.2"` produces `Just (Version [1,2])`
- `parseVersion ""` produces `Nothing`
- `parseVersion "abc"` produces `Nothing`
- `parseVersion "1.2.3.4"` works (four segments)
- `Version [1,2,0] == Version [1,2]` is `True`
- `Version [1,2] < Version [1,10]` is `True`
- `Version [2,0] > Version [1,99,99]` is `True`
- `renderVersion (Version [1,2,3])` produces `"1.2.3"`

**Step 2.4: Register the test module.**

Add `Seihou.Core.VersionSpec` to the test suite's module list in `seihou-core.cabal` or the test driver.

**Verification:** Run `cabal test seihou-core`. The new version tests should pass alongside all existing tests.


### Milestone 3: The `seihou outdated` command

This milestone adds the `seihou outdated` command that compares installed module versions against their remote registries.

**Step 3.1: Add `OutdatedOpts` and `Outdated` to the `Command` type in `seihou-cli/src/Seihou/CLI/Commands.hs`.**

    data OutdatedOpts = OutdatedOpts
      { outdatedJson :: Bool
      }
      deriving stock (Eq, Show, Generic)

Add `Outdated OutdatedOpts` to the `Command` ADT. Add the export. Add the parser:

    outdatedInfo :: ParserInfo Command
    outdatedInfo =
      info
        (outdatedParser <**> helper)
        ( fullDesc
            <> progDesc "Check installed modules for newer versions"
            <> footerDoc (Just outdatedFooter)
        )

    outdatedParser :: Parser Command
    outdatedParser =
      fmap Outdated $
        OutdatedOpts
          <$> switch (long "json" <> help "Output as JSON")

Wire into `commandParser`:

    <> command "outdated" outdatedInfo

Add help text in the footer doc:

    outdatedFooter :: Doc
    outdatedFooter =
      vsep
        [ pretty ("Checks each installed module's source registry for a newer version." :: String),
          pretty ("Modules without version information are shown as 'unversioned'." :: String),
          pretty ("Only modules installed via 'seihou install' are checked." :: String),
          line,
          pretty ("Example:" :: String),
          indent 2 $ pretty ("seihou outdated" :: String)
        ]

**Step 3.2: Create `seihou-cli/src/Seihou/CLI/Outdated.hs`.**

This is the main handler. The algorithm:

1. Discover all installed modules (from the installed search path only).
2. Read each module's `.seihou-origin.json` to get `sourceUrl`, `repoName`, and `version`.
3. Group installed modules by `sourceUrl` (to avoid cloning the same repo multiple times).
4. For each unique source URL, shallow-clone into a temp directory and discover its contents.
5. For each installed module from that source, find the matching entry in the cloned registry (by module name) and compare versions.
6. Render a table of results.

The output format for each module:

    Module          Installed    Available    Status
    haskell-base    1.0.0        1.2.0        outdated
    nix-flake       0.3.0        0.3.0        up to date
    cabal-setup     (none)       1.0.0        unversioned
    custom-mod      (none)       (none)       unversioned

A module is "outdated" when its installed version is strictly less than the registry version. A module is "up to date" when the versions are equal or the installed version is newer. A module is "unversioned" when either the installed or remote version is missing.

If the remote clone fails (network error, repo deleted, etc.), the module is shown with status "unreachable" and the available version as "?".

    module Seihou.CLI.Outdated
      ( handleOutdated,
      )
    where

    import Data.Map.Strict qualified as Map
    import Data.Text qualified as T
    import Data.Text.IO qualified as TIO
    import Seihou.CLI.Commands (OutdatedOpts (..))
    import Seihou.CLI.Style (dim, green, red, yellow, useColor)
    import Seihou.Core.Install (parseModuleName)
    import Seihou.Core.Module (DiscoveredModule (..), ModuleSource (..), defaultSearchPaths, discoverAllModules)
    import Seihou.Core.Registry (Registry (..), RegistryEntry (..), RepoContents (..), discoverRepoContents)
    import Seihou.Core.Types (ModuleName (..))
    import Seihou.Core.Version (Version, parseVersion, renderVersion)
    import Seihou.Dhall.Eval (evalModuleFromFile, evalRegistryFromFile)
    import Seihou.Prelude
    import System.IO.Temp (withSystemTempDirectory)
    import System.Process (readProcessWithExitCode)
    import System.Exit (ExitCode (..))
    ...

The key data structures for results:

    data OutdatedStatus
      = UpToDate
      | Outdated
      | Unversioned
      | Unreachable

    data OutdatedEntry = OutdatedEntry
      { moduleName :: Text,
        installedVersion :: Maybe Text,
        availableVersion :: Maybe Text,
        status :: OutdatedStatus
      }

The `handleOutdated` function ties it all together. It reads origin metadata from each installed module directory's `.seihou-origin.json`, groups by source URL, clones each unique URL, discovers the registry contents, matches modules by name, compares versions, and renders the table.

For matching: in a `MultiModule` registry, match by `RegistryEntry.name`. In a `SingleModule` repo, the entire repo is the module — match if the installed module name matches the repo-derived name (from `parseModuleName`). Use the module's `version` field from its `module.dhall` for single-module repos, since there is no registry entry.

**Step 3.3: Register the module in `seihou-cli.cabal`.**

Add `Seihou.CLI.Outdated` to `other-modules`.

**Step 3.4: Wire into `Main.hs`.**

Add the import and dispatch case:

    import Seihou.CLI.Outdated (handleOutdated)
    ...
    Outdated outdatedOpts ->
      handleOutdated outdatedOpts

**Step 3.5: Update `schema/Module.dhall` examples and the `new-module` scaffold.**

Check `seihou-cli/src/Seihou/CLI/NewModule.hs` for the template that generates new `module.dhall` files. Add `version = None Text` to the scaffold so new modules are created with the field present but empty.

**Verification:** Build with `cabal build all` and run `cabal test all`. Then manually test:

1. Create a test module with `version = Some "1.0.0"` in its `module.dhall`.
2. Create a git repo containing it, push to a local bare repo.
3. Install it with `seihou install <path-to-bare-repo>`.
4. Update the module's version to "1.1.0" in the git repo and commit.
5. Run `seihou outdated`. It should show the module as outdated with installed=1.0.0 and available=1.1.0.
6. Run `seihou list`. The installed module should show its version.


## Concrete Steps

All commands are run from the repository root at `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

Build after each milestone:

    cabal build all

Run tests after each milestone:

    cabal test all

Expected output: all tests pass. If new tests are added, they should appear in the test output.

For manual testing of the outdated command (Milestone 3), create a temporary git repo:

    mkdir /tmp/test-seihou-registry && cd /tmp/test-seihou-registry
    git init --bare

    mkdir /tmp/test-module && cd /tmp/test-module
    git init

Create a `module.dhall` with version "1.0.0", commit, push to the bare repo. Install with `seihou install /tmp/test-seihou-registry`. Then update the module.dhall version to "1.1.0", commit, push. Run `seihou outdated` from any directory.

Expected output:

    Checking installed modules for updates...
      Cloning source-repo...

    Module          Installed    Available    Status
    test-module     1.0.0        1.1.0        outdated

    1 module checked, 1 outdated.


## Validation and Acceptance

**Milestone 1 acceptance:**
- `cabal build all` succeeds with no warnings related to the new fields.
- `cabal test all` passes (all existing tests updated for the new optional field).
- An existing `module.dhall` without a `version` field still loads correctly (backward compatible).
- A `module.dhall` with `version = Some "1.0.0"` loads and the version is preserved.
- `seihou list` shows version for installed modules that have one.

**Milestone 2 acceptance:**
- `cabal test seihou-core` passes, including the new `VersionSpec` tests.
- `parseVersion "1.2.3"` returns `Just (Version [1,2,3])`.
- `Version [1,2] < Version [1,10]` is `True` (numeric, not lexicographic).
- `Version [1,2,0] == Version [1,2]` is `True` (trailing zeros ignored).

**Milestone 3 acceptance:**
- `seihou outdated` runs without error when no installed modules exist (prints "No installed modules found.").
- `seihou outdated` correctly identifies outdated modules against a test registry.
- `seihou outdated` handles unreachable registries gracefully (prints "unreachable" status, does not crash).
- `seihou outdated --json` produces valid JSON output.
- `seihou --help` includes the outdated command in the command list.


## Idempotence and Recovery

All changes in Milestone 1 and 2 are additive — new fields are `Maybe` types defaulting to `Nothing`. Existing Dhall files without `version` continue to decode correctly because the Dhall decoder uses `maybe strictText` which handles the absent field.

The outdated command clones into temporary directories that are cleaned up automatically via `withSystemTempDirectory`. If a clone fails, the error is caught and the module is marked "unreachable" — the command continues checking other modules. The command is read-only; it never modifies installed modules or the manifest.

Re-running `seihou install` for a module that is already installed overwrites the previous installation (the existing behavior at `Install.hs` line 270-272), and the new `.seihou-origin.json` will include the version from the newly installed module.


## Interfaces and Dependencies

No new library dependencies are required. The `Version` type uses `Numeric.Natural` from `base`.

**New module:** `seihou-core/src/Seihou/Core/Version.hs`

    parseVersion :: Text -> Maybe Version
    renderVersion :: Version -> Text

**New module:** `seihou-cli/src/Seihou/CLI/Outdated.hs`

    handleOutdated :: OutdatedOpts -> IO ()

**Modified types:**

In `seihou-core/src/Seihou/Core/Types.hs`:

    data Module = Module
      { name :: ModuleName,
        version :: Maybe Text,
        ...
      }

In `seihou-core/src/Seihou/Core/Registry.hs`:

    data RegistryEntry = RegistryEntry
      { name :: ModuleName,
        version :: Maybe Text,
        ...
      }

In `seihou-cli/src/Seihou/CLI/Install.hs`:

    data OriginMeta = OriginMeta
      { sourceUrl :: Text,
        repoName :: Maybe Text,
        installedAt :: Text,
        version :: Maybe Text
      }

    installModuleDir :: FilePath -> String -> Text -> Maybe Text -> Maybe Text -> IO ()

In `seihou-cli/src/Seihou/CLI/List.hs`:

    data OriginInfo = OriginInfo
      { originRepoName :: Maybe Text,
        originVersion :: Maybe Text
      }

In `seihou-cli/src/Seihou/CLI/Commands.hs`:

    data OutdatedOpts = OutdatedOpts { outdatedJson :: Bool }
    -- Added to Command ADT: | Outdated OutdatedOpts
