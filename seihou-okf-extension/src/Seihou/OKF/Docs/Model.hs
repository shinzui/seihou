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
  { entryName :: T.Text,
    entryKind :: DocKind,
    entryVersion :: Maybe T.Text,
    entryDescription :: Maybe T.Text,
    entryTags :: [T.Text],
    entryPath :: FilePath,
    entryArtifact :: DocArtifact,
    entryModuleRefs :: [ModuleRef]
  }
  deriving stock (Eq, Show)

data ModuleRef = ModuleRef
  { refName :: T.Text,
    refResolved :: Bool
  }
  deriving stock (Eq, Show)

data DocModel = DocModel
  { docRepoName :: T.Text,
    docRepoDescription :: Maybe T.Text,
    docEntries :: [DocEntry]
  }
  deriving stock (Eq, Show)

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
    let moduleNames = [entry.entryName | entry <- entries, entry.entryKind == DocModuleKind]
        resolvedEntries = map (resolveEntryRefs moduleNames) entries
    Right
      DocModel
        { docRepoName = repoName,
          docRepoDescription = repoDescription,
          docEntries = resolvedEntries
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
    { entryName = entry.name.unModuleName,
      entryKind = kind,
      entryVersion = entry.version,
      entryDescription = entry.description,
      entryTags = entry.tags,
      entryPath = entry.path,
      entryArtifact = artifact,
      entryModuleRefs = refs
    }

moduleRefs :: [Dependency] -> [ModuleRef]
moduleRefs dependencies =
  [ ModuleRef {refName = moduleName.unModuleName, refResolved = False}
  | moduleName <- depModuleNames dependencies
  ]

resolveEntryRefs :: [T.Text] -> DocEntry -> DocEntry
resolveEntryRefs moduleNames entry =
  entry
    { entryModuleRefs =
        [ ref {refResolved = ref.refName `elem` moduleNames}
        | ref <- entry.entryModuleRefs
        ]
    }

renderModuleLoadError :: ModuleLoadError -> T.Text
renderModuleLoadError = T.pack . show
