module Seihou.CLI.Update.Render
  ( UpdateOutput (..),
    UpdatePlanView,
    UpdateResultView,
    UpdateErrorView,
    planOutput,
    resultOutput,
    errorOutput,
    renderUpdateHuman,
    encodeUpdateOutput,
  )
where

import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString.Lazy (ByteString)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text qualified as T
import Seihou.CLI.CommandExecution
  ( CommandDisposition (..),
    CommandPlan (..),
    CommandPlanSummary (..),
    PlannedCommand (..),
    summarizeCommandPlan,
  )
import Seihou.CLI.Update.Types
import Seihou.Core.Migration (MigrationPlan (..))
import Seihou.Core.Types
  ( ApplicationId (..),
    AppliedComposition (..),
    AppliedTarget (..),
    BaselineRef (..),
    CommandFingerprint (..),
    ModuleName (..),
    Operation (..),
    RecipeName (..),
    SHA256 (..),
    VarName (..),
  )
import Seihou.Engine.Reconcile
  ( DesiredFile (..),
    FileConflictChoice (..),
    FileReconciliation (..),
    OrphanChoice (..),
    ReconciliationPlan (..),
    ReconciliationSummary (..),
    ResolvedFileConflict (..),
    reconciliationSummary,
  )
import Seihou.Prelude

newtype UpdatePlanView = UpdatePlanView UpdatePlan

newtype UpdateResultView = UpdateResultView UpdateResult

newtype UpdateErrorView = UpdateErrorView UpdateError

data UpdateOutput
  = UpdatePlanOutput UpdatePlanView
  | UpdateAppliedOutput UpdateResultView
  | UpdateFailedOutput UpdateErrorView

planOutput :: UpdatePlan -> UpdateOutput
planOutput = UpdatePlanOutput . UpdatePlanView

resultOutput :: UpdateResult -> UpdateOutput
resultOutput = UpdateAppliedOutput . UpdateResultView

errorOutput :: UpdateError -> UpdateOutput
errorOutput = UpdateFailedOutput . UpdateErrorView

renderUpdateHuman :: Bool -> UpdateOutput -> Text
renderUpdateHuman _ (UpdatePlanOutput (UpdatePlanView plan)) =
  T.unlines $
    versionLines plan
      <> [ renderInputs plan.inputChanges,
           "Migrations:  " <> count (length plan.migrations) <> migrationCaveat plan,
           renderFiles (reconciliationSummary plan.reconciliation),
           renderCommands (summarizeCommandPlan plan.commandPlan)
         ]
      <> conflictLines plan.reconciliation
      <> warningLines plan.warnings
renderUpdateHuman _ (UpdateAppliedOutput (UpdateResultView result)) =
  T.unlines $
    [ "Updated " <> count (length result.updatedApplications) <> " application(s).",
      renderFiles result.fileSummary,
      "Commands:    "
        <> count result.commandSummary.executed
        <> " executed; "
        <> count result.commandSummary.skippedUnchanged
        <> " unchanged skipped; "
        <> count result.commandSummary.skippedDisabled
        <> " disabled"
    ]
      <> warningLines result.warnings
renderUpdateHuman _ (UpdateFailedOutput (UpdateErrorView err)) =
  "Update failed [" <> errorCode err <> "]: " <> errorMessage err <> "\n"

encodeUpdateOutput :: UpdateOutput -> ByteString
encodeUpdateOutput = encode . outputValue

outputValue :: UpdateOutput -> Value
outputValue (UpdatePlanOutput (UpdatePlanView plan)) =
  object
    [ "schemaVersion" .= (1 :: Int),
      "outcome" .= ("plan" :: Text),
      "alreadyUpToDate" .= planLooksUnchanged plan,
      "applications" .= map applicationIdText plan.applications,
      "versions" .= map versionValue plan.versionChanges,
      "inputs" .= inputValue plan.inputChanges,
      "migrations" .= map migrationValue plan.migrations,
      "files" .= map fileValue (Map.toAscList plan.reconciliation.files),
      "commands" .= map commandValue plan.commandPlan.commands,
      "warnings" .= map warningText plan.warnings
    ]
outputValue (UpdateAppliedOutput (UpdateResultView result)) =
  object
    [ "schemaVersion" .= (1 :: Int),
      "outcome" .= ("applied" :: Text),
      "applications" .= map (.unApplicationId) result.updatedApplications,
      "versions" .= map versionValue result.versions,
      "files" .= summaryValue result.fileSummary,
      "commands"
        .= object
          [ "executed" .= result.commandSummary.executed,
            "skippedUnchanged" .= result.commandSummary.skippedUnchanged,
            "skippedDisabled" .= result.commandSummary.skippedDisabled
          ],
      "touchedPaths" .= Set.toAscList result.touchedPaths,
      "warnings" .= map warningText result.warnings
    ]
outputValue (UpdateFailedOutput (UpdateErrorView err)) =
  object
    [ "schemaVersion" .= (1 :: Int),
      "outcome" .= ("error" :: Text),
      "error" .= object ["code" .= errorCode err, "message" .= errorMessage err]
    ]

versionLines :: UpdatePlan -> [Text]
versionLines plan
  | null plan.versionChanges = ["Versions:    unchanged"]
  | otherwise = map renderVersionChange plan.versionChanges

renderVersionChange :: VersionChange -> Text
renderVersionChange change =
  change.name
    <> "  "
    <> fromMaybe "unversioned" change.fromVersion
    <> " -> "
    <> fromMaybe "unversioned" change.toVersion
    <> if change.sameVersionContentChanged then " (content changed at same version)" else ""

renderInputs :: InputChangeSummary -> Text
renderInputs summary =
  "Inputs:      "
    <> count summary.reused
    <> " reused; "
    <> count summary.overridden
    <> " overridden; "
    <> count summary.newlyResolved
    <> " newly resolved; "
    <> count summary.removed
    <> " removed"

renderFiles :: ReconciliationSummary -> Text
renderFiles summary =
  "Files:       "
    <> count summary.creates
    <> " created; "
    <> count summary.updates
    <> " updated; "
    <> count summary.merged
    <> " merged; "
    <> count summary.unchanged
    <> " unchanged; "
    <> count summary.conflicts
    <> " conflicts; "
    <> count summary.safeDeletes
    <> " deleted; "
    <> count summary.editedOrphans
    <> " edited orphans"

renderCommands summary =
  "Commands:    "
    <> count summary.willRun
    <> " will run; "
    <> count summary.skippedUnchanged
    <> " unchanged skipped; "
    <> count summary.skippedDisabled
    <> " disabled"

migrationCaveat plan
  | any (.containsCommands) plan.migrations = " (includes non-simulatable commands)"
  | otherwise = ""

conflictLines :: ReconciliationPlan -> [Text]
conflictLines reconciliation = concatMap renderOne (Map.toAscList reconciliation.files)
  where
    renderOne (path, FileConflict _ _ _ reason _ _ resolution) =
      [ "Conflict:    "
          <> T.pack path
          <> " ("
          <> T.pack (show reason)
          <> maybe "; unresolved" (("; " <>) . resolutionText . (.choice)) resolution
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
    [ "name" .= change.name,
      "from" .= change.fromVersion,
      "to" .= change.toVersion,
      "sameVersionContentChanged" .= change.sameVersionContentChanged
    ]

inputValue :: InputChangeSummary -> Value
inputValue summary =
  object
    [ "reused" .= summary.reused,
      "overridden" .= summary.overridden,
      "newlyResolved" .= summary.newlyResolved,
      "removed" .= summary.removed,
      "ambiguousLegacy" .= map (.unVarName) summary.ambiguousLegacy
    ]

migrationValue :: PlannedUpdateMigration -> Value
migrationValue migration =
  object
    [ "module" .= migration.moduleName.unModuleName,
      "from" .= showText migration.sourcePlan.planFrom,
      "to" .= showText migration.sourcePlan.planTo,
      "steps" .= length migration.sourcePlan.planSteps,
      "containsCommands" .= migration.containsCommands
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
resolutionFor (FileConflict _ _ _ _ _ _ resolution) = resolutionText . (.choice) <$> resolution
resolutionFor (FileOrphanEdited _ _ _ _ choice) = orphanChoiceText <$> choice
resolutionFor _ = Nothing

commandValue :: PlannedCommand -> Value
commandValue planned =
  object
    [ "fingerprint" .= fingerprintText planned.fingerprint,
      "status" .= dispositionText planned.disposition,
      "module" .= commandModule planned.operation,
      "command" .= commandText planned.operation
    ]

commandModule :: Operation -> Maybe Text
commandModule RunCommandOp {moduleName} = Just moduleName.unModuleName
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
    [ "created" .= summary.creates,
      "updated" .= summary.updates,
      "merged" .= summary.merged,
      "unchanged" .= summary.unchanged,
      "conflicts" .= summary.conflicts,
      "safeDeletes" .= summary.safeDeletes,
      "editedOrphans" .= summary.editedOrphans,
      "sharedOwnership" .= summary.sharedOwnership
    ]

applicationIdText :: AppliedComposition -> Text
applicationIdText application = application.applicationId.unApplicationId

fingerprintText :: CommandFingerprint -> Text
fingerprintText (CommandFingerprint (SHA256 value)) = value

warningText :: UpdateWarning -> Text
warningText = T.pack . show

errorCode :: UpdateError -> Text
errorCode UpdateManifestMissing {} = "manifest_missing"
errorCode UpdateManifestUnreadable {} = "manifest_unreadable"
errorCode NoRecordedApplications = "no_recorded_applications"
errorCode LegacyUpdateRequiresOneTarget = "legacy_update_requires_one_target"
errorCode UpdateTargetNotFound {} = "target_not_found"
errorCode SharedPathRequiresApplications {} = "shared_path_requires_applications"
errorCode CandidateCloneFailed {} = "candidate_clone_failed"
errorCode CandidateRepositoryInvalid {} = "candidate_repository_invalid"
errorCode CandidateArtifactMissing {} = "candidate_artifact_missing"
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

errorMessage :: UpdateError -> Text
errorMessage (UpdateManifestMissing path) =
  "No Seihou manifest was found at " <> T.pack path <> ". Run seihou run first."
errorMessage (UpdateTargetNotFound target available) =
  "No recorded application matches '"
    <> target
    <> "'. Available targets: "
    <> T.intercalate ", " available
errorMessage (SharedPathRequiresApplications path selected required) =
  "Path "
    <> T.pack path
    <> " is also owned by application(s) "
    <> T.intercalate ", " (map (.unApplicationId) (Set.toAscList required))
    <> ". Select every owner or run seihou update with no targets. Selected: "
    <> T.intercalate ", " (map (.unApplicationId) (Set.toAscList selected))
errorMessage (UpdateHasUnresolvedPaths paths) =
  "Resolve these paths before apply: " <> T.intercalate ", " (map T.pack (Set.toAscList paths))
errorMessage (UpdatePlanStale paths) =
  "The project changed after planning: " <> T.intercalate ", " (map T.pack (Set.toAscList paths))
errorMessage err = T.pack (show err)

planLooksUnchanged :: UpdatePlan -> Bool
planLooksUnchanged plan =
  null plan.versionChanges
    && null plan.migrations
    && plan.inputChanges.overridden == 0
    && plan.inputChanges.newlyResolved == 0
    && plan.inputChanges.removed == 0
    && (summarizeCommandPlan plan.commandPlan).willRun == 0
    && all isUnchanged (Map.elems plan.reconciliation.files)
  where
    isUnchanged FileUnchanged {} = True
    isUnchanged _ = False

count :: Int -> Text
count = T.pack . show

showText :: (Show a) => a -> Text
showText = T.pack . show
