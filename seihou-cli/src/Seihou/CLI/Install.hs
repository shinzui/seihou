module Seihou.CLI.Install
  ( handleInstall,
    installModuleDir,
    cloneRepo,
    copyDirectoryRecursive,
  )
where

import Control.Applicative ((<|>))
import Control.Monad (when)
import Data.Aeson (ToJSON (..), object, (.=))
import Data.Aeson.Encode.Pretty (encodePretty)
import Data.ByteString.Lazy qualified as LBS
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (getCurrentTime)
import Data.Time.Format.ISO8601 (iso8601Show)
import Seihou.CLI.Commands (InstallOpts (..))
import Seihou.CLI.InstallHistory (HistoryEntry (..), InstallHistory (..), readHistory, recordUrl)
import Seihou.CLI.Shared (logIO)
import Seihou.Core.Install (parseModuleName)
import Seihou.Core.Module (validateModule)
import Seihou.Core.Registry (Registry (..), RegistryEntry (..), RepoContents (..), discoverRepoContents, validateRegistry)
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalModuleFromFile, evalRegistryFromFile)
import Seihou.Effect.Fzf (selectOne)
import Seihou.Effect.FzfInterp (runFzfIO)
import Seihou.Effect.Logger (logError, logWarn)
import Seihou.Fzf (Candidate (..), FzfConfig, FzfResult (..), detectFzfConfig, isFzfUsable, withAnsi, withHeader, withHeight, withNoSort, withPrompt)
import Seihou.Fzf qualified
import Seihou.Prelude
import System.Directory
  ( XdgDirectory (..),
    copyFile,
    createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    getXdgDirectory,
    listDirectory,
    removeDirectoryRecursive,
  )
import System.Exit (ExitCode (..), exitFailure)
import System.IO (hFlush, stdout)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)

handleInstall :: InstallOpts -> IO ()
handleInstall iopts = do
  source <- resolveSource iopts.installSource

  TIO.putStrLn $ "Installing from " <> source <> "..."

  -- Clone into a temporary directory
  withSystemTempDirectory "seihou-install" $ \tmpDir -> do
    let repoName = parseModuleName source
        cloneDir = tmpDir </> repoName
    cloneRepo source cloneDir

    -- Determine what the repo contains
    contents <- discoverRepoContents evalRegistryFromFile cloneDir
    case contents of
      EmptyRepo -> do
        logIO LogNormal (logError "repository contains neither seihou-registry.dhall nor module.dhall.")
        exitFailure
      SingleModule rootDir -> do
        when (not (null iopts.installModules) || iopts.installAll) $
          logIO LogNormal (logWarn "--module and --all flags are ignored for single-module repositories.")
        installSingleModule iopts rootDir source Nothing
      SingleRecipe rootDir -> do
        when (not (null iopts.installModules) || iopts.installAll) $
          logIO LogNormal (logWarn "--module and --all flags are ignored for single-recipe repositories.")
        installSingleRecipe iopts rootDir source
      MultiModule registry -> do
        regErrors <- validateRegistry cloneDir registry
        if not (null regErrors)
          then do
            logIO LogNormal $ do
              logError "registry has validation errors:"
              mapM_ (\e -> logError $ "  - " <> e) regErrors
            exitFailure
          else installFromRegistry iopts cloneDir registry source

  -- Record URL in history for future recall (only reached on success)
  recordUrl source

-- | Resolve the install source: use the explicit URL if given, otherwise pick from history.
resolveSource :: Maybe Text -> IO Text
resolveSource (Just url) = pure url
resolveSource Nothing = do
  history <- readHistory
  case history.entries of
    [] -> do
      TIO.putStrLn "No URL specified and no install history found."
      TIO.putStrLn "Usage: seihou install <git-url>"
      exitFailure
    entries -> do
      fzfCfg <- detectFzfConfig
      if isFzfUsable fzfCfg
        then fzfUrlSelection fzfCfg entries
        else promptUrlSelection entries

-- | FZF selection of a URL from history.
fzfUrlSelection :: FzfConfig -> [HistoryEntry] -> IO Text
fzfUrlSelection fzfCfg entries = do
  let candidates =
        [ Candidate
            { candidateDisplay = entry.url,
              candidateValue = entry.url
            }
        | entry <- entries
        ]
      opts = withPrompt "install> " <> withHeader "Select a previously used source:" <> withHeight "40%" <> withAnsi <> withNoSort
  result <- runEff $ runFzfIO fzfCfg $ selectOne opts candidates
  case result of
    FzfSelected url -> pure url
    FzfCancelled -> do
      TIO.putStrLn "Cancelled."
      exitFailure
    FzfNoMatch -> do
      TIO.putStrLn "No match."
      exitFailure
    FzfError err -> do
      TIO.putStrLn $ "fzf error: " <> err <> ", falling back to prompt"
      promptUrlSelection entries

-- | Numbered prompt fallback for URL selection.
promptUrlSelection :: [HistoryEntry] -> IO Text
promptUrlSelection entries = do
  TIO.putStrLn ""
  TIO.putStrLn "Previously used sources:"
  let numbered = zip [1 :: Int ..] entries
  mapM_
    (\(i, entry) -> TIO.putStrLn $ "  " <> T.pack (show i) <> ") " <> entry.url)
    numbered
  TIO.putStrLn ""
  TIO.putStr "Select a source (number): "
  hFlush stdout
  input <- TIO.getLine
  case readMaybe (T.unpack (T.strip input)) of
    Just n
      | n >= 1 && n <= length entries ->
          pure (entries !! (n - 1)).url
    _ -> do
      TIO.putStrLn "Invalid selection."
      exitFailure

-- | Clone a git repo shallowly into the target directory.
cloneRepo :: Text -> FilePath -> IO ()
cloneRepo source cloneDir = do
  (exitCode, _stdout, stderr) <- readProcessWithExitCode "git" ["clone", "--depth", "1", T.unpack source, cloneDir] ""
  case exitCode of
    ExitFailure _ -> do
      logIO LogNormal $ do
        logError $ "git clone failed for '" <> source <> "'."
        logError $ "  " <> T.pack stderr
      exitFailure
    ExitSuccess -> pure ()
  TIO.putStrLn "  Cloned repository"

-- | Install a single-module repo (legacy behavior).
installSingleModule :: InstallOpts -> FilePath -> Text -> Maybe Text -> IO ()
installSingleModule iopts rootDir source registryName = do
  let name = case iopts.installName of
        Just n -> T.unpack n
        Nothing -> parseModuleName source

  let dhallFile = rootDir </> "module.dhall"
  decoded <- evalModuleFromFile dhallFile
  modul <- case decoded of
    Left err -> do
      logIO LogNormal $ do
        logError "repository is not a valid seihou module."
        logError $ "  " <> T.pack (show err)
      exitFailure
    Right m -> pure m

  result <- validateModule rootDir modul
  case result of
    Left (ValidationError _ errors) -> do
      logIO LogNormal $ do
        logError "module has validation errors:"
        mapM_ (\e -> logError $ "  - " <> e) errors
      exitFailure
    Left err -> do
      logIO LogNormal (logError $ T.pack (show err))
      exitFailure
    Right _ -> pure ()
  TIO.putStrLn "  Validated module definition"

  installModuleDir rootDir name source registryName modul.version []
  TIO.putStrLn ""
  TIO.putStrLn $ "Module available as: " <> T.pack name

-- | Install a single-recipe repo.
installSingleRecipe :: InstallOpts -> FilePath -> Text -> IO ()
installSingleRecipe iopts rootDir source = do
  let name = case iopts.installName of
        Just n -> T.unpack n
        Nothing -> parseModuleName source

  -- Validate recipe.dhall exists (discoverRepoContents already confirmed it)
  TIO.putStrLn "  Validated recipe definition"

  installModuleDir rootDir name source Nothing Nothing []
  TIO.putStrLn ""
  TIO.putStrLn $ "Recipe available as: " <> T.pack name

-- | Install from a multi-module registry.
installFromRegistry :: InstallOpts -> FilePath -> Registry -> Text -> IO ()
installFromRegistry iopts cloneDir registry source = do
  selected <- selectModules iopts registry
  if null selected
    then TIO.putStrLn "No modules selected."
    else do
      results <- mapM (installRegistryEntry cloneDir source registry.repoName) selected
      let succeeded = length (filter id results)
          failed = length results - succeeded
      TIO.putStrLn ""
      TIO.putStrLn $
        T.pack (show succeeded)
          <> " module(s) installed"
          <> (if failed > 0 then ", " <> T.pack (show failed) <> " failed" else "")
          <> "."

-- | Select which modules to install from a registry.
selectModules :: InstallOpts -> Registry -> IO [RegistryEntry]
selectModules iopts registry
  | iopts.installAll = pure (registry.modules ++ registry.recipes)
  | not (null iopts.installModules) = do
      let entries = registry.modules ++ registry.recipes
          findEntry name = filter (\e -> e.name.unModuleName == name) entries
          (found, missing) =
            foldr
              ( \name (f, m) -> case findEntry name of
                  (e : _) -> (e : f, m)
                  [] -> (f, name : m)
              )
              ([], [])
              iopts.installModules
      if not (null missing)
        then do
          logIO LogNormal $ do
            logError "the following modules were not found in the registry:"
            mapM_ (\n -> logError $ "  - " <> n) missing
          exitFailure
        else pure found
  | otherwise = do
      fzfCfg <- detectFzfConfig
      if isFzfUsable fzfCfg
        then fzfModuleSelection fzfCfg registry
        else promptModuleSelection registry

-- | Interactive module selection via fzf.
fzfModuleSelection :: Seihou.Fzf.FzfConfig -> Registry -> IO [RegistryEntry]
fzfModuleSelection fzfCfg registry = do
  let entries = registry.modules ++ registry.recipes
      candidates =
        [ Candidate
            { candidateDisplay =
                entry.name.unModuleName
                  <> maybe "" (\d -> "  " <> d) entry.description
                  <> if null entry.tags then "" else "  [" <> T.intercalate ", " entry.tags <> "]",
              candidateValue = entry
            }
        | entry <- entries
        ]
      opts = withPrompt "module> " <> withHeight "40%" <> withAnsi <> withNoSort
  result <- runEff $ runFzfIO fzfCfg $ selectOne opts candidates
  case result of
    FzfSelected entry -> pure [entry]
    FzfCancelled -> pure []
    FzfNoMatch -> pure []
    FzfError err -> do
      TIO.putStrLn $ "fzf error: " <> err
      promptModuleSelection registry

-- | Interactive module selection via numbered list.
promptModuleSelection :: Registry -> IO [RegistryEntry]
promptModuleSelection registry = do
  TIO.putStrLn ""
  TIO.putStrLn $ registry.repoName
  case registry.repoDescription of
    Just desc -> TIO.putStrLn $ "  " <> desc
    Nothing -> pure ()
  TIO.putStrLn ""
  TIO.putStrLn "Available modules and recipes:"
  let entries = zip [1 :: Int ..] (registry.modules ++ registry.recipes)
  mapM_
    ( \(i, entry) ->
        TIO.putStrLn $
          "  "
            <> T.pack (show i)
            <> ") "
            <> entry.name.unModuleName
            <> maybe "" (\d -> " - " <> d) entry.description
    )
    entries
  TIO.putStrLn ""
  TIO.putStr "Select modules (comma-separated numbers, or 'all'): "
  hFlush stdout
  input <- TIO.getLine
  let trimmed = T.strip input
  let allEntries = registry.modules ++ registry.recipes
  if T.toLower trimmed == "all"
    then pure allEntries
    else do
      let nums = map (readMaybe . T.unpack . T.strip) (T.splitOn "," trimmed)
      if any (== Nothing) nums
        then do
          TIO.putStrLn "Invalid input. Please enter numbers separated by commas."
          pure []
        else do
          let indices = map (\(Just n) -> n) nums
              maxIdx = length allEntries
              valid = all (\n -> n >= 1 && n <= maxIdx) indices
          if not valid
            then do
              TIO.putStrLn $ "Invalid selection. Please enter numbers between 1 and " <> T.pack (show maxIdx) <> "."
              pure []
            else pure [allEntries !! (n - 1) | n <- indices]

-- | Install a single registry entry (module or recipe).
installRegistryEntry :: FilePath -> Text -> Text -> RegistryEntry -> IO Bool
installRegistryEntry cloneDir source repoName entry = do
  let entryDir = cloneDir </> entry.path
      name = T.unpack entry.name.unModuleName
      moduleDhall = entryDir </> "module.dhall"
      recipeDhall = entryDir </> "recipe.dhall"
  TIO.putStrLn $ "  Installing " <> entry.name.unModuleName <> "..."

  hasModule <- doesFileExist moduleDhall
  if hasModule
    then do
      decoded <- evalModuleFromFile moduleDhall
      case decoded of
        Left err -> do
          logIO LogNormal $ do
            logError $ "  failed to load " <> entry.name.unModuleName <> ": " <> T.pack (show err)
          pure False
        Right modul -> do
          result <- validateModule entryDir modul
          case result of
            Left (ValidationError _ errors) -> do
              logIO LogNormal $ do
                logError $ "  " <> entry.name.unModuleName <> " has validation errors:"
                mapM_ (\e -> logError $ "    - " <> e) errors
              pure False
            Left err -> do
              logIO LogNormal (logError $ "  " <> T.pack (show err))
              pure False
            Right _ -> do
              let ver = entry.version <|> modul.version
              installModuleDir entryDir name source (Just repoName) ver entry.tags
              TIO.putStrLn $ "    Installed as: " <> T.pack name
              pure True
    else do
      hasRecipe <- doesFileExist recipeDhall
      if hasRecipe
        then do
          installModuleDir entryDir name source (Just repoName) entry.version entry.tags
          TIO.putStrLn $ "    Installed recipe as: " <> T.pack name
          pure True
        else do
          logIO LogNormal $ do
            logError $ "  entry '" <> entry.name.unModuleName <> "' has neither module.dhall nor recipe.dhall at " <> T.pack entry.path
          pure False

-- | Copy a module directory to the install location and write origin metadata.
installModuleDir :: FilePath -> String -> Text -> Maybe Text -> Maybe Text -> [Text] -> IO ()
installModuleDir moduleDir name source registryName moduleVersion moduleTags = do
  xdgConfig <- getXdgDirectory XdgConfig "seihou"
  let installDir = xdgConfig </> "installed" </> name

  exists <- doesDirectoryExist installDir
  when exists $ do
    logIO LogNormal (logWarn $ "overwriting existing installation of '" <> T.pack name <> "'")
    removeDirectoryRecursive installDir

  createDirectoryIfMissing True installDir
  copyDirectoryRecursive moduleDir installDir

  -- Write origin metadata
  now <- getCurrentTime
  let origin = OriginMeta source registryName (T.pack (iso8601Show now)) moduleVersion moduleTags
  LBS.writeFile (installDir </> ".seihou-origin.json") (encodePretty origin)

-- | Origin metadata stored alongside installed modules.
data OriginMeta = OriginMeta
  { sourceUrl :: Text,
    repoName :: Maybe Text,
    installedAt :: Text,
    version :: Maybe Text,
    tags :: [Text]
  }

instance ToJSON OriginMeta where
  toJSON m = object ["sourceUrl" .= m.sourceUrl, "repoName" .= m.repoName, "installedAt" .= m.installedAt, "version" .= m.version, "tags" .= m.tags]

-- | Recursively copy a directory tree, excluding the @.git@ directory.
copyDirectoryRecursive :: FilePath -> FilePath -> IO ()
copyDirectoryRecursive src dst = do
  entries <- listDirectory src
  mapM_ (copyEntry src dst) entries
  where
    copyEntry s d entry
      | entry == ".git" = pure ()
      | otherwise = do
          let srcPath = s </> entry
              dstPath = d </> entry
          isDir <- doesDirectoryExist srcPath
          if isDir
            then do
              createDirectoryIfMissing True dstPath
              copyDirectoryRecursive srcPath dstPath
            else copyFile srcPath dstPath

readMaybe :: String -> Maybe Int
readMaybe s = case reads s of
  [(n, "")] -> Just n
  _ -> Nothing
