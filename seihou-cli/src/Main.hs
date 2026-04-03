module Main (main) where

import Options.Applicative (customExecParser, prefs, showHelpOnEmpty)
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
import Seihou.CLI.NewModule (handleNewModule)
import Seihou.CLI.Outdated (handleOutdated)
import Seihou.CLI.Remove (handleRemove)
import Seihou.CLI.Run (handleRun)
import Seihou.CLI.SchemaUpgrade (handleSchemaUpgrade)
import Seihou.CLI.Setup (handleSetup)
import Seihou.CLI.Status (handleStatus)
import Seihou.CLI.Upgrade (handleUpgrade)
import Seihou.CLI.Validate (handleValidateModule)
import Seihou.CLI.Vars (handleVars)

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
    Status ->
      handleStatus
    Diff ->
      handleDiff
    List listOpts ->
      handleList (ListFilter listOpts.listRepo listOpts.listTag)
    NewModule newModOpts ->
      handleNewModule newModOpts
    ValidateModule validateOpts ->
      handleValidateModule validateOpts
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
    SchemaUpgrade schemaUpgradeOpts ->
      handleSchemaUpgrade schemaUpgradeOpts
    Kit kitCmd ->
      runKit kitCmd
    Agent agentOpts -> case agentOpts.agentCommand of
      AgentAssist assistOpts ->
        handleAssist agentOpts.agentDebug assistOpts
      AgentBootstrap bootstrapOpts ->
        handleBootstrap agentOpts.agentDebug bootstrapOpts
      AgentSetup setupOpts ->
        handleSetup agentOpts.agentDebug setupOpts
    HelpCmd helpCmd ->
      handleHelpCommand helpCmd
    Completions completionsCmd ->
      handleCompletionsCommand completionsCmd
