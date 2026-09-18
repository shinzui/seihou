module Seihou.CLI.InstallSourceSpec (tests) where

import Data.Text qualified as T
import Seihou.CLI.InstallShared
  ( RecordedSource (..),
    formatRecordedSourceNotice,
    recordedSourceUrl,
    resolveRecordedSource,
  )
import System.Directory (createDirectoryIfMissing)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.InstallSource" spec

fakeRemote :: T.Text
fakeRemote = "https://example.invalid/r.git"

-- | Run git in a directory with a throwaway identity, failing the test on a
-- nonzero exit so a broken fixture never masquerades as a result.
git :: FilePath -> [String] -> IO ()
git dir args = do
  (code, _out, err) <-
    readProcessWithExitCode
      "git"
      (["-C", dir, "-c", "user.name=seihou-test", "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false"] <> args)
      ""
  case code of
    ExitSuccess -> pure ()
    ExitFailure _ -> expectationFailure ("git " <> unwords args <> " failed: " <> err)

-- | A checkout with one commit.
initCheckout :: FilePath -> IO ()
initCheckout dir = do
  createDirectoryIfMissing True dir
  git dir ["init", "-q", "-b", "main"]
  writeFile (dir </> "module.dhall") "{=}"
  git dir ["add", "."]
  git dir ["commit", "-q", "-m", "init"]

-- | Point the checkout's @origin@ at a URL that cannot be fetched and
-- pretend its current HEAD has been pushed there. A bare repository's path
-- would itself count as machine-local, so the test fakes the remote-tracking
-- ref instead of pushing.
publishHead :: FilePath -> IO ()
publishHead dir = do
  git dir ["remote", "add", "origin", T.unpack fakeRemote]
  git dir ["update-ref", "refs/remotes/origin/main", "HEAD"]

spec :: Spec
spec = describe "resolveRecordedSource" $ do
  it "records a URL argument as given" $ do
    recorded <- resolveRecordedSource "https://github.com/shinzui/seihou-modules.git"
    recorded `shouldBe` RecordSource "https://github.com/shinzui/seihou-modules.git"
    formatRecordedSourceNotice recorded `shouldBe` Nothing

  it "records the origin remote of a checkout whose HEAD is published there" $
    withSystemTempDirectory "seihou-install-source" $ \tmp -> do
      let checkout = tmp </> "modules"
      initCheckout checkout
      publishHead checkout
      recorded <- resolveRecordedSource (T.pack checkout)
      recorded `shouldBe` RecordPublishedRemote fakeRemote (T.pack checkout)
      recordedSourceUrl recorded `shouldBe` fakeRemote
      fmap (T.isInfixOf "note: recording origin https://example.invalid/r.git") (formatRecordedSourceNotice recorded)
        `shouldBe` Just True

  it "keeps the path when HEAD has a commit that is not on the remote" $
    withSystemTempDirectory "seihou-install-source" $ \tmp -> do
      let checkout = tmp </> "modules"
      initCheckout checkout
      publishHead checkout
      writeFile (checkout </> "extra.txt") "unpushed"
      git checkout ["add", "."]
      git checkout ["commit", "-q", "-m", "unpushed"]
      recorded <- resolveRecordedSource (T.pack checkout)
      recorded
        `shouldBe` RecordLocalPath (T.pack checkout) "HEAD is not on any remote branch; push it first"
      recordedSourceUrl recorded `shouldBe` T.pack checkout
      fmap (T.isPrefixOf "warning: ") (formatRecordedSourceNotice recorded) `shouldBe` Just True

  it "keeps the path when the checkout has no origin remote" $
    withSystemTempDirectory "seihou-install-source" $ \tmp -> do
      let checkout = tmp </> "modules"
      initCheckout checkout
      recorded <- resolveRecordedSource (T.pack checkout)
      recorded `shouldBe` RecordLocalPath (T.pack checkout) "no origin remote"

  it "keeps the path when the origin remote is itself a local path" $
    withSystemTempDirectory "seihou-install-source" $ \tmp -> do
      let checkout = tmp </> "modules"
      initCheckout checkout
      git checkout ["remote", "add", "origin", tmp </> "bare.git"]
      git checkout ["update-ref", "refs/remotes/origin/main", "HEAD"]
      recorded <- resolveRecordedSource (T.pack checkout)
      case recorded of
        RecordLocalPath path reason -> do
          path `shouldBe` T.pack checkout
          reason `shouldSatisfy` T.isInfixOf "is itself a local path"
        other -> expectationFailure ("expected RecordLocalPath, got " <> show other)

  it "keeps the path when it is not a git repository" $
    withSystemTempDirectory "seihou-install-source" $ \tmp -> do
      let plain = tmp </> "plain"
      createDirectoryIfMissing True plain
      recorded <- resolveRecordedSource (T.pack plain)
      recorded `shouldBe` RecordLocalPath (T.pack plain) "not a git repository"
