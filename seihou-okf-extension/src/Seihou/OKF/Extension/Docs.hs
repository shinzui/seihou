module Seihou.OKF.Extension.Docs
  ( DocsOpts (..),
    runDocs,
    handleDocs,
    renderDocBundleError,
  )
where

import Control.Lens ((^.))
import Control.Monad (when)
import Data.Aeson (Value)
import Data.Aeson.Text qualified as Aeson
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.Builder qualified as TLB
import GHC.Generics (Generic)
import Okf.Bundle (BundleError (..))
import Okf.ConceptId qualified as Okf
import Okf.Document (DocumentParseError (..))
import Okf.Log (LogValidationError (..))
import Okf.Profile
  ( FieldCondition (..),
    FieldPath (..),
    FieldPathSegment (..),
    ProfileViolation (..),
    renderCardinalityName,
    renderFieldFormatName,
  )
import Okf.Validation (BundleValidationError (..), ValidationError (..), ValidationProfile (..))
import Seihou.OKF.Docs.Model
import Seihou.OKF.Docs.Render
import Seihou.OKF.Extension.Version (extensionVersion)
import System.Directory
  ( createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    doesPathExist,
    listDirectory,
    removeDirectoryRecursive,
  )
import System.Exit (exitFailure)
import System.FilePath ((</>))
import System.IO (stderr)

data DocsOpts = DocsOpts
  { dir :: !FilePath,
    out :: !FilePath,
    force :: !Bool,
    -- | Recorded verbatim as OKF @generated.at@. Absent by default, because
    -- reading the clock would make every regeneration produce different bytes.
    generatedAt :: !(Maybe T.Text),
    -- | Validate with 'PermissiveConformance' instead of the default
    -- 'StrictAuthoring'.
    permissive :: !Bool,
    -- | Check against this house profile descriptor instead of the built-in
    -- one.
    profile :: !(Maybe FilePath),
    -- | Skip house-profile enforcement entirely.
    noProfile :: !Bool
  }
  deriving stock (Eq, Generic, Show)

-- | The renderer configuration these command-line options describe.
renderOptionsFor :: DocsOpts -> RenderOptions
renderOptionsFor opts =
  RenderOptions
    { producerVersion = extensionVersion,
      generatedAt = opts ^. #generatedAt,
      validationProfile =
        if opts ^. #permissive then PermissiveConformance else StrictAuthoring,
      profileSource = opts ^. #profile,
      enforceProfile = not (opts ^. #noProfile)
    }

runDocs :: DocsOpts -> IO (Either T.Text T.Text)
runDocs opts = do
  let registryFile = opts ^. #dir </> "seihou-registry.dhall"
  registryExists <- doesFileExist registryFile
  if not registryExists
    then pure (Left ("registry file not found: " <> T.pack registryFile))
    else do
      outputCheck <- checkOutputDirectory opts
      case outputCheck of
        Left err -> pure (Left err)
        Right () -> do
          modelResult <- loadDocModel (opts ^. #dir)
          case modelResult of
            Left err -> pure (Left (renderDocLoadError err))
            Right model ->
              case renderDocBundle (renderOptionsFor opts) model of
                Left renderErrors ->
                  pure (Left (renderMany renderDocRenderError renderErrors))
                Right (concepts, validationProblems)
                  | not (null validationProblems) ->
                      pure (Left (renderMany renderBundleValidationError validationProblems))
                  | otherwise -> do
                      -- Check the house profile before touching the output
                      -- directory, so a violating run leaves whatever was
                      -- there untouched rather than clearing it first.
                      profileProblems <- checkDocProfile (renderOptionsFor opts) concepts
                      if not (null profileProblems)
                        then pure (Left (renderMany renderDocBundleError profileProblems))
                        else do
                          prepareOutputDirectory (opts ^. #out)
                          writeResult <- writeDocBundle (renderOptionsFor opts) (opts ^. #out) model
                          pure $ case writeResult of
                            Left errors -> Left (renderMany renderDocBundleError errors)
                            Right () -> Right ("Wrote " <> T.pack (show (length concepts)) <> " concepts to " <> T.pack (opts ^. #out))

handleDocs :: DocsOpts -> IO ()
handleDocs opts = do
  result <- runDocs opts
  case result of
    Left err -> do
      TIO.hPutStrLn stderr err
      exitFailure
    Right summary ->
      TIO.putStrLn summary

checkOutputDirectory :: DocsOpts -> IO (Either T.Text ())
checkOutputDirectory opts = do
  pathExists <- doesPathExist (opts ^. #out)
  if not pathExists
    then pure (Right ())
    else do
      isDirectory <- doesDirectoryExist (opts ^. #out)
      if not isDirectory
        then pure (Left ("output path exists and is not a directory: " <> T.pack (opts ^. #out)))
        else do
          entries <- listDirectory (opts ^. #out)
          if null entries || opts ^. #force
            then pure (Right ())
            else pure (Left ("output directory is not empty: " <> T.pack (opts ^. #out) <> "; pass --force to overwrite"))

prepareOutputDirectory :: FilePath -> IO ()
prepareOutputDirectory outDir = do
  exists <- doesDirectoryExist outDir
  when exists (removeDirectoryRecursive outDir)
  createDirectoryIfMissing True outDir

renderDocLoadError :: DocLoadError -> T.Text
renderDocLoadError (RegistryNotFound path) =
  "registry file not found: " <> T.pack path
renderDocLoadError (RegistryLoadFailed err) =
  "failed to load registry: " <> err
renderDocLoadError (ArtifactLoadFailed name err) =
  "failed to load registry entry " <> name <> ": " <> err

renderDocBundleError :: DocBundleError -> T.Text
renderDocBundleError (DocBundleRenderError err) = renderDocRenderError err
renderDocBundleError (DocBundleValidationError err) = renderBundleValidationError err
renderDocBundleError (DocBundleIndexError err) =
  "failed to write bundle indexes: " <> renderBundleError err
renderDocBundleError (DocBundleProfileUnreadable err) =
  "could not read the house profile descriptor: " <> err
renderDocBundleError (DocBundleProfileInvalid errs) =
  "the house profile descriptor does not compile: "
    <> T.intercalate "; " (T.pack . show <$> NonEmpty.toList errs)
renderDocBundleError (DocBundleProfileViolation violation) =
  "house profile: " <> renderProfileViolation violation

-- | Total by construction; see 'renderBundleValidationError'.
renderBundleError :: BundleError -> T.Text
renderBundleError (InvalidConceptPath path err) =
  T.pack path <> ": not a usable concept path: " <> T.pack (show err)
renderBundleError (InvalidConceptDocument path err) =
  T.pack path <> ": " <> renderDocumentParseError err
renderBundleError (BundleIoError path err) =
  T.pack path <> ": " <> err

-- | Total by construction; see 'renderBundleValidationError'.
renderDocumentParseError :: DocumentParseError -> T.Text
renderDocumentParseError UnterminatedFrontmatter =
  "frontmatter block is never closed"
renderDocumentParseError (InvalidYaml err) =
  "frontmatter is not valid YAML: " <> err
renderDocumentParseError FrontmatterNotMapping =
  "frontmatter is not a YAML mapping"

renderDocRenderError :: DocRenderError -> T.Text
renderDocRenderError (InvalidDocConceptId kind name err) =
  "invalid OKF concept ID for " <> T.pack (show kind) <> " " <> name <> ": " <> err

-- | Every 'BundleValidationError' constructor gets its own branch, deliberately
-- with no catch-all: @-Werror=incomplete-patterns@ then turns the next okf-core
-- upgrade that adds a constructor into a build failure here rather than a
-- pattern-match crash at generation time.
renderBundleValidationError :: BundleValidationError -> T.Text
renderBundleValidationError (DocumentInvalid conceptId err) =
  Okf.renderConceptId conceptId <> ": " <> renderValidationError err
renderBundleValidationError (DanglingReference source target) =
  Okf.renderConceptId source <> ": link to missing concept: " <> Okf.renderConceptId target
renderBundleValidationError (DanglingFrontmatterPath conceptId field target alternative) =
  Okf.renderConceptId conceptId
    <> ": frontmatter field "
    <> field
    <> " names a path that is not in the bundle: "
    <> T.pack target
    <> maybe "" (\alt -> " (did you mean " <> T.pack alt <> "?)") alternative
renderBundleValidationError (DuplicateConceptId conceptId) =
  "duplicate concept ID: " <> Okf.renderConceptId conceptId
renderBundleValidationError (LogInvalid path err) =
  T.pack path <> ": " <> renderLogValidationError err
renderBundleValidationError (BundleVersionUnparseable raw) =
  "bundle root index declares an unparseable OKF version: " <> raw
renderBundleValidationError (BundleVersionNotUnderstood raw) =
  "bundle root index declares an OKF version this tool does not understand: " <> raw

-- | Total by construction; see 'renderBundleValidationError'.
renderLogValidationError :: LogValidationError -> T.Text
renderLogValidationError (LogDateNotIso raw) =
  "log day heading is not an ISO-8601 date: " <> raw
renderLogValidationError (LogDaysOutOfOrder earlier later) =
  "log days are out of order: " <> earlier <> " appears before " <> later
renderLogValidationError (LogEmptyDay day) =
  "log day has no entries: " <> day

-- | Total by construction; see 'renderBundleValidationError'.
renderValidationError :: ValidationError -> T.Text
renderValidationError (MissingRequiredField field) =
  "missing required field: " <> field
renderValidationError (FieldMustBeNonEmptyText field) =
  "field must be non-empty text: " <> field
renderValidationError (MissingRecommendedField field) =
  "missing recommended field: " <> field
renderValidationError (FieldMustBeListOfText field) =
  "field must be a list of text: " <> field
renderValidationError MissingGeneratedField =
  "concept records neither a generated block nor a legacy timestamp"
renderValidationError GeneratedMustHaveActor =
  "concept has a generated block with no by actor"
renderValidationError (SourceMissingResource index) =
  "sources entry " <> T.pack (show index) <> " has no resource"
renderValidationError (DuplicateSourceId sourceId) =
  "two sources entries share the id: " <> sourceId
renderValidationError (FootnoteLabelNotInSources label) =
  "body cites footnote label with no matching sources entry: " <> label
renderValidationError (SourceIdNotCited sourceId) =
  "sources entry is never cited in the body: " <> sourceId
renderValidationError (LegacyFieldInDeclaredV2 field) =
  "concept uses the superseded OKF v0.1 field " <> field <> " in a bundle declaring v0.2"
renderValidationError AttestedComputationMissingRuntime =
  "Attested Computation concept declares no runtime"
renderValidationError AttestedComputationHasNoComputation =
  "Attested Computation concept offers neither a computation path nor a body code block"
renderValidationError AttestedComputationHasBothComputations =
  "Attested Computation concept offers both a computation path and a body code block"
renderValidationError (AttestedComputationHasManyBlocks count) =
  "Attested Computation section holds "
    <> T.pack (show count)
    <> " code blocks; exactly one is permitted"

renderMany :: (a -> T.Text) -> [a] -> T.Text
renderMany render = T.intercalate "\n" . fmap render

-- | Render one house-profile deviation.
--
-- okf-core reports 'ProfileViolation' but does not render it: the renderer
-- lives in the @okf-cli@ package, which this repository does not depend on.
-- Total by construction, for the reason 'renderBundleValidationError' gives.
renderProfileViolation :: ProfileViolation -> T.Text
renderProfileViolation (TypeNotInProfile conceptId conceptType) =
  at conceptId <> "type " <> conceptType <> " is not one this profile declares"
renderProfileViolation (MissingProfileField conceptId key condition) =
  at conceptId <> "missing required field " <> key <> renderFieldCondition condition
renderProfileViolation (MissingRecommendedProfileField conceptId key condition) =
  at conceptId <> "missing recommended field " <> key <> renderFieldCondition condition
renderProfileViolation (MissingNestedProfileField conceptId path condition) =
  at conceptId <> "missing required field " <> renderFieldPath path <> renderFieldCondition condition
renderProfileViolation (MissingRecommendedNestedProfileField conceptId path condition) =
  at conceptId <> "missing recommended field " <> renderFieldPath path <> renderFieldCondition condition
renderProfileViolation (ValueNotInVocabulary conceptId path allowed value) =
  at conceptId
    <> renderFieldPath path
    <> " holds "
    <> renderJson value
    <> ", which is not one of "
    <> T.intercalate ", " allowed
renderProfileViolation (CardinalityMismatch conceptId path cardinality value) =
  at conceptId
    <> renderFieldPath path
    <> " must be "
    <> renderCardinalityName cardinality
    <> ", but holds "
    <> renderJson value
renderProfileViolation (ValueFormatMismatch conceptId path format value) =
  at conceptId
    <> renderFieldPath path
    <> " must be "
    <> renderFieldFormatName format
    <> ", but holds "
    <> renderJson value
renderProfileViolation (DanglingHandleReference conceptId path handle) =
  at conceptId <> renderFieldPath path <> " references handle " <> handle <> ", which nothing in this bundle owns"
renderProfileViolation (ReferenceHandlePrefixMismatch conceptId path expected actual) =
  at conceptId <> renderFieldPath path <> " expects handle prefix " <> expected <> ", but holds " <> actual
renderProfileViolation (MalformedDocumentReference conceptId path value) =
  at conceptId <> renderFieldPath path <> " is neither a local handle nor an absolute URI: " <> renderJson value
renderProfileViolation (ExternalReferenceSchemeNotAllowed conceptId path scheme allowed) =
  at conceptId
    <> renderFieldPath path
    <> " uses URI scheme "
    <> scheme
    <> ", which this profile does not permit; allowed: "
    <> T.intercalate ", " allowed
renderProfileViolation (LocalDocumentReferenceNotAllowed conceptId path handle) =
  at conceptId <> renderFieldPath path <> " may not hold a local handle, but holds " <> handle
renderProfileViolation (ExternalReferencePatternMismatch conceptId path value pattern_) =
  at conceptId <> renderFieldPath path <> " holds " <> value <> ", which does not match " <> pattern_
renderProfileViolation (SelfDocumentReference conceptId path value) =
  at conceptId <> renderFieldPath path <> " references the concept it is written on: " <> value
renderProfileViolation (MalformedPathReference conceptId path value) =
  at conceptId <> renderFieldPath path <> " is not a usable path or URI: " <> renderJson value
renderProfileViolation (PathEscapesBundle conceptId path value) =
  at conceptId <> renderFieldPath path <> " climbs above the bundle root: " <> value
renderProfileViolation (DanglingPathReference conceptId path target) =
  at conceptId <> renderFieldPath path <> " names a path that is not in this bundle: " <> target
renderProfileViolation (FieldNotInProfile conceptId key) =
  at conceptId <> "field " <> key <> " is not one this profile declares"
renderProfileViolation (NestedElementNotRecord conceptId path value) =
  at conceptId <> renderFieldPath path <> " must be a record, but holds " <> renderJson value
renderProfileViolation (DuplicateNestedFieldValue conceptId path value indexes) =
  at conceptId
    <> renderFieldPath path
    <> " repeats the value "
    <> renderJson value
    <> " at elements "
    <> T.intercalate ", " (T.pack . show <$> NonEmpty.toList indexes)
renderProfileViolation (PathPatternMismatch conceptId conceptType pattern_) =
  at conceptId <> conceptType <> " concepts must live at " <> pattern_
renderProfileViolation (MissingResource conceptId conceptType scheme) =
  at conceptId <> conceptType <> " concepts must carry a " <> scheme <> ": resource"
renderProfileViolation (ResourceSchemeMismatch conceptId scheme resource) =
  at conceptId <> "resource must use the " <> scheme <> " scheme, but is " <> resource
renderProfileViolation (MissingSchemaSection conceptId conceptType) =
  at conceptId <> conceptType <> " concepts must carry a # Schema section"
renderProfileViolation (SchemaColumnsMismatch conceptId conceptType expected actual) =
  at conceptId
    <> conceptType
    <> " # Schema columns must be "
    <> T.intercalate ", " expected
    <> ", but are "
    <> T.intercalate ", " actual
renderProfileViolation (MissingDocumentId conceptId conceptType prefix) =
  at conceptId <> conceptType <> " concepts must carry a " <> prefix <> "-N handle"
renderProfileViolation (MalformedDocumentId conceptId prefix value) =
  at conceptId <> "handle " <> value <> " is not well formed for prefix " <> prefix
renderProfileViolation (DuplicateDocumentId handle conceptId other) =
  "handle "
    <> handle
    <> " is claimed by both "
    <> Okf.renderConceptId conceptId
    <> " and "
    <> Okf.renderConceptId other
renderProfileViolation (RequiredBundleVersionUnmet required declared) =
  "bundle must declare OKF version "
    <> required
    <> " or later, but declares "
    <> maybe "nothing" id declared

at :: Okf.ConceptId -> T.Text
at conceptId = Okf.renderConceptId conceptId <> ": "

renderFieldCondition :: Maybe FieldCondition -> T.Text
renderFieldCondition =
  foldMap
    ( \FieldCondition {field, hasValue} ->
        " (required when " <> field <> " is " <> T.intercalate " or " hasValue <> ")"
    )

-- | A frontmatter field path, in the dotted form the descriptor writes it in.
renderFieldPath :: FieldPath -> T.Text
renderFieldPath FieldPath {segments} =
  T.intercalate "." (renderFieldPathSegment <$> NonEmpty.toList segments)

renderFieldPathSegment :: FieldPathSegment -> T.Text
renderFieldPathSegment (FieldName name) = name
renderFieldPathSegment (ArrayIndex index) = "[" <> T.pack (show index) <> "]"

renderJson :: Value -> T.Text
renderJson = TL.toStrict . TLB.toLazyText . Aeson.encodeToTextBuilder
