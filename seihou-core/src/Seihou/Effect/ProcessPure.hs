module Seihou.Effect.ProcessPure
  ( runProcessPure,
    ProcessMock (..),
  )
where

import Data.Generics.Labels ()
import Seihou.Effect.Process (Process (..))
import Seihou.Prelude
import System.Exit (ExitCode (..))

data ProcessMock = ProcessMock
  { command :: !Text,
    args :: ![Text],
    result :: !(ExitCode, Text, Text)
  }
  deriving stock (Eq, Generic, Show)

runProcessPure :: [ProcessMock] -> Eff (Process : es) a -> Eff es a
runProcessPure mocks = interpret $ \_ -> \case
  RunProcess cmd args _workDir ->
    case findMock cmd args mocks of
      Just result -> pure result
      Nothing -> pure (ExitFailure 127, "", "command not found: " <> cmd)

findMock :: Text -> [Text] -> [ProcessMock] -> Maybe (ExitCode, Text, Text)
findMock _ _ [] = Nothing
findMock cmd args (m : ms)
  | m ^. #command == cmd && m ^. #args == args = Just (m ^. #result)
  | otherwise = findMock cmd args ms
