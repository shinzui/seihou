module Seihou.CLI.AgentLaunch
  ( AgentContext (..),
    gatherAgentContext,
    agentDirsForSession,
    launchAgent,
    launchAgentWith,
    defaultAllowedTools,
    setupAllowedTools,
    bootstrapAllowedTools,
    substitute,
    formatSeihouProjectState,
    formatManifestState,
    formatModuleDhallState,
    formatLocalModules,
    formatAvailableModules,
  )
where

import Control.Monad (filterM)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.Core.Module (DiscoveredModule (..), ModuleSource (..), defaultSearchPaths, discoverAllModules)
import Seihou.Core.Types
import Seihou.Prelude
import System.Directory (doesDirectoryExist, doesFileExist, findExecutable, getCurrentDirectory, getHomeDirectory)
import System.Exit (ExitCode (..), exitFailure, exitWith)
import System.Process (rawSystem)

-- | Dynamic context gathered from the current directory, shared across agent commands.
data AgentContext = AgentContext
  { cwd :: Text,
    seihouInitialized :: Bool,
    hasManifest :: Bool,
    localModuleDhall :: Bool,
    localModules :: [Text],
    -- | (name, description, source)
    availableModules :: [(Text, Text, Text)]
  }

gatherAgentContext :: IO AgentContext
gatherAgentContext = do
  cwd <- T.pack <$> getCurrentDirectory
  seihouInitialized <- doesDirectoryExist (T.unpack cwd </> ".seihou")
  hasManifest <- doesFileExist (T.unpack cwd </> ".seihou" </> "manifest.json")
  localModuleDhall <- doesFileExist (T.unpack cwd </> "module.dhall")

  localMods <- findLocalModuleDirs (T.unpack cwd)

  searchPaths <- defaultSearchPaths
  discovered <- discoverAllModules searchPaths
  let available = concatMap toModuleInfo discovered

  pure
    AgentContext
      { cwd = cwd,
        seihouInitialized = seihouInitialized,
        hasManifest = hasManifest,
        localModuleDhall = localModuleDhall,
        localModules = localMods,
        availableModules = available
      }

-- | Discover agent directories for kit content (both user and project scope).
-- Returns only directories that exist on disk.
agentDirsForSession :: IO [FilePath]
agentDirsForSession = do
  home <- getHomeDirectory
  cwd <- getCurrentDirectory
  let userAgentDir = home </> ".config" </> "seihou" </> "agents"
      projectAgentDir = cwd </> ".seihou" </> "agents"
  filterM doesDirectoryExist [userAgentDir, projectAgentDir]

-- | Launch claude with a system prompt, or print it in debug mode.
launchAgent :: Bool -> Text -> Maybe Text -> IO ()
launchAgent debug systemPrompt initialPrompt = do
  addDirs <- agentDirsForSession
  launchAgentWith addDirs defaultAllowedTools debug systemPrompt initialPrompt

-- | Launch claude with custom add-dirs and allowed tools.
launchAgentWith :: [FilePath] -> [String] -> Bool -> Text -> Maybe Text -> IO ()
launchAgentWith addDirs tools debug systemPrompt initialPrompt
  | debug = TIO.putStr systemPrompt
  | otherwise = do
      claudePath <- findExecutable "claude"
      case claudePath of
        Nothing -> do
          TIO.putStrLn "Error: 'claude' CLI (Claude Code) not found on PATH."
          TIO.putStrLn "Install it from: https://docs.anthropic.com/en/docs/claude-code"
          exitFailure
        Just _ -> do
          let args =
                ["--system-prompt", T.unpack systemPrompt]
                  <> concatMap (\d -> ["--add-dir", d]) addDirs
                  <> concatMap (\t -> ["--allowedTools", t]) tools
                  <> maybe [] (\p -> [T.unpack p]) initialPrompt
          exitCode <- rawSystem "claude" args
          exitWith exitCode

-- | Default allowed tools for agent commands (assist, bootstrap).
defaultAllowedTools :: [String]
defaultAllowedTools =
  [ "Bash(seihou *)",
    "Bash(git *)",
    "Bash(ls *)",
    "Bash(mkdir *)",
    "Bash(cat *)",
    "Bash(pwd)",
    "Read",
    "Write",
    "Edit",
    "Glob",
    "Grep",
    "EnterWorktree",
    "ExitWorktree"
  ]

-- | Allowed tools for the setup command — grants full git and seihou access
-- since setup needs to init repos, stage files, commit, and run any seihou command.
setupAllowedTools :: [String]
setupAllowedTools =
  [ "Bash(seihou *)",
    "Bash(git *)",
    "Bash(ls *)",
    "Bash(mkdir *)",
    "Bash(cat *)",
    "Bash(pwd)",
    "Read",
    "Write",
    "Edit",
    "Glob",
    "Grep",
    "EnterWorktree",
    "ExitWorktree"
  ]

-- | Allowed tools for the bootstrap command — grants full git access, temp directories,
-- and common shell utilities so the agent can scaffold, test, and commit without prompting.
bootstrapAllowedTools :: [String]
bootstrapAllowedTools =
  [ "Bash(seihou *)",
    "Bash(git *)",
    "Bash(ls *)",
    "Bash(mkdir *)",
    "Bash(cat *)",
    "Bash(pwd)",
    "Bash(mktemp *)",
    "Bash(cp *)",
    "Bash(rm *)",
    "Bash(mv *)",
    "Bash(touch *)",
    "Bash(tree *)",
    "Bash(find *)",
    "Bash(wc *)",
    "Bash(diff *)",
    "Bash(head *)",
    "Bash(tail *)",
    "Bash(echo *)",
    "Bash(chmod *)",
    "Read",
    "Write",
    "Edit",
    "Glob",
    "Grep",
    "EnterWorktree",
    "ExitWorktree"
  ]

-- | Simple {{key}} substitution. Replaces each {{key}} with the corresponding value.
substitute :: [(Text, Text)] -> Text -> Text
substitute vars template = foldl' replaceOne template vars
  where
    replaceOne t (key, val) = T.replace ("{{" <> key <> "}}") val t

-- Shared context formatters

formatSeihouProjectState :: AgentContext -> Text
formatSeihouProjectState ctx
  | ctx.seihouInitialized = "Seihou project: .seihou/ directory exists (this is a seihou-managed project)"
  | otherwise = "Seihou project: No .seihou/ directory (not yet a seihou project in this directory)"

formatManifestState :: AgentContext -> Text
formatManifestState ctx
  | ctx.hasManifest = "Manifest: .seihou/manifest.json exists (modules have been applied here)"
  | otherwise = "Manifest: No manifest (no modules applied yet)"

formatModuleDhallState :: AgentContext -> Text
formatModuleDhallState ctx
  | ctx.localModuleDhall = "Module in cwd: module.dhall found in current directory (user is authoring a module here)"
  | otherwise = ""

formatLocalModules :: AgentContext -> Text
formatLocalModules ctx
  | null ctx.localModules = ""
  | otherwise = T.intercalate "\n" $ "Local modules:" : map ("  - " <>) ctx.localModules

formatAvailableModules :: AgentContext -> Text
formatAvailableModules ctx
  | null ctx.availableModules = "Available modules: None discovered"
  | otherwise =
      T.intercalate "\n" $
        "Available modules across search paths:"
          : map formatMod ctx.availableModules
  where
    formatMod (name, desc, src) = "  - " <> name <> " — " <> desc <> " (" <> src <> ")"

-- Internal helpers

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
