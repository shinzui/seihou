module Main (main) where

import Data.Text qualified as T
import Options.Applicative (execParser)
import Seihou.CLI.Commands
import Seihou.CLI.Run (handleRun)
import Seihou.CLI.Status (handleStatus)
import Seihou.Core.Types (ModuleName (..))

main :: IO ()
main = do
  cmd <- execParser opts
  case cmd of
    Init ->
      putStrLn "seihou init: not yet implemented"
    Run runOpts ->
      handleRun runOpts
    Vars varsOpts -> do
      let modName = T.unpack (unModuleName (varsModule varsOpts))
      putStrLn $
        "seihou vars: not yet implemented (module: "
          <> modName
          <> ", explain: "
          <> show (varsExplain varsOpts)
          <> ")"
    Install installOpts ->
      putStrLn $
        "seihou install: not yet implemented (source: "
          <> T.unpack (installSource installOpts)
          <> ")"
    Status ->
      handleStatus
    NewModule newModOpts ->
      putStrLn $
        "seihou new-module: not yet implemented (name: "
          <> T.unpack (newModuleName newModOpts)
          <> ")"
    ValidateModule validateOpts ->
      putStrLn $
        "seihou validate-module: not yet implemented (path: "
          <> show (validatePath validateOpts)
          <> ")"
