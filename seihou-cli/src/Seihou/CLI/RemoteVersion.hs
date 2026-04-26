module Seihou.CLI.RemoteVersion
  ( FetchError (..),
    fetchTrueModuleVersion,
    renderFetchError,
  )
where

import Data.Text qualified as T
import Seihou.Core.Registry (Registry (..), RegistryEntry (..), RepoContents (..), discoverRepoContents)
import Seihou.Core.Types (Module (..), ModuleName (..))
import Seihou.Dhall.Eval (evalModuleFromFile, evalRegistryFromFile)
import Seihou.Prelude
import System.Directory (doesFileExist)

-- | Reasons a remote-version lookup can fail. These are distinct from
-- "the module declares no version", which is represented by @Right Nothing@
-- in the result of 'fetchTrueModuleVersion'.
data FetchError
  = -- | The repo had no @seihou-registry.dhall@ and no @module.dhall@ at the
    --   root, so the cloned tree exposes nothing we can read. Carries the
    --   path that was checked.
    RegistryNotFound FilePath
  | -- | The repo's @seihou-registry.dhall@ parsed, but no entry whose
    --   @name@ matches the requested module name.
    EntryNotFound ModuleName
  | -- | The path the registry pointed at (or the single-module root) does
    --   not contain a @module.dhall@ file. Carries the absolute path that
    --   was checked.
    ModuleDhallNotFound FilePath
  | -- | Either @seihou-registry.dhall@ or @module.dhall@ failed to evaluate
    --   or decode. Carries a human-readable description of the failure.
    ParseFailed Text
  deriving stock (Show, Eq)

-- | Read the truthful @version@ field of a module declared in a cloned
-- repository. Reads the module's @module.dhall@ directly, ignoring any
-- @version@ field that the registry might also declare.
--
-- The third state in the result, @Right Nothing@, represents a module whose
-- @module.dhall@ declares @version = None Text@ — i.e., an unversioned
-- module. Callers display this as "unversioned" rather than as an error.
--
-- Behavior depends on what the cloned repo contains, as classified by
-- 'discoverRepoContents':
--
--   * 'MultiModule' — look up the registry entry by name, then read
--     @<clone>/<entry.path>/module.dhall@.
--   * 'SingleModule' — read @<clone>/module.dhall@ regardless of the
--     requested name. (Single-module repos host exactly one module; the
--     name in @module.dhall@ is its own source of truth.)
--   * 'SingleRecipe' or 'EmptyRepo' — no module to read; return
--     'RegistryNotFound'.
fetchTrueModuleVersion :: FilePath -> ModuleName -> IO (Either FetchError (Maybe Text))
fetchTrueModuleVersion clonedRepoPath name = do
  contents <- discoverRepoContents evalRegistryFromFile clonedRepoPath
  case contents of
    SingleModule rootDir ->
      readModuleDhallVersion (rootDir </> "module.dhall")
    MultiModule registry -> case findEntry registry of
      Nothing -> pure (Left (EntryNotFound name))
      Just entry ->
        readModuleDhallVersion (clonedRepoPath </> entry.path </> "module.dhall")
    SingleRecipe _ -> pure (Left (RegistryNotFound clonedRepoPath))
    EmptyRepo -> pure (Left (RegistryNotFound clonedRepoPath))
  where
    findEntry :: Registry -> Maybe RegistryEntry
    findEntry registry =
      case filter (\e -> e.name == name) registry.modules of
        (entry : _) -> Just entry
        [] -> Nothing

-- | Read a @module.dhall@ at the given path and return its @version@ field.
readModuleDhallVersion :: FilePath -> IO (Either FetchError (Maybe Text))
readModuleDhallVersion path = do
  exists <- doesFileExist path
  if not exists
    then pure (Left (ModuleDhallNotFound path))
    else do
      result <- evalModuleFromFile path
      case result of
        Left err -> pure (Left (ParseFailed (T.pack (show err))))
        Right modul -> pure (Right modul.version)

-- | Render a 'FetchError' as a single-line human-readable message suitable
-- for printing in CLI output ("could not determine remote version: ...").
renderFetchError :: FetchError -> Text
renderFetchError = \case
  RegistryNotFound path ->
    "no module.dhall or seihou-registry.dhall in " <> T.pack path
  EntryNotFound (ModuleName n) ->
    "module '" <> n <> "' not listed in remote registry"
  ModuleDhallNotFound path ->
    "module.dhall not found at " <> T.pack path
  ParseFailed msg ->
    "could not parse remote module: " <> msg
