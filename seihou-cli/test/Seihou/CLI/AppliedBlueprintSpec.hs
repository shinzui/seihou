module Seihou.CLI.AppliedBlueprintSpec (tests) where

import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Seihou.CLI.AppliedBlueprint (recordAppliedBlueprint)
import Seihou.Core.Types
  ( AppliedBlueprint (..),
    AppliedRecipe (..),
    Manifest (..),
    ModuleName (..),
    RecipeName (..),
  )
import Seihou.Manifest.Types (currentManifestVersion, emptyManifest, manifestFromJSON, manifestToJSON)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.AppliedBlueprint" spec

fixedTime :: UTCTime
fixedTime =
  parseTimeOrError
    True
    defaultTimeLocale
    "%Y-%m-%dT%H:%M:%SZ"
    "2026-05-12T14:23:00Z"

mkEntry :: Text -> Maybe Text -> [Text] -> Bool -> Maybe Text -> AppliedBlueprint
mkEntry name mver baseline noBL prompt =
  AppliedBlueprint
    { name = ModuleName name,
      blueprintVersion = mver,
      appliedAt = fixedTime,
      baselineModules = map ModuleName baseline,
      noBaseline = noBL,
      userPrompt = prompt,
      agentSessionId = Nothing
    }

readManifestFile :: FilePath -> IO Manifest
readManifestFile path = do
  bs <- LBS.readFile path
  case manifestFromJSON bs of
    Right m -> pure m
    Left err -> error ("test fixture: malformed manifest: " <> err)

spec :: Spec
spec = do
  describe "recordAppliedBlueprint" $ do
    it "creates a fresh manifest when none exists" $
      withSystemTempDirectory "seihou-ab" $ \dir -> do
        let manifestPath = dir </> ".seihou" </> "manifest.json"
            entry = mkEntry "payments-service" (Just "0.3.1") ["nix-flake"] False (Just "set up payments")
        res <- recordAppliedBlueprint manifestPath entry
        res `shouldBe` Right ()
        m <- readManifestFile manifestPath
        m.version `shouldBe` currentManifestVersion
        m.blueprint `shouldBe` Just entry

    it "preserves unrelated manifest fields" $
      withSystemTempDirectory "seihou-ab" $ \dir -> do
        let manifestPath = dir </> "manifest.json"
            seedRecipe =
              AppliedRecipe
                { name = RecipeName "haskell-library",
                  recipeVersion = Just "1.2.0",
                  appliedAt = fixedTime
                }
            seed =
              (emptyManifest fixedTime)
                { recipe = Just seedRecipe,
                  vars = Map.empty
                }
        LBS.writeFile manifestPath (manifestToJSON seed)
        let entry = mkEntry "payments-service" Nothing [] True Nothing
        res <- recordAppliedBlueprint manifestPath entry
        res `shouldBe` Right ()
        m <- readManifestFile manifestPath
        m.recipe `shouldBe` Just seedRecipe
        m.blueprint `shouldBe` Just entry

    it "overwrites a prior blueprint entry" $
      withSystemTempDirectory "seihou-ab" $ \dir -> do
        let manifestPath = dir </> "manifest.json"
            ab1 = mkEntry "first" Nothing [] False Nothing
            ab2 = mkEntry "second" (Just "0.2.0") ["base"] False (Just "second run")
        _ <- recordAppliedBlueprint manifestPath ab1
        _ <- recordAppliedBlueprint manifestPath ab2
        m <- readManifestFile manifestPath
        m.blueprint `shouldBe` Just ab2

    it "returns Left when the existing manifest is unreadable" $
      withSystemTempDirectory "seihou-ab" $ \dir -> do
        let manifestPath = dir </> "manifest.json"
        writeFile manifestPath "{ this is not valid json"
        let entry = mkEntry "x" Nothing [] False Nothing
        res <- recordAppliedBlueprint manifestPath entry
        case res of
          Left err -> err `shouldSatisfy` not . T.null
          Right () -> expectationFailure "expected Left for corrupt manifest"
