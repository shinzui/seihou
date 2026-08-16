module Seihou.Core.Migration
  ( -- * Author-declared migrations
    Migration (..),
    MigrationOp (..),
    BlueprintMigration (..),
    EntailedEdge (..),

    -- * Migration planning
    MigrationPlan (..),
    BlueprintMigrationPlan (..),
    BlueprintMigrationStep (..),
    MigrationPlanError (..),
    planMigrationChain,
    planBlueprintMigrationChain,

    -- * Entailment expansion
    EntailmentSite (..),
    EntailmentError (..),
    expandEntailedEdges,
  )
where

import Control.Monad (foldM)
import Data.Generics.Labels ()
import Data.List (sortOn)
import Data.Set qualified as Set
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
  = MoveFile {src :: !FilePath, dest :: !FilePath}
  | MoveDir {src :: !FilePath, dest :: !FilePath}
  | DeleteFile {path :: !FilePath}
  | DeleteDir {path :: !FilePath}
  | RunCommand {run :: !Text, workDir :: !(Maybe FilePath)}
  deriving stock (Eq, Show, Generic)

-- | A migration that moves a project from module version @from@ to module
-- version @to@. The 'ops' list is applied in declaration order.
data Migration = Migration
  { from :: !Text,
    to :: !Text,
    ops :: ![MigrationOp]
  }
  deriving stock (Eq, Show, Generic)

-- | A reference from one blueprint's migration edge to an exact edge of
-- another blueprint. Resolution is by name through the same search paths
-- @seihou agent migrate@ uses; the referenced edge must exist verbatim.
--
-- This is how a breaking change that reaches consumers through an
-- intermediary library travels. A blueprint for @keiro@ — which absorbed a
-- breaking change from @kiroku@ — declares that crossing its own
-- @2.4.0 -> 3.0.0@ edge entails crossing kiroku's @1.9.0 -> 2.0.0@ edge. A
-- project that depends on keiro and has never heard of kiroku still gets
-- kiroku's upgrade guidance, in kiroku's own version space.
data EntailedEdge = EntailedEdge
  { blueprint :: !Text,
    from :: !Text,
    to :: !Text
  }
  deriving stock (Eq, Show, Generic)

-- | One agent-guided source migration declared by a blueprint. The
-- version strings use the same dotted-numeric format as module migrations,
-- while 'prompt' describes only the changes needed for this edge.
--
-- 'entails' names exact edges of other blueprints that crossing this edge
-- requires. They are expanded recursively and run before this edge; see
-- 'expandEntailedEdges'.
data BlueprintMigration = BlueprintMigration
  { from :: !Text,
    to :: !Text,
    prompt :: !Text,
    entails :: ![EntailedEdge]
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
-- migrations that will run. A plan with @steps == []@ means the
-- manifest will advance from @from@ to @to@ without running
-- any migration ops (a pure version bump).
data MigrationPlan = MigrationPlan
  { module_ :: !Text,
    -- | Installed (manifest) version at the start.
    from :: !Version,
    -- | Target version. The manifest will land here after the plan
    -- runs, regardless of whether any of the declared migrations
    -- bridge every gap inside @[from, to]@.
    to :: !Version,
    -- | The migrations that actually apply, in ascending @from@
    -- order. May be empty.
    steps :: ![Migration]
  }
  deriving stock (Eq, Show, Generic)

-- | Where an entailment declaration was written: the blueprint that owns the
-- declaring edge, and that edge's own version window.
--
-- Both 'EntailmentError' variants carry one because both are authoring
-- mistakes in that exact edge, and an error message that cannot say which
-- edge to fix is useless to the author who has to fix it.
data EntailmentSite = EntailmentSite
  { blueprint :: !Text,
    from :: !Text,
    to :: !Text
  }
  deriving stock (Eq, Show, Generic)

-- | One edge to run, together with the blueprint that declares it.
--
-- @owner@ is the name of the blueprint whose @migrations@ list contains
-- @edge@ — not the blueprint the user named on the command line. Receipts
-- are written under the owner, which is what makes a shared cohort edge the
-- same edge from either entry point.
--
-- @entailedBy@ names the edge that pulled this one in, when this step was
-- reached through entailment rather than selected directly by the version
-- window. It exists so output can say @(entailed by keiro-upgrade 2.4.0 ->
-- 3.0.0)@. It is display-only and must never enter an identity comparison:
-- the same cohort edge reached from two different declaring edges is one
-- edge, and treating the two as distinct would cross it twice.
data BlueprintMigrationStep = BlueprintMigrationStep
  { owner :: !Text,
    edge :: !BlueprintMigration,
    entailedBy :: !(Maybe EntailmentSite)
  }
  deriving stock (Eq, Show, Generic)

-- | The ordered blueprint migrations selected for a requested version
-- window. A non-trivial window may have no selected steps when the author
-- declared no agent intervention for that range.
--
-- @name@ and the version window belong to the blueprint the user invoked.
-- After 'expandEntailedEdges' has run, individual steps may be owned by other
-- blueprints and carry versions from those blueprints' version spaces; each
-- step says which blueprint it belongs to.
data BlueprintMigrationPlan = BlueprintMigrationPlan
  { name :: !Text,
    from :: !Version,
    to :: !Version,
    steps :: ![BlueprintMigrationStep]
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
planMigrationChain modName migrations installed target =
  fmap
    ( fmap
        ( \steps ->
            MigrationPlan
              { module_ = modName,
                from = installed,
                to = target,
                steps = steps
              }
        )
    )
    (planMigrationWindow (^. #from) (^. #to) migrations installed target)

-- | Compute the ordered agent-guided migrations for a blueprint and version
-- window. Selection and errors deliberately match 'planMigrationChain'.
--
-- Every selected edge is labelled with @blueprintName@, because at this point
-- every edge in the plan came out of that blueprint's own @migrations@ list.
-- Steps owned by other blueprints appear only after 'expandEntailedEdges'.
planBlueprintMigrationChain ::
  Text ->
  [BlueprintMigration] ->
  Version ->
  Version ->
  Either MigrationPlanError (Maybe BlueprintMigrationPlan)
planBlueprintMigrationChain blueprintName migrations current target =
  fmap
    ( fmap
        ( \steps ->
            BlueprintMigrationPlan
              { name = blueprintName,
                from = current,
                to = target,
                steps = map ownedBy steps
              }
        )
    )
    (planMigrationWindow (^. #from) (^. #to) migrations current target)
  where
    ownedBy selected =
      BlueprintMigrationStep
        { owner = blueprintName,
          edge = selected,
          entailedBy = Nothing
        }

-- | All the ways entailment expansion can fail. Every variant is an authoring
-- mistake in a published blueprint rather than anything the consumer running
-- the migration did, so each carries enough to name the blueprint whose author
-- has to fix it.
data EntailmentError
  = -- | An entailed blueprint could not be resolved on this machine. Carries
    -- the declaring edge and the name that did not resolve. This is a
    -- consumer-fixable situation — the blueprint is simply not installed —
    -- but seihou refuses rather than skipping, because the consumer does not
    -- know the cohort and a silently omitted member leaves a half-migrated
    -- project with no signal.
    EntailedBlueprintNotFound !EntailmentSite !Text
  | -- | The named blueprint resolved but declares no edge with that exact
    -- window. Carries the declaring edge, then the entailed blueprint's name,
    -- @from@, and @to@. Entailment names one exact edge; falling back to
    -- window planning inside the entailed blueprint would let a release
    -- silently change which upstream work it implies.
    EntailedEdgeNotDeclared !EntailmentSite !Text !Text !Text
  | -- | Entailment forms a cycle. Carries the chain in order, each element
    -- rendered as @blueprint from -> to@, beginning and ending with the edge
    -- that closed it.
    EntailmentCycle ![Text]
  deriving stock (Eq, Show, Generic)

-- | Expand each selected edge into its entailed edges followed by itself,
-- recursively, in declaration order.
--
-- @lookupMigrations@ answers "what edges does this blueprint declare?" and
-- returns 'Nothing' for a blueprint that could not be resolved. Keeping it a
-- parameter is what lets this function stay pure: discovery is the CLI's job.
--
-- Ordering: an entailed edge runs /before/ the edge that declares it, and
-- several entailed edges run in declaration order. The entailed edge is the
-- deeper change — kiroku's API — and the declaring edge's own guidance may
-- assume it has already been applied.
--
-- Deduplication: an edge already emitted is not emitted again, no matter how
-- many selected edges entail it. Identity is the triple @(owner, from, to)@,
-- which deliberately ignores @entailedBy@: the same cohort edge reached from
-- two declaring edges is one piece of work. This is expansion-time
-- deduplication only; dropping edges this project has already recorded
-- receipts for happens afterwards and separately.
--
-- Cycles are a hard error rather than a silently broken chain, because a
-- cycle means two blueprints each claim the other's edge must run first and
-- there is no order that satisfies both.
expandEntailedEdges ::
  (Text -> Maybe [BlueprintMigration]) ->
  [BlueprintMigrationStep] ->
  Either EntailmentError [BlueprintMigrationStep]
expandEntailedEdges lookupMigrations topSteps = do
  (expanded, _visited) <- foldM (expandStep []) ([], Set.empty) topSteps
  Right expanded
  where
    -- @path@ is the chain of edges currently being expanded, oldest first.
    -- @emitted@ is the output so far, in final order. @visited@ is every
    -- edge already emitted, so a second reference to it is dropped.
    expandStep path (emitted, visited) step
      | stepKey `Set.member` visited = Right (emitted, visited)
      | stepKey `elem` path = Left (EntailmentCycle (renderCycle path stepKey))
      | otherwise = do
          entailedSteps <- traverse (resolveEntailed step) (step ^. #edge . #entails)
          (emitted', visited') <-
            foldM (expandStep (path <> [stepKey])) (emitted, visited) entailedSteps
          Right (emitted' <> [step], Set.insert stepKey visited')
      where
        stepKey = edgeKey step

    resolveEntailed declaringStep entailed =
      case lookupMigrations (entailed ^. #blueprint) of
        Nothing -> Left (EntailedBlueprintNotFound site (entailed ^. #blueprint))
        Just declared ->
          case [ candidate
               | candidate <- declared,
                 candidate ^. #from == entailed ^. #from,
                 candidate ^. #to == entailed ^. #to
               ] of
            (matched : _) ->
              Right
                BlueprintMigrationStep
                  { owner = entailed ^. #blueprint,
                    edge = matched,
                    entailedBy = Just site
                  }
            [] ->
              Left
                ( EntailedEdgeNotDeclared
                    site
                    (entailed ^. #blueprint)
                    (entailed ^. #from)
                    (entailed ^. #to)
                )
      where
        site =
          EntailmentSite
            { blueprint = declaringStep ^. #owner,
              from = declaringStep ^. #edge . #from,
              to = declaringStep ^. #edge . #to
            }

    edgeKey step = (step ^. #owner, step ^. #edge . #from, step ^. #edge . #to)

    -- The cycle a reader wants to see starts where the repeat began, not at
    -- whichever top-level edge happened to lead there.
    renderCycle path repeated =
      map renderKey (dropWhile (/= repeated) path <> [repeated])

    renderKey (owner, fromVersion, toVersion) =
      owner <> " " <> fromVersion <> " -> " <> toVersion

-- | Shared gap-tolerant version-window planner. Keeping parsing, duplicate
-- detection, ordering, overlap handling, and overshoot handling here prevents
-- module and blueprint migrations from developing subtly different rules.
planMigrationWindow ::
  (a -> Text) ->
  (a -> Text) ->
  [a] ->
  Version ->
  Version ->
  Either MigrationPlanError (Maybe [a])
planMigrationWindow getFrom getTo migrations current target
  | current == target = Right Nothing
  | target < current = Left (MigrationDowngradeNotSupported current target)
  | otherwise = do
      parsed <- traverse parseEdge migrations
      checkDuplicates parsed
      let sorted = sortOn (\(_, f, _) -> f) parsed
      Right (Just (pickInWindow current target sorted))
  where
    parseEdge migration = do
      fromVersion <- parseVersionE (getFrom migration)
      toVersion <- parseVersionE (getTo migration)
      Right (migration, fromVersion, toVersion)

    parseVersionE versionText =
      case parseVersion versionText of
        Just version -> Right version
        Nothing -> Left (MigrationVersionUnparseable versionText)

    checkDuplicates [] = Right ()
    checkDuplicates ((_, fromVersion, _) : rest) =
      case [toVersion | (_, duplicateFrom, toVersion) <- rest, duplicateFrom == fromVersion] of
        (duplicateTo : _) -> Left (MigrationDuplicateEdge fromVersion duplicateTo)
        [] -> checkDuplicates rest

    pickInWindow _cursor _end [] = []
    pickInWindow cursor end ((migration, fromVersion, toVersion) : rest)
      | fromVersion < cursor = pickInWindow cursor end rest
      | fromVersion >= end = []
      | toVersion > end = pickInWindow cursor end rest
      | otherwise = migration : pickInWindow toVersion end rest
