{-# LANGUAGE TemplateHaskell #-}

module Seihou.CLI.Help
  ( HelpCommand (..),
    helpCommandParser,
    handleHelpCommand,
  )
where

import Data.FileEmbed (embedStringFile)
import Data.Foldable (forM_)
import Data.List (find)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Options.Applicative
import Seihou.Prelude

data HelpTopic = HelpTopic
  { topicName :: !Text,
    topicDescription :: !Text,
    topicContent :: !Text
  }

data HelpCommand
  = ListTopics
  | ShowTopic !Text
  deriving stock (Eq, Show)

helpTopics :: [HelpTopic]
helpTopics =
  [ HelpTopic "agent" "Configurable AI assistance commands" agentContent,
    HelpTopic "blueprints" "Agent-driven project blueprints" blueprintsContent,
    HelpTopic "modules" "How Seihou modules work" modulesContent,
    HelpTopic "variables" "Variable declaration, resolution, and overrides" variablesContent,
    HelpTopic "contexts" "Using contexts for environment-specific config" contextsContent,
    HelpTopic "config" "Config scopes, reading, and writing values" configContent,
    HelpTopic "git-repository" "Sharing and installing items from git" gitRepositoryContent,
    HelpTopic "kit" "Manage Claude Code and Codex skills and subagents" kitContent,
    HelpTopic "migrations" "Migrating a project between module versions" migrationsContent,
    HelpTopic "prompts" "Reusable agent-session prompt artifacts" promptsContent,
    HelpTopic "templating" "Placeholder substitution, {{#if}} blocks, and patterns" templatingContent,
    HelpTopic "update" "Safely update recorded project applications" updateContent
  ]

agentContent :: Text
agentContent = $(embedStringFile "help/agent.md")

blueprintsContent :: Text
blueprintsContent = $(embedStringFile "help/blueprints.md")

modulesContent :: Text
modulesContent = $(embedStringFile "help/modules.md")

variablesContent :: Text
variablesContent = $(embedStringFile "help/variables.md")

contextsContent :: Text
contextsContent = $(embedStringFile "help/contexts.md")

configContent :: Text
configContent = $(embedStringFile "help/config.md")

gitRepositoryContent :: Text
gitRepositoryContent = $(embedStringFile "help/git-repository.md")

kitContent :: Text
kitContent = $(embedStringFile "help/kit.md")

migrationsContent :: Text
migrationsContent = $(embedStringFile "help/migrations.md")

promptsContent :: Text
promptsContent = $(embedStringFile "help/prompts.md")

templatingContent :: Text
templatingContent = $(embedStringFile "help/templating.md")

updateContent :: Text
updateContent = $(embedStringFile "help/update.md")

helpCommandParser :: Parser HelpCommand
helpCommandParser =
  showTopicParser <|> pure ListTopics

showTopicParser :: Parser HelpCommand
showTopicParser =
  ShowTopic
    <$> strArgument
      ( metavar "TOPIC"
          <> help ("Help topic: " <> T.unpack topicList)
      )
  where
    topicList = T.intercalate ", " (map (.topicName) helpTopics)

handleHelpCommand :: HelpCommand -> IO ()
handleHelpCommand = \case
  ListTopics -> listTopics
  ShowTopic name -> showTopic name

listTopics :: IO ()
listTopics = do
  TIO.putStrLn "HELP TOPICS\n"
  forM_ helpTopics $ \t ->
    TIO.putStrLn $ "  " <> padRight 17 t.topicName <> t.topicDescription
  TIO.putStrLn "\nUse 'seihou help <topic>' for details."

padRight :: Int -> Text -> Text
padRight n t = t <> T.replicate (max 0 (n - T.length t)) " "

showTopic :: Text -> IO ()
showTopic name =
  case find (\t -> t.topicName == T.toLower name) helpTopics of
    Just t -> TIO.putStrLn t.topicContent
    Nothing -> do
      TIO.putStrLn $ "Unknown topic: " <> name
      TIO.putStrLn $ "Available: " <> T.intercalate ", " (map (.topicName) helpTopics)
