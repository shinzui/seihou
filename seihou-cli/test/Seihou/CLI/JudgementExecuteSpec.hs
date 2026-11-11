module Seihou.CLI.JudgementExecuteSpec (tests) where

import Control.Monad (void)
import Data.ByteString qualified as BS
import Data.Either (isLeft)
import Data.Generics.Labels ()
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Seihou.CLI.Judgement.Evidence
import Seihou.CLI.Judgement.Execute
import Seihou.CLI.Judgement.Runtime (ChunkRequest, JudgementBackend (..))
import Seihou.CLI.Judgement.Scanner (findScanner)
import Seihou.Core.Judgement
import Seihou.Prelude
import System.Directory (createDirectoryIfMissing)
import System.FilePath (takeDirectory)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (callProcess, readProcess)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

-- A synthetic token in the shape of a GitHub PAT; never a real credential.
fakeToken :: Text
fakeToken = "ghp_" <> "Z8yQ3mK7pL2nV5bX9cW4rT6uJ1hG0fD8sA3e"

git :: FilePath -> [String] -> IO ()
git dir args = callProcess "git" (["-C", dir, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "-c", "commit.gpgsign=false"] <> args)

writeAt :: FilePath -> FilePath -> Text -> IO ()
writeAt dir p body = do
  createDirectoryIfMissing True (takeDirectory (dir </> p))
  BS.writeFile (dir </> p) (TE.encodeUtf8 body)

withRepo :: (FilePath -> IO a) -> IO a
withRepo act = withSystemTempDirectory "judgement-repo" $ \dir -> do
  git dir ["init", "-q"]
  writeAt dir "README.md" "hello\n"
  git dir ["add", "README.md"]
  git dir ["commit", "-q", "-m", "init"]
  act dir

mkCheck :: Text -> JudgementCheck
mkCheck n =
  JudgementCheck n "Is the concern present?" Yes Nothing Nothing [FindingCategory "concern" High Nothing] Enforced High (Thresholds 0.5 0.1) (Thresholds 0.6 0.05) True

definition :: [DeterministicCheck] -> JudgementDefinition
definition dets =
  JudgementDefinition "demo" Nothing Nothing "Review." defaultEvidenceDeclaration defaultCoverageLimits dets (mkCheck "c" :| [])

-- | A backend that records every chunk it receives and answers with fixed
-- probabilities.
counting :: IORef [Text] -> IORef Int -> Maybe Double -> Double -> JudgementBackend
counting seen gates gateP reviewP =
  JudgementBackend
    { review = \_ _ req -> do
        modifyIORef' seen (chunkText req :)
        pure (Right (RawReview reviewP [] False)),
      gate = fmap (\p _ _ _ -> modifyIORef' gates (+ 1) >> pure (Right p)) gateP,
      observed = pure []
    }
  where
    chunkText :: ChunkRequest -> Text
    chunkText r = r ^. #evidence

execution :: Maybe JudgementBackend -> Bool -> IO JudgementExecution
execution be gateOn = do
  sc <- findScanner
  pure (JudgementExecution (defaultPolicy ApprovedRemote gateOn (definition [])) be True sc)

capture :: FilePath -> IO Snapshot
capture dir = either (fail . T.unpack) pure =<< captureStaged defaultCoverageLimits (gitBytes dir)

tests :: IO TestTree
tests = testSpec "judgement evidence and execution" $ do
  it "reads staged blobs from the index, not the working tree" $ withRepo $ \dir -> do
    writeAt dir "notes/a b.txt" "staged\n"
    git dir ["add", "notes/a b.txt"]
    writeAt dir "notes/a b.txt" "unstaged edit\n"
    snap <- capture dir
    map (^. #path) (snap ^. #files) `shouldBe` ["notes/a b.txt"]
    map (^. #content) (snap ^. #files) `shouldBe` [Just "staged\n"]
    blob <- readProcess "git" ["-C", dir, "rev-parse", ":notes/a b.txt"] ""
    map (^. #afterBlob) (snap ^. #files) `shouldBe` [Just (T.strip (T.pack blob))]
  it "records deletions and modifications with before and after identity" $ withRepo $ \dir -> do
    git dir ["rm", "-q", "README.md"]
    snap <- capture dir
    map (\f -> (f ^. #change, f ^. #content, isJustT (f ^. #beforeBlob))) (snap ^. #files) `shouldBe` [(Deleted, Nothing, True)]
  it "counts binary content as uncovered rather than dropping it" $ withRepo $ \dir -> do
    BS.writeFile (dir </> "image.bin") (BS.pack [0, 1, 2, 0, 3])
    git dir ["add", "image.bin"]
    snap <- capture dir
    map fst (snap ^. #uncovered) `shouldBe` ["image.bin"]
  it "refuses an index with unresolved entries" $ withRepo $ \dir -> do
    git dir ["checkout", "-q", "-b", "other"]
    writeAt dir "README.md" "other\n"
    git dir ["commit", "-q", "-am", "other"]
    git dir ["checkout", "-q", "-"]
    writeAt dir "README.md" "mine\n"
    git dir ["commit", "-q", "-am", "mine"]
    void (readProcess "sh" ["-c", "git -C '" <> dir <> "' -c user.name=t -c user.email=t@example.invalid merge -q other >/dev/null 2>&1 || true"] "")
    r <- captureStaged defaultCoverageLimits (gitBytes dir)
    r `shouldSatisfy` isLeft
  it "matches Git-style path patterns" $ do
    pathMatches "docs/**" "docs/a/b.md" `shouldBe` True
    pathMatches "*.md" "docs/a/b.md" `shouldBe` True
    pathMatches "src/*.hs" "src/a/b.hs" `shouldBe` False
  it "reports NoChanges for an empty staged set" $ withRepo $ \dir -> do
    snap <- capture dir
    seen <- newIORef []
    gates <- newIORef 0
    ex <- execution (Just (counting seen gates Nothing 0.0)) False
    obs <- runJudgement ex (definition []) snap
    decideJudgement (definition []) (ex ^. #policy) obs ^. #status `shouldBe` NoChanges
    readIORef seen >>= (`shouldBe` [])
  describe "with the packaged scanner" $ do
    it "blocks a credential beyond character 4,000 with no remote request" $ withRepo $ \dir -> do
      writeAt dir "config/app.env" (T.replicate 4100 "x" <> "\ntoken = \"" <> fakeToken <> "\"\n")
      git dir ["add", "config/app.env"]
      snap <- capture dir
      seen <- newIORef []
      gates <- newIORef 0
      ex <- execution (Just (counting seen gates Nothing 0.0)) False
      let def = definition [SecretScan]
      obs <- runJudgement ex def snap
      let d = decideJudgement def (ex ^. #policy) obs
      d ^. #status `shouldBe` Blocked
      map (\f -> (f ^. #location . #path, f ^. #location . #line)) (d ^. #deterministic) `shouldBe` [("config/app.env", Just 2)]
      readIORef seen >>= (`shouldBe` [])
      T.pack (show d) `shouldNotSatisfy` T.isInfixOf fakeToken
    it "stops a non-security judgement with an error and no finding when the safeguard flags material" $ withRepo $ \dir -> do
      writeAt dir "docs/guide.md" ("Use " <> fakeToken <> " to log in.\n")
      writeAt dir "docs/other.md" "Plain text.\n"
      git dir ["add", "docs"]
      snap <- capture dir
      seen <- newIORef []
      gates <- newIORef 0
      ex <- execution (Just (counting seen gates Nothing 0.0)) False
      let def = definition []
      obs <- runJudgement ex def snap
      let d = decideJudgement def (ex ^. #policy) obs
      d ^. #status `shouldBe` Failed
      d ^. #deterministic `shouldBe` []
      concatMap (^. #findings) (d ^. #checks) `shouldBe` []
      readIORef seen >>= (`shouldBe` [])
    it "sends clean evidence, and a gate clearance makes no review request" $ withRepo $ \dir -> do
      writeAt dir "src/A.hs" "module A where\n"
      git dir ["add", "src/A.hs"]
      snap <- capture dir
      seen <- newIORef []
      gates <- newIORef 0
      ex <- execution (Just (counting seen gates (Just 0.01) 0.9)) True
      obs <- runJudgement ex (definition []) snap
      decideJudgement (definition []) (ex ^. #policy) obs ^. #status `shouldBe` Passed
      readIORef gates >>= (`shouldBe` 1)
      readIORef seen >>= (`shouldBe` [])
    it "escalates past the gate pass threshold with exactly one review request" $ withRepo $ \dir -> do
      writeAt dir "src/A.hs" "module A where\n"
      git dir ["add", "src/A.hs"]
      snap <- capture dir
      seen <- newIORef []
      gates <- newIORef 0
      ex <- execution (Just (counting seen gates (Just 0.3) 0.02)) True
      obs <- runJudgement ex (definition []) snap
      decideJudgement (definition []) (ex ^. #policy) obs ^. #status `shouldBe` Passed
      sent <- readIORef seen
      length sent `shouldBe` 1
      T.concat sent `shouldSatisfy` T.isInfixOf "1 | module A where"
    it "refuses remote review under a local-only data policy" $ withRepo $ \dir -> do
      writeAt dir "src/A.hs" "module A where\n"
      git dir ["add", "src/A.hs"]
      snap <- capture dir
      seen <- newIORef []
      gates <- newIORef 0
      ex <- execution (Just (counting seen gates Nothing 0.0)) False
      let ex' = ex & #policy . #dataPolicy .~ LocalOnly
      obs <- runJudgement ex' (definition []) snap
      decideJudgement (definition []) (ex' ^. #policy) obs ^. #status `shouldBe` Failed
      readIORef seen >>= (`shouldBe` [])
  where
    isJustT = maybe False (const True)
