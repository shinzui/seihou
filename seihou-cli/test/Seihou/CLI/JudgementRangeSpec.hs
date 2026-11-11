module Seihou.CLI.JudgementRangeSpec (tests) where

import Data.ByteString qualified as BS
import Data.Either (isLeft)
import Data.Generics.Labels ()
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time (UTCTime (..), fromGregorian)
import Seihou.CLI.Judgement.Check
import Seihou.CLI.Judgement.CommitGate
import Seihou.CLI.Judgement.Evidence
import Seihou.CLI.Judgement.Runtime (JudgementBackend (..))
import Seihou.CLI.Judgement.Scanner (findScanner)
import Seihou.Core.Judgement
import Seihou.Core.Types (ActiveJudgement (..), ApplicationId (..), JudgementOwner (..), JudgementSource (..))
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.ManifestStore (writeManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Manifest.Judgement (definitionDigest)
import Seihou.Manifest.Types (emptyManifest)
import Seihou.Prelude
import System.Directory (createDirectoryIfMissing, removeFile)
import System.FilePath (takeDirectory)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (callProcess, readProcess)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

fakeToken :: Text
fakeToken = "ghp_" <> "Z8yQ3mK7pL2nV5bX9cW4rT6uJ1hG0fD8sA3e"

git :: FilePath -> [String] -> IO ()
git dir args = callProcess "git" (["-C", dir, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "-c", "commit.gpgsign=false"] <> args)

writeAt :: FilePath -> FilePath -> Text -> IO ()
writeAt dir p body = do
  createDirectoryIfMissing True (takeDirectory (dir </> p))
  BS.writeFile (dir </> p) (TE.encodeUtf8 body)

commitAll :: FilePath -> String -> IO ()
commitAll dir msg = git dir ["add", "-A"] >> git dir ["commit", "-q", "--no-verify", "-m", msg]

withRepo :: (FilePath -> IO a) -> IO a
withRepo act = withSystemTempDirectory "judgement-range" $ \dir -> do
  git dir ["init", "-q", "-b", "main"]
  git dir ["commit", "-q", "--allow-empty", "-m", "init"]
  act dir

secretReview :: JudgementDefinition
secretReview =
  JudgementDefinition "security-review" (Just "1.0.0") Nothing "Review." defaultEvidenceDeclaration defaultCoverageLimits [SecretScan] (JudgementCheck "c" "Is the concern present?" Yes Nothing Nothing [] Enforced High (Thresholds 0.5 0.1) (Thresholds 0.9 0.05) True :| [])

active :: JudgementDefinition -> ActiveJudgement
active d = ActiveJudgement BundledJudgement d (definitionDigest d) (defaultPolicy ApprovedRemote False d) [DirectAdoption]

countingServices :: FilePath -> IO (CheckServices, IO Int)
countingServices dir = do
  calls <- newIORef (0 :: Int)
  sc <- findScanner
  let be = JudgementBackend (\_ _ _ -> modifyIORef' calls (+ 1) >> pure (Right (RawReview 0.0 [] False))) Nothing (pure [])
  pure (CheckServices (gitBytes dir) sc (\_ -> pure (Right (BackendChoice (Just be) True (Just "stub") Nothing))), readIORef calls)

tests :: IO TestTree
tests = testSpec "judgement commit ranges, trusted policy and the commit gate" $ do
  describe "commit-range evidence" $ do
    it "captures a file added and then removed inside the range, by commit" $ withRepo $ \dir -> do
      git dir ["checkout", "-q", "-b", "feature"]
      writeAt dir "cfg/a.env" ("token = \"" <> fakeToken <> "\"\n")
      commitAll dir "add"
      git dir ["rm", "-q", "-r", "cfg"]
      commitAll dir "remove"
      Right snap <- captureRange defaultCoverageLimits (gitBytes dir) "main" "HEAD"
      snap ^. #scope `shouldBe` CommitRangeScope
      map sourcePath (snap ^. #files) `shouldBe` ["cfg/a.env"]
      map (T.pack . (^. #path)) (snap ^. #files) `shouldSatisfy` all ("cfg/a.env@" `T.isPrefixOf`)
    it "keeps the final path for the last version and names earlier ones by commit" $ withRepo $ \dir -> do
      git dir ["checkout", "-q", "-b", "feature"]
      writeAt dir "notes.md" "one\n"
      commitAll dir "one"
      writeAt dir "notes.md" "two\n"
      commitAll dir "two"
      Right snap <- captureRange defaultCoverageLimits (gitBytes dir) "main" "HEAD"
      [f ^. #content | f <- snap ^. #files, f ^. #path == "notes.md"] `shouldBe` [Just "two\n"]
      length (snap ^. #files) `shouldBe` 2
    it "reports NoChanges for an empty range and refuses an unknown base" $ withRepo $ \dir -> do
      Right snap <- captureRange defaultCoverageLimits (gitBytes dir) "main" "HEAD"
      snap ^. #files `shouldBe` []
      captureRange defaultCoverageLimits (gitBytes dir) "nope" "HEAD" >>= (`shouldSatisfy` isLeft)
    it "blocks the range with no review request when the scanner finds the removed secret" $ withRepo $ \dir -> do
      git dir ["checkout", "-q", "-b", "feature"]
      writeAt dir "cfg/a.env" ("token = \"" <> fakeToken <> "\"\n")
      commitAll dir "add"
      git dir ["rm", "-q", "-r", "cfg"]
      commitAll dir "remove"
      (services, calls) <- countingServices dir
      out <- runCheck services [active secretReview] (CheckRequest Nothing (Just ("main", "HEAD")) False False)
      out ^. #exitCode `shouldBe` 10
      out ^. #output `shouldNotSatisfy` T.isInfixOf fakeToken
      calls >>= (`shouldBe` 0)

  describe "trusted policy" $ do
    it "reads the judgements recorded at a ref from Git objects, and refuses a ref with none" $ withRepo $ \dir -> do
      loadPolicyAt (gitBytes dir) "main" >>= (`shouldSatisfy` either (T.isInfixOf "First adoption") (const False))
      createDirectoryIfMissing True (dir </> ".seihou")
      runEff (runFilesystem (runManifestStore (dir </> ".seihou" </> "manifest.json") (writeManifest (emptyManifest (UTCTime (fromGregorian 2026 11 11) 0) & #judgements .~ [active secretReview]))))
      commitAll dir "adopt"
      -- The working tree then drops the judgement; the trusted ref still has it.
      removeFile (dir </> ".seihou" </> "manifest.json")
      Right js <- loadPolicyAt (gitBytes dir) "main"
      map (^. #definition . #name) js `shouldBe` ["security-review"]
      loadActiveJudgements dir >>= (`shouldBe` Right [])
    it "parses BASE..HEAD and rejects other shapes" $ do
      parseRange "origin/main..HEAD" `shouldBe` Right ("origin/main", "HEAD")
      parseRange "main...HEAD" `shouldSatisfy` isLeft
      parseRange "main" `shouldSatisfy` isLeft

  describe "the commit gate" $ do
    it "commits without consulting judgements when none is active" $ withRepo $ \dir -> do
      writeAt dir "a.txt" "a\n"
      git dir ["add", "a.txt"]
      made <- newIORef (0 :: Int)
      r <- gatedCommit dir (modifyIORef' made (+ 1) >> pure "msg") (\_ -> pure (Right ()))
      r `shouldBe` Right ()
      readIORef made >>= (`shouldBe` 1)
    it "blocks before the message is produced and leaves the staging in place" $ withRepo $ \dir -> do
      createDirectoryIfMissing True (dir </> ".seihou")
      runEff (runFilesystem (runManifestStore (dir </> ".seihou" </> "manifest.json") (writeManifest (emptyManifest (UTCTime (fromGregorian 2026 11 11) 0) & #judgements .~ [active secretReview]))))
      writeAt dir "cfg/a.env" ("token = \"" <> fakeToken <> "\"\n")
      git dir ["add", "cfg/a.env"]
      made <- newIORef (0 :: Int)
      committed <- newIORef (0 :: Int)
      r <- gatedCommit dir (modifyIORef' made (+ 1) >> pure "msg") (\_ -> modifyIORef' committed (+ 1) >> pure (Right ()))
      case r of
        Left (CommitBlocked code report) -> do
          code `shouldBe` 10
          report `shouldNotSatisfy` T.isInfixOf fakeToken
        other -> expectationFailure (show other)
      readIORef made >>= (`shouldBe` 0)
      readIORef committed >>= (`shouldBe` 0)
      staged <- readProcess "git" ["-C", dir, "diff", "--cached", "--name-only"] ""
      lines staged `shouldBe` ["cfg/a.env"]
