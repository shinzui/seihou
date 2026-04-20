module Seihou.Core.Registry
  ( Registry (..),
    RegistryEntry (..),
    RepoContents (..),
    discoverRepoContents,
    validateRegistry,
    renderRegistryDhall,
    EntryKind (..),
    SyncStatus (..),
    SyncDiff (..),
    SyncReport (..),
    computeRegistrySync,
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

-- | What a registry entry points at on disk.
data EntryKind = ModuleEntry | RecipeEntry
  deriving stock (Eq, Show, Generic)

-- | Classification of a single registry entry relative to the on-disk
-- @module.dhall@/@recipe.dhall@ version.
data SyncStatus
  = -- | Registry @version@ is 'Nothing', on-disk version is @Just _@.
    SyncMissing
  | -- | Registry @version@ and on-disk version both @Just@ but differ;
    --   carries the new on-disk version.
    SyncStale Text
  | -- | Registry and on-disk versions match (both 'Just' equal or both 'Nothing').
    SyncInSync
  | -- | On-disk @module.dhall@/@recipe.dhall@ absent or unreadable.
    SyncOrphan
  deriving stock (Eq, Show, Generic)

-- | One row of a sync diff, preserving registry order.
data SyncDiff = SyncDiff
  { diffKind :: EntryKind,
    diffName :: ModuleName,
    diffOld :: Maybe Text,
    diffNew :: Maybe Text,
    diffStatus :: SyncStatus
  }
  deriving stock (Eq, Show, Generic)

-- | Output of 'computeRegistrySync': the classifications in registry order,
-- and a 'Registry' with each entry's @version@ field updated to the on-disk
-- value (except 'SyncOrphan' entries, which are preserved as-is).
data SyncReport = SyncReport
  { syncDiffs :: [SyncDiff],
    syncUpdated :: Registry
  }
  deriving stock (Eq, Show, Generic)

-- | Pure core of the version-sync flow. The caller resolves each entry's
-- on-disk version ('Just v', or 'Nothing' for orphaned/unreadable entries)
-- and passes them in; this function classifies and rewrites the registry
-- without performing any IO.
--
-- The lookup list is keyed by @(kind, name)@; entries absent from the list
-- are classified as 'SyncOrphan'.
computeRegistrySync ::
  Registry ->
  [(EntryKind, ModuleName, Maybe Text)] ->
  SyncReport
computeRegistrySync reg lookups =
  SyncReport
    { syncDiffs = moduleDiffs <> recipeDiffs,
      syncUpdated =
        reg
          { modules = zipWith applyDiff moduleDiffs reg.modules,
            recipes = zipWith applyDiff recipeDiffs reg.recipes
          }
    }
  where
    moduleDiffs = map (classify ModuleEntry) reg.modules
    recipeDiffs = map (classify RecipeEntry) reg.recipes

    classify :: EntryKind -> RegistryEntry -> SyncDiff
    classify kind entry =
      let onDisk = lookupOnDisk kind entry.name
          status = case (entry.version, onDisk) of
            (_, OnDiskMissing) -> SyncOrphan
            (Nothing, OnDiskValue Nothing) -> SyncInSync
            (Nothing, OnDiskValue (Just _)) -> SyncMissing
            (Just _, OnDiskValue Nothing) -> SyncInSync
            (Just old, OnDiskValue (Just new))
              | old == new -> SyncInSync
              | otherwise -> SyncStale new
          newVersion = case onDisk of
            OnDiskMissing -> entry.version
            OnDiskValue v -> v
       in SyncDiff
            { diffKind = kind,
              diffName = entry.name,
              diffOld = entry.version,
              diffNew = newVersion,
              diffStatus = status
            }

    applyDiff :: SyncDiff -> RegistryEntry -> RegistryEntry
    applyDiff diff entry = case diff.diffStatus of
      SyncOrphan -> entry
      _ -> entry {version = diff.diffNew}

    lookupOnDisk :: EntryKind -> ModuleName -> OnDiskVersion
    lookupOnDisk kind name =
      case [v | (k, n, v) <- lookups, k == kind, n == name] of
        [] -> OnDiskMissing
        (v : _) -> OnDiskValue v

-- | Three-way state used internally by 'computeRegistrySync' to distinguish
-- \"entry absent from the lookup list\" (orphan) from \"entry present, version
-- field is @Nothing@\" (in-sync with an unversioned module.dhall).
data OnDiskVersion = OnDiskMissing | OnDiskValue (Maybe Text)

-- | Serialize a 'Registry' as a Dhall record literal compatible with
-- 'Seihou.Dhall.Eval.registryDecoder'. Rewrites lose hand-written comments
-- and formatting; see @docs/plans/12-sync-registry-versions.md@ for rationale.
renderRegistryDhall :: Registry -> Text
renderRegistryDhall reg =
  T.unlines
    [ "{ repoName = " <> renderString reg.repoName,
      ", repoDescription = " <> renderOptionalText reg.repoDescription,
      ", modules =",
      renderEntryList reg.modules,
      ", recipes =",
      renderEntryList reg.recipes,
      "}"
    ]

renderEntryList :: [RegistryEntry] -> Text
renderEntryList [] =
  "  [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }"
renderEntryList entries =
  T.intercalate
    "\n"
    (zipWith renderEntry (True : repeat False) entries <> ["  ]"])

renderEntry :: Bool -> RegistryEntry -> Text
renderEntry isFirst entry =
  T.intercalate
    "\n"
    [ "  " <> opener <> " { name = " <> renderString entry.name.unModuleName,
      "    , version = " <> renderOptionalText entry.version,
      "    , path = " <> renderString (T.pack entry.path),
      "    , description = " <> renderOptionalText entry.description,
      "    , tags = " <> renderTextList entry.tags,
      "    }"
    ]
  where
    opener = if isFirst then "[" else ","

renderOptionalText :: Maybe Text -> Text
renderOptionalText Nothing = "None Text"
renderOptionalText (Just v) = "Some " <> renderString v

renderTextList :: [Text] -> Text
renderTextList [] = "[] : List Text"
renderTextList xs = "[ " <> T.intercalate ", " (map renderString xs) <> " ]"

-- | Render a Dhall double-quoted string literal.
-- Escapes backslashes, double quotes, dollar signs (for interpolation),
-- and common control characters per the Dhall spec.
renderString :: Text -> Text
renderString t = "\"" <> T.concatMap escape t <> "\""
  where
    escape '\\' = "\\\\"
    escape '"' = "\\\""
    escape '$' = "\\$"
    escape '\n' = "\\n"
    escape '\r' = "\\r"
    escape '\t' = "\\t"
    escape c = T.singleton c
