module Seihou.Core.Registry
  ( Registry (..),
    RegistryEntry (..),
    RepoContents (..),
    discoverRepoContents,
    validateRegistry,
  )
where

import Data.Text qualified as T
import GHC.Generics (Generic)
import Seihou.Core.Types (ModuleLoadError, ModuleName (..))
import Seihou.Prelude
import System.Directory (doesFileExist)

-- | A single module listing within a registry.
data RegistryEntry = RegistryEntry
  { name :: ModuleName,
    version :: Maybe Text,
    path :: FilePath,
    description :: Maybe Text,
    tags :: [Text]
  }
  deriving stock (Eq, Show, Generic)

-- | Registry metadata for a multi-module repository.
-- Declared in @seihou-registry.dhall@ at the repo root.
data Registry = Registry
  { repoName :: Text,
    repoDescription :: Maybe Text,
    modules :: [RegistryEntry],
    recipes :: [RegistryEntry]
  }
  deriving stock (Eq, Show, Generic)

-- | What a cloned repository contains.
data RepoContents
  = -- | Repo root has @module.dhall@ (single module)
    SingleModule FilePath
  | -- | Repo root has @recipe.dhall@ (single recipe)
    SingleRecipe FilePath
  | -- | Repo root has @seihou-registry.dhall@
    MultiModule Registry
  | -- | Neither found
    EmptyRepo
  deriving stock (Show)

-- | Examine a cloned repo root and determine what it contains.
-- The first argument is a function that evaluates a registry Dhall file,
-- injected to avoid a circular module dependency with @Seihou.Dhall.Eval@.
discoverRepoContents ::
  (FilePath -> IO (Either ModuleLoadError Registry)) ->
  FilePath ->
  IO RepoContents
discoverRepoContents evalRegistry repoRoot = do
  let registryFile = repoRoot </> "seihou-registry.dhall"
      moduleFile = repoRoot </> "module.dhall"
      recipeFile = repoRoot </> "recipe.dhall"
  hasRegistry <- doesFileExist registryFile
  if hasRegistry
    then do
      result <- evalRegistry registryFile
      case result of
        Right reg -> pure (MultiModule reg)
        Left _ -> do
          -- Registry file exists but failed to parse; fall back
          hasModule <- doesFileExist moduleFile
          if hasModule
            then pure (SingleModule repoRoot)
            else do
              hasRecipe <- doesFileExist recipeFile
              if hasRecipe
                then pure (SingleRecipe repoRoot)
                else pure EmptyRepo
    else do
      hasModule <- doesFileExist moduleFile
      if hasModule
        then pure (SingleModule repoRoot)
        else do
          hasRecipe <- doesFileExist recipeFile
          if hasRecipe
            then pure (SingleRecipe repoRoot)
            else pure EmptyRepo

-- | Validate a registry's entries against the filesystem.
-- Returns a list of error messages (empty means valid).
-- Checks: module name format, path safety, entry file existence,
-- and no name collisions between modules and recipes.
validateRegistry :: FilePath -> Registry -> IO [Text]
validateRegistry repoRoot reg = do
  modErrs <- concat <$> mapM (validateModuleEntry repoRoot) reg.modules
  recErrs <- concat <$> mapM (validateRecipeEntry repoRoot) reg.recipes
  let collisionErrs = checkNameCollisions reg.modules reg.recipes
  pure (modErrs <> recErrs <> collisionErrs)

validateModuleEntry :: FilePath -> RegistryEntry -> IO [Text]
validateModuleEntry repoRoot entry = do
  let nameText = entry.name.unModuleName
      nameErrors = checkName nameText
      pathText = T.pack entry.path
      pathErrors = checkPath pathText
  let moduleDhall = repoRoot </> entry.path </> "module.dhall"
  fileExists <- doesFileExist moduleDhall
  let fileErrors =
        if fileExists
          then []
          else ["registry entry '" <> nameText <> "' points to missing module.dhall at " <> pathText]
  pure (nameErrors <> pathErrors <> fileErrors)
  where
    checkName name
      | validModuleName name = []
      | otherwise = ["registry entry name must match [a-z][a-z0-9-]*, got: " <> name]

    checkPath path
      | T.isPrefixOf "/" path = ["registry entry path must be relative: " <> path]
      | ".." `T.isInfixOf` path = ["registry entry path must not contain '..': " <> path]
      | otherwise = []

validateRecipeEntry :: FilePath -> RegistryEntry -> IO [Text]
validateRecipeEntry repoRoot entry = do
  let nameText = entry.name.unModuleName
      nameErrors = checkRecipeName nameText
      pathText = T.pack entry.path
      pathErrors = checkRecipePath pathText
  let recipeDhall = repoRoot </> entry.path </> "recipe.dhall"
  fileExists <- doesFileExist recipeDhall
  let fileErrors =
        if fileExists
          then []
          else ["registry recipe entry '" <> nameText <> "' points to missing recipe.dhall at " <> pathText]
  pure (nameErrors <> pathErrors <> fileErrors)
  where
    checkRecipeName name
      | validModuleName name = []
      | otherwise = ["registry recipe name must match [a-z][a-z0-9-]*, got: " <> name]

    checkRecipePath path
      | T.isPrefixOf "/" path = ["registry recipe path must be relative: " <> path]
      | ".." `T.isInfixOf` path = ["registry recipe path must not contain '..': " <> path]
      | otherwise = []

-- | Detect name collisions between module and recipe entries.
checkNameCollisions :: [RegistryEntry] -> [RegistryEntry] -> [Text]
checkNameCollisions mods recs =
  let modNames = map (\e -> e.name.unModuleName) mods
      recNames = map (\e -> e.name.unModuleName) recs
      collisions = filter (`elem` recNames) modNames
   in map (\n -> "name collision: '" <> n <> "' appears as both a module and a recipe") collisions

-- | Check that a text matches @[a-z][a-z0-9-]*@.
-- Duplicated from @Seihou.Core.Module.isValidModuleName@ to avoid
-- a circular module dependency through @Seihou.Dhall.Eval@.
validModuleName :: Text -> Bool
validModuleName t = case T.uncons t of
  Nothing -> False
  Just (c, rest) ->
    (c >= 'a' && c <= 'z')
      && T.all (\ch -> (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '-') rest
