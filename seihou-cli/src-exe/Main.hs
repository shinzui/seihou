module Main (main) where

import Control.Applicative ((<|>))
import Data.Text (Text)
import Data.Text.IO qualified as TIO
import Options.Applicative (customExecParser, prefs, showHelpOnEmpty)
import Seihou.CLI.AgentCompletion qualified as AgentCompletion
import Seihou.CLI.AgentConfig (loadAgentModelConfig)
import Seihou.CLI.AgentRun (handleAgentRun)
import Seihou.CLI.Assist (handleAssist)
import Seihou.CLI.Bootstrap (handleBootstrap)
import Seihou.CLI.Browse (handleBrowse)
import Seihou.CLI.Commands
import Seihou.CLI.Completions (handleCompletionsCommand)
import Seihou.CLI.Config (handleConfig)
import Seihou.CLI.Context (handleContext)
import Seihou.CLI.Diff (handleDiff)
import Seihou.CLI.Help (handleHelpCommand)
import Seihou.CLI.Init (handleInit)
import Seihou.CLI.Install (handleInstall)
import Seihou.CLI.Kit (runKit)
import Seihou.CLI.List (ListFilter (..), handleList)
import Seihou.CLI.Migrate (handleMigrate)
import Seihou.CLI.NewBlueprint (handleNewBlueprint)
import Seihou.CLI.NewModule (handleNewModule)
import Seihou.CLI.NewPrompt (handleNewPrompt)
import Seihou.CLI.NewRecipe (handleNewRecipe)
import Seihou.CLI.Outdated (handleOutdated)
import Seihou.CLI.PromptRun (handlePromptRun)
import Seihou.CLI.Registry (handleRegistry)
import Seihou.CLI.Remove (handleRemove)
import Seihou.CLI.Run (handleRun)
import Seihou.CLI.SchemaUpgrade (handleSchemaUpgrade)
import Seihou.CLI.Setup (handleSetup)
import Seihou.CLI.Status (handleStatus)
import Seihou.CLI.Upgrade (handleUpgrade)
import Seihou.CLI.Validate (handleValidateModule)
import Seihou.CLI.ValidateBlueprint (handleValidateBlueprint)
import Seihou.CLI.ValidatePrompt (handleValidatePrompt)
import Seihou.CLI.Vars (handleVars)
import Seihou.Core.Module (RunnableKind (..))
import System.Exit (exitFailure)

main :: IO ()
main = do
  cmd <- customExecParser (prefs showHelpOnEmpty) opts
  case cmd of
    Init ->
      handleInit
    Run runOpts ->
      handleRun runOpts
    Remove removeOpts ->
      handleRemove removeOpts
    Vars varsOpts ->
      handleVars varsOpts
    Install installOpts ->
      handleInstall installOpts
    Status statusOpts ->
      handleStatus statusOpts
    Diff ->
      handleDiff
    List listOpts ->
      let kinds =
            [KindModule | listOpts.listModulesOnly]
              <> [KindRecipe | listOpts.listRecipesOnly]
              <> [KindBlueprint | listOpts.listBlueprintsOnly]
              <> [KindPrompt | listOpts.listPromptsOnly]
       in handleList (ListFilter listOpts.listRepo listOpts.listTag kinds)
    NewModule newModOpts ->
      handleNewModule newModOpts
    NewRecipe newRecOpts ->
      handleNewRecipe newRecOpts
    NewBlueprint newBpOpts ->
      handleNewBlueprint newBpOpts
    NewPrompt newPromptOpts ->
      handleNewPrompt newPromptOpts
    ValidateModule validateOpts ->
      handleValidateModule validateOpts
    ValidateBlueprint validateBpOpts ->
      handleValidateBlueprint validateBpOpts
    ValidatePrompt validatePromptOpts ->
      handleValidatePrompt validatePromptOpts
    Config configOpts ->
      handleConfig configOpts
    Context contextAction ->
      handleContext contextAction
    Browse browseOpts ->
      handleBrowse browseOpts
    Outdated outdatedOpts ->
      handleOutdated outdatedOpts
    Upgrade upgradeOpts ->
      handleUpgrade upgradeOpts
    Migrate migrateOpts ->
      handleMigrate migrateOpts
    SchemaUpgrade schemaUpgradeOpts ->
      handleSchemaUpgrade schemaUpgradeOpts
    Registry registryCmd ->
      handleRegistry registryCmd
    Kit kitCmd ->
      runKit kitCmd
    Agent agentOpts -> do
      case agentOpts.agentCommand of
        AgentAssist assistOpts -> do
          modelConfig <- resolveAgentModelConfig agentOpts.agentProvider agentOpts.agentModel assistOpts.assistProvider assistOpts.assistModel
          handleAssist agentOpts.agentDebug modelConfig assistOpts
        AgentBootstrap bootstrapOpts -> do
          modelConfig <- resolveAgentModelConfig agentOpts.agentProvider agentOpts.agentModel bootstrapOpts.bootstrapProvider bootstrapOpts.bootstrapModel
          handleBootstrap agentOpts.agentDebug modelConfig bootstrapOpts
        AgentSetup setupOpts -> do
          modelConfig <- resolveAgentModelConfig agentOpts.agentProvider agentOpts.agentModel setupOpts.setupProvider setupOpts.setupModel
          handleSetup agentOpts.agentDebug modelConfig setupOpts
        AgentRun blueprintRunOpts -> do
          modelConfig <- resolveAgentModelConfig agentOpts.agentProvider agentOpts.agentModel blueprintRunOpts.runBlueprintProvider blueprintRunOpts.runBlueprintModel
          handleAgentRun agentOpts.agentDebug modelConfig blueprintRunOpts
    Prompt promptCmd -> do
      case promptCmd of
        PromptRun promptRunOpts -> do
          modelConfig <- resolveAgentModelConfig Nothing Nothing promptRunOpts.runPromptProvider promptRunOpts.runPromptModel
          handlePromptRun modelConfig promptRunOpts
    HelpCmd helpCmd ->
      handleHelpCommand helpCmd
    Completions completionsCmd ->
      handleCompletionsCommand completionsCmd

resolveAgentModelConfig :: Maybe Text -> Maybe Text -> Maybe Text -> Maybe Text -> IO AgentCompletion.AgentModelConfig
resolveAgentModelConfig parentProvider parentModel commandProvider commandModel = do
  configResult <- loadAgentModelConfig (commandProvider <|> parentProvider) (commandModel <|> parentModel)
  case configResult of
    Left err -> do
      TIO.putStrLn $ "Error: " <> err
      exitFailure
    Right config -> pure config
