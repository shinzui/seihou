module Seihou.CLI.CommandReceiptE2ESpec (tests) where

import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Seihou.CLI.SeedRunE2ESpec (body, invoke, prepare, readManifest, success)
import Seihou.Core.Types
import Seihou.Manifest.Types (manifestFromJSON)
import Seihou.Prelude
import System.Directory qualified as D
import System.Exit (ExitCode (..))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (callProcess, readProcess)
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
