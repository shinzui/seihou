module Seihou.Effect.ManifestStoreSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Effectful
import Seihou.Core.Types
import Seihou.Effect.Filesystem (readFileText)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.FilesystemPure (PureFS (..), emptyFS, runFilesystemPure)
import Seihou.Effect.ManifestStore (readManifest, writeManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Effect.ManifestStorePure (runManifestStorePure)
import Seihou.Manifest.Types (emptyManifest)
import System.Directory (doesFileExist)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Effect.ManifestStore" spec

fixedTime :: UTCTime
fixedTime = parseTimeOrError True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" "2026-03-01T10:30:00Z"

sampleManifest :: Manifest
sampleManifest =
  (emptyManifest fixedTime)
    { modules =
        [ AppliedModule (ModuleName "haskell-base") emptyParentVars "/path/to/mod" Nothing fixedTime Nothing
        ],
      vars = Map.fromList [(VarName "project.name", "my-app")],
      files =
        Map.fromList
          [ ( "README.md",
              FileRecord (SHA256 "abc123") (ModuleName "haskell-base") Template fixedTime Nothing mempty
            )
          ]
    }

spec :: Spec
spec = do
  describe "pure interpreter" $ do
    it "returns Right Nothing when no manifest stored" $ do
      let (result, _) = runPureEff $ runManifestStorePure Nothing readManifest
      result `shouldBe` Right Nothing

    it "returns Right (Just manifest) after write" $ do
      let (result, _) = runPureEff $ runManifestStorePure Nothing $ do
            writeManifest sampleManifest
            readManifest
      result `shouldBe` Right (Just sampleManifest)

    it "overwrites previous manifest" $ do
      let m2 = emptyManifest fixedTime
          (result, _) = runPureEff $ runManifestStorePure Nothing $ do
            writeManifest sampleManifest
            writeManifest m2
            readManifest
      result `shouldBe` Right (Just m2)

    it "returns final state" $ do
      let (_, finalState) = runPureEff $ runManifestStorePure Nothing $ do
            writeManifest sampleManifest
      finalState `shouldBe` Just sampleManifest

  describe "real interpreter (via pure filesystem)" $ do
    it "returns Right Nothing when manifest file does not exist" $ do
      let manifestPath = ".seihou/manifest.json"
          (result, _) =
            runPureEff $
              runFilesystemPure emptyFS $
                runManifestStore manifestPath readManifest
      result `shouldBe` Right Nothing

    it "roundtrips a manifest through filesystem" $ do
      let manifestPath = ".seihou/manifest.json"
          (result, _) =
            runPureEff $
              runFilesystemPure emptyFS $
                runManifestStore manifestPath $ do
                  writeManifest sampleManifest
                  readManifest
      result `shouldBe` Right (Just sampleManifest)

    it "writes valid JSON to the filesystem" $ do
      let manifestPath = ".seihou/manifest.json"
          (((), content), _) =
            runPureEff $
              runFilesystemPure emptyFS $ do
                runManifestStore manifestPath (writeManifest sampleManifest)
                c <- readFileText manifestPath
                pure ((), c)
      T.isInfixOf "\"version\":4" content `shouldBe` True
      T.isInfixOf "haskell-base" content `shouldBe` True
      T.isInfixOf "my-app" content `shouldBe` True

    it "renames the temp manifest away after a successful write" $ do
      let manifestPath = ".seihou/manifest.json"
          (_, finalFS) =
            runPureEff $
              runFilesystemPure emptyFS $
                runManifestStore manifestPath (writeManifest sampleManifest)
      Map.member manifestPath finalFS.files `shouldBe` True
      Map.member (manifestPath <> ".tmp") finalFS.files `shouldBe` False
      Set.member ".seihou" finalFS.dirs `shouldBe` True

    it "returns Left for corrupt JSON" $ do
      let manifestPath = ".seihou/manifest.json"
          corruptFS = PureFS (Map.fromList [(manifestPath, "{ this is not json }")]) Set.empty
          (result, _) =
            runPureEff $
              runFilesystemPure corruptFS $
                runManifestStore manifestPath readManifest
      case result of
        Left _err -> pure () -- Any Left is correct for corrupt JSON
        Right _ -> expectationFailure "Expected Left for corrupt JSON"

  describe "real filesystem interpreter" $ do
    it "writes valid JSON atomically and leaves no temp file" $ do
      withSystemTempDirectory "seihou-manifest-store" $ \tmpDir -> do
        let manifestPath = tmpDir </> ".seihou" </> "manifest.json"
            tmpPath = manifestPath <> ".tmp"
        runEff $
          runFilesystem $
            runManifestStore manifestPath (writeManifest sampleManifest)
        finalExists <- doesFileExist manifestPath
        tempExists <- doesFileExist tmpPath
        finalExists `shouldBe` True
        tempExists `shouldBe` False
        result <-
          runEff $
            runFilesystem $
              runManifestStore manifestPath readManifest
        result `shouldBe` Right (Just sampleManifest)
