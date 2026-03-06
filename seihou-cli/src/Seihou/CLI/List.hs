module Seihou.CLI.List
  ( handleList,
    formatListOutput,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Shared (shortenHome)
import Seihou.CLI.Style (dim, red, useColor)
import Seihou.Core.Module (DiscoveredModule (..), ModuleSource (..), defaultSearchPaths, discoverAllModules)
import Seihou.Core.Types
import Seihou.Prelude

handleList :: IO ()
handleList = do
  searchPaths <- defaultSearchPaths
  modules <- discoverAllModules searchPaths
  colorEnabled <- useColor
  shortenedPaths <- mapM shortenHome searchPaths
  TIO.putStr (formatListOutput colorEnabled modules shortenedPaths)

formatListOutput :: Bool -> [DiscoveredModule] -> [Text] -> Text
formatListOutput color modules searchPaths
  | null modules =
      "No modules found.\n\nSearched:\n"
        <> T.unlines (map ("  " <>) searchPaths)
  | otherwise =
      let entries = map toEntry modules
          maxNameLen = maximum (map (T.length . (.entryName)) entries)
          maxDescLen = maximum (map (T.length . (.entryDesc)) entries)
          header = "Available modules:\n"
          fileLines = map (formatEntry color maxNameLen maxDescLen) entries
          n = length modules
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
toEntry dm = case dm.discoveredResult of
  Right m ->
    Entry
      { entryName = m.name.unModuleName,
        entryDesc = maybe "(no description)" id m.description,
        entrySource = sourceLabel dm.discoveredSource,
        entryIsError = False
      }
  Left err ->
    Entry
      { entryName = dirName dm.discoveredDir,
        entryDesc = "[error: " <> briefError err <> "]",
        entrySource = sourceLabel dm.discoveredSource,
        entryIsError = True
      }

sourceLabel :: ModuleSource -> Text
sourceLabel SourceProject = "project"
sourceLabel SourceUser = "user"
sourceLabel SourceInstalled = "installed"

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
