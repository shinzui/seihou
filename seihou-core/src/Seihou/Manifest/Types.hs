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
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime)
import Seihou.Core.Types

-- | Current manifest schema version.
currentManifestVersion :: Int
currentManifestVersion = 1

-- | Create an empty manifest with the given timestamp.
emptyManifest :: UTCTime -> Manifest
emptyManifest now =
  Manifest
    { manifestVersion = currentManifestVersion,
      manifestGenAt = now,
      manifestModules = [],
      manifestVars = Map.empty,
      manifestFiles = Map.empty
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
    Aeson.object
      [ "version" .= manifestVersion m,
        "generatedAt" .= manifestGenAt m,
        "modules" .= manifestModules m,
        "variables" .= varsToJSON (manifestVars m),
        "files" .= filesToJSON (manifestFiles m)
      ]

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

instance ToJSON AppliedModule where
  toJSON am =
    Aeson.object
      [ "name" .= unModuleName (appliedName am),
        "source" .= appliedSource am,
        "appliedAt" .= appliedAt am
      ]

instance FromJSON AppliedModule where
  parseJSON = Aeson.withObject "AppliedModule" $ \o ->
    AppliedModule
      <$> (ModuleName <$> o .: "name")
      <*> o .: "source"
      <*> o .: "appliedAt"

instance ToJSON FileRecord where
  toJSON fr =
    Aeson.object
      [ "hash" .= unSHA256 (fileHash fr),
        "module" .= unModuleName (fileModule fr),
        "strategy" .= strategyToText (fileStrategy fr),
        "generatedAt" .= fileGeneratedAt fr
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
varsToJSON = toJSON . Map.mapKeys unVarName

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
