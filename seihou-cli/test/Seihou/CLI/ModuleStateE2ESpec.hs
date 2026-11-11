-- | End-to-end proof that a module's own directory under @.seihou/@ is an
-- ordinary managed location for both @seihou run@ and @seihou update@, and that
-- Seihou's own state and other modules' directories stay out of reach.
-- See docs/adr/0025-a-module-owns-only-its-own-directory-under-seihou.md.
module Seihou.CLI.ModuleStateE2ESpec (tests) where

import Data.ByteString qualified as BS
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.SeedRunE2ESpec (invoke, prepare, success)
import Seihou.Prelude
import System.Directory qualified as D
import System.Exit (ExitCode (..))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

-- | A @demo@ module at the given version whose one template step writes
-- @files/helper.txt@ to the given destination.
stateModule :: Text -> Text -> Text
stateModule version dest =
  "let S = ./schema/package.dhall in S.Module::{name=\"demo\", version=Some \""
    <> version
    <> "\", steps=[S.Step::{strategy=\"template\",src=\"helper.txt\",dest=\""
    <> dest
    <> "\"}]}"

-- | Rewrite the project-local @demo@ module.
writeModule :: FilePath -> Text -> Text -> Text -> IO ()
writeModule modul version dest helper = do
  TIO.writeFile (modul </> "files/helper.txt") helper
  TIO.writeFile (modul </> "module.dhall") (stateModule version dest)

tests :: IO TestTree
tests = testSpec "module state directory end-to-end" $ do
  it "runs, then merges a user edit on update, in the module's own .seihou directory" $
    withSystemTempDirectory "module-state-update" $ \root -> do
      (binary, modul) <- prepare root
      let helper = root </> ".seihou/demo/helper.txt"
      -- An unchanged line separates the two edits: diff3, like git merge,
      -- treats edits to adjacent lines as overlapping.
      writeModule modul "1.0.0" ".seihou/demo/helper.txt" "top\nunchanged\nmiddle v1\nbottom\n"
      _ <- success binary root ["run", "demo"]
      TIO.readFile helper `shouldReturn` "top\nunchanged\nmiddle v1\nbottom\n"

      TIO.writeFile helper "top edited by user\nunchanged\nmiddle v1\nbottom\n"
      writeModule modul "2.0.0" ".seihou/demo/helper.txt" "top\nunchanged\nmiddle v2\nbottom\n"
      updated <- success binary root ["update", "demo", "--json"]
      updated `shouldSatisfy` T.isInfixOf "\"outcome\":\"applied\""
      TIO.readFile helper `shouldReturn` "top edited by user\nunchanged\nmiddle v2\nbottom\n"

      repeated <- success binary root ["update", "demo", "--json"]
      repeated `shouldSatisfy` T.isInfixOf "\"alreadyUpToDate\":true"

  it "refuses a step that targets Seihou's manifest and leaves the manifest unchanged" $
    withSystemTempDirectory "module-state-manifest" $ \root -> do
      (binary, modul) <- prepare root
      writeModule modul "1.0.0" "README.md" "readme\n"
      _ <- success binary root ["run", "demo"]
      before <- BS.readFile (root </> ".seihou/manifest.json")
      writeModule modul "1.0.0" ".seihou/manifest.json" "{}\n"
      (code, out, err) <- invoke binary root ["run", "demo", "--force"]
      code `shouldNotBe` ExitSuccess
      T.pack (out <> err) `shouldSatisfy` T.isInfixOf ".seihou/manifest.json"
      BS.readFile (root </> ".seihou/manifest.json") `shouldReturn` before

  it "refuses a step that writes into another directory under .seihou, naming its own" $
    withSystemTempDirectory "module-state-other" $ \root -> do
      (binary, modul) <- prepare root
      writeModule modul "1.0.0" ".seihou/other/x" "x\n"
      (code, out, err) <- invoke binary root ["run", "demo"]
      code `shouldNotBe` ExitSuccess
      let output = T.pack (out <> err)
      output `shouldSatisfy` T.isInfixOf ".seihou/other/x is outside this module's state directory"
      output `shouldSatisfy` T.isInfixOf ".seihou/demo/"
      D.doesPathExist (root </> ".seihou/other") `shouldReturn` False

  it "reports the module state check from validate-module" $
    withSystemTempDirectory "module-state-validate" $ \root -> do
      (binary, modul) <- prepare root
      writeModule modul "1.0.0" ".seihou/other/x" "x\n"
      (code, out, err) <- invoke binary root ["validate-module", modul]
      code `shouldNotBe` ExitSuccess
      T.pack (out <> err) `shouldSatisfy` T.isInfixOf "Module state destinations"
