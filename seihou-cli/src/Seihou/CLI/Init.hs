module Seihou.CLI.Init
  ( handleInit,
    formatInitOutput,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Shared (shortenHome)
import Seihou.Prelude
import System.Directory
  ( XdgDirectory (..),
    createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    getXdgDirectory,
  )

handleInit :: IO ()
handleInit = do
  base <- getXdgDirectory XdgConfig "seihou"
  createDirectoryIfMissing True base

  -- config.dhall
  let configPath = base </> "config.dhall"
  configExists <- doesFileExist configPath
  if configExists
    then pure ()
    else writeFile configPath defaultConfig
  let configCreated = not configExists

  -- modules/
  modulesExists <- doesDirectoryExist (base </> "modules")
  createDirectoryIfMissing True (base </> "modules")
  let modulesCreated = not modulesExists

  -- installed/
  installedExists <- doesDirectoryExist (base </> "installed")
  createDirectoryIfMissing True (base </> "installed")
  let installedCreated = not installedExists

  -- namespaces/ (internal, not reported)
  createDirectoryIfMissing True (base </> "namespaces")

  -- Output
  basePath <- shortenHome base
  let items =
        [ ("config.dhall", "global defaults", configCreated),
          ("modules/", "user modules", modulesCreated),
          ("installed/", "git-installed modules", installedCreated)
        ]
  TIO.putStr (formatInitOutput basePath items)

-- | Format the init command output. Takes the abbreviated base path and a list
-- of @(item, description, wasCreated)@ triples.
formatInitOutput :: Text -> [(Text, Text, Bool)] -> Text
formatInitOutput basePath items =
  T.unlines $
    ("Initialized Seihou configuration at " <> basePath <> "/")
      : map formatItem items
  where
    formatItem (item, desc, created) =
      let label = if created then "Created:" else "Exists: "
       in "  " <> label <> " " <> item <> " (" <> desc <> ")"

defaultConfig :: String
defaultConfig =
  unlines
    [ "-- Seihou global configuration",
      "-- Add variable defaults that apply to all modules.",
      "-- Example: { `project.name` = \"my-app\", `license` = \"MIT\" }",
      "{=}"
    ]
