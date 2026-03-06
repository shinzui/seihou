module Seihou.Effect.LoggerPure
  ( runLoggerPure,
    LoggerState (..),
    emptyLoggerState,
  )
where

import Effectful.State.Static.Local (State, modify, runState)
import Seihou.Effect.Logger (Logger (..))
import Seihou.Prelude

-- | State capturing all log messages by severity.
-- Messages are appended in order within each field.
data LoggerState = LoggerState
  { logDebugMsgs :: [Text],
    logInfoMsgs :: [Text],
    logWarnMsgs :: [Text],
    logErrorMsgs :: [Text]
  }
  deriving stock (Eq, Show)

-- | Empty logger state with no captured messages.
emptyLoggerState :: LoggerState
emptyLoggerState = LoggerState [] [] [] []

-- | Pure interpreter for the Logger effect.
-- Captures all messages regardless of level, organized by severity.
-- Use this for testing code that emits log messages.
runLoggerPure :: Eff (Logger : es) a -> Eff es (a, LoggerState)
runLoggerPure = reinterpret (runState emptyLoggerState) handler
  where
    handler :: (State LoggerState :> es') => EffectHandler Logger es'
    handler _ = \case
      LogDebug msg -> modify @LoggerState (\s -> s {logDebugMsgs = s.logDebugMsgs ++ [msg]})
      LogInfo msg -> modify @LoggerState (\s -> s {logInfoMsgs = s.logInfoMsgs ++ [msg]})
      LogWarn msg -> modify @LoggerState (\s -> s {logWarnMsgs = s.logWarnMsgs ++ [msg]})
      LogError msg -> modify @LoggerState (\s -> s {logErrorMsgs = s.logErrorMsgs ++ [msg]})
