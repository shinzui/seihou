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
import Okf.ConceptId qualified as Okf
import Okf.Validation (BundleValidationError (..), ValidationError (..))
import Seihou.OKF.Docs.Model
import Seihou.OKF.Docs.Render
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
    force :: !Bool
  }
  deriving stock (Eq, Generic, Show)

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
              case renderDocBundle model of
                Left renderErrors ->
                  pure (Left (renderMany renderDocRenderError renderErrors))
                Right (concepts, validationProblems)
                  | not (null validationProblems) ->
                      pure (Left (renderMany renderBundleValidationError validationProblems))
                  | otherwise -> do
                      prepareOutputDirectory (opts ^. #out)
                      writeResult <- writeDocBundle (opts ^. #out) model
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

renderDocRenderError :: DocRenderError -> T.Text
renderDocRenderError (InvalidDocConceptId kind name err) =
  "invalid OKF concept ID for " <> T.pack (show kind) <> " " <> name <> ": " <> err

renderBundleValidationError :: BundleValidationError -> T.Text
renderBundleValidationError (DocumentInvalid conceptId err) =
  Okf.renderConceptId conceptId <> ": " <> renderValidationError err
renderBundleValidationError (DanglingReference source target) =
  Okf.renderConceptId source <> ": link to missing concept: " <> Okf.renderConceptId target
renderBundleValidationError (DuplicateConceptId conceptId) =
  "duplicate concept ID: " <> Okf.renderConceptId conceptId

renderValidationError :: ValidationError -> T.Text
renderValidationError (MissingRequiredField field) =
  "missing required field: " <> field
renderValidationError (FieldMustBeNonEmptyText field) =
  "field must be non-empty text: " <> field
renderValidationError (MissingRecommendedField field) =
  "missing recommended field: " <> field

renderMany :: (a -> T.Text) -> [a] -> T.Text
renderMany render = T.intercalate "\n" . fmap render
