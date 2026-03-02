module Seihou.Effect.ConsoleInterp
  ( runConsole,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Effectful
import Effectful.Dispatch.Dynamic
import Seihou.Effect.Console (Console (..))
import System.IO (hFlush, hIsTerminalDevice, hPutStrLn, stderr, stdin, stdout)
import Prelude hiding (getLine)

-- | Real IO interpreter for the Console effect.
-- Writes output to stdout, errors to stderr, reads from stdin.
-- TTY detection uses 'hIsTerminalDevice' on stdin.
runConsole :: (IOE :> es) => Eff (Console : es) a -> Eff es a
runConsole = interpret $ \_ -> \case
  PutText msg -> liftIO $ TIO.putStrLn msg
  PutError msg -> liftIO $ hPutStrLn stderr (T.unpack msg)
  GetLine -> liftIO $ do
    hFlush stdout
    TIO.getLine
  Confirm prompt -> liftIO $ do
    TIO.putStr (prompt <> " [y/n] ")
    hFlush stdout
    answer <- TIO.getLine
    pure (T.toLower (T.strip answer) `elem` ["y", "yes"])
  IsInteractive -> liftIO $ hIsTerminalDevice stdin
