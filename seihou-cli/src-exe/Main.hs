module Main (main) where

import Control.Applicative ((<|>))
import Data.List (isPrefixOf)
import Data.Maybe (isJust)
import Data.String (fromString)
import Data.Text (Text)
import Data.Text.IO qualified as TIO
import Options.Applicative (customExecParser, prefs, showHelpOnEmpty)
import Seihou.CLI.AgentCompletion qualified as AgentCompletion
import Seihou.CLI.AgentConfig (AgentCommandName (..), loadAgentModelConfigFor)
import Seihou.CLI.AgentConfigShow (handleAgentConfigShow)
import Seihou.CLI.AgentMigrate (handleAgentMigrate)
import Seihou.CLI.AgentModels qualified as AgentModels
import Seihou.CLI.AgentRun (handleAgentRun)
import Seihou.CLI.Assist (handleAssist)
import Seihou.CLI.Bootstrap (handleBootstrap)
import Seihou.CLI.Browse (handleBrowse)
import Seihou.CLI.Commands
import Seihou.CLI.Completions (handleCompletionsCommand)
import Seihou.CLI.Config (handleConfig)
import Seihou.CLI.Context (handleContext)
import Seihou.CLI.Diff (handleDiff)
import Seihou.CLI.Extension (ExtensionRunOpts (..), handleExtensionRun)
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
import Seihou.CLI.Update (handleUpdate)
import Seihou.CLI.Upgrade (handleUpgrade)
import Seihou.CLI.Validate (handleValidateModule)
import Seihou.CLI.ValidateBlueprint (handleValidateBlueprint)
import Seihou.CLI.ValidatePrompt (handleValidatePrompt)
import Seihou.CLI.Vars (handleVars)
import Seihou.Core.Module (RunnableKind (..))
import System.Environment (getArgs)
import System.Exit (exitFailure)

main :: IO ()
main = do
  rawArgs <- getArgs
  case extensionRunFromRawArgs rawArgs of
    Just extensionRunOpts ->
      handleExtensionRun extensionRunOpts
    Nothing -> do
      cmd <- customExecParser (prefs showHelpOnEmpty) opts
      dispatch cmd

extensionRunFromRawArgs :: [String] -> Maybe ExtensionRunOpts
extensionRunFromRawArgs ("extension" : "run" : name : rest)
  | not ("-" `isPrefixOf` name) =
      Just
        ExtensionRunOpts
          { extensionName = fromString name,
            extensionArgs =
              case rest of
                "--" : forwarded -> forwarded
                forwarded -> forwarded
          }
extensionRunFromRawArgs _ = Nothing

dispatch :: Command -> IO ()
dispatch cmd =
  case cmd of
    Init ->
      handleInit
    Run runOpts ->
      handleRun runOpts
    Update updateOpts ->
      handleUpdate updateOpts
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
          modelConfig <- resolveAgentModelConfigFor AgentCmdAssist agentOpts.agentProvider agentOpts.agentModel agentOpts.agentEffort assistOpts.assistProvider assistOpts.assistModel assistOpts.assistEffort
          handleAssist agentOpts.agentDebug modelConfig assistOpts
        AgentBootstrap bootstrapOpts -> do
          modelConfig <- resolveAgentModelConfigFor AgentCmdBootstrap agentOpts.agentProvider agentOpts.agentModel agentOpts.agentEffort bootstrapOpts.bootstrapProvider bootstrapOpts.bootstrapModel bootstrapOpts.bootstrapEffort
          handleBootstrap agentOpts.agentDebug modelConfig bootstrapOpts
        AgentSetup setupOpts -> do
          modelConfig <- resolveAgentModelConfigFor AgentCmdSetup agentOpts.agentProvider agentOpts.agentModel agentOpts.agentEffort setupOpts.setupProvider setupOpts.setupModel setupOpts.setupEffort
          handleSetup agentOpts.agentDebug modelConfig setupOpts
        AgentRun blueprintRunOpts -> do
          modelConfig <- resolveAgentModelConfigFor AgentCmdRun agentOpts.agentProvider agentOpts.agentModel agentOpts.agentEffort blueprintRunOpts.runBlueprintProvider blueprintRunOpts.runBlueprintModel blueprintRunOpts.runBlueprintEffort
          handleAgentRun agentOpts.agentDebug modelConfig blueprintRunOpts
        AgentMigrate migrationOpts -> do
          modelConfig <- resolveAgentModelConfigFor AgentCmdMigrate agentOpts.agentProvider agentOpts.agentModel agentOpts.agentEffort migrationOpts.migrateBlueprintProvider migrationOpts.migrateBlueprintModel migrationOpts.migrateBlueprintEffort
          handleAgentMigrate agentOpts.agentDebug modelConfig migrationOpts
        AgentModels modelsOpts ->
          case agentOpts.agentModel of
            Just _ -> do
              TIO.putStrLn "Error: --model does not apply to 'seihou agent models'; omit it to list known choices."
              exitFailure
            Nothing ->
              case modelsOpts.modelsProvider <|> agentOpts.agentProvider of
                Nothing ->
                  TIO.putStr (AgentModels.formatAgentModels Nothing AgentModels.availableAgentModels)
                Just providerText ->
                  case AgentCompletion.providerFromText providerText of
                    Left err -> do
                      TIO.putStrLn $ "Error: " <> err
                      exitFailure
                    Right provider ->
                      TIO.putStr (AgentModels.formatAgentModels (Just provider) AgentModels.availableAgentModels)
        AgentConfigShow ->
          handleAgentConfigShow
    Prompt promptCmd -> do
      case promptCmd of
        PromptRun promptRunOpts -> do
          modelConfig <- resolveAgentModelConfigFor AgentCmdPromptRun Nothing Nothing Nothing promptRunOpts.runPromptProvider promptRunOpts.runPromptModel promptRunOpts.runPromptEffort
          handlePromptRun modelConfig promptRunOpts
    Extension extensionCmd -> do
      case extensionCmd of
        ExtensionRun extensionRunOpts ->
          handleExtensionRun extensionRunOpts
    HelpCmd helpCmd ->
      handleHelpCommand helpCmd
    Completions completionsCmd ->
      handleCompletionsCommand completionsCmd

-- | Resolve the effective provider/model/effort for one agent command. The
-- subcommand flag wins over the parent @seihou agent@ flag; that combined flag
-- then feeds the per-command config resolution, which also consults the
-- command's own @agent.<command>.*@ keys before the shared @agent.*@ defaults.
resolveAgentModelConfigFor ::
  AgentCommandName ->
  -- | parent @seihou agent@ provider, model, effort
  Maybe Text ->
  Maybe Text ->
  Maybe Text ->
  -- | subcommand provider, model, effort
  Maybe Text ->
  Maybe Text ->
  Maybe Text ->
  IO AgentCompletion.AgentModelConfig
resolveAgentModelConfigFor cmd parentProvider parentModel parentEffort commandProvider commandModel commandEffort = do
  let provider = commandProvider <|> parentProvider
      model = commandModel <|> parentModel
      effort = commandEffort <|> parentEffort
  configResult <-
    loadAgentModelConfigFor cmd provider model effort (isJust commandProvider) (isJust commandModel) (isJust commandEffort)
  case configResult of
    Left err -> do
      TIO.putStrLn $ "Error: " <> err
      exitFailure
    Right config -> pure config
