module Seihou.CLI.ManifestCapabilityUpgradeSpec (tests) where

import Control.Exception (bracket)
import Control.Lens ((&), (.~), (^.))
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Seihou.CLI.ManifestCapabilityUpgrade
import Seihou.CLI.ManifestUpgrade (ManifestUpgradeOpts (..), UpgradeOutcome (..), runManifestUpgrade)
import Seihou.CLI.UpdateSpec
  ( CoOwnerWriteMode (..),
    SharedPathFixture (..),
    installBetaVersion,
    prepareSharedPathFixture,
    publishBetaReleases,
  )
import Seihou.Core.Types
import Seihou.Manifest.Hash (hashContent)
import Seihou.Manifest.Types (emptyManifest, manifestFromJSON)
import System.Directory (doesFileExist, removeDirectoryRecursive, withCurrentDirectory)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.ManifestCapabilityUpgrade" spec

testTime :: UTCTime
testTime = parseTimeOrError True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" "2026-07-19T00:00:00Z"

appA, appB, appC :: ApplicationId
appA = ApplicationId "a"
appB = ApplicationId "b"
appC = ApplicationId "c"

recordedApplication :: ApplicationId -> AppliedComposition
recordedApplication applicationId =
  AppliedComposition
    { applicationId,
      target = AppliedModuleTarget (ModuleName (applicationId ^. #unApplicationId)),
      targetOrigin = LocalOrigin (applicationId ^. #unApplicationId),
      targetVersion = Just "1.0.0",
      additionalModules = [],
      namespace = Nothing,
      context = Nothing,
      instances = [],
      commandReceipts = Map.empty,
      appliedAt = testTime
    }

record :: [ApplicationId] -> SharedWriteMode -> FileRecord
record owners mode =
  FileRecord (hashContent "x") "m" Template testTime Nothing (Set.fromList owners) mode

-- | A manifest whose paths cover every classification the pure certifier
-- makes. Applications a and b are recorded; c owns a path but is recorded
-- too, so only its evidence is missing; d is not recorded at all.
fixtureManifest :: Manifest
fixtureManifest =
  emptyManifest testTime
    & #applications .~ map recordedApplication [appA, appB, appC]
    & #files
      .~ Map.fromList
        [ (".gitignore", record [appA, appB] SharedWriteUnknown),
          ("flake.nix", record [appA, appB] SharedWriteUnknown),
          ("shared.txt", record [appA, appC] SharedWriteUnknown),
          ("wholefile.txt", record [appB, appC] SharedWriteUnknown),
          ("gone.txt", record [appA, appB] SharedWriteUnknown),
          ("stranger.txt", record [appA, ApplicationId "d"] SharedWriteUnknown),
          ("solo.txt", record [appA] SharedWriteUnknown),
          ("closed.txt", record [appA, appB] SharedWriteRequiresOwnershipClosure),
          ("orphan.txt", record [] SharedWriteUnknown)
        ]

append :: FilePath -> Operation
append path = PatchFileOp path "line\n" AppendLineIfAbsent Template "m"

evidence :: Map.Map ApplicationId ApplicationEvidence
evidence =
  Map.fromList
    [ ( appA,
        EvidenceOperations
          (map append [".gitignore", "flake.nix", "shared.txt", "gone.txt", "stranger.txt", "solo.txt", "closed.txt"])
          []
      ),
      ( appB,
        EvidenceOperations
          [ PatchFileOp ".gitignore" "/dist\n" AppendSection Template "m",
            WriteFileOp "flake.nix" "{}" DhallText,
            WriteFileOp "wholefile.txt" "all" Template,
            append "closed.txt"
          ]
          []
      ),
      (appC, EvidenceUnavailable "c is not installed here")
    ]

entryFor :: FilePath -> SharedWriteCertification -> Maybe SharedWriteCertificationEntry
entryFor path certification = lookup path [(entry ^. #path, entry) | entry <- certification ^. #entries]

modeIn :: FilePath -> SharedWriteCertification -> Maybe SharedWriteMode
modeIn path certification = (^. #sharedWriteMode) <$> Map.lookup path (certification ^. #manifest . #files)

spec :: Spec
spec = do
  describe "certifySharedWriteModes" $ do
    let everything = certifySharedWriteModes CertifyAllUnknownPaths fixtureManifest evidence

    it "certifies a path every owner appends to as additive-only" $
      modeIn ".gitignore" everything `shouldBe` Just SharedWriteAdditiveOnly

    it "certifies a path one owner writes wholesale as closure-required" $
      modeIn "flake.nix" everything `shouldBe` Just SharedWriteRequiresOwnershipClosure

    it "leaves a path unknown when one owner's evidence is missing" $ do
      modeIn "shared.txt" everything `shouldBe` Just SharedWriteUnknown
      (^. #gaps) <$> entryFor "shared.txt" everything
        `shouldBe` Just [OwnerEvidenceUnavailable appC "c is not installed here"]

    it "proves a closure requirement from one whole-file owner even when another is missing" $
      modeIn "wholefile.txt" everything `shouldBe` Just SharedWriteRequiresOwnershipClosure

    it "leaves a path unknown when an owner no longer writes it" $ do
      modeIn "gone.txt" everything `shouldBe` Just SharedWriteUnknown
      (^. #gaps) <$> entryFor "gone.txt" everything `shouldBe` Just [OwnerEmitsNoOperation appB]

    it "leaves a path unknown when an owner is not a recorded application" $
      (^. #gaps) <$> entryFor "stranger.txt" everything
        `shouldBe` Just [OwnerNotRecorded (ApplicationId "d")]

    it "never revisits a known mode" $ do
      modeIn "closed.txt" everything `shouldBe` Just SharedWriteRequiresOwnershipClosure
      entryFor "closed.txt" everything `shouldBe` Nothing

    it "ignores a path with no owners, which no ownership check consults" $ do
      entryFor "orphan.txt" everything `shouldBe` Nothing
      modeIn "orphan.txt" everything `shouldBe` Just SharedWriteUnknown

    it "does not change the manifest's version or anything but the modes" $ do
      (everything ^. #manifest . #version) `shouldBe` (fixtureManifest ^. #version)
      (everything ^. #manifest & #files .~ Map.empty) `shouldBe` (fixtureManifest & #files .~ Map.empty)

    it "scopes a targeted certification to paths the selection shares with others" $ do
      let targeted = certifySharedWriteModes (CertifyPathsForApplications (Set.singleton appA)) fixtureManifest evidence
          scoped = map (^. #path) (targeted ^. #entries)
      scoped `shouldContain` [".gitignore"]
      scoped `shouldNotContain` ["solo.txt"]
      scoped `shouldNotContain` ["wholefile.txt"]
      modeIn "wholefile.txt" targeted `shouldBe` Just SharedWriteUnknown
      modeIn "solo.txt" targeted `shouldBe` Just SharedWriteUnknown

  describe "certifySharedWriteModesIO" $ do
    it "certifies a schema-6 shared .gitignore from the recorded owners' installed modules" $
      withSharedFixture CoOwnerAppendsUnrecorded $ \fixture manifest -> do
        before <- TIO.readFile (fixture ^. #gitignorePath)
        certification <- certify fixture manifest
        modeIn ".gitignore" certification `shouldBe` Just SharedWriteAdditiveOnly
        TIO.readFile (fixture ^. #gitignorePath) `shouldReturn` before

    it "certifies a co-owner that writes the whole file as closure-required" $
      withSharedFixture CoOwnerWritesWholeFile $ \fixture manifest -> do
        let unknown = manifest & #files .~ Map.map (& #sharedWriteMode .~ SharedWriteUnknown) (manifest ^. #files)
        certification <- certify fixture unknown
        modeIn ".gitignore" certification `shouldBe` Just SharedWriteRequiresOwnershipClosure

    it "refuses an installed module whose version differs from the recorded one" $
      withSharedFixture CoOwnerAppendsUnrecorded $ \fixture manifest -> do
        let betaModule = installedRoot fixture </> "beta" </> "module.dhall"
        TIO.readFile betaModule >>= TIO.writeFile betaModule . T.replace "Some \"1.0.0\"" "Some \"1.1.0\""
        certification <- certify fixture manifest
        modeIn ".gitignore" certification `shouldBe` Just SharedWriteUnknown
        case (^. #gaps) <$> entryFor ".gitignore" certification of
          Just [OwnerEvidenceUnavailable owner reason] -> do
            owner `shouldBe` (fixture ^. #betaApplicationId)
            reason `shouldSatisfy` T.isInfixOf "version 1.1.0 here but the manifest records version 1.0.0"
          other -> expectationFailure ("expected one version gap, got " <> show other)

    it "certifies from the recorded release in the recorded remote once the cache has moved on" $
      withSharedFixture CoOwnerAppendsUnrecorded $ \fixture manifest -> do
        _ <- publishBetaReleases fixture ["1.0.0", "1.1.0"]
        installBetaVersion fixture "1.1.0"
        installedBefore <- TIO.readFile (fixture ^. #betaInstalledPath </> "module.dhall")
        installedOnly <- certify fixture manifest
        modeIn ".gitignore" installedOnly `shouldBe` Just SharedWriteUnknown
        (installedOnly ^. #fetchedSources) `shouldBe` []
        withSystemTempDirectory "seihou-certify-session" $ \session -> do
          fetched <- certifyWith (FetchRecordedReleases session) fixture manifest
          modeIn ".gitignore" fetched `shouldBe` Just SharedWriteAdditiveOnly
          [(source ^. #moduleName, source ^. #version) | source <- fetched ^. #fetchedSources]
            `shouldBe` [("beta", "1.0.0")]
        -- The cache is exactly as it was: nothing was swapped in.
        TIO.readFile (fixture ^. #betaInstalledPath </> "module.dhall") `shouldReturn` installedBefore

    it "keeps the gap, naming what was searched, when no commit declares the recorded version" $
      withSharedFixture CoOwnerAppendsUnrecorded $ \fixture manifest -> do
        _ <- publishBetaReleases fixture ["1.1.0"]
        installBetaVersion fixture "1.1.0"
        withSystemTempDirectory "seihou-certify-session" $ \session -> do
          certification <- certifyWith (FetchRecordedReleases session) fixture manifest
          modeIn ".gitignore" certification `shouldBe` Just SharedWriteUnknown
          case (^. #gaps) <$> entryFor ".gitignore" certification of
            Just [OwnerEvidenceUnavailable _ reason] -> do
              reason `shouldSatisfy` T.isInfixOf "version 1.1.0 here but the manifest records version 1.0.0"
              reason `shouldSatisfy` T.isInfixOf "no commit of"
              reason `shouldSatisfy` T.isInfixOf "declares beta 1.0.0"
            other -> expectationFailure ("expected one gap, got " <> show other)

    it "leaves the path unknown when a recorded owner is not installed" $
      withSharedFixture CoOwnerAppendsUnrecorded $ \fixture manifest -> do
        removeDirectoryRecursive (installedRoot fixture </> "beta")
        certification <- certify fixture manifest
        modeIn ".gitignore" certification `shouldBe` Just SharedWriteUnknown

    it "compiles without executing a module's commands" $
      withSharedFixture CoOwnerAppendsUnrecorded $ \fixture manifest -> do
        let alphaModule = installedRoot fixture </> "alpha" </> "module.dhall"
            marker = fixture ^. #projectRoot </> "command-ran"
        TIO.readFile alphaModule
          >>= TIO.writeFile alphaModule
            . T.replace
              ", commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }"
              (", commands = [{ run = \"touch " <> T.pack marker <> "\", workDir = None Text, when = None Text }]")
        certification <- certify fixture manifest
        modeIn ".gitignore" certification `shouldBe` Just SharedWriteAdditiveOnly
        doesFileExist marker `shouldReturn` False

    it "compiles with the recorded resolved values and nothing else" $
      withSharedFixture CoOwnerAppendsUnrecorded $ \fixture manifest -> do
        -- Alpha now needs a value with no default. Only the manifest's saved
        -- value can supply it; no prompt, configuration, or environment is read.
        let alphaModule = installedRoot fixture </> "alpha" </> "module.dhall"
        TIO.readFile alphaModule
          >>= TIO.writeFile alphaModule
            . T.replace
              ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }"
              ", vars = [{ name = \"project.name\", type = \"text\", default = None Text, description = None Text, required = True, validation = None Text }]"
        let withSaved value =
              manifest
                & #applications
                  .~ [ if application ^. #applicationId == fixture ^. #alphaApplicationId
                         then application & #instances .~ map (& #resolvedVars .~ value) (application ^. #instances)
                         else application
                     | application <- manifest ^. #applications
                     ]
        saved <- certify fixture (withSaved (Map.singleton "project.name" "demo"))
        modeIn ".gitignore" saved `shouldBe` Just SharedWriteAdditiveOnly
        unsaved <- certify fixture (withSaved Map.empty)
        modeIn ".gitignore" unsaved `shouldBe` Just SharedWriteUnknown

  describe "seihou manifest upgrade" $
    it "upgrades a schema-6 manifest to 7 and records the certified mode, touching only the manifest" $
      withSharedFixture CoOwnerAppendsUnrecorded $ \fixture _ -> do
        gitignoreBefore <- TIO.readFile (fixture ^. #gitignorePath)
        outcome <-
          withEnv "XDG_CONFIG_HOME" (fixture ^. #xdgHome) $
            withCurrentDirectory (fixture ^. #projectRoot) $
              runManifestUpgrade (ManifestUpgradeOpts False False Nothing)
        case outcome of
          UpgradeWritten _ -> pure ()
          other -> expectationFailure ("expected a write, got " <> show other)
        written <- LBS.readFile (fixture ^. #manifestPath)
        case manifestFromJSON written of
          Left err -> expectationFailure err
          Right upgraded -> do
            (upgraded ^. #version) `shouldBe` ManifestSchemaVersion 7
            (^. #sharedWriteMode) <$> Map.lookup ".gitignore" (upgraded ^. #files)
              `shouldBe` Just SharedWriteAdditiveOnly
        TIO.readFile (fixture ^. #gitignorePath) `shouldReturn` gitignoreBefore
  where
    installedRoot fixture = fixture ^. #xdgHome </> "seihou" </> "installed"
    certify = certifyWith InstalledReleasesOnly
    certifyWith policy fixture manifest =
      certifySharedWriteModesIO
        policy
        (fixture ^. #projectRoot)
        [installedRoot fixture]
        CertifyAllUnknownPaths
        manifest
        Map.empty

-- | Build the shared-path fixture and hand over the manifest it wrote.
withSharedFixture :: CoOwnerWriteMode -> (SharedPathFixture -> Manifest -> IO a) -> IO a
withSharedFixture mode action =
  withSystemTempDirectory "seihou-certify" $ \root -> do
    fixture <- prepareSharedPathFixture mode root
    bytes <- LBS.readFile (fixture ^. #manifestPath)
    case manifestFromJSON bytes of
      Left err -> fail err
      Right manifest -> action fixture manifest

withEnv :: String -> String -> IO a -> IO a
withEnv key value inner =
  bracket (lookupEnv key <* setEnv key value) (maybe (unsetEnv key) (setEnv key)) (const inner)
