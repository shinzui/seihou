module Seihou.CLI.Install
  ( handleInstall,
    installModuleDir,
    cloneRepo,
    copyDirectoryRecursive,
  )
where

import Data.Generics.Labels ()
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.BrowseFormat (kindLabel)
import Seihou.CLI.Commands (InstallOpts (..))
import Seihou.CLI.InstallClosure (installClosure)
import Seihou.CLI.InstallHistory (HistoryEntry (..), InstallHistory (..), readHistory, recordUrl)
import Seihou.CLI.InstallShared
  ( cloneRepo,
    copyDirectoryRecursive,
    formatRecordedSourceNotice,
    installModuleDir,
    recordedSourceUrl,
    resolveRecordedSource,
  )
import Seihou.CLI.Shared (logIO)
import Seihou.Core.Install (parseModuleName)
import Seihou.Core.Registry (EntryKind (..), Registry (..), RegistryEntry (..), RepoContents (..), discoverRepoContents)
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalRegistryFromFile)
import Seihou.Effect.Fzf (selectOne)
import Seihou.Effect.FzfInterp (runFzfIO)
import Seihou.Effect.Logger (logError)
import Seihou.Fzf (Candidate (..), FzfConfig, FzfResult (..), detectFzfConfig, isFzfUsable, withAnsi, withHeader, withHeight, withNoSort, withPrompt)
import Seihou.Fzf qualified
import Seihou.Prelude
import System.Exit (exitFailure)
import System.IO (hFlush, stdout)
import System.IO.Temp (withSystemTempDirectory)
import Text.Read (readMaybe)

handleInstall :: InstallOpts -> IO ()
handleInstall iopts = do
  source <- resolveSource (iopts ^. #source)

  TIO.putStrLn $ "Installing from " <> source <> "..."

  -- The clone reads from the argument as given; what the installed copy
  -- records as its origin may differ. A local checkout records its published
  -- remote so no machine-local path reaches a project's manifest.
  recordedSource <- resolveRecordedSource source
  mapM_ TIO.putStrLn (formatRecordedSourceNotice recordedSource)
  let recorded = recordedSourceUrl recordedSource

  -- Clone into a temporary directory
  withSystemTempDirectory "seihou-install" $ \tmpDir -> do
    let repoName = parseModuleName source
        cloneDir = tmpDir </> repoName
    cloneRes <- cloneRepo source cloneDir
    case cloneRes of
      Left err -> do
        logIO LogNormal $ do
          logError err
        exitFailure
      Right () -> TIO.putStrLn "  Cloned repository"

    contents <- discoverRepoContents evalRegistryFromFile cloneDir
    roots <- case contents of
      MultiModule registry -> do
        selected <- selectModules iopts registry
        pure [(e ^. #name . #unModuleName, cloneDir </> (e ^. #path)) | e <- selected]
      EmptyRepo -> do
        TIO.putStrLn "No supported artifact or registry found."
        exitFailure
      _ -> pure [(fromMaybe (T.pack repoName) (iopts ^. #name), cloneDir)]
    if null roots
      then TIO.putStrLn "No entries selected."
      else do
        result <- installClosure (iopts ^. #force) cloneDir recorded roots
        case result of
          Left err -> TIO.putStrLn err >> exitFailure
          Right () -> pure ()

  -- Record URL in history for future recall (only reached on success)
  recordUrl source

-- | Resolve the install source: use the explicit URL if given, otherwise pick from history.
resolveSource :: Maybe Text -> IO Text
resolveSource (Just url) = pure url
resolveSource Nothing = do
  history <- readHistory
  case history ^. #entries of
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
            { display = entry ^. #url,
              value = entry ^. #url
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
    (\(i, entry) -> TIO.putStrLn $ "  " <> T.pack (show i) <> ") " <> entry ^. #url)
    numbered
  TIO.putStrLn ""
  TIO.putStr "Select a source (number): "
  hFlush stdout
  input <- TIO.getLine
  case readMaybe (T.unpack (T.strip input)) of
    Just n
      | n >= 1 && n <= length entries ->
          pure ((entries !! (n - 1)) ^. #url)
    _ -> do
      TIO.putStrLn "Invalid selection."
      exitFailure

-- | All registry entries (modules, recipes, blueprints, prompts) in display order.
-- Used wherever installation must treat all four kinds uniformly.
allEntries :: Registry -> [RegistryEntry]
allEntries registry = registry ^. #modules ++ registry ^. #recipes ++ registry ^. #blueprints ++ (registry ^. #prompts)

-- | Pair each registry entry with its 'EntryKind' tag, preserving the
-- module → recipe → blueprint → prompt display order. Used by the install picker
-- to render per-kind labels and by callers that need to discriminate
-- after selection.
labelledEntries :: Registry -> [(EntryKind, RegistryEntry)]
labelledEntries registry =
  map ((,) ModuleEntry) (registry ^. #modules)
    ++ map ((,) RecipeEntry) (registry ^. #recipes)
    ++ map ((,) BlueprintEntry) (registry ^. #blueprints)
    ++ map ((,) PromptEntry) (registry ^. #prompts)

-- | Select which modules to install from a registry.
selectModules :: InstallOpts -> Registry -> IO [RegistryEntry]
selectModules iopts registry
  | (iopts ^. #all) = pure (allEntries registry)
  | not (null (iopts ^. #modules)) = do
      let entries = allEntries registry
          findEntry name = filter (\e -> e ^. #name . #unModuleName == name) entries
          (found, missing) =
            foldr
              ( \name (f, m) -> case findEntry name of
                  (e : _) -> (e : f, m)
                  [] -> (f, name : m)
              )
              ([], [])
              (iopts ^. #modules)
      if not (null missing)
        then do
          logIO LogNormal $ do
            logError "the following entries were not found in the registry:"
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
  let entries = labelledEntries registry
      candidates =
        [ Candidate
            { display =
                kindLabel kind
                  <> "  "
                  <> entry ^. #name . #unModuleName
                  <> maybe "" (\d -> "  " <> d) (entry ^. #description)
                  <> if null (entry ^. #tags) then "" else "  [" <> T.intercalate ", " (entry ^. #tags) <> "]",
              value = entry
            }
        | (kind, entry) <- entries
        ]
      opts = withPrompt "entry> " <> withHeight "40%" <> withAnsi <> withNoSort
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
  TIO.putStrLn $ (registry ^. #repoName)
  case registry ^. #repoDescription of
    Just desc -> TIO.putStrLn $ "  " <> desc
    Nothing -> pure ()
  TIO.putStrLn ""
  TIO.putStrLn "Available modules, recipes, blueprints, and prompts:"
  let entries = zip [1 :: Int ..] (labelledEntries registry)
  mapM_
    ( \(i, (kind, entry)) ->
        TIO.putStrLn $
          "  "
            <> T.pack (show i)
            <> ") "
            <> kindLabel kind
            <> "  "
            <> entry ^. #name . #unModuleName
            <> maybe "" (\d -> " - " <> d) (entry ^. #description)
    )
    entries
  TIO.putStrLn ""
  TIO.putStr "Select entries (comma-separated numbers, or 'all'): "
  hFlush stdout
  input <- TIO.getLine
  let trimmed = T.strip input
  let entryList = allEntries registry
  if T.toLower trimmed == "all"
    then pure entryList
    else do
      let nums = map (readMaybe . T.unpack . T.strip) (T.splitOn "," trimmed)
      if any (== Nothing) nums
        then do
          TIO.putStrLn "Invalid input. Please enter numbers separated by commas."
          pure []
        else do
          let indices = map (\(Just n) -> n) nums
              maxIdx = length entryList
              valid = all (\n -> n >= 1 && n <= maxIdx) indices
          if not valid
            then do
              TIO.putStrLn $ "Invalid selection. Please enter numbers between 1 and " <> T.pack (show maxIdx) <> "."
              pure []
            else pure [entryList !! (n - 1) | n <- indices]
