-- | Dispatcher for @seihou check@. The work lives in
-- "Seihou.CLI.Judgement.Check"; this module only maps options and the exit
-- status.
module Seihou.CLI.Check (handleCheck) where

import Data.Generics.Labels ()
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (CheckOpts (..))
import Seihou.CLI.Judgement.Check
import Seihou.CLI.Judgement.Evidence (gitBytes)
import Seihou.Core.JudgementState (policyWeakenings)
import Seihou.Prelude
import System.Directory (getCurrentDirectory)
import System.Exit (ExitCode (..), exitWith)

handleCheck :: CheckOpts -> IO ()
handleCheck opts = do
  root <- getCurrentDirectory
  outcome <- case (opts ^. #staged, traverse parseRange (opts ^. #range)) of
    (True, Right (Just _)) -> pure (CheckOutcome 1 "--staged and --range select different evidence; give one of them.\n")
    (_, Left err) -> pure (CheckOutcome 1 (err <> "\n"))
    (_, Right range) -> do
      let req = CheckRequest (opts ^. #judgement) range (opts ^. #dryRun) (opts ^. #json)
      policy <- maybe (loadActiveJudgements root) (loadPolicyAt (gitBytes root)) (opts ^. #policyRef)
      case policy of
        Left err -> pure (CheckOutcome 1 (err <> "\n"))
        Right active -> do
          services <- productionServices root
          out <- runCheck services active req
          -- A staged check against the working tree's own policy says so when
          -- that policy is weaker than the one committed at HEAD.
          notices <- case (opts ^. #policyRef, range) of
            (Nothing, Nothing) ->
              loadPolicyAt (gitBytes root) "HEAD" <&> \case
                Right trusted -> policyWeakenings trusted active
                Left _ -> []
            _ -> pure []
          pure $
            if null notices || opts ^. #json
              then out
              else out & #output %~ (T.unlines ["Policy change staged, weaker than HEAD: " <> n | n <- notices] <>)
  TIO.putStr (outcome ^. #output)
  exitWith (if outcome ^. #exitCode == 0 then ExitSuccess else ExitFailure (outcome ^. #exitCode))
