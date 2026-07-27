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
  { debugMsgs :: ![Text],
    infoMsgs :: ![Text],
    warnMsgs :: ![Text],
    errorMsgs :: ![Text]
  }
  deriving stock (Eq, Generic, Show)

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
      LogDebug msg -> modify @LoggerState (\s -> s {debugMsgs = s.debugMsgs ++ [msg]})
      LogInfo msg -> modify @LoggerState (\s -> s {infoMsgs = s.infoMsgs ++ [msg]})
      LogWarn msg -> modify @LoggerState (\s -> s {warnMsgs = s.warnMsgs ++ [msg]})
      LogError msg -> modify @LoggerState (\s -> s {errorMsgs = s.errorMsgs ++ [msg]})
