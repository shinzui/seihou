module Seihou.CLI.PendingMigrations
  ( detectPendingMigrations,
    formatRefusalMessage,
  )
where

import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text qualified as T
import Seihou.CLI.Migrate (pendingChainFor)
import Seihou.Core.Migration (MigrationPlan (..))
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
-- migration plan that describes the gap. Under the gap-tolerant
-- planner the plan always advances the manifest to the supplied
-- target on apply; the carried 'planSteps' may be empty (a pure
-- version bump where no declared migration falls in the window) or
-- non-empty.
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
-- @--with-migrations@. Each row reports the module, the version range
-- the migration would cover, and how many migration ops it would run
-- (which may be zero — a pure version bump).
formatRefusalMessage :: [(ModuleName, MigrationPlan)] -> Text
formatRefusalMessage pendings =
  T.unlines $
    "Pending migrations detected:"
      : map renderEntry pendings
      ++ [ "",
           "For a recorded project application, run 'seihou update <target>'.",
           "For focused recovery, run 'seihou migrate <module>' for each, or pass --with-migrations to this explicit reconfiguration run."
         ]
  where
    renderEntry (name, plan) =
      "  "
        <> name.unModuleName
        <> ": "
        <> renderVersion plan.planFrom
        <> " -> "
        <> renderVersion plan.planTo
        <> " ("
        <> T.pack (show (length plan.planSteps))
        <> " step(s))"
