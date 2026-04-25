module Seihou.Core.Migration
  ( -- * Author-declared migrations
    Migration (..),
    MigrationOp (..),

    -- * Migration planning
    MigrationChain (..),
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

-- | All the ways planning can fail. Each carries enough information to
-- write a useful error message at the CLI layer.
data MigrationPlanError
  = -- | A 'Migration' had a 'from' or 'to' string that didn't parse.
    -- Carries the offending string verbatim.
    MigrationVersionUnparseable Text
  | -- | No contiguous chain spans @installed → target@. The two arguments
    -- are the version we got stuck at, and the target we couldn't reach.
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

-- | Compute the migration chain that spans installed → target.
--
-- Returns:
--
--   * @Right Nothing@ — installed and target are equal; no work to do.
--   * @Right (Just chain)@ — the contiguous, in-order chain that lands on
--     the target.
--   * @Left e@ — planning failed; the error variant explains why.
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
  Either MigrationPlanError (Maybe MigrationChain)
planMigrationChain modName migrations installed target
  | installed == target = Right Nothing
  | target < installed =
      Left (MigrationDowngradeNotSupported installed target)
  | otherwise = do
      parsed <- traverse parseEdges migrations
      checkDuplicates parsed
      steps <- walk installed target (sortOn (\(_, f, _) -> f) parsed) []
      Right
        ( Just
            MigrationChain
              { migrationModule = modName,
                chainFrom = installed,
                chainTo = target,
                chainSteps = steps
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
    -- a gap.
    walk current tgt edges acc
      | current == tgt = Right (reverse acc)
      | otherwise =
          case [(m, f, t) | (m, f, t) <- edges, f == current] of
            [] -> Left (MigrationGap current tgt)
            ((m, _f, t) : _)
              | t > tgt -> Left (MigrationOvershoot current t)
              | otherwise -> walk t tgt edges (m : acc)
