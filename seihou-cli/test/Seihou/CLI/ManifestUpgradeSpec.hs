module Seihou.CLI.ManifestUpgradeSpec (tests) where

import Control.Lens ((^.))
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.Text (Text)
import Data.Text qualified as T
import Seihou.CLI.ManifestUpgrade
  ( InferenceOutcome (..),
    LegacyManifest (..),
    LegacyRef (..),
    inferOriginFromLegacyPath,
    readLegacyManifest,
  )
import Seihou.Core.Types (ArtifactOrigin (..))
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
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

  describe "inferOriginFromLegacyPath" $ do
    it "converts a foreign project path by its .seihou/modules suffix" $ do
      outcome <-
        inferOriginFromLegacyPath
          "/nowhere/this-project"
          []
          (legacyRef "demo" "/Users/someone-else/work/theirproject/.seihou/modules/demo")
      outcome `shouldBe` InferredFromProjectPath (ProjectOrigin ".seihou/modules/demo")

    it "recovers the upstream URL from a locally installed copy" $
      withInstall (Just originJson) $ \projectRoot installRoot -> do
        outcome <-
          inferOriginFromLegacyPath
            projectRoot
            [installRoot]
            (legacyRef "demo" "/Users/someone-else/.config/seihou/installed/demo")
        outcome
          `shouldBe` InferredFromLocalInstall
            (RemoteOrigin "https://example.com/demo-modules.git" "demo" (Just "demo-modules"))

    it "falls back to an unverifiable local origin when nothing is installed here" $
      withSystemTempDirectory "seihou-upgrade" $ \root -> do
        let projectRoot = root </> "project"
            installRoot = root </> "home" </> "seihou" </> "installed"
        createDirectoryIfMissing True projectRoot
        createDirectoryIfMissing True installRoot
        outcome <-
          inferOriginFromLegacyPath
            projectRoot
            [installRoot]
            (legacyRef "demo" "/Users/someone-else/.config/seihou/installed/demo")
        outcome `shouldBe` InferredAsUnverifiable (LocalOrigin "demo")

    it "reports an installed copy with no recorded provenance as unverifiable" $
      withInstall Nothing $ \projectRoot installRoot -> do
        outcome <-
          inferOriginFromLegacyPath
            projectRoot
            [installRoot]
            (legacyRef "demo" "/Users/someone-else/.config/seihou/modules/demo")
        outcome `shouldBe` InferredAsUnverifiable (LocalOrigin "demo")

-- | A reference to a module, which is all the inference tests need.
legacyRef :: Text -> FilePath -> LegacyRef
legacyRef name path =
  LegacyRef
    { jsonPointer = ["modules", "0", "source"],
      artifactName = name,
      legacyPath = path,
      recordedVersion = Just "1.0.0",
      definitionFile = "module.dhall"
    }

originJson :: String
originJson =
  "{\"sourceUrl\":\"https://example.com/demo-modules.git\"\
  \,\"repoName\":\"demo-modules\"\
  \,\"installedAt\":\"2026-07-01T00:00:00Z\"\
  \,\"version\":\"1.0.0\",\"tags\":[]}"

-- | A project root plus a search path holding an installed @demo@, with or
-- without the @.seihou-origin.json@ that records where it came from.
withInstall :: Maybe String -> (FilePath -> FilePath -> IO a) -> IO a
withInstall mOriginJson action =
  withSystemTempDirectory "seihou-upgrade" $ \root -> do
    let projectRoot = root </> "project"
        installRoot = root </> "home" </> "seihou" </> "installed"
        artifactDir = installRoot </> "demo"
    createDirectoryIfMissing True projectRoot
    createDirectoryIfMissing True artifactDir
    writeFile (artifactDir </> "module.dhall") "{ name = \"demo\" }"
    case mOriginJson of
      Nothing -> pure ()
      Just contents -> writeFile (artifactDir </> ".seihou-origin.json") contents
    action projectRoot installRoot
