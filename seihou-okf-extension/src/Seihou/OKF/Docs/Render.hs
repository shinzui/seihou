module Seihou.OKF.Docs.Render
  ( conceptIdFor,
    DocRenderError (..),
    DocBundleError (..),
    renderDocBundle,
    writeDocBundle,
  )
where

import Data.Aeson (Value (..))
import Data.Bifunctor (first)
import Data.Either (partitionEithers)
import Data.Text qualified as T
import Okf.Bundle (Concept, conceptFromDocument, writeBundle)
import Okf.ConceptId (ConceptId, parseConceptId, renderConceptLink)
import Okf.Document qualified as Okf
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

data DocRenderError
  = InvalidDocConceptId DocKind T.Text T.Text
  deriving stock (Eq, Show)

data DocBundleError
  = DocBundleRenderError DocRenderError
  | DocBundleValidationError BundleValidationError
  deriving stock (Eq, Show)

conceptIdFor :: DocKind -> T.Text -> Either T.Text ConceptId
conceptIdFor kind name =
  first (T.pack . show) (parseConceptId (conceptIdTextFor kind name))

renderDocBundle :: DocModel -> Either [DocRenderError] ([Concept], [BundleValidationError])
renderDocBundle model =
  case partitionEithers (conceptFor model.docRepoName <$> model.docEntries) of
    ([], concepts) ->
      Right (concepts, validateBundle PermissiveConformance concepts)
    (errors, _) ->
      Left errors

-- | Write concepts into the output directory. This overwrites files it writes but does
-- not clear unrelated files; callers that need pristine regeneration should clear the
-- output directory before calling this function.
writeDocBundle :: FilePath -> DocModel -> IO (Either [DocBundleError] ())
writeDocBundle outDir model =
  case renderDocBundle model of
    Left renderErrors ->
      pure (Left (DocBundleRenderError <$> renderErrors))
    Right (concepts, validationErrors)
      | null validationErrors -> Right <$> writeBundle outDir concepts
      | otherwise -> pure (Left (DocBundleValidationError <$> validationErrors))

conceptFor :: T.Text -> DocEntry -> Either DocRenderError Concept
conceptFor repoName entry =
  case conceptIdFor entry.entryKind entry.entryName of
    Left err ->
      Left (InvalidDocConceptId entry.entryKind entry.entryName err)
    Right conceptId ->
      Right (conceptFromDocument conceptId (documentFor repoName entry))

documentFor :: T.Text -> DocEntry -> Okf.OKFDocument
documentFor repoName entry =
  Okf.OKFDocument
    (frontmatterFor repoName entry)
    (bodyFor entry)

frontmatterFor :: T.Text -> DocEntry -> Okf.Frontmatter
frontmatterFor repoName entry =
  maybeSetVersion
    . Okf.setTags entry.entryTags
    . Okf.setResource (resourceFor repoName entry)
    $ Okf.okfCommon
      Okf.OkfCommon
        { Okf.commonType = typeFor entry.entryKind,
          Okf.commonTitle = Just entry.entryName,
          Okf.commonDescription = entry.entryDescription,
          Okf.commonTimestamp = Nothing
        }
  where
    maybeSetVersion =
      maybe id (\version -> Okf.setField "version" (String version)) entry.entryVersion

resourceFor :: T.Text -> DocEntry -> T.Text
resourceFor repoName entry =
  "seihou://" <> repoName <> "/" <> T.pack entry.entryPath

bodyFor :: DocEntry -> T.Text
bodyFor entry =
  T.intercalate
    "\n\n"
    ( baseSections entry
        <> kindSections entry
    )
    <> "\n"

baseSections :: DocEntry -> [T.Text]
baseSections entry =
  [ "# " <> entry.entryName,
    maybe "No description provided." id entry.entryDescription
  ]
    <> foldMap (\version -> ["**Version:** " <> version]) entry.entryVersion

kindSections :: DocEntry -> [T.Text]
kindSections entry =
  case entry.entryArtifact of
    DocModuleArtifact Module {vars, exports} ->
      [ "## Dependencies\n\n" <> renderModuleRefs "This module has no dependencies." entry.entryModuleRefs,
        "## Variables\n\n" <> renderVarDecls vars,
        "## Exports\n\n" <> renderExports exports
      ]
    DocRecipeArtifact _ ->
      ["## Composes\n\n" <> renderModuleRefs "This recipe does not compose any modules." entry.entryModuleRefs]
    DocBlueprintArtifact Blueprint {prompt, files} ->
      [ "## Base modules\n\n" <> renderModuleRefs "This blueprint declares no base modules." entry.entryModuleRefs,
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
    _ -> T.unlines ["- " <> moduleLink ref.refName | ref <- refs]

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
