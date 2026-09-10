module Seihou.OKF.Extension.Docs
  ( DocsOpts (..),
    runDocs,
    handleDocs,
    renderDocBundleError,
  )
where

import Control.Lens ((^.))
import Control.Monad (when)
import Data.Generics.Labels ()
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import GHC.Generics (Generic)
import Okf.Bundle (BundleError (..))
import Okf.ConceptId qualified as Okf
import Okf.Document (DocumentParseError (..))
import Okf.Log (LogValidationError (..))
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
    permissive :: !Bool
  }
  deriving stock (Eq, Generic, Show)

-- | The renderer configuration these command-line options describe.
renderOptionsFor :: DocsOpts -> RenderOptions
renderOptionsFor opts =
  RenderOptions
    { producerVersion = extensionVersion,
      generatedAt = opts ^. #generatedAt,
      validationProfile =
        if opts ^. #permissive then PermissiveConformance else StrictAuthoring
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
