module Seihou.CLI.Update.Types
  ( UpdateSelection (..),
    PromptPolicy (..),
    UpdateRequest (..),
    VersionChange (..),
    InputChangeSummary (..),
    CandidateArtifactKind (..),
    CandidateArtifact (..),
    CandidateCatalog (..),
    PlannedUpdateMigration (..),
    PlannedApplication (..),
    UpdateSnapshot (..),
    UpdateWarning (..),
    UpdatePlan (..),
    CommandSummary (..),
    UpdateResult (..),
    UpdateError (..),
  )
where

import Data.Map.Strict (Map)
import Data.Set (Set)
import Seihou.CLI.CommandExecution
  ( CommandExecutionError,
    CommandPlan,
    CommandPolicy,
  )
import Seihou.Composition.Instance (ModuleInstance)
import Seihou.Core.Migration (MigrationPlan, MigrationPlanError)
import Seihou.Core.Types
import Seihou.Engine.Migrate (ExecutedMigrationPlan, MigrationExecError)
import Seihou.Engine.Reconcile
  ( DesiredFileOwner,
    ReconciliationError,
    ReconciliationPlan,
    ReconciliationSummary,
  )
import Seihou.Engine.UpdateTransaction (TransactionError)
import Seihou.Prelude

data UpdateSelection
  = AllRecordedApplications
  | NamedUpdateTargets [Text]
  deriving stock (Eq, Show)

data PromptPolicy
  = AllowPrompts
  | ForbidPrompts
  deriving stock (Eq, Show)

data UpdateRequest = UpdateRequest
  { selection :: UpdateSelection,
    varOverrides :: [(Text, Text)],
    reconfigure :: Bool,
    promptPolicy :: PromptPolicy,
    commandPolicy :: CommandPolicy,
    dryRun :: Bool
  }
  deriving stock (Eq, Show)

data VersionChange = VersionChange
  { name :: Text,
    fromVersion :: Maybe Text,
    toVersion :: Maybe Text,
    sameVersionContentChanged :: Bool
  }
  deriving stock (Eq, Show)

data InputChangeSummary = InputChangeSummary
  { reused :: Int,
    overridden :: Int,
    newlyResolved :: Int,
    removed :: Int,
    ambiguousLegacy :: [VarName]
  }
  deriving stock (Eq, Show)

data CandidateArtifactKind = CandidateModule | CandidateRecipe
  deriving stock (Eq, Ord, Show)

-- | One validated artifact staged for this update session. The source path is
-- temporary for remote candidates and must not escape 'withProjectUpdate'.
data CandidateArtifact = CandidateArtifact
  { kind :: CandidateArtifactKind,
    name :: Text,
    version :: Maybe Text,
    originalDirectory :: FilePath,
    sourceDirectory :: FilePath,
    sourceUrl :: Maybe Text,
    repoName :: Maybe Text,
    tags :: [Text],
    sourceRevision :: Maybe Text,
    contentHash :: SHA256,
    moduleDefinition :: Maybe Module,
    recipeDefinition :: Maybe Recipe
  }
  deriving stock (Eq, Show)

data CandidateCatalog = CandidateCatalog
  { searchRoot :: FilePath,
    artifacts :: Map (CandidateArtifactKind, Text) CandidateArtifact,
    clonedOrigins :: Map Text FilePath
  }
  deriving stock (Eq, Show)

data PlannedUpdateMigration = PlannedUpdateMigration
  { moduleName :: ModuleName,
    sourceDirectory :: FilePath,
    sourcePlan :: MigrationPlan,
    stagedPlan :: ExecutedMigrationPlan,
    containsCommands :: Bool
  }
  deriving stock (Eq, Show)

-- | Internal, renderer-neutral material retained so apply can re-plan after
-- migration commands without reusing parser state.
data PlannedApplication = PlannedApplication
  { previous :: Maybe AppliedComposition,
    candidate :: AppliedComposition,
    modulesInOrder :: [(ModuleInstance, Module, FilePath)],
    resolvedValues :: Map ModuleInstance (Map VarName ResolvedVar),
    operations :: [Operation],
    desiredOwners :: Map FilePath DesiredFileOwner
  }
  deriving stock (Eq, Show)

data UpdateSnapshot = UpdateSnapshot
  { sessionDirectory :: FilePath,
    projectRoot :: FilePath,
    manifestPath :: FilePath,
    baselineDirectory :: FilePath,
    installedDirectory :: FilePath,
    originalManifest :: Manifest,
    candidateHashes :: Map FilePath SHA256,
    observedProjectHashes :: Map FilePath (Maybe SHA256),
    transactionTargets :: Set FilePath
  }
  deriving stock (Eq, Show)

data UpdateWarning
  = LocalArtifactHasNoRemote Text
  | SameVersionContentChanged Text
  | AmbiguousLegacyValue VarName
  | MissingLegacyValue VarName
  | MigrationCommandNotSimulated ModuleName Text
  | CrossApplicationLastWriter FilePath ModuleName ModuleName
  | ArbitraryCommandSideEffectsMayRemain
  | BaselinePruneFailed Text
  | RecoveryCleanupDeferred Text
  deriving stock (Eq, Show)

data UpdatePlan = UpdatePlan
  { applications :: [AppliedComposition],
    versionChanges :: [VersionChange],
    inputChanges :: InputChangeSummary,
    migrations :: [PlannedUpdateMigration],
    reconciliation :: ReconciliationPlan,
    commandPlan :: CommandPlan,
    candidateArtifacts :: [CandidateArtifact],
    warnings :: [UpdateWarning],
    request :: UpdateRequest,
    snapshot :: UpdateSnapshot,
    plannedApplications :: [PlannedApplication]
  }
  deriving stock (Eq, Show)

data CommandSummary = CommandSummary
  { executed :: Int,
    skippedUnchanged :: Int,
    skippedDisabled :: Int
  }
  deriving stock (Eq, Show)

data UpdateResult = UpdateResult
  { updatedApplications :: [ApplicationId],
    manifest :: Manifest,
    versions :: [VersionChange],
    fileSummary :: ReconciliationSummary,
    commandSummary :: CommandSummary,
    touchedPaths :: Set FilePath,
    warnings :: [UpdateWarning]
  }
  deriving stock (Eq, Show)

data UpdateError
  = UpdateManifestMissing FilePath
  | UpdateManifestUnreadable FilePath Text
  | NoRecordedApplications
  | LegacyUpdateRequiresOneTarget
  | UpdateTargetNotFound Text [Text]
  | SharedPathRequiresApplications FilePath (Set ApplicationId) (Set ApplicationId)
  | CandidateCloneFailed Text Text
  | CandidateRepositoryInvalid Text [Text]
  | CandidateArtifactMissing CandidateArtifactKind Text
  | CandidateArtifactAmbiguous CandidateArtifactKind Text [Text]
  | CandidateLoadFailed Text ModuleLoadError
  | CandidateDowngrade Text (Maybe Text) (Maybe Text)
  | CandidateVersionInvalid Text Text
  | UpdateConflictingPriorVersions ModuleName [Text]
  | UpdateVariableErrors [VarError]
  | UpdateConfigurationFailed Text
  | UpdateMigrationPlanFailed ModuleName MigrationPlanError
  | UpdateMigrationStageFailed ModuleName MigrationExecError
  | UpdateCompositionFailed [Text]
  | UpdateReconciliationFailed ReconciliationError
  | UpdateHasUnresolvedPaths (Set FilePath)
  | UpdateRecoveryFailed [TransactionError]
  | UpdatePlanStale (Set FilePath)
  | UpdateTransactionFailed TransactionError
  | UpdateMigrationFailed ModuleName MigrationExecError
  | UpdateChangedAfterMigrationCommand ReconciliationSummary ReconciliationSummary
  | UpdateCommandFailed CommandExecutionError [UpdateWarning]
  | UpdateCachePublicationFailed Text
  | UpdateManifestWriteFailed Text
  deriving stock (Eq, Show)
