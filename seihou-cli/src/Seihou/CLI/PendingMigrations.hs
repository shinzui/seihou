module Seihou.CLI.PendingMigrations
  ( detectPendingMigrations,
    formatRefusalMessage,
    isBenignUpgrade,
  )
where

import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text qualified as T
import Seihou.CLI.Migrate (pendingChainFor)
import Seihou.Core.Migration (MigrationChain (..), MigrationPlan (..))
import Seihou.Core.Types
  ( AppliedModule (..),
    Manifest (..),
    ModuleName (..),
  )
import Seihou.Core.Version (renderVersion)
import Seihou.Dhall.Eval (evalModuleFromFile)
import Seihou.Prelude
import System.Directory (doesFileExist)

-- | Detect pending migrations across applied modules in a manifest.
--
-- For each applied module whose installed @module.dhall@ declares a
-- newer version than the manifest's recorded version, return the
-- migration plan that describes the gap. The plan's shape tells the
-- caller which user-visible row to render:
--
--   * Full chain — chain reaches the remote version exactly.
--   * Partial chain — chain reaches some intermediate version; the
--     'planUnreachable' field carries the remaining tail.
--   * Blocked — no edge starts at the manifest version; @planChain@'s
--     step list is empty and 'planUnreachable' covers the entire span.
--
-- IO failures (missing @module.dhall@, eval errors, parse failures) are
-- silently skipped: pending-migration reporting is best-effort and never
-- raises.
--
-- The optional filter restricts detection to a subset of module names.
-- 'Nothing' means "consider every applied module" (used by @seihou
-- status@). @'Just' names@ keeps only modules whose name is in the set
-- (used by @seihou run@, which only blocks when a module it is about
-- to write into has a pending plan).
detectPendingMigrations ::
  Manifest ->
  Maybe (Set ModuleName) ->
  IO [(ModuleName, MigrationPlan)]
detectPendingMigrations manifest mFilter =
  fmap
    (\xs -> [(name, p) | (name, Just p) <- xs])
    (mapM check candidates)
  where
    candidates = case mFilter of
      Nothing -> manifest.modules
      Just names -> filter (\am -> Set.member am.name names) manifest.modules

    check am = do
      let dhallFile = am.source </> "module.dhall"
      exists <- doesFileExist dhallFile
      if not exists
        then pure (am.name, Nothing)
        else do
          r <- evalModuleFromFile dhallFile
          case r of
            Left _ -> pure (am.name, Nothing)
            Right installed -> pure (am.name, pendingChainFor am installed)

-- | Format the user-facing refusal message that @seihou run@ prints
-- when it detects pending migrations and the user has not opted into
-- @--with-migrations@.
--
-- Each row's shape follows the underlying 'MigrationPlan': full
-- chains print @from -> to (N step(s))@; partial chains add the
-- unreachable-tail advisory; blocked plans print a "Blocked: no
-- migration declared from <version>" line because there is no
-- chain summary to show. The closing instructions explain both the
-- per-module @seihou migrate@ remediation and the @--with-migrations@
-- shortcut.
formatRefusalMessage :: [(ModuleName, MigrationPlan)] -> Text
formatRefusalMessage pendings =
  T.unlines $
    "Pending migrations detected:"
      : map renderEntry pendings
      ++ [ "",
           "Run 'seihou migrate <module>' for each, or pass --with-migrations to apply during this run."
         ]
  where
    renderEntry (name, plan)
      | null plan.planChain.chainSteps,
        not plan.planMigrationsDeclared,
        Just (_stuck, target) <- plan.planUnreachable =
          -- Defensive: M5 strips benign entries from the input list
          -- before calling this formatter, so this branch is normally
          -- unreachable. Keep it correct in case a future caller
          -- forwards benign entries — the language stays softened so
          -- the user never sees the EP-5 "Blocked:" wording for a
          -- benign version bump.
          "  "
            <> name.unModuleName
            <> ": "
            <> renderVersion plan.planChain.chainFrom
            <> " -> "
            <> renderVersion target
            <> " (no migrations declared; benign — would not block run)"
      | null plan.planChain.chainSteps,
        Just (stuck, target) <- plan.planUnreachable =
          "  "
            <> name.unModuleName
            <> ": Blocked: no migration declared from "
            <> renderVersion stuck
            <> "; remote is at "
            <> renderVersion target
      | otherwise =
          let chain = plan.planChain
              base =
                "  "
                  <> name.unModuleName
                  <> ": "
                  <> renderVersion chain.chainFrom
                  <> " -> "
                  <> renderVersion chain.chainTo
                  <> " ("
                  <> T.pack (show (length chain.chainSteps))
                  <> " step(s))"
           in case plan.planUnreachable of
                Nothing -> base
                Just (stuck, target) ->
                  base
                    <> "; no migration declared from "
                    <> renderVersion stuck
                    <> ", remote is at "
                    <> renderVersion target

-- | A benign upgrade is a 'MigrationPlan' that the planner produced
-- because the manifest version trails the installed copy's version,
-- but the module declared no migrations at all (@migrations = []@).
-- Callers (notably @seihou run@'s pre-flight) treat these as
-- non-blocking: the project can be re-rendered against the new
-- template content without any destructive migration ops.
isBenignUpgrade :: MigrationPlan -> Bool
isBenignUpgrade plan =
  null plan.planChain.chainSteps
    && not plan.planMigrationsDeclared
