module Seihou.CLI.List
  ( handleList,
    formatListOutput,
    applyFilters,
    ListFilter (..),
    Entry (..),
  )
where

import Data.Aeson (FromJSON (..), withObject, (.:?))
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Shared (shortenHome)
import Seihou.CLI.Style (dim, red, useColor)
import Seihou.Core.Module (DiscoveredModule (..), DiscoveredRunnable (..), ModuleSource (..), RunnableKind (..), defaultSearchPaths, discoverAllModules, discoverAllRunnables)
import Seihou.Core.Types
import Seihou.Prelude
import System.Directory (doesFileExist)

-- | Origin metadata read from @.seihou-origin.json@.
data OriginInfo = OriginInfo
  { originRepoName :: Maybe Text,
    originVersion :: Maybe Text,
    originTags :: [Text]
  }

instance FromJSON OriginInfo where
  parseJSON = withObject "OriginInfo" $ \v ->
    OriginInfo <$> v .:? "repoName" <*> v .:? "version" <*> (fromMaybe [] <$> v .:? "tags")

-- | Filter criteria for the list command.  Defined here (rather than
-- imported from Commands) so the internal library does not depend on
-- optparse-applicative.
data ListFilter = ListFilter
  { filterRepo :: Maybe Text,
    filterTag :: Maybe Text
  }
  deriving stock (Eq, Show)

noFilter :: ListFilter
noFilter = ListFilter Nothing Nothing

handleList :: ListFilter -> IO ()
handleList listOpts = do
  searchPaths <- defaultSearchPaths
  runnables <- discoverAllRunnables searchPaths
  colorEnabled <- useColor
  shortenedPaths <- mapM shortenHome searchPaths
  -- Read origin metadata for installed items
  origins <- Map.fromList <$> mapM readRunnableOrigin runnables
  let entries = map (runnableToEntryWithOrigin origins) runnables
      filtered = applyFilters listOpts entries
  TIO.putStr (formatListOutputEntries colorEnabled filtered shortenedPaths listOpts)

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

readRunnableOrigin :: DiscoveredRunnable -> IO (FilePath, Maybe OriginInfo)
readRunnableOrigin dr = do
  let originFile = dr.drDir </> ".seihou-origin.json"
  exists <- doesFileExist originFile
  if exists
    then do
      bs <- LBS.readFile originFile
      case Aeson.decode bs of
        Just info -> pure (dr.drDir, Just info)
        Nothing -> pure (dr.drDir, Nothing)
    else pure (dr.drDir, Nothing)

runnableToEntryWithOrigin :: Map FilePath (Maybe OriginInfo) -> DiscoveredRunnable -> Entry
runnableToEntryWithOrigin origins dr =
  let (originName, originVer, originTags) = case Map.lookup dr.drDir origins of
        Just (Just info) -> (info.originRepoName, info.originVersion, info.originTags)
        _ -> (Nothing, Nothing, [])
      srcLabel = sourceLabelWithOrigin dr.drSource originName originVer
      kindSuffix = case dr.drKind of
        KindModule -> ""
        KindRecipe -> " [recipe]"
   in if dr.drIsError
        then
          Entry
            { entryName = dr.drName,
              entryDesc = "[error: " <> fromMaybe "unknown" dr.drError <> "]",
              entrySource = srcLabel <> kindSuffix,
              entryIsError = True,
              entryRepoName = originName,
              entryTags = originTags
            }
        else
          Entry
            { entryName = dr.drName,
              entryDesc = fromMaybe "(no description)" dr.drDescription,
              entrySource = srcLabel <> kindSuffix,
              entryIsError = False,
              entryRepoName = originName,
              entryTags = originTags
            }

-- | Format list output — backward-compatible version without origin info.
-- Used by tests that construct DiscoveredModule values directly.
formatListOutput :: Bool -> [DiscoveredModule] -> [Text] -> Text
formatListOutput color modules searchPaths =
  let entries = map toEntry modules
   in formatListOutputEntries color entries searchPaths noFilter

formatListOutputEntries :: Bool -> [Entry] -> [Text] -> ListFilter -> Text
formatListOutputEntries color entries searchPaths listOpts
  | null entries =
      "No modules found."
        <> filterSuffix
        <> "\n\nSearched:\n"
        <> T.unlines (map ("  " <>) searchPaths)
  | otherwise =
      let maxNameLen = maximum (map (T.length . (.entryName)) entries)
          maxDescLen = maximum (map (T.length . (.entryDesc)) entries)
          header = "Available modules and recipes:\n"
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
              <> " sources searched)"
              <> filterSuffix
              <> "\n"
       in header <> "\n" <> T.unlines fileLines <> "\n" <> summary
  where
    filterSuffix = formatFilterSuffix listOpts

-- | Build a display suffix describing the active filters, e.g.
-- @" [filtered: repo=foo, tag=bar]"@.  Returns empty text when no filters
-- are active.
formatFilterSuffix :: ListFilter -> Text
formatFilterSuffix opts =
  let parts =
        maybe [] (\r -> ["repo=" <> r]) opts.filterRepo
          <> maybe [] (\t -> ["tag=" <> t]) opts.filterTag
   in if null parts
        then ""
        else " [filtered: " <> T.intercalate ", " parts <> "]"

-- | Apply repo and tag filters to a list of entries.  Both filters combine
-- with AND: an entry must match all active filters to be included.
applyFilters :: ListFilter -> [Entry] -> [Entry]
applyFilters opts = filter match
  where
    match entry = repoMatch entry && tagMatch entry
    repoMatch entry = case opts.filterRepo of
      Nothing -> True
      Just r -> entry.entryRepoName == Just r
    tagMatch entry = case opts.filterTag of
      Nothing -> True
      Just t -> t `elem` entry.entryTags

data Entry = Entry
  { entryName :: Text,
    entryDesc :: Text,
    entrySource :: Text,
    entryIsError :: Bool,
    entryRepoName :: Maybe Text,
    entryTags :: [Text]
  }
  deriving stock (Eq, Show)

toEntry :: DiscoveredModule -> Entry
toEntry = toEntryWithOrigin Map.empty

toEntryWithOrigin :: Map FilePath (Maybe OriginInfo) -> DiscoveredModule -> Entry
toEntryWithOrigin origins dm =
  let (originName, originVer, originTags) = case Map.lookup dm.discoveredDir origins of
        Just (Just info) -> (info.originRepoName, info.originVersion, info.originTags)
        _ -> (Nothing, Nothing, [])
      srcLabel = sourceLabelWithOrigin dm.discoveredSource originName originVer
   in case dm.discoveredResult of
        Right m ->
          Entry
            { entryName = m.name.unModuleName,
              entryDesc = maybe "(no description)" id m.description,
              entrySource = srcLabel,
              entryIsError = False,
              entryRepoName = originName,
              entryTags = originTags
            }
        Left err ->
          Entry
            { entryName = dirName dm.discoveredDir,
              entryDesc = "[error: " <> briefError err <> "]",
              entrySource = srcLabel,
              entryIsError = True,
              entryRepoName = originName,
              entryTags = originTags
            }

sourceLabelWithOrigin :: ModuleSource -> Maybe Text -> Maybe Text -> Text
sourceLabelWithOrigin SourceProject _ _ = "project"
sourceLabelWithOrigin SourceUser _ _ = "user"
sourceLabelWithOrigin SourceInstalled Nothing Nothing = "installed"
sourceLabelWithOrigin SourceInstalled (Just rn) Nothing = "installed: " <> rn
sourceLabelWithOrigin SourceInstalled (Just rn) (Just v) = "installed: " <> rn <> " v" <> v
sourceLabelWithOrigin SourceInstalled Nothing (Just v) = "installed v" <> v

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
