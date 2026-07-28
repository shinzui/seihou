module Seihou.CLI.ManifestUpgradeSpec (tests) where

import Control.Lens ((^.))
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.Text qualified as T
import Seihou.CLI.ManifestUpgrade
  ( LegacyManifest (..),
    LegacyRef (..),
    readLegacyManifest,
  )
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.ManifestUpgrade" spec

fixturePath :: FilePath
fixturePath = "test/fixtures/legacy-manifest-v5.json"

-- | Every legacy reference the fixture contains, as
-- @(pointer, name, path, version, definition file)@.
expectedRefs :: [([String], String, FilePath, Maybe String, FilePath)]
expectedRefs =
  [ ( ["modules", "0", "source"],
      "haskell-base",
      "/Users/someone-else/.config/seihou/installed/haskell-base",
      Just "1.4.0",
      "module.dhall"
    ),
    ( ["modules", "1", "source"],
      "project-lint",
      "/Users/someone-else/work/myproject/.seihou/modules/project-lint",
      Just "0.2.0",
      "module.dhall"
    ),
    ( ["applications", "0", "targetSource"],
      "haskell-base",
      "/Users/someone-else/.config/seihou/installed/haskell-base",
      Just "1.4.0",
      "module.dhall"
    ),
    ( ["applications", "0", "instances", "0", "source"],
      "haskell-base",
      "/Users/someone-else/.config/seihou/installed/haskell-base",
      Just "1.4.0",
      "module.dhall"
    ),
    ( ["applications", "1", "targetSource"],
      "haskell-service",
      "/Users/someone-else/.config/seihou/installed/haskell-service",
      Just "3.1.0",
      "recipe.dhall"
    ),
    ( ["applications", "1", "instances", "0", "source"],
      "project-lint",
      "/Users/someone-else/work/myproject/.seihou/modules/project-lint",
      Just "0.2.0",
      "module.dhall"
    ),
    ( ["applications", "1", "instances", "1", "source"],
      "scratch-helper",
      "/Users/someone-else/.config/seihou/modules/scratch-helper",
      Nothing,
      "module.dhall"
    )
  ]

describeRef :: LegacyRef -> ([String], String, FilePath, Maybe String, FilePath)
describeRef ref =
  ( map T.unpack (ref ^. #jsonPointer),
    T.unpack (ref ^. #artifactName),
    ref ^. #legacyPath,
    fmap T.unpack (ref ^. #recordedVersion),
    ref ^. #definitionFile
  )

spec :: Spec
spec = do
  describe "readLegacyManifest" $ do
    it "finds every legacy reference in a schema-5 manifest, in document order" $ do
      bytes <- LBS.readFile fixturePath
      case readLegacyManifest bytes of
        Left err -> expectationFailure ("expected a legacy manifest, got: " <> err)
        Right Nothing -> expectationFailure "expected a legacy manifest, got 'nothing to do'"
        Right (Just legacy) -> do
          (legacy ^. #schemaVersion) `shouldBe` 5
          map describeRef (legacy ^. #refs) `shouldBe` expectedRefs

    it "reports nothing to do for a manifest already at the current schema version" $
      readLegacyManifest "{\"version\":6,\"modules\":[]}" `shouldBe` Right Nothing

    it "reports nothing to do for a manifest from a newer seihou" $
      readLegacyManifest "{\"version\":7,\"modules\":[]}" `shouldBe` Right Nothing

    it "rejects a document with no version field" $
      readLegacyManifest "{\"modules\":[]}"
        `shouldBe` Left "manifest has no 'version' field"
