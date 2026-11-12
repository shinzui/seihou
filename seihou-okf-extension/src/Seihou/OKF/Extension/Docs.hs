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
    ProfileDefinitionError (..),
    ProfileViolation (..),
    ValueSelector (..),
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
    renameDirectory,
  )
import System.Exit (exitFailure)
import System.FilePath (takeDirectory, (</>))
import System.IO (stderr)
import System.IO.Temp (withTempDirectory)

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
                      -- Complete validation, profile copying and index writing
                      -- before replacing output. In particular, --profile may
                      -- name the descriptor inside the bundle being replaced.
                      let parent = takeDirectory (opts ^. #out)
                      createDirectoryIfMissing True parent
                      withTempDirectory parent ".seihou-okf-docs" $ \staging -> do
                        writeResult <- writeDocBundle (renderOptionsFor opts) staging model
                        case writeResult of
                          Left errors -> pure (Left (renderMany renderDocBundleError errors))
                          Right () -> do
                            replaceOutputDirectory staging (opts ^. #out)
                            pure (Right ("Wrote " <> T.pack (show (length concepts)) <> " concepts to " <> T.pack (opts ^. #out)))

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

replaceOutputDirectory :: FilePath -> FilePath -> IO ()
replaceOutputDirectory staging outDir = do
  exists <- doesDirectoryExist outDir
  when exists (removeDirectoryRecursive outDir)
  renameDirectory staging outDir

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
    <> T.intercalate "; " (renderProfileDefinitionError <$> NonEmpty.toList errs)
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
renderProfileViolation (ConstraintPresenceMissing conceptId path condition) =
  at conceptId <> "constraint requires field " <> renderFieldPath path <> renderFieldCondition condition
renderProfileViolation (ConstraintAlternativeMissing conceptId paths condition) =
  at conceptId <> "constraint requires one of " <> T.intercalate ", " (renderFieldPath <$> paths) <> renderFieldCondition condition
renderProfileViolation (TimestampOrderViolation conceptId before after) =
  at conceptId <> renderFieldPath before <> " must precede " <> renderFieldPath after
renderProfileViolation (TextOperandMismatch conceptId path value) =
  at conceptId <> renderFieldPath path <> " must hold text for this constraint, but holds " <> renderJson value
renderProfileViolation (MembershipValueMissing conceptId path value selector) =
  at conceptId <> renderFieldPath path <> " holds " <> value <> ", which is absent from " <> renderValueSelector selector
renderProfileViolation (DuplicateSelectedValue conceptId path value other) =
  at conceptId <> renderFieldPath path <> " repeats " <> value <> " from " <> renderFieldPath other
renderProfileViolation (NestedFieldNotInProfile conceptId path) =
  at conceptId <> "nested field " <> renderFieldPath path <> " is not one this profile declares"
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

renderValueSelector :: ValueSelector -> T.Text
renderValueSelector ValueSelector {field, member} = field <> foldMap ("[]." <>) member

-- Adapted from the diagnostic contract of mori://shinzui/okf/packages/okf-cli.
renderProfileDefinitionError :: ProfileDefinitionError -> T.Text
renderProfileDefinitionError = \case
  InvalidConceptConstraint scope parent sel reason -> renderScope scope <> ": invalid constraint " <> maybe "" (<> ".") parent <> renderValueSelector sel <> ": " <> reason
  DuplicateTypeRule ctype -> "duplicate type rule: " <> ctype
  DuplicateFieldRule scope listName key ->
    renderScope scope <> ": duplicate " <> listName <> " field: " <> key
  ConflictingFieldRequirement scope key ->
    renderScope scope <> ": field appears in more than one of required, recommended, and optional: " <> key
  UnsatisfiableVocabulary scope key profileValues typeValues ->
    renderScope scope
      <> ": disjoint allowed values for "
      <> key
      <> " (profile: ["
      <> T.intercalate ", " profileValues
      <> "], type: ["
      <> T.intercalate ", " typeValues
      <> "])"
  ConflictingCardinality scope key profileCardinality typeCardinality ->
    renderScope scope
      <> ": conflicting cardinality for "
      <> key
      <> " (profile: "
      <> renderCardinalityName profileCardinality
      <> ", type: "
      <> renderCardinalityName typeCardinality
      <> ")"
  ElementFieldsRequireList scope fieldPath actualCardinality ->
    renderScope scope
      <> ": elementFields at "
      <> renderFieldPath fieldPath
      <> " requires list cardinality, found: "
      <> renderCardinalityName actualCardinality
  ObjectFieldsRequireObjectShape scope fieldPath actualCardinality ->
    renderScope scope
      <> ": objectFields at "
      <> renderFieldPath fieldPath
      <> " cannot be combined with cardinality "
      <> renderCardinalityName actualCardinality
  InvalidFormatParameter fieldPath fieldFormat parameter ->
    "invalid parameter for format "
      <> renderFieldFormatName fieldFormat
      <> " at "
      <> renderFieldPath fieldPath
      <> ": "
      <> parameter
  ConflictingFieldFormat fieldPath profileFormat typeFormat ->
    "conflicting formats for "
      <> renderFieldPath fieldPath
      <> " (profile: "
      <> renderFieldFormatName profileFormat
      <> ", type: "
      <> renderFieldFormatName typeFormat
      <> ")"
  EmptyConditionValues scope target source ->
    renderConditionDefinition scope target source <> " has an empty hasValue list"
  ConditionFieldNotDeclared scope target source ->
    renderConditionDefinition scope target source <> " names an undeclared source field"
  ConditionFieldNotScalar scope target source actualCardinality ->
    renderConditionDefinition scope target source
      <> " requires scalar cardinality, found: "
      <> renderCardinalityName actualCardinality
  ConditionFieldOpenVocabulary scope target source ->
    renderConditionDefinition scope target source <> " requires a non-empty allowedValues vocabulary"
  ConditionFieldHasUnreachableValues scope target source unreachable allowed ->
    renderConditionDefinition scope target source
      <> " contains unreachable values ["
      <> T.intercalate ", " unreachable
      <> "]; source allows ["
      <> T.intercalate ", " allowed
      <> "]"
  SelfConditionalField scope target ->
    renderScope scope <> ": field cannot condition its own presence: " <> renderFieldPath target
  InvalidReferencePrefix scope target prefix ->
    renderScope scope <> ": invalid local reference prefix at " <> renderFieldPath target <> ": " <> prefix
  ReferencePrefixNotDeclared scope target prefix ->
    renderScope scope
      <> ": local reference prefix at "
      <> renderFieldPath target
      <> " is not declared by any type: "
      <> prefix
  ReferenceRequiresIdField scope target ->
    renderScope scope <> ": reference at " <> renderFieldPath target <> " requires profile idField"
  InvalidExternalReferenceScheme scope target scheme ->
    renderScope scope <> ": invalid external reference scheme at " <> renderFieldPath target <> ": " <> scheme
  ConflictingReferencePrefix ctype target profilePrefix typePrefix ->
    "type "
      <> ctype
      <> " frontmatter: conflicting local reference prefixes for "
      <> renderFieldPath target
      <> " (profile: "
      <> profilePrefix
      <> ", type: "
      <> typePrefix
      <> ")"
  ReferenceWithFormat scope target fieldFormat ->
    renderScope scope
      <> ": reference at "
      <> renderFieldPath target
      <> " cannot also declare format "
      <> renderFieldFormatName fieldFormat
  OptionalFieldWithCondition scope target ->
    renderScope scope
      <> ": optional field cannot carry a when condition: "
      <> renderFieldPath target
  PathReferenceWithHandleReference scope target ->
    renderScope scope
      <> ": path at "
      <> renderFieldPath target
      <> " cannot also declare a document reference; a value is resolved as one or the other"
  InvalidExternalUriPattern scope target patternText detail ->
    renderScope scope
      <> ": invalid external URI pattern at "
      <> renderFieldPath target
      <> ": "
      <> patternText
      <> " ("
      <> detail
      <> ")"
  ConflictingExternalUriPatterns ctype target profilePattern typePattern ->
    "type "
      <> ctype
      <> " frontmatter: conflicting external URI patterns for "
      <> renderFieldPath target
      <> " (profile: "
      <> profilePattern
      <> ", type: "
      <> typePattern
      <> ")"
  UniqueByRequiresElementFields scope target key ->
    renderScope scope
      <> ": uniqueBy at "
      <> renderFieldPath target
      <> " names "
      <> key
      <> " but the field has no elementFields"
  UniqueByFieldNotDeclared scope target ->
    renderScope scope <> ": uniqueBy field is not declared at " <> renderFieldPath target
  UniqueByFieldNotUnconditionallyRequired scope target ->
    renderScope scope <> ": uniqueBy field must be unconditionally required at " <> renderFieldPath target
  UniqueByFieldNotScalar scope target actualCardinality ->
    renderScope scope
      <> ": uniqueBy field must be scalar at "
      <> renderFieldPath target
      <> ", found: "
      <> renderCardinalityName actualCardinality
  ConflictingUniqueBy ctype target profileKey typeKey ->
    "type "
      <> ctype
      <> " frontmatter: conflicting uniqueBy keys for "
      <> renderFieldPath target
      <> " (profile: "
      <> profileKey
      <> ", type: "
      <> typeKey
      <> ")"
  -- Each version message names *both* halves of the contradiction. One that said
  -- only "field requires OKF 0.2" would leave the author hunting for where the
  -- version is declared, which is the other end of the file.
  InvalidProfileOkfVersion rawVersion ->
    "okfVersion is not <major>.<minor>: " <> rawVersion
  ProfileOkfVersionNotUnderstood rawVersion ->
    "okfVersion "
      <> rawVersion
      <> " names an OKF major version this okf does not implement (supported: "
      <> "0.2"
      <> ")"
  InvalidRequiredBundleVersion rawVersion ->
    "requireBundleVersion is not <major>.<minor>: " <> rawVersion
  FieldSupersededInOkfVersion scope target declared supersededIn ->
    renderScope scope
      <> ": declared okfVersion "
      <> declared
      <> " supersedes the frontmatter key "
      <> renderFieldPath target
      <> " (OKF "
      <> supersededIn
      <> "); move it to the optional list"
  FormatRequiresOkfVersion scope target fieldFormat declared introducedIn ->
    renderScope scope
      <> ": declared okfVersion "
      <> declared
      <> " does not support the format "
      <> renderFieldFormatName fieldFormat
      <> " at "
      <> renderFieldPath target
      <> ", which OKF "
      <> introducedIn
      <> " introduced"
  where
    renderScope Nothing = "profile frontmatter"
    renderScope (Just ctype) = "type " <> ctype <> " frontmatter"
    renderConditionDefinition scope target source =
      renderScope scope
        <> ": condition for "
        <> renderFieldPath target
        <> " on "
        <> renderFieldPath source
