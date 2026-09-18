module Seihou.CLI.UpgradeDiagnosisSpec (tests) where

import Control.Exception (bracket)
import Control.Lens ((&), (.~), (^.))
import Control.Monad (forM_)
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.ManifestRepairOrigins (overManifestOrigins)
import Seihou.CLI.UpdateSpec (CoOwnerWriteMode (..), SharedPathFixture (..))
import Seihou.CLI.UpgradeDiagnosis
import Seihou.CLI.UpgradeFixture (portableEnvironment, preparePortableFixture, snapshotTree)
import Seihou.Core.Types (ArtifactOrigin (..), ManifestSchemaVersion (..))
import Seihou.Manifest.Types (manifestFromJSON, manifestToJSON)
import System.Directory (createDirectoryIfMissing, removeFile, renameDirectory)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.UpgradeDiagnosis" spec

spec :: Spec
spec = do
  describe "diagnoseUpgrade" $ do
    it "finds a healthy project ready" $
      withFixture CoOwnerAppends noDamage $ \_ fixture diagnose -> do
        diagnosis <- diagnose "alpha"
        let checks = readiness diagnosis
        [(check ^. #name, check ^. #status) | check <- checks, check ^. #status /= Ready] `shouldBe` []
        isReady checks `shouldBe` True
        statusOf "update-plans-cleanly" checks `shouldBe` Ready
        detailOf "update-plans-cleanly" checks `shouldSatisfy` T.isInfixOf "alpha 1.0.0 -> 2.0.0"
        detailOf "target-recorded" checks `shouldBe` "alpha"
        fixture ^. #projectRoot `shouldBe` (diagnosis ^. #projectRoot)

    it "reports a schema-6 manifest and its unknown shared path, while the update certifies it" $
      withFixture CoOwnerAppendsPredatingEvidence noDamage $ \_ _ diagnose -> do
        checks <- readiness <$> diagnose "alpha"
        statusOf "manifest-schema-current" checks `shouldBe` NeedsAttention
        detailOf "manifest-schema-current" checks `shouldSatisfy` T.isInfixOf "schema 6 is older than 7"
        statusOf "shared-evidence-known" checks `shouldBe` NeedsAttention
        detailOf "shared-evidence-known" checks `shouldBe` ".gitignore is shared with beta and its write mode is unknown"
        statusOf "update-plans-cleanly" checks `shouldBe` Ready
        statusOf "manifest-readable" checks `shouldBe` Ready
        isReady checks `shouldBe` False

    it "reports unavailable co-owner evidence with the update's error code" $
      withFixture CoOwnerAppendsPredatingEvidence evidenceUnavailable $ \_ _ diagnose -> do
        diagnosis <- diagnose "alpha"
        let checks = readiness diagnosis
        statusOf "update-plans-cleanly" checks `shouldBe` NeedsAttention
        detailOf "update-plans-cleanly" checks `shouldSatisfy` T.isInfixOf "[shared_write_evidence_unavailable]"
        ((^. #errorCode) <$> diagnosis ^. #updateDryRun) `shouldBe` ProbeOk (Just "shared_write_evidence_unavailable")

    it "reports a schema-5 manifest as needing seihou manifest upgrade" $
      withFixture CoOwnerAppends (withManifestText (T.replace "\"version\":7" "\"version\":5")) $ \_ _ diagnose -> do
        diagnosis <- diagnose "alpha"
        let checks = readiness diagnosis
        statusOf "manifest-readable" checks `shouldBe` NeedsAttention
        detailOf "manifest-readable" checks `shouldSatisfy` T.isInfixOf "seihou manifest upgrade"
        detailOf "manifest-schema-current" checks `shouldSatisfy` T.isInfixOf "schema 5"
        diagnosis ^. #manifestUpgrade `shouldSatisfy` \case
          ProbeOk _ -> True
          _ -> False
        lookup "manifest_upgrade_section" (briefSections diagnosis []) `shouldSatisfy` maybe False (T.isInfixOf "seihou manifest upgrade --dry-run")

    it "turns a missing manifest into a finding, not an exception" $
      withFixture CoOwnerAppends (\fixture -> removeFile (fixture ^. #manifestPath)) $ \_ _ diagnose -> do
        diagnosis <- diagnose "alpha"
        let checks = readiness diagnosis
        statusOf "manifest-readable" checks `shouldBe` NeedsAttention
        detailOf "manifest-readable" checks `shouldSatisfy` T.isInfixOf "does not exist"
        isReady checks `shouldBe` False
        renderReadinessReport "alpha" checks `shouldSatisfy` T.isSuffixOf "Upgrade readiness: not ready (7 checks need attention)\n"

    it "turns a manifest that is not JSON into a finding" $
      withFixture CoOwnerAppends (withManifestText (const "{not json")) $ \_ _ diagnose -> do
        checks <- readiness <$> diagnose "alpha"
        statusOf "manifest-readable" checks `shouldBe` NeedsAttention
        detailOf "manifest-readable" checks `shouldSatisfy` T.isInfixOf "not valid JSON"

    it "names a co-owner whose recorded origin is a machine-local path" $
      withFixture CoOwnerAppends localBetaOrigin $ \_ _ diagnose -> do
        checks <- readiness <$> diagnose "alpha"
        statusOf "origins-portable" checks `shouldBe` NeedsAttention
        detailOf "origins-portable" checks `shouldSatisfy` T.isInfixOf "/nonexistent/seihou-modules is recorded for beta"
        detailOf "origins-portable" checks `shouldSatisfy` T.isInfixOf "seihou manifest repair-origins"

    it "lists the recorded targets for an unknown one" $
      withFixture CoOwnerAppends noDamage $ \_ _ diagnose -> do
        diagnosis <- diagnose "nope"
        let checks = readiness diagnosis
        statusOf "target-recorded" checks `shouldBe` NeedsAttention
        detailOf "target-recorded" checks `shouldBe` "nope is not a recorded target; recorded targets: alpha, beta"
        statusOf "update-plans-cleanly" checks `shouldBe` NeedsAttention
        detailOf "update-plans-cleanly" checks `shouldSatisfy` T.isInfixOf "[target_not_found]"

    it "skips the update probe while an interrupted update waits" $
      withFixture CoOwnerAppends pendingTransaction $ \_ _ diagnose -> do
        diagnosis <- diagnose "alpha"
        let checks = readiness diagnosis
        statusOf "no-interrupted-update" checks `shouldBe` NeedsAttention
        statusOf "update-plans-cleanly" checks `shouldBe` CouldNotDetermine
        diagnosis ^. #updateDryRun `shouldSatisfy` \case
          ProbeSkipped reason -> "interrupted update" `T.isInfixOf` reason
          _ -> False

    it "writes nothing in any fixture" $
      forM_ fixtures $ \(label, mode, damage) ->
        withFixture mode damage $ \root fixture diagnose -> do
          let trees = [fixture ^. #projectRoot, fixture ^. #xdgHome]
          before <- traverse snapshotTree trees
          _ <- diagnose "alpha"
          _ <- diagnose "nope"
          after <- traverse snapshotTree trees
          (label, after) `shouldBe` (label, before)
          root `shouldSatisfy` (not . null)

  describe "renderReadinessReport" $ do
    it "ends in the exact verdict line, counting checks that could not be determined" $ do
      let checks =
            [ ReadinessCheck "manifest-readable" Ready "fine",
              ReadinessCheck "update-plans-cleanly" CouldNotDetermine "did not finish within 180 seconds"
            ]
      renderReadinessReport "alpha" checks
        `shouldBe` T.unlines
          [ "Upgrade readiness for alpha",
            "  ✓ manifest-readable     fine",
            "  ? update-plans-cleanly  did not finish within 180 seconds",
            "Upgrade readiness: not ready (1 check needs attention)"
          ]
      renderReadinessReport "alpha" (take 1 checks) `shouldSatisfy` T.isSuffixOf "Upgrade readiness: ready\n"

  describe "briefSections" $ do
    it "names applications by label and reports caller findings" $
      withFixture CoOwnerAppendsPredatingEvidence noDamage $ \_ _ diagnose -> do
        diagnosis <- diagnose "alpha"
        let sections = briefSections diagnosis ["agent configuration: fell back to claude-cli"]
            everything = T.concat (map snd sections)
        lookup "findings_section" sections `shouldSatisfy` maybe False (T.isInfixOf "fell back to claude-cli")
        lookup "shared_evidence_section" sections `shouldSatisfy` maybe False (T.isInfixOf "`.gitignore`: also owned by beta")
        lookup "manifest_section" sections `shouldSatisfy` maybe False (T.isInfixOf "schema 6")
        everything `shouldNotSatisfy` T.isInfixOf "ApplicationRef"
        everything `shouldNotSatisfy` T.isInfixOf "ModuleName"
        everything `shouldNotSatisfy` T.isInfixOf (diagnosisIdText diagnosis)
  where
    fixtures =
      [ ("healthy" :: Text, CoOwnerAppends, const (pure ())),
        ("schema 6", CoOwnerAppendsPredatingEvidence, const (pure ())),
        ("evidence unavailable", CoOwnerAppendsPredatingEvidence, evidenceUnavailable),
        ("schema 5", CoOwnerAppends, withManifestText (T.replace "\"version\":7" "\"version\":5")),
        ("not json", CoOwnerAppends, withManifestText (const "{not json")),
        ("local origin", CoOwnerAppends, localBetaOrigin),
        ("pending transaction", CoOwnerAppends, pendingTransaction)
      ]

-- | Build a portable fixture, damage it, and diagnose it with the fixture's
-- configuration and git URL mapping in the environment.
withFixture ::
  CoOwnerWriteMode ->
  (SharedPathFixture -> IO ()) ->
  (FilePath -> SharedPathFixture -> (Text -> IO UpgradeDiagnosis) -> IO a) ->
  IO a
withFixture mode damage action =
  withSystemTempDirectory "seihou-upgrade-diagnosis" $ \root -> do
    fixture <- preparePortableFixture mode root
    damage fixture
    withEnvironment (portableEnvironment root fixture) $ do
      env <- diagnosisEnvFor (fixture ^. #projectRoot)
      action root fixture (diagnoseUpgrade env)

-- | The fixture from "Seihou.CLI.UpdateE2ESpec": a schema-7 manifest that
-- still records the shared path as unknown, with beta's recorded release
-- neither installed nor published.
evidenceUnavailable :: SharedPathFixture -> IO ()
evidenceUnavailable fixture = do
  decoded <- manifestFromJSON <$> LBS.readFile (fixture ^. #manifestPath)
  manifest <- either fail pure decoded
  LBS.writeFile (fixture ^. #manifestPath) (manifestToJSON (manifest & #version .~ ManifestSchemaVersion 7))
  renameDirectory (fixture ^. #betaInstalledPath) (fixture ^. #betaInstalledPath <> "-parked")

localBetaOrigin :: SharedPathFixture -> IO ()
localBetaOrigin fixture = do
  decoded <- manifestFromJSON <$> LBS.readFile (fixture ^. #manifestPath)
  manifest <- either fail pure decoded
  let damage = \case
        RemoteOrigin _ "beta" _ -> RemoteOrigin "/nonexistent/seihou-modules" "beta" (Just "seihou-modules")
        other -> other
  LBS.writeFile (fixture ^. #manifestPath) (manifestToJSON (overManifestOrigins damage manifest))

pendingTransaction :: SharedPathFixture -> IO ()
pendingTransaction fixture = do
  let transaction = fixture ^. #projectRoot </> ".seihou" </> "transactions" </> "interrupted"
  createDirectoryIfMissing True transaction
  TIO.writeFile (transaction </> "journal.json") "{\"version\":1,\"entries\":[],\"newDirectories\":[]}"

withManifestText :: (Text -> Text) -> SharedPathFixture -> IO ()
withManifestText change fixture = do
  body <- TIO.readFile (fixture ^. #manifestPath)
  TIO.writeFile (fixture ^. #manifestPath) (change body)

statusOf :: Text -> [ReadinessCheck] -> ReadinessStatus
statusOf checkName checks = case [check ^. #status | check <- checks, check ^. #name == checkName] of
  status : _ -> status
  [] -> error ("no check named " <> T.unpack checkName)

detailOf :: Text -> [ReadinessCheck] -> Text
detailOf checkName checks = case [check ^. #detail | check <- checks, check ^. #name == checkName] of
  detail : _ -> detail
  [] -> error ("no check named " <> T.unpack checkName)

-- | Beta's full application id, which no rendering may show.
diagnosisIdText :: UpgradeDiagnosis -> Text
diagnosisIdText diagnosis = case diagnosis ^. #unknownSharedPaths of
  ProbeOk (shared : _) -> case shared ^. #otherOwners of
    owner : _ -> owner ^. #applicationId . #unApplicationId
    [] -> "no owner"
  _ -> "no shared path"

withEnvironment :: [(String, String)] -> IO a -> IO a
withEnvironment assignments action =
  bracket
    (traverse (\(key, value) -> (key,) <$> (lookupEnv key <* setEnv key value)) assignments)
    (traverse_' restore)
    (const action)
  where
    restore (key, Just previous) = setEnv key previous
    restore (key, Nothing) = unsetEnv key
    traverse_' f = mapM_ f

noDamage :: SharedPathFixture -> IO ()
noDamage _ = pure ()
