module Seihou.Manifest.Types
  ( emptyManifest,
    currentManifestVersion,
    oldestDecodableManifestVersion,
    minimumManifestVersion,
    manifestSupports,
    sharedWriteModeToText,
    sharedWriteModeFromText,
    manifestToJSON,
    manifestFromJSON,
    writeAppliedBlueprint,
    writeAppliedBlueprintMigration,
    hasAppliedBlueprintMigration,
    artifactOriginName,
  )
where

import Data.Aeson (FromJSON (..), ToJSON (..), (.:), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.Types qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Time (UTCTime)
import Seihou.Core.ArtifactIdentity (sameArtifactIdentity)
import Seihou.Core.Types
import Seihou.Manifest.Hash (baselineRefFromText)
import Seihou.Prelude hiding ((.=))
import System.FilePath (takeFileName)

-- | Current manifest schema version.
--
-- Bumped from 1 to 2 when 'AppliedModule' gained the @parentVars@ field
-- (see docs/plans/10-parameterized-dep-multi-instantiation.md). Version-1
-- manifests remain readable because the decoder treats a missing
-- @parentVars@ key as 'emptyParentVars'.
--
-- Bumped from 2 to 3 when 'Manifest' gained the optional @blueprint@
-- field (see docs/plans/32-blueprint-manifest-and-status.md).
-- Schema-2 manifests remain readable because the decoder treats a
-- missing @blueprint@ key as 'Nothing'.
--
-- Bumped from 3 to 4 when 'Manifest' gained reproducible applications
-- and 'FileRecord' gained generated-baseline and application ownership.
-- Older manifests remain readable because every new field has an empty
-- or absent default.
--
-- Bumped from 4 to 5 when 'Manifest' gained the durable
-- @blueprintMigrations@ receipt ledger. A missing ledger decodes as empty.
--
-- Bumped from 5 to 6 when every recorded artifact reference gained a
-- portable @origin@ and the machine-specific @source@ / @targetSource@
-- absolute paths were dropped from the serialized form
-- (see docs/plans/76-record-portable-artifact-origins-in-the-manifest.md).
-- Version-5-and-earlier manifests are not readable directly; see
-- docs/plans/79-upgrade-legacy-absolute-path-manifests-in-place.md.
--
-- Bumped from 6 to 7 when every 'FileRecord' gained a required
-- @sharedWriteMode@ (see
-- docs/plans/92-define-manifest-schema-capabilities-and-ordered-upgrade-steps.md).
-- Schema 6 carried the same fact as an optional @additiveOnly@ Boolean that
-- was emitted only when true, so an absent key meant both "an owner rewrites
-- the whole file" and "this manifest predates the question". Schema 6 still
-- decodes directly: @additiveOnly: true@ becomes 'SharedWriteAdditiveOnly'
-- and anything else becomes 'SharedWriteUnknown'. The adjacent raw-document
-- step lives in "Seihou.Manifest.Upgrade"; the rule that every semantic
-- change advances this number is
-- docs/adr/0014-every-semantic-manifest-change-advances-the-schema-version.md.
currentManifestVersion :: ManifestSchemaVersion
currentManifestVersion = ManifestSchemaVersion 7

-- | The oldest schema the ordinary decoder reads. Anything older records
-- machine-specific absolute paths and must go through the explicit
-- @seihou manifest upgrade@ conversion first.
oldestDecodableManifestVersion :: ManifestSchemaVersion
oldestDecodableManifestVersion = ManifestSchemaVersion 6

-- | The oldest schema that can express the facts a capability relies on.
-- This is the only place a feature's manifest requirement is written down;
-- commands ask 'manifestSupports' instead of comparing version numbers.
minimumManifestVersion :: ManifestCapability -> ManifestSchemaVersion
minimumManifestVersion TargetedAdditiveSharedPathUpdate = ManifestSchemaVersion 7

-- | Whether a manifest's schema can express everything a capability needs.
-- A decoded schema-6 manifest answers 'False' for
-- 'TargetedAdditiveSharedPathUpdate' even though its records carry an
-- explicit 'SharedWriteUnknown', because the file itself does not say so.
manifestSupports :: ManifestCapability -> Manifest -> Bool
manifestSupports capability manifest =
  manifest ^. #version >= minimumManifestVersion capability

-- | Create an empty manifest with the given timestamp.
emptyManifest :: UTCTime -> Manifest
emptyManifest now =
  Manifest
    { version = currentManifestVersion,
      genAt = now,
      modules = [],
      vars = Map.empty,
      files = Map.empty,
      applications = [],
      recipe = Nothing,
      blueprint = Nothing,
      blueprintMigrations = []
    }

-- | Record an applied-blueprint provenance on a manifest, replacing any
-- prior entry. Re-running @seihou agent run@ overwrites the recorded
-- blueprint, mirroring the way 'Manifest.recipe' is overwritten when a
-- recipe is re-applied.
writeAppliedBlueprint :: AppliedBlueprint -> Manifest -> Manifest
writeAppliedBlueprint ab m =
  Manifest
    { version = m ^. #version,
      genAt = m ^. #genAt,
      modules = m ^. #modules,
      vars = m ^. #vars,
      files = m ^. #files,
      applications = m ^. #applications,
      recipe = m ^. #recipe,
      blueprint = Just ab,
      blueprintMigrations = m ^. #blueprintMigrations
    }

-- | Insert or replace one exact blueprint migration receipt. Replacement is
-- performed in place, while adding a v5-only receipt upgrades the manifest
-- version and preserves every unrelated field.
--
-- The receipt's 'outcome' is deliberately excluded from the edge comparison,
-- which is the one place it is left out of one. An edge that reported itself
-- not applicable and later runs for real must replace its earlier receipt, not
-- accumulate a second one for the same edge.
writeAppliedBlueprintMigration :: AppliedBlueprintMigration -> Manifest -> Manifest
writeAppliedBlueprintMigration receipt manifest =
  Manifest
    { version = currentManifestVersion,
      genAt = manifest ^. #genAt,
      modules = manifest ^. #modules,
      vars = manifest ^. #vars,
      files = manifest ^. #files,
      applications = manifest ^. #applications,
      recipe = manifest ^. #recipe,
      blueprint = manifest ^. #blueprint,
      blueprintMigrations = upsert (manifest ^. #blueprintMigrations)
    }
  where
    sameEdge existing =
      sameArtifactIdentity (existing ^. #origin) (receipt ^. #origin)
        && existing ^. #name == receipt ^. #name
        && existing ^. #fromVersion == receipt ^. #fromVersion
        && existing ^. #toVersion == (receipt ^. #toVersion)

    upsert receipts
      | any sameEdge receipts = map (\existing -> if sameEdge existing then receipt else existing) receipts
      | otherwise = receipts <> [receipt]

-- | Whether one exact blueprint migration edge has been applied.
--
-- The edge is identified by the origin and name of the blueprint that owns it
-- together with its @from@ and @to@ versions, and only a receipt whose outcome
-- is 'MigrationApplied' counts — matching the completion key
-- 'Seihou.CLI.BlueprintMigration.pendingBlueprintMigrations' applies when it
-- decides what is still pending. The two must agree, or an edge could be
-- reported here as done while the planner still schedules it.
--
-- This is deliberately a different comparison from
-- 'writeAppliedBlueprintMigration'’s: that one identifies the edge in order to
-- upsert its receipt and so ignores the outcome, while this one answers
-- whether the work happened.
hasAppliedBlueprintMigration :: ArtifactOrigin -> ModuleName -> Text -> Text -> Manifest -> Bool
hasAppliedBlueprintMigration blueprintOrigin blueprintName fromVersion toVersion manifest =
  any
    ( \receipt ->
        receipt ^. #outcome == MigrationApplied
          && sameArtifactIdentity (receipt ^. #origin) blueprintOrigin
          && receipt ^. #name == blueprintName
          && receipt ^. #fromVersion == fromVersion
          && receipt ^. #toVersion == toVersion
    )
    (manifest ^. #blueprintMigrations)

-- | Encode a manifest to JSON bytes.
manifestToJSON :: Manifest -> LBS.ByteString
manifestToJSON = Aeson.encode

-- | Decode a manifest from JSON bytes.
manifestFromJSON :: LBS.ByteString -> Either String Manifest
manifestFromJSON = Aeson.eitherDecode

-- JSON instances

instance ToJSON Manifest where
  toJSON m =
    Aeson.object $
      [ "version" .= (m ^. #version),
        "generatedAt" .= (m ^. #genAt),
        "modules" .= (m ^. #modules),
        "variables" .= varsToJSON (m ^. #vars),
        "files" .= filesToJSON (m ^. #version) (m ^. #files),
        "applications" .= (m ^. #applications),
        "blueprintMigrations" .= (m ^. #blueprintMigrations)
      ]
        ++ maybe [] (\r -> ["recipe" .= r]) (m ^. #recipe)
        ++ maybe [] (\b -> ["blueprint" .= b]) (m ^. #blueprint)

-- | The version is read and checked before anything else, because the
-- file-record representation depends on it.
instance FromJSON Manifest where
  parseJSON = Aeson.withObject "Manifest" $ \o -> do
    v <- o .: "version"
    checkManifestVersion v
    Manifest
      <$> pure v
      <*> o .: "generatedAt"
      <*> o .: "modules"
      <*> (varsFromJSON =<< o .: "variables")
      <*> (filesFromJSON v =<< o .: "files")
      <*> o Aeson..:? "applications" Aeson..!= []
      <*> o Aeson..:? "recipe"
      <*> o Aeson..:? "blueprint"
      <*> o Aeson..:? "blueprintMigrations" Aeson..!= []

-- | Reject a manifest this build cannot read, naming the remedy.
--
-- Schema-5-and-earlier manifests carry an absolute @source@ path in place of
-- the portable @origin@; converting them is an inference that stays behind
-- the explicit @seihou manifest upgrade@ command
-- (docs/adr/0005-legacy-manifests-convert-through-an-explicit-command.md),
-- so they fail here rather than being silently misread.
checkManifestVersion :: ManifestSchemaVersion -> Aeson.Parser ()
checkManifestVersion v
  | v > currentManifestVersion =
      fail "manifest was created by a newer version of seihou"
  | v < oldestDecodableManifestVersion =
      fail
        ( "this manifest uses schema version "
            <> show (v ^. #unManifestSchemaVersion)
            <> ", which records machine-specific absolute paths; run "
            <> "'seihou manifest upgrade' to convert it"
        )
  | otherwise = pure ()

instance ToJSON ManifestSchemaVersion where
  toJSON (ManifestSchemaVersion v) = toJSON v

instance FromJSON ManifestSchemaVersion where
  parseJSON value = ManifestSchemaVersion <$> parseJSON value

instance ToJSON AppliedTarget where
  toJSON (AppliedModuleTarget name) =
    Aeson.object ["kind" .= ("module" :: Text), "name" .= (name ^. #unModuleName)]
  toJSON (AppliedRecipeTarget name) =
    Aeson.object ["kind" .= ("recipe" :: Text), "name" .= (name ^. #unRecipeName)]

instance FromJSON AppliedTarget where
  parseJSON = Aeson.withObject "AppliedTarget" $ \o -> do
    kind <- o .: "kind" :: Aeson.Parser Text
    name <- o .: "name"
    case kind of
      "module" -> pure (AppliedModuleTarget (ModuleName name))
      "recipe" -> pure (AppliedRecipeTarget (RecipeName name))
      other -> fail ("unknown applied target kind: " <> T.unpack other)

-- | Machine-independent artifact references are encoded as a tagged object
-- so a manifest diff stays readable and so future constructors can be added
-- without breaking the shape.
instance ToJSON ArtifactOrigin where
  toJSON (RemoteOrigin url artifact repo) =
    Aeson.object $
      [ "kind" .= ("remote" :: Text),
        "url" .= url,
        "artifact" .= artifact
      ]
        ++ maybe [] (\value -> ["repo" .= value]) repo
  toJSON (ProjectOrigin path) =
    Aeson.object
      [ "kind" .= ("project" :: Text),
        "path" .= T.pack path
      ]
  toJSON (LocalOrigin artifact) =
    Aeson.object
      [ "kind" .= ("local" :: Text),
        "artifact" .= artifact
      ]

instance FromJSON ArtifactOrigin where
  parseJSON = Aeson.withObject "ArtifactOrigin" $ \o -> do
    kind <- o .: "kind" :: Aeson.Parser Text
    case kind of
      "remote" ->
        RemoteOrigin
          <$> o .: "url"
          <*> o .: "artifact"
          <*> o Aeson..:? "repo"
      "project" -> ProjectOrigin . T.unpack <$> o .: "path"
      "local" -> LocalOrigin <$> o .: "artifact"
      other -> fail ("unknown artifact origin kind: " <> T.unpack other)

-- | The artifact name an origin refers to, for display and for matching
-- against a discovered artifact. 'ProjectOrigin' derives it from the last
-- path segment, which is how @.seihou\/modules\/\<name\>@ is laid out.
artifactOriginName :: ArtifactOrigin -> Text
artifactOriginName (RemoteOrigin _ artifact _) = artifact
artifactOriginName (LocalOrigin artifact) = artifact
artifactOriginName (ProjectOrigin path) = T.pack (takeFileName path)

-- | The origin to use for a record written before 'ArtifactOrigin' reached the
-- agent-applied records — the blueprint, blueprint-migration and recipe
-- entries, all of which carried a bare name until
-- docs\/plans\/81-record-artifact-origin-for-agent-applied-artifacts.md.
--
-- Where the artifact actually came from is genuinely unrecoverable: nothing on
-- disk says which repository a receipt written last month was resolved from.
-- 'LocalOrigin' is the constructor that already means "provenance seihou
-- cannot verify", so decoding to it is honest rather than a fabrication, and
-- it keeps every older manifest readable without an explicit conversion pass
-- (see docs\/adr\/0005-legacy-manifests-convert-through-an-explicit-command.md,
-- whose explicit-command rule exists for conversions that lose or relocate
-- information; this one loses nothing).
legacyLocalOrigin :: Text -> Maybe ArtifactOrigin -> ArtifactOrigin
legacyLocalOrigin recordedName = fromMaybe (LocalOrigin recordedName)

instance ToJSON AppliedInstanceState where
  toJSON state =
    Aeson.object $
      [ "name" .= (state ^. #name . #unModuleName),
        "origin" .= (state ^. #origin),
        "resolvedVars" .= varsToJSON (state ^. #resolvedVars)
      ]
        ++ parentVarsField (state ^. #parentVars)
        ++ maybe [] (\v -> ["version" .= v]) (state ^. #moduleVersion)
    where
      parentVarsField (ParentVars m)
        | Map.null m = []
        | otherwise = ["parentVars" .= parentVarsMapToJSON m]

instance FromJSON AppliedInstanceState where
  parseJSON = Aeson.withObject "AppliedInstanceState" $ \o -> do
    mParentVars <- o Aeson..:? "parentVars"
    pv <- case mParentVars of
      Nothing -> pure emptyParentVars
      Just value -> ParentVars <$> parentVarsMapFromJSON value
    AppliedInstanceState
      <$> (ModuleName <$> o .: "name")
      <*> pure pv
      <*> o .: "origin"
      <*> o Aeson..:? "version"
      <*> (varsFromJSON =<< o Aeson..:? "resolvedVars" Aeson..!= Aeson.object [])

instance ToJSON AppliedComposition where
  toJSON composition =
    Aeson.object $
      [ "applicationId" .= (composition ^. #applicationId . #unApplicationId),
        "target" .= (composition ^. #target),
        "targetOrigin" .= (composition ^. #targetOrigin),
        "additionalModules" .= map (^. #unModuleName) (composition ^. #additionalModules),
        "instances" .= (composition ^. #instances),
        "appliedAt" .= (composition ^. #appliedAt)
      ]
        ++ maybe [] (\v -> ["targetVersion" .= v]) (composition ^. #targetVersion)
        ++ maybe [] (\v -> ["namespace" .= v]) (composition ^. #namespace)
        ++ maybe [] (\v -> ["context" .= v]) (composition ^. #context)
        ++ commandReceiptsField (composition ^. #commandReceipts)
    where
      commandReceiptsField receipts
        | Map.null receipts = []
        | otherwise = ["commandReceipts" .= commandReceiptsToJSON receipts]

instance FromJSON AppliedComposition where
  parseJSON = Aeson.withObject "AppliedComposition" $ \o ->
    AppliedComposition
      <$> (ApplicationId <$> o .: "applicationId")
      <*> o .: "target"
      <*> o .: "targetOrigin"
      <*> o Aeson..:? "targetVersion"
      <*> (map ModuleName <$> o Aeson..:? "additionalModules" Aeson..!= [])
      <*> o Aeson..:? "namespace"
      <*> o Aeson..:? "context"
      <*> o Aeson..:? "instances" Aeson..!= []
      <*> (commandReceiptsFromJSON =<< o Aeson..:? "commandReceipts" Aeson..!= Aeson.object [])
      <*> o .: "appliedAt"

instance ToJSON CommandReceipt where
  toJSON receipt =
    Aeson.object $
      [ "fingerprint" .= commandFingerprintText (receipt ^. #fingerprint),
        "module" .= (receipt ^. #moduleName . #unModuleName),
        "command" .= (receipt ^. #command),
        "completedAt" .= (receipt ^. #completedAt)
      ]
        ++ maybe [] (\path -> ["workDir" .= path]) (receipt ^. #workDir)

instance FromJSON CommandReceipt where
  parseJSON = Aeson.withObject "CommandReceipt" $ \o ->
    CommandReceipt
      <$> (CommandFingerprint . SHA256 <$> o .: "fingerprint")
      <*> (ModuleName <$> o .: "module")
      <*> o .: "command"
      <*> o Aeson..:? "workDir"
      <*> o .: "completedAt"

instance ToJSON AppliedRecipe where
  toJSON ar =
    Aeson.object $
      [ "name" .= (ar ^. #name . #unRecipeName),
        "origin" .= (ar ^. #origin),
        "appliedAt" .= (ar ^. #appliedAt)
      ]
        ++ maybe [] (\v -> ["version" .= v]) (ar ^. #recipeVersion)

instance FromJSON AppliedRecipe where
  parseJSON = Aeson.withObject "AppliedRecipe" $ \o -> do
    name <- RecipeName <$> o .: "name"
    origin <- legacyLocalOrigin (name ^. #unRecipeName) <$> o Aeson..:? "origin"
    AppliedRecipe name origin
      <$> o Aeson..:? "version"
      <*> o .: "appliedAt"

instance ToJSON AppliedBlueprint where
  toJSON ab =
    Aeson.object $
      [ "name" .= (ab ^. #name . #unModuleName),
        "origin" .= (ab ^. #origin),
        "appliedAt" .= (ab ^. #appliedAt),
        "baselineModules" .= map (^. #unModuleName) (ab ^. #baselineModules),
        "noBaseline" .= (ab ^. #noBaseline)
      ]
        ++ maybe [] (\v -> ["version" .= v]) (ab ^. #blueprintVersion)
        ++ maybe [] (\p -> ["userPrompt" .= p]) (ab ^. #userPrompt)
        ++ maybe [] (\s -> ["agentSessionId" .= s]) (ab ^. #agentSessionId)

instance FromJSON AppliedBlueprint where
  parseJSON = Aeson.withObject "AppliedBlueprint" $ \o -> do
    name <- ModuleName <$> o .: "name"
    origin <- legacyLocalOrigin (name ^. #unModuleName) <$> o Aeson..:? "origin"
    AppliedBlueprint name origin
      <$> o Aeson..:? "version"
      <*> o .: "appliedAt"
      <*> (map ModuleName <$> o Aeson..:? "baselineModules" Aeson..!= [])
      <*> o Aeson..:? "noBaseline" Aeson..!= False
      <*> o Aeson..:? "userPrompt"
      <*> o Aeson..:? "agentSessionId"

-- | A nested object with a discriminator, matching 'ArtifactOrigin', because
-- the not-applicable case carries a reason and a bare string would have
-- nowhere to put it.
instance ToJSON MigrationOutcome where
  toJSON MigrationApplied =
    Aeson.object ["status" .= ("applied" :: Text)]
  toJSON (MigrationNotApplicable reason) =
    Aeson.object
      [ "status" .= ("not-applicable" :: Text),
        "reason" .= reason
      ]

instance FromJSON MigrationOutcome where
  parseJSON = Aeson.withObject "MigrationOutcome" $ \o -> do
    status <- o .: "status" :: Aeson.Parser Text
    case status of
      "applied" -> pure MigrationApplied
      "not-applicable" -> MigrationNotApplicable <$> o Aeson..:? "reason" Aeson..!= unstatedReason
      other -> fail ("unknown blueprint migration outcome: " <> T.unpack other)

-- | Stand-in for a not-applicable outcome whose reason is missing. An edge
-- that reports itself skipped always supplies one, so this only covers a
-- hand-edited manifest.
unstatedReason :: Text
unstatedReason = "(no reason recorded)"

instance ToJSON AppliedBlueprintMigration where
  toJSON receipt =
    Aeson.object $
      [ "name" .= (receipt ^. #name . #unModuleName),
        "origin" .= (receipt ^. #origin),
        "from" .= (receipt ^. #fromVersion),
        "to" .= (receipt ^. #toVersion),
        "outcome" .= (receipt ^. #outcome),
        "appliedAt" .= (receipt ^. #appliedAt)
      ]
        ++ maybe [] (\version -> ["version" .= version]) (receipt ^. #blueprintVersion)
        ++ maybe [] (\sessionId -> ["agentSessionId" .= sessionId]) (receipt ^. #agentSessionId)

instance FromJSON AppliedBlueprintMigration where
  parseJSON = Aeson.withObject "AppliedBlueprintMigration" $ \o -> do
    name <- ModuleName <$> o .: "name"
    origin <- legacyLocalOrigin (name ^. #unModuleName) <$> o Aeson..:? "origin"
    AppliedBlueprintMigration name origin
      <$> o Aeson..:? "version"
      <*> o .: "from"
      <*> o .: "to"
      -- A receipt written before the field existed records an edge whose
      -- session returned, which is exactly what 'MigrationApplied' means, so
      -- reading it that way preserves its meaning rather than inventing one.
      <*> o Aeson..:? "outcome" Aeson..!= MigrationApplied
      <*> o .: "appliedAt"
      <*> o Aeson..:? "agentSessionId"

instance ToJSON AppliedModule where
  toJSON am =
    Aeson.object $
      [ "name" .= (am ^. #name . #unModuleName),
        "origin" .= (am ^. #origin),
        "appliedAt" .= (am ^. #appliedAt)
      ]
        ++ parentVarsField (am ^. #parentVars)
        ++ maybe [] (\v -> ["version" .= v]) (am ^. #moduleVersion)
        ++ maybe [] (\r -> ["removal" .= removalToJSON r]) (am ^. #removal)
    where
      parentVarsField (ParentVars m)
        | Map.null m = []
        | otherwise = ["parentVars" .= parentVarsMapToJSON m]

instance FromJSON AppliedModule where
  parseJSON = Aeson.withObject "AppliedModule" $ \o -> do
    -- Backwards compatibility: old manifests have "removable" :: Bool.
    -- "removable": true -> Just (Removal [] [])
    -- "removable": false or absent, and no "removal" -> Nothing
    mRemoval <- o Aeson..:? "removal"
    removal <- case mRemoval of
      Just v -> Just <$> parseRemovalJSON v
      Nothing -> do
        oldRemovable <- o Aeson..:? "removable" Aeson..!= False
        pure (if oldRemovable then Just (Removal [] []) else Nothing)
    -- Schema v1 manifests omit parentVars entirely; decode those as empty.
    mParentVars <- o Aeson..:? "parentVars"
    pv <- case mParentVars of
      Nothing -> pure emptyParentVars
      Just v -> ParentVars <$> parentVarsMapFromJSON v
    AppliedModule
      <$> (ModuleName <$> o .: "name")
      <*> pure pv
      <*> o .: "origin"
      <*> o Aeson..:? "version"
      <*> o .: "appliedAt"
      <*> pure removal

parentVarsMapToJSON :: Map VarName Text -> Aeson.Value
parentVarsMapToJSON = toJSON . Map.mapKeys (^. #unVarName)

parentVarsMapFromJSON :: Aeson.Value -> Aeson.Parser (Map VarName Text)
parentVarsMapFromJSON v = do
  m <- parseJSON v :: Aeson.Parser (Map Text Text)
  pure (Map.mapKeys VarName m)

-- | Encode a Removal to JSON.
removalToJSON :: Removal -> Aeson.Value
removalToJSON r =
  Aeson.object
    [ "steps" .= map removalStepToJSON (r ^. #steps),
      "commands" .= map removalCommandToJSON (r ^. #commands)
    ]

removalStepToJSON :: RemovalStep -> Aeson.Value
removalStepToJSON s =
  Aeson.object $
    [ "action" .= removalActionToText (s ^. #action),
      "dest" .= (s ^. #dest)
    ]
      ++ maybe [] (\p -> ["src" .= p]) (s ^. #src)

removalActionToText :: RemovalAction -> Text
removalActionToText RemoveFileAction = "remove-file"
removalActionToText RemoveSectionAction = "remove-section"
removalActionToText RewriteFileAction = "rewrite-file"

removalCommandToJSON :: Command -> Aeson.Value
removalCommandToJSON c =
  Aeson.object $
    ["run" .= (c ^. #run)]
      ++ maybe [] (\w -> ["workDir" .= w]) (c ^. #workDir)

-- | Parse a Removal from JSON.
parseRemovalJSON :: Aeson.Value -> Aeson.Parser Removal
parseRemovalJSON = Aeson.withObject "Removal" $ \o ->
  Removal
    <$> (o Aeson..:? "steps" Aeson..!= [] >>= mapM parseRemovalStepJSON)
    <*> (o Aeson..:? "commands" Aeson..!= [] >>= mapM parseRemovalCommandJSON)

parseRemovalStepJSON :: Aeson.Value -> Aeson.Parser RemovalStep
parseRemovalStepJSON = Aeson.withObject "RemovalStep" $ \o ->
  RemovalStep
    <$> (parseRemovalActionText =<< o .: "action")
    <*> o .: "dest"
    <*> o Aeson..:? "src"

parseRemovalActionText :: Text -> Aeson.Parser RemovalAction
parseRemovalActionText "remove-file" = pure RemoveFileAction
parseRemovalActionText "remove-section" = pure RemoveSectionAction
parseRemovalActionText "rewrite-file" = pure RewriteFileAction
parseRemovalActionText other = fail ("unknown removal action: " <> T.unpack other)

parseRemovalCommandJSON :: Aeson.Value -> Aeson.Parser Command
parseRemovalCommandJSON = Aeson.withObject "RemovalCommand" $ \o ->
  Command
    <$> o .: "run"
    <*> o Aeson..:? "workDir"
    <*> pure Nothing

-- | Encode a file record in the representation of the given schema.
--
-- Schema 7 always emits @sharedWriteMode@, including @unknown@, so absence
-- can never again stand for a value. Schema 6 can only say
-- @additiveOnly: true@; a closure-required path is written without the key
-- and reads back as unknown, which is the fail-closed direction.
fileRecordToJSON :: ManifestSchemaVersion -> FileRecord -> Aeson.Value
fileRecordToJSON schema fr =
  Aeson.object $
    [ "hash" .= (fr ^. #hash . #unSHA256),
      "module" .= (fr ^. #moduleName . #unModuleName),
      "strategy" .= strategyToText (fr ^. #strategy),
      "generatedAt" .= (fr ^. #generatedAt)
    ]
      ++ maybe [] (\ref -> ["baseline" .= (ref ^. #unBaselineRef . #unSHA256)]) (fr ^. #baseline)
      ++ applicationIdsField (fr ^. #applicationIds)
      ++ sharedWriteField (fr ^. #sharedWriteMode)
  where
    applicationIdsField ids
      | Set.null ids = []
      | otherwise = ["applications" .= map (^. #unApplicationId) (Set.toAscList ids)]
    sharedWriteField mode
      | schema >= ManifestSchemaVersion 7 = ["sharedWriteMode" .= sharedWriteModeToText mode]
      | mode == SharedWriteAdditiveOnly = ["additiveOnly" .= True]
      | otherwise = []

-- | Decode a file record in the representation of the given schema.
parseFileRecord :: ManifestSchemaVersion -> Aeson.Value -> Aeson.Parser FileRecord
parseFileRecord schema = Aeson.withObject "FileRecord" $ \o -> do
  baselineText <- o Aeson..:? "baseline"
  baseline <- traverse parseBaselineRef baselineText
  FileRecord
    <$> (SHA256 <$> o .: "hash")
    <*> (ModuleName <$> o .: "module")
    <*> (strategyFromText =<< o .: "strategy")
    <*> o .: "generatedAt"
    <*> pure baseline
    <*> (Set.fromList . map ApplicationId <$> o Aeson..:? "applications" Aeson..!= [])
    <*> parseSharedWrite o
  where
    parseBaselineRef value = case baselineRefFromText value of
      Just ref -> pure ref
      Nothing -> fail "baseline must be a 64-character hexadecimal SHA-256 digest"
    parseSharedWrite o
      | schema >= ManifestSchemaVersion 7 = do
          raw <- o Aeson..:? "sharedWriteMode"
          case raw of
            Nothing -> fail "missing required key \"sharedWriteMode\" (schema 7 records it on every file)"
            Just text -> case sharedWriteModeFromText text of
              Just mode -> pure mode
              Nothing ->
                fail
                  ( "invalid \"sharedWriteMode\" value "
                      <> show text
                      <> "; expected \"unknown\", \"additive-only\", or \"requires-ownership-closure\""
                  )
      | otherwise = do
          -- Version 6 omitted false, so only an explicit true proves anything.
          additive <- o Aeson..:? "additiveOnly" Aeson..!= False
          pure (if additive then SharedWriteAdditiveOnly else SharedWriteUnknown)

-- | The schema-7 wire spelling of a shared-write mode.
sharedWriteModeToText :: SharedWriteMode -> Text
sharedWriteModeToText SharedWriteUnknown = "unknown"
sharedWriteModeToText SharedWriteAdditiveOnly = "additive-only"
sharedWriteModeToText SharedWriteRequiresOwnershipClosure = "requires-ownership-closure"

sharedWriteModeFromText :: Text -> Maybe SharedWriteMode
sharedWriteModeFromText text =
  lookup text [(sharedWriteModeToText mode, mode) | mode <- [minBound .. maxBound]]

instance ToJSON SHA256 where
  toJSON (SHA256 t) = toJSON t

instance FromJSON SHA256 where
  parseJSON v = SHA256 <$> parseJSON v

commandFingerprintText :: CommandFingerprint -> Text
commandFingerprintText (CommandFingerprint (SHA256 value)) = value

commandReceiptsToJSON :: Map CommandFingerprint CommandReceipt -> Aeson.Value
commandReceiptsToJSON = toJSON . Map.mapKeys commandFingerprintText

commandReceiptsFromJSON :: Aeson.Value -> Aeson.Parser (Map CommandFingerprint CommandReceipt)
commandReceiptsFromJSON value = do
  receipts <- parseJSON value :: Aeson.Parser (Map Text CommandReceipt)
  pure (Map.mapKeys (CommandFingerprint . SHA256) receipts)

-- Helpers for VarName-keyed maps

varsToJSON :: Map VarName Text -> Aeson.Value
varsToJSON = toJSON . Map.mapKeys (^. #unVarName)

varsFromJSON :: Aeson.Value -> Aeson.Parser (Map VarName Text)
varsFromJSON v = do
  m <- parseJSON v :: Aeson.Parser (Map Text Text)
  pure (Map.mapKeys VarName m)

-- Helpers for FilePath-keyed maps

filesToJSON :: ManifestSchemaVersion -> Map FilePath FileRecord -> Aeson.Value
filesToJSON schema = toJSON . Map.map (fileRecordToJSON schema) . Map.mapKeys T.pack

-- | Each record is parsed under its path, so a malformed record's error
-- names the file it belongs to.
filesFromJSON :: ManifestSchemaVersion -> Aeson.Value -> Aeson.Parser (Map FilePath FileRecord)
filesFromJSON schema v = do
  m <- parseJSON v :: Aeson.Parser (Map Text Aeson.Value)
  records <-
    Map.traverseWithKey
      ( \path value ->
          Aeson.modifyFailure
            (\err -> "file record " <> show path <> ": " <> err)
            (parseFileRecord schema value Aeson.<?> Aeson.Key (Key.fromText path))
      )
      m
  pure (Map.mapKeys T.unpack records)

-- Strategy serialization

strategyToText :: Strategy -> Text
strategyToText Copy = "copy"
strategyToText Template = "template"
strategyToText DhallText = "dhall-text"
strategyToText Structured = "structured"

strategyFromText :: Text -> Aeson.Parser Strategy
strategyFromText "copy" = pure Copy
strategyFromText "template" = pure Template
strategyFromText "dhall-text" = pure DhallText
strategyFromText "structured" = pure Structured
strategyFromText other = fail ("unknown strategy: " <> T.unpack other)
