module Main (main) where

import Control.Applicative ((<|>))
import Control.Lens ((^.))
import Data.Generics.Labels ()
import Data.List (isPrefixOf)
import Data.Maybe (isJust)
import Data.String (fromString)
import Data.Text (Text)
import Data.Text.IO qualified as TIO
import Options.Applicative (customExecParser, prefs, showHelpOnEmpty)
import Seihou.CLI.AgentCompletion qualified as AgentCompletion
import Seihou.CLI.AgentConfig (AgentCommandName (..), AgentSettingFlags (..), PendingAgentConfig, loadAgentModelConfigFor, loadPendingAgentConfig, noAgentSettingFlags)
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
import Seihou.CLI.Manifest (handleManifest)
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
          { name = fromString name,
            args =
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
            [KindModule | listOpts ^. #modulesOnly]
              <> [KindRecipe | listOpts ^. #recipesOnly]
              <> [KindBlueprint | listOpts ^. #blueprintsOnly]
              <> [KindPrompt | listOpts ^. #promptsOnly]
       in handleList (ListFilter (listOpts ^. #repo) (listOpts ^. #tag) kinds)
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
    ManifestCmd manifestCmd ->
      handleManifest manifestCmd
    Kit kitCmd ->
      runKit kitCmd
    Agent agentOpts -> do
      case agentOpts ^. #command of
        AgentAssist assistOpts -> do
          modelConfig <- resolveAgentModelConfigFor AgentCmdAssist (parentAgentFlags agentOpts) (AgentSettingFlags (assistOpts ^. #provider) (assistOpts ^. #model) (assistOpts ^. #effort) (assistOpts ^. #trace))
          handleAssist (agentOpts ^. #debug) modelConfig assistOpts
        AgentBootstrap bootstrapOpts -> do
          modelConfig <- resolveAgentModelConfigFor AgentCmdBootstrap (parentAgentFlags agentOpts) (AgentSettingFlags (bootstrapOpts ^. #provider) (bootstrapOpts ^. #model) (bootstrapOpts ^. #effort) (bootstrapOpts ^. #trace))
          handleBootstrap (agentOpts ^. #debug) modelConfig bootstrapOpts
        AgentSetup setupOpts -> do
          modelConfig <- resolveAgentModelConfigFor AgentCmdSetup (parentAgentFlags agentOpts) (AgentSettingFlags (setupOpts ^. #provider) (setupOpts ^. #model) (setupOpts ^. #effort) (setupOpts ^. #trace))
          handleSetup (agentOpts ^. #debug) modelConfig setupOpts
        AgentRun blueprintRunOpts -> do
          pending <- pendingAgentConfigFor AgentCmdRun (parentAgentFlags agentOpts) (AgentSettingFlags (blueprintRunOpts ^. #provider) (blueprintRunOpts ^. #model) (blueprintRunOpts ^. #effort) (blueprintRunOpts ^. #trace))
          handleAgentRun (agentOpts ^. #debug) pending blueprintRunOpts
        AgentMigrate migrationOpts -> do
          pending <- pendingAgentConfigFor AgentCmdMigrate (parentAgentFlags agentOpts) (AgentSettingFlags (migrationOpts ^. #provider) (migrationOpts ^. #model) (migrationOpts ^. #effort) (migrationOpts ^. #trace))
          handleAgentMigrate (agentOpts ^. #debug) pending migrationOpts
        AgentModels modelsOpts ->
          case agentOpts ^. #model of
            Just _ -> do
              TIO.putStrLn "Error: --model does not apply to 'seihou agent models'; omit it to list known choices."
              exitFailure
            Nothing ->
              case modelsOpts ^. #modelsProvider <|> agentOpts ^. #provider of
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
          pending <- pendingAgentConfigFor AgentCmdPromptRun noAgentSettingFlags (AgentSettingFlags (promptRunOpts ^. #provider) (promptRunOpts ^. #model) (promptRunOpts ^. #effort) (promptRunOpts ^. #trace))
          handlePromptRun pending promptRunOpts
    Extension extensionCmd -> do
      case extensionCmd of
        ExtensionRun extensionRunOpts ->
          handleExtensionRun extensionRunOpts
    HelpCmd helpCmd ->
      handleHelpCommand helpCmd
    Completions completionsCmd ->
      handleCompletionsCommand completionsCmd

-- | The four agent settings as given on the parent @seihou agent@ command.
parentAgentFlags :: AgentOpts -> AgentSettingFlags
parentAgentFlags agentOpts =
  AgentSettingFlags
    { provider = agentOpts ^. #provider,
      model = agentOpts ^. #model,
      effort = agentOpts ^. #effort,
      trace = agentOpts ^. #trace
    }

-- | Resolve the effective provider/model/effort/trace for one agent command.
-- The subcommand flag wins over the parent @seihou agent@ flag; that combined
-- flag then feeds the per-command config resolution, which also consults the
-- command's own @agent.<command>.*@ keys before the shared @agent.*@ defaults.
resolveAgentModelConfigFor ::
  AgentCommandName ->
  -- | flags on the parent @seihou agent@ command
  AgentSettingFlags ->
  -- | flags on the subcommand itself
  AgentSettingFlags ->
  IO AgentCompletion.AgentModelConfig
resolveAgentModelConfigFor cmd parentFlags commandFlags = do
  configResult <- loadAgentModelConfigFor cmd parentFlags commandFlags
  case configResult of
    Left err -> do
      TIO.putStrLn $ "Error: " <> err
      exitFailure
    Right config -> pure config

-- | Gather flags, environment, and config for a command whose artifact may
-- declare its own launch settings, stopping one step short of resolution.
--
-- The blueprint or prompt is not loaded until the handler runs, so the handler
-- finishes resolution itself with 'resolveDeclaredAgentConfig' once it knows
-- what the artifact declares. Flag combination and error reporting match
-- 'resolveAgentModelConfigFor' exactly.
pendingAgentConfigFor ::
  AgentCommandName ->
  -- | flags on the parent @seihou agent@ command
  AgentSettingFlags ->
  -- | flags on the subcommand itself
  AgentSettingFlags ->
  IO PendingAgentConfig
pendingAgentConfigFor cmd parentFlags commandFlags = do
  pendingResult <- loadPendingAgentConfig cmd parentFlags commandFlags
  case pendingResult of
    Left err -> do
      TIO.putStrLn $ "Error: " <> err
      exitFailure
    Right pending -> pure pending
