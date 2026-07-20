module Seihou.Manifest.Types
  ( emptyManifest,
    currentManifestVersion,
    manifestToJSON,
    manifestFromJSON,
    writeAppliedBlueprint,
    writeAppliedBlueprintMigration,
    hasAppliedBlueprintMigration,
  )
where

import Data.Aeson (FromJSON (..), ToJSON (..), (.:), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Types qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Time (UTCTime)
import Seihou.Core.Types
import Seihou.Manifest.Hash (baselineRefFromText)
import Seihou.Prelude hiding ((.=))

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
currentManifestVersion :: Int
currentManifestVersion = 5

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
    { version = m.version,
      genAt = m.genAt,
      modules = m.modules,
      vars = m.vars,
      files = m.files,
      applications = m.applications,
      recipe = m.recipe,
      blueprint = Just ab,
      blueprintMigrations = m.blueprintMigrations
    }

-- | Insert or replace one exact blueprint migration receipt. Replacement is
-- performed in place, while adding a v5-only receipt upgrades the manifest
-- version and preserves every unrelated field.
writeAppliedBlueprintMigration :: AppliedBlueprintMigration -> Manifest -> Manifest
writeAppliedBlueprintMigration receipt manifest =
  Manifest
    { version = currentManifestVersion,
      genAt = manifest.genAt,
      modules = manifest.modules,
      vars = manifest.vars,
      files = manifest.files,
      applications = manifest.applications,
      recipe = manifest.recipe,
      blueprint = manifest.blueprint,
      blueprintMigrations = upsert manifest.blueprintMigrations
    }
  where
    sameEdge existing =
      existing.name == receipt.name
        && existing.fromVersion == receipt.fromVersion
        && existing.toVersion == receipt.toVersion

    upsert receipts
      | any sameEdge receipts = map (\existing -> if sameEdge existing then receipt else existing) receipts
      | otherwise = receipts <> [receipt]

-- | Whether one exact blueprint migration edge already has a receipt.
hasAppliedBlueprintMigration :: ModuleName -> Text -> Text -> Manifest -> Bool
hasAppliedBlueprintMigration blueprintName fromVersion toVersion manifest =
  any
    ( \receipt ->
        receipt.name == blueprintName
          && receipt.fromVersion == fromVersion
          && receipt.toVersion == toVersion
    )
    manifest.blueprintMigrations

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
      [ "version" .= m.version,
        "generatedAt" .= m.genAt,
        "modules" .= m.modules,
        "variables" .= varsToJSON m.vars,
        "files" .= filesToJSON m.files,
        "applications" .= m.applications,
        "blueprintMigrations" .= m.blueprintMigrations
      ]
        ++ maybe [] (\r -> ["recipe" .= r]) m.recipe
        ++ maybe [] (\b -> ["blueprint" .= b]) m.blueprint

instance FromJSON Manifest where
  parseJSON = Aeson.withObject "Manifest" $ \o -> do
    v <- o .: "version"
    if v > currentManifestVersion
      then fail "manifest was created by a newer version of seihou"
      else
        Manifest
          <$> pure v
          <*> o .: "generatedAt"
          <*> o .: "modules"
          <*> (varsFromJSON =<< o .: "variables")
          <*> (filesFromJSON =<< o .: "files")
          <*> o Aeson..:? "applications" Aeson..!= []
          <*> o Aeson..:? "recipe"
          <*> o Aeson..:? "blueprint"
          <*> o Aeson..:? "blueprintMigrations" Aeson..!= []

instance ToJSON AppliedTarget where
  toJSON (AppliedModuleTarget name) =
    Aeson.object ["kind" .= ("module" :: Text), "name" .= name.unModuleName]
  toJSON (AppliedRecipeTarget name) =
    Aeson.object ["kind" .= ("recipe" :: Text), "name" .= name.unRecipeName]

instance FromJSON AppliedTarget where
  parseJSON = Aeson.withObject "AppliedTarget" $ \o -> do
    kind <- o .: "kind" :: Aeson.Parser Text
    name <- o .: "name"
    case kind of
      "module" -> pure (AppliedModuleTarget (ModuleName name))
      "recipe" -> pure (AppliedRecipeTarget (RecipeName name))
      other -> fail ("unknown applied target kind: " <> T.unpack other)

instance ToJSON AppliedInstanceState where
  toJSON state =
    Aeson.object $
      [ "name" .= state.name.unModuleName,
        "source" .= state.source,
        "resolvedVars" .= varsToJSON state.resolvedVars
      ]
        ++ parentVarsField state.parentVars
        ++ maybe [] (\v -> ["version" .= v]) state.moduleVersion
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
      <*> o .: "source"
      <*> o Aeson..:? "version"
      <*> (varsFromJSON =<< o Aeson..:? "resolvedVars" Aeson..!= Aeson.object [])

instance ToJSON AppliedComposition where
  toJSON composition =
    Aeson.object $
      [ "applicationId" .= composition.applicationId.unApplicationId,
        "target" .= composition.target,
        "targetSource" .= composition.targetSource,
        "additionalModules" .= map (.unModuleName) composition.additionalModules,
        "instances" .= composition.instances,
        "appliedAt" .= composition.appliedAt
      ]
        ++ maybe [] (\v -> ["targetVersion" .= v]) composition.targetVersion
        ++ maybe [] (\v -> ["namespace" .= v]) composition.namespace
        ++ maybe [] (\v -> ["context" .= v]) composition.context
        ++ commandReceiptsField composition.commandReceipts
    where
      commandReceiptsField receipts
        | Map.null receipts = []
        | otherwise = ["commandReceipts" .= commandReceiptsToJSON receipts]

instance FromJSON AppliedComposition where
  parseJSON = Aeson.withObject "AppliedComposition" $ \o ->
    AppliedComposition
      <$> (ApplicationId <$> o .: "applicationId")
      <*> o .: "target"
      <*> o .: "targetSource"
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
      [ "fingerprint" .= commandFingerprintText receipt.fingerprint,
        "module" .= receipt.moduleName.unModuleName,
        "command" .= receipt.command,
        "completedAt" .= receipt.completedAt
      ]
        ++ maybe [] (\path -> ["workDir" .= path]) receipt.workDir

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
      [ "name" .= ar.name.unRecipeName,
        "appliedAt" .= ar.appliedAt
      ]
        ++ maybe [] (\v -> ["version" .= v]) ar.recipeVersion

instance FromJSON AppliedRecipe where
  parseJSON = Aeson.withObject "AppliedRecipe" $ \o ->
    AppliedRecipe
      <$> (RecipeName <$> o .: "name")
      <*> o Aeson..:? "version"
      <*> o .: "appliedAt"

instance ToJSON AppliedBlueprint where
  toJSON ab =
    Aeson.object $
      [ "name" .= ab.name.unModuleName,
        "appliedAt" .= ab.appliedAt,
        "baselineModules" .= map (.unModuleName) ab.baselineModules,
        "noBaseline" .= ab.noBaseline
      ]
        ++ maybe [] (\v -> ["version" .= v]) ab.blueprintVersion
        ++ maybe [] (\p -> ["userPrompt" .= p]) ab.userPrompt
        ++ maybe [] (\s -> ["agentSessionId" .= s]) ab.agentSessionId

instance FromJSON AppliedBlueprint where
  parseJSON = Aeson.withObject "AppliedBlueprint" $ \o ->
    AppliedBlueprint
      <$> (ModuleName <$> o .: "name")
      <*> o Aeson..:? "version"
      <*> o .: "appliedAt"
      <*> (map ModuleName <$> o Aeson..:? "baselineModules" Aeson..!= [])
      <*> o Aeson..:? "noBaseline" Aeson..!= False
      <*> o Aeson..:? "userPrompt"
      <*> o Aeson..:? "agentSessionId"

instance ToJSON AppliedBlueprintMigration where
  toJSON receipt =
    Aeson.object $
      [ "name" .= receipt.name.unModuleName,
        "from" .= receipt.fromVersion,
        "to" .= receipt.toVersion,
        "appliedAt" .= receipt.appliedAt
      ]
        ++ maybe [] (\version -> ["version" .= version]) receipt.blueprintVersion
        ++ maybe [] (\sessionId -> ["agentSessionId" .= sessionId]) receipt.agentSessionId

instance FromJSON AppliedBlueprintMigration where
  parseJSON = Aeson.withObject "AppliedBlueprintMigration" $ \o ->
    AppliedBlueprintMigration
      <$> (ModuleName <$> o .: "name")
      <*> o Aeson..:? "version"
      <*> o .: "from"
      <*> o .: "to"
      <*> o .: "appliedAt"
      <*> o Aeson..:? "agentSessionId"

instance ToJSON AppliedModule where
  toJSON am =
    Aeson.object $
      [ "name" .= am.name.unModuleName,
        "source" .= am.source,
        "appliedAt" .= am.appliedAt
      ]
        ++ parentVarsField am.parentVars
        ++ maybe [] (\v -> ["version" .= v]) am.moduleVersion
        ++ maybe [] (\r -> ["removal" .= removalToJSON r]) am.removal
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
      <*> o .: "source"
      <*> o Aeson..:? "version"
      <*> o .: "appliedAt"
      <*> pure removal

parentVarsMapToJSON :: Map VarName Text -> Aeson.Value
parentVarsMapToJSON = toJSON . Map.mapKeys (.unVarName)

parentVarsMapFromJSON :: Aeson.Value -> Aeson.Parser (Map VarName Text)
parentVarsMapFromJSON v = do
  m <- parseJSON v :: Aeson.Parser (Map Text Text)
  pure (Map.mapKeys VarName m)

-- | Encode a Removal to JSON.
removalToJSON :: Removal -> Aeson.Value
removalToJSON r =
  Aeson.object
    [ "steps" .= map removalStepToJSON r.removalSteps,
      "commands" .= map removalCommandToJSON r.removalCommands
    ]

removalStepToJSON :: RemovalStep -> Aeson.Value
removalStepToJSON s =
  Aeson.object $
    [ "action" .= removalActionToText s.action,
      "dest" .= s.dest
    ]
      ++ maybe [] (\p -> ["src" .= p]) s.src

removalActionToText :: RemovalAction -> Text
removalActionToText RemoveFileAction = "remove-file"
removalActionToText RemoveSectionAction = "remove-section"
removalActionToText RewriteFileAction = "rewrite-file"

removalCommandToJSON :: Command -> Aeson.Value
removalCommandToJSON c =
  Aeson.object $
    ["run" .= c.run]
      ++ maybe [] (\w -> ["workDir" .= w]) c.workDir

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

instance ToJSON FileRecord where
  toJSON fr =
    Aeson.object $
      [ "hash" .= fr.hash.unSHA256,
        "module" .= fr.moduleName.unModuleName,
        "strategy" .= strategyToText fr.strategy,
        "generatedAt" .= fr.generatedAt
      ]
        ++ maybe [] (\ref -> ["baseline" .= ref.unBaselineRef.unSHA256]) fr.baseline
        ++ applicationIdsField fr.applicationIds
    where
      applicationIdsField ids
        | Set.null ids = []
        | otherwise = ["applications" .= map (.unApplicationId) (Set.toAscList ids)]

instance FromJSON FileRecord where
  parseJSON = Aeson.withObject "FileRecord" $ \o -> do
    baselineText <- o Aeson..:? "baseline"
    baseline <- traverse parseBaselineRef baselineText
    FileRecord
      <$> (SHA256 <$> o .: "hash")
      <*> (ModuleName <$> o .: "module")
      <*> (strategyFromText =<< o .: "strategy")
      <*> o .: "generatedAt"
      <*> pure baseline
      <*> (Set.fromList . map ApplicationId <$> o Aeson..:? "applications" Aeson..!= [])
    where
      parseBaselineRef value = case baselineRefFromText value of
        Just ref -> pure ref
        Nothing -> fail "baseline must be a 64-character hexadecimal SHA-256 digest"

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
varsToJSON = toJSON . Map.mapKeys (.unVarName)

varsFromJSON :: Aeson.Value -> Aeson.Parser (Map VarName Text)
varsFromJSON v = do
  m <- parseJSON v :: Aeson.Parser (Map Text Text)
  pure (Map.mapKeys VarName m)

-- Helpers for FilePath-keyed maps

filesToJSON :: Map FilePath FileRecord -> Aeson.Value
filesToJSON = toJSON . Map.mapKeys T.pack

filesFromJSON :: Aeson.Value -> Aeson.Parser (Map FilePath FileRecord)
filesFromJSON v = do
  m <- parseJSON v :: Aeson.Parser (Map Text FileRecord)
  pure (Map.mapKeys T.unpack m)

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
