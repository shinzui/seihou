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
    ApplicationRef (..),
    ManifestPreparation (..),
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
import Seihou.CLI.ManifestCapabilityUpgrade (CertificationGap)
import Seihou.Composition.Instance (ModuleInstance)
import Seihou.Core.ArtifactRef (ArtifactRefError)
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
  { selection :: !UpdateSelection,
    varOverrides :: ![(Text, Text)],
    reconfigure :: !Bool,
    promptPolicy :: !PromptPolicy,
    commandPolicy :: !CommandPolicy,
    dryRun :: !Bool,
    -- | When 'True', accept a candidate artifact whose version is lower
    -- than the version @.seihou\/manifest.json@ records, instead of
    -- failing with 'CandidateDowngrade'. The default is 'False', so an
    -- update never moves a project backwards by accident.
    allowDowngrade :: !Bool,
    -- | When 'True', expand a named selection to the applications the
    -- ownership closure still requires instead of refusing, reporting each
    -- one added. The default is 'False': a named selection is never
    -- broadened without being asked.
    includeSharedOwners :: !Bool
  }
  deriving stock (Eq, Generic, Show)

data VersionChange = VersionChange
  { name :: !Text,
    fromVersion :: !(Maybe Text),
    toVersion :: !(Maybe Text),
    sameVersionContentChanged :: !Bool
  }
  deriving stock (Eq, Generic, Show)

data InputChangeSummary = InputChangeSummary
  { reused :: !Int,
    overridden :: !Int,
    newlyResolved :: !Int,
    removed :: !Int,
    ambiguousLegacy :: ![VarName]
  }
  deriving stock (Eq, Generic, Show)

data CandidateArtifactKind = CandidateModule | CandidateRecipe
  deriving stock (Eq, Ord, Show)

-- | One validated artifact staged for this update session. The source path is
-- temporary for remote candidates and must not escape 'withProjectUpdate'.
data CandidateArtifact = CandidateArtifact
  { kind :: !CandidateArtifactKind,
    name :: !Text,
    version :: !(Maybe Text),
    originalDirectory :: !FilePath,
    sourceDirectory :: !FilePath,
    sourceUrl :: !(Maybe Text),
    repoName :: !(Maybe Text),
    tags :: ![Text],
    sourceRevision :: !(Maybe Text),
    contentHash :: !SHA256,
    moduleDefinition :: !(Maybe Module),
    recipeDefinition :: !(Maybe Recipe)
  }
  deriving stock (Eq, Generic, Show)

data CandidateCatalog = CandidateCatalog
  { searchRoot :: !FilePath,
    artifacts :: !(Map (CandidateArtifactKind, Text) CandidateArtifact),
    clonedOrigins :: !(Map Text FilePath)
  }
  deriving stock (Eq, Generic, Show)

data PlannedUpdateMigration = PlannedUpdateMigration
  { moduleName :: !ModuleName,
    sourceDirectory :: !FilePath,
    sourcePlan :: !MigrationPlan,
    stagedPlan :: !ExecutedMigrationPlan,
    containsCommands :: !Bool
  }
  deriving stock (Eq, Generic, Show)

-- | Internal, renderer-neutral material retained so apply can re-plan after
-- migration commands without reusing parser state.
data PlannedApplication = PlannedApplication
  { previous :: !(Maybe AppliedComposition),
    candidate :: !AppliedComposition,
    modulesInOrder :: ![(ModuleInstance, Module, FilePath)],
    resolvedValues :: !(Map ModuleInstance (Map VarName ResolvedVar)),
    operations :: ![Operation],
    desiredOwners :: !(Map FilePath DesiredFileOwner)
  }
  deriving stock (Eq, Generic, Show)

data UpdateSnapshot = UpdateSnapshot
  { sessionDirectory :: !FilePath,
    projectRoot :: !FilePath,
    manifestPath :: !FilePath,
    baselineDirectory :: !FilePath,
    installedDirectory :: !FilePath,
    originalManifest :: !Manifest,
    candidateHashes :: !(Map FilePath SHA256),
    observedProjectHashes :: !(Map FilePath (Maybe SHA256)),
    transactionTargets :: !(Set FilePath)
  }
  deriving stock (Eq, Generic, Show)

-- | A renderer-neutral reference to one recorded application: enough for a
-- renderer to label it without ever showing only an opaque digest.
data ApplicationRef = ApplicationRef
  { applicationId :: !ApplicationId,
    -- | The recorded root target, or 'Nothing' when a file record names an
    -- owner the manifest does not record as an application.
    target :: !(Maybe AppliedTarget),
    -- | The parent variables of the target's root instance.
    parentVars :: !ParentVars
  }
  deriving stock (Eq, Ord, Show, Generic)

-- | The lossless manifest change a targeted update stages in memory before
-- it enforces the ownership closure: the schema step the feature requires
-- (docs/adr/0014-every-semantic-manifest-change-advances-the-schema-version.md)
-- and every shared-write mode certification established. It is published
-- only with the update's own manifest, never as a separate write.
data ManifestPreparation = ManifestPreparation
  { fromVersion :: !ManifestSchemaVersion,
    toVersion :: !ManifestSchemaVersion,
    -- | Each certified path with its mode before and after.
    modeChanges :: !(Map FilePath (SharedWriteMode, SharedWriteMode)),
    -- | The manifest planning, migration, reconciliation, and the final
    -- manifest build start from instead of the on-disk one.
    preparedManifest :: !Manifest
  }
  deriving stock (Eq, Generic, Show)

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
  | -- | @--include-shared-owners@ added this application to the selection
    --   because it co-owns the named path with something the user asked for.
    SelectionExpandedForSharedPath FilePath ApplicationRef
  deriving stock (Eq, Show)

data UpdatePlan = UpdatePlan
  { applications :: ![AppliedComposition],
    versionChanges :: ![VersionChange],
    inputChanges :: !InputChangeSummary,
    migrations :: ![PlannedUpdateMigration],
    reconciliation :: !ReconciliationPlan,
    commandPlan :: !CommandPlan,
    candidateArtifacts :: ![CandidateArtifact],
    warnings :: ![UpdateWarning],
    request :: !UpdateRequest,
    snapshot :: !UpdateSnapshot,
    plannedApplications :: ![PlannedApplication],
    manifestPreparation :: !(Maybe ManifestPreparation)
  }
  deriving stock (Eq, Generic, Show)

data CommandSummary = CommandSummary
  { executed :: !Int,
    skippedUnchanged :: !Int,
    skippedDisabled :: !Int
  }
  deriving stock (Eq, Generic, Show)

data UpdateResult = UpdateResult
  { updatedApplications :: ![ApplicationId],
    manifest :: !Manifest,
    versions :: ![VersionChange],
    fileSummary :: !ReconciliationSummary,
    commandSummary :: !CommandSummary,
    touchedPaths :: !(Set FilePath),
    warnings :: ![UpdateWarning]
  }
  deriving stock (Eq, Generic, Show)

data UpdateError
  = UpdateManifestMissing FilePath
  | UpdateManifestUnreadable FilePath Text
  | -- | The manifest is at a schema older than the ordinary decoder reads.
    -- Converting it recovers artifact origins from machine-local paths,
    -- which is inference and so only @seihou manifest upgrade@ may do it
    -- (docs/adr/0005-legacy-manifests-convert-through-an-explicit-command.md).
    UpdateManifestUpgradeRequired FilePath ManifestSchemaVersion
  | NoRecordedApplications
  | LegacyUpdateRequiresOneTarget
  | UpdateTargetNotFound Text [Text]
  | -- | The path is known to require the ownership closure: selected
    -- owners, then the owners missing from the selection.
    SharedPathRequiresApplications FilePath (Set ApplicationRef) (Set ApplicationRef)
  | -- | Nothing records how the path's owners write it, and certification
    -- could not establish it: each owner whose evidence is missing, with why.
    -- Selecting more applications would not supply the missing fact.
    SharedWriteEvidenceUnavailable FilePath [(ApplicationRef, CertificationGap)]
  | CandidateCloneFailed Text Text
  | CandidateRepositoryInvalid Text [Text]
  | CandidateArtifactMissing CandidateArtifactKind Text
  | -- | An artifact the manifest records could not be located on this
    -- machine and has no remote to fetch it from.
    CandidateArtifactUnresolved ArtifactRefError
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
