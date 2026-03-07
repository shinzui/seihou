{-# LANGUAGE TemplateHaskell #-}

module Seihou.CLI.Assist
  ( handleAssist,
  )
where

import Data.ByteString qualified as BS
import Data.FileEmbed (embedFile)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (AssistOpts (..))
import Seihou.Core.Module (DiscoveredModule (..), ModuleSource (..), defaultSearchPaths, discoverAllModules)
import Seihou.Core.Types
import Seihou.Prelude
import System.Directory (doesDirectoryExist, doesFileExist, findExecutable, getCurrentDirectory)
import System.Exit (ExitCode (..), exitFailure, exitWith)
import System.Process (rawSystem)

-- | The prompt template, embedded at compile time from data/assist-prompt.md.
promptTemplate :: Text
promptTemplate = TE.decodeUtf8 $(embedFile "data/assist-prompt.md")

handleAssist :: AssistOpts -> IO ()
handleAssist assistOpts = do
  claudePath <- findExecutable "claude"
  case claudePath of
    Nothing -> do
      TIO.putStrLn "Error: 'claude' CLI (Claude Code) not found on PATH."
      TIO.putStrLn "Install it from: https://docs.anthropic.com/en/docs/claude-code"
      exitFailure
    Just _ -> do
      context <- gatherContext
      let systemPrompt = renderPrompt context
          args = buildArgs systemPrompt assistOpts
      exitCode <- rawSystem "claude" args
      exitWith exitCode

-- | Dynamic context gathered from the current directory.
data AssistContext = AssistContext
  { cwd :: Text,
    seihouInitialized :: Bool,
    hasManifest :: Bool,
    localModuleDhall :: Bool,
    localModules :: [Text],
    -- | (name, description, source)
    availableModules :: [(Text, Text, Text)]
  }

gatherContext :: IO AssistContext
gatherContext = do
  cwd <- T.pack <$> getCurrentDirectory
  seihouInitialized <- doesDirectoryExist (T.unpack cwd </> ".seihou")
  hasManifest <- doesFileExist (T.unpack cwd </> ".seihou" </> "manifest.json")
  localModuleDhall <- doesFileExist (T.unpack cwd </> "module.dhall")

  localMods <- findLocalModuleDirs (T.unpack cwd)

  searchPaths <- defaultSearchPaths
  discovered <- discoverAllModules searchPaths
  let available = concatMap toModuleInfo discovered

  pure
    AssistContext
      { cwd = cwd,
        seihouInitialized = seihouInitialized,
        hasManifest = hasManifest,
        localModuleDhall = localModuleDhall,
        localModules = localMods,
        availableModules = available
      }

findLocalModuleDirs :: FilePath -> IO [Text]
findLocalModuleDirs dir = do
  let seihouModsDir = dir </> ".seihou" </> "modules"
  hasSeihouMods <- doesDirectoryExist seihouModsDir
  if hasSeihouMods
    then pure ["(project modules directory exists at .seihou/modules/)"]
    else pure []

toModuleInfo :: DiscoveredModule -> [(Text, Text, Text)]
toModuleInfo dm = case dm.discoveredResult of
  Right m ->
    [ ( m.name.unModuleName,
        maybe "(no description)" id m.description,
        sourceLabel dm.discoveredSource
      )
    ]
  Left _ -> []

sourceLabel :: ModuleSource -> Text
sourceLabel SourceProject = "project"
sourceLabel SourceUser = "user"
sourceLabel SourceInstalled = "installed"

-- | Render the prompt template by substituting {{placeholders}} with dynamic values.
renderPrompt :: AssistContext -> Text
renderPrompt ctx =
  substitute
    [ ("cwd", ctx.cwd),
      ("seihou_project_state", seihouProjectState ctx),
      ("manifest_state", manifestState ctx),
      ("module_dhall_state", moduleDhallState ctx),
      ("local_modules", localModulesText ctx),
      ("available_modules", availableModulesText ctx)
    ]
    promptTemplate

seihouProjectState :: AssistContext -> Text
seihouProjectState ctx
  | ctx.seihouInitialized = "Seihou project: .seihou/ directory exists (this is a seihou-managed project)"
  | otherwise = "Seihou project: No .seihou/ directory (not yet a seihou project in this directory)"

manifestState :: AssistContext -> Text
manifestState ctx
  | ctx.hasManifest = "Manifest: .seihou/manifest.json exists (modules have been applied here)"
  | otherwise = "Manifest: No manifest (no modules applied yet)"

moduleDhallState :: AssistContext -> Text
moduleDhallState ctx
  | ctx.localModuleDhall = "Module in cwd: module.dhall found in current directory (user is authoring a module here)"
  | otherwise = ""

localModulesText :: AssistContext -> Text
localModulesText ctx
  | null ctx.localModules = ""
  | otherwise = T.intercalate "\n" $ "Local modules:" : map ("  - " <>) ctx.localModules

availableModulesText :: AssistContext -> Text
availableModulesText ctx
  | null ctx.availableModules = "Available modules: None discovered"
  | otherwise =
      T.intercalate "\n" $
        "Available modules across search paths:"
          : map formatMod ctx.availableModules
  where
    formatMod (name, desc, src) = "  - " <> name <> " — " <> desc <> " (" <> src <> ")"

-- | Simple {{key}} substitution. Replaces each {{key}} with the corresponding value.
substitute :: [(Text, Text)] -> Text -> Text
substitute vars template = foldl' replaceOne template vars
  where
    replaceOne t (key, val) = T.replace ("{{" <> key <> "}}") val t

buildArgs :: Text -> AssistOpts -> [String]
buildArgs systemPrompt assistOpts =
  ["--system-prompt", T.unpack systemPrompt]
    <> ["--allowedTools", allowedTools]
    <> promptArgs
  where
    allowedTools = "Bash(seihou:*,git:*,ls:*,mkdir:*,cat:*,pwd:*) Read Write Edit Glob Grep"
    promptArgs = case assistOpts.assistPrompt of
      Just p -> [T.unpack p]
      Nothing -> []
