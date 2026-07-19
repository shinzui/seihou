module Seihou.CLI.Update.Interaction
  ( InteractionMode (..),
    InteractionError (..),
    ResolutionDecision (..),
    applyResolutionDecisions,
    forceResolveUpdatePlan,
    resolveInteractively,
  )
where

import Control.Exception (IOException, try)
import Control.Monad (foldM)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Update.Types (UpdatePlan (..))
import Seihou.Engine.Reconcile
  ( FileConflictChoice (..),
    FileReconciliation (..),
    OrphanChoice (..),
    ReconciliationError,
    ReconciliationPlan (..),
    ReconciliationReason (..),
    resolveEditedOrphan,
    resolveFileConflict,
    unresolvedPaths,
  )
import Seihou.Prelude
import System.IO (hFlush, isEOF, stderr, stdin)

data InteractionMode = Interactive | NonInteractive
  deriving stock (Eq, Show)

data InteractionError
  = InteractionRequired (Set FilePath)
  | InteractionAborted FilePath
  | InteractionResolutionFailed ReconciliationError
  | InteractionInputFailed Text
  deriving stock (Eq, Show)

data ResolutionDecision
  = ResolveFile FilePath FileConflictChoice
  | ResolveOrphan FilePath OrphanChoice
  deriving stock (Eq, Show)

applyResolutionDecisions ::
  [ResolutionDecision] ->
  UpdatePlan ->
  Either InteractionError UpdatePlan
applyResolutionDecisions decisions plan = do
  reconciliation <- foldM applyOne plan.reconciliation decisions
  pure plan {reconciliation}
  where
    applyOne current (ResolveFile path choice) =
      first InteractionResolutionFailed (resolveFileConflict path choice current)
    applyOne current (ResolveOrphan path choice) =
      first InteractionResolutionFailed (resolveEditedOrphan path choice current)

forceResolveUpdatePlan :: UpdatePlan -> Either InteractionError UpdatePlan
forceResolveUpdatePlan plan = applyResolutionDecisions decisions plan
  where
    decisions = concatMap forceOne (Map.toAscList plan.reconciliation.files)
    forceOne (path, FileConflict _ _ _ reason _ _ Nothing) = case reason of
      MergeDriverUnavailable _ -> []
      _ -> [ResolveFile path AcceptGenerated]
    forceOne (path, FileOrphanEdited _ _ _ _ Nothing) =
      [ResolveOrphan path RetainTrackedOrphan]
    forceOne _ = []

resolveInteractively ::
  InteractionMode ->
  UpdatePlan ->
  IO (Either InteractionError UpdatePlan)
resolveInteractively mode plan
  | Set.null remaining = pure (Right plan)
  | mode == NonInteractive = pure (Left (InteractionRequired remaining))
  | otherwise = go plan (Map.toAscList plan.reconciliation.files)
  where
    remaining = unresolvedPaths plan.reconciliation
    go current [] = pure (Right current)
    go current ((path, reconciliation) : rest) = case reconciliation of
      FileConflict _ currentText markers reason _ _ Nothing -> do
        decision <- promptConflict path currentText markers reason
        case decision of
          Left err -> pure (Left err)
          Right choice -> case applyResolutionDecisions [ResolveFile path choice] current of
            Left err -> pure (Left err)
            Right updated -> go updated rest
      FileOrphanEdited _ _ content _ Nothing -> do
        decision <- promptOrphan path content
        case decision of
          Left err -> pure (Left err)
          Right choice -> case applyResolutionDecisions [ResolveOrphan path choice] current of
            Left err -> pure (Left err)
            Right updated -> go updated rest
      _ -> go current rest

promptConflict ::
  FilePath ->
  Text ->
  Text ->
  ReconciliationReason ->
  IO (Either InteractionError FileConflictChoice)
promptConflict path current markers reason = do
  TIO.hPutStrLn stderr ("Conflict: " <> T.pack path <> " (" <> T.pack (show reason) <> ")")
  TIO.hPutStrLn stderr "  Labels: baseline = previous generated, current = project, generated = candidate"
  TIO.hPutStrLn stderr "  Diff3 preview:"
  TIO.hPutStrLn stderr (indentPreview (if T.null markers then current else markers))
  promptChoice path "Choose [g]enerated, [k]eep current, [m]arkers, [a]bort: " parse
  where
    parse "g" = Just AcceptGenerated
    parse "generated" = Just AcceptGenerated
    parse "k" = Just KeepCurrent
    parse "keep" = Just KeepCurrent
    parse "m" = Just WriteConflictMarkers
    parse "markers" = Just WriteConflictMarkers
    parse "a" = Nothing
    parse "abort" = Nothing
    parse _ = Nothing

promptOrphan :: FilePath -> Text -> IO (Either InteractionError OrphanChoice)
promptOrphan path content = do
  TIO.hPutStrLn stderr ("Edited orphan: " <> T.pack path)
  TIO.hPutStrLn stderr (indentPreview content)
  promptChoice path "Choose [d]elete, [r]etain tracked, [u]nmanage and keep, [a]bort: " parse
  where
    parse "d" = Just DeleteEditedOrphan
    parse "delete" = Just DeleteEditedOrphan
    parse "r" = Just RetainTrackedOrphan
    parse "retain" = Just RetainTrackedOrphan
    parse "u" = Just DetachAndKeepOrphan
    parse "unmanage" = Just DetachAndKeepOrphan
    parse "a" = Nothing
    parse "abort" = Nothing
    parse _ = Nothing

promptChoice ::
  FilePath ->
  Text ->
  (Text -> Maybe a) ->
  IO (Either InteractionError a)
promptChoice path prompt parse = loop
  where
    loop = do
      TIO.hPutStr stderr prompt
      hFlush stderr
      eofResult <- try @IOException isEOF
      case eofResult of
        Left err -> pure (Left (InteractionInputFailed (T.pack (show err))))
        Right True -> pure (Left (InteractionAborted path))
        Right False -> do
          inputResult <- try @IOException TIO.getLine
          case inputResult of
            Left err -> pure (Left (InteractionInputFailed (T.pack (show err))))
            Right input ->
              let normalized = T.toLower (T.strip input)
               in if normalized `elem` ["a", "abort"]
                    then pure (Left (InteractionAborted path))
                    else case parse normalized of
                      Just choice -> pure (Right choice)
                      _ -> do
                        TIO.hPutStrLn stderr "Invalid choice; enter one of the displayed letters or words."
                        loop

indentPreview :: Text -> Text
indentPreview content =
  let shownLines = take 80 (T.lines content)
      suffix = if length (T.lines content) > 80 then ["  ... preview truncated ..."] else []
   in T.unlines (map ("  " <>) shownLines <> suffix)
