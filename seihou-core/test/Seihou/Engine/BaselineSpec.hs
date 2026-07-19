module Seihou.Engine.BaselineSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Effectful
import Seihou.Core.Types
import Seihou.Effect.BaselineStore (BaselineError (..), readBaseline)
import Seihou.Effect.BaselineStorePure (runBaselineStorePure)
import Seihou.Effect.FilesystemPure (PureFS (..), runFilesystemPure)
import Seihou.Engine.Baseline
import Seihou.Manifest.Hash (baselineRefForContent, hashContent)
import Seihou.Manifest.Types (emptyManifest)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Engine.Baseline" spec

fixedTime :: UTCTime
fixedTime = parseTimeOrError True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" "2026-03-01T10:30:00Z"

spec :: Spec
spec = do
  describe "recordGeneratedBaselines" $ do
    it "captures post-execution content and preserves ownership metadata" $ do
      let path = "README.md"
          content = "generated after patch\n"
          applicationId = ApplicationId "application"
          record =
            FileRecord
              { hash = hashContent "stale pre-patch content",
                moduleName = ModuleName "module",
                strategy = Template,
                generatedAt = fixedTime,
                baseline = Nothing,
                applicationIds = Set.singleton applicationId
              }
          initialFS = PureFS (Map.singleton ("/project/" <> path) content) Set.empty
          ((result, stored), _) =
            runPureEff $
              runFilesystemPure initialFS $
                runBaselineStorePure Map.empty $
                  recordGeneratedBaselines "/project" (Map.singleton path record)
      case result of
        Left err -> expectationFailure ("unexpected baseline error: " <> show err)
        Right records -> do
          let enriched = records Map.! path
              expectedRef = baselineRefForContent content
          enriched.hash `shouldBe` hashContent content
          enriched.baseline `shouldBe` Just expectedRef
          enriched.applicationIds `shouldBe` Set.singleton applicationId
          Map.lookup expectedRef stored `shouldBe` Just content

    it "returns an error and publishes no reference when a generated file is missing" $ do
      let record = FileRecord (hashContent "planned") "module" Template fixedTime Nothing Set.empty
          ((result, stored), _) =
            runPureEff $
              runFilesystemPure (PureFS Map.empty Set.empty) $
                runBaselineStorePure Map.empty $
                  recordGeneratedBaselines "/project" (Map.singleton "missing.txt" record)
      result `shouldSatisfy` isStoreFailure
      stored `shouldBe` Map.empty

    it "stores content that can be read back through the baseline effect" $ do
      let content = "round trip"
          record = FileRecord (hashContent content) "module" Copy fixedTime Nothing Set.empty
          initialFS = PureFS (Map.singleton "copy.txt" content) Set.empty
          ((result, readBack), _) =
            runPureEff $
              runFilesystemPure initialFS $
                runBaselineStorePure Map.empty $ do
                  captured <- recordGeneratedBaselines "" (Map.singleton "copy.txt" record)
                  case captured of
                    Left err -> pure (Left err)
                    Right records -> case (records Map.! "copy.txt").baseline of
                      Nothing -> pure (Left (BaselineStoreFailure "missing reference"))
                      Just ref -> readBaseline ref
      result `shouldBe` Right "round trip"
      readBack `shouldBe` Map.singleton (baselineRefForContent content) content

  describe "manifestBaselineRefs" $ do
    it "collects and deduplicates every referenced blob" $ do
      let first = baselineRefForContent "first"
          second = baselineRefForContent "second"
          mkRecord ref = FileRecord (hashContent "applied") "module" Template fixedTime ref Set.empty
          manifest :: Manifest
          manifest =
            (emptyManifest fixedTime)
              { files =
                  Map.fromList
                    [ ("a", mkRecord (Just first)),
                      ("b", mkRecord (Just first)),
                      ("c", mkRecord (Just second)),
                      ("legacy", mkRecord Nothing)
                    ]
              }
      manifestBaselineRefs manifest `shouldBe` Set.fromList [first, second]

isStoreFailure :: Either BaselineError a -> Bool
isStoreFailure (Left (BaselineStoreFailure _)) = True
isStoreFailure _ = False
