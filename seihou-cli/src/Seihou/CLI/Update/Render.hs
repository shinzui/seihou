module Seihou.CLI.Update.Render
  ( UpdateOutput (..),
    UpdatePlanView,
    UpdateResultView,
    UpdateErrorView,
    planOutput,
    resultOutput,
    errorOutput,
    errorOutputFor,
    agentUpgradeHint,
    renderUpdateHuman,
    encodeUpdateOutput,
    errorCode,
  )
where

import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString.Lazy (ByteString)
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isNothing)
import Data.Set qualified as Set
import Data.Text qualified as T
import Seihou.CLI.ApplicationDisplay (applicationLabel, appliedTargetName, moduleNameText)
import Seihou.CLI.CommandExecution
  ( CommandDisposition (..),
    CommandPlan (..),
    CommandPlanSummary (..),
    PlannedCommand (..),
    summarizeCommandPlan,
  )
import Seihou.CLI.ManifestCapabilityUpgrade (CertificationGap (..), EvidenceSource (..), renderEvidenceSource)
import Seihou.CLI.Shared (formatVarError)
import Seihou.CLI.Update.Types
import Seihou.Core.ArtifactRef (renderArtifactRefError)
import Seihou.Core.Migration (MigrationPlan (..), MigrationPlanError (..))
import Seihou.Core.Types
  ( ApplicationId (..),
    AppliedComposition (..),
    AppliedTarget (..),
    BaselineRef (..),
    CommandFingerprint (..),
    ManifestSchemaVersion (..),
    ModuleLoadError (..),
    ModuleName (..),
    Operation (..),
    SHA256 (..),
    VarName (..),
  )
import Seihou.Core.Version (renderVersion)
import Seihou.Engine.Migrate (MigrationExecError (..))
import Seihou.Engine.Reconcile
  ( DesiredFile (..),
    FileConflictChoice (..),
    FileReconciliation (..),
    OrphanChoice (..),
    ReconciliationError
      ( CopySourceUnavailable,
        DesiredOwnerOutsideSelection,
        InvalidReconciliationPath,
        MissingDesiredOwner,
        NotAFileConflict,
        NotAnEditedOrphan,
        PatchMaterializationFailed,
        ReconciliationPathNotFound,
        UpdateAborted
      ),
    ReconciliationPlan (..),
    ReconciliationSummary (..),
    ResolvedFileConflict (..),
    reconciliationSummary,
    recordedSharedWriteMode,
  )
import Seihou.Engine.Reconcile qualified as Reconcile
import Seihou.Engine.UpdateTransaction (TransactionError (..))
import Seihou.Manifest.Types (sharedWriteModeToText)
import Seihou.Prelude

newtype UpdatePlanView = UpdatePlanView UpdatePlan

newtype UpdateResultView = UpdateResultView UpdateResult

-- | A failure, and the first target the update named, which the human
-- rendering's @seihou agent upgrade@ hint repeats.
data UpdateErrorView = UpdateErrorView (Maybe Text) UpdateError

data UpdateOutput
  = UpdatePlanOutput UpdatePlanView
  | UpdateAppliedOutput UpdateResultView
  | UpdateFailedOutput UpdateErrorView

planOutput :: UpdatePlan -> UpdateOutput
planOutput = UpdatePlanOutput . UpdatePlanView

resultOutput :: UpdateResult -> UpdateOutput
resultOutput = UpdateAppliedOutput . UpdateResultView

errorOutput :: UpdateError -> UpdateOutput
errorOutput = errorOutputFor []

-- | 'errorOutput' for an update that named these targets.
errorOutputFor :: [Text] -> UpdateError -> UpdateOutput
errorOutputFor targets = UpdateFailedOutput . UpdateErrorView (case targets of target : _ -> Just target; [] -> Nothing)

-- | The line every human update failure ends with, after the remedy-first
-- message: the escape hatch when that remedy is unclear. JSON output never
-- carries it, so @error.message@ stays stable.
agentUpgradeHint :: Maybe Text -> Text
agentUpgradeHint target =
  "If this keeps failing, run 'seihou agent upgrade "
    <> fromMaybe "<module>" target
    <> "' to have an agent repair the manifest state and finish the upgrade.\n"

renderUpdateHuman :: Bool -> UpdateOutput -> Text
renderUpdateHuman _ (UpdatePlanOutput (UpdatePlanView plan)) =
  T.unlines $
    preparationLines (plan ^. #manifestPreparation)
      <> versionLines plan
      <> [ renderInputs (plan ^. #inputChanges),
           "Migrations:  " <> count (length (plan ^. #migrations)) <> migrationCaveat plan,
           renderFiles (reconciliationSummary (plan ^. #reconciliation)),
           renderCommands (summarizeCommandPlan (plan ^. #commandPlan))
         ]
      <> conflictLines (plan ^. #reconciliation)
      <> warningLines (plan ^. #warnings)
renderUpdateHuman _ (UpdateAppliedOutput (UpdateResultView result)) =
  T.unlines $
    [ "Updated " <> count (length (result ^. #updatedApplications)) <> " application(s).",
      renderFiles (result ^. #fileSummary),
      "Commands:    "
        <> count (result ^. #commandSummary . #executed)
        <> " executed; "
        <> count (result ^. #commandSummary . #skippedUnchanged)
        <> " unchanged skipped; "
        <> count (result ^. #commandSummary . #skippedDisabled)
        <> " disabled"
    ]
      <> warningLines (result ^. #warnings)
renderUpdateHuman _ (UpdateFailedOutput (UpdateErrorView target err)) =
  "Update failed [" <> errorCode err <> "]: " <> errorMessage err <> "\n" <> agentUpgradeHint target

encodeUpdateOutput :: UpdateOutput -> ByteString
encodeUpdateOutput = encode . outputValue

outputValue :: UpdateOutput -> Value
outputValue (UpdatePlanOutput (UpdatePlanView plan)) =
  object
    [ "schemaVersion" .= (1 :: Int),
      "outcome" .= ("plan" :: Text),
      "alreadyUpToDate" .= planLooksUnchanged plan,
      "manifestPreparation" .= fmap preparationValue (plan ^. #manifestPreparation),
      "applications" .= map applicationIdText (plan ^. #applications),
      "versions" .= map versionValue (plan ^. #versionChanges),
      "inputs" .= inputValue (plan ^. #inputChanges),
      "migrations" .= map migrationValue (plan ^. #migrations),
      "files" .= map fileValue (Map.toAscList (plan ^. #reconciliation . #files)),
      "commands" .= map commandValue (plan ^. #commandPlan . #commands),
      "warnings" .= map warningText (plan ^. #warnings)
    ]
outputValue (UpdateAppliedOutput (UpdateResultView result)) =
  object
    [ "schemaVersion" .= (1 :: Int),
      "outcome" .= ("applied" :: Text),
      "applications" .= map (^. #unApplicationId) (result ^. #updatedApplications),
      "versions" .= map versionValue (result ^. #versions),
      "files" .= summaryValue (result ^. #fileSummary),
      "commands"
        .= object
          [ "executed" .= (result ^. #commandSummary . #executed),
            "skippedUnchanged" .= (result ^. #commandSummary . #skippedUnchanged),
            "skippedDisabled" .= (result ^. #commandSummary . #skippedDisabled)
          ],
      "touchedPaths" .= Set.toAscList (result ^. #touchedPaths),
      "warnings" .= map warningText (result ^. #warnings)
    ]
outputValue (UpdateFailedOutput (UpdateErrorView _ err)) =
  object
    [ "schemaVersion" .= (1 :: Int),
      "outcome" .= ("error" :: Text),
      "error" .= object ["code" .= errorCode err, "message" .= errorMessage err]
    ]

-- | The manifest change a targeted update stages before it plans.
preparationLines :: Maybe ManifestPreparation -> [Text]
preparationLines Nothing = []
preparationLines (Just preparation) =
  ("Manifest:    " <> schemaChange preparation)
    : [ "             "
          <> T.pack path
          <> " evidence "
          <> sharedWriteModeToText before
          <> " -> "
          <> sharedWriteModeToText after
      | (path, (before, after)) <- Map.toAscList (preparation ^. #modeChanges)
      ]
      <> [ "             (" <> renderEvidenceSource source <> ")"
         | source <- preparation ^. #evidenceSources
         ]
  where
    schemaChange p
      | p ^. #fromVersion == p ^. #toVersion = "schema " <> schemaText (p ^. #toVersion) <> " (evidence recorded)"
      | otherwise = "schema " <> schemaText (p ^. #fromVersion) <> " -> " <> schemaText (p ^. #toVersion)

preparationValue :: ManifestPreparation -> Value
preparationValue preparation =
  object $
    [ "fromSchema" .= (preparation ^. #fromVersion . #unManifestSchemaVersion),
      "toSchema" .= (preparation ^. #toVersion . #unManifestSchemaVersion),
      "sharedWriteModes"
        .= [ object
               [ "path" .= path,
                 "from" .= sharedWriteModeToText before,
                 "to" .= sharedWriteModeToText after
               ]
           | (path, (before, after)) <- Map.toAscList (preparation ^. #modeChanges)
           ]
    ]
      -- Additive and omitted when empty, so an update that fetched nothing
      -- prints exactly what it printed before.
      <> [ "evidenceSources" .= map evidenceSourceValue sources
         | let sources = preparation ^. #evidenceSources,
           not (null sources)
         ]
  where
    evidenceSourceValue source =
      object
        [ "module" .= (source ^. #moduleName . #unModuleName),
          "version" .= (source ^. #version),
          "origin" .= (source ^. #originUrl),
          "revision" .= (source ^. #revision)
        ]

schemaText :: ManifestSchemaVersion -> Text
schemaText version = T.pack (show (version ^. #unManifestSchemaVersion))

versionLines :: UpdatePlan -> [Text]
versionLines plan
  | null (plan ^. #versionChanges) = ["Versions:    unchanged"]
  | otherwise = map renderVersionChange (plan ^. #versionChanges)

renderVersionChange :: VersionChange -> Text
renderVersionChange change =
  change ^. #name
    <> "  "
    <> fromMaybe "unversioned" (change ^. #fromVersion)
    <> " -> "
    <> fromMaybe "unversioned" (change ^. #toVersion)
    <> if change ^. #sameVersionContentChanged then " (content changed at same version)" else ""

renderInputs :: InputChangeSummary -> Text
renderInputs summary =
  "Inputs:      "
    <> count (summary ^. #reused)
    <> " reused; "
    <> count (summary ^. #overridden)
    <> " overridden; "
    <> count (summary ^. #newlyResolved)
    <> " newly resolved; "
    <> count (summary ^. #removed)
    <> " removed"

renderFiles :: ReconciliationSummary -> Text
renderFiles summary =
  "Files:       "
    <> count (summary ^. #creates)
    <> " created; "
    <> count (summary ^. #updates)
    <> " updated; "
    <> count (summary ^. #merged)
    <> " merged; "
    <> count (summary ^. #unchanged)
    <> " unchanged; "
    <> count (summary ^. #conflicts)
    <> " conflicts; "
    <> count (summary ^. #safeDeletes)
    <> " deleted; "
    <> count (summary ^. #editedOrphans)
    <> " edited orphans"

renderCommands summary =
  "Commands:    "
    <> count (summary ^. #willRun)
    <> " will run; "
    <> count (summary ^. #skippedUnchanged)
    <> " unchanged skipped; "
    <> count (summary ^. #skippedDisabled)
    <> " disabled"

migrationCaveat plan
  | any (^. #containsCommands) (plan ^. #migrations) = " (includes non-simulatable commands)"
  | otherwise = ""

conflictLines :: ReconciliationPlan -> [Text]
conflictLines reconciliation = concatMap renderOne (Map.toAscList (reconciliation ^. #files))
  where
    renderOne (path, FileConflict _ _ _ reason _ _ resolution) =
      [ "Conflict:    "
          <> T.pack path
          <> " ("
          <> T.pack (show reason)
          <> maybe "; unresolved" (("; " <>) . resolutionText . (^. #choice)) resolution
          <> ")"
      ]
    renderOne (path, FileOrphanEdited _ _ _ _ choice) =
      [ "Orphan:      "
          <> T.pack path
          <> maybe " (unresolved)" ((" (" <>) . (<> ")") . orphanChoiceText) choice
      ]
    renderOne _ = []

warningLines :: [UpdateWarning] -> [Text]
warningLines = map (("Warning:     " <>) . warningText)

versionValue :: VersionChange -> Value
versionValue change =
  object
    [ "name" .= (change ^. #name),
      "from" .= (change ^. #fromVersion),
      "to" .= (change ^. #toVersion),
      "sameVersionContentChanged" .= (change ^. #sameVersionContentChanged)
    ]

inputValue :: InputChangeSummary -> Value
inputValue summary =
  object
    [ "reused" .= (summary ^. #reused),
      "overridden" .= (summary ^. #overridden),
      "newlyResolved" .= (summary ^. #newlyResolved),
      "removed" .= (summary ^. #removed),
      "ambiguousLegacy" .= map (^. #unVarName) (summary ^. #ambiguousLegacy)
    ]

migrationValue :: PlannedUpdateMigration -> Value
migrationValue migration =
  object
    [ "module" .= (migration ^. #moduleName . #unModuleName),
      "from" .= showText (migration ^. #sourcePlan . #from),
      "to" .= showText (migration ^. #sourcePlan . #to),
      "steps" .= length (migration ^. #sourcePlan . #steps),
      "containsCommands" .= (migration ^. #containsCommands)
    ]

fileValue :: (FilePath, FileReconciliation) -> Value
fileValue (path, reconciliation) =
  object
    [ "path" .= path,
      "classification" .= classification reconciliation,
      "resolution" .= resolutionFor reconciliation
    ]

classification :: FileReconciliation -> Text
classification FileCreate {} = "create"
classification FileUpdate {} = "update"
classification FileAutoMerge {} = "autoMerge"
classification FileUnchanged {} = "unchanged"
classification FileConflict {} = "conflict"
classification FileDeleteSafe {} = "safeDelete"
classification FileOrphanEdited {} = "editedOrphan"
classification FileReleaseSharedOwnership {} = "releaseSharedOwnership"
classification FileAlreadyAbsent {} = "alreadyAbsent"

resolutionFor :: FileReconciliation -> Maybe Text
resolutionFor (FileConflict _ _ _ _ _ _ resolution) = resolutionText . (^. #choice) <$> resolution
resolutionFor (FileOrphanEdited _ _ _ _ choice) = orphanChoiceText <$> choice
resolutionFor _ = Nothing

commandValue :: PlannedCommand -> Value
commandValue planned =
  object
    [ "fingerprint" .= fingerprintText (planned ^. #fingerprint),
      "status" .= dispositionText (planned ^. #disposition),
      "module" .= commandModule (planned ^. #operation),
      "command" .= commandText (planned ^. #operation)
    ]

commandModule :: Operation -> Maybe Text
commandModule RunCommandOp {moduleName} = Just (moduleName ^. #unModuleName)
commandModule _ = Nothing

commandText :: Operation -> Maybe Text
commandText RunCommandOp {command} = Just command
commandText _ = Nothing

dispositionText :: CommandDisposition -> Text
dispositionText CommandWillRun = "willRun"
dispositionText CommandSkippedUnchanged = "skippedUnchanged"
dispositionText CommandSkippedDisabled = "skippedDisabled"

resolutionText :: FileConflictChoice -> Text
resolutionText AcceptGenerated = "useGenerated"
resolutionText KeepCurrent = "keepCurrent"
resolutionText WriteConflictMarkers = "writeConflictMarkers"
resolutionText AbortUpdate = "abort"

orphanChoiceText :: OrphanChoice -> Text
orphanChoiceText DeleteEditedOrphan = "delete"
orphanChoiceText RetainTrackedOrphan = "retainTracked"
orphanChoiceText DetachAndKeepOrphan = "detachAndKeep"
orphanChoiceText AbortOrphanUpdate = "abort"

summaryValue :: ReconciliationSummary -> Value
summaryValue summary =
  object
    [ "created" .= (summary ^. #creates),
      "updated" .= (summary ^. #updates),
      "merged" .= (summary ^. #merged),
      "unchanged" .= (summary ^. #unchanged),
      "conflicts" .= (summary ^. #conflicts),
      "safeDeletes" .= (summary ^. #safeDeletes),
      "editedOrphans" .= (summary ^. #editedOrphans),
      "sharedOwnership" .= (summary ^. #sharedOwnership)
    ]

gapText :: CertificationGap -> Text
gapText (OwnerNotRecorded _) = "the manifest does not record it as an application, so nothing describes how it writes"
gapText (OwnerEvidenceUnavailable _ reason) = reason
gapText (OwnerEmitsNoOperation _) = "its recorded version no longer writes this path"

applicationIdText :: AppliedComposition -> Text
applicationIdText application = (application ^. #applicationId . #unApplicationId)

fingerprintText :: CommandFingerprint -> Text
fingerprintText (CommandFingerprint (SHA256 value)) = value

-- | Every warning, as a sentence a person can act on. Deliberately
-- exhaustive, with no fallback to 'show': a new constructor must not compile
-- its way into the terminal as Haskell syntax.
warningText :: UpdateWarning -> Text
warningText (LocalArtifactHasNoRemote name) =
  name
    <> " has no recorded remote, so the locally installed copy is the update candidate;"
    <> " record its origin to update it from upstream"
warningText (SameVersionContentChanged name) =
  name <> " changed content without changing its declared version"
warningText (AmbiguousLegacyValue name) =
  "the legacy manifest value for "
    <> name ^. #unVarName
    <> " is declared by more than one module, so it was not reused; it is resolved again"
warningText (MissingLegacyValue name) =
  "the legacy manifest has no value for required variable " <> name ^. #unVarName <> "; it is resolved again"
warningText (MigrationCommandNotSimulated name command) =
  "a migration of "
    <> moduleNameText name
    <> " runs '"
    <> command
    <> "', which a dry run cannot simulate; the file summary assumes it changes nothing"
warningText (CrossApplicationLastWriter path earlier later)
  | earlier == later = T.pack path <> " is written more than once by " <> moduleNameText later
  | otherwise =
      T.pack path
        <> " receives content from both "
        <> moduleNameText earlier
        <> " and "
        <> moduleNameText later
        <> "; "
        <> moduleNameText later
        <> " is recorded as its last writer (ownership attribution only, not a content change)"
warningText ArbitraryCommandSideEffectsMayRemain =
  "a command ran before the failure; managed files were restored, but anything else it changed was not"
warningText (BaselinePruneFailed reason) =
  "the update succeeded, but old update baselines could not be pruned: " <> reason
warningText (RecoveryCleanupDeferred reason) =
  "the update succeeded, but cleaning up its recovery data was deferred: " <> reason
warningText (SelectionExpandedForSharedPath path owner) =
  "also updating "
    <> applicationLabel owner
    <> " because it co-owns "
    <> T.pack path
    <> " (--include-shared-owners)"

errorCode :: UpdateError -> Text
errorCode UpdateManifestMissing {} = "manifest_missing"
errorCode UpdateManifestUnreadable {} = "manifest_unreadable"
errorCode UpdateManifestUpgradeRequired {} = "manifest_upgrade_required"
errorCode NoRecordedApplications = "no_recorded_applications"
errorCode LegacyUpdateRequiresOneTarget = "legacy_update_requires_one_target"
errorCode UpdateTargetNotFound {} = "target_not_found"
errorCode SharedPathRequiresApplications {} = "shared_path_requires_applications"
errorCode SharedWriteEvidenceUnavailable {} = "shared_write_evidence_unavailable"
errorCode CandidateCloneFailed {} = "candidate_clone_failed"
errorCode CandidateRepositoryInvalid {} = "candidate_repository_invalid"
errorCode CandidateArtifactMissing {} = "candidate_artifact_missing"
errorCode CandidateArtifactUnresolved {} = "candidate_artifact_unresolved"
errorCode CandidateArtifactAmbiguous {} = "candidate_artifact_ambiguous"
errorCode CandidateLoadFailed {} = "candidate_load_failed"
errorCode CandidateDowngrade {} = "candidate_downgrade"
errorCode CandidateVersionInvalid {} = "candidate_version_invalid"
errorCode UpdateConflictingPriorVersions {} = "conflicting_prior_versions"
errorCode UpdateVariableErrors {} = "variable_errors"
errorCode UpdateConfigurationFailed {} = "configuration_failed"
errorCode UpdateMigrationPlanFailed {} = "migration_plan_failed"
errorCode UpdateMigrationStageFailed {} = "migration_stage_failed"
errorCode UpdateCompositionFailed {} = "composition_failed"
errorCode UpdateReconciliationFailed {} = "reconciliation_failed"
errorCode UpdateHasUnresolvedPaths {} = "unresolved_paths"
errorCode UpdateRecoveryFailed {} = "recovery_failed"
errorCode UpdatePlanStale {} = "plan_stale"
errorCode UpdateTransactionFailed {} = "transaction_failed"
errorCode UpdateMigrationFailed {} = "migration_failed"
errorCode UpdateChangedAfterMigrationCommand {} = "changed_after_migration_command"
errorCode UpdateCommandFailed {} = "command_failed"
errorCode UpdateCachePublicationFailed {} = "cache_publication_failed"
errorCode UpdateManifestWriteFailed {} = "manifest_write_failed"

-- | Every error, as prose that leads with the repair. Deliberately
-- exhaustive, like 'warningText'.
errorMessage :: UpdateError -> Text
errorMessage (UpdateManifestMissing path) =
  "No Seihou manifest was found at " <> T.pack path <> ". Run seihou run first."
errorMessage (UpdateManifestUnreadable path reason) =
  "The manifest at " <> T.pack path <> " could not be read: " <> reason
errorMessage (UpdateManifestUpgradeRequired path version) =
  "Run 'seihou manifest upgrade --dry-run' to review the conversion, then 'seihou manifest upgrade',"
    <> " then update again. The manifest at "
    <> T.pack path
    <> " uses schema "
    <> schemaText version
    <> ", which records machine-specific artifact paths; converting them to portable origins"
    <> " is inference, so it is never done implicitly."
errorMessage NoRecordedApplications =
  "The manifest records no applications to update. Run seihou run <target> first."
errorMessage LegacyUpdateRequiresOneTarget =
  "This manifest predates recorded applications. Name exactly one target to update, and"
    <> " seihou records it as the first application."
errorMessage (UpdateTargetNotFound target available) =
  "No recorded application matches '"
    <> target
    <> "'. Available targets: "
    <> T.intercalate ", " available
errorMessage (SharedPathRequiresApplications path selected required) =
  "At least one owner of "
    <> T.pack path
    <> " writes the whole file, so its owners have to be updated together. Selected: "
    <> labels selected
    <> ". Also required: "
    <> labels required
    <> ". Name them as targets"
    <> maybe "" (\command -> " (" <> command <> ")") (selectionCommand (selected <> required))
    <> ", or pass --include-shared-owners to update their full applications too."
  where
    labels = T.intercalate ", " . map applicationLabel . Set.toAscList
errorMessage (SharedWriteEvidenceUnavailable path gaps) =
  "Seihou has to inspect how the owners of "
    <> T.pack path
    <> " write it before a targeted update may leave any of them out, and it could not read the"
    <> " recorded version of each application below, either installed here or from its recorded origin: "
    <> T.intercalate "; " [applicationLabel owner <> ": " <> gapText gap | (owner, gap) <- gaps]
    <> ". Install that exact version, or make its recorded origin reachable, then update again."
    <> " Inspecting an owner does not update it, and selecting more applications would not"
    <> " supply the missing evidence. 'seihou manifest upgrade --dry-run' lists every path still unresolved."
errorMessage (CandidateCloneFailed url reason) =
  "Could not clone " <> url <> ": " <> reason
errorMessage (CandidateRepositoryInvalid source problems) =
  source <> " is not a usable Seihou artifact source: " <> T.intercalate "; " problems
errorMessage (CandidateArtifactMissing kind name) =
  "No candidate " <> kindText kind <> " named " <> name <> " was found in its recorded source."
errorMessage (CandidateArtifactUnresolved err) =
  renderArtifactRefError err
errorMessage (CandidateArtifactAmbiguous kind name locations) =
  "More than one candidate "
    <> kindText kind
    <> " named "
    <> name
    <> " was found: "
    <> T.intercalate ", " locations
errorMessage (CandidateLoadFailed name err) =
  "Candidate " <> name <> " could not be loaded: " <> loadErrorText err
errorMessage (CandidateDowngrade name recorded candidate) =
  "Updating "
    <> name
    <> " would move it from "
    <> fromMaybe "unversioned" recorded
    <> " back to "
    <> fromMaybe "unversioned" candidate
    <> ". Pass --allow-downgrade if that is intended."
errorMessage (CandidateVersionInvalid name version) =
  "Candidate " <> name <> " declares a version seihou cannot parse: '" <> version <> "'"
errorMessage (UpdateConflictingPriorVersions name versions) =
  "Module "
    <> moduleNameText name
    <> " is recorded at more than one version ("
    <> T.intercalate ", " versions
    <> "), so there is no single starting point to plan its migrations from."
errorMessage (UpdateVariableErrors errors) =
  "Variables could not be resolved: " <> T.intercalate "; " (map formatVarError errors)
errorMessage (UpdateConfigurationFailed reason) =
  "Configuration could not be loaded: " <> reason
errorMessage (UpdateMigrationPlanFailed name err) =
  "Cannot plan migrations for " <> moduleNameText name <> ": " <> migrationPlanErrorText err
errorMessage (UpdateMigrationStageFailed name err) =
  "Staging the migrations for " <> moduleNameText name <> " failed: " <> migrationExecErrorText err
errorMessage (UpdateCompositionFailed problems) =
  "The candidate composition is invalid: " <> T.intercalate "; " problems
errorMessage (UpdateReconciliationFailed err) =
  reconciliationErrorText err
errorMessage (UpdateHasUnresolvedPaths paths) =
  "Resolve these paths before apply: " <> T.intercalate ", " (map T.pack (Set.toAscList paths))
errorMessage (UpdateRecoveryFailed errors) =
  "An interrupted update could not be recovered: " <> T.intercalate "; " (map transactionErrorText errors)
errorMessage (UpdatePlanStale paths) =
  "The project changed after planning: " <> T.intercalate ", " (map T.pack (Set.toAscList paths))
errorMessage (UpdateTransactionFailed err) =
  "Publishing the update failed: " <> transactionErrorText err
errorMessage (UpdateMigrationFailed name err) =
  "A migration of " <> moduleNameText name <> " failed and the update was rolled back: " <> migrationExecErrorText err
errorMessage (UpdateChangedAfterMigrationCommand planned actual) =
  "A migration command changed the project in a way the plan did not show (planned "
    <> summaryText planned
    <> "; found "
    <> summaryText actual
    <> "). The update was rolled back; review the migration and plan again."
errorMessage (UpdateCommandFailed failure warnings) =
  "Command"
    <> maybe "" (\command -> " '" <> command <> "'") (commandText (failure ^. #command . #operation))
    <> " exited with code "
    <> count (failure ^. #exitCode)
    <> " and the update was rolled back"
    <> stderrText (failure ^. #stderr)
    <> T.concat [". Warning: " <> warningText warning | warning <- warnings]
  where
    stderrText output
      | T.null (T.strip output) = ""
      | otherwise = ": " <> T.strip output
errorMessage (UpdateCachePublicationFailed reason) =
  "The installed module cache could not be updated, so the update was rolled back: " <> reason
errorMessage (UpdateManifestWriteFailed reason) =
  "The manifest could not be written, so the update was rolled back: " <> reason

-- | A command line that names every recorded target among these owners,
-- when each has one.
selectionCommand :: Set.Set ApplicationRef -> Maybe Text
selectionCommand refs = do
  targets <- traverse (^. #target) (Set.toAscList refs)
  pure ("seihou update " <> T.unwords (Set.toAscList (Set.fromList (map appliedTargetName targets))))

kindText :: CandidateArtifactKind -> Text
kindText CandidateModule = "module"
kindText CandidateRecipe = "recipe"

loadErrorText :: ModuleLoadError -> Text
loadErrorText (ModuleNotFound name searched) =
  "module " <> moduleNameText name <> " was not found (searched " <> T.intercalate ", " (map T.pack searched) <> ")"
loadErrorText (DhallEvalError name reason) = "evaluating " <> moduleNameText name <> " failed: " <> reason
loadErrorText (DhallDecodeError name reason) = "decoding " <> moduleNameText name <> " failed: " <> reason
loadErrorText (ValidationError name problems) =
  moduleNameText name <> " is invalid: " <> T.intercalate "; " problems
loadErrorText (CircularDependency names) =
  "circular dependency: " <> T.intercalate " -> " (map moduleNameText names)
loadErrorText (MissingSourceFile name path) =
  moduleNameText name <> " is missing its source file " <> T.pack path
loadErrorText (RegistryEvalError source reason) =
  "evaluating registry " <> source <> " failed: " <> reason

migrationPlanErrorText :: MigrationPlanError -> Text
migrationPlanErrorText (MigrationVersionUnparseable version) =
  "a migration declares an unparseable version '" <> version <> "'"
migrationPlanErrorText (MigrationDowngradeNotSupported installed target) =
  "migrating down from " <> renderVersion installed <> " to " <> renderVersion target <> " is not supported"
migrationPlanErrorText (MigrationDuplicateEdge from _) =
  "more than one migration starts at " <> renderVersion from <> ", so the chain is ambiguous"

migrationExecErrorText :: MigrationExecError -> Text
migrationExecErrorText (MigrationConflict paths) =
  "these files were edited since they were generated: " <> T.intercalate ", " (map T.pack paths)
migrationExecErrorText (MigrationCommandFailed output code) =
  "a migration command exited with code " <> count code <> ": " <> output
migrationExecErrorText (MigrationUnsafePath label path reason) =
  "unsafe migration " <> label <> " '" <> T.pack path <> "': " <> reason

reconciliationErrorText :: ReconciliationError -> Text
reconciliationErrorText (InvalidReconciliationPath path reason) =
  "Path " <> T.pack path <> " cannot be reconciled: " <> reason
reconciliationErrorText (MissingDesiredOwner path) =
  "No selected application claims " <> T.pack path <> "."
reconciliationErrorText (DesiredOwnerOutsideSelection path owners) =
  T.pack path <> " would be written by " <> ownerCount owners <> " outside the selection."
reconciliationErrorText (Reconcile.SharedPathRequiresApplications path owners) =
  T.pack path
    <> " is also owned by "
    <> ownerCount owners
    <> " outside the selection and is not written only by additive patches."
    <> " Name those owners as targets, or pass --include-shared-owners."
reconciliationErrorText (CopySourceUnavailable path) =
  "The source for " <> T.pack path <> " is unavailable."
reconciliationErrorText (PatchMaterializationFailed path _ name reason) =
  "The patch " <> moduleNameText name <> " applies to " <> T.pack path <> " could not be applied: " <> reason
reconciliationErrorText (ReconciliationPathNotFound path) =
  "No planned change exists for " <> T.pack path <> "."
reconciliationErrorText (NotAFileConflict path) =
  T.pack path <> " is not a conflict, so it cannot be resolved as one."
reconciliationErrorText (NotAnEditedOrphan path) =
  T.pack path <> " is not an edited orphan, so it cannot be resolved as one."
reconciliationErrorText (UpdateAborted path) =
  "The update was aborted at " <> T.pack path <> "."

-- | Count, never list, application ids the engine hands over bare: a digest
-- is not a name.
ownerCount :: Set.Set ApplicationId -> Text
ownerCount owners = count (Set.size owners) <> " other application(s)"

transactionErrorText :: TransactionError -> Text
transactionErrorText (InvalidTransactionPath path reason) = T.pack path <> ": " <> reason
transactionErrorText (TransactionStartFailed reason) = "the update transaction could not start: " <> reason
transactionErrorText (TransactionJournalMalformed path reason) =
  "the update journal " <> T.pack path <> " is malformed: " <> reason
transactionErrorText (TransactionUnjournaledPaths paths) =
  "these paths are not covered by the update journal: " <> T.intercalate ", " (map T.pack (Set.toAscList paths))
transactionErrorText (TransactionUnresolvedPaths paths) =
  "these paths are unresolved: " <> T.intercalate ", " (map T.pack (Set.toAscList paths))
transactionErrorText (TransactionStalePlan path _ _) =
  T.pack path <> " changed after planning"
transactionErrorText (TransactionApplyFailed reason rollback) =
  reason <> maybe "; the project was restored" ("; restoring the project also failed: " <>) rollback
transactionErrorText (TransactionRollbackFailed reason) = "restoring the project failed: " <> reason
transactionErrorText (TransactionCompletionFailed reason) = "finishing the update failed: " <> reason

summaryText :: ReconciliationSummary -> Text
summaryText summary =
  count (summary ^. #creates)
    <> " created, "
    <> count (summary ^. #updates)
    <> " updated, "
    <> count (summary ^. #safeDeletes)
    <> " deleted"

planLooksUnchanged :: UpdatePlan -> Bool
planLooksUnchanged plan =
  isNothing (plan ^. #manifestPreparation)
    && null (plan ^. #versionChanges)
    && null (plan ^. #migrations)
    && plan ^. #inputChanges . #overridden == 0
    && plan ^. #inputChanges . #newlyResolved == 0
    && plan ^. #inputChanges . #removed == 0
    && (summarizeCommandPlan (plan ^. #commandPlan)) ^. #willRun == 0
    && all isUnchanged (Map.elems (plan ^. #reconciliation . #files))
  where
    -- Kept in step with 'Seihou.CLI.Update.isUpdateNoOp': a file whose bytes
    -- are unchanged still counts as a change when this plan would record a
    -- different shared-write mode than the manifest holds, so @alreadyUpToDate@
    -- does not claim otherwise.
    isUnchanged (FileUnchanged desired _ _ prior) =
      maybe True (\record -> record ^. #sharedWriteMode == recordedSharedWriteMode (plan ^. #reconciliation . #applicationIds) desired prior) prior
    isUnchanged _ = False

count :: Int -> Text
count = T.pack . show

showText :: (Show a) => a -> Text
showText = T.pack . show
