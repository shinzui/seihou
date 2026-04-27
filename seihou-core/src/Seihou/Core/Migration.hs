module Seihou.Core.Migration
  ( -- * Author-declared migrations
    Migration (..),
    MigrationOp (..),

    -- * Migration planning
    MigrationChain (..),
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
-- Pure planner
--
-- The planner is the bridge between the unsorted list of author-declared
-- migrations on a 'Module' and the contiguous chain that the migration
-- engine actually executes. It is a pure function: no IO, no filesystem,
-- no manifest. The @moduleName@ parameter is the rendered module name
-- (a 'Text', not 'Seihou.Core.Types.ModuleName') so this module can stay
-- self-contained and avoid a circular dependency with @Types@ (which
-- imports 'Migration' for the @migrations@ field on @Module@). The CLI
-- handler unwraps the 'ModuleName' newtype before calling.
-- ----------------------------------------------------------------------------

-- | A contiguous, ordered sequence of migrations that spans a known
-- installed version up to a known target version.
data MigrationChain = MigrationChain
  { migrationModule :: Text,
    chainFrom :: Version,
    chainTo :: Version,
    chainSteps :: [Migration]
  }
  deriving stock (Eq, Show, Generic)

-- | The planner result for a non-trivial @installed → target@ request.
--
-- 'planChain' is the longest reachable prefix the planner could build by
-- greedily walking declared edges starting at @installed@. If the planner
-- could not take a single step (no edge starts at @installed@), the chain
-- is empty: @chainFrom == chainTo == installed@ and @chainSteps == []@.
--
-- 'planUnreachable' is 'Nothing' when the chain reaches the requested
-- target exactly, and @Just (stuckAt, target)@ when the chain stops short
-- — either because no edge continues from @stuckAt@ or because the only
-- continuing edge would overshoot @target@.
--
-- Consumers distinguish three shapes:
--
--   * Full chain: @chainSteps@ non-empty and @planUnreachable == Nothing@.
--   * Partial chain: @chainSteps@ non-empty and @planUnreachable@ is 'Just'.
--   * Blocked: @chainSteps == []@ and @planUnreachable@ is 'Just'.
data MigrationPlan = MigrationPlan
  { planChain :: MigrationChain,
    planUnreachable :: Maybe (Version, Version)
  }
  deriving stock (Eq, Show, Generic)

-- | All the ways planning can fail. Each carries enough information to
-- write a useful error message at the CLI layer.
data MigrationPlanError
  = -- | A 'Migration' had a 'from' or 'to' string that didn't parse.
    -- Carries the offending string verbatim.
    MigrationVersionUnparseable Text
  | -- | No contiguous chain spans @installed → target@. The two arguments
    -- are the version we got stuck at, and the target we couldn't reach.
    --
    -- The planner itself no longer produces this variant — it returns the
    -- partial chain plus 'planUnreachable' instead. CLI consumers that
    -- need to fail hard (notably @seihou migrate --to TARGET@) construct
    -- this error from a 'planUnreachable' tail to preserve the existing
    -- error message.
    MigrationGap Version Version
  | -- | Refusing to plan a downgrade. @installed → target@ where @target@
    -- compares strictly less than @installed@.
    MigrationDowngradeNotSupported Version Version
  | -- | Two migrations declare the same 'from' version, so the planner
    -- can't unambiguously pick a successor. Args: the duplicated 'from'
    -- and one of the conflicting 'to' versions.
    MigrationDuplicateEdge Version Version
  | -- | A migration would step past the target (e.g. installed = 1.0.0,
    -- target = 1.5.0, available = 1.0.0 → 2.0.0). Args: the offending
    -- 'from' and the offending 'to'.
    MigrationOvershoot Version Version
  deriving stock (Eq, Show, Generic)

-- | Compute the migration plan that spans installed → target.
--
-- Returns:
--
--   * @Right Nothing@ — installed and target are equal; no work to do.
--   * @Right (Just plan)@ — the plan carries the longest reachable prefix
--     plus, if the prefix doesn't reach the target exactly, an in-band
--     description of the unreachable tail. Consumers decide whether the
--     partial coverage is fatal (e.g. @seihou migrate --to TARGET@) or
--     surfaceable as an advisory (e.g. @seihou status@,
--     @seihou migrate@ without a target).
--   * @Left e@ — planning failed; the error variant explains why.
--     Author-side mistakes (overshoot, duplicate edge, unparseable
--     version) and downgrades are still hard errors. Partial coverage is
--     not.
--
-- The chain is built greedily: starting at the installed version, the
-- planner picks the migration whose @from@ equals the current version,
-- moves to that migration's @to@, and repeats. Migrations declared with a
-- @from@ already past the target are ignored; migrations whose @to@
-- overshoots the target are rejected with 'MigrationOvershoot'.
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
      (steps, reached, mTail) <-
        walk installed target (sortOn (\(_, f, _) -> f) parsed) []
      let chain =
            MigrationChain
              { migrationModule = modName,
                chainFrom = installed,
                chainTo = reached,
                chainSteps = steps
              }
      Right
        ( Just
            MigrationPlan
              { planChain = chain,
                planUnreachable = mTail
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

    -- Greedy walk: at each step, find the migration whose `from` is the
    -- current version. If `to` exceeds the target, that's an overshoot;
    -- if no migration matches and we haven't reached the target, that's
    -- an unreachable tail (the chain so far is returned in-band).
    walk current tgt edges acc
      | current == tgt = Right (reverse acc, current, Nothing)
      | otherwise =
          case [(m, f, t) | (m, f, t) <- edges, f == current] of
            [] -> Right (reverse acc, current, Just (current, tgt))
            ((m, _f, t) : _)
              | t > tgt -> Left (MigrationOvershoot current t)
              | otherwise -> walk t tgt edges (m : acc)
