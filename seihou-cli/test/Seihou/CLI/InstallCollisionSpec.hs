module Seihou.CLI.InstallCollisionSpec (tests) where

import Control.Lens ((^.))
import Data.Generics.Labels ()
import Data.Text qualified as T
import Seihou.CLI.InstallShared
  ( InstallCollision (..),
    InstallOutcome (..),
    OriginInfo (..),
    classifyInstallCollision,
    formatInstallRefusal,
    installModuleDirInto,
    readOriginInfo,
  )
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.InstallCollision" spec

repoOne :: T.Text
repoOne = "https://github.com/acme/one"

repoTwo :: T.Text
repoTwo = "https://github.com/acme/two"

-- | Lay out a directory that looks like an installed artifact: one content
-- file plus the provenance file @seihou install@ writes beside it. A
-- 'Nothing' source means "installed by hand, no provenance", which is a real
-- state a user's cache can be in.
seedInstalled :: FilePath -> Maybe T.Text -> Maybe T.Text -> IO ()
seedInstalled dir mSource mVersion = do
  createDirectoryIfMissing True dir
  writeFile (dir </> "marker.txt") "the copy that was already here"
  case mSource of
    Nothing -> pure ()
    Just source ->
      writeFile (dir </> ".seihou-origin.json") $
        "{\"sourceUrl\":"
          <> show (T.unpack source)
          <> ",\"repoName\":null,\"installedAt\":\"2026-08-16T00:00:00Z\",\"version\":"
          <> maybe "null" (show . T.unpack) mVersion
          <> ",\"tags\":[]}"

-- | The directory an install copies *from*.
seedIncoming :: FilePath -> IO ()
seedIncoming dir = do
  createDirectoryIfMissing True dir
  writeFile (dir </> "incoming.txt") "the copy being installed"

spec :: Spec
spec = do
  describe "classifyInstallCollision" $ do
    it "classifies an absent directory as NoExistingInstall" $
      withSystemTempDirectory "seihou-collision" $ \dir -> do
        collision <- classifyInstallCollision (dir </> "nothing-here") repoOne
        collision `shouldBe` NoExistingInstall

    it "classifies a matching source URL as SameSource, carrying the recorded version" $
      withSystemTempDirectory "seihou-collision" $ \dir -> do
        let installed = dir </> "shared-thing"
        seedInstalled installed (Just repoOne) (Just "0.4.0")
        collision <- classifyInstallCollision installed repoOne
        collision `shouldBe` SameSource (Just "0.4.0")

    -- Two spellings of one git URL are one repository. A user who typed the
    -- .git suffix last week and omitted it today must not be told they have a
    -- different artifact.
    it "treats a trailing .git as the same source" $
      withSystemTempDirectory "seihou-collision" $ \dir -> do
        let installed = dir </> "shared-thing"
        seedInstalled installed (Just (repoOne <> ".git")) Nothing
        collision <- classifyInstallCollision installed repoOne
        collision `shouldBe` SameSource Nothing

    it "treats a trailing slash as the same source" $
      withSystemTempDirectory "seihou-collision" $ \dir -> do
        let installed = dir </> "shared-thing"
        seedInstalled installed (Just (repoOne <> "/")) Nothing
        collision <- classifyInstallCollision installed repoOne
        collision `shouldBe` SameSource Nothing

    it "classifies a different source URL as DifferentSource, carrying the recorded URL" $
      withSystemTempDirectory "seihou-collision" $ \dir -> do
        let installed = dir </> "shared-thing"
        seedInstalled installed (Just repoOne) Nothing
        collision <- classifyInstallCollision installed repoTwo
        collision `shouldBe` DifferentSource repoOne

    it "classifies a directory with no provenance file as UnknownSource" $
      withSystemTempDirectory "seihou-collision" $ \dir -> do
        let installed = dir </> "handmade"
        seedInstalled installed Nothing Nothing
        collision <- classifyInstallCollision installed repoOne
        collision `shouldBe` UnknownSource

    it "classifies an unparseable provenance file as UnknownSource" $
      withSystemTempDirectory "seihou-collision" $ \dir -> do
        let installed = dir </> "corrupt"
        seedInstalled installed Nothing Nothing
        writeFile (installed </> ".seihou-origin.json") "{ this is not valid json"
        collision <- classifyInstallCollision installed repoOne
        collision `shouldBe` UnknownSource

  describe "installModuleDirInto" $ do
    it "installs into an empty cache without comment" $
      withSystemTempDirectory "seihou-collision" $ \dir -> do
        let root = dir </> "installed"
            incoming = dir </> "incoming"
        seedIncoming incoming
        outcome <- installModuleDirInto root False incoming "shared-thing" repoOne Nothing (Just "1.0.0") []
        outcome `shouldBe` InstallPerformed
        doesFileExist (root </> "shared-thing" </> "incoming.txt") `shouldReturn` True
        recorded <- readOriginInfo (root </> "shared-thing")
        fmap (^. #sourceUrl) recorded `shouldBe` Just repoOne

    it "replaces an installation from the same source" $
      withSystemTempDirectory "seihou-collision" $ \dir -> do
        let root = dir </> "installed"
            incoming = dir </> "incoming"
        seedInstalled (root </> "shared-thing") (Just repoOne) (Just "0.4.0")
        seedIncoming incoming
        outcome <- installModuleDirInto root False incoming "shared-thing" repoOne Nothing (Just "0.5.0") []
        outcome `shouldBe` InstallPerformed
        doesFileExist (root </> "shared-thing" </> "incoming.txt") `shouldReturn` True
        doesFileExist (root </> "shared-thing" </> "marker.txt") `shouldReturn` False

    -- The property that matters: the refusal happens before anything is
    -- removed, so a refused install leaves the cache exactly as it was. The
    -- marker file is the evidence.
    it "refuses a different source and leaves the existing installation untouched" $
      withSystemTempDirectory "seihou-collision" $ \dir -> do
        let root = dir </> "installed"
            incoming = dir </> "incoming"
        seedInstalled (root </> "shared-thing") (Just repoOne) Nothing
        seedIncoming incoming
        outcome <- installModuleDirInto root False incoming "shared-thing" repoTwo Nothing Nothing []
        outcome `shouldBe` InstallRefused (DifferentSource repoOne)
        readFile (root </> "shared-thing" </> "marker.txt")
          `shouldReturn` "the copy that was already here"
        doesFileExist (root </> "shared-thing" </> "incoming.txt") `shouldReturn` False
        recorded <- readOriginInfo (root </> "shared-thing")
        fmap (^. #sourceUrl) recorded `shouldBe` Just repoOne

    it "refuses an installation with no provenance and leaves it untouched" $
      withSystemTempDirectory "seihou-collision" $ \dir -> do
        let root = dir </> "installed"
            incoming = dir </> "incoming"
        seedInstalled (root </> "handmade") Nothing Nothing
        seedIncoming incoming
        outcome <- installModuleDirInto root False incoming "handmade" repoOne Nothing Nothing []
        outcome `shouldBe` InstallRefused UnknownSource
        readFile (root </> "handmade" </> "marker.txt")
          `shouldReturn` "the copy that was already here"

    it "replaces a different source when force is passed" $
      withSystemTempDirectory "seihou-collision" $ \dir -> do
        let root = dir </> "installed"
            incoming = dir </> "incoming"
        seedInstalled (root </> "shared-thing") (Just repoOne) Nothing
        seedIncoming incoming
        outcome <- installModuleDirInto root True incoming "shared-thing" repoTwo Nothing Nothing []
        outcome `shouldBe` InstallPerformed
        doesFileExist (root </> "shared-thing" </> "incoming.txt") `shouldReturn` True
        doesFileExist (root </> "shared-thing" </> "marker.txt") `shouldReturn` False
        recorded <- readOriginInfo (root </> "shared-thing")
        fmap (^. #sourceUrl) recorded `shouldBe` Just repoTwo

  describe "formatInstallRefusal" $ do
    it "names both sources and the override flag" $ do
      let rendered = formatInstallRefusal "shared-thing" repoTwo (DifferentSource repoOne)
      rendered `shouldSatisfy` T.isInfixOf repoOne
      rendered `shouldSatisfy` T.isInfixOf repoTwo
      rendered `shouldSatisfy` T.isInfixOf "--force"
      rendered `shouldSatisfy` T.isInfixOf "shared-thing"

    it "says provenance is missing rather than naming a recorded URL" $ do
      let rendered = formatInstallRefusal "handmade" repoOne UnknownSource
      rendered `shouldSatisfy` T.isInfixOf "no .seihou-origin.json"
      rendered `shouldSatisfy` T.isInfixOf "--force"

    it "has nothing to say about a case that is not refused" $ do
      formatInstallRefusal "shared-thing" repoOne NoExistingInstall `shouldBe` ""
      formatInstallRefusal "shared-thing" repoOne (SameSource (Just "1.0.0")) `shouldBe` ""
