module Seihou.CLI.SeedUpdateE2ESpec (tests) where

import Control.Monad (forM_, when)
import Data.ByteString qualified as BS
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.SeedRunE2ESpec (body, invoke, prepare, readManifest, success)
import Seihou.Core.Types
import Seihou.Prelude
import System.Directory qualified as D
import System.Exit (ExitCode (..))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (callProcess, readProcess)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

candidate modul lifecycle = TIO.writeFile (modul </> "module.dhall") (T.replace "1.0.0" "2.0.0" (body lifecycle ""))

tests :: IO TestTree
tests = testSpec "seed update end-to-end" $ do
  it "auto-commits creations and the manifest without staging edits to released files" $
    withSystemTempDirectory "seed-update-commit" $ \root -> do
      (binary, modul) <- prepare root
      TIO.writeFile (modul </> "module.dhall") (body "managed" "")
      _ <- success binary root ["run", "demo"]
      callProcess "git" ["-C", root, "init", "-q"]
      callProcess "git" ["-C", root, "config", "user.name", "Seihou Test"]
      callProcess "git" ["-C", root, "config", "user.email", "test@example.com"]
      callProcess "git" ["-C", root, "add", "."]
      callProcess "git" ["-C", root, "commit", "-qm", "test: record managed fixture"]
      TIO.writeFile (root </> "nested/start.txt") "uncommitted project edit\n"
      TIO.writeFile (modul </> "module.dhall") (T.replace "1.0.0" "2.0.0" (T.replace ",S.Step::{strategy=\"copy\",src=\"license\",dest=\"LICENSE\"}" ",S.Step::{strategy=\"copy\",src=\"starter\",dest=\"new.txt\",lifecycle=Some \"seed\"},S.Step::{strategy=\"copy\",src=\"license\",dest=\"LICENSE\"}" (body "seed" "")))
      _ <- success binary root ["update", "demo", "--json", "--commit-message", "chore: adopt seeds"]
      committed <- lines <$> readProcess "git" ["-C", root, "show", "--pretty=", "--name-only", "HEAD"] ""
      committed `shouldContain` [".seihou/manifest.json", "new.txt"]
      committed `shouldNotContain` ["nested/start.txt"]
      TIO.readFile (root </> "nested/start.txt") `shouldReturn` "uncommitted project edit\n"

  it "releases managed edits, absence and replacement directories without touching project state" $
    forM_ ["edited", "missing", "directory"] $ \state -> withSystemTempDirectory "seed-update-release" $ \root -> do
      (binary, modul) <- prepare root
      TIO.writeFile (modul </> "module.dhall") (body "managed" "")
      _ <- success binary root ["run", "demo"]
      case state of
        "edited" -> TIO.writeFile (root </> "nested/start.txt") "project edit\n"
        "missing" -> D.removeFile (root </> "nested/start.txt")
        _ -> D.removeFile (root </> "nested/start.txt") >> D.createDirectory (root </> "nested/start.txt")
      candidate modul "seed"
      before <- BS.readFile (root </> ".seihou/manifest.json")
      preview <- success binary root ["update", "demo", "--dry-run"]
      preview `shouldSatisfy` T.isInfixOf "release to project nested/start.txt"
      BS.readFile (root </> ".seihou/manifest.json") `shouldReturn` before
      _ <- success binary root ["update", "demo", "--json"]
      applied <- readManifest root
      Map.member "nested/start.txt" (applied ^. #files) `shouldBe` False
      fmap (^. #outcome) (Map.lookup "nested/start.txt" (applied ^. #seeds)) `shouldBe` Just SeedReleasedFromManaged
      case state of
        "edited" -> TIO.readFile (root </> "nested/start.txt") `shouldReturn` "project edit\n"
        "missing" -> D.doesPathExist (root </> "nested/start.txt") `shouldReturn` False
        _ -> D.doesDirectoryExist (root </> "nested/start.txt") `shouldReturn` True
      after <- BS.readFile (root </> ".seihou/manifest.json")
      repeated <- success binary root ["update", "demo", "--json"]
      repeated `shouldSatisfy` T.isInfixOf "\"alreadyUpToDate\":true"
      BS.readFile (root </> ".seihou/manifest.json") `shouldReturn` after

  it "creates newly introduced seeds once and preserves deliberate deletion on repeat" $
    withSystemTempDirectory "seed-update-create" $ \root -> do
      (binary, modul) <- prepare root
      let empty = "let S = ./schema/package.dhall in S.Module::{name=\"demo\",version=Some \"1.0.0\"}"
      TIO.writeFile (modul </> "module.dhall") empty
      _ <- success binary root ["run", "demo"]
      candidate modul "seed"
      _ <- success binary root ["update", "demo", "--json"]
      TIO.readFile (root </> "nested/start.txt") `shouldReturn` "starter\n"
      D.removeFile (root </> "nested/start.txt")
      D.removeDirectory (root </> "nested")
      _ <- success binary root ["update", "demo", "--force", "--json"]
      D.doesPathExist (root </> "nested") `shouldReturn` False

  it "retires disappearing claims and seeds an absent path after reintroduction" $
    withSystemTempDirectory "seed-update-retire" $ \root -> do
      (binary, modul) <- prepare root
      _ <- success binary root ["run", "demo"]
      TIO.writeFile (root </> "nested/start.txt") "mine\n"
      TIO.writeFile (modul </> "module.dhall") "let S = ./schema/package.dhall in S.Module::{name=\"demo\",version=Some \"2.0.0\"}"
      _ <- success binary root ["update", "demo", "--json"]
      retired <- readManifest root
      retired ^. #seeds `shouldBe` Map.empty
      TIO.readFile (root </> "nested/start.txt") `shouldReturn` "mine\n"
      D.removeFile (root </> "nested/start.txt")
      TIO.writeFile (modul </> "module.dhall") (T.replace "1.0.0" "3.0.0" (body "seed" ""))
      _ <- success binary root ["update", "demo", "--json"]
      TIO.readFile (root </> "nested/start.txt") `shouldReturn` "starter\n"

  it "requires explicit adoption even for equal bytes, and force or JSON cannot consent" $
    forM_ [False, True] $ \missing -> withSystemTempDirectory "seed-update-adopt" $ \root -> do
      (binary, modul) <- prepare root
      _ <- success binary root ["run", "demo"]
      when missing (D.removeFile (root </> "nested/start.txt"))
      candidate modul "managed"
      before <- BS.readFile (root </> ".seihou/manifest.json")
      forM_ [["--json"], ["--force", "--json"]] $ \flags -> do
        (code, out, _) <- invoke binary root (["update", "demo"] <> flags)
        code `shouldBe` ExitFailure 1
        T.pack out `shouldSatisfy` T.isInfixOf "seed_adoption_requires_interaction"
        BS.readFile (root </> ".seihou/manifest.json") `shouldReturn` before
      D.doesFileExist (root </> "nested/start.txt") `shouldReturn` not missing

  it "rejects mixed candidate lifecycles after expanding shared managed owners" $
    withSystemTempDirectory "seed-update-shared" $ \root -> do
      (binary, modul) <- prepare root
      TIO.writeFile (modul </> "module.dhall") (body "managed" "")
      _ <- success binary root ["run", "demo"]
      let other = root </> ".seihou/modules/other"
      D.createDirectoryIfMissing True (other </> "files")
      D.copyFile (modul </> "files/starter") (other </> "files/starter")
      D.copyFile (modul </> "files/license") (other </> "files/license")
      TIO.writeFile (other </> "module.dhall") (T.replace "./schema/package.dhall" "../demo/schema/package.dhall" (T.replace "name=\"demo\"" "name=\"other\"" (body "managed" "")))
      _ <- success binary root ["run", "other", "--force"]
      candidate modul "seed"
      before <- BS.readFile (root </> ".seihou/manifest.json")
      forM_ [[], ["--include-shared-owners"]] $ \flags -> do
        (code, _, _) <- invoke binary root (["update", "demo", "--json"] <> flags)
        code `shouldBe` ExitFailure 1
        BS.readFile (root </> ".seihou/manifest.json") `shouldReturn` before
      TIO.readFile (root </> "nested/start.txt") `shouldReturn` "starter\n"
