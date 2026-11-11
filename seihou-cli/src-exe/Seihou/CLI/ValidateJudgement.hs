-- | @seihou validate-judgement [TARGET]@.
module Seihou.CLI.ValidateJudgement (handleValidateJudgement) where

import Control.Monad (unless)
import Data.Generics.Labels ()
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (ValidateJudgementOpts (..))
import Seihou.CLI.Judgement.Validate
import Seihou.Prelude
import System.Exit (exitFailure)

handleValidateJudgement :: ValidateJudgementOpts -> IO ()
handleValidateJudgement opts =
  resolveJudgementTarget (opts ^. #target) >>= \case
    Left err -> TIO.putStrLn err >> exitFailure
    Right dir -> do
      v <- validateJudgementDir dir
      TIO.putStr (renderValidation v)
      unless (null (v ^. #errors)) exitFailure
