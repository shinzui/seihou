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

import Data.List (isPrefixOf, isSuffixOf)
import Data.Text (Text)
import Data.Text qualified as T
import System.Directory
  ( doesDirectoryExist,
    listDirectory,
  )
import System.FilePath (dropExtension, (</>))

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
skillTargetDir ClaudeLayout baseDir n =
  baseDir </> ".claude" </> "skills" </> T.unpack n
skillTargetDir CodexLayout baseDir n =
  baseDir </> ".agents" </> "skills" </> T.unpack n

agentTargetFile :: KitProviderLayout -> FilePath -> Text -> FilePath
agentTargetFile ClaudeLayout baseDir n =
  baseDir </> ".claude" </> "agents" </> T.unpack n <> ".md"
agentTargetFile CodexLayout baseDir n =
  baseDir </> ".codex" </> "agents" </> T.unpack n <> ".toml"

codexAgentToml :: Text -> Text -> Text -> Text
codexAgentToml n desc instructions =
  T.unlines
    [ "name = " <> tomlString n,
      "description = " <> tomlString desc,
      "developer_instructions = " <> tomlMultilineString instructions
    ]

tomlString :: Text -> Text
tomlString t =
  "\"" <> T.concatMap escape t <> "\""
  where
    escape '"' = "\\\""
    escape '\\' = "\\\\"
    escape '\n' = "\\n"
    escape '\r' = "\\r"
    escape '\t' = "\\t"
    escape c = T.singleton c

tomlMultilineString :: Text -> Text
tomlMultilineString t =
  "\"\"\"\n" <> T.replace "\"\"\"" "\\\"\\\"\\\"" t <> "\n\"\"\""

scanInstalledForProvider :: KitProviderLayout -> FilePath -> IO [InstalledKitItem]
scanInstalledForProvider layout baseDir = do
  skillItems <- scanSkills layout (skillsDir layout baseDir)
  agentItems <- scanAgents layout (agentsDir layout baseDir)
  pure (skillItems ++ agentItems)

skillsDir :: KitProviderLayout -> FilePath -> FilePath
skillsDir ClaudeLayout baseDir = baseDir </> ".claude" </> "skills"
skillsDir CodexLayout baseDir = baseDir </> ".agents" </> "skills"

agentsDir :: KitProviderLayout -> FilePath -> FilePath
agentsDir ClaudeLayout baseDir = baseDir </> ".claude" </> "agents"
agentsDir CodexLayout baseDir = baseDir </> ".codex" </> "agents"

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
agentExtension ClaudeLayout = ".md"
agentExtension CodexLayout = ".toml"

visible :: FilePath -> Bool
visible = not . ("." `isPrefixOf`)
