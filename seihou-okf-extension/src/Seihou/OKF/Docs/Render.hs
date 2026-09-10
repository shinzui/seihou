module Seihou.OKF.Docs.Render
  ( conceptIdFor,
    RenderOptions (..),
    defaultRenderOptions,
    DocRenderError (..),
    DocBundleError (..),
    renderDocBundle,
    writeDocBundle,
  )
where

import Control.Lens ((^.))
import Data.Aeson (Value (..))
import Data.Bifunctor (first)
import Data.Either (partitionEithers)
import Data.Generics.Labels ()
import Data.Text qualified as T
import GHC.Generics (Generic)
import Okf.Actor (Actor (..))
import Okf.Bundle (BundleError, Concept, bundleInventoryOfConcepts, conceptFromDocument, writeBundle)
import Okf.ConceptId (ConceptId, parseConceptId, renderConceptLink)
import Okf.Document qualified as Okf
import Okf.Index (VersionDeclaration (..), supportedOkfVersion, writeBundleIndexesWith)
import Okf.Validation (BundleValidationError, ValidationProfile (..), validateBundle)
import Seihou.Core.Types
  ( AgentPrompt (..),
    Blueprint (..),
    BlueprintFile (..),
    Module (..),
    Recipe (..),
    VarDecl (..),
    VarExport (..),
    VarName (..),
  )
import Seihou.OKF.Docs.Model
import Seihou.OKF.Extension.Version (producerActorName)

-- | Everything the renderer needs that is not in the model: who to name as the
-- producer, whether to stamp a generation date, and how strictly to validate.
--
-- 'generatedAt' is deliberately a value the operator supplies rather than a
-- clock reading. Nothing in the generator reads the clock, so regenerating an
-- unchanged registry produces byte-identical output.
data RenderOptions = RenderOptions
  { producerVersion :: !T.Text,
    generatedAt :: !(Maybe T.Text),
    validationProfile :: !ValidationProfile
  }
  deriving stock (Eq, Generic, Show)

-- | Strict validation with no generation date, for the given producer version.
defaultRenderOptions :: T.Text -> RenderOptions
defaultRenderOptions version =
  RenderOptions
    { producerVersion = version,
      generatedAt = Nothing,
      validationProfile = StrictAuthoring
    }

data DocRenderError
  = InvalidDocConceptId DocKind T.Text T.Text
  deriving stock (Eq, Show)

data DocBundleError
  = DocBundleRenderError DocRenderError
  | DocBundleValidationError BundleValidationError
  | -- | Writing the bundle\'s @index.md@ files failed after the concepts were
    -- written, so the bundle on disk is missing its version declaration and its
    -- per-kind section indexes.
    DocBundleIndexError BundleError
  deriving stock (Eq, Show)

conceptIdFor :: DocKind -> T.Text -> Either T.Text ConceptId
conceptIdFor kind name =
  first (T.pack . show) (parseConceptId (conceptIdTextFor kind name))

renderDocBundle :: RenderOptions -> DocModel -> Either [DocRenderError] ([Concept], [BundleValidationError])
renderDocBundle opts model =
  case partitionEithers (conceptFor opts (model ^. #repoName) <$> model ^. #entries) of
    ([], concepts) ->
      Right
        ( concepts,
          validateBundle
            (opts ^. #validationProfile)
            (VersionDeclared supportedOkfVersion)
            (bundleInventoryOfConcepts concepts)
            concepts
        )
    (errors, _) ->
      Left errors

-- | Write concepts into the output directory. This overwrites files it writes but does
-- not clear unrelated files; callers that need pristine regeneration should clear the
-- output directory before calling this function.
writeDocBundle :: RenderOptions -> FilePath -> DocModel -> IO (Either [DocBundleError] ())
writeDocBundle opts outDir model =
  case renderDocBundle opts model of
    Left renderErrors ->
      pure (Left (DocBundleRenderError <$> renderErrors))
    Right (concepts, validationErrors)
      | null validationErrors -> do
          writeBundle outDir concepts
          -- Walk what was just written and lay down the root index (carrying the
          -- OKF version declaration, the one place a bundle states it) plus one
          -- index per subdirectory.
          indexResult <- writeBundleIndexesWith (Just supportedOkfVersion) outDir
          pure (first (pure . DocBundleIndexError) indexResult)
      | otherwise -> pure (Left (DocBundleValidationError <$> validationErrors))

conceptFor :: RenderOptions -> T.Text -> DocEntry -> Either DocRenderError Concept
conceptFor opts repoName entry =
  case conceptIdFor (entry ^. #kind) (entry ^. #name) of
    Left err ->
      Left (InvalidDocConceptId (entry ^. #kind) (entry ^. #name) err)
    Right conceptId ->
      Right (conceptFromDocument conceptId (documentFor opts repoName entry))

documentFor :: RenderOptions -> T.Text -> DocEntry -> Okf.OKFDocument
documentFor opts repoName entry =
  Okf.OKFDocument
    (frontmatterFor opts repoName entry)
    (bodyFor repoName entry)

frontmatterFor :: RenderOptions -> T.Text -> DocEntry -> Okf.Frontmatter
frontmatterFor opts repoName entry =
  maybeSetVersion
    . Okf.setGenerated generated
    . Okf.setStatus Okf.Stable
    . Okf.setTags (entry ^. #tags)
    . Okf.setResource (resourceFor repoName entry)
    $ Okf.okfCommon
      Okf.OkfCommon
        { Okf.commonType = typeFor (entry ^. #kind),
          Okf.commonTitle = Just (entry ^. #name),
          Okf.commonDescription = Just (descriptionFor repoName entry),
          Okf.commonTimestamp = Nothing
        }
  where
    maybeSetVersion =
      maybe id (\version -> Okf.setField "version" (String version)) (entry ^. #version)
    generated =
      Okf.Generated
        { Okf.generatedBy = ProducerActor producerActorName (opts ^. #producerVersion),
          Okf.generatedAt = opts ^. #generatedAt
        }

-- | The description strict validation insists on, in three deterministic steps:
-- what the registry catalog says about the entry, then what the artifact says
-- about itself, then a synthesized sentence. Frontmatter and the body\'s opening
-- paragraph both use this, so the two can never disagree.
descriptionFor :: T.Text -> DocEntry -> T.Text
descriptionFor repoName entry =
  case nonEmpty (entry ^. #description) of
    Just described -> described
    Nothing ->
      case nonEmpty (artifactDescription (entry ^. #artifact)) of
        Just described -> described
        Nothing ->
          "Seihou "
            <> kindNoun (entry ^. #kind)
            <> " `"
            <> entry ^. #name
            <> "` published by the `"
            <> repoName
            <> "` registry."
  where
    nonEmpty = (>>= \text -> if T.null (T.strip text) then Nothing else Just text)

artifactDescription :: DocArtifact -> Maybe T.Text
artifactDescription (DocModuleArtifact Module {description}) = description
artifactDescription (DocRecipeArtifact Recipe {description}) = description
artifactDescription (DocBlueprintArtifact Blueprint {description}) = description
artifactDescription (DocPromptArtifact AgentPrompt {description}) = description

kindNoun :: DocKind -> T.Text
kindNoun DocModuleKind = "module"
kindNoun DocRecipeKind = "recipe"
kindNoun DocBlueprintKind = "blueprint"
kindNoun DocPromptKind = "agent prompt"

resourceFor :: T.Text -> DocEntry -> T.Text
resourceFor repoName entry =
  "seihou://" <> repoName <> "/" <> T.pack (entry ^. #path)

bodyFor :: T.Text -> DocEntry -> T.Text
bodyFor repoName entry =
  T.intercalate
    "\n\n"
    ( baseSections repoName entry
        <> kindSections entry
    )
    <> "\n"

baseSections :: T.Text -> DocEntry -> [T.Text]
baseSections repoName entry =
  [ "# " <> entry ^. #name,
    descriptionFor repoName entry
  ]
    <> foldMap (\version -> ["**Version:** " <> version]) (entry ^. #version)

kindSections :: DocEntry -> [T.Text]
kindSections entry =
  case entry ^. #artifact of
    DocModuleArtifact Module {vars, exports} ->
      [ "## Dependencies\n\n" <> renderModuleRefs "This module has no dependencies." (entry ^. #moduleRefs),
        "## Variables\n\n" <> renderVarDecls vars,
        "## Exports\n\n" <> renderExports exports
      ]
    DocRecipeArtifact Recipe {} ->
      ["## Composes\n\n" <> renderModuleRefs "This recipe does not compose any modules." (entry ^. #moduleRefs)]
    DocBlueprintArtifact Blueprint {prompt, files} ->
      [ "## Base modules\n\n" <> renderModuleRefs "This blueprint declares no base modules." (entry ^. #moduleRefs),
        "## Agent prompt\n\n" <> firstParagraph prompt,
        "## Reference files\n\n" <> renderBlueprintFiles files
      ]
    DocPromptArtifact AgentPrompt {prompt, files, allowedTools} ->
      [ "## Agent prompt\n\n" <> firstParagraph prompt,
        "## Reference files\n\n" <> renderBlueprintFiles files,
        "## Tools\n\n" <> maybe "No tool restrictions declared." renderTextList allowedTools
      ]

renderModuleRefs :: T.Text -> [ModuleRef] -> T.Text
renderModuleRefs emptyMessage refs =
  case refs of
    [] -> emptyMessage
    _ -> T.unlines ["- " <> moduleLink (ref ^. #name) | ref <- refs]

moduleLink :: T.Text -> T.Text
moduleLink name =
  case conceptIdFor DocModuleKind name of
    Right conceptId -> renderConceptLink conceptId name
    Left _ -> "`" <> name <> "`"

renderVarDecls :: [VarDecl] -> T.Text
renderVarDecls [] = "No variables declared."
renderVarDecls vars =
  T.unlines ["- `" <> varName <> "`" <> requiredLabel required | VarDecl {name = VarName varName, required} <- vars]

requiredLabel :: Bool -> T.Text
requiredLabel required
  | required = " (required)"
  | otherwise = ""

renderExports :: [VarExport] -> T.Text
renderExports [] = "No exports declared."
renderExports exports =
  T.unlines ["- `" <> varName <> "`" | VarExport {var = VarName varName} <- exports]

renderBlueprintFiles :: [BlueprintFile] -> T.Text
renderBlueprintFiles [] = "No reference files declared."
renderBlueprintFiles files =
  T.unlines
    [ "- `" <> T.pack src <> "`" <> maybe "" (" - " <>) description
    | BlueprintFile {src, description} <- files
    ]

renderTextList :: [T.Text] -> T.Text
renderTextList [] = "No tool restrictions declared."
renderTextList values = T.unlines ["- `" <> value <> "`" | value <- values]

firstParagraph :: T.Text -> T.Text
firstParagraph text =
  case T.splitOn "\n\n" text of
    [] -> "No prompt text provided."
    paragraph : _ ->
      case T.strip paragraph of
        "" -> "No prompt text provided."
        stripped -> stripped

conceptIdTextFor :: DocKind -> T.Text -> T.Text
conceptIdTextFor kind name = kindDir kind <> "/" <> name

kindDir :: DocKind -> T.Text
kindDir DocModuleKind = "modules"
kindDir DocRecipeKind = "recipes"
kindDir DocBlueprintKind = "blueprints"
kindDir DocPromptKind = "prompts"

typeFor :: DocKind -> T.Text
typeFor DocModuleKind = "SeihouModule"
typeFor DocRecipeKind = "SeihouRecipe"
typeFor DocBlueprintKind = "SeihouBlueprint"
typeFor DocPromptKind = "SeihouPrompt"
