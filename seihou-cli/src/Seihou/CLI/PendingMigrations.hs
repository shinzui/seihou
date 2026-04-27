module Seihou.CLI.PendingMigrations
  ( detectPendingMigrations,
    formatRefusalMessage,
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
