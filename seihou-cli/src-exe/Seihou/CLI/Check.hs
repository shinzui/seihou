-- | Dispatcher for @seihou check@. The work lives in
-- "Seihou.CLI.Judgement.Check"; this module only maps options and the exit
-- status.
module Seihou.CLI.Check (handleCheck) where

import Data.Generics.Labels ()
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (CheckOpts (..))
import Seihou.CLI.Judgement.Check
import Seihou.Prelude
import System.Directory (getCurrentDirectory)
import System.Exit (ExitCode (..), exitWith)

handleCheck :: CheckOpts -> IO ()
handleCheck opts = do
  root <- getCurrentDirectory
  let req = CheckRequest (opts ^. #judgement) (opts ^. #dryRun) (opts ^. #json)
  outcome <-
    loadActiveJudgements root >>= \case
      Left err -> pure (CheckOutcome 1 (err <> "\n"))
      Right active -> do
        services <- productionServices root
        runCheck services active req
  TIO.putStr (outcome ^. #output)
  exitWith (if outcome ^. #exitCode == 0 then ExitSuccess else ExitFailure (outcome ^. #exitCode))
