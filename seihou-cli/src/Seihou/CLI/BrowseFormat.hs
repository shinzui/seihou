module Seihou.CLI.BrowseFormat
  ( formatBrowseRegistry,
    formatBrowseSingleModule,
    formatBrowseSingleBlueprint,
    kindLabel,
  )
where

import Data.Text qualified as T
import Seihou.Core.Registry (EntryKind (..), Registry (..), RegistryEntry (..))
import Seihou.Core.Types (ModuleName (..))
import Seihou.Prelude

-- | Display-string label for an 'EntryKind'. Each label is padded to
-- eleven characters so registry rows line up regardless of which kind
-- appears on a given row.
kindLabel :: EntryKind -> Text
kindLabel ModuleEntry = "[module]   "
kindLabel RecipeEntry = "[recipe]   "
kindLabel BlueprintEntry = "[blueprint]"

-- | Format browse output for a multi-module registry. Each row begins
-- with a per-kind label so the user can see at a glance whether they are
-- selecting a module, recipe, or blueprint.
formatBrowseRegistry :: Text -> Registry -> [(EntryKind, RegistryEntry)] -> Maybe Text -> Text
formatBrowseRegistry source registry filtered tagFilter =
  let header =
        registry.repoName
          <> "\n"
          <> maybe "" (<> "\n") registry.repoDescription
          <> "\n"
   in if null filtered
        then
          header
            <> ( case tagFilter of
                   Just tag -> "No entries matching tag '" <> tag <> "'.\n"
                   Nothing -> "No entries in registry.\n"
               )
        else
          let nameOf e = let (ModuleName n) = e.name in n
              maxNameLen = maximum (map (T.length . nameOf . snd) filtered)
              entryLines = T.unlines (map (formatEntry maxNameLen) filtered)
              n = length filtered
              noun = if n == 1 then "entry" else "entries"
              footer =
                T.pack (show n)
                  <> " "
                  <> noun
                  <> " available. Install with:\n"
                  <> "  seihou install "
                  <> source
                  <> " --module <name>\n"
                  <> "  seihou install "
                  <> source
                  <> " --all\n"
           in header <> "Available entries:\n\n" <> entryLines <> "\n" <> footer

-- | Format browse output for a single-module repo.
formatBrowseSingleModule :: Text -> Text -> Maybe Text -> Text
formatBrowseSingleModule source name desc =
  name
    <> "\n"
    <> maybe "" (\d -> "  " <> d <> "\n") desc
    <> "\n"
    <> "Single-module repository. Install with:\n"
    <> "  seihou install "
    <> source
    <> "\n"

-- | Format browse output for a single-blueprint repo.
formatBrowseSingleBlueprint :: Text -> Text -> Maybe Text -> Text
formatBrowseSingleBlueprint source name desc =
  name
    <> "\n"
    <> maybe "" (\d -> "  " <> d <> "\n") desc
    <> "\n"
    <> "Single-blueprint repository. Install with:\n"
    <> "  seihou install "
    <> source
    <> "\n"

formatEntry :: Int -> (EntryKind, RegistryEntry) -> Text
formatEntry maxNameLen (kind, entry) =
  let (ModuleName name) = entry.name
      padding = T.replicate (maxNameLen - T.length name + 3) " "
      desc = maybe "" id entry.description
      tagsText =
        if null entry.tags
          then ""
          else "  [" <> T.intercalate ", " entry.tags <> "]"
   in "  " <> kindLabel kind <> "  " <> name <> padding <> desc <> tagsText
