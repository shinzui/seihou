module Seihou.CLI.Upgrade
  ( handleUpgrade,
  )
where

import Control.Applicative ((<|>))
import Control.Exception (SomeException, try)
import Control.Monad (when)
import Data.Aeson (ToJSON (..), object, (.=))
import Data.Aeson.Encode.Pretty (encodePretty)
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (UpgradeOpts (..))
import Seihou.CLI.Install (installModuleDir)
import Seihou.CLI.InstallShared (OriginInfo (..))
import Seihou.CLI.Migrate
  ( MigrateError (..),
    MigrateOpts (..),
    MigrateResult (..),
    pendingChainFor,
    runMigrate,
  )
import Seihou.CLI.Outdated (moduleNameFromDm, readOriginWithModule)
import Seihou.CLI.RemoteVersion (fetchTrueModuleVersion)
import Seihou.CLI.Style (dim, green, red, useColor, yellow)
import Seihou.CLI.VersionCompare (OutdatedStatus (..), compareVersions)
import Seihou.Core.Install (parseModuleName)
import Seihou.Core.Migration (MigrationChain (..), MigrationPlan (..))
import Seihou.Core.Module (DiscoveredModule (..), ModuleSource (..), defaultSearchPaths, discoverAllModules, validateModule)
import Seihou.Core.Registry (Registry (..), RegistryEntry (..), RepoContents (..), discoverRepoContents)
import Seihou.Core.Types (AppliedModule (..), Manifest (..), Module (..), ModuleName (..))
import Seihou.Core.Version (renderVersion)
import Seihou.Dhall.Eval (evalModuleFromFile, evalRegistryFromFile)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.ManifestStore (readManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Prelude
import System.Exit (ExitCode (..), exitFailure)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)

data UpgradeStatus
  = Upgraded
  | AlreadyUpToDate
  | Skipped
  | UpgradeFailed Text
  | SourceUnreachable
  deriving stock (Eq, Show)

data UpgradeEntry = UpgradeEntry
  { moduleName :: Text,
    oldVersion :: Maybe Text,
    newVersion :: Maybe Text,
    upgradeStatus :: UpgradeStatus
  }
  deriving stock (Eq, Show)

instance ToJSON UpgradeEntry where
  toJSON e =
    object
      [ "module" .= e.moduleName,
        "oldVersion" .= e.oldVersion,
        "newVersion" .= e.newVersion,
        "status" .= statusText e.upgradeStatus
      ]
    where
      statusText :: UpgradeStatus -> Text
      statusText Upgraded = "upgraded"
      statusText AlreadyUpToDate = "up to date"
      statusText Skipped = "skipped"
      statusText (UpgradeFailed reason) = "failed: " <> reason
      statusText SourceUnreachable = "unreachable"

handleUpgrade :: UpgradeOpts -> IO ()
handleUpgrade uopts = do
  searchPaths <- defaultSearchPaths
  modules <- discoverAllModules searchPaths
  let installed = filter (\dm -> dm.discoveredSource == SourceInstalled) modules

  if null installed
    then TIO.putStrLn "No installed modules found."
    else do
      originsWithModules <- mapM readOriginWithModule installed
      let withOrigins = [(dm, origin) | (dm, Just origin) <- originsWithModules]

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

      if null filtered
        then TIO.putStrLn "No installed modules with origin metadata found."
        else do
          let grouped = Map.toList $ Map.fromListWith (++) [(origin.sourceUrl, [(dm, origin)]) | (dm, origin) <- filtered]

          if uopts.upgradeDryRun
            then TIO.putStrLn "Checking installed modules for updates (dry run)..."
            else TIO.putStrLn "Upgrading installed modules..."

          entries <- concat <$> mapM (upgradeSource uopts) grouped

          if uopts.upgradeJson
            then LBS.putStr (encodePretty entries)
            else renderUpgradeTable entries

          -- After all upgrades, see whether the *current project* has
          -- migrations pending for any module that was upgraded just
          -- now. Either run them (--with-migrations) or print a
          -- one-line advisory per module.
          unless uopts.upgradeDryRun $
            handlePostUpgradeMigrations uopts entries

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

mkUnreachableEntry :: DiscoveredModule -> OriginInfo -> UpgradeEntry
mkUnreachableEntry dm origin =
  UpgradeEntry
    { moduleName = moduleNameFromDm dm,
      oldVersion = origin.version,
      newVersion = Nothing,
      upgradeStatus = SourceUnreachable
    }

upgradeModule :: UpgradeOpts -> FilePath -> RepoContents -> Text -> (DiscoveredModule, OriginInfo) -> IO UpgradeEntry
upgradeModule uopts cloneDir contents sourceUrl (dm, origin) = do
  let name = moduleNameFromDm dm
      installedVer = origin.version
  availableVer <- fetchAvailable cloneDir (ModuleName name)
  let status = compareVersions installedVer availableVer

  case status of
    OutdatedSt
      | uopts.upgradeDryRun ->
          pure UpgradeEntry {moduleName = name, oldVersion = installedVer, newVersion = availableVer, upgradeStatus = Upgraded}
      | otherwise ->
          doUpgrade cloneDir contents sourceUrl origin name installedVer availableVer
    UpToDate ->
      pure UpgradeEntry {moduleName = name, oldVersion = installedVer, newVersion = availableVer, upgradeStatus = AlreadyUpToDate}
    Unversioned
      | uopts.upgradeSkipUnversioned ->
          pure UpgradeEntry {moduleName = name, oldVersion = installedVer, newVersion = availableVer, upgradeStatus = Skipped}
      | uopts.upgradeDryRun ->
          pure UpgradeEntry {moduleName = name, oldVersion = installedVer, newVersion = availableVer, upgradeStatus = Upgraded}
      | otherwise ->
          doUpgrade cloneDir contents sourceUrl origin name installedVer availableVer
    Unreachable ->
      pure UpgradeEntry {moduleName = name, oldVersion = installedVer, newVersion = Nothing, upgradeStatus = SourceUnreachable}

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
      pure UpgradeEntry {moduleName = name, oldVersion = installedVer, newVersion = availableVer, upgradeStatus = UpgradeFailed "module not found in remote"}
    Just (moduleDir, registryName) -> do
      let dhallFile = moduleDir </> "module.dhall"
      decoded <- evalModuleFromFile dhallFile
      case decoded of
        Left err ->
          pure UpgradeEntry {moduleName = name, oldVersion = installedVer, newVersion = availableVer, upgradeStatus = UpgradeFailed (T.pack (show err))}
        Right modul -> do
          valResult <- validateModule moduleDir modul
          case valResult of
            Left err ->
              pure UpgradeEntry {moduleName = name, oldVersion = installedVer, newVersion = availableVer, upgradeStatus = UpgradeFailed (T.pack (show err))}
            Right _ -> do
              -- Trust the module.dhall version over the registry's static
              -- entry.version: the registry can be stale (the bug fixed in
              -- docs/plans/14-fix-outdated-version-detection.md). Tags are
              -- still sourced from the registry entry since module.dhall
              -- has no equivalent field.
              let (ver, entryTags) = case contents of
                    MultiModule registry -> case filter (\e -> e.name.unModuleName == name) registry.modules of
                      (entry : _) -> (modul.version <|> entry.version, entry.tags)
                      [] -> (modul.version, [])
                    _ -> (modul.version, [])
              installModuleDir moduleDir (T.unpack name) sourceUrl registryName ver entryTags
              TIO.putStrLn $ "    Upgraded " <> name
              pure UpgradeEntry {moduleName = name, oldVersion = installedVer, newVersion = availableVer, upgradeStatus = Upgraded}

renderUpgradeTable :: [UpgradeEntry] -> IO ()
renderUpgradeTable entries = do
  colorEnabled <- useColor
  let maxNameLen = max 6 (maximum (map (T.length . (.moduleName)) entries))
      maxOldLen = max 3 (maximum (map (T.length . maybe "(none)" id . (.oldVersion)) entries))
      maxNewLen = max 3 (maximum (map (T.length . maybe "(none)" id . (.newVersion)) entries))

      padR n t = t <> T.replicate (n - T.length t + 2) " "

      header =
        padR maxNameLen "Module"
          <> padR maxOldLen "Old"
          <> padR maxNewLen "New"
          <> "Status"

      formatRow e =
        let oldText = maybe "(none)" id e.oldVersion
            newText = maybe "(none)" id e.newVersion
            statusTxt = case e.upgradeStatus of
              Upgraded -> if colorEnabled then green "upgraded" else "upgraded"
              AlreadyUpToDate -> if colorEnabled then dim "up to date" else "up to date"
              Skipped -> if colorEnabled then yellow "skipped (unversioned)" else "skipped (unversioned)"
              UpgradeFailed reason -> if colorEnabled then red ("failed: " <> reason) else "failed: " <> reason
              SourceUnreachable -> if colorEnabled then yellow "unreachable" else "unreachable"
         in padR maxNameLen e.moduleName
              <> padR maxOldLen oldText
              <> padR maxNewLen newText
              <> statusTxt

  TIO.putStrLn ""
  TIO.putStrLn header
  mapM_ (TIO.putStrLn . formatRow) entries

  let upgraded = length (filter (\e -> e.upgradeStatus == Upgraded) entries)
      failed = length (filter isFailedEntry entries)
      skipped = length (filter (\e -> e.upgradeStatus == Skipped) entries)
  TIO.putStrLn ""
  TIO.putStrLn $
    T.pack (show (length entries))
      <> " module(s) checked, "
      <> T.pack (show upgraded)
      <> " upgraded"
      <> (if failed > 0 then ", " <> T.pack (show failed) <> " failed" else "")
      <> (if skipped > 0 then ", " <> T.pack (show skipped) <> " skipped" else "")
      <> "."

isFailedEntry :: UpgradeEntry -> Bool
isFailedEntry e = case e.upgradeStatus of
  UpgradeFailed _ -> True
  SourceUnreachable -> True
  _ -> False

-- | After the upgrade table is printed, look at the project's local
-- manifest for each module that was just upgraded. If the upgrade
-- raised the installed-copy version above the manifest's recorded
-- version, there are migrations to run. With @--with-migrations@,
-- run them. Otherwise, print a single advisory line per module.
--
-- If there's no local manifest at all (the user is upgrading without
-- a project), this is a silent no-op.
handlePostUpgradeMigrations :: UpgradeOpts -> [UpgradeEntry] -> IO ()
handlePostUpgradeMigrations uopts entries = do
  let manifestPath = ".seihou" </> "manifest.json"
      upgraded =
        [ entry.moduleName | entry <- entries, entry.upgradeStatus == Upgraded
        ]
  if null upgraded
    then pure ()
    else do
      mfRes <- runEff $ runFilesystem $ runManifestStore manifestPath readManifest
      case mfRes of
        Left _ -> pure ()
        Right Nothing -> pure ()
        Right (Just manifest) ->
          mapM_ (handleOneModule uopts manifest) upgraded

handleOneModule :: UpgradeOpts -> Manifest -> Text -> IO ()
handleOneModule uopts manifest name =
  case findAppliedByName manifest name of
    Nothing -> pure ()
    Just am -> do
      let dhallFile = am.source </> "module.dhall"
      r <- evalModuleFromFile dhallFile
      case r of
        Left _ -> pure ()
        Right installed ->
          case pendingChainFor am installed of
            Nothing -> pure ()
            Just plan
              | uopts.upgradeWithMigrations -> runOnePostUpgradeMigration am.source name
              | otherwise -> printAdvisory name plan

findAppliedByName :: Manifest -> Text -> Maybe AppliedModule
findAppliedByName manifest name =
  case filter (\am -> am.name.unModuleName == name) manifest.modules of
    (am : _) -> Just am
    [] -> Nothing

printAdvisory :: Text -> MigrationPlan -> IO ()
printAdvisory name plan = do
  colorEnabled <- useColor
  let msg
        -- Benign: the module declared no migrations and the version
        -- bumped. The post-upgrade advisory points at the natural
        -- remediation (the user just ran `seihou upgrade` so the
        -- "and seihou run" half is what's left to do).
        | null plan.planChain.chainSteps,
          not plan.planMigrationsDeclared,
          Just (from, to) <- plan.planUnreachable =
            "note: "
              <> name
              <> " has no migrations declared ("
              <> renderVersion from
              <> " -> "
              <> renderVersion to
              <> "); run 'seihou run' to refresh templates."
        | null plan.planChain.chainSteps,
          Just (stuck, target) <- plan.planUnreachable =
            "note: "
              <> name
              <> " is blocked: no migration declared from "
              <> renderVersion stuck
              <> "; remote is at "
              <> renderVersion target
              <> ". Run 'seihou migrate "
              <> name
              <> " --bump-only' to acknowledge no migration is needed."
        | otherwise =
            let chain = plan.planChain
                base =
                  "note: "
                    <> name
                    <> " has "
                    <> T.pack (show (length chain.chainSteps))
                    <> " migration(s) pending ("
                    <> renderVersion chain.chainFrom
                    <> " → "
                    <> renderVersion chain.chainTo
                    <> "); run 'seihou migrate "
                    <> name
                    <> "'"
                tail_ = case plan.planUnreachable of
                  Nothing -> ""
                  Just (stuck, target) ->
                    " (note: no migration declared from "
                      <> renderVersion stuck
                      <> "; remote is at "
                      <> renderVersion target
                      <> ")"
             in base <> tail_
  TIO.putStrLn $ if colorEnabled then yellow msg else msg

-- | Run a migration for a single module. Reads the manifest fresh so
-- chained migrations against multiple upgraded modules see each
-- other's effects.
runOnePostUpgradeMigration :: FilePath -> Text -> IO ()
runOnePostUpgradeMigration installedDir name = do
  let manifestPath = ".seihou" </> "manifest.json"
  mfRes <- runEff $ runFilesystem $ runManifestStore manifestPath readManifest
  case mfRes of
    Right (Just manifest) -> do
      let opts =
            MigrateOpts
              { migrateModule = ModuleName name,
                migrateTo = Nothing,
                migrateDryRun = False,
                migrateForce = False,
                migrateJson = False,
                migrateVerbose = False,
                -- The post-upgrade hook has already refreshed the
                -- installed copy via 'seihou upgrade'; skip the
                -- redundant fetch in 'runMigrate'.
                migrateNoFetch = True,
                migrateBumpOnly = False,
                migrateCommit = False,
                migrateCommitMessage = Nothing
              }
      result <- runMigrate opts manifest installedDir
      case result of
        Right (MigrateApplied _ _) -> do
          colorEnabled <- useColor
          let msg = "    " <> "Migrated " <> name
          TIO.putStrLn $ if colorEnabled then green msg else msg
        Right (MigrateAppliedPartial _ _ stuck target) -> do
          colorEnabled <- useColor
          let msg =
                "    Migrated "
                  <> name
                  <> " (partial; no migration declared from "
                  <> renderVersion stuck
                  <> ", remote is at "
                  <> renderVersion target
                  <> ")"
          TIO.putStrLn $ if colorEnabled then yellow msg else msg
        Right (MigrateAppliedBumpedThrough _ _ stuck target) -> do
          -- EP-28: chain prefix ran AND manifest bumped through the
          -- exhausted tail to @target@.
          colorEnabled <- useColor
          let msg =
                "    Migrated "
                  <> name
                  <> " (chain applied; "
                  <> renderVersion stuck
                  <> " → "
                  <> renderVersion target
                  <> " bumped through with no migration declared)"
          TIO.putStrLn $ if colorEnabled then green msg else msg
        Right (MigrateBlocked stuck target) -> do
          colorEnabled <- useColor
          let msg =
                "    Migration blocked for "
                  <> name
                  <> ": no migration declared from "
                  <> renderVersion stuck
                  <> "; remote is at "
                  <> renderVersion target
                  <> ". Run 'seihou migrate "
                  <> name
                  <> " --bump-only' to acknowledge no migration is needed."
          TIO.putStrLn $ if colorEnabled then yellow msg else msg
        Right (MigrateBenignUpgrade _ _) -> pure ()
        Right (MigrateNoOp _) -> pure ()
        Right (MigrateDryRunOK _) -> pure ()
        Right (MigrateDryRunOKPartial _ _ _) -> pure ()
        Right (MigrateDryRunOKBumpedThrough _ _ _) -> pure ()
        Left err -> do
          colorEnabled <- useColor
          let msg = "    Migration failed for " <> name <> ": " <> renderMigrateError err
          TIO.putStrLn $ if colorEnabled then red msg else msg
    _ -> pure ()

renderMigrateError :: MigrateError -> Text
renderMigrateError err = case err of
  MigrateModuleNotApplied n -> "module " <> n.unModuleName <> " not applied"
  MigrateNoRecordedVersion n -> "no version recorded for " <> n.unModuleName
  MigrateInstalledModuleEvalFailed _ msg -> msg
  MigrateInstalledModuleHasNoVersion n _ -> "no version on installed " <> n.unModuleName
  MigrateUnparseableInstalledVersion v -> "bad version " <> v
  MigrateUnparseableTargetVersion v -> "bad target version " <> v
  MigrateUnparseableManifestVersion v -> "bad manifest version " <> v
  MigratePlanFailed _ -> "plan failed"
  MigrateExecFailed _ -> "execution failed (use --force or revert your edits)"
  MigrateNoManifest _ -> "no manifest in current dir"
  MigrateConflictingFlags msg -> msg

-- | Local @unless@ to avoid pulling in another import.
unless :: Bool -> IO () -> IO ()
unless True _ = pure ()
unless False action = action

-- | Look up the available version of a module in a cloned repo by reading
-- its @module.dhall@. Fetch errors collapse to @Nothing@; downstream
-- 'compareVersions' treats that as "unversioned" and 'doUpgrade' will
-- still attempt the install (the registry's static @version@ is no longer
-- consulted for the comparison — see EP-1).
fetchAvailable :: FilePath -> ModuleName -> IO (Maybe Text)
fetchAvailable cloneDir name = do
  result <- fetchTrueModuleVersion cloneDir name
  case result of
    Right v -> pure v
    Left _ -> pure Nothing
