module Main (main) where

import Options.Applicative (execParser)
import Seihou.CLI.Browse (handleBrowse)
import Seihou.CLI.Commands
import Seihou.CLI.Config (handleConfig)
import Seihou.CLI.Diff (handleDiff)
import Seihou.CLI.Init (handleInit)
import Seihou.CLI.Install (handleInstall)
import Seihou.CLI.List (handleList)
import Seihou.CLI.NewModule (handleNewModule)
import Seihou.CLI.Run (handleRun)
import Seihou.CLI.Status (handleStatus)
import Seihou.CLI.Validate (handleValidateModule)
import Seihou.CLI.Vars (handleVars)

main :: IO ()
main = do
  cmd <- execParser opts
  case cmd of
    Init ->
      handleInit
    Run runOpts ->
      handleRun runOpts
    Vars varsOpts ->
      handleVars varsOpts
    Install installOpts ->
      handleInstall installOpts
    Status ->
      handleStatus
    Diff ->
      handleDiff
    List ->
      handleList
    NewModule newModOpts ->
      handleNewModule newModOpts
    ValidateModule validateOpts ->
      handleValidateModule validateOpts
    Config configOpts ->
      handleConfig configOpts
    Browse browseOpts ->
      handleBrowse browseOpts
