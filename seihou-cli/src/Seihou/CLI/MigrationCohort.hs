-- | Resolving the set of blueprints one @seihou agent migrate@ run needs.
--
-- A blueprint migration edge may declare that crossing it entails crossing an
-- exact edge of another blueprint — that is how a breaking change reaches
-- consumers who depend on the library that absorbed it rather than on the
-- library that shipped it. The set of blueprints reached that way is a
-- /cohort/. It is not an artifact and is recorded nowhere: it is recomputed
-- from declarations on every run, per
-- docs\/adr\/0004-the-manifest-is-the-only-record-of-applied-state.md.
--
-- This module is the filesystem half of that. It resolves blueprints by name
-- through the same search paths the command uses for the blueprint the user
-- typed, validates each one, and classifies each into a portable
-- 'ArtifactOrigin' so its receipts can be keyed by identity rather than by
-- name. The pure half — turning declarations into an ordered list of steps —
-- is 'Seihou.Core.Migration.expandEntailedEdges', which takes what this module
-- found as a lookup function.
module Seihou.CLI.MigrationCohort
  ( CohortBlueprint (..),
    CohortResolutionError (..),
    resolveCohortBlueprint,
    resolveMigrationCohort,
  )
where

import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Seihou.Core.ArtifactOriginDetect (detectArtifactOrigin)
import Seihou.Core.Blueprint (validateBlueprint)
import Seihou.Core.Migration
  ( BlueprintMigration (..),
    BlueprintMigrationStep (..),
    EntailedEdge (..),
  )
import Seihou.Core.Module (discoverRunnable)
import Seihou.Core.Types
  ( ArtifactOrigin,
    Blueprint (..),
    ModuleLoadError (..),
    ModuleName (..),
    Runnable (..),
  )
import Seihou.Prelude

-- | One blueprint this run needs, with everything the run needs to know about
-- it: its declarations, where it lives on disk (so its @files\/@ directory can
-- be mounted for its own steps), and the portable identity its receipts are
-- keyed by.
data CohortBlueprint = CohortBlueprint
  { blueprint :: !Blueprint,
    blueprintDir :: !FilePath,
    origin :: !ArtifactOrigin
  }
  deriving stock (Generic)

-- | Why a named blueprint could not be turned into a 'CohortBlueprint'.
--
-- 'CohortArtifactMissing' is deliberately separate from the other two. A
-- blueprint that is simply not installed is reported by the /expander/, which
-- knows which edge named it and can therefore say what to install and why;
-- resolution just hands the absence back. The other two are genuine problems
-- with an artifact that /is/ present, and stop the command wherever they are
-- found.
data CohortResolutionError
  = -- | The name resolved to something other than a blueprint. Carries the
    -- name and the kind word for the message ("module", "recipe", "prompt").
    CohortArtifactWrongKind !ModuleName !Text
  | -- | Nothing of that name is installed. Carries the name and the
    -- directories searched.
    CohortArtifactMissing !ModuleName ![FilePath]
  | -- | Found, but it could not be evaluated, decoded, or validated.
    CohortArtifactUnusable !ModuleLoadError
  deriving stock (Eq, Show, Generic)

-- | Resolve one blueprint by name: discover it, refuse a same-named artifact
-- of another kind, validate it, and classify its directory into an origin.
--
-- @projectRoot@ is the working directory the command was invoked in; it is
-- what makes a local origin's recorded path relative to the project rather
-- than to the machine, per
-- docs\/adr\/0001-manifest-is-a-checked-in-machine-independent-artifact.md.
resolveCohortBlueprint ::
  -- | project root, for classifying a local blueprint's path
  FilePath ->
  -- | module search paths
  [FilePath] ->
  ModuleName ->
  IO (Either CohortResolutionError CohortBlueprint)
resolveCohortBlueprint projectRoot searchPaths requestedName = do
  runnableResult <- discoverRunnable searchPaths requestedName
  case runnableResult of
    Left (ModuleNotFound name searched) -> pure (Left (CohortArtifactMissing name searched))
    Left err -> pure (Left (CohortArtifactUnusable err))
    Right (RunnableModule _ _) -> pure (Left (CohortArtifactWrongKind requestedName "module"))
    Right (RunnableRecipe _ _) -> pure (Left (CohortArtifactWrongKind requestedName "recipe"))
    Right (RunnableAgentPrompt _ _) -> pure (Left (CohortArtifactWrongKind requestedName "prompt"))
    Right (RunnableBlueprint discovered dir) -> do
      validationResult <- validateBlueprint dir discovered
      case validationResult of
        Left err -> pure (Left (CohortArtifactUnusable err))
        Right validated -> do
          detected <- detectArtifactOrigin projectRoot dir
          pure $
            Right
              CohortBlueprint
                { blueprint = validated,
                  blueprintDir = dir,
                  origin = detected
                }

-- | Load every blueprint reachable by entailment from a planned window, on top
-- of the blueprints already loaded.
--
-- The walk follows /exact edges/ rather than whole blueprints: a reference
-- names one edge, so only that edge's own @entails@ list is followed onward.
-- Loading everything a newly discovered blueprint mentions anywhere would make
-- an unrelated, uninstalled member of some other chain fail a run that never
-- needed it.
--
-- Termination does not depend on the declarations being acyclic. Every
-- reference is expanded at most once, tracked by its @(blueprint, from, to)@
-- triple, so a cycle here simply stops; /reporting/ the cycle is
-- 'Seihou.Core.Migration.expandEntailedEdges''s job, which has the ordering
-- context to name it.
--
-- A blueprint that is not installed is left out of the returned map rather
-- than raised here, so the expander can report it against the edge that named
-- it.
resolveMigrationCohort ::
  -- | project root, for classifying a local blueprint's path
  FilePath ->
  -- | module search paths
  [FilePath] ->
  -- | blueprints already loaded, keyed by name (at least the invoked one)
  Map Text CohortBlueprint ->
  -- | the window-selected steps whose entailments to follow
  [BlueprintMigrationStep] ->
  IO (Either CohortResolutionError (Map Text CohortBlueprint))
resolveMigrationCohort projectRoot searchPaths initial steps =
  walk initial Set.empty (concatMap (\step -> step ^. #edge . #entails) steps)
  where
    walk loaded _seen [] = pure (Right loaded)
    walk loaded seen (reference : rest)
      | referenceKey reference `Set.member` seen = walk loaded seen rest
      | otherwise =
          case Map.lookup (reference ^. #blueprint) loaded of
            Just already -> walk loaded seen' (rest <> onward already reference)
            Nothing -> do
              result <-
                resolveCohortBlueprint
                  projectRoot
                  searchPaths
                  (ModuleName (reference ^. #blueprint))
              case result of
                Left (CohortArtifactMissing _ _) -> walk loaded seen' rest
                Left err -> pure (Left err)
                Right resolved ->
                  walk
                    (Map.insert (reference ^. #blueprint) resolved loaded)
                    seen'
                    (rest <> onward resolved reference)
      where
        seen' = Set.insert (referenceKey reference) seen

    -- What the named edge itself entails. An empty result also covers the
    -- case where the blueprint declares no such edge at all, which the
    -- expander reports against the edge that named it.
    onward resolved reference =
      concat
        [ declared ^. #entails
        | declared <- resolved ^. #blueprint . #migrations,
          declared ^. #from == reference ^. #from,
          declared ^. #to == reference ^. #to
        ]

    referenceKey reference =
      (reference ^. #blueprint, reference ^. #from, reference ^. #to)
