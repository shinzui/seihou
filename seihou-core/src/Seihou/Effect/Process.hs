module Seihou.Effect.Process
  ( Process (..),
    runProcess,
  )
where

import Data.Text (Text)
import Effectful
import Effectful.Dispatch.Dynamic
import System.Exit (ExitCode)

data Process :: Effect where
  RunProcess :: Text -> [Text] -> Maybe FilePath -> Process m (ExitCode, Text, Text)

type instance DispatchOf Process = Dynamic

runProcess :: (Process :> es) => Text -> [Text] -> Maybe FilePath -> Eff es (ExitCode, Text, Text)
runProcess cmd args workDir = send (RunProcess cmd args workDir)
