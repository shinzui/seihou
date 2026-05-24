module Seihou.CLI.KitPaths
  ( KitProviderLayout (..),
    InstalledKitItem (..),
    allKitProviderLayouts,
    providerLabel,
    skillTargetDir,
    agentTargetFile,
    codexAgentToml,
    scanInstalledForProvider,
  )
where

import Baikai.AgentAssets qualified as AgentAssets
import Baikai.Interactive
  ( InteractiveProvider (InteractiveClaude, InteractiveCodex),
    InteractiveScope (InteractiveProjectScope),
  )
import Data.List (isPrefixOf, isSuffixOf)
import Data.Text (Text)
import Data.Text qualified as T
import System.Directory
  ( doesDirectoryExist,
    listDirectory,
  )
import System.FilePath (dropExtension, takeDirectory, (</>))

data KitProviderLayout
  = ClaudeLayout
  | CodexLayout
  deriving stock (Eq, Ord, Show)

data InstalledKitItem = InstalledKitItem
  { installedName :: !Text,
    installedType :: !Text,
    installedProvider :: !Text
  }
  deriving stock (Eq, Show)

allKitProviderLayouts :: [KitProviderLayout]
allKitProviderLayouts = [ClaudeLayout, CodexLayout]

providerLabel :: KitProviderLayout -> Text
providerLabel ClaudeLayout = "claude"
providerLabel CodexLayout = "codex"

skillTargetDir :: KitProviderLayout -> FilePath -> Text -> FilePath
skillTargetDir layout baseDir n =
  baseDir
    </> AgentAssets.skillTargetPath
      (assetProvider layout)
      InteractiveProjectScope
      (T.unpack n)

agentTargetFile :: KitProviderLayout -> FilePath -> Text -> FilePath
agentTargetFile layout baseDir n =
  baseDir
    </> AgentAssets.agentTargetPath
      (assetProvider layout)
      InteractiveProjectScope
      (T.unpack n)

codexAgentToml :: Text -> Text -> Text -> Text
codexAgentToml n desc instructions =
  AgentAssets.codexCustomAgentToml
    AgentAssets.CodexCustomAgent
      { name = n,
        description = desc,
        developerInstructions = instructions
      }

scanInstalledForProvider :: KitProviderLayout -> FilePath -> IO [InstalledKitItem]
scanInstalledForProvider layout baseDir = do
  skillItems <- scanSkills layout (skillsDir layout baseDir)
  agentItems <- scanAgents layout (agentsDir layout baseDir)
  pure (skillItems ++ agentItems)

skillsDir :: KitProviderLayout -> FilePath -> FilePath
skillsDir layout baseDir =
  takeDirectory (skillTargetDir layout baseDir "__scan__")

agentsDir :: KitProviderLayout -> FilePath -> FilePath
agentsDir layout baseDir =
  takeDirectory (agentTargetFile layout baseDir "__scan__")

scanSkills :: KitProviderLayout -> FilePath -> IO [InstalledKitItem]
scanSkills layout dir = do
  exists <- doesDirectoryExist dir
  if exists
    then do
      entries <- listDirectory dir
      pure $
        map
          (\e -> InstalledKitItem (T.pack e) "skill" (providerLabel layout))
          (filter visible entries)
    else pure []

scanAgents :: KitProviderLayout -> FilePath -> IO [InstalledKitItem]
scanAgents layout dir = do
  exists <- doesDirectoryExist dir
  if exists
    then do
      entries <- listDirectory dir
      let ext = agentExtension layout
          agentFiles = filter (\f -> ext `isSuffixOf` f && visible f) entries
      pure $
        map
          (\f -> InstalledKitItem (T.pack (dropExtension f)) "agent" (providerLabel layout))
          agentFiles
    else pure []

agentExtension :: KitProviderLayout -> String
agentExtension layout =
  case AgentAssets.agentAssetFormat (assetProvider layout) AgentAssets.CustomAgentAsset of
    AgentAssets.MarkdownFile -> ".md"
    AgentAssets.TomlFile -> ".toml"
    AgentAssets.DirectoryAsset -> ""

visible :: FilePath -> Bool
visible = not . ("." `isPrefixOf`)

assetProvider :: KitProviderLayout -> InteractiveProvider
assetProvider ClaudeLayout = InteractiveClaude
assetProvider CodexLayout = InteractiveCodex
