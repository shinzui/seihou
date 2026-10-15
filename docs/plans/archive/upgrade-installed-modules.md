---
slug: upgrade-installed-modules
title: "Add seihou upgrade command for installed modules"
kind: exec-plan
created_at: 2026-03-16T04:24:39Z
---


# Add seihou upgrade command for installed modules

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, a user who has installed modules via `seihou install` can upgrade them to the latest version available from their source repository by running `seihou upgrade`. Today, if a module author publishes version 1.2.0 and the user has 1.0.0 installed, the only way to update is to re-run `seihou install <url>`, which requires remembering the original URL. The upgrade command automates this: it reads each installed module's `.seihou-origin.json` (which already records the source URL and installed version), clones the source, compares versions, and replaces the local copy with the newer one.

The user-visible behavior: running `seihou upgrade` checks all installed modules and upgrades any that have a newer version available. Running `seihou upgrade <module-name>` upgrades only the named module. A `--dry-run` flag shows what would be upgraded without making changes. After upgrading, the user sees a summary table showing each module's old version, new version, and status.

This plan builds on the version tracking infrastructure from `docs/plans/module-version-comparison.md`, which added the `Version` type, `version` fields on `Module`, `RegistryEntry`, and `OriginMeta`, and the `seihou outdated` command. The upgrade command reuses the same clone-and-discover pattern and version comparison logic.


## Progress

- [x] M1: Add `UpgradeOpts` and `Upgrade` to Command ADT in `seihou-cli/src/Seihou/CLI/Commands.hs` (2026-03-15)
- [x] M1: Add `upgradeParser`, `upgradeInfo`, and CLI help text (2026-03-15)
- [x] M1: Wire `upgrade` into `commandParser` (2026-03-15)
- [x] M1: Add `Upgrade UpgradeOpts` case to `seihou-cli/src/Main.hs` dispatcher (2026-03-15)
- [x] M1: Export `installModuleDir`, `cloneRepo`, and `copyDirectoryRecursive` from `seihou-cli/src/Seihou/CLI/Install.hs` (2026-03-15)
- [x] M1: Create `seihou-cli/src/Seihou/CLI/Upgrade.hs` with `handleUpgrade` (2026-03-15)
- [x] M1: Register `Seihou.CLI.Upgrade` in `seihou-cli/seihou-cli.cabal` (2026-03-15)
- [x] M1: Build and verify `seihou upgrade --help` works (2026-03-15)
- [x] M2: Implement full upgrade logic in `handleUpgrade` (2026-03-15)
- [x] M2: Build and run `cabal test all` — all 586 tests pass (2026-03-15)
- [x] M2: Manual end-to-end test with installed modules — unversioned modules correctly skipped, --dry-run/--json/nonexistent-module all work (2026-03-15)


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: The upgrade command replaces the entire installed module directory rather than attempting a merge or patch.
  Rationale: Installed modules live at `~/.config/seihou/installed/<name>/` and are treated as read-only copies of remote content. The existing `seihou install` already overwrites without merging (see `Install.hs` line 272-274). Users do not customize installed modules in-place; they fork into `.seihou/modules/` or `~/.config/seihou/modules/` for customization. A full replacement is simple, safe, and consistent with install semantics.
  Date: 2026-03-15

- Decision: Reuse existing functions from `Install.hs` (`installModuleDir`, `cloneRepo`, `copyDirectoryRecursive`) rather than duplicating them.
  Rationale: These functions already handle directory copying (excluding `.git`), origin metadata writing, and shallow cloning. Exporting them from `Install.hs` keeps the upgrade handler thin and avoids divergence.
  Date: 2026-03-15

- Decision: The upgrade command validates the new module before replacing the old one.
  Rationale: If the remote module has become invalid (broken `module.dhall`, missing source files), upgrading to it would leave the user with a broken module. The command validates first and skips the upgrade with an error message if validation fails, preserving the existing working installation.
  Date: 2026-03-15

- Decision: Modules without version information are skipped during upgrade with a "skipped (unversioned)" status.
  Rationale: Without version information, there is no way to determine whether the remote version is newer. The user can use `seihou install <url>` to force-reinstall. This is consistent with how `seihou outdated` treats unversioned modules.
  Date: 2026-03-15

- Decision: `--dry-run` reuses the outdated-style comparison table without performing any file operations.
  Rationale: The outdated command already has the clone-compare-render pipeline. Dry-run is effectively "outdated with upgrade intent," showing what would change. This avoids duplicating the comparison logic.
  Date: 2026-03-15

- Decision: Do not add a `--force` flag in this plan.
  Rationale: Force-upgrading (ignoring version comparison, upgrading unversioned modules) adds complexity. Users who want this can run `seihou install <url>` directly. A future plan can add `--force` if demand arises.
  Date: 2026-03-15


## Outcomes & Retrospective

Both milestones completed successfully on 2026-03-15. The upgrade command follows the same clone-discover-compare pattern as `seihou outdated` and reuses `installModuleDir` from Install.hs for the actual replacement. All 586 existing tests pass. Manual testing confirmed: unversioned modules are skipped, `--dry-run` previews without changes, `--json` produces valid JSON, and nonexistent module names exit with failure.


## Context and Orientation

Seihou is a composable project scaffolding tool. Users write module definitions in Dhall (a typed configuration language) and run them to generate project files. Modules can be shared via git repositories, either as single-module repos (containing a `module.dhall` at the root) or multi-module registries (containing a `seihou-registry.dhall` that lists multiple modules).

The codebase is a Haskell workspace with two packages: `seihou-core` (library at `seihou-core/`) and `seihou-cli` (executable at `seihou-cli/`). It uses GHC 9.12.2 with GHC2024, `effectful-core` for effects, and `optparse-applicative` for CLI parsing. Tests use `hspec`. Extensions `OverloadedRecordDot`, `DuplicateRecordFields`, and `NoFieldSelectors` are enabled project-wide, so record access uses dot syntax (e.g., `module.version`).

Key files and types involved in this change:

**Module installation** — `seihou-cli/src/Seihou/CLI/Install.hs`. The `handleInstall` function is the entry point. It calls `cloneRepo` (line 75) to shallow-clone a git repository into a temp directory, `discoverRepoContents` to determine whether it is a single-module or multi-module repo, validates the module, and calls `installModuleDir` (line 266) to copy the module files to `~/.config/seihou/installed/<name>/` and write `.seihou-origin.json`. The `OriginMeta` type (line 285) stores `sourceUrl`, `repoName`, `installedAt`, and `version`. Currently, `installModuleDir`, `cloneRepo`, and `copyDirectoryRecursive` are not exported; they must be exported for the upgrade handler to reuse them.

**Outdated detection** — `seihou-cli/src/Seihou/CLI/Outdated.hs`. The `handleOutdated` function discovers installed modules, reads their `.seihou-origin.json`, groups by source URL, clones each unique source, and compares versions. It defines its own `OriginInfo` type (line 60) with `sourceUrl`, `repoName`, and `version` fields, decoded from JSON. The `compareVersions` function (line 176) takes two `Maybe Text` values and returns an `OutdatedStatus`. The upgrade handler will import and reuse `OriginInfo`, `readOriginWithModule`, `moduleNameFromDm`, and `compareVersions` from this module.

**Version type** — `seihou-core/src/Seihou/Core/Version.hs`. The `Version` newtype wraps `[Natural]`. `parseVersion` parses "1.2.3" into `Version [1,2,3]`. The `Ord` instance pads shorter lists with zeros so `Version [1,2] == Version [1,2,0]`. `renderVersion` converts back to text.

**Module discovery** — `seihou-core/src/Seihou/Core/Module.hs`. `defaultSearchPaths` returns three paths: `.seihou/modules/` (project), `~/.config/seihou/modules/` (user), `~/.config/seihou/installed/` (installed). `discoverAllModules` scans these paths and returns `[DiscoveredModule]`. Each `DiscoveredModule` has `discoveredResult` (either a load error or a `Module`), `discoveredSource` (one of `SourceProject`, `SourceUser`, `SourceInstalled`), and `discoveredDir` (the filesystem path).

**Registry types** — `seihou-core/src/Seihou/Core/Registry.hs`. `RegistryEntry` has `name`, `version`, `path`, `description`, `tags`. `RepoContents` is `SingleModule FilePath | MultiModule Registry | EmptyRepo`. `discoverRepoContents` takes a Dhall evaluator and a directory path and returns `RepoContents`.

**Module validation** — `seihou-core/src/Seihou/Core/Module.hs`. `validateModule :: FilePath -> Module -> IO (Either ModuleLoadError Module)` checks 9 rules (module name, unique vars, prompt refs, file existence, etc.).

**Command type** — `seihou-cli/src/Seihou/CLI/Commands.hs` line 34. The `Command` ADT lists all CLI commands. Each variant has an associated options type and parser.

**Main dispatcher** — `seihou-cli/src/Main.hs` line 24. Pattern-matches on `Command` and calls the appropriate handler.

**CLI cabal file** — `seihou-cli/seihou-cli.cabal`. The `seihou` executable section lists `other-modules` (line 61-93). New modules must be added here.

**Styling** — `seihou-cli/src/Seihou/CLI/Style.hs`. Provides `useColor`, `green`, `yellow`, `red`, `dim`, `bold`, `cyan` for ANSI-colored output.


## Plan of Work

The work is organized into two milestones. The first wires up the CLI plumbing: the command variant, parser, dispatcher, new module file, and exports from existing modules. The second implements the upgrade logic itself.


### Milestone 1: CLI plumbing and module skeleton

This milestone adds the `seihou upgrade` command to the CLI without implementing the upgrade logic. At the end, `seihou upgrade --help` prints help text, and running `seihou upgrade` prints "Not yet implemented." The purpose is to validate that the command parsing and dispatch work correctly before adding the logic.

**Step 1.1: Add `UpgradeOpts` and `Upgrade` to `seihou-cli/src/Seihou/CLI/Commands.hs`.**

Add a new options type after `OutdatedOpts` (line 147):

    data UpgradeOpts = UpgradeOpts
      { upgradeModules :: [Text],
        upgradeDryRun :: Bool,
        upgradeJson :: Bool
      }
      deriving stock (Eq, Show, Generic)

The `upgradeModules` field is a list of module names to upgrade. When empty, all installed modules are checked. The `upgradeDryRun` field enables preview mode without making changes. The `upgradeJson` field enables JSON output.

Add `Upgrade UpgradeOpts` to the `Command` ADT after `Outdated OutdatedOpts` (line 47). Add `UpgradeOpts (..)` to the module export list (after `OutdatedOpts (..)`).

Add the parser and info block:

    upgradeInfo :: ParserInfo Command
    upgradeInfo =
      info
        (upgradeParser <**> helper)
        ( fullDesc
            <> progDesc "Upgrade installed modules to latest versions"
            <> footerDoc (Just upgradeFooter)
        )

    upgradeParser :: Parser Command
    upgradeParser =
      fmap Upgrade $
        UpgradeOpts
          <$> many (argument (T.pack <$> str) (metavar "MODULE" <> help "Module(s) to upgrade (default: all)"))
          <*> switch (long "dry-run" <> help "Show what would be upgraded without making changes")
          <*> switch (long "json" <> help "Output as JSON")

    upgradeFooter :: Doc
    upgradeFooter =
      vsep
        [ pretty ("Upgrades installed modules to the latest version available from their" :: String),
          pretty ("source repository. Only modules installed via 'seihou install' are checked." :: String),
          pretty ("Modules without version information are skipped." :: String),
          line,
          pretty ("With no arguments, checks all installed modules. Pass module names to" :: String),
          pretty ("upgrade specific modules only." :: String),
          line,
          pretty ("Examples:" :: String),
          indent 2 $
            vsep
              [ pretty ("seihou upgrade                   # upgrade all installed modules" :: String),
                pretty ("seihou upgrade haskell-base       # upgrade a specific module" :: String),
                pretty ("seihou upgrade --dry-run          # preview without changes" :: String)
              ]
        ]

Wire into `commandParser` by adding `<> command "upgrade" upgradeInfo` after the `outdated` entry (line 202).

**Step 1.2: Export reusable functions from `seihou-cli/src/Seihou/CLI/Install.hs`.**

Change the module export list from `( handleInstall, )` to:

    ( handleInstall,
      installModuleDir,
      cloneRepo,
      copyDirectoryRecursive,
    )

**Step 1.3: Export reusable functions from `seihou-cli/src/Seihou/CLI/Outdated.hs`.**

Change the module export list from `( handleOutdated, )` to:

    ( handleOutdated,
      OriginInfo (..),
      OutdatedStatus (..),
      OutdatedEntry (..),
      readOriginWithModule,
      moduleNameFromDm,
      compareVersions,
      findAvailableVersion,
      checkSource,
    )

**Step 1.4: Create `seihou-cli/src/Seihou/CLI/Upgrade.hs` with a stub handler.**

    module Seihou.CLI.Upgrade
      ( handleUpgrade,
      )
    where

    import Data.Text.IO qualified as TIO
    import Seihou.CLI.Commands (UpgradeOpts (..))
    import Seihou.Prelude

    handleUpgrade :: UpgradeOpts -> IO ()
    handleUpgrade _uopts = do
      TIO.putStrLn "Not yet implemented."

**Step 1.5: Wire into `seihou-cli/src/Main.hs`.**

Add import:

    import Seihou.CLI.Upgrade (handleUpgrade)

Add case in the dispatch block after `Outdated`:

    Upgrade upgradeOpts ->
      handleUpgrade upgradeOpts

**Step 1.6: Register in `seihou-cli/seihou-cli.cabal`.**

Add `Seihou.CLI.Upgrade` to the `other-modules` list in the `executable seihou` section, after `Seihou.CLI.Style` (line 85).

**Verification:** Run `cabal build all` from the repository root. Then run `cabal run seihou -- upgrade --help`. The output should show the upgrade command help text with `--dry-run`, `--json`, and `MODULE` argument. Running `cabal run seihou -- upgrade` should print "Not yet implemented."


### Milestone 2: Upgrade logic

This milestone implements the full upgrade handler. At the end, `seihou upgrade` discovers installed modules with outdated versions and replaces them with the latest from their source repositories. The handler follows the same clone-discover-compare pattern as `seihou outdated`, then calls `installModuleDir` to replace the module directory.

**Step 2.1: Implement `handleUpgrade` in `seihou-cli/src/Seihou/CLI/Upgrade.hs`.**

Replace the stub with the full implementation. The algorithm:

1. Discover all installed modules using `defaultSearchPaths` and `discoverAllModules`, filtering to `SourceInstalled`.
2. Read `.seihou-origin.json` for each using `readOriginWithModule` (imported from `Outdated`).
3. If the user specified module names in `upgradeModules`, filter to only those modules. If a named module is not found among installed modules, print an error and exit.
4. Group modules by `sourceUrl` to avoid cloning the same repository multiple times.
5. For each unique source URL, shallow-clone into a temp directory and discover its contents.
6. For each installed module from that source:
   a. Find the available version using `findAvailableVersion`.
   b. Compare versions using `compareVersions`.
   c. If the status is `OutdatedSt` (the installed version is older than the available version) and `--dry-run` is not set:
      - Locate the module directory in the cloned repo (for single-module repos, the clone root; for multi-module, the entry's `path` subdirectory).
      - Decode the module's `module.dhall` with `evalModuleFromFile`.
      - Validate with `validateModule`.
      - If validation passes, call `installModuleDir` to replace the installed copy.
      - Record the result as "upgraded."
      - If validation fails, record as "failed" with the error.
   d. If the status is `UpToDate`, record as "up to date."
   e. If the status is `Unversioned`, record as "skipped."
7. Render a results table (or JSON if `--json` is set).

The imports needed:

    import Control.Applicative ((<|>))
    import Control.Exception (SomeException, try)
    import Data.Aeson (ToJSON (..), object, (.=))
    import Data.Aeson.Encode.Pretty (encodePretty)
    import Data.ByteString.Lazy qualified as LBS
    import Data.Map.Strict qualified as Map
    import Data.Text qualified as T
    import Data.Text.IO qualified as TIO
    import Seihou.CLI.Commands (UpgradeOpts (..))
    import Seihou.CLI.Install (cloneRepo, installModuleDir)
    import Seihou.CLI.Outdated (OriginInfo (..), OutdatedStatus (..), compareVersions, findAvailableVersion, moduleNameFromDm, readOriginWithModule)
    import Seihou.CLI.Style (dim, green, red, useColor, yellow)
    import Seihou.Core.Module (DiscoveredModule (..), ModuleSource (..), defaultSearchPaths, discoverAllModules, validateModule)
    import Seihou.Core.Registry (Registry (..), RegistryEntry (..), RepoContents (..), discoverRepoContents)
    import Seihou.Core.Types (Module (..), ModuleName (..))
    import Seihou.Dhall.Eval (evalModuleFromFile, evalRegistryFromFile)
    import Seihou.Prelude
    import System.Exit (ExitCode (..), exitFailure)
    import System.IO.Temp (withSystemTempDirectory)
    import System.Process (readProcessWithExitCode)

The result type for the upgrade report:

    data UpgradeStatus
      = Upgraded
      | AlreadyUpToDate
      | Skipped        -- unversioned
      | UpgradeFailed Text  -- validation or other error
      | SourceUnreachable
      deriving stock (Eq, Show)

    data UpgradeEntry = UpgradeEntry
      { moduleName :: Text,
        oldVersion :: Maybe Text,
        newVersion :: Maybe Text,
        upgradeStatus :: UpgradeStatus
      }
      deriving stock (Eq, Show)

The `handleUpgrade` function structure:

    handleUpgrade :: UpgradeOpts -> IO ()
    handleUpgrade uopts = do
      searchPaths <- defaultSearchPaths
      modules <- discoverAllModules searchPaths
      let installed = filter (\dm -> dm.discoveredSource == SourceInstalled) modules

      when (null installed) $ do
        TIO.putStrLn "No installed modules found."
        pure ()

      -- (guard against empty list continuing past this point)

      originsWithModules <- mapM readOriginWithModule installed
      let withOrigins = [(dm, origin) | (dm, Just origin) <- originsWithModules]

      -- Filter to requested modules if specified
      filtered <- case uopts.upgradeModules of
        [] -> pure withOrigins
        names -> do
          let result = [(dm, origin) | (dm, origin) <- withOrigins, moduleNameFromDm dm `elem` names]
              found = map (moduleNameFromDm . fst) result
              missing = filter (`notElem` found) names
          when (not (null missing)) $ do
            TIO.putStrLn $ "Module(s) not found: " <> T.intercalate ", " missing
            exitFailure
          pure result

      when (null filtered) $ do
        TIO.putStrLn "No installed modules with origin metadata found."
        pure ()

      let grouped = Map.toList $ Map.fromListWith (++) [(origin.sourceUrl, [(dm, origin)]) | (dm, origin) <- filtered]

      when (not uopts.upgradeDryRun) $
        TIO.putStrLn "Upgrading installed modules..."

      when uopts.upgradeDryRun $
        TIO.putStrLn "Checking installed modules for updates (dry run)..."

      entries <- concat <$> mapM (upgradeSource uopts) grouped

      if uopts.upgradeJson
        then LBS.putStr (encodePretty entries)
        else renderUpgradeTable entries

The `upgradeSource` function handles one source URL. It clones the repo, then for each module from that source, decides whether to upgrade:

    upgradeSource :: UpgradeOpts -> (Text, [(DiscoveredModule, OriginInfo)]) -> IO [UpgradeEntry]
    upgradeSource uopts (sourceUrl, modulesWithOrigins) = do
      let repoName = parseModuleName sourceUrl
      TIO.putStrLn $ "  Cloning " <> T.pack repoName <> "..."

      result <- try $ withSystemTempDirectory "seihou-upgrade" $ \tmpDir -> do
        let cloneDir = tmpDir </> repoName
        (exitCode, _stdout, _stderr) <- readProcessWithExitCode "git" ["clone", "--depth", "1", T.unpack sourceUrl, cloneDir] ""
        case exitCode of
          ExitFailure _ -> pure Nothing
          ExitSuccess -> do
            contents <- discoverRepoContents evalRegistryFromFile cloneDir
            Just <$> mapM (upgradeModule uopts cloneDir contents sourceUrl) modulesWithOrigins

      case result of
        Left (_ :: SomeException) ->
          pure [mkUnreachableEntry dm origin | (dm, origin) <- modulesWithOrigins]
        Right Nothing ->
          pure [mkUnreachableEntry dm origin | (dm, origin) <- modulesWithOrigins]
        Right (Just entries) ->
          pure entries

The `upgradeModule` function handles one module. It compares versions, validates, and either performs the upgrade or records the status:

    upgradeModule :: UpgradeOpts -> FilePath -> RepoContents -> Text -> (DiscoveredModule, OriginInfo) -> IO UpgradeEntry
    upgradeModule uopts cloneDir contents sourceUrl (dm, origin) = do
      let name = moduleNameFromDm dm
          installedVer = origin.version
      availableVer <- findAvailableVersion cloneDir contents name
      let status = compareVersions installedVer availableVer

      case status of
        OutdatedSt
          | uopts.upgradeDryRun ->
              pure UpgradeEntry { moduleName = name, oldVersion = installedVer, newVersion = availableVer, upgradeStatus = Upgraded }
          | otherwise -> doUpgrade cloneDir contents sourceUrl origin name installedVer availableVer
        UpToDate ->
          pure UpgradeEntry { moduleName = name, oldVersion = installedVer, newVersion = availableVer, upgradeStatus = AlreadyUpToDate }
        Unversioned ->
          pure UpgradeEntry { moduleName = name, oldVersion = installedVer, newVersion = availableVer, upgradeStatus = Skipped }
        Unreachable ->
          pure UpgradeEntry { moduleName = name, oldVersion = installedVer, newVersion = Nothing, upgradeStatus = SourceUnreachable }

The `doUpgrade` function performs the actual upgrade by locating the module directory in the cloned repo, validating, and calling `installModuleDir`:

    doUpgrade :: FilePath -> RepoContents -> Text -> OriginInfo -> Text -> Maybe Text -> Maybe Text -> IO UpgradeEntry
    doUpgrade cloneDir contents sourceUrl origin name installedVer availableVer = do
      let result = case contents of
            SingleModule rootDir -> Just (rootDir, origin.repoName)
            MultiModule registry ->
              case filter (\e -> e.name.unModuleName == name) registry.modules of
                (entry : _) -> Just (cloneDir </> entry.path, Just registry.repoName)
                [] -> Nothing
            EmptyRepo -> Nothing

      case result of
        Nothing ->
          pure UpgradeEntry { moduleName = name, oldVersion = installedVer, newVersion = availableVer, upgradeStatus = UpgradeFailed "module not found in remote" }
        Just (moduleDir, registryName) -> do
          let dhallFile = moduleDir </> "module.dhall"
          decoded <- evalModuleFromFile dhallFile
          case decoded of
            Left err ->
              pure UpgradeEntry { moduleName = name, oldVersion = installedVer, newVersion = availableVer, upgradeStatus = UpgradeFailed (T.pack (show err)) }
            Right modul -> do
              valResult <- validateModule moduleDir modul
              case valResult of
                Left err ->
                  pure UpgradeEntry { moduleName = name, oldVersion = installedVer, newVersion = availableVer, upgradeStatus = UpgradeFailed (T.pack (show err)) }
                Right _ -> do
                  let ver = case contents of
                        MultiModule registry -> case filter (\e -> e.name.unModuleName == name) registry.modules of
                          (entry : _) -> entry.version <|> modul.version
                          [] -> modul.version
                        _ -> modul.version
                  installModuleDir moduleDir (T.unpack name) sourceUrl registryName ver
                  TIO.putStrLn $ "    Upgraded " <> name
                  pure UpgradeEntry { moduleName = name, oldVersion = installedVer, newVersion = availableVer, upgradeStatus = Upgraded }

The table renderer follows the same pattern as `Outdated.hs` but uses upgrade-specific statuses:

    renderUpgradeTable :: [UpgradeEntry] -> IO ()
    renderUpgradeTable entries = do
      colorEnabled <- useColor
      -- similar padding and formatting logic as Outdated.renderTable
      -- Status column shows: "upgraded", "up to date", "skipped (unversioned)", "failed: <reason>", "unreachable"
      -- Color coding: green for upgraded, dim for up to date, yellow for skipped, red for failed/unreachable

The summary line:

    let upgraded = length (filter (\e -> e.upgradeStatus == Upgraded) entries)
        failed = length (filter isFailedEntry entries)
        skipped = length (filter (\e -> e.upgradeStatus == Skipped) entries)
    TIO.putStrLn $ T.pack (show (length entries)) <> " module(s) checked, "
      <> T.pack (show upgraded) <> " upgraded"
      <> (if failed > 0 then ", " <> T.pack (show failed) <> " failed" else "")
      <> (if skipped > 0 then ", " <> T.pack (show skipped) <> " skipped" else "")
      <> "."

Add a `ToJSON` instance for `UpgradeEntry` so that `--json` output works:

    instance ToJSON UpgradeEntry where
      toJSON e = object
        [ "module" .= e.moduleName
        , "oldVersion" .= e.oldVersion
        , "newVersion" .= e.newVersion
        , "status" .= statusText e.upgradeStatus
        ]
      where
        statusText Upgraded = "upgraded" :: Text
        statusText AlreadyUpToDate = "up to date"
        statusText Skipped = "skipped"
        statusText (UpgradeFailed reason) = "failed: " <> reason
        statusText SourceUnreachable = "unreachable"

Also import `parseModuleName` from `Seihou.Core.Install` for extracting the repo name from a URL.

**Verification:** Run `cabal build all` and `cabal test all`. All existing tests should pass since this is purely additive.

Then manually test:

1. Create a test module with `version = Some "1.0.0"` in its `module.dhall`. Initialize a git repo, commit, and push to a bare repo.
2. Install it with `seihou install <path-to-bare-repo>`.
3. Update the module's version to `"1.1.0"` in the source repo and commit/push.
4. Run `seihou upgrade --dry-run`. It should show the module as "upgraded" with old=1.0.0 and new=1.1.0 but not change any files.
5. Run `seihou upgrade`. It should upgrade the module. Verify with `seihou list` that the version is now 1.1.0.
6. Run `seihou upgrade` again. It should show "up to date."


## Concrete Steps

All commands are run from the repository root at `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

Build after each milestone:

    cabal build all

Run tests after each milestone:

    cabal test all

Expected output: all tests pass with no new failures.

To verify the CLI plumbing (Milestone 1):

    cabal run seihou -- upgrade --help

Expected output includes the description "Upgrade installed modules to latest versions" and flags `--dry-run`, `--json`, and `MODULE` positional arguments.

    cabal run seihou -- upgrade

Expected output: "Not yet implemented." (Milestone 1) or the upgrade report (Milestone 2).

For manual end-to-end testing (Milestone 2), create a temporary git repo:

    mkdir /tmp/test-upgrade-bare && cd /tmp/test-upgrade-bare && git init --bare
    mkdir /tmp/test-upgrade-src && cd /tmp/test-upgrade-src && git init

Create a minimal `module.dhall` with version "1.0.0", commit, push to the bare repo. Install with `seihou install /tmp/test-upgrade-bare`. Then update the version to "1.1.0", commit, push. Run `seihou upgrade`.

Expected output:

    Upgrading installed modules...
      Cloning test-upgrade-bare...
        Upgraded test-upgrade-src

    Module              Old          New          Status
    test-upgrade-src    1.0.0        1.1.0        upgraded

    1 module(s) checked, 1 upgraded.


## Validation and Acceptance

**Milestone 1 acceptance:**
- `cabal build all` succeeds.
- `seihou upgrade --help` shows the upgrade command help with `--dry-run`, `--json`, and `MODULE` arguments.
- `seihou --help` includes `upgrade` in the command list.
- `seihou upgrade` runs without crashing (prints "Not yet implemented.").
- All existing tests pass (`cabal test all`).

**Milestone 2 acceptance:**
- `seihou upgrade` runs without error when no installed modules exist (prints "No installed modules found.").
- `seihou upgrade` correctly upgrades a module from version 1.0.0 to 1.1.0 against a test repository.
- After upgrading, `seihou list` shows the new version for the upgraded module.
- After upgrading, `.seihou-origin.json` contains the new version and updated timestamp.
- `seihou upgrade` when all modules are up to date shows "up to date" for each and upgrades nothing.
- `seihou upgrade --dry-run` shows what would be upgraded without modifying any files.
- `seihou upgrade --json` produces valid JSON output with module name, old version, new version, and status.
- `seihou upgrade <module-name>` upgrades only the named module.
- `seihou upgrade nonexistent-module` prints an error and exits with failure.
- Unversioned modules are shown as "skipped (unversioned)" and are not upgraded.
- If the source repository is unreachable, the module is shown as "unreachable" and the command does not crash.
- If the remote module fails validation, the upgrade is skipped with a "failed" status and the existing installation is preserved.
- All existing tests pass (`cabal test all`).


## Idempotence and Recovery

The upgrade operation is idempotent. Running `seihou upgrade` when all modules are already at the latest version produces an "up to date" report and changes nothing. Running it again after a successful upgrade also produces "up to date."

If an upgrade fails partway (e.g., the process is killed during `installModuleDir`), the module directory may be in a partially written state. The next `seihou upgrade` or `seihou install <url>` will overwrite it completely, recovering to a clean state. This is the same recovery model as the existing `seihou install` command.

The `--dry-run` flag is always safe — it clones repos into temp directories (cleaned up automatically) and never writes to the installed module directories.

Temp directories used for cloning are created with `withSystemTempDirectory` and are cleaned up automatically when the block exits, even on exceptions.


## Interfaces and Dependencies

No new library dependencies are required. All needed libraries (aeson, process, temporary, directory, etc.) are already dependencies of `seihou-cli`.

**New module:** `seihou-cli/src/Seihou/CLI/Upgrade.hs`

    handleUpgrade :: UpgradeOpts -> IO ()

**New types in `seihou-cli/src/Seihou/CLI/Commands.hs`:**

    data UpgradeOpts = UpgradeOpts
      { upgradeModules :: [Text],
        upgradeDryRun :: Bool,
        upgradeJson :: Bool
      }

    -- Added to Command ADT: | Upgrade UpgradeOpts

**Modified exports in `seihou-cli/src/Seihou/CLI/Install.hs`:**

    module Seihou.CLI.Install
      ( handleInstall,
        installModuleDir,
        cloneRepo,
        copyDirectoryRecursive,
      )

**Modified exports in `seihou-cli/src/Seihou/CLI/Outdated.hs`:**

    module Seihou.CLI.Outdated
      ( handleOutdated,
        OriginInfo (..),
        OutdatedStatus (..),
        OutdatedEntry (..),
        readOriginWithModule,
        moduleNameFromDm,
        compareVersions,
        findAvailableVersion,
        checkSource,
      )
