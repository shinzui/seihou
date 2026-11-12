{-# LANGUAGE TemplateHaskell #-}

module Seihou.OKF.Docs.Render
  ( conceptIdFor,
    RenderOptions (..),
    defaultRenderOptions,
    DocRenderError (..),
    DocBundleError (..),
    builtinProfileDescriptor,
    profileFileName,
    renderDocBundle,
    checkDocProfile,
    writeDocBundle,
  )
where

import Control.Lens ((^.))
import Data.Aeson (Value (..))
import Data.Aeson.Text qualified as Aeson
import Data.Bifunctor (first)
import Data.Either (partitionEithers)
import Data.FileEmbed (embedStringFile)
import Data.Foldable (toList)
import Data.Generics.Labels ()
import Data.List.NonEmpty (NonEmpty)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Text.Lazy qualified as TL
import GHC.Generics (Generic)
import Okf.Actor (Actor (..))
import Okf.Bundle (BundleError, Concept, bundleInventoryOfConcepts, conceptFromDocument, writeBundle)
import Okf.ConceptId (ConceptId, parseConceptId, renderConceptLink)
import Okf.Document qualified as Okf
import Okf.Index (VersionDeclaration (..), supportedOkfVersion, writeBundleIndexesWith)
import Okf.Profile
  ( ProfileDefinitionError,
    ProfileViolation,
    compileProfile,
    loadProfileFile,
    validateProfile,
    validateProfileVersion,
  )
import Okf.Validation (BundleValidationError, ValidationProfile (..), validateBundle)
import Seihou.Core.Expr (renderExpr)
import Seihou.Core.Judgement qualified as J
import Seihou.Core.Migration
  ( BlueprintMigration (..),
    EntailedEdge (..),
    Migration (..),
    MigrationOp (..),
  )
import Seihou.Core.Types
  ( AgentLaunch (..),
    AgentPrompt (..),
    Blueprint (..),
    BlueprintFile (..),
    Command (..),
    CommandLifecycle (..),
    CommandVar (..),
    Dependency (..),
    Expr,
    Module (..),
    PatchOp (..),
    Prompt (..),
    PromptGuidance (..),
    Recipe (..),
    RecipeReference (..),
    Removal (..),
    RemovalAction (..),
    RemovalStep (..),
    Step (..),
    StepLifecycle (..),
    Strategy (..),
    Validation (..),
    VarDecl (..),
    VarExport (..),
    VarName (..),
    VarType (..),
    VarValue (..),
  )
import Seihou.OKF.Docs.Model
import Seihou.OKF.Extension.Version (producerActorName)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)

-- | Everything the renderer needs that is not in the model: who to name as the
-- producer, whether to stamp a generation date, and how strictly to validate.
--
-- 'generatedAt' is deliberately a value the operator supplies rather than a
-- clock reading. Nothing in the generator reads the clock, so regenerating an
-- unchanged registry produces byte-identical output.
data RenderOptions = RenderOptions
  { producerVersion :: !T.Text,
    generatedAt :: !(Maybe T.Text),
    validationProfile :: !ValidationProfile,
    -- | Where to read the house profile descriptor from. 'Nothing' means the
    -- descriptor embedded in this executable.
    profileSource :: !(Maybe FilePath),
    -- | Whether to check the rendered concepts against that descriptor before
    -- writing anything.
    enforceProfile :: !Bool
  }
  deriving stock (Eq, Generic, Show)

-- | Strict OKF validation and the built-in house profile enforced, with no
-- generation date, for the given producer version.
defaultRenderOptions :: T.Text -> RenderOptions
defaultRenderOptions version =
  RenderOptions
    { producerVersion = version,
      generatedAt = Nothing,
      validationProfile = StrictAuthoring,
      profileSource = Nothing,
      enforceProfile = True
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
  | -- | The house profile descriptor could not be read as a profile at all.
    DocBundleProfileUnreadable T.Text
  | -- | The descriptor read but does not compile to a checkable profile.
    DocBundleProfileInvalid (NonEmpty ProfileDefinitionError)
  | -- | The rendered concepts deviate from the house profile.
    DocBundleProfileViolation ProfileViolation
  deriving stock (Eq, Show)

-- | The house profile descriptor, embedded so the generator never depends on
-- its own source tree at run time. It is also written into every bundle, so a
-- downstream consumer can check a bundle it did not generate.
builtinProfileDescriptor :: T.Text
builtinProfileDescriptor = $(embedStringFile "profile/seihou-registry-docs.dhall")

-- | Where the descriptor is written inside a generated bundle. A Dhall file at
-- the bundle root is not a concept and does not disturb the bundle walk.
profileFileName :: FilePath
profileFileName = "profile.dhall"

conceptIdFor :: DocKind -> T.Text -> Either T.Text ConceptId
conceptIdFor kind name =
  first (T.pack . show) (parseConceptId (conceptIdTextFor kind name))

renderDocBundle :: RenderOptions -> DocModel -> Either [DocRenderError] ([Concept], [BundleValidationError])
renderDocBundle opts model =
  case partitionEithers (registryConceptFor opts model : (conceptFor opts (model ^. #repoName) <$> model ^. #entries)) of
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
-- | Check rendered concepts against the house profile, before anything is
-- written. The descriptor is read from @--profile PATH@ when the operator
-- supplied one and otherwise from 'builtinProfileDescriptor', written to a
-- temporary file because okf reads a profile from a path.
--
-- Returns @[]@ when the profile is not being enforced.
checkDocProfile :: RenderOptions -> [Concept] -> IO [DocBundleError]
checkDocProfile opts concepts
  | not (opts ^. #enforceProfile) = pure []
  | otherwise =
      case opts ^. #profileSource of
        Just path -> checkAgainst path
        Nothing ->
          withSystemTempDirectory "seihou-okf-profile" $ \tmpDir -> do
            let path = tmpDir </> profileFileName
            TIO.writeFile path builtinProfileDescriptor
            checkAgainst path
  where
    checkAgainst path = do
      loaded <- loadProfileFile path
      pure $ case loaded of
        Left err -> [DocBundleProfileUnreadable err]
        Right spec ->
          case compileProfile spec of
            Left definitionErrors -> [DocBundleProfileInvalid definitionErrors]
            Right compiled ->
              DocBundleProfileViolation
                <$> ( validateProfileVersion (VersionDeclared supportedOkfVersion) compiled
                        <> validateProfile (opts ^. #validationProfile) compiled concepts
                    )

writeDocBundle :: RenderOptions -> FilePath -> DocModel -> IO (Either [DocBundleError] ())
writeDocBundle opts outDir model =
  case renderDocBundle opts model of
    Left renderErrors ->
      pure (Left (DocBundleRenderError <$> renderErrors))
    Right (concepts, validationErrors)
      | not (null validationErrors) ->
          pure (Left (DocBundleValidationError <$> validationErrors))
      | otherwise -> do
          -- The profile is checked before a single file is written, so a bundle
          -- that violates the house convention never reaches disk at all.
          profileProblems <- checkDocProfile opts concepts
          if not (null profileProblems)
            then pure (Left profileProblems)
            else do
              writeBundle outDir concepts
              writeProfileDescriptor opts outDir
              -- Walk what was just written and lay down the root index (carrying
              -- the OKF version declaration, the one place a bundle states it)
              -- plus one index per subdirectory.
              indexResult <- writeBundleIndexesWith (Just supportedOkfVersion) outDir
              pure (first (pure . DocBundleIndexError) indexResult)

-- | Write the descriptor the bundle was checked against beside the bundle, so a
-- reader can re-run the same check with @okf validate --profile@.
writeProfileDescriptor :: RenderOptions -> FilePath -> IO ()
writeProfileDescriptor opts outDir = do
  createDirectoryIfMissing True outDir
  descriptor <- case opts ^. #profileSource of
    Nothing -> pure builtinProfileDescriptor
    Just path -> TIO.readFile path
  TIO.writeFile (outDir </> profileFileName) descriptor

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
    ( baseFrontmatter
        opts
        (typeFor (entry ^. #kind))
        (entry ^. #name)
        (descriptionFor repoName entry)
        (resourceFor repoName entry)
        (entry ^. #tags)
    )
  where
    maybeSetVersion =
      maybe id (\version -> Okf.setField "version" (String version)) (entry ^. #version)

-- | The frontmatter every concept this generator emits carries: the OKF common
-- identity fields, the resource pointer back into the registry, the tags, the
-- lifecycle status, and the @generated@ provenance block that gives the concept
-- a trust tier.
baseFrontmatter :: RenderOptions -> T.Text -> T.Text -> T.Text -> T.Text -> [T.Text] -> Okf.Frontmatter
baseFrontmatter opts conceptType title description resource tags =
  Okf.setGenerated generated
    . Okf.setStatus Okf.Stable
    . Okf.setTags tags
    . Okf.setResource resource
    $ Okf.okfCommon
      Okf.OkfCommon
        { Okf.commonType = conceptType,
          Okf.commonTitle = Just title,
          Okf.commonDescription = Just description,
          Okf.commonTimestamp = Nothing
        }
  where
    generated =
      Okf.Generated
        { Okf.generatedBy = ProducerActor producerActorName (opts ^. #producerVersion),
          Okf.generatedAt = opts ^. #generatedAt
        }

-- | One concept describing the registry itself, so the bundle is a connected
-- graph from a single entry point rather than a flat set of artifact pages.
registryConceptFor :: RenderOptions -> DocModel -> Either DocRenderError Concept
registryConceptFor opts model =
  case conceptIdFor DocRegistryKind repoName of
    Left err -> Left (InvalidDocConceptId DocRegistryKind repoName err)
    Right conceptId ->
      Right (conceptFromDocument conceptId document)
  where
    repoName = model ^. #repoName
    description =
      case model ^. #repoDescription of
        Just described | not (T.null (T.strip described)) -> described
        _ -> "The `" <> repoName <> "` seihou registry."
    document =
      Okf.OKFDocument
        ( baseFrontmatter
            opts
            (typeFor DocRegistryKind)
            repoName
            description
            ("seihou://" <> repoName <> "/seihou-registry.dhall")
            ["registry", "seihou"]
        )
        (registryBody repoName description (model ^. #entries))

registryBody :: T.Text -> T.Text -> [DocEntry] -> T.Text
registryBody repoName description entries =
  T.intercalate
    "\n\n"
    ( [ "# " <> repoName,
        description,
        "Every artifact below is published by the `"
          <> repoName
          <> "` registry and documented in its own concept. Modules, recipes, blueprints, prompts and judgements are read from declarations; generation never executes their commands or reviews."
      ]
        <> foldMap (uncurry (registryKindSection entries)) kindHeadings
    )
    <> "\n"
  where
    kindHeadings =
      [ (DocModuleKind, "Modules"),
        (DocRecipeKind, "Recipes"),
        (DocBlueprintKind, "Blueprints"),
        (DocPromptKind, "Prompts"),
        (DocJudgementKind, "Judgements")
      ]

registryKindSection :: [DocEntry] -> DocKind -> T.Text -> [T.Text]
registryKindSection entries kind heading =
  case [entry | entry <- entries, entry ^. #kind == kind] of
    [] -> []
    matching ->
      [ section heading (T.unlines (registryEntryLink <$> matching))
      ]

registryEntryLink :: DocEntry -> T.Text
registryEntryLink entry =
  case conceptIdFor (entry ^. #kind) (entry ^. #name) of
    Right conceptId -> "- " <> renderConceptLink conceptId (entry ^. #name)
    Left _ -> "- `" <> entry ^. #name <> "`"

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
artifactDescription (DocJudgementArtifact def) = def ^. #description

kindNoun :: DocKind -> T.Text
kindNoun DocModuleKind = "module"
kindNoun DocRecipeKind = "recipe"
kindNoun DocBlueprintKind = "blueprint"
kindNoun DocPromptKind = "agent prompt"
kindNoun DocJudgementKind = "judgement"
kindNoun DocRegistryKind = "registry"

resourceFor :: T.Text -> DocEntry -> T.Text
resourceFor repoName entry =
  "seihou://" <> repoName <> "/" <> T.pack (entry ^. #path)

bodyFor :: T.Text -> DocEntry -> T.Text
bodyFor repoName entry =
  T.intercalate
    "\n\n"
    ( baseSections repoName entry
        <> optionalSection "Declaration metadata" (renderDeclaredMetadata entry)
        <> optionalSection "Judgements" (renderJudgementRefs (entry ^. #judgementRefs))
        <> kindSections entry
    )
    <> "\n"

baseSections :: T.Text -> DocEntry -> [T.Text]
baseSections repoName entry =
  [ "# " <> entry ^. #name,
    descriptionFor repoName entry
  ]
    <> foldMap (\version -> ["**Version:** " <> version]) (entry ^. #version)

-- | The per-kind body sections.
--
-- A section that the artifact declares nothing for is omitted entirely, so a
-- reader never wades through a page of "none declared". The four sections that
-- predate this renderer -- Dependencies, Variables, Exports for a module,
-- Composes for a recipe, Base modules and Reference files for a blueprint,
-- Agent prompt, Reference files and Tools for a prompt -- keep their
-- "nothing declared" sentence instead, because a reader who has seen them
-- before would read their absence as a rendering bug.
--
-- Every helper below is total and deterministic: no clock, no filesystem, and
-- every 'Data.Map.Strict.Map' walked in key order.
kindSections :: DocEntry -> [T.Text]
kindSections entry =
  case entry ^. #artifact of
    DocModuleArtifact Module {vars, exports, prompts, steps, commands, dependencies, removal, migrations} ->
      [ section "Dependencies" (renderDependencies entry "This module has no dependencies." dependencies),
        section "Variables" (renderVarDecls vars),
        section "Exports" (renderExports exports)
      ]
        <> optionalSection "Prompts" (renderPrompts prompts)
        <> optionalSection "Generation steps" (renderSteps steps)
        <> optionalSection "Commands" (renderCommands commands)
        <> foldMap (optionalSection "Removal" . renderRemoval) removal
        <> optionalSection "Migrations" (renderMigrations migrations)
    DocRecipeArtifact Recipe {modules = recipeModules, vars, prompts, extends, moduleOverrides, promptOverrides} ->
      foldMap (\ref -> [section "Extends" (renderRecipeBase entry ref)]) extends
        <> [section "Composes" (renderDependencies entry (maybe "This recipe does not compose any modules." (const "Uses its inherited members without adding modules.") extends) recipeModules)]
        <> optionalSection "Inherited module overrides" (T.unlines ["- " <> inlineCode (override ^. #module_ . #unModuleName) <> renderSuppliedVars (override ^. #vars) | override <- moduleOverrides])
        <> [section "Override rules" "The oldest base supplies the primary module. Child literals override ancestor literals globally by variable name; defaults remain fallbacks. Explicit module overrides replace selected keys without adding instances. Prompt overrides replace inherited questions in place; new prompts append." | extends /= Nothing]
        <> optionalSection "Variables" (renderVarDecls' vars)
        <> optionalSection "Prompts" (renderPrompts prompts)
        <> optionalSection "Inherited prompt overrides" (renderPrompts promptOverrides)
    DocBlueprintArtifact Blueprint {prompt, vars, prompts, baseModules, files, allowedTools, migrations, launch, versionProbe} ->
      [ section "Base modules" (renderDependencies entry "This blueprint declares no base modules." baseModules),
        section "Agent prompt" (renderAgentPrompt prompt)
      ]
        <> optionalSection "Variables" (renderVarDecls' vars)
        <> optionalSection "Prompts" (renderPrompts prompts)
        <> [section "Reference files" (renderBlueprintFiles files)]
        <> [section "Tools" (renderTools allowedTools <> "\n\nBlueprint runs also pre-approve Seihou setup tools.")]
        <> foldMap (optionalSection "Agent launch" . renderAgentLaunch) launch
        <> foldMap (optionalSection "Version probe" . renderVersionProbe) versionProbe
        <> optionalSection
          "Migrations"
          (renderBlueprintMigrations (resolvedEntailedBlueprints entry) migrations)
    DocPromptArtifact AgentPrompt {prompt, vars, prompts, commandVars, guidance, files, allowedTools, launch} ->
      [section "Agent prompt" (renderAgentPrompt prompt)]
        <> optionalSection "Variables" (renderVarDecls' vars)
        <> optionalSection "Prompts" (renderPrompts prompts)
        <> optionalSection "Command variables" (renderCommandVars commandVars)
        <> optionalSection "Guidance" (renderGuidance guidance)
        <> [ section "Reference files" (renderBlueprintFiles files),
             section "Tools" (renderTools allowedTools)
           ]
        <> foldMap (optionalSection "Agent launch" . renderAgentLaunch) launch
    DocJudgementArtifact def ->
      [ section "Instructions" (if T.null (T.strip (def ^. #instructions)) then "No shared instructions." else fencedBlock "text" (def ^. #instructions)),
        section "Decision semantics" "Thresholds apply to the model-reported probability of the concern, converting probability of yes according to concern direction. These probabilities are not calibrated risk estimates. Values at or below passAt may pass only with complete coverage; values at or above blockAt block; the intervening band needs review. Authored enforcement and thresholds are defaults; a consuming project's recorded policy decides. A permitted gate may clear a check, but cannot overrule review or permit a pass at its block threshold.",
        section "Checks" (T.unlines (concatMap renderJudgementCheck (toList (def ^. #checks)))),
        section
          "Evidence"
          ( "Scopes: "
              <> T.intercalate ", " (map J.renderScopeKind (def ^. #evidence . #scopes))
              <> ".\n"
              <> "Include: "
              <> listOrAll (def ^. #evidence . #include)
              <> ". Exclude: "
              <> listOrNone (def ^. #evidence . #exclude)
              <> "."
          ),
        section "Deterministic checks" (if null (def ^. #deterministicChecks) then "None." else T.intercalate ", " (map J.renderDeterministicCheck (def ^. #deterministicChecks)) <> "."),
        section "Coverage limits" (renderCoverageLimits (def ^. #limits))
      ]

-- | Catalog metadata remains authoritative. Preserve differing declaration
-- metadata instead of silently dropping a stale catalog's source values.
renderDeclaredMetadata :: DocEntry -> T.Text
renderDeclaredMetadata entry =
  T.unlines $
    ["- name: " <> inlineCode name | name /= entry ^. #name]
      <> ["- version: " <> maybe "not declared" inlineCode version | version /= entry ^. #version]
      <> ["- description: " <> maybe "not declared" inlineCode description | description /= entry ^. #description]
      <> ["- tags: " <> T.intercalate ", " (inlineCode <$> tags) | Just tags <- [artifactTags], tags /= entry ^. #tags]
  where
    (name, version, description, artifactTags) = case entry ^. #artifact of
      DocModuleArtifact m -> (m ^. #name . #unModuleName, m ^. #version, m ^. #description, Nothing)
      DocRecipeArtifact r -> (r ^. #name . #unRecipeName, r ^. #version, r ^. #description, Nothing)
      DocBlueprintArtifact b -> (b ^. #name . #unModuleName, b ^. #version, b ^. #description, Just (b ^. #tags))
      DocPromptArtifact p -> (p ^. #name . #unModuleName, p ^. #version, p ^. #description, Just (p ^. #tags))
      DocJudgementArtifact j -> (j ^. #name, j ^. #version, j ^. #description, Nothing)

renderJudgementRefs :: [JudgementDocRef] -> T.Text
renderJudgementRefs refs =
  T.unlines
    [ "- "
        <> target ref
        <> sourceLabel (ref ^. #reference . #source)
        <> foldMap (\condition -> " — when " <> inlineCode condition) (ref ^. #reference . #when)
    | ref <- refs
    ]
  where
    target ref
      | ref ^. #resolved,
        ref ^. #reference . #source == Nothing,
        Right conceptId <- conceptIdFor DocJudgementKind (ref ^. #reference . #name) =
          renderConceptLink conceptId (ref ^. #reference . #name)
      | otherwise = inlineCode (ref ^. #reference . #name) <> " (not linked in this registry)"

-- | Sections are joined with a blank line between them, so a body\'s own
-- trailing newline is stripped rather than left to open a second blank line.
section :: T.Text -> T.Text -> T.Text
section heading body = "## " <> heading <> "\n\n" <> T.stripEnd body

-- | A section that disappears when its renderer produced nothing.
optionalSection :: T.Text -> T.Text -> [T.Text]
optionalSection heading body
  | T.null (T.strip body) = []
  | otherwise = [section heading body]

-- | The blueprint names that this entry's entailed edges resolved to inside the
-- same registry. Resolution is decided once, in
-- 'Seihou.OKF.Docs.Model.resolveEntryRefs'; this only reads the answer.
resolvedEntailedBlueprints :: DocEntry -> [T.Text]
resolvedEntailedBlueprints entry =
  [ref ^. #blueprint | ref <- entry ^. #entailedRefs, ref ^. #resolved]

renderRecipeBase :: DocEntry -> RecipeReference -> T.Text
renderRecipeBase entry ref =
  let name = ref ^. #recipe . #unRecipeName
      linked = case entry ^. #baseRecipe of
        Just base
          | base ^. #resolved,
            ref ^. #source == Nothing -> case conceptIdFor DocRecipeKind name of
              Right conceptId -> renderConceptLink conceptId name
              Left _ -> inlineCode name
        _ -> inlineCode name
      source = sourceLabel (ref ^. #source)
      interval = maybe "" (\range -> "; version >= " <> inlineCode (range ^. #minimum) <> " and < " <> inlineCode (range ^. #before)) (ref ^. #versionRange)
   in linked <> source <> interval <> ". Selected from the source's default-branch HEAD; no historical tag search. This page documents the declared child; inherited declarations are not expanded."

renderDependencies :: DocEntry -> T.Text -> [Dependency] -> T.Text
renderDependencies _ emptyMessage [] = emptyMessage
renderDependencies entry _ dependencies =
  T.unlines
    [ "- " <> target dep <> sourceLabel source <> renderSuppliedVars vars
    | dep@Dependency {source, vars} <- dependencies
    ]
  where
    target Dependency {module_ = moduleName, source, vars}
      | source == Nothing, any (\ref -> ref ^. #name == moduleName ^. #unModuleName && ref ^. #source == source && ref ^. #vars == vars && ref ^. #resolved) (entry ^. #moduleRefs) = moduleLink (moduleName ^. #unModuleName)
      | otherwise = inlineCode (moduleName ^. #unModuleName) <> " (not linked in this registry)"

sourceLabel :: Maybe T.Text -> T.Text
sourceLabel = maybe " (declaring registry)" (\source -> " from " <> inlineCode source)

-- | The variable bindings the composing artifact supplies along this edge.
renderSuppliedVars :: Map VarName T.Text -> T.Text
renderSuppliedVars vars
  | Map.null vars = ""
  | otherwise =
      " (with "
        <> T.intercalate
          ", "
          [ inlineCode varName <> " = " <> inlineCode value
          | (VarName varName, value) <- Map.toAscList vars
          ]
        <> ")"

moduleLink :: T.Text -> T.Text
moduleLink name =
  case conceptIdFor DocModuleKind name of
    Right conceptId -> renderConceptLink conceptId name
    Left _ -> inlineCode name

-- | Variables, with the type, requiredness, default, validation rule and
-- description the declaration actually carries.
renderVarDecls :: [VarDecl] -> T.Text
renderVarDecls [] = "No variables declared."
renderVarDecls vars = renderVarDecls' vars

-- | 'renderVarDecls' without the "none declared" fallback, for the kinds whose
-- Variables section is omitted when empty.
renderVarDecls' :: [VarDecl] -> T.Text
renderVarDecls' vars = T.unlines (renderVarDecl <$> vars)

renderVarDecl :: VarDecl -> T.Text
renderVarDecl VarDecl {name = VarName varName, type_, default_, description, required, validation} =
  "- "
    <> inlineCode varName
    <> " — "
    <> T.intercalate
      ", "
      ( [renderVarType type_, if required then "required" else "optional"]
          <> foldMap (\value -> ["default " <> inlineCode (renderValue value)]) default_
          <> foldMap (pure . renderValidation) validation
      )
    <> foldMap (". " <>) description

renderVarType :: VarType -> T.Text
renderVarType VTText = "text"
renderVarType VTBool = "boolean"
renderVarType VTInt = "integer"
renderVarType (VTList inner) = "list of " <> renderVarType inner
renderVarType (VTChoice choices) =
  "one of " <> T.intercalate ", " [inlineCode choice | choice <- choices]

renderValidation :: Validation -> T.Text
renderValidation (ValPattern pattern_) = "matching " <> inlineCode pattern_
renderValidation (ValRange low high) =
  "between " <> T.pack (show low) <> " and " <> T.pack (show high)
renderValidation (ValMinLength n) = "at least " <> T.pack (show n) <> " characters"
renderValidation (ValMaxLength n) = "at most " <> T.pack (show n) <> " characters"

-- | A concrete value, in the plainest form a reader can act on. Distinct from
-- 'Seihou.Core.Expr.renderExpr', which renders values as expression syntax and
-- therefore quotes text.
renderValue :: VarValue -> T.Text
renderValue (VText text) = text
renderValue (VBool True) = "true"
renderValue (VBool False) = "false"
renderValue (VInt n) = T.pack (show n)
renderValue (VList values) = "[" <> T.intercalate ", " (renderListValue <$> values) <> "]"
  where
    renderListValue (VText text) = TL.toStrict (Aeson.encodeToLazyText (String text))
    renderListValue value = renderValue value

renderExports :: [VarExport] -> T.Text
renderExports [] = "No exports declared."
renderExports exports =
  T.unlines
    [ "- " <> inlineCode varName <> foldMap (\(VarName aliasName) -> " as " <> inlineCode aliasName) alias
    | VarExport {var = VarName varName, alias} <- exports
    ]

-- | Interactive prompts: which variable each fills, what it asks, the choices
-- it offers, and the condition that gates it.
renderPrompts :: [Prompt] -> T.Text
renderPrompts prompts = T.unlines (renderPrompt <$> prompts)

renderPrompt :: Prompt -> T.Text
renderPrompt Prompt {var = VarName varName, text, condition, choices} =
  "- "
    <> inlineCode varName
    <> " — "
    <> inlineCode text
    <> foldMap renderChoices choices
    <> renderCondition condition
  where
    renderChoices options =
      " (choices: " <> T.intercalate ", " [inlineCode option | option <- options] <> ")"

renderCondition :: Maybe Expr -> T.Text
renderCondition = foldMap (\expr -> " — when " <> inlineCode (renderExpr expr))

renderSteps :: [Step] -> T.Text
renderSteps steps = T.unlines (renderStep <$> steps)

renderStep :: Step -> T.Text
renderStep Step {strategy, src, dest, condition, patch, lifecycle} =
  "- "
    <> inlineCode (renderStrategy strategy)
    <> " "
    <> inlineCode (T.pack src)
    <> " → "
    <> inlineCode dest
    <> foldMap (\op -> " (" <> renderPatchOp op <> ")") patch
    <> renderCondition condition
    <> " — "
    <> renderStepLifecycle lifecycle

renderStepLifecycle :: StepLifecycle -> T.Text
renderStepLifecycle Managed = "Managed: owned and reconciled by Seihou updates"
renderStepLifecycle Seed = "Seed: created once when absent, then project owned; updates and removal preserve it"
renderStepLifecycle Checkout = "Checkout: portable symlink restored by `seihou sync` in fresh clones and worktrees"

renderStrategy :: Strategy -> T.Text
renderStrategy Copy = "Copy"
renderStrategy Template = "Template"
renderStrategy DhallText = "DhallText"
renderStrategy Structured = "Structured"
renderStrategy Symlink = "Symlink"

renderPatchOp :: PatchOp -> T.Text
renderPatchOp AppendFile = "appends to a file another module owns"
renderPatchOp PrependFile = "prepends to a file another module owns"
renderPatchOp AppendSection = "appends a marked section to a file another module owns"
renderPatchOp AppendLineIfAbsent = "appends one line to a file another module owns, if absent"

renderCommands :: [Command] -> T.Text
renderCommands commands = T.unlines (renderCommand <$> commands)

renderCommand :: Command -> T.Text
renderCommand Command {run, workDir, condition, lifecycle} =
  "- " <> inlineCode run <> renderWorkDir workDir <> renderCondition condition <> renderCommandLifecycle lifecycle

renderWorkDir :: Maybe T.Text -> T.Text
renderWorkDir = foldMap (\dir -> " in " <> inlineCode dir)

renderCommandLifecycle :: CommandLifecycle -> T.Text
renderCommandLifecycle ApplicationCommand = " (application command)"
renderCommandLifecycle CheckoutCommandLifecycle = " (repeatable checkout setup; seihou sync)"

renderRemoval :: Removal -> T.Text
renderRemoval Removal {steps, commands} =
  T.intercalate "\n" (filter (not . T.null) [renderRemovalSteps steps, renderRemovalCommands commands])
  where
    renderRemovalSteps [] = ""
    renderRemovalSteps removalSteps = T.unlines (renderRemovalStep <$> removalSteps)
    renderRemovalCommands [] = ""
    renderRemovalCommands removalCommands =
      "Then runs:\n\n" <> T.unlines (renderCommand <$> removalCommands)

renderRemovalStep :: RemovalStep -> T.Text
renderRemovalStep RemovalStep {action, dest, src, condition} =
  "- " <> renderRemovalAction action <> " " <> inlineCode dest <> foldMap (\path -> " using " <> inlineCode (T.pack path)) src <> renderCondition condition

renderRemovalAction :: RemovalAction -> T.Text
renderRemovalAction RemoveFileAction = "delete"
renderRemovalAction RemoveSectionAction = "strip this module's section from"
renderRemovalAction RewriteFileAction = "rewrite"

renderMigrations :: [Migration] -> T.Text
renderMigrations migrations =
  T.intercalate "\n\n" (renderMigration <$> migrations)

renderMigration :: Migration -> T.Text
renderMigration Migration {from, to, ops} =
  "### " <> from <> " → " <> to <> "\n\n" <> renderMigrationOps ops

renderMigrationOps :: [MigrationOp] -> T.Text
renderMigrationOps [] = "This edge declares no operations; it advances the recorded version only."
renderMigrationOps ops = T.unlines (renderMigrationOp <$> ops)

renderMigrationOp :: MigrationOp -> T.Text
renderMigrationOp MoveFile {src, dest} = "- move " <> inlineCode (T.pack src) <> " → " <> inlineCode (T.pack dest)
renderMigrationOp MoveDir {src, dest} = "- move directory " <> inlineCode (T.pack src) <> " → " <> inlineCode (T.pack dest)
renderMigrationOp DeleteFile {path} = "- delete " <> inlineCode (T.pack path)
renderMigrationOp DeleteDir {path} = "- delete directory " <> inlineCode (T.pack path)
renderMigrationOp RemoveLine {path, line} = "- remove exact line " <> inlineCode line <> " from " <> inlineCode (T.pack path) <> "; removes every matching logical line, excluding its LF/CRLF terminator from comparison; preserves nonmatching bytes. Missing files or matches are no-ops."
renderMigrationOp RunCommand {run, workDir} =
  "- run " <> inlineCode run <> foldMap (\dir -> " in " <> inlineCode (T.pack dir)) workDir

-- | Blueprint migration edges, each with the guidance the agent is given and
-- the other blueprints' edges that crossing this one entails.
renderBlueprintMigrations :: [T.Text] -> [BlueprintMigration] -> T.Text
renderBlueprintMigrations resolvedBlueprints migrations =
  T.intercalate "\n\n" (renderBlueprintMigration resolvedBlueprints <$> migrations)

renderBlueprintMigration :: [T.Text] -> BlueprintMigration -> T.Text
renderBlueprintMigration resolvedBlueprints BlueprintMigration {from, to, prompt, entails} =
  T.intercalate
    "\n\n"
    ( ["### " <> from <> " → " <> to, T.strip prompt]
        <> renderEntails resolvedBlueprints entails
    )

renderEntails :: [T.Text] -> [EntailedEdge] -> [T.Text]
renderEntails _ [] = []
renderEntails resolvedBlueprints entails =
  [ "Entails:\n\n"
      <> T.unlines (renderEntailedEdge resolvedBlueprints <$> entails)
  ]

-- | An entailed edge naming a blueprint in this registry becomes a cross-link;
-- one naming a blueprint elsewhere becomes labelled text.
--
-- The distinction is not cosmetic. An entailed edge is owned by the blueprint
-- that declares it and may legitimately name a blueprint in another repository
-- entirely (ADR 0008 in the seihou repository), and okf reports a link to a
-- concept that is not in the bundle as a dangling reference, which this
-- generator treats as fatal.
renderEntailedEdge :: [T.Text] -> EntailedEdge -> T.Text
renderEntailedEdge resolvedBlueprints EntailedEdge {blueprint, from, to}
  | blueprint `elem` resolvedBlueprints,
    Right conceptId <- conceptIdFor DocBlueprintKind blueprint =
      "- " <> renderConceptLink conceptId blueprint <> " `" <> from <> "` → `" <> to <> "`"
  | otherwise =
      "- `" <> blueprint <> "` `" <> from <> "` → `" <> to <> "` (declared outside this registry)"

renderAgentLaunch :: AgentLaunch -> T.Text
renderAgentLaunch AgentLaunch {provider, model, effort, mode} =
  case declared of
    [] -> ""
    _ ->
      T.unlines declared
        <> "\nThese are defaults. An explicit `--provider`, `--model` or `--effort` flag \
           \and the `SEIHOU_AGENT_*` environment variables both override them; the \
           \invoking user's configuration files do not.\n"
  where
    declared =
      foldMap (\value -> ["- provider: " <> inlineCode value]) provider
        <> foldMap (\value -> ["- model: " <> inlineCode value]) model
        <> foldMap (\value -> ["- effort: " <> inlineCode value]) effort
        <> foldMap (\value -> ["- mode: " <> inlineCode value <> " (reserved; ignored)"]) mode

renderVersionProbe :: T.Text -> T.Text
renderVersionProbe probe =
  fencedBlock "bash" probe
    <> "\n\nSeihou reads no package-manager format of its own, so this \
       \author-declared command is how it discovers which version of this \
       \blueprint's library the project currently declares; its output supplies \
       \the default `--to` for `seihou agent migrate` (ADR 0009 in the seihou \
       \repository)."

renderCommandVars :: [CommandVar] -> T.Text
renderCommandVars commandVars = T.unlines (renderCommandVar <$> commandVars)

renderCommandVar :: CommandVar -> T.Text
renderCommandVar CommandVar {name = VarName varName, run, workDir, condition, trim, maxBytes} =
  "- "
    <> inlineCode varName
    <> " — runs "
    <> inlineCode run
    <> renderWorkDir workDir
    <> ", "
    <> (if trim then "trimmed" else "untrimmed")
    <> foldMap (\limit -> ", capped at " <> T.pack (show limit) <> " bytes") maxBytes
    <> renderCondition condition

renderGuidance :: [PromptGuidance] -> T.Text
renderGuidance guidance = T.intercalate "\n\n" (renderGuidanceBlock <$> guidance)

renderGuidanceBlock :: PromptGuidance -> T.Text
renderGuidanceBlock PromptGuidance {title, body, condition} =
  T.intercalate
    "\n\n"
    ( ["### " <> title, T.strip body]
        <> foldMap (\expr -> ["Applies when `" <> renderExpr expr <> "`."]) condition
    )

-- | The prompt as a reader needs it: an opening excerpt so the section reads,
-- then the whole text verbatim in a fence so nothing is lost.
renderAgentPrompt :: T.Text -> T.Text
renderAgentPrompt prompt
  | T.null (T.strip prompt) = "No prompt text provided."
  | otherwise =
      fencedBlock "text" prompt

renderBlueprintFiles :: [BlueprintFile] -> T.Text
renderBlueprintFiles [] = "No reference files declared."
renderBlueprintFiles files =
  T.unlines
    [ "- " <> inlineCode (T.pack src) <> maybe "" (" - " <>) description
    | BlueprintFile {src, description} <- files
    ]

renderTools :: Maybe [T.Text] -> T.Text
renderTools Nothing = "No additional tools declared."
renderTools (Just []) = "No additional tools declared (explicit empty allowlist)."
renderTools (Just tools) = renderTextList' tools

renderTextList' :: [T.Text] -> T.Text
renderTextList' values = T.unlines ["- " <> inlineCode value | value <- values]

-- | Choose delimiters from the source data, so literals cannot close their own
-- span or fence. Inline multiline text is labelled JSON to retain exact breaks.
inlineCode :: T.Text -> T.Text
inlineCode value
  | T.null value || T.all (== ' ') value || T.any (`elem` ['\n', '\r']) value = codeSpan (TL.toStrict (Aeson.encodeToLazyText (String value))) <> " (JSON string)"
  | otherwise = codeSpan value

codeSpan :: T.Text -> T.Text
codeSpan value = delimiter <> padding <> value <> padding <> delimiter
  where
    delimiter = T.replicate (maxBackticks value + 1) "`"
    padding = if T.null value || T.isPrefixOf "`" value || T.isSuffixOf "`" value || T.isPrefixOf " " value || T.isSuffixOf " " value then " " else ""

fencedBlock :: T.Text -> T.Text -> T.Text
fencedBlock language value = delimiter <> language <> "\n" <> value <> (if T.isSuffixOf "\n" value then "" else "\n") <> delimiter
  where
    delimiter = T.replicate (max 3 (maxBackticks value + 1)) "`"

maxBackticks :: T.Text -> Int
maxBackticks value = maximum (0 : [T.length run | run <- T.group value, T.isPrefixOf "`" run])

conceptIdTextFor :: DocKind -> T.Text -> T.Text
conceptIdTextFor kind name = kindDir kind <> "/" <> name

kindDir :: DocKind -> T.Text
kindDir DocModuleKind = "modules"
kindDir DocRecipeKind = "recipes"
kindDir DocBlueprintKind = "blueprints"
kindDir DocPromptKind = "prompts"
kindDir DocJudgementKind = "judgements"
kindDir DocRegistryKind = "registry"

typeFor :: DocKind -> T.Text
typeFor DocModuleKind = "SeihouModule"
typeFor DocRecipeKind = "SeihouRecipe"
typeFor DocBlueprintKind = "SeihouBlueprint"
typeFor DocPromptKind = "SeihouPrompt"
typeFor DocJudgementKind = "SeihouJudgement"
typeFor DocRegistryKind = "SeihouRegistry"

renderJudgementCheck :: J.JudgementCheck -> [T.Text]
renderJudgementCheck c =
  [ "### " <> c ^. #name,
    inlineCode (c ^. #question),
    "Enforcement: " <> J.renderEnforcement (c ^. #enforcement) <> ". Concern when the answer is " <> J.renderAnswer (c ^. #concernWhen) <> ".",
    "Review: " <> renderThresholds (c ^. #review) <> "; findings block from " <> J.renderSeverity (c ^. #blockingSeverity) <> " severity.",
    "Gate: useGate = " <> (if c ^. #useGate then "true" else "false (disabled)") <> "; " <> renderThresholds (c ^. #gate) <> "."
  ]
    <> foldMap (\meaning -> ["Yes means: " <> inlineCode meaning]) (c ^. #yesMeans)
    <> foldMap (\meaning -> ["No means: " <> inlineCode meaning]) (c ^. #noMeans)
    <> ["- Category " <> inlineCode (cat ^. #name) <> ": " <> J.renderSeverity (cat ^. #severity) <> foldMap (\description -> " — " <> inlineCode description) (cat ^. #description) | cat <- c ^. #categories]
    <> [""]

renderThresholds :: J.Thresholds -> T.Text
renderThresholds thresholds = "passAt = " <> J.renderProbability (thresholds ^. #passAt) <> ", blockAt = " <> J.renderProbability (thresholds ^. #blockAt)

renderCoverageLimits :: J.CoverageLimits -> T.Text
renderCoverageLimits limits =
  T.unlines
    [ "- " <> field <> ": " <> T.pack (show value)
    | (field, value) <-
        [ ("maxFileBytes", limits ^. #maxFileBytes),
          ("maxChunkBytes", limits ^. #maxChunkBytes),
          ("maxChunks", limits ^. #maxChunks),
          ("maxAttempts", limits ^. #maxAttempts),
          ("timeoutSeconds", limits ^. #timeoutSeconds),
          ("maxFindings", limits ^. #maxFindings)
        ]
    ]

listOrAll :: [T.Text] -> T.Text
listOrAll [] = "every path"
listOrAll xs = T.intercalate ", " (inlineCode <$> xs)

listOrNone :: [T.Text] -> T.Text
listOrNone [] = "none"
listOrNone xs = T.intercalate ", " (inlineCode <$> xs)
