module Main (main) where

import Data.Text qualified as T
import Options.Applicative (execParser)
import Seihou.CLI.Commands
import Seihou.Core.Types (ModuleName (..))

main :: IO ()
main = do
  cmd <- execParser opts
  case cmd of
    Init ->
      putStrLn "seihou init: not yet implemented"
    Run runOpts -> do
      let modName = T.unpack (unModuleName (runModule runOpts))
      putStrLn $
        "seihou run: not yet implemented (module: "
          <> modName
          <> ", dry-run: "
          <> show (runDryRun runOpts)
          <> ")"
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
      putStrLn "seihou status: not yet implemented"
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
