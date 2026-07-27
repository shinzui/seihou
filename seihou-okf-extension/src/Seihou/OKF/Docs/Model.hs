module Seihou.OKF.Docs.Model
  ( DocKind (..),
    DocArtifact (..),
    DocEntry (..),
    ModuleRef (..),
    DocModel (..),
    DocLoadError (..),
    loadDocModel,
  )
where

import Data.Text qualified as T
import GHC.Generics (Generic)
import Seihou.Core.Registry (Registry (..), RegistryEntry (..))
import Seihou.Core.Types
  ( AgentPrompt,
    Blueprint (..),
    Dependency,
    Module (..),
    ModuleLoadError,
    ModuleName (..),
    Recipe (..),
    RecipeName (..),
    depModuleNames,
  )
import Seihou.Dhall.Eval
  ( evalAgentPromptFromFile,
    evalBlueprintFromFile,
    evalModuleFromFile,
    evalRecipeFromFile,
    evalRegistryFromFile,
  )
import System.Directory (doesFileExist)
import System.FilePath ((</>))

data DocKind
  = DocModuleKind
  | DocRecipeKind
  | DocBlueprintKind
  | DocPromptKind
  deriving stock (Eq, Show)

data DocArtifact
  = DocModuleArtifact Module
  | DocRecipeArtifact Recipe
  | DocBlueprintArtifact Blueprint
  | DocPromptArtifact AgentPrompt
  deriving stock (Eq, Show)

data DocEntry = DocEntry
  { name :: !T.Text,
    kind :: !DocKind,
    version :: !(Maybe T.Text),
    description :: !(Maybe T.Text),
    tags :: ![T.Text],
    path :: !FilePath,
    artifact :: !DocArtifact,
    moduleRefs :: ![ModuleRef]
  }
  deriving stock (Eq, Generic, Show)

data ModuleRef = ModuleRef
  { name :: !T.Text,
    resolved :: !Bool
  }
  deriving stock (Eq, Generic, Show)

data DocModel = DocModel
  { repoName :: !T.Text,
    repoDescription :: !(Maybe T.Text),
    entries :: ![DocEntry]
  }
  deriving stock (Eq, Generic, Show)

data DocLoadError
  = RegistryNotFound FilePath
  | RegistryLoadFailed T.Text
  | ArtifactLoadFailed T.Text T.Text
  deriving stock (Eq, Show)

loadDocModel :: FilePath -> IO (Either DocLoadError DocModel)
loadDocModel registryDir = do
  let registryFile = registryDir </> "seihou-registry.dhall"
  registryExists <- doesFileExist registryFile
  if not registryExists
    then pure (Left (RegistryNotFound registryFile))
    else do
      registryResult <- evalRegistryFromFile registryFile
      case registryResult of
        Left err ->
          pure (Left (RegistryLoadFailed (renderModuleLoadError err)))
        Right registry ->
          buildDocModel registryDir registry

buildDocModel :: FilePath -> Registry -> IO (Either DocLoadError DocModel)
buildDocModel registryDir Registry {repoName, repoDescription, modules, recipes, blueprints, prompts} = do
  entriesResult <-
    concatResults
      [ loadEntries (loadModuleEntry registryDir) modules,
        loadEntries (loadRecipeEntry registryDir) recipes,
        loadEntries (loadBlueprintEntry registryDir) blueprints,
        loadEntries (loadPromptEntry registryDir) prompts
      ]
  pure $ do
    entries <- entriesResult
    let moduleNames = [entry.name | entry <- entries, entry.kind == DocModuleKind]
        resolvedEntries = map (resolveEntryRefs moduleNames) entries
    Right
      DocModel
        { repoName = repoName,
          repoDescription = repoDescription,
          entries = resolvedEntries
        }

loadEntries :: (RegistryEntry -> IO (Either DocLoadError DocEntry)) -> [RegistryEntry] -> IO (Either DocLoadError [DocEntry])
loadEntries _ [] = pure (Right [])
loadEntries loadEntry (entry : entries) = do
  result <- loadEntry entry
  case result of
    Left err -> pure (Left err)
    Right docEntry -> do
      rest <- loadEntries loadEntry entries
      pure ((docEntry :) <$> rest)

concatResults :: [IO (Either DocLoadError [DocEntry])] -> IO (Either DocLoadError [DocEntry])
concatResults [] = pure (Right [])
concatResults (action : actions) = do
  result <- action
  case result of
    Left err -> pure (Left err)
    Right entries -> do
      rest <- concatResults actions
      pure ((entries <>) <$> rest)

loadModuleEntry :: FilePath -> RegistryEntry -> IO (Either DocLoadError DocEntry)
loadModuleEntry registryDir entry = do
  let artifactFile = registryDir </> entry.path </> "module.dhall"
  result <- evalModuleFromFile artifactFile
  pure $ case result of
    Left err -> Left (ArtifactLoadFailed entry.name.unModuleName (renderModuleLoadError err))
    Right artifact@Module {dependencies} ->
      Right $
        docEntryFromRegistry
          entry
          DocModuleKind
          (DocModuleArtifact artifact)
          (moduleRefs dependencies)

loadRecipeEntry :: FilePath -> RegistryEntry -> IO (Either DocLoadError DocEntry)
loadRecipeEntry registryDir entry = do
  let artifactFile = registryDir </> entry.path </> "recipe.dhall"
  result <- evalRecipeFromFile artifactFile
  pure $ case result of
    Left err -> Left (ArtifactLoadFailed entry.name.unModuleName (renderModuleLoadError err))
    Right artifact@Recipe {modules = recipeModules} ->
      Right $
        docEntryFromRegistry
          entry
          DocRecipeKind
          (DocRecipeArtifact artifact)
          (moduleRefs recipeModules)

loadBlueprintEntry :: FilePath -> RegistryEntry -> IO (Either DocLoadError DocEntry)
loadBlueprintEntry registryDir entry = do
  let artifactFile = registryDir </> entry.path </> "blueprint.dhall"
  result <- evalBlueprintFromFile artifactFile
  pure $ case result of
    Left err -> Left (ArtifactLoadFailed entry.name.unModuleName (renderModuleLoadError err))
    Right artifact@Blueprint {baseModules} ->
      Right $
        docEntryFromRegistry
          entry
          DocBlueprintKind
          (DocBlueprintArtifact artifact)
          (moduleRefs baseModules)

loadPromptEntry :: FilePath -> RegistryEntry -> IO (Either DocLoadError DocEntry)
loadPromptEntry registryDir entry = do
  let artifactFile = registryDir </> entry.path </> "prompt.dhall"
  result <- evalAgentPromptFromFile artifactFile
  pure $ case result of
    Left err -> Left (ArtifactLoadFailed entry.name.unModuleName (renderModuleLoadError err))
    Right artifact ->
      Right $
        docEntryFromRegistry
          entry
          DocPromptKind
          (DocPromptArtifact artifact)
          []

docEntryFromRegistry :: RegistryEntry -> DocKind -> DocArtifact -> [ModuleRef] -> DocEntry
docEntryFromRegistry entry kind artifact refs =
  DocEntry
    { name = entry.name.unModuleName,
      kind = kind,
      version = entry.version,
      description = entry.description,
      tags = entry.tags,
      path = entry.path,
      artifact = artifact,
      moduleRefs = refs
    }

moduleRefs :: [Dependency] -> [ModuleRef]
moduleRefs dependencies =
  [ ModuleRef {name = moduleName.unModuleName, resolved = False}
  | moduleName <- depModuleNames dependencies
  ]

resolveEntryRefs :: [T.Text] -> DocEntry -> DocEntry
resolveEntryRefs moduleNames entry =
  entry
    { moduleRefs =
        [ ref {resolved = ref.name `elem` moduleNames}
        | ref <- entry.moduleRefs
        ]
    }

renderModuleLoadError :: ModuleLoadError -> T.Text
renderModuleLoadError = T.pack . show
