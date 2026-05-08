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
    formatDriftWarning,
    RegistryValidationIssue (..),
    RegistryValidationReport (..),
    reportHasIssues,
    validateRegistryFull,
    formatValidationIssue,
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
    recipes :: [RegistryEntry],
    blueprints :: [RegistryEntry]
  }
  deriving stock (Eq, Show, Generic)

-- | What a cloned repository contains.
data RepoContents
  = -- | Repo root has @module.dhall@ (single module)
    SingleModule FilePath
  | -- | Repo root has @recipe.dhall@ (single recipe)
    SingleRecipe FilePath
  | -- | Repo root has @blueprint.dhall@ (single blueprint)
    SingleBlueprint FilePath
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
  hasRegistry <- doesFileExist registryFile
  if hasRegistry
    then do
      result <- evalRegistry registryFile
      case result of
        Right reg -> pure (MultiModule reg)
        Left _ -> probeSingleArtifact repoRoot
    else probeSingleArtifact repoRoot

-- | Probe for a single-artifact repo at @repoRoot@. Precedence:
-- @module.dhall@ → @recipe.dhall@ → @blueprint.dhall@ → 'EmptyRepo'.
-- A stray @module.dhall@ next to a @blueprint.dhall@ resolves as the
-- module: the more specific, deterministic artifact wins.
probeSingleArtifact :: FilePath -> IO RepoContents
probeSingleArtifact repoRoot = do
  let moduleFile = repoRoot </> "module.dhall"
      recipeFile = repoRoot </> "recipe.dhall"
      blueprintFile = repoRoot </> "blueprint.dhall"
  hasModule <- doesFileExist moduleFile
  if hasModule
    then pure (SingleModule repoRoot)
    else do
      hasRecipe <- doesFileExist recipeFile
      if hasRecipe
        then pure (SingleRecipe repoRoot)
        else do
          hasBlueprint <- doesFileExist blueprintFile
          if hasBlueprint
            then pure (SingleBlueprint repoRoot)
            else pure EmptyRepo

-- | Validate a registry's entries against the filesystem.
-- Returns a list of error messages (empty means valid).
-- Checks: module name format, path safety, entry file existence,
-- and no name collisions between modules, recipes, and blueprints.
validateRegistry :: FilePath -> Registry -> IO [Text]
validateRegistry repoRoot reg = do
  modErrs <- concat <$> mapM (validateModuleEntry repoRoot) reg.modules
  recErrs <- concat <$> mapM (validateRecipeEntry repoRoot) reg.recipes
  bpErrs <- concat <$> mapM (validateBlueprintEntry repoRoot) reg.blueprints
  let collisionErrs = checkNameCollisions reg.modules reg.recipes reg.blueprints
  pure (modErrs <> recErrs <> bpErrs <> collisionErrs)

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

validateBlueprintEntry :: FilePath -> RegistryEntry -> IO [Text]
validateBlueprintEntry repoRoot entry = do
  let nameText = entry.name.unModuleName
      nameErrors = checkBlueprintName nameText
      pathText = T.pack entry.path
      pathErrors = checkBlueprintPath pathText
  let blueprintDhall = repoRoot </> entry.path </> "blueprint.dhall"
  fileExists <- doesFileExist blueprintDhall
  let fileErrors =
        if fileExists
          then []
          else ["registry blueprint entry '" <> nameText <> "' points to missing blueprint.dhall at " <> pathText]
  pure (nameErrors <> pathErrors <> fileErrors)
  where
    checkBlueprintName name
      | validModuleName name = []
      | otherwise = ["registry blueprint name must match [a-z][a-z0-9-]*, got: " <> name]

    checkBlueprintPath path
      | T.isPrefixOf "/" path = ["registry blueprint path must be relative: " <> path]
      | ".." `T.isInfixOf` path = ["registry blueprint path must not contain '..': " <> path]
      | otherwise = []

-- | Detect name collisions across module, recipe, and blueprint entries.
-- Each cross-kind pair sharing a name produces one message; a name that
-- appears in all three kinds produces three messages (one per pair).
checkNameCollisions :: [RegistryEntry] -> [RegistryEntry] -> [RegistryEntry] -> [Text]
checkNameCollisions mods recs bps =
  let modNames = map (\e -> e.name.unModuleName) mods
      recNames = map (\e -> e.name.unModuleName) recs
      bpNames = map (\e -> e.name.unModuleName) bps
      modRec = [n | n <- modNames, n `elem` recNames]
      modBp = [n | n <- modNames, n `elem` bpNames]
      recBp = [n | n <- recNames, n `elem` bpNames]
   in map (\n -> "name collision: '" <> n <> "' appears as both a module and a recipe") modRec
        <> map (\n -> "name collision: '" <> n <> "' appears as both a module and a blueprint") modBp
        <> map (\n -> "name collision: '" <> n <> "' appears as both a recipe and a blueprint") recBp

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
data EntryKind = ModuleEntry | RecipeEntry | BlueprintEntry
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
    { syncDiffs = moduleDiffs <> recipeDiffs <> blueprintDiffs,
      syncUpdated =
        reg
          { modules = zipWith applyDiff moduleDiffs reg.modules,
            recipes = zipWith applyDiff recipeDiffs reg.recipes,
            blueprints = zipWith applyDiff blueprintDiffs reg.blueprints
          }
    }
  where
    moduleDiffs = map (classify ModuleEntry) reg.modules
    recipeDiffs = map (classify RecipeEntry) reg.recipes
    blueprintDiffs = map (classify BlueprintEntry) reg.blueprints

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

-- | Format a single 'SyncDiff' as a human-readable drift warning, or
-- 'Nothing' if the entry is already in sync. Used by @seihou browse@ and
-- @seihou install@ to surface stale registry versions without blocking.
formatDriftWarning :: SyncDiff -> Maybe Text
formatDriftWarning diff = case diff.diffStatus of
  SyncInSync -> Nothing
  SyncOrphan -> Nothing
  SyncMissing ->
    Just $
      kindWord diff.diffKind
        <> " '"
        <> diff.diffName.unModuleName
        <> "' registry version is missing; "
        <> entryFile diff.diffKind
        <> " declares "
        <> renderVersion diff.diffNew
        <> " — run `seihou registry sync-versions`"
  SyncStale newVer ->
    Just $
      kindWord diff.diffKind
        <> " '"
        <> diff.diffName.unModuleName
        <> "' registry version "
        <> renderVersion diff.diffOld
        <> " differs from "
        <> entryFile diff.diffKind
        <> " version "
        <> newVer
        <> " — run `seihou registry sync-versions`"
  where
    renderVersion Nothing = "(none)"
    renderVersion (Just v) = v
    kindWord ModuleEntry = "module"
    kindWord RecipeEntry = "recipe"
    kindWord BlueprintEntry = "blueprint"
    entryFile ModuleEntry = "module.dhall"
    entryFile RecipeEntry = "recipe.dhall"
    entryFile BlueprintEntry = "blueprint.dhall"

-- | One row of the unified validation report. Either reuses an existing
-- structural error message (path/name/file-existence/collisions) or
-- carries a version-mismatch row classified by 'SyncStatus'.
data RegistryValidationIssue
  = StructuralError Text
  | VersionMismatch SyncDiff
  deriving stock (Eq, Show, Generic)

-- | Whole-registry validation outcome, carrying every issue plus the
-- entry counts used by the human-readable summary line.
data RegistryValidationReport = RegistryValidationReport
  { reportIssues :: [RegistryValidationIssue],
    reportModuleCount :: Int,
    reportRecipeCount :: Int,
    reportBlueprintCount :: Int
  }
  deriving stock (Eq, Show, Generic)

-- | True iff the report has at least one issue.
reportHasIssues :: RegistryValidationReport -> Bool
reportHasIssues r = not (null r.reportIssues)

-- | Combine the existing structural checks with version classification.
-- The third argument is the same shape 'computeRegistrySync' takes —
-- the caller loads each entry's @module.dhall@/@recipe.dhall@ once and
-- passes a lookup list keyed by @(kind, name)@.
validateRegistryFull ::
  FilePath ->
  Registry ->
  [(EntryKind, ModuleName, Maybe Text)] ->
  IO RegistryValidationReport
validateRegistryFull repoRoot reg lookups = do
  structuralErrs <- validateRegistry repoRoot reg
  let report = computeRegistrySync reg lookups
      versionIssues =
        [ VersionMismatch d
        | d <- report.syncDiffs,
          isVersionDrift d.diffStatus
        ]
  pure
    RegistryValidationReport
      { reportIssues = map StructuralError structuralErrs <> versionIssues,
        reportModuleCount = length reg.modules,
        reportRecipeCount = length reg.recipes,
        reportBlueprintCount = length reg.blueprints
      }
  where
    isVersionDrift SyncMissing = True
    isVersionDrift (SyncStale _) = True
    isVersionDrift _ = False

-- | Render a single 'RegistryValidationIssue' as a one-line human-readable
-- string. 'VersionMismatch' rows reuse the @modules.foo@/@recipes.bar@
-- prefix used by @sync-versions@ but omit the trailing
-- "run @seihou registry sync-versions@" suggestion — the validate handler
-- prints a single aggregated suggestion at the bottom.
formatValidationIssue :: RegistryValidationIssue -> Text
formatValidationIssue (StructuralError msg) = msg
formatValidationIssue (VersionMismatch diff) =
  validationKindPrefix diff.diffKind
    <> diff.diffName.unModuleName
    <> ": registry version "
    <> validationRenderVersion diff.diffOld
    <> " does not match "
    <> entryFile diff.diffKind
    <> " version "
    <> validationRenderVersion diff.diffNew
  where
    entryFile ModuleEntry = "module.dhall"
    entryFile RecipeEntry = "recipe.dhall"
    entryFile BlueprintEntry = "blueprint.dhall"

validationKindPrefix :: EntryKind -> Text
validationKindPrefix ModuleEntry = "modules."
validationKindPrefix RecipeEntry = "recipes."
validationKindPrefix BlueprintEntry = "blueprints."

validationRenderVersion :: Maybe Text -> Text
validationRenderVersion Nothing = "(none)"
validationRenderVersion (Just v) = v

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
      ", blueprints =",
      renderEntryList reg.blueprints,
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
