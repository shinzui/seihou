-- | The ordered, adjacent schema steps that take a raw
-- @.seihou/manifest.json@ document from any supported schema to a newer one.
--
-- Every semantic manifest change advances the schema and adds exactly one
-- @N -> N + 1@ step here
-- (docs/adr/0014-every-semantic-manifest-change-advances-the-schema-version.md).
-- A path is planned one adjacent step at a time, so a missing step is an
-- error rather than a silent jump, and a document's @version@ only ever
-- names the last step that actually ran.
--
-- Steps work on 'Aeson.Value' rather than 'Manifest' so that keys this build
-- does not model survive. Each step is classified: a lossless step is a
-- deterministic transform implemented here and may be staged by any command
-- that needs it; an inference-bearing step consults machine-local state and
-- is implemented only by the explicit @seihou manifest upgrade@ command in
-- @seihou-cli@ (docs/adr/0005-legacy-manifests-convert-through-an-explicit-command.md).
module Seihou.Manifest.Upgrade
  ( UpgradeStepAction (..),
    UpgradeStepKind (..),
    ManifestUpgradeStep (..),
    ManifestUpgradeError (..),
    oldestUpgradableManifestVersion,
    manifestUpgradeSteps,
    upgradeStepKind,
    planManifestUpgrade,
    planUpgradeWith,
    documentSchemaVersion,
    setDocumentSchemaVersion,
    applyLosslessUpgradeStep,
    upgradeDocumentLosslessly,
    makeSharedWriteEvidenceExplicit,
    renderManifestUpgradeError,
  )
where

import Control.Monad (foldM, unless)
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Generics.Labels ()
import Data.Text qualified as T
import Seihou.Core.Types
import Seihou.Manifest.Types (currentManifestVersion, sharedWriteModeToText)
import Seihou.Prelude

-- | What a step does to the document. The kind of each action is fixed by
-- 'upgradeStepKind', so a step cannot be declared lossless while doing
-- inference.
data UpgradeStepAction
  = -- | Only the version changes: every field the newer schema added decodes
    -- from its absence to the same default the older reader assumed.
    StampVersion
  | -- | Schema 5 to 6: machine-local @source@ and @targetSource@ paths
    -- become portable artifact origins. Implemented by the CLI.
    ConvertMachineLocalPaths
  | -- | Schema 6 to 7: the optional @additiveOnly@ Boolean becomes a
    -- required @sharedWriteMode@ on every file record.
    MakeSharedWriteEvidenceExplicit
  deriving stock (Eq, Ord, Show, Enum, Bounded, Generic)

-- | Whether a step may be staged automatically.
data UpgradeStepKind
  = -- | Deterministic and loses nothing; may be staged by a command that
    -- requires the newer schema and committed atomically with its result.
    LosslessUpgrade
  | -- | Consults machine-local state or chooses among plausible answers;
    -- only the explicit, reviewable @seihou manifest upgrade@ runs it.
    InferenceBearingUpgrade
  deriving stock (Eq, Ord, Show, Enum, Bounded, Generic)

-- | One adjacent schema step.
data ManifestUpgradeStep = ManifestUpgradeStep
  { fromVersion :: !ManifestSchemaVersion,
    toVersion :: !ManifestSchemaVersion,
    action :: !UpgradeStepAction,
    -- | A short description for upgrade reports.
    summary :: !Text
  }
  deriving stock (Eq, Show, Generic)

data ManifestUpgradeError
  = -- | The document has no integer @version@, or is not an object.
    UnreadableSchemaVersion Text
  | -- | Older than any schema this build knows how to upgrade.
    SourceVersionUnsupported ManifestSchemaVersion
  | -- | Written by a newer seihou than this one.
    SourceNewerThanBinary ManifestSchemaVersion
  | -- | Asked for a schema this build does not know.
    TargetAboveCurrent ManifestSchemaVersion
  | -- | Asked to go backwards: source, then requested target.
    TargetBelowSource ManifestSchemaVersion ManifestSchemaVersion
  | -- | No step starts at this version.
    MissingUpgradeStep ManifestSchemaVersion
  | -- | A lossless run reached a step only the explicit command may run.
    StepRequiresInference ManifestUpgradeStep
  | -- | A step was applied to a document at a different version.
    StepVersionMismatch ManifestUpgradeStep ManifestSchemaVersion
  | -- | The document did not have the shape its version promises.
    MalformedDocument ManifestSchemaVersion Text
  deriving stock (Eq, Show, Generic)

-- | The oldest schema any step starts from.
oldestUpgradableManifestVersion :: ManifestSchemaVersion
oldestUpgradableManifestVersion = ManifestSchemaVersion 1

-- | Every adjacent step, oldest first. Adding a schema version means adding
-- exactly one entry here; the test suite plans a path from every supported
-- version to 'currentManifestVersion', so a forgotten step fails it.
manifestUpgradeSteps :: [ManifestUpgradeStep]
manifestUpgradeSteps =
  [ step 1 StampVersion "per-instance parent variables",
    step 2 StampVersion "applied blueprint record",
    step 3 StampVersion "reproducible applications and generated baselines",
    step 4 StampVersion "blueprint migration receipts",
    step 5 ConvertMachineLocalPaths "portable artifact origins",
    step 6 MakeSharedWriteEvidenceExplicit "explicit shared-write evidence"
  ]
  where
    step from stepAction =
      ManifestUpgradeStep (ManifestSchemaVersion from) (ManifestSchemaVersion (from + 1)) stepAction

upgradeStepKind :: UpgradeStepAction -> UpgradeStepKind
upgradeStepKind StampVersion = LosslessUpgrade
upgradeStepKind ConvertMachineLocalPaths = InferenceBearingUpgrade
upgradeStepKind MakeSharedWriteEvidenceExplicit = LosslessUpgrade

-- | The contiguous steps from @source@ to @target@. Planning from a version
-- to itself is an empty path.
planManifestUpgrade ::
  ManifestSchemaVersion ->
  ManifestSchemaVersion ->
  Either ManifestUpgradeError [ManifestUpgradeStep]
planManifestUpgrade = planUpgradeWith manifestUpgradeSteps currentManifestVersion

-- | 'planManifestUpgrade' over an explicit step table and current version,
-- so the gap check itself can be tested.
planUpgradeWith ::
  [ManifestUpgradeStep] ->
  ManifestSchemaVersion ->
  ManifestSchemaVersion ->
  ManifestSchemaVersion ->
  Either ManifestUpgradeError [ManifestUpgradeStep]
planUpgradeWith steps current source target
  | source > current = Left (SourceNewerThanBinary source)
  | source < oldestUpgradableManifestVersion = Left (SourceVersionUnsupported source)
  | target > current = Left (TargetAboveCurrent target)
  | target < source = Left (TargetBelowSource source target)
  | otherwise = walk source
  where
    walk version
      | version == target = Right []
      | otherwise = case [candidate | candidate <- steps, candidate ^. #fromVersion == version] of
          [found]
            | found ^. #toVersion == nextVersion version -> (found :) <$> walk (nextVersion version)
          _ -> Left (MissingUpgradeStep version)
    nextVersion (ManifestSchemaVersion v) = ManifestSchemaVersion (v + 1)

-- | Read a raw document's top-level @version@.
documentSchemaVersion :: Aeson.Value -> Either ManifestUpgradeError ManifestSchemaVersion
documentSchemaVersion (Aeson.Object fields) = case KeyMap.lookup "version" fields of
  Just value | Aeson.Success v <- Aeson.fromJSON value -> Right (ManifestSchemaVersion v)
  Just _ -> Left (UnreadableSchemaVersion "the \"version\" field is not an integer")
  Nothing -> Left (UnreadableSchemaVersion "the manifest has no \"version\" field")
documentSchemaVersion _ = Left (UnreadableSchemaVersion "the manifest is not a JSON object")

-- | Replace a raw document's top-level @version@, keeping every other key.
setDocumentSchemaVersion :: ManifestSchemaVersion -> Aeson.Value -> Aeson.Value
setDocumentSchemaVersion version (Aeson.Object fields) =
  Aeson.Object (KeyMap.insert "version" (Aeson.toJSON (version ^. #unManifestSchemaVersion)) fields)
setDocumentSchemaVersion _ other = other

-- | Run one lossless step. The document must be at the step's source
-- version; the version is advanced only after the transform succeeds.
applyLosslessUpgradeStep :: ManifestUpgradeStep -> Aeson.Value -> Either ManifestUpgradeError Aeson.Value
applyLosslessUpgradeStep upgradeStep document = do
  actual <- documentSchemaVersion document
  unless (actual == upgradeStep ^. #fromVersion) $
    Left (StepVersionMismatch upgradeStep actual)
  transformed <- case upgradeStep ^. #action of
    StampVersion -> Right document
    MakeSharedWriteEvidenceExplicit ->
      first (MalformedDocument actual) (makeSharedWriteEvidenceExplicit document)
    ConvertMachineLocalPaths -> Left (StepRequiresInference upgradeStep)
  pure (setDocumentSchemaVersion (upgradeStep ^. #toVersion) transformed)

-- | Upgrade a raw document to @target@ using lossless steps only. Stops with
-- 'StepRequiresInference' before changing anything if the path crosses an
-- inference-bearing step. Returns the steps that ran with the result.
upgradeDocumentLosslessly ::
  ManifestSchemaVersion ->
  Aeson.Value ->
  Either ManifestUpgradeError ([ManifestUpgradeStep], Aeson.Value)
upgradeDocumentLosslessly target document = do
  source <- documentSchemaVersion document
  steps <- planManifestUpgrade source target
  case [s | s <- steps, upgradeStepKind (s ^. #action) == InferenceBearingUpgrade] of
    blocked : _ -> Left (StepRequiresInference blocked)
    [] -> (steps,) <$> foldM (flip applyLosslessUpgradeStep) document steps

-- | The schema 6 to 7 transform. Every file record gains a required
-- @sharedWriteMode@: an explicit @additiveOnly: true@ becomes
-- @additive-only@, and anything else becomes @unknown@, because schema 6
-- omitted @false@ and absence therefore proves nothing. The old key is
-- removed; every other member at every level is kept.
makeSharedWriteEvidenceExplicit :: Aeson.Value -> Either Text Aeson.Value
makeSharedWriteEvidenceExplicit (Aeson.Object fields) = case KeyMap.lookup "files" fields of
  Just (Aeson.Object records) -> do
    converted <- KeyMap.traverseWithKey convertRecord records
    Right (Aeson.Object (KeyMap.insert "files" (Aeson.Object converted) fields))
  Just _ -> Left "\"files\" is not an object"
  Nothing -> Left "the manifest has no \"files\" object"
  where
    convertRecord path (Aeson.Object record) = do
      mode <- case KeyMap.lookup "additiveOnly" record of
        Nothing -> Right SharedWriteUnknown
        Just (Aeson.Bool True) -> Right SharedWriteAdditiveOnly
        Just (Aeson.Bool False) -> Right SharedWriteUnknown
        Just _ -> Left ("file record " <> Key.toText path <> ": \"additiveOnly\" is not a Boolean")
      Right
        ( Aeson.Object
            ( KeyMap.insert "sharedWriteMode" (Aeson.String (sharedWriteModeToText mode)) $
                KeyMap.delete "additiveOnly" record
            )
        )
    convertRecord path _ = Left ("file record " <> Key.toText path <> " is not an object")
makeSharedWriteEvidenceExplicit _ = Left "the manifest is not a JSON object"

renderManifestUpgradeError :: ManifestUpgradeError -> Text
renderManifestUpgradeError err = case err of
  UnreadableSchemaVersion reason -> "cannot read the manifest schema version: " <> reason
  SourceVersionUnsupported v -> "manifest schema " <> showVersion v <> " is older than any schema seihou can upgrade"
  SourceNewerThanBinary v ->
    "manifest schema "
      <> showVersion v
      <> " was written by a newer seihou; this build understands up to schema "
      <> showVersion currentManifestVersion
  TargetAboveCurrent v ->
    "schema "
      <> showVersion v
      <> " is newer than this build supports (up to "
      <> showVersion currentManifestVersion
      <> ")"
  TargetBelowSource source target ->
    "cannot upgrade from schema " <> showVersion source <> " to the older schema " <> showVersion target
  MissingUpgradeStep v -> "no upgrade step is defined from schema " <> showVersion v
  StepRequiresInference s ->
    "upgrading from schema "
      <> showVersion (s ^. #fromVersion)
      <> " to "
      <> showVersion (s ^. #toVersion)
      <> " ("
      <> s ^. #summary
      <> ") needs review; run 'seihou manifest upgrade'"
  StepVersionMismatch s actual ->
    "the "
      <> showVersion (s ^. #fromVersion)
      <> " -> "
      <> showVersion (s ^. #toVersion)
      <> " step cannot run on a schema-"
      <> showVersion actual
      <> " document"
  MalformedDocument v reason -> "the schema-" <> showVersion v <> " manifest is malformed: " <> reason
  where
    showVersion (ManifestSchemaVersion v) = T.pack (show v)
