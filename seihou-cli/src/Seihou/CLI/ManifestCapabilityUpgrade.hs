-- | Establish the shared-write mode of manifest paths whose mode is
-- 'SharedWriteUnknown', without touching any project file.
--
-- A path's mode is a conjunction across its owners: it is additive-only
-- exactly when every owner reaches it through an additive, non-overlapping
-- patch ('isAdditiveOperation'), and it requires the ownership closure when
-- any owner writes it otherwise
-- (docs\/adr\/0012-an-additive-co-write-is-not-a-shared-path-conflict.md).
-- A schema-6 manifest usually cannot say which, so this module recompiles
-- the owners' operations and reads the answer off them.
--
-- The work is split in two. 'certifySharedWriteModes' is pure: given the
-- manifest and the operations each owner compiles to, it classifies every
-- path in scope. 'gatherApplicationEvidence' is the IO shell that obtains
-- those operations from what the manifest records — each instance's
-- recorded origin, version, parent variables and resolved values — and
-- refuses any artifact that is not provably the one recorded
-- (docs\/adr\/0003-a-stale-or-substituted-artifact-is-a-hard-error.md).
-- Compilation never reconciles, executes a command, applies a migration, or
-- writes anything; its only product is operations to inspect.
--
-- A path is certified additive-only only when operations for every owner are
-- available and all of them are additive. One owner that writes the path any
-- other way proves a closure requirement by itself. Anything else leaves the
-- path 'SharedWriteUnknown' with a reason, so the caller keeps the ownership
-- closure rather than guessing.
module Seihou.CLI.ManifestCapabilityUpgrade
  ( -- * Scope and evidence
    CertificationScope (..),
    EvidencePolicy (..),
    EvidenceSource (..),
    ApplicationEvidence (..),
    CertificationGap (..),
    SharedWriteCertificationEntry (..),
    SharedWriteCertification (..),

    -- * Classifying
    certifySharedWriteModes,
    pathsInScope,
    certifiedChanges,

    -- * Obtaining evidence
    gatherApplicationEvidence,
    certifySharedWriteModesIO,

    -- * Rendering
    renderCertificationGap,
    renderEvidenceSource,
  )
where

import Data.Containers.ListUtils (nubOrd)
import Data.Generics.Labels ()
import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text qualified as T
import Seihou.CLI.ManifestGuard (ArtifactVerdict (..), judgeArtifact, machineLocalOriginNote)
import Seihou.CLI.RecordedRelease (RecordedRelease (..), locateRecordedRelease, renderRecordedReleaseError)
import Seihou.Composition.Instance (ModuleInstance (..))
import Seihou.Composition.Plan (compileComposedPlan)
import Seihou.Composition.Resolve (PromptPermission (..), resolveWithPromptPermission)
import Seihou.Core.ArtifactIdentity (isMachineLocalOriginUrl)
import Seihou.Core.ArtifactOriginDetect (detectArtifactOrigin)
import Seihou.Core.ArtifactRef (resolveArtifactOrigin)
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalModuleFromFile)
import Seihou.Effect.ConsoleInterp (runConsole)
import Seihou.Prelude
import System.Directory (doesPathExist)

-- | Which unknown paths to certify.
data CertificationScope
  = -- | Every path whose mode is unknown. Used by the explicit
    -- @seihou manifest upgrade@.
    CertifyAllUnknownPaths
  | -- | Only unknown paths that one of these applications shares with an
    -- application outside the set: the paths whose mode decides whether a
    -- targeted update of these applications may leave a co-owner out.
    CertifyPathsForApplications !(Set ApplicationId)
  deriving stock (Eq, Show, Generic)

-- | Where a co-owner's recorded release may be read from.
data EvidencePolicy
  = -- | Only copies installed on this machine.
    InstalledReleasesOnly
  | -- | Installed copies first; otherwise the exact recorded release, fetched
    --   from the recorded remote into this session directory. The fetched
    --   copy never enters the install cache
    --   (docs\/adr\/0012-an-additive-co-write-is-not-a-shared-path-conflict.md).
    FetchRecordedReleases !FilePath
  deriving stock (Eq, Show, Generic)

-- | A module instance whose evidence was read from a fetched recorded
-- release rather than an installed copy.
data EvidenceSource = EvidenceSource
  { moduleName :: !ModuleName,
    version :: !Text,
    originUrl :: !Text,
    -- | The short id of the commit the release was read at.
    revision :: !Text
  }
  deriving stock (Eq, Ord, Show, Generic)

-- | What is known about one application's contribution.
data ApplicationEvidence
  = -- | Every operation the application compiles to, in plan order, and the
    --   instances that were compiled from a fetched release (empty when all
    --   of them were installed).
    EvidenceOperations ![Operation] ![EvidenceSource]
  | -- | The application could not be compiled from its recorded state.
    EvidenceUnavailable !Text
  deriving stock (Eq, Show, Generic)

-- | Why a path in scope stayed unknown.
data CertificationGap
  = -- | The owner is not among the manifest's recorded applications.
    OwnerNotRecorded !ApplicationId
  | -- | The owner is recorded but its operations could not be obtained.
    OwnerEvidenceUnavailable !ApplicationId !Text
  | -- | The owner's operations no longer write this path, so what they say
    -- is not evidence about how the path was written.
    OwnerEmitsNoOperation !ApplicationId
  deriving stock (Eq, Show, Generic)

-- | The outcome for one path in scope.
data SharedWriteCertificationEntry = SharedWriteCertificationEntry
  { path :: !FilePath,
    owners :: !(Set ApplicationId),
    previousMode :: !SharedWriteMode,
    certifiedMode :: !SharedWriteMode,
    -- | Empty exactly when 'certifiedMode' is known.
    gaps :: ![CertificationGap]
  }
  deriving stock (Eq, Show, Generic)

-- | The manifest with every certified mode applied, and one entry per path
-- in scope. The manifest's version is not changed; the caller decides what
-- schema to publish it as.
data SharedWriteCertification = SharedWriteCertification
  { manifest :: !Manifest,
    entries :: ![SharedWriteCertificationEntry],
    -- | Every fetched release the evidence was compiled from.
    fetchedSources :: ![EvidenceSource]
  }
  deriving stock (Eq, Show, Generic)

-- | The unknown paths a scope covers, with their records, in path order.
pathsInScope :: CertificationScope -> Manifest -> [(FilePath, FileRecord)]
pathsInScope scope manifest =
  [ (path, record)
  | (path, record) <- Map.toAscList (manifest ^. #files),
    record ^. #sharedWriteMode == SharedWriteUnknown,
    -- A path nobody owns is outside every ownership check, so its mode
    -- decides nothing.
    not (Set.null (record ^. #applicationIds)),
    inScope (record ^. #applicationIds)
  ]
  where
    inScope owners = case scope of
      CertifyAllUnknownPaths -> True
      CertifyPathsForApplications selected ->
        not (Set.null (Set.intersection selected owners))
          && not (owners `Set.isSubsetOf` selected)

-- | Classify every path in scope from the owners' operations.
--
-- Pure, so the whole decision can be tested with small fixtures. Only
-- 'SharedWriteUnknown' records are ever changed, so a known answer —
-- in particular a closure requirement — is never overwritten here.
certifySharedWriteModes ::
  CertificationScope ->
  Manifest ->
  Map ApplicationId ApplicationEvidence ->
  SharedWriteCertification
certifySharedWriteModes scope manifest evidence =
  SharedWriteCertification
    { manifest = manifest & #files %~ \files -> foldl' applyEntry files entries,
      entries = entries,
      fetchedSources = nubOrd (concat [sources | EvidenceOperations _ sources <- Map.elems evidence])
    }
  where
    recorded = Set.fromList (map (^. #applicationId) (manifest ^. #applications))
    entries = map (uncurry classify) (pathsInScope scope manifest)

    applyEntry files entry
      | entry ^. #certifiedMode == SharedWriteUnknown = files
      | otherwise = Map.adjust (& #sharedWriteMode .~ (entry ^. #certifiedMode)) (entry ^. #path) files

    classify path record =
      let owners = record ^. #applicationIds
          perOwner = map (ownerContribution path) (Set.toAscList owners)
          missing = [gap | Left gap <- perOwner]
          -- One owner that writes the path other than additively settles the
          -- conjunction on its own, whatever the missing owners do.
          anyWholeFile = or [not (all isAdditiveOperation operations) | Right operations <- perOwner]
          (mode, gaps)
            | anyWholeFile = (SharedWriteRequiresOwnershipClosure, [])
            | not (null missing) = (SharedWriteUnknown, missing)
            | otherwise = (SharedWriteAdditiveOnly, [])
       in SharedWriteCertificationEntry
            { path = path,
              owners = owners,
              previousMode = record ^. #sharedWriteMode,
              certifiedMode = mode,
              gaps = gaps
            }

    ownerContribution path owner
      | Set.notMember owner recorded = Left (OwnerNotRecorded owner)
      | otherwise = case Map.lookup owner evidence of
          Nothing -> Left (OwnerEvidenceUnavailable owner "its operations were not compiled")
          Just (EvidenceUnavailable reason) -> Left (OwnerEvidenceUnavailable owner reason)
          Just (EvidenceOperations operations _) ->
            case filter ((== Just path) . operationDestination) operations of
              [] -> Left (OwnerEmitsNoOperation owner)
              writes -> Right writes

-- | The entries whose mode actually changed.
certifiedChanges :: SharedWriteCertification -> [SharedWriteCertificationEntry]
certifiedChanges certification =
  [ entry
  | entry <- certification ^. #entries,
    entry ^. #certifiedMode /= entry ^. #previousMode
  ]

operationDestination :: Operation -> Maybe FilePath
operationDestination (WriteFileOp path _ _) = Just path
operationDestination (CopyFileOp _ path) = Just path
operationDestination (PatchFileOp path _ _ _ _) = Just path
operationDestination CreateDirOp {} = Nothing
operationDestination RunCommandOp {} = Nothing

-- | Compile the named recorded applications from exactly what the manifest
-- records about them.
--
-- For each instance the recorded origin is resolved through @searchPaths@,
-- and the copy found must have the same identity and the /same/ declared
-- version as recorded: a newer local copy would describe how the module
-- writes today, not how it wrote the project, so it is refused rather than
-- used. Under 'FetchRecordedReleases', an instance with no such installed
-- copy is read instead from the commit of its recorded remote that declares
-- the recorded version ("Seihou.CLI.RecordedRelease"); no other version is
-- ever substituted. The instances are compiled in their recorded order with
-- their recorded parent variables and resolved values; nothing is prompted
-- for and no configuration or environment value is consulted.
gatherApplicationEvidence ::
  EvidencePolicy ->
  FilePath ->
  [FilePath] ->
  Manifest ->
  Set ApplicationId ->
  IO (Map ApplicationId ApplicationEvidence)
gatherApplicationEvidence policy projectRoot searchPaths manifest wanted =
  Map.fromList
    <$> traverse
      (\application -> (application ^. #applicationId,) <$> compileRecorded application)
      [ application
      | application <- manifest ^. #applications,
        Set.member (application ^. #applicationId) wanted
      ]
  where
    compileRecorded application = do
      loaded <- traverse loadInstance (application ^. #instances)
      case sequence loaded of
        Left reason -> pure (EvidenceUnavailable reason)
        Right loadedInOrder
          | null loadedInOrder -> pure (EvidenceUnavailable "it records no module instances")
          | otherwise -> do
              let modulesInOrder = map fst loadedInOrder
                  sources = [source | (_, Just source) <- loadedInOrder]
                  saved =
                    Map.fromList
                      [ (instanceId, state ^. #resolvedVars)
                      | ((instanceId, _, _), state) <- zip modulesInOrder (application ^. #instances)
                      ]
              resolved <-
                runEff $
                  runConsole $
                    resolveWithPromptPermission
                      PromptsForbidden
                      modulesInOrder
                      saved
                      Map.empty
                      Map.empty
                      (fromMaybeText (application ^. #namespace))
                      (fromMaybeText (application ^. #context))
                      Map.empty
                      Map.empty
                      Map.empty
                      Map.empty
              case resolved of
                Left errors ->
                  pure (EvidenceUnavailable ("its recorded values no longer resolve: " <> T.pack (show errors)))
                Right values -> do
                  compiled <-
                    compileComposedPlan
                      [ (instanceId, modul, directory, Map.map (^. #value) (Map.findWithDefault Map.empty instanceId values))
                      | (instanceId, modul, directory) <- modulesInOrder
                      ]
                  pure $ case compiled of
                    Left errors -> EvidenceUnavailable ("it no longer compiles: " <> T.intercalate "; " errors)
                    Right (operations, _, _) -> EvidenceOperations operations sources

    loadInstance state = do
      installed <- loadInstalled state
      case installed of
        Right loaded -> pure (Right (loaded, Nothing))
        Left (reason, noted) -> do
          fetched <- case policy of
            InstalledReleasesOnly -> pure (Left Nothing)
            FetchRecordedReleases session -> first Just <$> loadFetched session state
          let recordedOrigin = state ^. #origin
              attachNote text
                | noted = withLocalOriginNote recordedOrigin text
                | otherwise = text
          pure $ case fetched of
            Right loaded -> Right loaded
            Left Nothing -> Left (attachNote reason)
            Left (Just fetchReason) -> Left (attachNote (reason <> "; " <> fetchReason))

    -- The installed copy, or why it cannot be used and whether the
    -- machine-local origin note explains that.
    loadInstalled state = do
      let name = state ^. #name
          recordedOrigin = state ^. #origin
          recordedVersion = state ^. #moduleVersion
      located <- resolveArtifactOrigin projectRoot searchPaths "module.dhall" recordedOrigin
      case located of
        Left _ ->
          pure
            ( Left
                ( "module "
                    <> name ^. #unModuleName
                    <> maybe "" (" " <>) recordedVersion
                    <> " is not installed here",
                  True
                )
            )
        Right directory -> do
          localOrigin <- detectArtifactOrigin projectRoot directory
          evaluated <- evalModuleFromFile (directory </> "module.dhall")
          pure $ case evaluated of
            Left _ -> Left ("module " <> name ^. #unModuleName <> " installed here does not evaluate", False)
            Right modul -> case judgeArtifact recordedOrigin recordedVersion localOrigin (modul ^. #version) of
              ArtifactOriginMismatch _ _ ->
                Left ("module " <> name ^. #unModuleName <> " is installed here from a different origin than recorded", True)
              _
                | modul ^. #version /= recordedVersion ->
                    Left
                      ( "module "
                          <> name ^. #unModuleName
                          <> " is "
                          <> describeVersion (modul ^. #version)
                          <> " here but the manifest records "
                          <> describeVersion recordedVersion,
                        False
                      )
                | otherwise -> Right (ModuleInstance name (state ^. #parentVars), modul, directory)

    -- The exact recorded release from the recorded remote, or why not.
    loadFetched session state = do
      let name = state ^. #name
      case (state ^. #origin, state ^. #moduleVersion) of
        (RemoteOrigin url _ _, Just recordedVersion) -> do
          unreachable <- isUnreachablePath url
          if unreachable
            then pure (Left ("its recorded origin " <> url <> " is a path on another machine"))
            else do
              located <- locateRecordedRelease session url (name ^. #unModuleName) "module.dhall" recordedVersion
              case located of
                Left err -> pure (Left (renderRecordedReleaseError err))
                Right release -> do
                  let directory = release ^. #directory
                  evaluated <- evalModuleFromFile (directory </> "module.dhall")
                  pure $ case evaluated of
                    Right modul
                      | modul ^. #version == Just recordedVersion ->
                          Right
                            ( (ModuleInstance name (state ^. #parentVars), modul, directory),
                              Just
                                EvidenceSource
                                  { moduleName = name,
                                    version = recordedVersion,
                                    originUrl = url,
                                    revision = release ^. #revision
                                  }
                            )
                    _ -> Left ("the release of " <> name ^. #unModuleName <> " fetched from " <> url <> " does not evaluate to the recorded version")
        (RemoteOrigin {}, Nothing) -> pure (Left "it records no version to fetch")
        _ -> pure (Left "its recorded origin names no remote to fetch from")

    -- A recorded path that does not exist here cannot be cloned; one that
    -- does exist is cloned like any other remote.
    isUnreachablePath url
      | isMachineLocalOriginUrl url = not <$> doesPathExist (T.unpack (fromMaybe url (T.stripPrefix "file://" url)))
      | otherwise = pure False

    fromMaybeText = fromMaybe ""
    describeVersion = maybe "unversioned" ("version " <>)

    -- A path recorded as the origin is why the installed copy cannot be
    -- matched, and installing the recorded version will not fix that.
    withLocalOriginNote recordedOrigin reason = case machineLocalOriginNote recordedOrigin of
      Just note -> reason <> ". " <> note
      Nothing -> reason

-- | Certify a scope, compiling every owner the scope needs except those the
-- caller already supplies operations for. A targeted update supplies the
-- candidate operations of the applications it is about to apply, because
-- that is the contribution the update will actually write.
certifySharedWriteModesIO ::
  EvidencePolicy ->
  FilePath ->
  [FilePath] ->
  CertificationScope ->
  Manifest ->
  Map ApplicationId [Operation] ->
  IO SharedWriteCertification
certifySharedWriteModesIO policy projectRoot searchPaths scope manifest supplied = do
  let needed =
        Set.unions [record ^. #applicationIds | (_, record) <- pathsInScope scope manifest]
          Set.\\ Map.keysSet supplied
  gathered <- gatherApplicationEvidence policy projectRoot searchPaths manifest needed
  let evidence = Map.union (Map.map (`EvidenceOperations` []) supplied) gathered
  pure (certifySharedWriteModes scope manifest evidence)

-- | One line explaining a gap, naming the application by its target.
renderCertificationGap :: Manifest -> CertificationGap -> Text
renderCertificationGap manifest gap = case gap of
  OwnerNotRecorded owner -> label owner <> " owns the path but is not a recorded application"
  OwnerEvidenceUnavailable owner reason -> label owner <> ": " <> reason
  OwnerEmitsNoOperation owner -> label owner <> " no longer writes this path"
  where
    label owner =
      maybe
        (owner ^. #unApplicationId)
        targetLabel
        (find ((== owner) . (^. #applicationId)) (manifest ^. #applications))
    targetLabel application = case application ^. #target of
      AppliedModuleTarget name -> name ^. #unModuleName
      AppliedRecipeTarget name -> name ^. #unRecipeName

-- | How a fetched release is named in a report, for example
-- @nix-haskell-flake 0.13.2 read from https:\/\/github.com\/o\/r.git at 08191d3@.
renderEvidenceSource :: EvidenceSource -> Text
renderEvidenceSource source =
  source ^. #moduleName . #unModuleName
    <> " "
    <> source ^. #version
    <> " read from "
    <> source ^. #originUrl
    <> " at "
    <> source ^. #revision
