module Seihou.Engine.Conflict
  ( resolveConflicts,
    resolveConflictsInteractive,
  )
where

import Data.Text qualified as T
import Seihou.Core.Types (ConflictFile (..), ConflictResolution (..))
import Seihou.Effect.Console (Console, getLine, isInteractive, putText)
import Seihou.Prelude
import Prelude hiding (getLine)

-- | Resolve a list of conflicts, returning per-file resolutions.
--
-- Returns 'Just' with the list of resolutions when all conflicts are handled,
-- or 'Nothing' when the run should abort (non-interactive without force, or
-- user chose Abort).
--
-- Behavior:
--   * Empty conflict list → @Just []@.
--   * @force = True@ → all conflicts resolved as 'AcceptNew'.
--   * Non-interactive terminal → 'Nothing' (caller should print errors and exit).
--   * Interactive terminal → prompts user for each file via 'resolveConflictsInteractive'.
resolveConflicts ::
  (Console :> es) =>
  Bool ->
  [ConflictFile] ->
  Eff es (Maybe [(ConflictFile, ConflictResolution)])
resolveConflicts _ [] = pure (Just [])
resolveConflicts force conflicts
  | force = pure (Just (map (\c -> (c, AcceptNew)) conflicts))
  | otherwise = do
      interactive <- isInteractive
      if interactive
        then resolveConflictsInteractive conflicts
        else pure Nothing

-- | Interactively prompt for each conflicted file.
--
-- For each conflict, displays the file path and offers four choices:
-- accept (overwrite), keep (preserve disk copy), skip (leave untouched),
-- or abort (stop the entire run).
--
-- Returns 'Nothing' if the user chooses Abort on any file.
resolveConflictsInteractive ::
  (Console :> es) =>
  [ConflictFile] ->
  Eff es (Maybe [(ConflictFile, ConflictResolution)])
resolveConflictsInteractive = go []
  where
    go acc [] = pure (Just (reverse acc))
    go acc (c : cs) = do
      resolution <- promptConflict c
      case resolution of
        Abort -> pure Nothing
        _ -> go ((c, resolution) : acc) cs

-- | Prompt the user for a single conflict, re-prompting on invalid input.
promptConflict ::
  (Console :> es) =>
  ConflictFile ->
  Eff es ConflictResolution
promptConflict c = do
  putText $ "Conflict: " <> T.pack c.path <> " (modified since last generation)"
  promptChoice
  where
    promptChoice = do
      putText "  [a]ccept new  [k]eep current  [s]kip  [A]bort all"
      input <- getLine
      case parseChoice (T.strip input) of
        Just res -> pure res
        Nothing -> do
          putText "Invalid choice, try again."
          promptChoice

-- | Parse user input into a ConflictResolution.
parseChoice :: T.Text -> Maybe ConflictResolution
parseChoice "a" = Just AcceptNew
parseChoice "accept" = Just AcceptNew
parseChoice "k" = Just KeepCurrent
parseChoice "keep" = Just KeepCurrent
parseChoice "s" = Just Skip
parseChoice "skip" = Just Skip
parseChoice "A" = Just Abort
parseChoice "abort" = Just Abort
parseChoice _ = Nothing
