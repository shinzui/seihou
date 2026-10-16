module Seihou.CLI.CheckoutSync
  ( CheckoutSyncResult (..),
    runCheckoutSync,
    checkoutReportJSON,
    renderCheckoutPlan,
    renderCheckoutReport,
    checkoutAdoptionNotices,
    renderCheckoutStatus,
    checkoutFailureJSON,
  )
where

import Control.Exception (IOException, displayException, try)
import Control.Monad (forM)
import Data.Aeson qualified as A
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Seihou.CLI.CommandExecution
import Seihou.CLI.Update.Recovery (pendingUpdateRecovery)
import Seihou.Core.Checkout
import Seihou.Core.Types
import Seihou.Effect.Filesystem hiding (CreateDirectoryLink)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.ProcessInterp (runProcessIO)
import Seihou.Engine.Checkout
import Seihou.Manifest.Types (manifestFromJSON)
import Seihou.Prelude

-- | Planning and execution remain separate so dry-run never reports writes.
data CheckoutSyncResult = CheckoutSyncResult
  { root :: !FilePath,
    dryRun :: !Bool,
    plan :: !CheckoutPlan,
    execution :: !CheckoutExecution,
    notices :: ![Text],
    commands :: ![(ApplicationId, PlannedCommand)],
    commandOutcomes :: ![(ApplicationId, CommandOutcome)]
  }
  deriving stock (Eq, Show, Generic)

runCheckoutSync :: Bool -> IO (Either CheckoutError CheckoutSyncResult)
runCheckoutSync dryRun = do
  result <- try @IOException $ runEff $ runFilesystem $ runProcessIO $ do
    root <- normalizePath =<< getCurrentDirectory
    gitRoot <- checkoutGitRoot root
    case gitRoot of
      Nothing -> pure (Left (checkoutError "checkout_git_required" "seihou sync requires a Git working tree; run it from the working-tree root"))
      Just gitRoot | gitRoot /= root -> pure (Left (checkoutError "checkout_wrong_root" ("change directory to the Git working-tree root: " <> T.pack gitRoot)))
      _ -> do
        safe <- safeCheckoutManifest root
        case safe of
          Left err -> pure (Left err)
          Right () -> do
            pending <- liftIO (pendingUpdateRecovery root)
            if pending
              then pure (Left (checkoutError "checkout_update_recovery_pending" "An interrupted update needs recovery. Run seihou update --dry-run; its entry path recovers the prior transaction's files/index before previewing any new update. Then retry seihou sync."))
              else do
                bytes <- readFileText (root </> ".seihou/manifest.json")
                case manifestFromJSON (LBS.fromStrict (TE.encodeUtf8 bytes)) of
                  Left err -> pure (Left (checkoutError "checkout_manifest_invalid" (T.pack err <> "; use seihou manifest upgrade for an older manifest, or a newer seihou for a newer schema")))
                  Right manifest -> do
                    let commands = [(application ^. #applicationId, command) | application <- sortOn (^. #applicationId) (manifest ^. #applications), command <- planCheckoutCommands (application ^. #checkoutCommands) ^. #commands]
                    readiness <- forM commands $ \(application, command) -> case command ^. #operation of
                      RunCommandOp {workDir, moduleName} -> do
                        ready <- liftIO (checkCheckoutWorkDir root workDir)
                        pure (first (checkoutError "checkout_command_workdir" . (("application " <> application ^. #unApplicationId <> ", instance " <> moduleName ^. #unModuleName <> ": ") <>)) ready)
                      _ -> pure (Right ())
                    case sequence readiness of
                      Left err -> pure (Left err)
                      Right _ -> do
                        planned <- prepareCheckoutPlan Rebuild SyncIgnoredOnly root manifest manifest []
                        case planned of
                          Left err -> pure (Left err)
                          Right plan -> do
                            execution <- if dryRun then pure (CheckoutExecution Map.empty [] Nothing) else applyCheckoutPlan SyncIgnoredOnly root plan
                            outcomes <- if dryRun || not (checkoutApplicable plan) || execution ^. #failure /= Nothing then pure [] else executeCommandOutcomes (CommandPlan (map snd commands))
                            let notices = checkoutAdoptionNotices manifest
                            pure (Right (CheckoutSyncResult root dryRun plan execution notices commands (zip (map fst commands) outcomes)))
  pure $ case result of
    Left err -> Left (checkoutError "checkout_io_failed" ("cannot inspect checkout: " <> T.pack (displayException err)))
    Right value -> value

-- | Absence of declarations is zero recorded work, never authority to update.
checkoutAdoptionNotices :: Manifest -> [Text]
checkoutAdoptionNotices manifest
  | Map.null (manifest ^. #checkoutOutputs) && commandCount == 0 =
      ["No checkout effects are recorded. Nothing to sync."]
  | otherwise = []
  where
    commandCount = sum (map (length . (^. #checkoutCommands)) (manifest ^. #applications))

checkoutFailureJSON :: Bool -> CheckoutError -> A.Value
checkoutFailureJSON dryRun err = A.object ["mode" A..= mode dryRun, "outputs" A..= ([] :: [A.Value]), "errors" A..= [errorJSON err], "summary" A..= A.object ["planned" A..= counts [], "applied" A..= counts []]]

checkoutReportJSON :: CheckoutSyncResult -> A.Value
checkoutReportJSON result =
  A.object
    [ "mode" A..= mode (result ^. #dryRun),
      "root" A..= (result ^. #root),
      "applicable" A..= checkoutApplicable (result ^. #plan),
      "outputs" A..= map entryJSON entries,
      "commands" A..= map commandJSON (result ^. #commands),
      "errors" A..= map errorJSON (maybe [] pure (result ^. #execution . #failure)),
      "notices" A..= (result ^. #notices),
      "summary"
        A..= A.object
          [ "planned" A..= counts (map (^. #action) entries),
            "applied" A..= counts [entry ^. #action | entry <- entries, Map.lookup (entry ^. #dest) (result ^. #execution . #outcomes) == Just "applied"]
          ]
    ]
  where
    entries = result ^. #plan . #entries
    commandJSON (application, planned) =
      let outcome = lookupOutcome application planned
       in A.object ["application" A..= (application ^. #unApplicationId), "instance" A..= commandOwner planned, "command" A..= commandText planned, "outcome" A..= maybe (if result ^. #dryRun then "would-run" else "not-run") outcomeText outcome, "exitCode" A..= (outcome >>= (^. #exitCode)), "stdout" A..= maybe "" (^. #stdout) outcome, "stderr" A..= maybe "" (^. #stderr) outcome]
    lookupOutcome application planned = lookup (application, planned) [((owner, outcome ^. #command), outcome) | (owner, outcome) <- result ^. #commandOutcomes]
    entryJSON entry =
      A.object
        [ "destination" A..= (entry ^. #dest),
          "kind" A..= ("directory-symlink" :: Text),
          "plannedAction" A..= actionText (entry ^. #action),
          "observation" A..= observationJSON (entry ^. #observation),
          "outcome" A..= Map.findWithDefault "not-applied" (entry ^. #dest) (result ^. #execution . #outcomes),
          "errors" A..= map errorJSON (entry ^. #errors),
          "warnings" A..= (entry ^. #warnings)
        ]

mode :: Bool -> Text
mode True = "dry-run"
mode False = "apply"

counts :: [CheckoutAction] -> A.Value
counts actions = A.object ["created" A..= count CreateLink, "replaced" A..= count ReplaceLink, "retired" A..= count RetireLink, "unchanged" A..= count UnchangedLink, "refused" A..= count RefusedLink]
  where
    count action = length (filter (== action) actions)

errorJSON :: CheckoutError -> A.Value
errorJSON err = A.object ["code" A..= (err ^. #code), "message" A..= (err ^. #message)]

observationJSON :: CheckoutObservation -> A.Value
observationJSON observation =
  A.object
    [ "entry" A..= kind,
      "target" A..= target,
      "sourceDirectory" A..= (observation ^. #sourceDirectory),
      "gitAvailable" A..= (observation ^. #gitAvailable),
      "ignored" A..= (observation ^. #ignored)
    ]
  where
    (kind, target) = case observation ^. #entry of
      EntryMissing -> ("missing" :: Text, Nothing)
      EntryFile -> ("file", Nothing)
      EntryDirectory -> ("directory", Nothing)
      EntrySymlink target -> ("symlink", Just target)

actionText :: CheckoutAction -> Text
actionText CreateLink = "create"
actionText ReplaceLink = "replace-link"
actionText RetireLink = "retire-matching-link"
actionText UnchangedLink = "unchanged"
actionText AlreadyAbsent = "already-absent"
actionText PreserveModified = "preserve-modified"
actionText RefusedLink = "refused"

renderCheckoutPlan :: Bool -> CheckoutPlan -> Text
renderCheckoutPlan dryRun plan =
  T.unlines
    [ (if dryRun && entry ^. #action `elem` [CreateLink, ReplaceLink, RetireLink] then "would-" else "")
        <> actionText (entry ^. #action)
        <> " "
        <> T.pack (entry ^. #dest)
        <> T.concat [": " <> err ^. #message | err <- entry ^. #errors]
        <> T.concat ["; " <> warning | warning <- entry ^. #warnings]
    | entry <- plan ^. #entries
    ]

renderCheckoutReport :: CheckoutSyncResult -> Text
renderCheckoutReport report =
  renderCheckoutPlan (report ^. #dryRun) displayedPlan
    <> summary
    <> renderCommands report
    <> T.unlines (report ^. #notices)
    <> T.unlines (map (^. #message) (maybe [] pure (report ^. #execution . #failure)))
  where
    entries = report ^. #plan . #entries
    outcomes = report ^. #execution . #outcomes
    -- A failed or rolled-back apply must never print a proposed create as
    -- though it succeeded. The summary counts successful mutations only.
    displayedPlan =
      if report ^. #dryRun
        then report ^. #plan
        else
          CheckoutPlan
            [ entry
                & #warnings
                %~ (<> [outcome | outcome `notElem` ["applied", "unchanged"]])
                & #action
                .~ (if outcome `elem` ["applied", "unchanged"] then entry ^. #action else RefusedLink)
            | entry <- entries,
              let outcome = Map.findWithDefault "not-applied" (entry ^. #dest) outcomes
            ]
    countAction action =
      T.pack
        ( show
            ( length
                [ ()
                | entry <- entries,
                  entry ^. #action == action,
                  report ^. #dryRun || Map.lookup (entry ^. #dest) outcomes `elem` [Just "applied", Just "unchanged"]
                ]
            )
        )
    summary
      | null entries = ""
      | otherwise =
          (if report ^. #dryRun then "Would sync links: " else "Links: ")
            <> countAction CreateLink
            <> " created, "
            <> countAction ReplaceLink
            <> " repaired, "
            <> countAction UnchangedLink
            <> " unchanged.\n"

renderCheckoutStatus :: CheckoutPlan -> Text
renderCheckoutStatus plan
  | null (plan ^. #entries) = "Checkout outputs: none declared.\n"
  | otherwise =
      let affected = filter ((/= UnchangedLink) . (^. #action)) (plan ^. #entries)
          count = length affected
       in "Checkout outputs: "
            <> T.pack (show (length (plan ^. #entries)))
            <> " declared, "
            <> T.pack (show count)
            <> " need attention.\n"
            <> T.concat ["  " <> T.pack (entry ^. #dest) <> ": " <> reason entry <> "\n" | entry <- take 10 affected]
            <> (if count > 10 then "  … " <> T.pack (show (count - 10)) <> " more affected paths\n" else "")
  where
    reason entry = case entry ^. #errors of
      err : _ -> err ^. #message
      [] -> case entry ^. #action of
        CreateLink -> "missing link; run seihou sync"
        ReplaceLink -> "wrong link target; run seihou sync"
        RetireLink -> "retirement pending"
        AlreadyAbsent -> "already absent"
        PreserveModified -> "modified entry preserved"
        UnchangedLink -> "correct"
        RefusedLink -> "repair refused; inspect this path"

commandOwner :: PlannedCommand -> Text
commandOwner planned = case planned ^. #operation of
  RunCommandOp {moduleName} -> moduleName ^. #unModuleName
  _ -> ""

commandText :: PlannedCommand -> Text
commandText planned = case planned ^. #operation of
  RunCommandOp {command} -> command
  _ -> ""

outcomeText :: CommandOutcome -> Text
outcomeText outcome = case outcome ^. #status of
  CommandSucceeded -> "succeeded"
  CommandFailed -> "failed"
  CommandSkipped -> "skipped"
  CommandNotRun -> "not-run"

renderCommands :: CheckoutSyncResult -> Text
renderCommands report =
  T.concat
    [ let outcome = lookup (application, planned) [((owner, value ^. #command), value) | (owner, value) <- report ^. #commandOutcomes]
          label = if report ^. #dryRun then "would-run" else maybe "not-run" outcomeText outcome
       in label
            <> " checkout command ["
            <> application ^. #unApplicationId
            <> "/"
            <> commandOwner planned
            <> "]: "
            <> commandText planned
            <> "\n"
            <> maybe "" (\value -> maybe "" (\code -> "  exit " <> T.pack (show code) <> "\n") (value ^. #exitCode) <> value ^. #stdout <> value ^. #stderr) outcome
    | (application, planned) <- report ^. #commands
    ]
    <> if commandOutcomesFailed (map snd (report ^. #commandOutcomes)) then "Checkout command failed. Completed local effects remain; retry with seihou sync after correcting the failure.\n" else ""
