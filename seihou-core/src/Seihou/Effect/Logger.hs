module Seihou.Effect.Logger
  ( Logger (..),
    logDebug,
    logInfo,
    logWarn,
    logError,
  )
where

import Seihou.Prelude

data Logger :: Effect where
  LogDebug :: Text -> Logger m ()
  LogInfo :: Text -> Logger m ()
  LogWarn :: Text -> Logger m ()
  LogError :: Text -> Logger m ()

type instance DispatchOf Logger = Dynamic

logDebug :: (Logger :> es) => Text -> Eff es ()
logDebug msg = send (LogDebug msg)

logInfo :: (Logger :> es) => Text -> Eff es ()
logInfo msg = send (LogInfo msg)

logWarn :: (Logger :> es) => Text -> Eff es ()
logWarn msg = send (LogWarn msg)

logError :: (Logger :> es) => Text -> Eff es ()
logError msg = send (LogError msg)
