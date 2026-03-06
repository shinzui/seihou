module Seihou.Effect.LoggerInterp
  ( runLoggerIO,
    shouldLog,
  )
where

import Control.Monad (when)
import Data.Text qualified as T
import Seihou.Core.Types (LogLevel (..))
import Seihou.Effect.Logger (Logger (..))
import Seihou.Prelude
import System.IO (hPutStrLn, stderr)

-- | IO interpreter for the Logger effect.
-- Messages are written to stderr, filtered by the given 'LogLevel'.
-- At 'LogQuiet', only errors are shown. At 'LogNormal', warnings and errors.
-- At 'LogVerbose', all messages including info and debug.
runLoggerIO :: (IOE :> es) => LogLevel -> Eff (Logger : es) a -> Eff es a
runLoggerIO level = interpret $ \_ -> \case
  LogDebug msg -> whenLevel LogVerbose $ emit "[debug] " msg
  LogInfo msg -> whenLevel LogVerbose $ emit "[info]  " msg
  LogWarn msg -> whenLevel LogNormal $ emit "[warn]  " msg
  LogError msg -> whenLevel LogQuiet $ emit "[error] " msg
  where
    whenLevel minLevel action =
      when (shouldLog level minLevel) action
    emit prefix msg =
      liftIO $ hPutStrLn stderr (T.unpack (prefix <> msg))

-- | Pure filtering predicate: does the configured level permit a message
-- that requires @minLevel@?
--
-- >>> shouldLog LogVerbose LogVerbose
-- True
-- >>> shouldLog LogNormal LogVerbose
-- False
shouldLog :: LogLevel -> LogLevel -> Bool
shouldLog configured minLevel = configured >= minLevel
