module Seihou.CLI.BrowseFormat
  ( formatBrowseRegistry,
    formatBrowseSingleModule,
  )
where

import Data.Text qualified as T
import Seihou.Core.Registry (Registry (..), RegistryEntry (..))
import Seihou.Core.Types (ModuleName (..))
import Seihou.Prelude

-- | Format browse output for a multi-module registry.
formatBrowseRegistry :: Text -> Registry -> [RegistryEntry] -> Maybe Text -> Text
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
                   Just tag -> "No modules matching tag '" <> tag <> "'.\n"
                   Nothing -> "No modules in registry.\n"
               )
        else
          let nameOf e = let (ModuleName n) = e.name in n
              maxNameLen = maximum (map (T.length . nameOf) filtered)
              entryLines = T.unlines (map (formatEntry maxNameLen) filtered)
              n = length filtered
              noun = if n == 1 then "module" else "modules"
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
           in header <> "Available modules:\n\n" <> entryLines <> "\n" <> footer

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

formatEntry :: Int -> RegistryEntry -> Text
formatEntry maxNameLen entry =
  let (ModuleName name) = entry.name
      padding = T.replicate (maxNameLen - T.length name + 3) " "
      desc = maybe "" id entry.description
      tagsText =
        if null entry.tags
          then ""
          else "  [" <> T.intercalate ", " entry.tags <> "]"
   in "  " <> name <> padding <> desc <> tagsText
