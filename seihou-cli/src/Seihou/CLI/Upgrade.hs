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
import Seihou.CLI.Outdated (OriginInfo (..), OutdatedStatus (..), compareVersions, findAvailableVersion, moduleNameFromDm, readOriginWithModule)
import Seihou.CLI.Style (dim, green, red, useColor, yellow)
import Seihou.Core.Install (parseModuleName)
import Seihou.Core.Module (DiscoveredModule (..), ModuleSource (..), defaultSearchPaths, discoverAllModules, validateModule)
import Seihou.Core.Registry (Registry (..), RegistryEntry (..), RepoContents (..), discoverRepoContents)
import Seihou.Core.Types (Module (..), ModuleName (..))
import Seihou.Dhall.Eval (evalModuleFromFile, evalRegistryFromFile)
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
  availableVer <- findAvailableVersion cloneDir contents name
  let status = compareVersions installedVer availableVer

  case status of
    OutdatedSt
      | uopts.upgradeDryRun ->
          pure UpgradeEntry {moduleName = name, oldVersion = installedVer, newVersion = availableVer, upgradeStatus = Upgraded}
      | otherwise ->
          doUpgrade cloneDir contents sourceUrl origin name installedVer availableVer
    UpToDate ->
      pure UpgradeEntry {moduleName = name, oldVersion = installedVer, newVersion = availableVer, upgradeStatus = AlreadyUpToDate}
    Unversioned ->
      pure UpgradeEntry {moduleName = name, oldVersion = installedVer, newVersion = availableVer, upgradeStatus = Skipped}
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
              let ver = case contents of
                    MultiModule registry -> case filter (\e -> e.name.unModuleName == name) registry.modules of
                      (entry : _) -> entry.version <|> modul.version
                      [] -> modul.version
                    _ -> modul.version
              installModuleDir moduleDir (T.unpack name) sourceUrl registryName ver
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
