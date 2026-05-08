module Seihou.Core.Migration
  ( -- * Author-declared migrations
    Migration (..),
    MigrationOp (..),

    -- * Migration planning
    MigrationPlan (..),
    MigrationPlanError (..),
    planMigrationChain,
  )
where

import Data.List (sortOn)
import GHC.Generics (Generic)
import Seihou.Core.Version (Version, parseVersion)
import Seihou.Prelude

-- | A single filesystem operation declared by a migration.
--
-- The variants mirror the Dhall union @schema/MigrationOp.dhall@ exactly:
--
--   * 'MoveFile'   — rename a tracked file. The migration engine rewrites
--     the manifest's @files@ map key from @src@ to @dest@.
--   * 'MoveDir'    — rename a directory. Every manifest @files@ entry whose
--     path starts with @src/@ has its key rewritten with the @dest/@ prefix.
--   * 'DeleteFile' — remove a tracked file from disk and drop it from the
--     manifest.
--   * 'DeleteDir'  — remove a directory recursively and drop every manifest
--     entry under that prefix.
--   * 'RunCommand' — execute a shell command. The manifest is not rewritten
--     by this op; if the command moves files, the migration author is
--     responsible for following it with explicit move/delete ops.
data MigrationOp
  = MoveFile {src :: FilePath, dest :: FilePath}
  | MoveDir {src :: FilePath, dest :: FilePath}
  | DeleteFile {path :: FilePath}
  | DeleteDir {path :: FilePath}
  | RunCommand {run :: Text, workDir :: Maybe FilePath}
  deriving stock (Eq, Show, Generic)

-- | A migration that moves a project from module version @from@ to module
-- version @to@. The 'ops' list is applied in declaration order.
data Migration = Migration
  { from :: Text,
    to :: Text,
    ops :: [MigrationOp]
  }
  deriving stock (Eq, Show, Generic)

-- ----------------------------------------------------------------------------
-- Pure planner — gap-tolerant version-window walker
--
-- The planner is the bridge between the unsorted list of author-declared
-- migrations on a 'Module' and the ordered sequence that the migration
-- engine actually executes. It is a pure function: no IO, no filesystem,
-- no manifest. The @moduleName@ parameter is the rendered module name
-- (a 'Text', not 'Seihou.Core.Types.ModuleName') so this module can stay
-- self-contained and avoid a circular dependency with @Types@ (which
-- imports 'Migration' for the @migrations@ field on @Module@). The CLI
-- handler unwraps the 'ModuleName' newtype before calling.
--
-- The planner's contract is simple: given an installed manifest version
-- and a target version, apply every declared migration @m@ such that
-- @installed ≤ m.from@ and @m.to ≤ target@, in ascending @from@ order,
-- advancing a cursor as you go (skipping any edge whose @from@ has
-- fallen behind the cursor). After all applicable edges have been
-- collected, the manifest's recorded version always advances to
-- @target@, even when no migration applies (a "pure version bump").
-- ----------------------------------------------------------------------------

-- | The planner result for a non-trivial @installed → target@ request.
--
-- The plan carries the module name for rendering, the start and end
-- versions of the user-visible "X → Y" header, and the ordered list of
-- migrations that will run. A plan with @planSteps == []@ means the
-- manifest will advance from @planFrom@ to @planTo@ without running
-- any migration ops (a pure version bump).
data MigrationPlan = MigrationPlan
  { planModule :: Text,
    -- | Installed (manifest) version at the start.
    planFrom :: Version,
    -- | Target version. The manifest will land here after the plan
    -- runs, regardless of whether any of the declared migrations
    -- bridge every gap inside @[planFrom, planTo]@.
    planTo :: Version,
    -- | The migrations that actually apply, in ascending @from@
    -- order. May be empty.
    planSteps :: [Migration]
  }
  deriving stock (Eq, Show, Generic)

-- | All the ways planning can fail. Each carries enough information to
-- write a useful error message at the CLI layer.
data MigrationPlanError
  = -- | A 'Migration' had a 'from' or 'to' string that didn't parse.
    -- Carries the offending string verbatim.
    MigrationVersionUnparseable Text
  | -- | Refusing to plan a downgrade. @installed → target@ where @target@
    -- compares strictly less than @installed@.
    MigrationDowngradeNotSupported Version Version
  | -- | Two migrations declare the same 'from' version, so the planner
    -- can't unambiguously pick a successor. Args: the duplicated 'from'
    -- and one of the conflicting 'to' versions.
    MigrationDuplicateEdge Version Version
  deriving stock (Eq, Show, Generic)

-- | Compute the migration plan that spans installed → target.
--
-- Returns:
--
--   * @Right Nothing@ — installed and target are equal; no work to do.
--   * @Right (Just plan)@ — the plan carries every migration whose
--     version range falls inside @[installed, target]@, plus the
--     installed and target versions for downstream rendering and
--     manifest-advance logic. The list may be empty (a pure version
--     bump where no migration applies); the manifest still advances
--     to @target@ in that case.
--   * @Left e@ — planning failed; the error variant explains why.
--     Author-side mistakes (duplicate edge, unparseable version) and
--     downgrades are still hard errors. Partial coverage is not, and
--     overshoots are silently skipped.
--
-- Algorithm: parse every declared migration's @from@/@to@ into
-- 'Version' values, reject duplicate @from@s, sort the remaining edges
-- by @from@ ascending, then walk the sorted list with a cursor. Each
-- edge is either picked (and the cursor advances to its @to@), skipped
-- because its @from@ has fallen behind the cursor (already covered by
-- an earlier picked edge), skipped because its @to@ overshoots the
-- target (the user hasn't asked to go that far), or terminates the
-- walk because its @from@ has reached or exceeded the target (no
-- subsequent edge in the sorted list can contribute either).
planMigrationChain ::
  -- | Module name (already rendered to text)
  Text ->
  -- | All declared migrations on the module
  [Migration] ->
  -- | Installed version
  Version ->
  -- | Target version
  Version ->
  Either MigrationPlanError (Maybe MigrationPlan)
planMigrationChain modName migrations installed target
  | installed == target = Right Nothing
  | target < installed =
      Left (MigrationDowngradeNotSupported installed target)
  | otherwise = do
      parsed <- traverse parseEdges migrations
      checkDuplicates parsed
      let sorted = sortOn (\(_, f, _) -> f) parsed
          steps = pickInWindow installed target sorted
      Right
        ( Just
            MigrationPlan
              { planModule = modName,
                planFrom = installed,
                planTo = target,
                planSteps = steps
              }
        )
  where
    -- Parse a migration's from/to fields into Version values.
    parseEdges m = do
      fv <- parseVersionE m.from
      tv <- parseVersionE m.to
      Right (m, fv, tv)

    parseVersionE t =
      case parseVersion t of
        Just v -> Right v
        Nothing -> Left (MigrationVersionUnparseable t)

    -- Detect two migrations declaring the same `from` version.
    checkDuplicates [] = Right ()
    checkDuplicates ((_, f, t) : rest) =
      case [t' | (_, f', t') <- rest, f' == f] of
        (t' : _) -> Left (MigrationDuplicateEdge f t')
        [] -> checkDuplicates rest

    -- Walk the sorted edge list collecting in-window migrations.
    -- The list is sorted by `from` ascending, so once an edge has
    -- `from >= end` no later edge can contribute either. An edge with
    -- `from < cursor` is already-covered (or precedes the manifest)
    -- and is skipped. An edge with `to > end` overshoots the target
    -- and is silently skipped — a future invocation with a higher
    -- target will pick it up.
    pickInWindow _cursor _end [] = []
    pickInWindow cursor end ((m, f, t) : rest)
      | f < cursor = pickInWindow cursor end rest
      | f >= end = []
      | t > end = pickInWindow cursor end rest
      | otherwise = m : pickInWindow t end rest
