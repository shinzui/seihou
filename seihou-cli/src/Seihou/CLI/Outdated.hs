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
where

import Control.Exception (SomeException, try)
import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Encode.Pretty (encodePretty)
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (OutdatedOpts (..))
import Seihou.CLI.Style (dim, green, red, useColor, yellow)
import Seihou.Core.Install (parseModuleName)
import Seihou.Core.Module (DiscoveredModule (..), ModuleSource (..), defaultSearchPaths, discoverAllModules)
import Seihou.Core.Registry (Registry (..), RegistryEntry (..), RepoContents (..), discoverRepoContents)
import Seihou.Core.Types (Module (..), ModuleName (..))
import Seihou.Core.Version (Version, parseVersion, renderVersion)
import Seihou.Dhall.Eval (evalModuleFromFile, evalRegistryFromFile)
import Seihou.Prelude
import System.Directory (doesFileExist)
import System.Exit (ExitCode (..))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)

-- | Status of a module with respect to available updates.
data OutdatedStatus
  = UpToDate
  | OutdatedSt
  | Unversioned
  | Unreachable
  deriving stock (Eq, Show)

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

-- | Origin metadata read from @.seihou-origin.json@.
data OriginInfo = OriginInfo
  { sourceUrl :: Text,
    repoName :: Maybe Text,
    version :: Maybe Text
  }

instance FromJSON OriginInfo where
  parseJSON = withObject "OriginInfo" $ \v ->
    OriginInfo <$> v .: "sourceUrl" <*> v .:? "repoName" <*> v .:? "version"

handleOutdated :: OutdatedOpts -> IO ()
handleOutdated oopts = do
  searchPaths <- defaultSearchPaths
  modules <- discoverAllModules searchPaths

  -- Filter to installed modules only
  let installed = filter (\dm -> dm.discoveredSource == SourceInstalled) modules

  if null installed
    then TIO.putStrLn "No installed modules found."
    else do
      -- Read origin metadata for each installed module
      originsWithModules <- mapM readOriginWithModule installed
      let withOrigins = [(dm, origin) | (dm, Just origin) <- originsWithModules]

      if null withOrigins
        then TIO.putStrLn "No installed modules with origin metadata found."
        else do
          -- Group by source URL
          let grouped = Map.toList $ Map.fromListWith (++) [(origin.sourceUrl, [(dm, origin)]) | (dm, origin) <- withOrigins]

          TIO.putStrLn "Checking installed modules for updates..."
          entries <- concat <$> mapM checkSource grouped

          if oopts.outdatedJson
            then LBS.putStr (encodePretty entries)
            else renderTable entries

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
checkSource :: (Text, [(DiscoveredModule, OriginInfo)]) -> IO [OutdatedEntry]
checkSource (sourceUrl, modulesWithOrigins) = do
  let repoName = parseModuleName sourceUrl
  TIO.putStrLn $ "  Cloning " <> T.pack repoName <> "..."

  result <- try $ withSystemTempDirectory "seihou-outdated" $ \tmpDir -> do
    let cloneDir = tmpDir </> repoName
    (exitCode, _stdout, _stderr) <- readProcessWithExitCode "git" ["clone", "--depth", "1", T.unpack sourceUrl, cloneDir] ""
    case exitCode of
      ExitFailure _ -> pure Nothing
      ExitSuccess -> do
        contents <- discoverRepoContents evalRegistryFromFile cloneDir
        pure (Just (cloneDir, contents))

  case result of
    Left (_ :: SomeException) ->
      pure [mkUnreachable dm origin | (dm, origin) <- modulesWithOrigins]
    Right Nothing ->
      pure [mkUnreachable dm origin | (dm, origin) <- modulesWithOrigins]
    Right (Just (cloneDir, contents)) ->
      mapM (compareModule cloneDir contents) modulesWithOrigins

-- | Compare a single installed module against the remote contents.
compareModule :: FilePath -> RepoContents -> (DiscoveredModule, OriginInfo) -> IO OutdatedEntry
compareModule cloneDir contents (dm, origin) = do
  let name = moduleNameFromDm dm
      installedVer = origin.version
  availableVer <- findAvailableVersion cloneDir contents name
  let status = compareVersions installedVer availableVer
  pure
    OutdatedEntry
      { moduleName = name,
        installedVersion = installedVer,
        availableVersion = availableVer,
        status = status
      }

-- | Find the available version for a module name in the remote repo contents.
findAvailableVersion :: FilePath -> RepoContents -> Text -> IO (Maybe Text)
findAvailableVersion cloneDir contents name = case contents of
  SingleModule rootDir -> do
    let dhallFile = rootDir </> "module.dhall"
    decoded <- evalModuleFromFile dhallFile
    case decoded of
      Right m -> pure m.version
      Left _ -> pure Nothing
  MultiModule registry -> do
    -- Find the matching entry by name
    let matchingEntries = filter (\e -> e.name.unModuleName == name) registry.modules
    case matchingEntries of
      (entry : _) -> do
        -- Try registry entry version first, then module.dhall version
        case entry.version of
          Just v -> pure (Just v)
          Nothing -> do
            let dhallFile = cloneDir </> entry.path </> "module.dhall"
            decoded <- evalModuleFromFile dhallFile
            case decoded of
              Right m -> pure m.version
              Left _ -> pure Nothing
      [] -> pure Nothing
  EmptyRepo -> pure Nothing

-- | Compare installed and available version strings.
compareVersions :: Maybe Text -> Maybe Text -> OutdatedStatus
compareVersions (Just instText) (Just availText) =
  case (parseVersion instText, parseVersion availText) of
    (Just instV, Just availV)
      | instV < availV -> OutdatedSt
      | otherwise -> UpToDate
    _ -> Unversioned -- unparseable version treated as unversioned
compareVersions _ _ = Unversioned

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
