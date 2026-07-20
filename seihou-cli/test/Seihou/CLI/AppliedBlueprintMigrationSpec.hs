module Seihou.CLI.AppliedBlueprintMigrationSpec (tests) where

import Data.ByteString.Lazy qualified as LBS
import Data.Text qualified as T
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Seihou.CLI.AppliedBlueprintMigration (recordAppliedBlueprintMigration)
import Seihou.Core.Types (AppliedBlueprintMigration (..), Manifest (..), ModuleName (..))
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

mkReceipt :: T.Text -> T.Text -> T.Text -> UTCTime -> AppliedBlueprintMigration
mkReceipt blueprintName fromVersion toVersion appliedAt =
  AppliedBlueprintMigration
    { name = ModuleName blueprintName,
      blueprintVersion = Just "0.4.0",
      fromVersion = fromVersion,
      toVersion = toVersion,
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
spec = describe "recordAppliedBlueprintMigration" $ do
  it "creates a version-5 manifest for the first receipt" $
    withSystemTempDirectory "seihou-blueprint-migration" $ \dir -> do
      let manifestPath = dir </> ".seihou" </> "manifest.json"
          receipt = mkReceipt "payments" "1.0.0" "2.0.0" fixedTime
      result <- recordAppliedBlueprintMigration manifestPath receipt
      result `shouldBe` Right ()
      manifest <- readManifestFile manifestPath
      manifest.version `shouldBe` currentManifestVersion
      manifest.blueprintMigrations `shouldBe` [receipt]

  it "upserts the same exact edge and retains unrelated edges" $
    withSystemTempDirectory "seihou-blueprint-migration" $ \dir -> do
      let manifestPath = dir </> "manifest.json"
          first = mkReceipt "payments" "1.0.0" "2.0.0" fixedTime
          second = mkReceipt "payments" "2.5.0" "3.0.0" fixedTime
          replacement =
            (mkReceipt "payments" "1.0.0" "2.0.0" fixedTime2)
              { blueprintVersion = Just "0.5.0"
              }
      recordAppliedBlueprintMigration manifestPath first `shouldReturn` Right ()
      recordAppliedBlueprintMigration manifestPath second `shouldReturn` Right ()
      recordAppliedBlueprintMigration manifestPath replacement `shouldReturn` Right ()
      manifest <- readManifestFile manifestPath
      manifest.blueprintMigrations `shouldBe` [replacement, second]

  it "returns Left and preserves a corrupt existing manifest" $
    withSystemTempDirectory "seihou-blueprint-migration" $ \dir -> do
      let manifestPath = dir </> "manifest.json"
          corrupt = "{ this is not valid json"
      writeFile manifestPath corrupt
      result <- recordAppliedBlueprintMigration manifestPath (mkReceipt "payments" "1.0.0" "2.0.0" fixedTime)
      case result of
        Left err -> err `shouldSatisfy` not . T.null
        Right () -> expectationFailure "expected corrupt manifest failure"
      readFile manifestPath `shouldReturn` corrupt
