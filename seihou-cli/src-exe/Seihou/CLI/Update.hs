module Seihou.CLI.Update
  ( handleUpdate,
  )
where

import Control.Monad (unless, when)
import Data.Aeson (encode, object, (.=))
import Data.ByteString.Lazy.Char8 qualified as LBS
import Data.Maybe (isJust)
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.CommandExecution (CommandPolicy (..))
import Seihou.CLI.Commands (UpdateOpts (..))
import Seihou.CLI.CommitMessage (generateCommitMessage)
import Seihou.CLI.Git (gitAdd, gitCheckIgnore, gitCommit, gitDiffCached, isGitRepo)
import Seihou.CLI.Style (useColor)
import Seihou.CLI.Update.Interaction
  ( InteractionError (..),
    InteractionMode (..),
    forceResolveUpdatePlan,
    resolveInteractively,
  )
import Seihou.CLI.Update.Render
  ( encodeUpdateOutput,
    errorOutput,
    planOutput,
    renderUpdateHuman,
    resultOutput,
  )
import Seihou.Core.Types (ModuleName (..))
import Seihou.Effect.ProcessInterp (runProcessIO)
import Seihou.Prelude
import System.Exit (ExitCode (..), exitFailure)
import System.FilePath (isAbsolute)
import System.IO (hFlush, hIsTerminalDevice, isEOF, stderr, stdin)
import "seihou-cli" Seihou.CLI.Update qualified as Service

handleUpdate :: UpdateOpts -> IO ()
handleUpdate opts = do
  validateOptions opts
  terminal <- hIsTerminalDevice stdin
  let request = requestFromOptions terminal opts
  Service.withProjectUpdate request (handlePlanned terminal opts)

validateOptions :: UpdateOpts -> IO ()
validateOptions opts
  | opts.updateDryRun && (opts.updateCommit || isJust opts.updateCommitMessage) =
      failCli opts "invalid_options" "--commit and --commit-message cannot be used with --dry-run"
  | opts.updateRunAllCommands && opts.updateNoCommands =
      failCli opts "invalid_options" "--run-all-commands and --no-commands are mutually exclusive"
  | otherwise = pure ()

requestFromOptions :: Bool -> UpdateOpts -> Service.UpdateRequest
requestFromOptions terminal opts =
  Service.UpdateRequest
    { selection =
        if null opts.updateTargets
          then Service.AllRecordedApplications
          else Service.NamedUpdateTargets opts.updateTargets,
      varOverrides = opts.updateVars,
      reconfigure = opts.updateReconfigure,
      promptPolicy =
        if terminal && not opts.updateJson
          then Service.AllowPrompts
          else Service.ForbidPrompts,
      commandPolicy =
        if opts.updateRunAllCommands
          then RunAllCommands
          else if opts.updateNoCommands then DisableCommands else RunChangedCommands,
      dryRun = opts.updateDryRun
    }

handlePlanned :: Bool -> UpdateOpts -> Either Service.UpdateError Service.UpdatePlan -> IO ()
handlePlanned _ opts (Left err) = do
  if opts.updateJson
    then LBS.putStrLn (encodeUpdateOutput (errorOutput err))
    else TIO.hPutStr stderr (renderUpdateHuman False (errorOutput err))
  exitFailure
handlePlanned terminal opts (Right originalPlan) = do
  forced <-
    if opts.updateForce
      then either (failInteraction opts) pure (forceResolveUpdatePlan originalPlan)
      else pure originalPlan
  resolved <-
    resolveInteractively
      (if terminal && not opts.updateJson then Interactive else NonInteractive)
      forced
      >>= either (failInteraction opts) pure
  color <- useColor
  if Service.isUpdateNoOp resolved
    then
      if opts.updateJson
        then LBS.putStrLn (encodeUpdateOutput (planOutput resolved))
        else TIO.putStrLn "Already up to date."
    else
      if opts.updateDryRun
        then emitPlan color opts resolved
        else do
          unless opts.updateJson $ TIO.putStr (renderUpdateHuman color (planOutput resolved))
          accepted <- if opts.updateJson then pure True else confirmApply terminal
          if not accepted
            then TIO.hPutStrLn stderr "Update cancelled; no managed state was changed."
            else do
              applied <- Service.applyProjectUpdate resolved
              case applied of
                Left err -> handlePlanned terminal opts (Left err)
                Right result -> do
                  if opts.updateJson
                    then LBS.putStrLn (encodeUpdateOutput (resultOutput result))
                    else TIO.putStr (renderUpdateHuman color (resultOutput result))
                  when (opts.updateCommit || isJust opts.updateCommitMessage) $ do
                    committed <- commitUpdate opts result
                    case committed of
                      Left err -> do
                        TIO.hPutStrLn stderr ("Update succeeded, but git commit failed: " <> err)
                        exitFailure
                      Right () -> pure ()

emitPlan :: Bool -> UpdateOpts -> Service.UpdatePlan -> IO ()
emitPlan color opts plan =
  if opts.updateJson
    then LBS.putStrLn (encodeUpdateOutput (planOutput plan))
    else TIO.putStr (renderUpdateHuman color (planOutput plan))

confirmApply :: Bool -> IO Bool
confirmApply False = pure False
confirmApply True = loop
  where
    loop = do
      TIO.hPutStr stderr "Apply? [Y/n] "
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
            _ -> do
              TIO.hPutStrLn stderr "Please answer yes or no."
              loop

commitUpdate :: UpdateOpts -> Service.UpdateResult -> IO (Either Text ())
commitUpdate opts result = do
  let candidates = filter (not . isAbsolute) (Set.toAscList result.touchedPaths)
  inRepo <- runEff $ runProcessIO isGitRepo
  if not inRepo
    then pure (Right ())
    else do
      ignored <- runEff $ runProcessIO $ gitCheckIgnore candidates
      let staged = filter (`notElem` ignored) candidates
      if null staged
        then pure (Right ())
        else do
          (addExit, _, addErr) <- runEff $ runProcessIO $ gitAdd staged
          case addExit of
            ExitFailure _ -> pure (Left (T.strip addErr))
            ExitSuccess -> do
              message <- case opts.updateCommitMessage of
                Just custom -> pure custom
                Nothing -> do
                  diff <- runEff $ runProcessIO gitDiffCached
                  let modules = map (ModuleName . (.name)) result.versions
                  generateCommitMessage modules diff
              (commitExit, _, commitErr) <- runEff $ runProcessIO $ gitCommit message
              pure $ case commitExit of
                ExitSuccess -> Right ()
                ExitFailure _ -> Left (T.strip commitErr)

failInteraction :: UpdateOpts -> InteractionError -> IO a
failInteraction opts err = case err of
  InteractionRequired paths ->
    failCli
      opts
      "unresolved_conflicts"
      ( "Unresolved paths require an interactive terminal or an applicable --force choice: "
          <> T.intercalate ", " (map T.pack (Set.toAscList paths))
      )
  InteractionAborted path ->
    failCli opts "update_aborted" ("Resolution aborted for " <> T.pack path)
  InteractionResolutionFailed inner ->
    failCli opts "resolution_failed" (T.pack (show inner))
  InteractionInputFailed message ->
    failCli opts "input_failed" message

failCli :: UpdateOpts -> Text -> Text -> IO a
failCli opts code message = do
  if opts.updateJson
    then
      LBS.putStrLn $
        encode $
          object
            [ "schemaVersion" .= (1 :: Int),
              "outcome" .= ("error" :: Text),
              "error" .= object ["code" .= code, "message" .= message]
            ]
    else TIO.hPutStrLn stderr ("Update failed [" <> code <> "]: " <> message)
  exitFailure
