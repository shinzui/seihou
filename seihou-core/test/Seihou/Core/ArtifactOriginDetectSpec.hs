module Seihou.Core.ArtifactOriginDetectSpec (tests) where

import Seihou.Core.ArtifactOriginDetect (detectArtifactOrigin)
import Seihou.Core.Types
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.ArtifactOriginDetect" spec

-- | Lay out a scratch project root and a sibling "installed" root, both
-- inside one temporary directory, and hand both to the test body.
withRoots :: (FilePath -> FilePath -> IO a) -> IO a
withRoots body =
  withSystemTempDirectory "seihou-artifact-origin" $ \tmpDir -> do
    let projectRoot = tmpDir </> "project"
        installedRoot = tmpDir </> "installed"
    createDirectoryIfMissing True projectRoot
    createDirectoryIfMissing True installedRoot
    body projectRoot installedRoot

spec :: Spec
spec = do
  describe "detectArtifactOrigin" $ do
    it "records a directory inside the project as a project-relative origin" $ do
      withRoots $ \projectRoot _installedRoot -> do
        let moduleDir = projectRoot </> ".seihou" </> "modules" </> "foo"
        createDirectoryIfMissing True moduleDir
        origin <- detectArtifactOrigin projectRoot moduleDir
        origin `shouldBe` ProjectOrigin ".seihou/modules/foo"

    it "records an installed directory with origin metadata as a remote origin" $ do
      withRoots $ \projectRoot installedRoot -> do
        let moduleDir = installedRoot </> "haskell-base"
        createDirectoryIfMissing True moduleDir
        writeFile
          (moduleDir </> ".seihou-origin.json")
          "{\"sourceUrl\":\"https://github.com/shinzui/seihou-modules.git\",\"repoName\":\"seihou-modules\",\"version\":\"1.4.0\"}"
        origin <- detectArtifactOrigin projectRoot moduleDir
        origin
          `shouldBe` RemoteOrigin
            "https://github.com/shinzui/seihou-modules.git"
            "haskell-base"
            (Just "seihou-modules")

    it "omits the repository name when the metadata does not record one" $ do
      withRoots $ \projectRoot installedRoot -> do
        let moduleDir = installedRoot </> "haskell-base"
        createDirectoryIfMissing True moduleDir
        writeFile
          (moduleDir </> ".seihou-origin.json")
          "{\"sourceUrl\":\"https://example.com/mods.git\"}"
        origin <- detectArtifactOrigin projectRoot moduleDir
        origin `shouldBe` RemoteOrigin "https://example.com/mods.git" "haskell-base" Nothing

    it "falls back to a local origin when the metadata is malformed" $ do
      withRoots $ \projectRoot installedRoot -> do
        let moduleDir = installedRoot </> "haskell-base"
        createDirectoryIfMissing True moduleDir
        writeFile (moduleDir </> ".seihou-origin.json") "not json at all"
        origin <- detectArtifactOrigin projectRoot moduleDir
        origin `shouldBe` LocalOrigin "haskell-base"

    it "falls back to a local origin when there is no metadata file" $ do
      withRoots $ \projectRoot installedRoot -> do
        let moduleDir = installedRoot </> "scratch-module"
        createDirectoryIfMissing True moduleDir
        origin <- detectArtifactOrigin projectRoot moduleDir
        origin `shouldBe` LocalOrigin "scratch-module"

    it "treats the project root itself as outside the project" $ do
      withRoots $ \projectRoot _installedRoot -> do
        origin <- detectArtifactOrigin projectRoot projectRoot
        origin `shouldBe` LocalOrigin "project"

    it "classifies a directory that does not exist without throwing" $ do
      withRoots $ \projectRoot _installedRoot -> do
        origin <- detectArtifactOrigin projectRoot (projectRoot </> ".seihou" </> "modules" </> "ghost")
        origin `shouldBe` ProjectOrigin ".seihou/modules/ghost"
