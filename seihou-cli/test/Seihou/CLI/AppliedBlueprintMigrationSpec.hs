module Seihou.CLI.AppliedBlueprintMigrationSpec (tests) where

import Control.Lens ((&), (.~), (^.))
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Seihou.CLI.AppliedBlueprintMigration (recordAppliedBlueprintMigration)
import Seihou.Core.Types
  ( AppliedBlueprintMigration (..),
    ArtifactOrigin (..),
    Manifest (..),
    MigrationOutcome (..),
    ModuleName (..),
  )
import Seihou.Manifest.Types (currentManifestVersion, manifestFromJSON)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.AppliedBlueprintMigration" spec

fixedTime :: UTCTime
fixedTime =
  parseTimeOrError True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" "2026-07-20T12:00:00Z"

fixedTime2 :: UTCTime
fixedTime2 =
  parseTimeOrError True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" "2026-07-20T13:00:00Z"

-- | The identity of the blueprint most cases here record receipts for.
repoOne :: ArtifactOrigin
repoOne = RemoteOrigin "https://github.com/acme/one" "payments" Nothing

-- | A different repository publishing a blueprint of the same name.
repoTwo :: ArtifactOrigin
repoTwo = RemoteOrigin "https://github.com/acme/two" "payments" Nothing

mkReceipt :: ArtifactOrigin -> T.Text -> T.Text -> T.Text -> UTCTime -> AppliedBlueprintMigration
mkReceipt origin blueprintName fromVersion toVersion appliedAt =
  mkReceiptWithOutcome origin blueprintName fromVersion toVersion appliedAt MigrationApplied

mkReceiptWithOutcome ::
  ArtifactOrigin ->
  T.Text ->
  T.Text ->
  T.Text ->
  UTCTime ->
  MigrationOutcome ->
  AppliedBlueprintMigration
mkReceiptWithOutcome origin blueprintName fromVersion toVersion appliedAt outcome =
  AppliedBlueprintMigration
    { name = ModuleName blueprintName,
      origin = origin,
      blueprintVersion = Just "0.4.0",
      fromVersion = fromVersion,
      toVersion = toVersion,
      outcome = outcome,
      appliedAt = appliedAt,
      agentSessionId = Nothing
    }

readManifestFile :: FilePath -> IO Manifest
readManifestFile path = do
  bytes <- LBS.readFile path
  case manifestFromJSON bytes of
    Right manifest -> pure manifest
    Left err -> error ("test fixture: malformed manifest: " <> err)

spec :: Spec
spec = do
  describe "recordAppliedBlueprintMigration" $ do
    it "creates a version-5 manifest for the first receipt" $
      withSystemTempDirectory "seihou-blueprint-migration" $ \dir -> do
        let manifestPath = dir </> ".seihou" </> "manifest.json"
            receipt = mkReceipt repoOne "payments" "1.0.0" "2.0.0" fixedTime
        result <- recordAppliedBlueprintMigration manifestPath receipt
        result `shouldBe` Right ()
        manifest <- readManifestFile manifestPath
        (manifest ^. #version) `shouldBe` currentManifestVersion
        (manifest ^. #blueprintMigrations) `shouldBe` [receipt]

    it "upserts the same exact edge and retains unrelated edges" $
      withSystemTempDirectory "seihou-blueprint-migration" $ \dir -> do
        let manifestPath = dir </> "manifest.json"
            first = mkReceipt repoOne "payments" "1.0.0" "2.0.0" fixedTime
            second = mkReceipt repoOne "payments" "2.5.0" "3.0.0" fixedTime
            replacement =
              ( (mkReceipt repoOne "payments" "1.0.0" "2.0.0" fixedTime2)
                  & #blueprintVersion .~ Just "0.5.0"
              )
        recordAppliedBlueprintMigration manifestPath first `shouldReturn` Right ()
        recordAppliedBlueprintMigration manifestPath second `shouldReturn` Right ()
        recordAppliedBlueprintMigration manifestPath replacement `shouldReturn` Right ()
        manifest <- readManifestFile manifestPath
        (manifest ^. #blueprintMigrations) `shouldBe` [replacement, second]

    -- The ledger keys receipts by the origin of the blueprint that owns the
    -- edge, so two repositories publishing the same name and the same edge
    -- window each keep their own receipt rather than overwriting each other.
    it "appends rather than replaces when only the origin differs" $
      withSystemTempDirectory "seihou-blueprint-migration" $ \dir -> do
        let manifestPath = dir </> "manifest.json"
            fromRepoOne = mkReceipt repoOne "payments" "1.0.0" "2.0.0" fixedTime
            fromRepoTwo = mkReceipt repoTwo "payments" "1.0.0" "2.0.0" fixedTime2
        recordAppliedBlueprintMigration manifestPath fromRepoOne `shouldReturn` Right ()
        recordAppliedBlueprintMigration manifestPath fromRepoTwo `shouldReturn` Right ()
        manifest <- readManifestFile manifestPath
        (manifest ^. #blueprintMigrations) `shouldBe` [fromRepoOne, fromRepoTwo]

    it "replaces in place when the origin spelling differs only by a .git suffix" $
      withSystemTempDirectory "seihou-blueprint-migration" $ \dir -> do
        let manifestPath = dir </> "manifest.json"
            plainUrl = mkReceipt repoOne "payments" "1.0.0" "2.0.0" fixedTime
            dotGitUrl =
              mkReceipt
                (RemoteOrigin "https://github.com/acme/one.git" "payments" Nothing)
                "payments"
                "1.0.0"
                "2.0.0"
                fixedTime2
        recordAppliedBlueprintMigration manifestPath plainUrl `shouldReturn` Right ()
        recordAppliedBlueprintMigration manifestPath dotGitUrl `shouldReturn` Right ()
        manifest <- readManifestFile manifestPath
        (manifest ^. #blueprintMigrations) `shouldBe` [dotGitUrl]

    it "returns Left and preserves a corrupt existing manifest" $
      withSystemTempDirectory "seihou-blueprint-migration" $ \dir -> do
        let manifestPath = dir </> "manifest.json"
            corrupt = "{ this is not valid json"
        writeFile manifestPath corrupt
        result <- recordAppliedBlueprintMigration manifestPath (mkReceipt repoOne "payments" "1.0.0" "2.0.0" fixedTime)
        case result of
          Left err -> err `shouldSatisfy` not . T.null
          Right () -> expectationFailure "expected corrupt manifest failure"
        readFile manifestPath `shouldReturn` corrupt

  describe "receipt JSON" $ do
    it "round-trips a receipt's origin through the manifest encoding" $
      withSystemTempDirectory "seihou-blueprint-migration" $ \dir -> do
        let manifestPath = dir </> "manifest.json"
            receipt = mkReceipt repoOne "payments" "1.0.0" "2.0.0" fixedTime
        recordAppliedBlueprintMigration manifestPath receipt `shouldReturn` Right ()
        encoded <- LBS.readFile manifestPath
        LBS.toStrict encoded
          `shouldSatisfy` BS.isInfixOf (TE.encodeUtf8 "https://github.com/acme/one")
        manifest <- readManifestFile manifestPath
        map (^. #origin) (manifest ^. #blueprintMigrations) `shouldBe` [repoOne]

    it "round-trips a not-applicable outcome with its reason intact" $
      withSystemTempDirectory "seihou-blueprint-migration" $ \dir -> do
        let manifestPath = dir </> "manifest.json"
            reason = "the project has not adopted the bundle"
            skipped =
              mkReceiptWithOutcome repoOne "payments" "1.0.0" "2.0.0" fixedTime (MigrationNotApplicable reason)
        recordAppliedBlueprintMigration manifestPath skipped `shouldReturn` Right ()
        encoded <- LBS.readFile manifestPath
        LBS.toStrict encoded `shouldSatisfy` BS.isInfixOf (TE.encodeUtf8 "not-applicable")
        manifest <- readManifestFile manifestPath
        (manifest ^. #blueprintMigrations) `shouldBe` [skipped]

    -- Outcome is audit metadata, not identity. An edge that reported itself
    -- inapplicable and later ran for real must leave one receipt behind, not
    -- two records of the same edge disagreeing about what happened.
    it "replaces a not-applicable receipt when the same edge later applies" $
      withSystemTempDirectory "seihou-blueprint-migration" $ \dir -> do
        let manifestPath = dir </> "manifest.json"
            skipped =
              mkReceiptWithOutcome repoOne "payments" "1.0.0" "2.0.0" fixedTime (MigrationNotApplicable "no adr bundle")
            applied = mkReceipt repoOne "payments" "1.0.0" "2.0.0" fixedTime2
        recordAppliedBlueprintMigration manifestPath skipped `shouldReturn` Right ()
        recordAppliedBlueprintMigration manifestPath applied `shouldReturn` Right ()
        manifest <- readManifestFile manifestPath
        (manifest ^. #blueprintMigrations) `shouldBe` [applied]

    -- A manifest written before the origin field existed must keep parsing.
    -- Nothing on disk can say where such a receipt came from, so it decodes
    -- to the constructor that means "provenance seihou cannot verify".
    it "decodes a receipt with no origin key as unverifiable provenance" $ do
      let legacy =
            LBS.fromStrict $
              TE.encodeUtf8 $
                T.unlines
                  [ "{ \"version\": 6",
                    ", \"generatedAt\": \"2026-07-20T12:00:00Z\"",
                    ", \"modules\": []",
                    ", \"variables\": {}",
                    ", \"files\": {}",
                    ", \"blueprintMigrations\":",
                    "  [ { \"name\": \"payments\"",
                    "    , \"from\": \"1.0.0\"",
                    "    , \"to\": \"2.0.0\"",
                    "    , \"appliedAt\": \"2026-07-20T12:00:00Z\"",
                    "    } ]",
                    "}"
                  ]
      case manifestFromJSON legacy of
        Left err -> expectationFailure ("legacy manifest must still parse: " <> err)
        Right manifest -> do
          map (^. #origin) (manifest ^. #blueprintMigrations)
            `shouldBe` [LocalOrigin "payments"]
          -- Every receipt written before the outcome field existed recorded an
          -- edge whose session returned, which is what MigrationApplied means.
          -- Reading it that way preserves its meaning; a receipt that was
          -- really a deliberate no-op stays wrong, and --rerun is its remedy.
          map (^. #outcome) (manifest ^. #blueprintMigrations)
            `shouldBe` [MigrationApplied]
