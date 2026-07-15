module Seihou.CLI.AgentLaunch
  ( AgentContext (..),
    BaselineStatus (..),
    gatherAgentContext,
    defaultAllowedTools,
    setupAllowedTools,
    bootstrapAllowedTools,
    substitute,
    formatSeihouProjectState,
    formatManifestState,
    formatModuleDhallState,
    formatLocalModules,
    formatAvailableModules,
    formatBlueprintIdentity,
    formatBaselineStatus,
    formatReferenceFiles,
    formatReferenceFilesDir,
  )
where

import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Seihou.Core.Module (DiscoveredModule (..), ModuleSource (..), defaultSearchPaths, discoverAllModules)
import Seihou.Core.Types
import Seihou.Prelude
import System.Directory (doesDirectoryExist, doesFileExist, getCurrentDirectory)

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

-- | Outcome of the optional baseline-application phase in
-- @seihou agent run@. Captured here in the library so the runner
-- (in @src-exe@) and the formatter share one shape.
data BaselineStatus
  = -- | The user passed @--no-baseline@; the runner skipped baseline application entirely.
    BaselineSkipped
  | -- | The blueprint declared no @baseModules@; nothing to apply.
    BaselineEmpty
  | -- | Baseline modules were applied. Each entry is the module's name and (optional) version.
    BaselineApplied [(ModuleName, Maybe Text)]
  deriving stock (Eq, Show)

-- | Render a blueprint's identity (name, version, description) as the
-- block embedded under "## Blueprint Identity" in the agent's system prompt.
formatBlueprintIdentity :: Blueprint -> Text
formatBlueprintIdentity bp =
  T.intercalate
    "\n"
    [ "Name: " <> bp.name.unModuleName,
      "Version: " <> fromMaybe "(unspecified)" bp.version,
      "Description: " <> fromMaybe "(no description)" bp.description
    ]

-- | Render the "## Baseline" body for the agent prompt.
formatBaselineStatus :: BaselineStatus -> Text
formatBaselineStatus BaselineSkipped =
  "(no baseline applied — `--no-baseline` was passed)"
formatBaselineStatus BaselineEmpty =
  "(this blueprint declares no base modules)"
formatBaselineStatus (BaselineApplied entries) =
  T.intercalate "\n" (map render entries)
  where
    render (n, Just v) = "  - " <> n.unModuleName <> " (v" <> v <> ")"
    render (n, Nothing) = "  - " <> n.unModuleName <> " (unversioned)"

-- | Render a blueprint's @files@ list as the body of the
-- "## Reference Files" block. When the directory exists, the interactive
-- runner mounts it via @--add-dir@ and 'formatReferenceFilesDir' prints its
-- path; this list helps the agent pick the right reference for the request.
formatReferenceFiles :: [BlueprintFile] -> Text
formatReferenceFiles [] = "(no reference files)"
formatReferenceFiles bfs = T.intercalate "\n" (map render bfs)
  where
    render bf = case bf.description of
      Just d -> "  - " <> T.pack bf.src <> " — " <> d
      Nothing -> "  - " <> T.pack bf.src

-- | Render guidance for the blueprint's reference-files directory. A
-- present path means the directory is mounted and readable by the interactive
-- agent; 'Nothing' means the provider cannot access it in this session.
formatReferenceFilesDir :: Maybe FilePath -> Text
formatReferenceFilesDir (Just dir) =
  "These files are readable at: "
    <> T.pack dir
    <> " — open them directly with your file tools before asking the user."
formatReferenceFilesDir Nothing =
  "These files are not mounted in this session; ask the user to paste any "
    <> "reference you need and never claim to have read one."
