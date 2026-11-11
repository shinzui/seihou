module Seihou.CLI.List
  ( handleList,
    formatListOutput,
    formatListOutputEntries,
    applyFilters,
    ListFilter (..),
    DescriptionMode (..),
    Entry (..),
    runnableToEntryWithOrigin,
  )
where

import Data.Aeson (FromJSON (..), withObject, (.:?))
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.List (intercalate, sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Shared (shortenHome)
import Seihou.CLI.Style (bold, dim, red, useColor)
import Seihou.CLI.TextLayout (truncateForSummary, wrapParagraphs)
import Seihou.Core.Module (DiscoveredModule (..), DiscoveredRunnable (..), ModuleSource (..), RunnableKind (..), defaultSearchPaths, discoverAllModules, discoverAllRunnables)
import Seihou.Core.Types
import Seihou.Prelude
import System.Directory (doesFileExist)

-- | Origin metadata read from @.seihou-origin.json@.
data OriginInfo = OriginInfo
  { repoName :: !(Maybe Text),
    version :: !(Maybe Text),
    tags :: ![Text]
  }
  deriving stock (Generic)

instance FromJSON OriginInfo where
  parseJSON = withObject "OriginInfo" $ \v ->
    OriginInfo <$> v .:? "repoName" <*> v .:? "version" <*> (fromMaybe [] <$> v .:? "tags")

-- | Filter criteria for the list command.  Defined here (rather than
-- imported from Commands) so the internal library does not depend on
-- optparse-applicative.
data ListFilter = ListFilter
  { repo :: !(Maybe Text),
    tag :: !(Maybe Text),
    kinds :: ![RunnableKind]
  }
  deriving stock (Eq, Generic, Show)

noFilter :: ListFilter
noFilter = ListFilter Nothing Nothing []

-- | How the list shows each entry's description: bounded to one line by
-- default, or in full (word-wrapped at a fixed width) when @--full@ asks for it.
data DescriptionMode = BoundedDescriptions | FullDescriptions
  deriving stock (Eq, Show, Generic)

handleList :: ListFilter -> DescriptionMode -> IO ()
handleList listOpts mode = do
  searchPaths <- defaultSearchPaths
  runnables <- discoverAllRunnables searchPaths
  colorEnabled <- useColor
  shortenedPaths <- mapM shortenHome searchPaths
  -- Read origin metadata for installed items
  origins <- Map.fromList <$> mapM readRunnableOrigin runnables
  let entries = map (runnableToEntryWithOrigin origins) runnables
      filtered = applyFilters listOpts entries
  TIO.putStr (formatListOutputEntries colorEnabled mode filtered shortenedPaths listOpts)

readOrigin :: DiscoveredModule -> IO (FilePath, Maybe OriginInfo)
readOrigin dm = do
  let originFile = dm ^. #dir </> ".seihou-origin.json"
  exists <- doesFileExist originFile
  if exists
    then do
      bs <- LBS.readFile originFile
      case Aeson.decode bs of
        Just info -> pure (dm ^. #dir, Just info)
        Nothing -> pure (dm ^. #dir, Nothing)
    else pure (dm ^. #dir, Nothing)

readRunnableOrigin :: DiscoveredRunnable -> IO (FilePath, Maybe OriginInfo)
readRunnableOrigin dr = do
  let originFile = dr ^. #dir </> ".seihou-origin.json"
  exists <- doesFileExist originFile
  if exists
    then do
      bs <- LBS.readFile originFile
      case Aeson.decode bs of
        Just info -> pure (dr ^. #dir, Just info)
        Nothing -> pure (dr ^. #dir, Nothing)
    else pure (dr ^. #dir, Nothing)

runnableToEntryWithOrigin :: Map FilePath (Maybe OriginInfo) -> DiscoveredRunnable -> Entry
runnableToEntryWithOrigin origins dr =
  let (originName, originVer, tags) = case Map.lookup (dr ^. #dir) origins of
        Just (Just info) -> (info ^. #repoName, info ^. #version, info ^. #tags)
        _ -> (Nothing, Nothing, [])
      -- The kind is not part of the label: 'formatListOutputEntries' shows it
      -- once, as the heading of the section the entry is listed under.
      srcLabel = sourceLabelWithOrigin (dr ^. #source) originName originVer
   in if dr ^. #isError
        then
          Entry
            { name = dr ^. #name,
              desc = "[error: " <> fromMaybe "unknown" (dr ^. #error) <> "]",
              source = srcLabel,
              isError = True,
              repoName = originName,
              tags = tags,
              kind = dr ^. #kind
            }
        else
          Entry
            { name = dr ^. #name,
              desc = fromMaybe "(no description)" (dr ^. #description),
              source = srcLabel,
              isError = False,
              repoName = originName,
              tags = tags,
              kind = dr ^. #kind
            }

-- | Format list output — backward-compatible version without origin info.
-- Used by tests that construct DiscoveredModule values directly.
formatListOutput :: Bool -> [DiscoveredModule] -> [Text] -> Text
formatListOutput color modules searchPaths =
  let entries = map toEntry modules
   in formatListOutputEntries color BoundedDescriptions entries searchPaths noFilter

formatListOutputEntries :: Bool -> DescriptionMode -> [Entry] -> [Text] -> ListFilter -> Text
formatListOutputEntries color mode entries searchPaths listOpts
  | null entries =
      -- With nothing to show, the kind comes from the active filter (if any).
      "No "
        <> pluralize 0 (summaryNoun (listOpts ^. #kinds))
        <> " found."
        <> filterSuffix
        <> "\n\nSearched:\n"
        <> T.unlines (map ("  " <>) searchPaths)
  | otherwise =
      let n = length entries
          nSources = length searchPaths
          -- The count noun reflects the kinds actually shown: a single shared
          -- kind names that kind; a mix falls back to the neutral "item".
          noun = pluralize n (summaryNoun (map (^. #kind) entries))
          summary =
            T.pack (show n)
              <> " "
              <> noun
              <> " found ("
              <> T.pack (show nSources)
              <> " sources searched)"
              <> filterSuffix
              <> "\n"
       in T.unlines (formatSections color mode entries) <> summary
  where
    filterSuffix = formatFilterSuffix listOpts

-- | Choose the singular base noun for a set of kinds.  When every kind is the
-- same, name it ("module", "recipe", "blueprint"); when the set is empty or
-- mixed, fall back to the neutral "item".
summaryNoun :: [RunnableKind] -> Text
summaryNoun kinds = case kinds of
  [] -> "item"
  (k : ks)
    | all (== k) ks -> kindBase k
    | otherwise -> "item"
  where
    kindBase KindModule = "module"
    kindBase KindRecipe = "recipe"
    kindBase KindBlueprint = "blueprint"
    kindBase KindPrompt = "prompt"

-- | Append @s@ to a singular noun unless the count is exactly one.
pluralize :: Int -> Text -> Text
pluralize n base = if n == 1 then base else base <> "s"

-- | Build a display suffix describing the active filters, e.g.
-- @" [filtered: repo=foo, tag=bar]"@.  Returns empty text when no filters
-- are active.
formatFilterSuffix :: ListFilter -> Text
formatFilterSuffix opts =
  let parts =
        maybe [] (\r -> ["repo=" <> r]) (opts ^. #repo)
          <> maybe [] (\t -> ["tag=" <> t]) (opts ^. #tag)
          <> kindPart
      kindPart = case opts ^. #kinds of
        [] -> []
        ks -> ["kind=" <> T.intercalate "+" (map kindNoun ks)]
   in if null parts
        then ""
        else " [filtered: " <> T.intercalate ", " parts <> "]"
  where
    kindNoun KindModule = "module"
    kindNoun KindRecipe = "recipe"
    kindNoun KindBlueprint = "blueprint"
    kindNoun KindPrompt = "prompt"

-- | Apply repo and tag filters to a list of entries.  Both filters combine
-- with AND: an entry must match all active filters to be included.
applyFilters :: ListFilter -> [Entry] -> [Entry]
applyFilters opts = filter match
  where
    match entry = repoMatch entry && tagMatch entry && kindMatch entry
    repoMatch entry = case opts ^. #repo of
      Nothing -> True
      Just r -> entry ^. #repoName == Just r
    tagMatch entry = case opts ^. #tag of
      Nothing -> True
      Just t -> t `elem` (entry ^. #tags)
    kindMatch entry = case opts ^. #kinds of
      [] -> True
      ks -> (entry ^. #kind) `elem` ks

data Entry = Entry
  { name :: !Text,
    desc :: !Text,
    source :: !Text,
    isError :: !Bool,
    repoName :: !(Maybe Text),
    tags :: ![Text],
    kind :: !RunnableKind
  }
  deriving stock (Eq, Generic, Show)

toEntry :: DiscoveredModule -> Entry
toEntry = toEntryWithOrigin Map.empty

toEntryWithOrigin :: Map FilePath (Maybe OriginInfo) -> DiscoveredModule -> Entry
toEntryWithOrigin origins dm =
  let (originName, originVer, tags) = case Map.lookup (dm ^. #dir) origins of
        Just (Just info) -> (info ^. #repoName, info ^. #version, info ^. #tags)
        _ -> (Nothing, Nothing, [])
      srcLabel = sourceLabelWithOrigin (dm ^. #source) originName originVer
   in case dm ^. #result of
        Right m ->
          Entry
            { name = m ^. #name . #unModuleName,
              desc = maybe "(no description)" id (m ^. #description),
              source = srcLabel,
              isError = False,
              repoName = originName,
              tags = tags,
              kind = KindModule
            }
        Left err ->
          Entry
            { name = dirName (dm ^. #dir),
              desc = "[error: " <> briefError err <> "]",
              source = srcLabel,
              isError = True,
              repoName = originName,
              tags = tags,
              kind = KindModule
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

-- | How much of an entry's description the bounded list shows: one line
-- indented by four spaces, so the description line never exceeds 76 columns
-- and fits an 80-column terminal. @seihou list@ is a scannable summary like
-- @seihou status@, and follows the same rule (see
-- docs/adr/0013-status-is-a-bounded-summary-the-manifest-is-the-record.md).
descriptionWidth :: Int
descriptionWidth = 72

-- | The widest the name column grows. A longer name is not truncated; it
-- pushes its own source label further right instead of every row's.
nameColumnCap :: Int
nameColumnCap = 32

-- | The order sections appear in, with their headings.
kindSections :: [(RunnableKind, Text)]
kindSections =
  [ (KindModule, "Modules"),
    (KindRecipe, "Recipes"),
    (KindBlueprint, "Blueprints"),
    (KindPrompt, "Prompts")
  ]

-- | Render entries as one section per kind, each a heading with a count, a
-- blank line, the entries sorted by name, and a closing blank line. A kind
-- with no entries has no section. In 'FullDescriptions' mode a blank line
-- also separates consecutive entries, since each may span several lines.
formatSections :: Bool -> DescriptionMode -> [Entry] -> [Text]
formatSections color mode entries = concatMap section kindSections
  where
    nameWidth = min nameColumnCap (maximum (0 : map (T.length . (^. #name)) entries))
    section (k, title) = case sortOn (^. #name) (filter ((== k) . (^. #kind)) entries) of
      [] -> []
      es ->
        [styleIf bold (title <> " (" <> T.pack (show (length es)) <> ")"), ""]
          <> entryLines es
          <> [""]
    entryLines es = case mode of
      BoundedDescriptions -> concatMap (formatEntry color mode nameWidth) es
      FullDescriptions -> intercalate [""] (map (formatEntry color mode nameWidth) es)
    styleIf f t = if color then f t else t

-- | Render one entry: the name padded to the name column and its source
-- label, then the description indented under it. 'BoundedDescriptions' makes
-- that one collapsed, bounded line; 'FullDescriptions' word-wraps the whole
-- description at 'descriptionWidth', so the indentation marks where it ends.
formatEntry :: Bool -> DescriptionMode -> Int -> Entry -> [Text]
formatEntry color mode nameWidth entry =
  ("  " <> paddedName <> "  " <> styleIf dim (entry ^. #source))
    : map indent descLines
  where
    descLines = case mode of
      BoundedDescriptions -> [truncateForSummary descriptionWidth desc]
      FullDescriptions -> wrapParagraphs descriptionWidth desc
    -- A paragraph separator stays empty rather than becoming trailing spaces.
    indent l = if T.null l then l else "    " <> styleDesc l
    name = entry ^. #name
    paddedName = name <> T.replicate (nameWidth - T.length name) " "
    rawDesc = entry ^. #desc
    desc = if T.null (T.strip rawDesc) then "(no description)" else rawDesc
    styleDesc = if entry ^. #isError then styleIf red else id
    styleIf f t = if color then f t else t
