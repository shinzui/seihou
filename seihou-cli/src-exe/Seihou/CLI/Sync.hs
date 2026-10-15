module Seihou.CLI.Sync (handleSync) where

import Control.Monad (unless, when)
import Data.Aeson qualified as A
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString.Lazy.Char8 qualified as LBS
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.CheckoutSync
import Seihou.CLI.CommandExecution (CommandPolicy (..))
import Seihou.CLI.Commands (SyncOpts (..))
import Seihou.CLI.Update.Interaction (InteractionMode (..), resolveInteractively)
import Seihou.CLI.Update.Render (encodeUpdateOutput, errorCode, errorOutput, planOutput, renderUpdateHuman)
import Seihou.Core.Checkout
import Seihou.Engine.Checkout (CheckoutExecution (..))
import Seihou.Prelude
import System.Exit (exitFailure)
import System.IO (hFlush, hIsTerminalDevice, isEOF, stderr, stdin)
import "seihou-cli" Seihou.CLI.Update qualified as Update

handleSync :: SyncOpts -> IO ()
handleSync opts = do
  result <- runCheckoutSync (opts ^. #dryRun)
  case result of
    Left err -> failSync opts err
    Right report
      | null (report ^. #plan . #entries) -> adoptLinks opts report
      | otherwise -> emitReport opts report

-- Empty older manifests need setup, not a successful zero-work report. Keep the
-- manifest-only engine unchanged; the CLI owns the explicit adoption workflow.
adoptLinks :: SyncOpts -> CheckoutSyncResult -> IO ()
adoptLinks opts emptyReport = do
  terminal <- hIsTerminalDevice stdin
  let interactive = terminal && not (opts ^. #json)
      request =
        Update.UpdateRequest
          { selection = Update.AllRecordedApplications,
            varOverrides = [],
            reconfigure = False,
            promptPolicy = if interactive then Update.AllowPrompts else Update.ForbidPrompts,
            commandPolicy = DisableCommands,
            dryRun = opts ^. #dryRun,
            allowDowngrade = False,
            includeSharedOwners = True
          }
  unless (opts ^. #json) $ TIO.putStrLn "No checkout links are recorded yet. Checking the project's recorded sources for link setup..."
  Update.withCheckoutAdoption request $ \case
    Left err -> failAdoption opts err
    Right Nothing -> emitReport opts (emptyReport & #notices .~ ["No checkout links are declared by the recorded applications. Nothing to sync."])
    Right (Just plan) -> do
      let preview =
            emptyReport
              & #dryRun
              .~ True
              & #plan
              .~ (plan ^. #checkoutPlan)
              & #notices
              .~ ["One-time link setup will update the project manifest and the files shown in the preview. Commit those changes so teammates can use seihou sync."]
          jsonPreview = case checkoutReportJSON preview of
            A.Object fields -> A.Object $ KM.insert "adoption" (A.object ["approvalRequired" A..= True, "update" A..= (A.decode (encodeUpdateOutput (planOutput plan)) :: Maybe A.Value)]) fields
            other -> other
      if opts ^. #json
        then when (opts ^. #dryRun || not (opts ^. #yes)) (LBS.putStrLn (A.encode jsonPreview))
        else do
          TIO.putStrLn "One-time link setup is available. Review these project changes:"
          TIO.putStr (renderUpdateHuman False (planOutput plan))
          TIO.putStrLn "Commit the resulting manifest and source changes so teammates can use seihou sync."
      unless (opts ^. #dryRun) $ do
        accepted <- if opts ^. #yes then pure True else confirmAdoption interactive
        if not accepted
          then do
            unless (opts ^. #json) $ TIO.hPutStrLn stderr "Link setup was not applied. Run seihou sync in a terminal to review and accept it, or use seihou sync --yes for automation."
            exitFailure
          else do
            resolved <- resolveInteractively (if interactive then Interactive else NonInteractive) plan
            case resolved of
              Left _ -> failSync opts (checkoutError "checkout_adoption_conflict" "Link setup has unresolved file conflicts. Run seihou sync in a terminal to resolve them; no link setup was applied.")
              Right ready -> do
                applied <- Update.applyProjectUpdate ready
                case applied of
                  Left err -> failAdoption opts err
                  Right _ -> do
                    -- An empty prior declaration set means every new output was
                    -- checked and materialized by the update transaction itself.
                    let entries = ready ^. #checkoutPlan . #entries
                        outcomes = Map.fromList [(entry ^. #dest, if entry ^. #action == UnchangedLink then "unchanged" else "applied") | entry <- entries]
                        report =
                          preview
                            & #dryRun
                            .~ False
                            & #plan
                            .~ (ready ^. #checkoutPlan)
                            & #execution
                            .~ CheckoutExecution outcomes [] Nothing
                            & #notices
                            .~ ["Link setup adopted. Commit the manifest and source changes; teammates then run seihou sync."]
                    emitReport opts report

confirmAdoption :: Bool -> IO Bool
confirmAdoption False = pure False
confirmAdoption True = do
  TIO.hPutStr stderr "Apply link setup? [Y/n] "
  hFlush stderr
  eof <- isEOF
  if eof
    then pure False
    else do
      answer <- T.toLower . T.strip <$> TIO.getLine
      case answer of
        "" -> pure True
        "y" -> pure True
        "yes" -> pure True
        "n" -> pure False
        "no" -> pure False
        _ -> TIO.hPutStrLn stderr "Please answer yes or no." >> confirmAdoption True

failAdoption :: SyncOpts -> Update.UpdateError -> IO a
failAdoption opts err =
  failSync opts (checkoutError (errorCode err) (T.strip (renderUpdateHuman False (errorOutput err))))

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
  if not (checkoutApplicable (report ^. #plan)) || isJust (report ^. #execution . #failure) then exitFailure else pure ()
