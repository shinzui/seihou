module Seihou.CLI.SeedRunE2ESpec (tests, prepare, body, invoke, success, readManifest) where

import Control.Monad (forM_)
import Data.Aeson qualified as A
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.CheckoutSyncE2ESpec (copyPinnedSchema)
import Seihou.CLI.SeihouBinary (seihouBinary)
import Seihou.Core.Types
import Seihou.Manifest.Types (manifestFromJSON)
import Seihou.Prelude
import System.Directory qualified as D
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

invoke binary root args = do
  inherited <- getEnvironment
  let overrides = [("HOME", root </> "home"), ("XDG_CONFIG_HOME", root </> "config"), ("XDG_CACHE_HOME", root </> "cache")]
  readCreateProcessWithExitCode (proc binary args) {cwd = Just root, env = Just (overrides <> filter (\(key, _) -> key `notElem` map fst overrides) inherited)} ""

success binary root args = do
  (code, out, err) <- invoke binary root args
  unlessSuccess code (T.pack (out <> err))
  pure (T.pack (out <> err))
  where
    unlessSuccess ExitSuccess _ = pure ()
    unlessSuccess _ output = expectationFailure (unwords args <> ": " <> T.unpack output)

body lifecycle extra = "let S = ./schema/package.dhall in S.Module::{name=\"demo\", version=Some \"1.0.0\", steps=[S.Step::{strategy=\"copy\",src=\"starter\",dest=\"nested/start.txt\",lifecycle=Some \"" <> lifecycle <> "\"},S.Step::{strategy=\"copy\",src=\"license\",dest=\"LICENSE\"}] " <> extra <> "}"

prepare root = do
  binary <- seihouBinary
  cwd <- D.getCurrentDirectory
  schema <- D.canonicalizePath (takeDirectory cwd </> "schema")
  let modul = root </> ".seihou/modules/demo"
  D.createDirectoryIfMissing True (modul </> "schema")
  D.createDirectoryIfMissing True (modul </> "files")
  copyPinnedSchema schema (modul </> "schema")
  TIO.writeFile (modul </> "files/starter") "starter\n"
  TIO.writeFile (modul </> "files/license") "license\n"
  TIO.writeFile (modul </> "module.dhall") (body "seed" "")
  pure (binary, modul)

readManifest root = do
  bytes <- LBS.readFile (root </> ".seihou/manifest.json")
  case manifestFromJSON bytes of Left err -> fail err; Right manifest -> pure manifest

tests :: IO TestTree
tests = testSpec "seed run end-to-end" $ do
  it "creates once, preserves forced edits and deliberate deletion without parent resurrection" $
    withSystemTempDirectory "seed-run" $ \root -> do
      (binary, _) <- prepare root
      first <- success binary root ["run", "demo"]
      first `shouldSatisfy` T.isInfixOf "create once nested/start.txt"
      manifest <- readManifest root
      Map.member "nested/start.txt" (manifest ^. #seeds) `shouldBe` True
      Map.member "nested/start.txt" (manifest ^. #files) `shouldBe` False
      TIO.writeFile (root </> "nested/start.txt") "project changes\n"
      _ <- success binary root ["run", "demo", "--force"]
      TIO.readFile (root </> "nested/start.txt") `shouldReturn` "project changes\n"
      D.removeFile (root </> "nested/start.txt")
      D.removeDirectory (root </> "nested")
      deleted <- success binary root ["run", "demo", "--force"]
      deleted `shouldSatisfy` T.isInfixOf "keep deleted nested/start.txt"
      D.doesPathExist (root </> "nested") `shouldReturn` False
  it "keeps a pre-existing regular file without force and makes previews immutable" $
    withSystemTempDirectory "seed-existing" $ \root -> do
      (binary, _) <- prepare root
      D.createDirectory (root </> "nested")
      TIO.writeFile (root </> "nested/start.txt") "already mine\n"
      _ <- success binary root ["run", "demo", "--dry-run"]
      D.doesPathExist (root </> ".seihou/manifest.json") `shouldReturn` False
      D.doesPathExist (root </> "LICENSE") `shouldReturn` False
      _ <- success binary root ["run", "demo"]
      TIO.readFile (root </> "nested/start.txt") `shouldReturn` "already mine\n"
      manifest <- readManifest root
      fmap (^. #outcome) (Map.lookup "nested/start.txt" (manifest ^. #seeds)) `shouldBe` Just SeedFoundExisting
      before <- BS.readFile (root </> ".seihou/manifest.json")
      _ <- success binary root ["run", "demo", "--diff"]
      BS.readFile (root </> ".seihou/manifest.json") `shouldReturn` before
  it "refuses both lifecycle transitions before bytes or applied metadata advance" $
    withSystemTempDirectory "seed-transition" $ \root -> do
      (binary, modul) <- prepare root
      TIO.writeFile (modul </> "module.dhall") (body "managed" "")
      _ <- success binary root ["run", "demo", "--force"]
      before <- BS.readFile (root </> ".seihou/manifest.json")
      TIO.writeFile (modul </> "module.dhall") (body "seed" "")
      (code, _, err) <- invoke binary root ["run", "demo", "--force"]
      code `shouldBe` ExitFailure 1
      BS.readFile (root </> ".seihou/manifest.json") `shouldReturn` before
      -- Start the reverse direction in another project so no fixture edits
      -- silently perform the transition the public command must refuse.
      withSystemTempDirectory "seed-reverse" $ \other -> do
        (otherBinary, otherModule) <- prepare other
        _ <- success otherBinary other ["run", "demo"]
        old <- BS.readFile (other </> ".seihou/manifest.json")
        TIO.writeFile (other </> "nested/start.txt") "mine\n"
        TIO.writeFile (otherModule </> "module.dhall") (body "managed" "")
        (refused, _, _) <- invoke otherBinary other ["run", "demo", "--force"]
        refused `shouldBe` ExitFailure 1
        BS.readFile (other </> ".seihou/manifest.json") `shouldReturn` old
        TIO.readFile (other </> "nested/start.txt") `shouldReturn` "mine\n"
  it "refuses directories and dangling links without writing managed siblings" $
    forM_ [False, True] $ \linked -> withSystemTempDirectory "seed-occupied" $ \root -> do
      (binary, _) <- prepare root
      D.createDirectory (root </> "nested")
      if linked then D.createFileLink "missing" (root </> "nested/start.txt") else D.createDirectory (root </> "nested/start.txt")
      (code, _, _) <- invoke binary root ["run", "demo", "--force"]
      code `shouldBe` ExitFailure 1
      D.doesPathExist (root </> "LICENSE") `shouldReturn` False
      D.doesPathExist (root </> ".seihou/manifest.json") `shouldReturn` False

  it "records co-seeders in one application and adds another application without changing the supplier" $
    withSystemTempDirectory "seed-coowners" $ \root -> do
      (binary, modul) <- prepare root
      let child = root </> ".seihou/modules/child"
      D.createDirectoryIfMissing True (child </> "files")
      TIO.writeFile (child </> "files/starter") "child supplies first\n"
      TIO.writeFile (child </> "module.dhall") "let S = ../demo/schema/package.dhall in S.Module::{name=\"child\", version=Some \"1.0.0\", vars=[S.VarDecl::{name=\"slot\",type=\"text\",default=Some \"base\"}], steps=[S.Step::{strategy=\"copy\",src=\"starter\",dest=\"nested/start.txt\",lifecycle=Some \"seed\"}]}"
      TIO.writeFile (modul </> "module.dhall") (body "seed" ", dependencies=[S.Dependency::{module=\"child\",vars=[{name=\"slot\",value=\"one\"}]},S.Dependency::{module=\"child\",vars=[{name=\"slot\",value=\"two\"}]}]")
      _ <- success binary root ["run", "demo"]
      first <- readManifest root
      let Just firstReceipt = Map.lookup "nested/start.txt" (first ^. #seeds)
      case firstReceipt ^. #ownership of
        KnownSeedOwners owners -> owners `shouldSatisfy` ((== [3]) . map length . Map.elems)
        _ -> expectationFailure "expected exact owners"
      firstReceipt ^. #moduleName . #unModuleName `shouldSatisfy` T.isPrefixOf "child#"
      TIO.readFile (root </> "nested/start.txt") `shouldReturn` "child supplies first\n"
      let other = root </> ".seihou/modules/other"
      D.createDirectoryIfMissing True (other </> "files")
      D.copyFile (modul </> "files/starter") (other </> "files/starter")
      D.copyFile (modul </> "files/license") (other </> "files/license")
      TIO.writeFile (other </> "module.dhall") (T.replace "./schema/package.dhall" "../demo/schema/package.dhall" (T.replace "name=\"demo\"" "name=\"other\"" (body "seed" "")))
      TIO.writeFile (root </> "nested/start.txt") "project bytes\n"
      _ <- success binary root ["run", "other", "--force"]
      shared <- readManifest root
      let Just sharedReceipt = Map.lookup "nested/start.txt" (shared ^. #seeds)
      sharedReceipt ^. #moduleName `shouldBe` firstReceipt ^. #moduleName
      sharedReceipt ^. #settledAt `shouldBe` firstReceipt ^. #settledAt
      case sharedReceipt ^. #ownership of
        KnownSeedOwners owners -> Map.size owners `shouldBe` 2
        _ -> expectationFailure "expected exact owners"
      TIO.readFile (root </> "nested/start.txt") `shouldReturn` "project bytes\n"
  it "retires false-condition claims and permits seeding after final receipt retirement" $
    withSystemTempDirectory "seed-condition" $ \root -> do
      (binary, modul) <- prepare root
      let conditional = T.replace "lifecycle=Some \"seed\"" "lifecycle=Some \"seed\",when=Some \"Eq enabled true\"" (body "seed" ",vars=[S.VarDecl::{name=\"enabled\",type=\"bool\",default=Some \"true\"}]")
      TIO.writeFile (modul </> "module.dhall") conditional
      _ <- success binary root ["run", "demo"]
      TIO.writeFile (root </> "nested/start.txt") "mine\n"
      _ <- success binary root ["run", "demo", "--var", "enabled=false"]
      retired <- readManifest root
      retired ^. #seeds `shouldBe` Map.empty
      TIO.readFile (root </> "nested/start.txt") `shouldReturn` "mine\n"
      D.removeFile (root </> "nested/start.txt")
      _ <- success binary root ["run", "demo", "--var", "enabled=true"]
      TIO.readFile (root </> "nested/start.txt") `shouldReturn` "starter\n"
  it "uses the same seed handling for an agent blueprint baseline" $
    withSystemTempDirectory "seed-agent" $ \root -> do
      (binary, _) <- prepare root
      let blueprint = root </> ".seihou/modules/seed-blueprint"
      D.createDirectoryIfMissing True blueprint
      TIO.writeFile (blueprint </> "blueprint.dhall") "let S = ../demo/schema/package.dhall in S.Blueprint::{name=\"seed-blueprint\",version=Some \"1.0.0\",prompt=\"Describe the accepted baseline.\", baseModules = [ S.Dependency::{ module = \"demo\" } ]}"
      _ <- success binary root ["agent", "--debug", "run", "seed-blueprint", "--force"]
      first <- readManifest root
      Map.member "nested/start.txt" (first ^. #seeds) `shouldBe` True
      TIO.writeFile (root </> "nested/start.txt") "agent project changes\n"
      _ <- success binary root ["agent", "--debug", "run", "seed-blueprint", "--force"]
      TIO.readFile (root </> "nested/start.txt") `shouldReturn` "agent project changes\n"
      D.removeFile (root </> "nested/start.txt")
      _ <- success binary root ["agent", "--debug", "run", "seed-blueprint", "--force"]
      D.doesPathExist (root </> "nested/start.txt") `shouldReturn` False
  it "reports receipts without drift and retires a seed-only owner without a removal specification" $
    withSystemTempDirectory "seed-remove" $ \root -> do
      (binary, modul) <- prepare root
      let seedOnly = T.replace ",S.Step::{strategy=\"copy\",src=\"license\",dest=\"LICENSE\"}" "" (body "seed" "")
      TIO.writeFile (modul </> "module.dhall") seedOnly
      _ <- success binary root ["run", "demo"]
      TIO.writeFile (root </> "nested/start.txt") "mine\n"
      status <- success binary root ["status"]
      status `shouldSatisfy` T.isInfixOf "Seed files: 1"
      diff <- success binary root ["diff"]
      diff `shouldSatisfy` T.isInfixOf "1 seed files not compared"
      diff `shouldSatisfy` (not . T.isInfixOf "nested/start.txt")
      before <- BS.readFile (root </> ".seihou/manifest.json")
      preview <- success binary root ["remove", "demo", "--dry-run"]
      preview `shouldSatisfy` T.isInfixOf "Keep nested/start.txt"
      BS.readFile (root </> ".seihou/manifest.json") `shouldReturn` before
      removed <- success binary root ["remove", "demo", "--force"]
      removed `shouldSatisfy` T.isInfixOf "Retired 1 seed claims"
      TIO.readFile (root </> "nested/start.txt") `shouldReturn` "mine\n"
      retired <- readManifest root
      retired ^. #seeds `shouldBe` Map.empty
      D.removeFile (root </> "nested/start.txt")
      _ <- success binary root ["run", "demo"]
      TIO.readFile (root </> "nested/start.txt") `shouldReturn` "starter\n"
