-- | Convert a @.seihou\/manifest.json@ written before schema version 6 into
-- the portable form every current command expects.
--
-- Schema-5-and-earlier manifests record, for each applied artifact, the
-- absolute directory that artifact occupied on the machine that ran seihou —
-- entries like @\/Users\/shinzui\/.config\/seihou\/installed\/haskell-base@.
-- That string is meaningless in any other clone, which is why
-- docs\/adr\/0001-manifest-is-a-checked-in-machine-independent-artifact.md
-- forbids it and why
-- 'Seihou.Manifest.Types.checkManifestVersion' refuses such a manifest
-- outright rather than misreading it.
--
-- This module turns those paths into 'ArtifactOrigin' values. Doing so
-- requires inference — the recorded path belongs to somebody else's machine,
-- so the upstream URL has to be recovered from what is installed here — and
-- inference that happens silently inside a file that is committed to git is
-- exactly what this initiative exists to remove. So the conversion is an
-- explicit command with a printed report rather than an automatic upgrade on
-- first read, and every entry says how confident it is.
--
-- The document is manipulated as an 'Aeson.Value' rather than decoded into
-- mirror records. The upgrade only needs to find three keys and replace them;
-- every other field — resolved variables, file records, baseline references,
-- command receipts, blueprint migration receipts — must survive untouched,
-- and walking the 'Aeson.Value' guarantees that where decode-and-re-encode
-- would risk dropping a key some later schema version added.
module Seihou.CLI.ManifestUpgrade
  ( -- * Reading a legacy manifest
    LegacyRef (..),
    LegacyManifest (..),
    readLegacyManifest,

    -- * Inferring a portable origin
    InferenceOutcome (..),
    inferredOrigin,
    inferOriginFromLegacyPath,
  )
where

import Data.Aeson qualified as Aeson
import Data.Aeson.Key (Key)
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (toList)
import Data.Generics.Labels ()
import Data.Text qualified as T
import Seihou.Core.ArtifactOriginDetect (detectArtifactOrigin)
import Seihou.Core.ArtifactRef (resolveArtifactOrigin)
import Seihou.Core.Types (ArtifactOrigin (..))
import Seihou.Manifest.Types (currentManifestVersion)
import Seihou.Prelude

-- ----------------------------------------------------------------------------
-- Reading a legacy manifest
-- ----------------------------------------------------------------------------

-- | One legacy artifact reference found in a schema-5-or-earlier manifest.
--
-- @jsonPointer@ locates the reference inside the document so the rewriter can
-- put the converted origin back in the right place, and so the report can say
-- which record it came from. It is a list of object keys and array indices
-- ending in the key that holds the path, for example
-- @["modules", "0", "source"]@ or
-- @["applications", "0", "instances", "1", "source"]@.
--
-- @definitionFile@ is the file that must be present for a directory to count
-- as this artifact — @module.dhall@ for a module, @recipe.dhall@ for an
-- application whose target is a recipe. Inference needs it because it looks
-- the artifact up by name in the local search paths.
data LegacyRef = LegacyRef
  { jsonPointer :: ![Text],
    artifactName :: !Text,
    legacyPath :: !FilePath,
    recordedVersion :: !(Maybe Text),
    definitionFile :: !FilePath
  }
  deriving stock (Eq, Show, Generic)

-- | Every legacy reference in a document, together with the document itself
-- so the rewriter can operate on it directly.
data LegacyManifest = LegacyManifest
  { schemaVersion :: !Int,
    document :: !Aeson.Value,
    refs :: ![LegacyRef]
  }
  deriving stock (Eq, Show, Generic)

-- | Parse a manifest document that has not yet been upgraded.
--
-- Returns 'Nothing' when the document's @version@ is already at or above the
-- current schema version, so callers can treat "nothing to do" as an ordinary
-- outcome rather than an error. A manifest from a /newer/ seihou is also
-- 'Nothing': there is nothing here to convert, and complaining about it is
-- 'Seihou.Manifest.Types.checkManifestVersion''s job.
readLegacyManifest :: LBS.ByteString -> Either String (Maybe LegacyManifest)
readLegacyManifest bytes = do
  value <- Aeson.eitherDecode bytes
  fields <- case value of
    Aeson.Object fields -> Right fields
    _ -> Left "manifest is not a JSON object"
  schemaVersion <- case KeyMap.lookup "version" fields of
    Just (Aeson.Number n) -> Right (truncate n :: Int)
    Just _ -> Left "manifest 'version' is not a number"
    Nothing -> Left "manifest has no 'version' field"
  pure $
    if schemaVersion >= currentManifestVersion
      then Nothing
      else
        Just
          LegacyManifest
            { schemaVersion = schemaVersion,
              document = value,
              refs = collectRefs value
            }

-- | Every machine-specific path recorded in a legacy document, in the order a
-- reader meets them.
--
-- Three keys hold such a path: @source@ inside each entry of @modules@,
-- @targetSource@ on each application, and @source@ inside each of an
-- application's @instances@. Everything else in the format is already
-- portable.
collectRefs :: Aeson.Value -> [LegacyRef]
collectRefs value =
  concatMap moduleRef (withIndices (arrayAt value "modules"))
    <> concatMap applicationRefs (withIndices (arrayAt value "applications"))
  where
    moduleRef (index, element) =
      mkRef
        ["modules", index, "source"]
        "module.dhall"
        (textAt element "name")
        (textAt element "source")
        (textAt element "version")

    applicationRefs (index, element) =
      mkRef
        ["applications", index, "targetSource"]
        (targetDefinitionFile element)
        (objectAt element "target" >>= \target -> textAt target "name")
        (textAt element "targetSource")
        (textAt element "targetVersion")
        <> concatMap (instanceRef index) (withIndices (arrayAt element "instances"))

    instanceRef applicationIndex (index, element) =
      mkRef
        ["applications", applicationIndex, "instances", index, "source"]
        "module.dhall"
        (textAt element "name")
        (textAt element "source")
        (textAt element "version")

-- | An application's target is either a module or a recipe, and the two are
-- discovered by different definition files.
targetDefinitionFile :: Aeson.Value -> FilePath
targetDefinitionFile application =
  case objectAt application "target" >>= \target -> textAt target "kind" of
    Just "recipe" -> "recipe.dhall"
    _ -> "module.dhall"

-- | Build a reference, or nothing when the record lacks a name or a path.
--
-- A record with no @source@ is not an error: a hand-edited manifest, or a
-- record a future field made optional, simply has nothing to convert.
mkRef ::
  [Text] ->
  FilePath ->
  Maybe Text ->
  Maybe Text ->
  Maybe Text ->
  [LegacyRef]
mkRef pointer definitionFile mName mSource mVersion =
  case (mName, mSource) of
    (Just name, Just source) ->
      [ LegacyRef
          { jsonPointer = pointer,
            artifactName = name,
            legacyPath = T.unpack source,
            recordedVersion = mVersion,
            definitionFile = definitionFile
          }
      ]
    _ -> []

-- ----------------------------------------------------------------------------
-- Inferring a portable origin
-- ----------------------------------------------------------------------------

-- | How confident the upgrade is about a converted origin.
--
-- The distinction is not decoration: it is what the printed report shows the
-- developer, and it is the difference between a manifest entry that names its
-- upstream and one that admits it cannot.
data InferenceOutcome
  = -- | The artifact resolved locally and its install metadata gave a URL.
    -- Strongest result.
    InferredFromLocalInstall !ArtifactOrigin
  | -- | The legacy path names a directory inside the project, so it converts
    -- to a 'ProjectOrigin' by path arithmetic alone. Exact rather than
    -- inferred: a project-relative path means the same thing in every clone.
    InferredFromProjectPath !ArtifactOrigin
  | -- | Nothing local matched, or what matched carries no provenance; fell
    -- back to 'LocalOrigin' with only the recorded name. The developer can
    -- improve this by reinstalling from the real upstream and re-running the
    -- upgrade.
    InferredAsUnverifiable !ArtifactOrigin
  deriving stock (Eq, Show, Generic)

-- | The converted origin, whatever the confidence.
inferredOrigin :: InferenceOutcome -> ArtifactOrigin
inferredOrigin (InferredFromLocalInstall origin) = origin
inferredOrigin (InferredFromProjectPath origin) = origin
inferredOrigin (InferredAsUnverifiable origin) = origin

-- | Convert one legacy reference into a portable origin.
--
-- @projectRoot@ is the absolute directory holding @.seihou@. @searchPaths@ is
-- normally 'Seihou.Core.Module.defaultSearchPaths'.
--
-- Inference proceeds in three steps.
--
-- First, path arithmetic that needs no local state. The recorded path was
-- written by another machine, so its project-root prefix is that machine's
-- checkout, not this one — which is why the test is on the /suffix/: a path
-- ending in @.seihou\/modules\/\<name\>@ names a project-local artifact in
-- every clone. Containment inside this machine's project root is checked
-- second, as confirmation, for a layout the suffix test does not recognise.
--
-- Second, a local lookup by name through @searchPaths@, which is exactly what
-- 'Seihou.Core.ArtifactRef.resolveArtifactOrigin' does for a 'LocalOrigin'.
-- What is found is classified by 'detectArtifactOrigin', so an installed copy
-- with a @.seihou-origin.json@ yields the upstream URL the legacy path had
-- thrown away.
--
-- Third, 'LocalOrigin' carrying only the recorded name — the honest
-- representation of "this came from somewhere on that developer's machine and
-- we cannot say where".
inferOriginFromLegacyPath ::
  FilePath ->
  [FilePath] ->
  LegacyRef ->
  IO InferenceOutcome
inferOriginFromLegacyPath projectRoot searchPaths ref =
  case projectModuleSuffix (ref ^. #legacyPath) of
    Just relative -> pure (InferredFromProjectPath (ProjectOrigin relative))
    Nothing -> do
      recorded <- detectArtifactOrigin projectRoot (ref ^. #legacyPath)
      case recorded of
        ProjectOrigin _ -> pure (InferredFromProjectPath recorded)
        _ -> fromLocalLookup
  where
    name = ref ^. #artifactName

    fromLocalLookup = do
      resolved <-
        resolveArtifactOrigin
          projectRoot
          searchPaths
          (ref ^. #definitionFile)
          (LocalOrigin name)
      case resolved of
        Left _ -> pure (InferredAsUnverifiable (LocalOrigin name))
        Right directory -> do
          found <- detectArtifactOrigin projectRoot directory
          pure $ case found of
            RemoteOrigin {} -> InferredFromLocalInstall found
            ProjectOrigin {} -> InferredFromProjectPath found
            LocalOrigin {} -> InferredAsUnverifiable found

-- | The project-relative form of a legacy path that names an artifact under
-- @.seihou\/modules\/@, whichever machine's checkout it was written on.
projectModuleSuffix :: FilePath -> Maybe FilePath
projectModuleSuffix path = case reverse (pathSegments path) of
  (name : "modules" : ".seihou" : _) -> Just (".seihou/modules/" <> name)
  _ -> Nothing

-- | Whether a legacy path has the shape of an entry in the install cache,
-- @\<xdg-config\>\/seihou\/installed\/\<name\>@.
--
-- A path with that shape says the original author had the artifact installed
-- from an upstream, so when inference still falls back to 'LocalOrigin' the
-- report can say the URL was lost rather than that there never was one.
legacyPathWasInstalled :: FilePath -> Bool
legacyPathWasInstalled path = case reverse (pathSegments path) of
  (_ : "installed" : "seihou" : _) -> True
  _ -> False

-- | Split a recorded path into its segments, tolerating either separator: the
-- path may have been written by a machine that is not this one.
pathSegments :: FilePath -> [FilePath]
pathSegments = filter (not . null) . foldr split [[]]
  where
    split character segments@(current : rest)
      | character == '/' || character == '\\' = [] : segments
      | otherwise = (character : current) : rest
    split _ [] = []

-- ----------------------------------------------------------------------------
-- Small JSON accessors
-- ----------------------------------------------------------------------------

-- | Pair every element of a list with its index, rendered as the text an
-- array position takes inside a pointer.
withIndices :: [a] -> [(Text, a)]
withIndices = zip (map (T.pack . show) [(0 :: Int) ..])

objectAt :: Aeson.Value -> Key -> Maybe Aeson.Value
objectAt (Aeson.Object fields) name = KeyMap.lookup name fields
objectAt _ _ = Nothing

textAt :: Aeson.Value -> Key -> Maybe Text
textAt value name = case objectAt value name of
  Just (Aeson.String text) -> Just text
  _ -> Nothing

arrayAt :: Aeson.Value -> Key -> [Aeson.Value]
arrayAt value name = case objectAt value name of
  Just (Aeson.Array elements) -> toList elements
  _ -> []
