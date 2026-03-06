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
      LogDebug msg -> modify (\s -> s {logDebugMsgs = logDebugMsgs s ++ [msg]})
      LogInfo msg -> modify (\s -> s {logInfoMsgs = logInfoMsgs s ++ [msg]})
      LogWarn msg -> modify (\s -> s {logWarnMsgs = logWarnMsgs s ++ [msg]})
      LogError msg -> modify (\s -> s {logErrorMsgs = logErrorMsgs s ++ [msg]})
