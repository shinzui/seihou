module Seihou.CLI.Update.Source
  ( stageCandidateSources,
    hashArtifactDirectory,
    artifactDirectoryOnThisMachine,
  )
where

import Control.Exception (SomeException, displayException, try)
import Control.Monad (foldM, forM)
import Data.ByteString qualified as BS
import Data.Foldable (traverse_)
import Data.Generics.Labels ()
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Seihou.CLI.InstallShared
  ( OriginInfo (..),
    cloneRepo,
    copyDirectoryRecursive,
  )
import Seihou.CLI.Update.Types
import Seihou.Core.Module (defaultSearchPaths, discoverRunnable, validateModule)
import Seihou.Core.Recipe (validateRecipe)
import Seihou.Core.Registry (Registry (..), RegistryEntry (..), validateRegistry)
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalModuleFromFile, evalRecipeFromFile, evalRegistryFromFile)
import Seihou.Manifest.Hash (hashContent)
import Seihou.Prelude
import System.Directory qualified as Directory
import System.Exit (ExitCode (..))
import System.Process (readProcessWithExitCode)

data ArtifactRequirement = ArtifactRequirement
  { kind :: !CandidateArtifactKind,
    name :: !Text,
    sourceDirectory :: !FilePath,
    origin :: !(Maybe OriginInfo)
  }
  deriving stock (Generic)

-- | Clone every distinct remote once, validate its complete module/recipe
-- catalog, and materialize a name-keyed temporary search root. Local artifacts
-- remain a fallback and are called out explicitly.
stageCandidateSources ::
  FilePath ->
  FilePath ->
  FilePath ->
  [AppliedComposition] ->
  IO (Either UpdateError (CandidateCatalog, [UpdateWarning]))
stageCandidateSources sessionRoot projectRoot installedDirectory selected = do
  requirements <- requirementsFor projectRoot installedDirectory selected
  let remoteOrigins =
        Map.fromList
          [ (origin ^. #sourceUrl, origin)
          | requirement <- requirements,
            Just origin <- [requirement ^. #origin]
          ]
      clonesRoot = sessionRoot </> "clones"
      searchRoot = sessionRoot </> "search"
  Directory.createDirectoryIfMissing True clonesRoot
  Directory.createDirectoryIfMissing True searchRoot
  remoteResult <- stageRemoteOrigins clonesRoot searchRoot (Map.toAscList remoteOrigins)
  case remoteResult of
    Left err -> pure (Left err)
    Right (remoteArtifacts, clones) -> do
      localResult <- stageLocalRequirements searchRoot remoteArtifacts requirements
      pure $ do
        (allArtifacts, localWarnings) <- localResult
        verifyRemoteRequirements requirements allArtifacts
        Right
          ( CandidateCatalog
              { searchRoot,
                artifacts = allArtifacts,
                clonedOrigins = clones
              },
            localWarnings
          )

requirementsFor :: FilePath -> FilePath -> [AppliedComposition] -> IO [ArtifactRequirement]
requirementsFor projectRoot installedDirectory applications = concat <$> mapM applicationRequirements applications
  where
    applicationRequirements application = do
      targetRequirement <-
        requirement
          ( case application ^. #target of
              AppliedModuleTarget name -> (CandidateModule, name ^. #unModuleName)
              AppliedRecipeTarget name -> (CandidateRecipe, name ^. #unRecipeName)
          )
          (application ^. #targetOrigin)
      instanceRequirements <-
        forM (application ^. #instances) $ \state ->
          requirement (CandidateModule, state ^. #name . #unModuleName) (state ^. #origin)
      pure (targetRequirement : instanceRequirements)

    requirement (kind, name) origin = do
      sourceDirectory <- artifactDirectoryOnThisMachine projectRoot installedDirectory origin
      pure ArtifactRequirement {kind, name, sourceDirectory, origin = remoteProvenance origin}

-- | Recover the remote-provenance view an update needs from the manifest's
-- portable origin.
--
-- Before schema version 6 this was read from the @.seihou-origin.json@ file
-- beside the absolute path the manifest recorded — that is, from whatever the
-- machine that ran the command happened to have installed. Taking it from the
-- manifest instead is both portable and more authoritative: it is the
-- project's own record of what it was generated from. The installed-at
-- version is deliberately not reconstructed here; nothing in staging reads it.
remoteProvenance :: ArtifactOrigin -> Maybe OriginInfo
remoteProvenance (RemoteOrigin url _ repo) = Just (OriginInfo url repo Nothing)
remoteProvenance (ProjectOrigin _) = Nothing
remoteProvenance (LocalOrigin _) = Nothing

-- | Where the artifact an origin names currently lives on this machine.
--
-- The manifest deliberately records no absolute path, so anything that has to
-- look at an artifact's bytes — staging a local fallback, hashing the
-- currently-applied content — has to ask this question first. A
-- 'RemoteOrigin' resolves to its slot in the install cache, a 'ProjectOrigin'
-- to a directory inside the project, and a 'LocalOrigin' to whatever ordinary
-- discovery finds by that name. When discovery finds nothing the bare name is
-- returned, so the caller fails with its own "cannot read this artifact"
-- error rather than silently reading something else.
--
-- Resolving an origin back to a directory is owned in general by
-- docs/plans/77-resolve-manifest-artifact-origins-to-local-directories.md,
-- which replaces this helper with @Seihou.Core.ArtifactRef@ and its
-- user-facing resolution-error type. It lives here for now so schema version
-- 6 does not have to land with @seihou update@ broken.
artifactDirectoryOnThisMachine :: FilePath -> FilePath -> ArtifactOrigin -> IO FilePath
artifactDirectoryOnThisMachine projectRoot installedDirectory origin = case origin of
  RemoteOrigin _ name _ -> pure (installedDirectory </> T.unpack name)
  ProjectOrigin relative -> pure (projectRoot </> relative)
  LocalOrigin name -> do
    searchPaths <- defaultSearchPaths
    discovered <- discoverRunnable searchPaths (ModuleName name)
    pure $ case discovered of
      Right (RunnableModule _ directory) -> directory
      Right (RunnableRecipe _ directory) -> directory
      Right (RunnableBlueprint _ directory) -> directory
      Right (RunnableAgentPrompt _ directory) -> directory
      Left _ -> T.unpack name

stageRemoteOrigins ::
  FilePath ->
  FilePath ->
  [(Text, OriginInfo)] ->
  IO
    ( Either
        UpdateError
        (Map (CandidateArtifactKind, Text) CandidateArtifact, Map Text FilePath)
    )
stageRemoteOrigins clonesRoot searchRoot = go 0 Map.empty Map.empty
  where
    go _ artifacts clones [] = pure (Right (artifacts, clones))
    go index artifacts clones ((url, origin) : rest) = do
      let cloneDirectory = clonesRoot </> show index
      cloneResult <- cloneRepo url cloneDirectory
      case cloneResult of
        Left message -> pure (Left (CandidateCloneFailed url message))
        Right () -> do
          revision <- gitRevision cloneDirectory
          discovered <- discoverRemote url origin revision cloneDirectory
          case discovered of
            Left err -> pure (Left err)
            Right candidates -> do
              inserted <- foldM (insertCandidate searchRoot) (Right artifacts) candidates
              case inserted of
                Left err -> pure (Left err)
                Right artifacts' ->
                  go (index + 1) artifacts' (Map.insert url cloneDirectory clones) rest

discoverRemote ::
  Text ->
  OriginInfo ->
  Maybe Text ->
  FilePath ->
  IO (Either UpdateError [CandidateArtifact])
discoverRemote url origin revision repoRoot = do
  let registryFile = repoRoot </> "seihou-registry.dhall"
  hasRegistry <- Directory.doesFileExist registryFile
  if hasRegistry
    then do
      decoded <- evalRegistryFromFile registryFile
      case decoded of
        Left err -> pure (Left (CandidateLoadFailed (T.pack registryFile) err))
        Right registry -> do
          validationErrors <- validateRegistry repoRoot registry
          if null validationErrors
            then discoverRegistryArtifacts url revision repoRoot registry
            else pure (Left (CandidateRepositoryInvalid url validationErrors))
    else discoverSingleArtifact url origin revision repoRoot

discoverRegistryArtifacts ::
  Text ->
  Maybe Text ->
  FilePath ->
  Registry ->
  IO (Either UpdateError [CandidateArtifact])
discoverRegistryArtifacts url revision repoRoot registry = do
  modules <- traverse (loadRemoteModule url (Just (registry ^. #repoName)) revision repoRoot) (registry ^. #modules)
  recipes <- traverse (loadRemoteRecipe url (Just (registry ^. #repoName)) revision repoRoot) (registry ^. #recipes)
  pure ((<>) <$> sequence modules <*> sequence recipes)

discoverSingleArtifact ::
  Text ->
  OriginInfo ->
  Maybe Text ->
  FilePath ->
  IO (Either UpdateError [CandidateArtifact])
discoverSingleArtifact url origin revision repoRoot = do
  hasModule <- Directory.doesFileExist (repoRoot </> "module.dhall")
  hasRecipe <- Directory.doesFileExist (repoRoot </> "recipe.dhall")
  if hasModule
    then fmap (fmap (: [])) (loadModuleArtifact (Just url) (origin ^. #repoName) [] revision repoRoot)
    else
      if hasRecipe
        then fmap (fmap (: [])) (loadRecipeArtifact (Just url) (origin ^. #repoName) [] revision repoRoot)
        else pure (Left (CandidateRepositoryInvalid url ["repository contains no module, recipe, or registry"]))

loadRemoteModule ::
  Text -> Maybe Text -> Maybe Text -> FilePath -> RegistryEntry -> IO (Either UpdateError CandidateArtifact)
loadRemoteModule url repoName revision repoRoot entry =
  loadModuleArtifact (Just url) repoName (entry ^. #tags) revision (repoRoot </> entry ^. #path)

loadRemoteRecipe ::
  Text -> Maybe Text -> Maybe Text -> FilePath -> RegistryEntry -> IO (Either UpdateError CandidateArtifact)
loadRemoteRecipe url repoName revision repoRoot entry =
  loadRecipeArtifact (Just url) repoName (entry ^. #tags) revision (repoRoot </> entry ^. #path)

loadModuleArtifact ::
  Maybe Text -> Maybe Text -> [Text] -> Maybe Text -> FilePath -> IO (Either UpdateError CandidateArtifact)
loadModuleArtifact sourceUrl repoName tags revision directory = do
  decoded <- evalModuleFromFile (directory </> "module.dhall")
  case decoded of
    Left err -> pure (Left (CandidateLoadFailed (T.pack directory) err))
    Right modul -> do
      validated <- validateModule directory modul
      case validated of
        Left err -> pure (Left (CandidateLoadFailed (modul ^. #name . #unModuleName) err))
        Right candidateModule -> do
          contentHash <- hashArtifactDirectory directory
          pure
            ( Right
                CandidateArtifact
                  { kind = CandidateModule,
                    name = candidateModule ^. #name . #unModuleName,
                    version = candidateModule ^. #version,
                    originalDirectory = directory,
                    sourceDirectory = directory,
                    sourceUrl,
                    repoName,
                    tags,
                    sourceRevision = revision,
                    contentHash,
                    moduleDefinition = Just candidateModule,
                    recipeDefinition = Nothing
                  }
            )

loadRecipeArtifact ::
  Maybe Text -> Maybe Text -> [Text] -> Maybe Text -> FilePath -> IO (Either UpdateError CandidateArtifact)
loadRecipeArtifact sourceUrl repoName tags revision directory = do
  decoded <- evalRecipeFromFile (directory </> "recipe.dhall")
  case first (CandidateLoadFailed (T.pack directory)) decoded of
    Left err -> pure (Left err)
    Right recipe -> case first (CandidateRepositoryInvalid (maybe "local" id sourceUrl)) (validateRecipe recipe) of
      Left err -> pure (Left err)
      Right validated -> do
        contentHash <- hashArtifactDirectory directory
        pure
          ( Right
              CandidateArtifact
                { kind = CandidateRecipe,
                  name = validated ^. #name . #unRecipeName,
                  version = validated ^. #version,
                  originalDirectory = directory,
                  sourceDirectory = directory,
                  sourceUrl,
                  repoName,
                  tags,
                  sourceRevision = revision,
                  contentHash,
                  moduleDefinition = Nothing,
                  recipeDefinition = Just validated
                }
          )

stageLocalRequirements ::
  FilePath ->
  Map (CandidateArtifactKind, Text) CandidateArtifact ->
  [ArtifactRequirement] ->
  IO (Either UpdateError (Map (CandidateArtifactKind, Text) CandidateArtifact, [UpdateWarning]))
stageLocalRequirements searchRoot initial = go initial []
  where
    go artifacts warnings [] = pure (Right (artifacts, reverse warnings))
    go artifacts warnings (requirement : rest) = case requirement ^. #origin of
      Just _ -> go artifacts warnings rest
      Nothing
        | Map.member (requirement ^. #kind, requirement ^. #name) artifacts -> go artifacts warnings rest
        | otherwise -> do
            loaded <- case requirement ^. #kind of
              CandidateModule -> loadModuleArtifact Nothing Nothing [] Nothing (requirement ^. #sourceDirectory)
              CandidateRecipe -> loadRecipeArtifact Nothing Nothing [] Nothing (requirement ^. #sourceDirectory)
            case loaded of
              Left err -> pure (Left err)
              Right candidate -> do
                inserted <- insertCandidate searchRoot (Right artifacts) candidate
                case inserted of
                  Left err -> pure (Left err)
                  Right artifacts' ->
                    go artifacts' (LocalArtifactHasNoRemote (requirement ^. #name) : warnings) rest

insertCandidate ::
  FilePath ->
  Either UpdateError (Map (CandidateArtifactKind, Text) CandidateArtifact) ->
  CandidateArtifact ->
  IO (Either UpdateError (Map (CandidateArtifactKind, Text) CandidateArtifact))
insertCandidate _ (Left err) _ = pure (Left err)
insertCandidate searchRoot (Right artifacts) candidate =
  case Map.lookup key artifacts of
    Just existing ->
      pure
        ( Left
            ( CandidateArtifactAmbiguous
                (candidate ^. #kind)
                (candidate ^. #name)
                (map (maybe "local" id . (^. #sourceUrl)) [existing, candidate])
            )
        )
    Nothing -> do
      let destination = searchRoot </> T.unpack (candidate ^. #name)
      Directory.createDirectoryIfMissing True destination
      copied <- try @SomeException (copyDirectoryRecursive (candidate ^. #sourceDirectory) destination)
      pure $ case copied of
        Left err -> Left (CandidateRepositoryInvalid (candidate ^. #name) [T.pack (displayException err)])
        Right () ->
          Right
            ( Map.insert
                key
                (setCandidateSource destination candidate)
                artifacts
            )
  where
    key = (candidate ^. #kind, candidate ^. #name)

setCandidateSource :: FilePath -> CandidateArtifact -> CandidateArtifact
setCandidateSource directory candidate =
  CandidateArtifact
    { kind = candidate ^. #kind,
      name = candidate ^. #name,
      version = candidate ^. #version,
      originalDirectory = candidate ^. #originalDirectory,
      sourceDirectory = directory,
      sourceUrl = candidate ^. #sourceUrl,
      repoName = candidate ^. #repoName,
      tags = candidate ^. #tags,
      sourceRevision = candidate ^. #sourceRevision,
      contentHash = candidate ^. #contentHash,
      moduleDefinition = candidate ^. #moduleDefinition,
      recipeDefinition = candidate ^. #recipeDefinition
    }

verifyRemoteRequirements ::
  [ArtifactRequirement] ->
  Map (CandidateArtifactKind, Text) CandidateArtifact ->
  Either UpdateError ()
verifyRemoteRequirements requirements artifacts = traverse_ verify requirements
  where
    verify requirement = case Map.lookup (requirement ^. #kind, requirement ^. #name) artifacts of
      Nothing -> Left (CandidateArtifactMissing (requirement ^. #kind) (requirement ^. #name))
      Just candidate -> case requirement ^. #origin of
        Nothing -> Right ()
        Just origin
          | candidate ^. #sourceUrl == Just (origin ^. #sourceUrl) -> Right ()
          | otherwise -> Left (CandidateArtifactMissing (requirement ^. #kind) (requirement ^. #name))

gitRevision :: FilePath -> IO (Maybe Text)
gitRevision directory = do
  result <- try @SomeException (readProcessWithExitCode "git" ["-C", directory, "rev-parse", "HEAD"] "")
  pure $ case result of
    Right (ExitSuccess, stdout, _) -> Just (T.strip (T.pack stdout))
    _ -> Nothing

hashArtifactDirectory :: FilePath -> IO SHA256
hashArtifactDirectory root = do
  entries <- collectFiles root ""
  chunks <- forM entries $ \relative -> do
    bytes <- BS.readFile (root </> relative)
    pure (T.pack relative <> "\NUL" <> T.pack (show bytes))
  pure (hashContent (T.intercalate "\NUL" chunks))
  where
    collectFiles base relative = do
      let directory = if null relative then base else base </> relative
      names <- sort <$> Directory.listDirectory directory
      fmap concat $ forM names $ \name -> do
        let childRelative = if null relative then name else relative </> name
            child = base </> childRelative
        isDirectory <- Directory.doesDirectoryExist child
        if name == ".seihou-origin.json"
          then pure []
          else
            if isDirectory
              then
                if name == ".git"
                  then pure []
                  else collectFiles base childRelative
              else pure [childRelative]
