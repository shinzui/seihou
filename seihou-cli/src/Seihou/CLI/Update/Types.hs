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
    isUpdateNoOp,
  )
where

import Data.Generics.Labels ()
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (isNothing, mapMaybe)
import Data.Set (Set)
import Seihou.CLI.CommandExecution
  ( CommandDisposition (..),
    CommandExecutionError,
    CommandPlan (..),
    CommandPolicy (..),
    PlannedCommand (..),
  )
import Seihou.CLI.ManifestCapabilityUpgrade (CertificationGap, EvidenceSource)
import Seihou.Composition.Instance (ModuleInstance)
import Seihou.Core.ArtifactRef (ArtifactRefError)
import Seihou.Core.Checkout (CheckoutAction (..), CheckoutEntry (..), CheckoutError, CheckoutPlan (..))
import Seihou.Core.CommandFingerprint (isCheckoutCommand)
import Seihou.Core.Migration (MigrationPlan, MigrationPlanError)
import Seihou.Core.Seed (replaceSelectedSeedClaims)
import Seihou.Core.Types
import Seihou.Engine.Migrate (ExecutedMigrationPlan, MigrationExecError)
import Seihou.Engine.Reconcile
  ( DesiredFileOwner,
    FileReconciliation (..),
    ReconciliationError,
    ReconciliationPlan (..),
    ReconciliationSummary,
    recordedSharedWriteMode,
    seedCandidateReceipts,
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
    parentVars :: !ParentVars,
    -- | The modules applied alongside the target. Together with the target
    -- they are the whole of the application id, so a label built from both
    -- is unique among recorded applications.
    additionalModules :: ![ModuleName]
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
    -- | The recorded releases fetched from their remotes to certify those
    -- modes, because no installed copy was the recorded version.
    evidenceSources :: ![EvidenceSource],
    -- | The manifest planning, migration, reconciliation, and the final
    -- manifest build start from instead of the on-disk one.
    preparedManifest :: !Manifest
  }
  deriving stock (Eq, Generic, Show)

data UpdateWarning
  = DependencyApplicationIncluded ApplicationRef (Map VarName Text)
  | LocalArtifactHasNoRemote Text
  | SameVersionContentChanged Text
  | AmbiguousLegacyValue VarName
  | MissingLegacyValue VarName
  | MigrationCommandNotSimulated ModuleName Text
  | CrossApplicationLastWriter FilePath ModuleName ModuleName
  | ArbitraryCommandSideEffectsMayRemain
  | BaselinePruneFailed Text
  | RecoveryCleanupDeferred Text
  | CheckoutWarning Text
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
    checkoutPlan :: !CheckoutPlan,
    checkoutOutputs :: !(Map FilePath CheckoutOutputRecord),
    checkoutAdoptions :: !(Map FilePath Text),
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
    adoptedLinks :: ![FilePath],
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
  | UpdateCheckoutFailed CheckoutError
  | UpdateSeedReleaseBlocked FilePath (Set ApplicationRef)
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

isUpdateNoOp :: UpdatePlan -> Bool
isUpdateNoOp plan =
  -- A lossless schema step or a newly certified shared-write mode is a
  -- change to applied state that only this update will publish (ADR 0004),
  -- so a plan carrying one is never a deliberate no-op (ADR 0007).
  plan ^. #checkoutOutputs == plan ^. #snapshot . #originalManifest . #checkoutOutputs
    && Map.null (plan ^. #checkoutAdoptions)
    && all ((== UnchangedLink) . (^. #action)) (plan ^. #checkoutPlan . #entries)
    && isNothing (plan ^. #manifestPreparation)
    && null (plan ^. #versionChanges)
    && null (plan ^. #migrations)
    && plan ^. #inputChanges . #overridden == 0
    && plan ^. #inputChanges . #newlyResolved == 0
    && plan ^. #inputChanges . #removed == 0
    && not (any actionableCommand (plan ^. #commandPlan . #commands))
    && seedClaimsUnchanged
    && all unchangedFile (Map.elems (plan ^. #reconciliation . #files))
    && and (zipWith sameApplication (mapMaybe (^. #previous) (plan ^. #plannedApplications)) (plan ^. #applications))
  where
    actionableCommand command = command ^. #disposition == CommandWillRun && (plan ^. #request . #commandPolicy == RunAllCommands || not (isCheckoutCommand (command ^. #operation)))
    -- A file whose content is unchanged can still carry a manifest record
    -- that is out of date. The shared-write mode is the case that matters: a
    -- project whose manifest predates the evidence has no answer for any path, and
    -- treating that as a no-op would mean the answer is never written, so the
    -- shared-path exemption could never take effect on an existing project.
    -- Recording a fact about applied state is a change to applied state
    -- (ADR 0004), so such a plan is not a deliberate no-op (ADR 0007).
    seedClaimsUnchanged =
      let original = plan ^. #snapshot . #originalManifest
          reconciliation = plan ^. #reconciliation
          candidate = seedCandidateReceipts (original ^. #genAt) original reconciliation
       in case replaceSelectedSeedClaims (reconciliation ^. #applicationIds) candidate original of
            Right next -> next ^. #seeds == original ^. #seeds
            Left _ -> False
    unchangedFile FileSeedSettle {} = True
    unchangedFile (FileUnchanged desired _ _ prior) =
      maybe True (\record -> record ^. #sharedWriteMode == recordedSharedWriteMode (plan ^. #reconciliation . #applicationIds) desired prior) prior
    unchangedFile _ = False
    -- Compare only what the manifest actually records. Anything derived from
    -- where an artifact happens to sit on this machine would differ between a
    -- decoded application and a freshly loaded candidate, and would report
    -- every re-run as a change.
    sameApplication previous candidate =
      previous ^. #target == candidate ^. #target
        && previous ^. #targetOrigin == candidate ^. #targetOrigin
        && previous ^. #targetVersion == candidate ^. #targetVersion
        && previous ^. #additionalModules == candidate ^. #additionalModules
        && previous ^. #namespace == candidate ^. #namespace
        && previous ^. #context == candidate ^. #context
        && length (previous ^. #instances) == length (candidate ^. #instances)
        && and (zipWith sameInstance (previous ^. #instances) (candidate ^. #instances))
        && previous ^. #commandReceipts == (candidate ^. #commandReceipts)
        && previous ^. #checkoutCommands == candidate ^. #checkoutCommands

    sameInstance previous candidate =
      previous ^. #name == candidate ^. #name
        && previous ^. #parentVars == candidate ^. #parentVars
        && previous ^. #origin == candidate ^. #origin
        && previous ^. #moduleVersion == candidate ^. #moduleVersion
        && previous ^. #resolvedVars == candidate ^. #resolvedVars
