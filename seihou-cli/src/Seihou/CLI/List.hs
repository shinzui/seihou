module Seihou.CLI.List
  ( handleList,
    formatListOutput,
  )
where

import Data.Aeson (FromJSON (..), withObject, (.:?))
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Shared (shortenHome)
import Seihou.CLI.Style (dim, red, useColor)
import Seihou.Core.Module (DiscoveredModule (..), ModuleSource (..), defaultSearchPaths, discoverAllModules)
import Seihou.Core.Types
import Seihou.Prelude
import System.Directory (doesFileExist)

-- | Origin metadata read from @.seihou-origin.json@.
data OriginInfo = OriginInfo
  { originRepoName :: Maybe Text
  }

instance FromJSON OriginInfo where
  parseJSON = withObject "OriginInfo" $ \v ->
    OriginInfo <$> v .:? "repoName"

handleList :: IO ()
handleList = do
  searchPaths <- defaultSearchPaths
  modules <- discoverAllModules searchPaths
  colorEnabled <- useColor
  shortenedPaths <- mapM shortenHome searchPaths
  -- Read origin metadata for installed modules
  origins <- Map.fromList <$> mapM readOrigin modules
  let entries = map (toEntryWithOrigin origins) modules
  TIO.putStr (formatListOutputEntries colorEnabled entries shortenedPaths)

readOrigin :: DiscoveredModule -> IO (FilePath, Maybe OriginInfo)
readOrigin dm = do
  let originFile = dm.discoveredDir </> ".seihou-origin.json"
  exists <- doesFileExist originFile
  if exists
    then do
      bs <- LBS.readFile originFile
      case Aeson.decode bs of
        Just info -> pure (dm.discoveredDir, Just info)
        Nothing -> pure (dm.discoveredDir, Nothing)
    else pure (dm.discoveredDir, Nothing)

-- | Format list output — backward-compatible version without origin info.
-- Used by tests that construct DiscoveredModule values directly.
formatListOutput :: Bool -> [DiscoveredModule] -> [Text] -> Text
formatListOutput color modules searchPaths =
  let entries = map toEntry modules
   in formatListOutputEntries color entries searchPaths

formatListOutputEntries :: Bool -> [Entry] -> [Text] -> Text
formatListOutputEntries color entries searchPaths
  | null entries =
      "No modules found.\n\nSearched:\n"
        <> T.unlines (map ("  " <>) searchPaths)
  | otherwise =
      let maxNameLen = maximum (map (T.length . (.entryName)) entries)
          maxDescLen = maximum (map (T.length . (.entryDesc)) entries)
          header = "Available modules:\n"
          fileLines = map (formatEntry color maxNameLen maxDescLen) entries
          n = length entries
          nSources = length searchPaths
          noun = if n == 1 then "module" else "modules"
          summary =
            T.pack (show n)
              <> " "
              <> noun
              <> " found ("
              <> T.pack (show nSources)
              <> " sources searched)\n"
       in header <> "\n" <> T.unlines fileLines <> "\n" <> summary

data Entry = Entry
  { entryName :: Text,
    entryDesc :: Text,
    entrySource :: Text,
    entryIsError :: Bool
  }

toEntry :: DiscoveredModule -> Entry
toEntry = toEntryWithOrigin Map.empty

toEntryWithOrigin :: Map FilePath (Maybe OriginInfo) -> DiscoveredModule -> Entry
toEntryWithOrigin origins dm =
  let origin = case Map.lookup dm.discoveredDir origins of
        Just (Just info) -> info.originRepoName
        _ -> Nothing
      srcLabel = sourceLabelWithOrigin dm.discoveredSource origin
   in case dm.discoveredResult of
        Right m ->
          Entry
            { entryName = m.name.unModuleName,
              entryDesc = maybe "(no description)" id m.description,
              entrySource = srcLabel,
              entryIsError = False
            }
        Left err ->
          Entry
            { entryName = dirName dm.discoveredDir,
              entryDesc = "[error: " <> briefError err <> "]",
              entrySource = srcLabel,
              entryIsError = True
            }

sourceLabelWithOrigin :: ModuleSource -> Maybe Text -> Text
sourceLabelWithOrigin SourceProject _ = "project"
sourceLabelWithOrigin SourceUser _ = "user"
sourceLabelWithOrigin SourceInstalled Nothing = "installed"
sourceLabelWithOrigin SourceInstalled (Just rn) = "installed: " <> rn

dirName :: FilePath -> Text
dirName path = case reverse (T.splitOn "/" (T.pack path)) of
  (name : _) -> name
  [] -> T.pack path

briefError :: ModuleLoadError -> Text
briefError (DhallEvalError _ _) = "Dhall evaluation failed"
briefError (DhallDecodeError _ _) = "Dhall decode failed"
briefError (ValidationError _ _) = "validation failed"
briefError (ModuleNotFound _ _) = "not found"
briefError (MissingSourceFile _ _) = "missing source file"
briefError (CircularDependency _) = "circular dependency"
briefError (RegistryEvalError _ _) = "registry eval failed"

formatEntry :: Bool -> Int -> Int -> Entry -> Text
formatEntry color maxNameLen maxDescLen entry =
  let name = entry.entryName
      desc = entry.entryDesc
      src = entry.entrySource
      paddedName = name <> T.replicate (maxNameLen - T.length name + 3) " "
      paddedDesc = desc <> T.replicate (maxDescLen - T.length desc + 3) " "
      srcTag = "(" <> src <> ")"
      colorDesc = if color && entry.entryIsError then red desc else desc
      colorSrc = if color then dim srcTag else srcTag
      colorPaddedDesc = colorDesc <> T.replicate (maxDescLen - T.length desc + 3) " "
   in "  " <> paddedName <> (if color && entry.entryIsError then colorPaddedDesc else paddedDesc) <> colorSrc
