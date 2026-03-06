module Seihou.Effect.ProcessPure
  ( runProcessPure,
    ProcessMock (..),
  )
where

import Seihou.Effect.Process (Process (..))
import Seihou.Prelude
import System.Exit (ExitCode (..))

data ProcessMock = ProcessMock
  { mockCommand :: Text,
    mockArgs :: [Text],
    mockResult :: (ExitCode, Text, Text)
  }
  deriving stock (Eq, Show)

runProcessPure :: [ProcessMock] -> Eff (Process : es) a -> Eff es a
runProcessPure mocks = interpret $ \_ -> \case
  RunProcess cmd args _workDir ->
    case findMock cmd args mocks of
      Just result -> pure result
      Nothing -> pure (ExitFailure 127, "", "command not found: " <> cmd)

findMock :: Text -> [Text] -> [ProcessMock] -> Maybe (ExitCode, Text, Text)
findMock _ _ [] = Nothing
findMock cmd args (m : ms)
  | mockCommand m == cmd && mockArgs m == args = Just (mockResult m)
  | otherwise = findMock cmd args ms
