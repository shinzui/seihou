module Seihou.CLI.RecordedReleaseSpec
  ( tests,
    ReleaseHistory (..),
    publishHistory,
    gitHead,
  )
where

import Control.Lens ((^.))
import Control.Monad (forM_)
import Data.Generics.Labels ()
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import GHC.Generics (Generic)
import Seihou.CLI.RecordedRelease
import System.Directory (createDirectoryIfMissing, listDirectory, removePathForcibly)
import System.Environment (getEnvironment)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), proc, readCreateProcess)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.RecordedRelease" spec

-- | One commit of a published history: every file it writes, relative to
-- the repository root, and its message.
data ReleaseHistory = ReleaseHistory
  { message :: !Text,
    files :: ![(FilePath, Text)]
  }
  deriving stock (Generic)

-- | Commit each step of a history, in order, into a fresh repository.
publishHistory :: FilePath -> [ReleaseHistory] -> IO ()
publishHistory repository history = do
  removePathForcibly repository
  createDirectoryIfMissing True repository
  runGit repository ["init", "-q"]
  forM_ history $ \step -> do
    forM_ (step ^. #files) $ \(path, content) -> do
      createDirectoryIfMissing True (repository </> takeDirectoryOf path)
      TIO.writeFile (repository </> path) content
    runGit repository ["add", "-A"]
    runGit repository ["-c", "user.name=Seihou Test", "-c", "user.email=test@example.com", "commit", "-qm", T.unpack (step ^. #message)]
  where
    takeDirectoryOf path = reverse (drop 1 (dropWhile (/= '/') (reverse path)))

-- | The full id of a repository's current commit.
gitHead :: FilePath -> IO Text
gitHead repository = T.strip . T.pack <$> readGit repository ["rev-parse", "HEAD"]

runGit :: FilePath -> [String] -> IO ()
runGit repository arguments = () <$ readGit repository arguments

readGit :: FilePath -> [String] -> IO String
readGit repository arguments = do
  inherited <- getEnvironment
  readCreateProcess ((proc "git" (["-C", repository] <> arguments)) {env = Just inherited}) ""

spec :: Spec
spec = do
  describe "chooseRevision" $ do
    it "takes the first revision, newest first, that declares the version" $
      chooseRevision "1.0.0" [("c3", Just "1.1.0"), ("c2", Just "1.0.0"), ("c1", Just "1.0.0")]
        `shouldBe` Just "c2"
    it "ignores revisions without the artifact or without a version" $
      chooseRevision "1.0.0" [("c3", Nothing), ("c2", Just "1.0.0")] `shouldBe` Just "c2"
    it "returns nothing when no revision declares the version" $
      chooseRevision "0.9.0" [("c2", Just "1.1.0"), ("c1", Just "1.0.0")] `shouldBe` Nothing

  describe "planRevisionSearch" $ do
    it "walks recent history when the literal never appears" $
      planRevisionSearch "tip" [] `shouldBe` WalkRecentHistory
    it "searches each hit, each hit's parent, and the tip, once each" $
      planRevisionSearch "tip" [("c3", Just "c2"), ("c1", Nothing), ("tip", Just "c3")]
        `shouldBe` SearchRevisions ["tip", "c3", "c2", "c1"]

  describe "locateRecordedRelease" $ do
    it "returns the newest commit declaring the version, not the one that introduced it" $
      withRegistryHistory $ \session repository -> do
        secondCommit <- readGit repository ["rev-parse", "HEAD~1"]
        located <- locateRecordedRelease session (T.pack repository) "beta" "module.dhall" "1.0.0"
        case located of
          Left err -> expectationFailure (T.unpack (renderRecordedReleaseError err))
          Right release -> do
            release ^. #revision `shouldBe` T.take 7 (T.pack secondCommit)
            TIO.readFile (release ^. #directory </> "files" </> "beta.tmpl") `shouldReturn` "beta second\n"

    it "returns the tip for the version that is still current" $
      withRegistryHistory $ \session repository -> do
        tip <- gitHead repository
        located <- locateRecordedRelease session (T.pack repository) "beta" "module.dhall" "1.1.0"
        fmap (^. #revision) located `shouldBe` Right (T.take 7 tip)

    it "reports a version no commit declares, naming the origin, the name, and the version" $
      withRegistryHistory $ \session repository -> do
        located <- locateRecordedRelease session (T.pack repository) "beta" "module.dhall" "0.9.0"
        case located of
          Left err@(RecordedReleaseNotFound url name version _) -> do
            (url, name, version) `shouldBe` (T.pack repository, "beta", "0.9.0")
            renderRecordedReleaseError err `shouldSatisfy` T.isInfixOf ("no commit of " <> T.pack repository <> " declares beta 0.9.0")
          other -> expectationFailure ("expected not found, got " <> show other)

    it "reports an artifact the repository never held as not found" $
      withRegistryHistory $ \session repository -> do
        located <- locateRecordedRelease session (T.pack repository) "gamma" "module.dhall" "1.0.0"
        case located of
          Left RecordedReleaseNotFound {} -> pure ()
          other -> expectationFailure ("expected not found, got " <> show other)

    it "reports an origin that cannot be cloned as an error, not an exception" $
      withSystemTempDirectory "seihou-recorded-release" $ \root -> do
        let missing = root </> "no-such-repository"
        located <- locateRecordedRelease (root </> "session") (T.pack missing) "beta" "module.dhall" "1.0.0"
        case located of
          Left (RecordedReleaseCloneFailed url _) -> url `shouldBe` T.pack missing
          other -> expectationFailure ("expected a clone failure, got " <> show other)

    it "finds a computed version by walking the history" $
      withSystemTempDirectory "seihou-recorded-release" $ \root -> do
        let repository = root </> "computed"
        publishHistory
          repository
          [ ReleaseHistory "computed 1.0.0" [("module.dhall", betaModule "\"1.0\" ++ \".0\""), ("files/beta.tmpl", "computed\n")],
            ReleaseHistory "1.1.0" [("module.dhall", betaModule "\"1.1.0\"")]
          ]
        first <- readGit repository ["rev-parse", "HEAD~1"]
        located <- locateRecordedRelease (root </> "session") (T.pack repository) "beta" "module.dhall" "1.0.0"
        fmap (^. #revision) located `shouldBe` Right (T.take 7 (T.pack first))

    it "reuses one clone for every lookup of the same origin in a session" $
      withRegistryHistory $ \session repository -> do
        _ <- locateRecordedRelease session (T.pack repository) "beta" "module.dhall" "1.0.0"
        _ <- locateRecordedRelease session (T.pack (repository <> "/")) "beta" "module.dhall" "1.1.0"
        clones <- filter (T.isPrefixOf "clone-" . T.pack) <$> listDirectory (session </> "recorded-releases")
        length clones `shouldBe` 1

    it "answers repeated lookups that visit the same revisions in one session" $
      withRegistryHistory $ \session repository -> do
        first <- locateRecordedRelease session (T.pack repository) "beta" "module.dhall" "0.9.0"
        again <- locateRecordedRelease session (T.pack repository) "beta" "module.dhall" "0.9.0"
        found <- locateRecordedRelease session (T.pack repository) "beta" "module.dhall" "1.0.0"
        case (first, again, found) of
          (Left RecordedReleaseNotFound {}, Left RecordedReleaseNotFound {}, Right _) -> pure ()
          other -> expectationFailure ("expected not found twice, then found; got " <> show other)

-- | A registry repository holding @beta@ at @modules/beta@: 1.0.0, then a
-- template change that keeps 1.0.0, then 1.1.0.
withRegistryHistory :: (FilePath -> FilePath -> IO a) -> IO a
withRegistryHistory action =
  withSystemTempDirectory "seihou-recorded-release" $ \root -> do
    let repository = root </> "registry"
    publishHistory
      repository
      [ ReleaseHistory
          "beta 1.0.0"
          [ ("seihou-registry.dhall", registry),
            ("modules/beta/module.dhall", betaModule "\"1.0.0\""),
            ("modules/beta/files/beta.tmpl", "beta first\n")
          ],
        ReleaseHistory "beta template" [("modules/beta/files/beta.tmpl", "beta second\n")],
        ReleaseHistory "beta 1.1.0" [("modules/beta/module.dhall", betaModule "\"1.1.0\"")]
      ]
    action (root </> "session") repository
  where
    registry =
      T.unlines
        [ "{ repoName = \"Test\"",
          ", repoDescription = None Text",
          ", modules = [ { name = \"beta\", version = None Text, path = \"modules/beta\", description = None Text, tags = [] : List Text } ]",
          "}"
        ]

-- | A module named @beta@ whose version is the given Dhall expression.
betaModule :: Text -> Text
betaModule versionExpression =
  T.unlines
    [ "{ name = \"beta\"",
      ", version = Some (" <> versionExpression <> ")",
      ", description = None Text",
      ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
      ", exports = [] : List { var : Text, alias : Optional Text }",
      ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
      ", steps = [{ strategy = \"template\", src = \"beta.tmpl\", dest = \"beta.txt\", when = None Text, patch = None Text }]",
      ", commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }",
      ", dependencies = [] : List Text",
      ", removal = None { steps : List { action : Text, dest : Text, src : Optional Text }, commands : List { run : Text, workDir : Optional Text, when : Optional Text } }",
      "}"
    ]
