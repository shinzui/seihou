module Seihou.CLI.Sync (handleSync) where

import Data.Aeson qualified as A
import Data.ByteString.Lazy.Char8 qualified as LBS
import Data.Generics.Labels ()
import Data.Maybe (isJust)
import Data.Text.IO qualified as TIO
import Seihou.CLI.CheckoutSync
import Seihou.CLI.Commands (SyncOpts (..))
import Seihou.Core.Checkout
import Seihou.Engine.Checkout (CheckoutExecution (..))
import Seihou.Prelude
import System.Exit (exitFailure)

handleSync :: SyncOpts -> IO ()
handleSync opts = do
  result <- runCheckoutSync (opts ^. #dryRun)
  case result of
    Left err -> do
      if opts ^. #json
        then LBS.putStrLn (A.encode (checkoutFailureJSON (opts ^. #dryRun) err))
        else TIO.putStrLn (err ^. #message)
      exitFailure
    Right report -> do
      if opts ^. #json
        then LBS.putStrLn (A.encode (checkoutReportJSON report))
        else do
          TIO.putStr (renderCheckoutReport report)
      if not (checkoutApplicable (report ^. #plan)) || isJust (report ^. #execution . #failure) then exitFailure else pure ()
