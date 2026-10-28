module Seihou.CLI.CommandReceiptE2ESpec (tests) where

import Control.Monad (filterM)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Seihou.CLI.SeedRunE2ESpec (body, invoke, prepare, readManifest, success)
import Seihou.CLI.SeihouBinary (seihouBinary)
import Seihou.CLI.UpdateSpec (UpdateFixture (..), prepareUpdateFixture)
import Seihou.Core.Types
import Seihou.Manifest.Types (manifestFromJSON)
import Seihou.Prelude
import System.Directory qualified as D
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), callProcess, proc, readCreateProcessWithExitCode, readProcess)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

initCommand :: Text
initCommand = "git init -q -b master"

commitCommand :: Text
commitCommand = "git add -A && git -c user.name='Seihou Test' -c user.email=test@example.com -c commit.gpgsign=false commit -qm 'Initial commit'"

-- | Replace the demo module with a managed step and the given commands. The
-- fixture's HOME and XDG directories live inside the project, so ignore them
-- before any command snapshots the tree.
writeCommandModule :: FilePath -> FilePath -> [Text] -> IO ()
writeCommandModule root modul commands = do
  TIO.writeFile (root </> ".gitignore") "/home/\n/config/\n/cache/\n"
  TIO.writeFile (modul </> "module.dhall") (body "managed" (", commands = [" <> T.intercalate ", " (map command commands) <> "]"))
  where
    command text = "S.Command::{action = S.Command.Action.Apply \"" <> T.replace "\"" "\\\"" text <> "\"}"

demoReceipts :: Manifest -> [CommandReceipt]
demoReceipts manifest =
  concat
    [ Map.elems (application ^. #commandReceipts)
    | application <- manifest ^. #applications,
      application ^. #target == AppliedModuleTarget "demo"
    ]

-- | The manifest blob recorded at HEAD, as bytes and decoded.
committedManifest :: FilePath -> IO (BS.ByteString, Manifest)
committedManifest root = do
  blob <- readProcess "git" ["-C", root, "show", "HEAD:.seihou/manifest.json"] ""
  let bytes = TE.encodeUtf8 (T.pack blob)
  case manifestFromJSON (LBS.fromStrict bytes) of
    Left err -> fail err
    Right manifest -> pure (bytes, manifest)

-- | Turn the update fixture's project into a git repository, and publish a
-- 2.0.0 of @demo@ whose only command is @command@.
prepareCommandUpdate :: FilePath -> Text -> IO (FilePath, UpdateFixture)
prepareCommandUpdate root command = do
  fixture <- prepareUpdateFixture root
  binary <- seihouBinary
  let project = fixture ^. #projectRoot
      remote = fixture ^. #remote
  callProcess "git" ["-C", project, "init", "-q", "-b", "master"]
  callProcess "git" ["-C", project, "add", "-A"]
  callProcess "git" ["-C", project, "-c", "user.name=Seihou Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false", "commit", "-qm", "Adopt demo 1.0.0"]
  released <- TIO.readFile (remote </> "module.dhall")
  TIO.writeFile (remote </> "module.dhall") (T.replace "printf should-not-run >> command.log" command released)
  callProcess "git" ["-C", remote, "-c", "user.name=Seihou Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false", "commit", "-qam", "v2 command"]
  pure (binary, fixture)

runUpdate :: FilePath -> UpdateFixture -> [String] -> IO (ExitCode, Text)
runUpdate binary fixture args = do
  inherited <- getEnvironment
  let environment = ("XDG_CONFIG_HOME", fixture ^. #xdgHome) : filter ((/= "XDG_CONFIG_HOME") . fst) inherited
  (code, out, err) <- readCreateProcessWithExitCode (proc binary args) {cwd = Just (fixture ^. #projectRoot), env = Just environment} ""
  pure (code, T.pack (out <> err))

tests :: IO TestTree
tests = testSpec "command receipts end-to-end" $ do
  it "commits a complete manifest when a module command commits the project" $
    withSystemTempDirectory "receipt-run-commit" $ \root -> do
      (binary, modul) <- prepare root
      writeCommandModule root modul [initCommand, commitCommand]
      _ <- success binary root ["run", "demo"]
      readProcess "git" ["-C", root, "status", "--porcelain"] "" `shouldReturn` ""
      (committedBytes, committed) <- committedManifest root
      map (^. #command) (demoReceipts committed) `shouldMatchList` [initCommand, commitCommand]
      BS.readFile (root </> ".seihou/manifest.json") `shouldReturn` committedBytes
      withSystemTempDirectory "receipt-run-clone" $ \cloneParent -> do
        let clone = cloneParent </> "clone"
        callProcess "git" ["clone", "-q", root, clone]
        output <- success binary clone ["update", "demo", "--dry-run"]
        output `shouldSatisfy` T.isInfixOf "Already up to date."

  it "withdraws the published receipts when a later command fails" $
    withSystemTempDirectory "receipt-run-failure" $ \root -> do
      (binary, modul) <- prepare root
      writeCommandModule root modul [initCommand, commitCommand, "exit 7"]
      (code, out, err) <- invoke binary root ["run", "demo"]
      let output = T.pack (out <> err)
      code `shouldBe` ExitFailure 1
      output `shouldSatisfy` T.isInfixOf "Command failed (exit 7)"
      output `shouldSatisfy` T.isInfixOf "published in advance were withdrawn"
      onDisk <- readManifest root
      demoReceipts onDisk `shouldBe` []
      readProcess "git" ["-C", root, "status", "--porcelain"] "" `shouldReturn` " M .seihou/manifest.json\n"
      -- The accepted residual: the snapshot the commit took over-claims.
      (_, committed) <- committedManifest root
      length (demoReceipts committed) `shouldBe` 3

  it "keeps --no-commands and --dry-run behavior unchanged" $ do
    withSystemTempDirectory "receipt-run-disabled" $ \root -> do
      (binary, modul) <- prepare root
      writeCommandModule root modul [initCommand, commitCommand]
      _ <- success binary root ["run", "demo"]
      before <- demoReceipts <$> readManifest root
      length before `shouldBe` 2
      _ <- success binary root ["run", "demo", "--no-commands", "--force"]
      after <- demoReceipts <$> readManifest root
      after `shouldBe` before
    withSystemTempDirectory "receipt-run-dry" $ \root -> do
      (binary, modul) <- prepare root
      writeCommandModule root modul [initCommand, commitCommand]
      _ <- success binary root ["run", "demo", "--dry-run"]
      D.doesPathExist (root </> ".seihou/manifest.json") `shouldReturn` False
      D.doesPathExist (root </> ".git") `shouldReturn` False

  it "commits a complete manifest when an update's new command commits the project" $
    withSystemTempDirectory "receipt-update-commit" $ \root -> do
      let command = "git add -A && git -c user.name='Seihou Test' -c user.email=test@example.com -c commit.gpgsign=false commit -qm 'Adopt demo 2.0.0'"
      (binary, fixture) <- prepareCommandUpdate root command
      let project = fixture ^. #projectRoot
      (code, output) <- runUpdate binary fixture ["update", "demo", "--json"]
      code `shouldBe` ExitSuccess
      output `shouldSatisfy` T.isInfixOf "\"outcome\":\"applied\""
      readProcess "git" ["-C", project, "status", "--porcelain"] "" `shouldReturn` ""
      (committedBytes, committed) <- committedManifest project
      map (^. #command) (demoReceipts committed) `shouldBe` [command]
      map (^. #moduleVersion) (committed ^. #modules) `shouldBe` [Just "2.0.0"]
      BS.readFile (fixture ^. #manifestPath) `shouldReturn` committedBytes

  it "restores the pre-update manifest and files when an update's command fails" $
    withSystemTempDirectory "receipt-update-failure" $ \root -> do
      (binary, fixture) <- prepareCommandUpdate root "exit 7"
      let project = fixture ^. #projectRoot
      beforeManifest <- BS.readFile (fixture ^. #manifestPath)
      beforeReadme <- BS.readFile (fixture ^. #projectFile)
      (code, output) <- runUpdate binary fixture ["update", "demo", "--json"]
      code `shouldNotBe` ExitSuccess
      output `shouldSatisfy` T.isInfixOf "\"command_failed\""
      BS.readFile (fixture ^. #manifestPath) `shouldReturn` beforeManifest
      BS.readFile (fixture ^. #projectFile) `shouldReturn` beforeReadme
      let transactions = project </> ".seihou/transactions"
      exists <- D.doesDirectoryExist transactions
      entries <- if exists then D.listDirectory transactions else pure []
      leftovers <- filterM (D.doesDirectoryExist . (transactions </>)) entries
      leftovers `shouldBe` []
