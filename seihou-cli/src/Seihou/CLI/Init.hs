module Seihou.CLI.Init
  ( handleInit,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import System.Directory (XdgDirectory (..), createDirectoryIfMissing, doesFileExist, getXdgDirectory)
import System.FilePath ((</>))

handleInit :: IO ()
handleInit = do
  base <- getXdgDirectory XdgConfig "seihou"

  -- Create subdirectories
  mapM_ (createSubdir base) ["modules", "installed", "namespaces"]

  -- Write default config.dhall if it doesn't exist
  let configPath = base </> "config.dhall"
  exists <- doesFileExist configPath
  if exists
    then TIO.putStrLn $ "Already exists: " <> showT configPath
    else do
      writeFile configPath defaultConfig
      TIO.putStrLn $ "Created " <> showT configPath

createSubdir :: FilePath -> FilePath -> IO ()
createSubdir base name = do
  let path = base </> name
  createDirectoryIfMissing True path
  TIO.putStrLn $ "Created " <> showT path

showT :: FilePath -> Text
showT = T.pack

defaultConfig :: String
defaultConfig =
  unlines
    [ "-- Seihou global configuration",
      "-- Add variable defaults that apply to all modules.",
      "-- Example: { `project.name` = \"my-app\", `license` = \"MIT\" }",
      "{=}"
    ]
