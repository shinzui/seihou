module Seihou.CLI.Sync (handleSync) where

import Control.Monad (unless)
import Data.Aeson qualified as A
import Data.ByteString.Lazy.Char8 qualified as LBS
import Data.Generics.Labels ()
import Data.Maybe (isJust)
import Data.Text.IO qualified as TIO
import Seihou.CLI.CheckoutSync
import Seihou.CLI.CommandExecution (commandOutcomesFailed)
import Seihou.CLI.Commands (SyncOpts (..))
import Seihou.CLI.Judgement.Adopt (judgementHookState)
import Seihou.Core.Checkout
import Seihou.Engine.Checkout (CheckoutExecution (..))
import Seihou.Prelude
import System.Directory (getCurrentDirectory)
import System.Exit (exitFailure)

handleSync :: SyncOpts -> IO ()
handleSync opts = do
  runCheckoutSync (opts ^. #dryRun) >>= either (failSync opts) (\r -> emitReport opts r)
  root <- getCurrentDirectory
  judgementHookState root (opts ^. #dryRun) >>= \case
    Left err -> TIO.putStrLn err >> exitFailure
    Right msgs -> unless (opts ^. #json) (mapM_ TIO.putStrLn msgs)

failSync :: SyncOpts -> CheckoutError -> IO a
failSync opts err = do
  if opts ^. #json
    then LBS.putStrLn (A.encode (checkoutFailureJSON (opts ^. #dryRun) err))
    else TIO.putStrLn (err ^. #message)
  exitFailure

emitReport :: SyncOpts -> CheckoutSyncResult -> IO ()
emitReport opts report = do
  if opts ^. #json
    then LBS.putStrLn (A.encode (checkoutReportJSON report))
    else TIO.putStr (renderCheckoutReport report)
  if not (checkoutApplicable (report ^. #plan)) || isJust (report ^. #execution . #failure) || commandOutcomesFailed (map snd (report ^. #commandOutcomes)) then exitFailure else pure ()
