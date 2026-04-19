module Seihou.Manifest.Types
  ( emptyManifest,
    currentManifestVersion,
    manifestToJSON,
    manifestFromJSON,
  )
where

import Data.Aeson (FromJSON (..), ToJSON (..), (.:), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Types qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Time (UTCTime)
import Seihou.Core.Types
import Seihou.Prelude hiding ((.=))

-- | Current manifest schema version.
--
-- Bumped from 1 to 2 when 'AppliedModule' gained the @parentVars@ field
-- (see docs/plans/10-parameterized-dep-multi-instantiation.md). Version-1
-- manifests remain readable because the decoder treats a missing
-- @parentVars@ key as 'emptyParentVars'.
currentManifestVersion :: Int
currentManifestVersion = 2

-- | Create an empty manifest with the given timestamp.
emptyManifest :: UTCTime -> Manifest
emptyManifest now =
  Manifest
    { version = currentManifestVersion,
      genAt = now,
      modules = [],
      vars = Map.empty,
      files = Map.empty,
      recipe = Nothing
    }

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
        "files" .= filesToJSON m.files
      ]
        ++ maybe [] (\r -> ["recipe" .= r]) m.recipe

instance FromJSON Manifest where
  parseJSON = Aeson.withObject "Manifest" $ \o -> do
    v <- o .: "version"
    if v > currentManifestVersion
      then fail "manifest was created by a newer version of seihou"
      else
        Manifest v
          <$> o .: "generatedAt"
          <*> o .: "modules"
          <*> (varsFromJSON =<< o .: "variables")
          <*> (filesFromJSON =<< o .: "files")
          <*> o Aeson..:? "recipe"

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
    Aeson.object
      [ "hash" .= fr.hash.unSHA256,
        "module" .= fr.moduleName.unModuleName,
        "strategy" .= strategyToText fr.strategy,
        "generatedAt" .= fr.generatedAt
      ]

instance FromJSON FileRecord where
  parseJSON = Aeson.withObject "FileRecord" $ \o ->
    FileRecord
      <$> (SHA256 <$> o .: "hash")
      <*> (ModuleName <$> o .: "module")
      <*> (strategyFromText =<< o .: "strategy")
      <*> o .: "generatedAt"

instance ToJSON SHA256 where
  toJSON (SHA256 t) = toJSON t

instance FromJSON SHA256 where
  parseJSON v = SHA256 <$> parseJSON v

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
