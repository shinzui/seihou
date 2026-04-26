module Seihou.CLI.Outdated
  ( handleOutdated,
    OriginInfo (..),
    OutdatedStatus (..),
    OutdatedEntry (..),
    CheckStats (..),
    checkInstalledModulesForUpdates,
    readOriginWithModule,
    moduleNameFromDm,
    compareVersions,
    checkSource,
  )
where

import Control.Exception (SomeException, try)
import Data.Aeson (ToJSON (..), object, (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Encode.Pretty (encodePretty)
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (OutdatedOpts (..))
import Seihou.CLI.InstallShared (OriginInfo (..))
import Seihou.CLI.RemoteVersion (fetchTrueModuleVersion)
import Seihou.CLI.Style (dim, green, red, useColor, yellow)
import Seihou.CLI.VersionCompare (OutdatedStatus (..), compareVersions)
import Seihou.Core.Install (parseModuleName)
import Seihou.Core.Module (DiscoveredModule (..), ModuleSource (..), defaultSearchPaths, discoverAllModules)
import Seihou.Core.Types (Module (..), ModuleName (..))
import Seihou.Prelude
import System.Directory (doesFileExist)
import System.Exit (ExitCode (..))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)

-- | A single entry in the outdated report.
data OutdatedEntry = OutdatedEntry
  { moduleName :: Text,
    installedVersion :: Maybe Text,
    availableVersion :: Maybe Text,
    status :: OutdatedStatus
  }
  deriving stock (Eq, Show)

instance ToJSON OutdatedEntry where
  toJSON e =
    object
      [ "module" .= e.moduleName,
        "installed" .= e.installedVersion,
        "available" .= e.availableVersion,
        "status" .= statusText e.status
      ]
    where
      statusText UpToDate = "up to date" :: Text
      statusText OutdatedSt = "outdated"
      statusText Unversioned = "unversioned"
      statusText Unreachable = "unreachable"

-- | Summary statistics for an update check.
data CheckStats = CheckStats
  { checkedCount :: Int,
    skippedNoOrigin :: Int
  }
  deriving stock (Eq, Show)

handleOutdated :: OutdatedOpts -> IO ()
handleOutdated oopts = do
  searchPaths <- defaultSearchPaths
  modules <- discoverAllModules searchPaths
  let installed = filter (\dm -> dm.discoveredSource == SourceInstalled) modules

  if null installed
    then TIO.putStrLn "No installed modules found."
    else do
      (entries, _stats) <- checkInstalledModulesForUpdates installed
      if null entries
        then TIO.putStrLn "No installed modules with origin metadata found."
        else
          if oopts.outdatedJson
            then LBS.putStr (encodePretty entries)
            else renderTable entries

-- | Check a list of already-discovered modules for updates.
--
-- Filters to @SourceInstalled@ modules internally, reads @.seihou-origin.json@
-- for each, groups by source URL, clones each source shallowly, and compares
-- installed versions against what the remote registry advertises.
--
-- Prints progress lines to stdout via 'checkSource'. Returns the flat list
-- of outdated entries plus stats describing how many modules were actually
-- checked versus skipped for lack of origin metadata.
checkInstalledModulesForUpdates ::
  [DiscoveredModule] ->
  IO ([OutdatedEntry], CheckStats)
checkInstalledModulesForUpdates modules = do
  let installed = filter (\dm -> dm.discoveredSource == SourceInstalled) modules
  originsWithModules <- mapM readOriginWithModule installed
  let withOrigins = [(dm, origin) | (dm, Just origin) <- originsWithModules]
      skipped = length installed - length withOrigins
  if null withOrigins
    then
      pure
        ( [],
          CheckStats {checkedCount = 0, skippedNoOrigin = skipped}
        )
    else do
      let grouped =
            Map.toList $
              Map.fromListWith
                (++)
                [(origin.sourceUrl, [(dm, origin)]) | (dm, origin) <- withOrigins]
      TIO.putStrLn "Checking installed modules for updates..."
      entries <- concat <$> mapM checkSource grouped
      pure
        ( entries,
          CheckStats {checkedCount = length entries, skippedNoOrigin = skipped}
        )

-- | Read origin info from a discovered module's directory.
readOriginWithModule :: DiscoveredModule -> IO (DiscoveredModule, Maybe OriginInfo)
readOriginWithModule dm = do
  let originFile = dm.discoveredDir </> ".seihou-origin.json"
  exists <- doesFileExist originFile
  if exists
    then do
      bs <- LBS.readFile originFile
      case Aeson.decode bs of
        Just info -> pure (dm, Just info)
        Nothing -> pure (dm, Nothing)
    else pure (dm, Nothing)

-- | Check a single source URL for updates. Clones the repo and compares versions.
--
-- The comparison must happen inside 'withSystemTempDirectory' because
-- 'fetchTrueModuleVersion' reads @module.dhall@ off disk. If we returned
-- the clone path to the caller, the temp directory would already be gone
-- by the time the Dhall read ran, and every module would resolve to
-- @Nothing@ (appearing as \"unversioned\").
checkSource :: (Text, [(DiscoveredModule, OriginInfo)]) -> IO [OutdatedEntry]
checkSource (sourceUrl, modulesWithOrigins) = do
  let repoName = parseModuleName sourceUrl
  TIO.putStrLn $ "  Cloning " <> T.pack repoName <> "..."

  result <- try $ withSystemTempDirectory "seihou-outdated" $ \tmpDir -> do
    let cloneDir = tmpDir </> repoName
    (exitCode, _stdout, _stderr) <- readProcessWithExitCode "git" ["clone", "--depth", "1", T.unpack sourceUrl, cloneDir] ""
    case exitCode of
      ExitFailure _ -> pure Nothing
      ExitSuccess ->
        Just <$> mapM (compareModule cloneDir) modulesWithOrigins

  case result of
    Left (_ :: SomeException) ->
      pure [mkUnreachable dm origin | (dm, origin) <- modulesWithOrigins]
    Right Nothing ->
      pure [mkUnreachable dm origin | (dm, origin) <- modulesWithOrigins]
    Right (Just entries) -> pure entries

-- | Compare a single installed module against the remote contents.
compareModule :: FilePath -> (DiscoveredModule, OriginInfo) -> IO OutdatedEntry
compareModule cloneDir (dm, origin) = do
  let name = moduleNameFromDm dm
      installedVer = origin.version
  availableVer <- fetchAvailable cloneDir (ModuleName name)
  let status = compareVersions installedVer availableVer
  pure
    OutdatedEntry
      { moduleName = name,
        installedVersion = installedVer,
        availableVersion = availableVer,
        status = status
      }

-- | Look up the available version of a module in a cloned repo. Wraps
-- 'fetchTrueModuleVersion' so that fetch errors collapse to @Nothing@ for
-- the consumer-facing comparison; downstream renderers display this as
-- "unversioned".
fetchAvailable :: FilePath -> ModuleName -> IO (Maybe Text)
fetchAvailable cloneDir name = do
  result <- fetchTrueModuleVersion cloneDir name
  case result of
    Right v -> pure v
    Left _ -> pure Nothing

-- | Compare installed and available version strings.
-- | Extract the module name text from a DiscoveredModule.
moduleNameFromDm :: DiscoveredModule -> Text
moduleNameFromDm dm = case dm.discoveredResult of
  Right m -> m.name.unModuleName
  Left _ -> dirName dm.discoveredDir

-- | Extract the last path component as a name.
dirName :: FilePath -> Text
dirName path = case reverse (T.splitOn "/" (T.pack path)) of
  (name : _) -> name
  [] -> T.pack path

-- | Create an unreachable entry for a module.
mkUnreachable :: DiscoveredModule -> OriginInfo -> OutdatedEntry
mkUnreachable dm origin =
  OutdatedEntry
    { moduleName = moduleNameFromDm dm,
      installedVersion = origin.version,
      availableVersion = Nothing,
      status = Unreachable
    }

-- | Render the outdated report as a table.
renderTable :: [OutdatedEntry] -> IO ()
renderTable entries = do
  colorEnabled <- useColor
  let maxNameLen = max 6 (maximum (map (T.length . (.moduleName)) entries))
      maxInstLen = max 9 (maximum (map (T.length . maybe "(none)" id . (.installedVersion)) entries))
      maxAvailLen = max 9 (maximum (map (T.length . maybe "(none)" id . (.availableVersion)) entries))

      padR n t = t <> T.replicate (n - T.length t + 2) " "

      header =
        padR maxNameLen "Module"
          <> padR maxInstLen "Installed"
          <> padR maxAvailLen "Available"
          <> "Status"

      formatRow e =
        let instText = maybe "(none)" id e.installedVersion
            availText = maybe "(none)" id e.availableVersion
            statusTxt = case e.status of
              UpToDate -> if colorEnabled then green "up to date" else "up to date"
              OutdatedSt -> if colorEnabled then red "outdated" else "outdated"
              Unversioned -> if colorEnabled then dim "unversioned" else "unversioned"
              Unreachable -> if colorEnabled then yellow "unreachable" else "unreachable"
         in padR maxNameLen e.moduleName
              <> padR maxInstLen instText
              <> padR maxAvailLen availText
              <> statusTxt

  TIO.putStrLn ""
  TIO.putStrLn header
  mapM_ (TIO.putStrLn . formatRow) entries

  let total = length entries
      outdated = length (filter (\e -> e.status == OutdatedSt) entries)
  TIO.putStrLn ""
  TIO.putStrLn $
    T.pack (show total)
      <> " module(s) checked, "
      <> T.pack (show outdated)
      <> " outdated."
