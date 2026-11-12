module Seihou.CLI.RebindingUpdateE2ESpec (tests) where

import Data.Aeson qualified as A
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding (encodeUtf8)
import Data.Text.IO qualified as TIO
import Data.Vector qualified as V
import Seihou.CLI.SeedRunE2ESpec (invoke, prepare, readManifest, success)
import Seihou.Core.Types
import Seihou.Prelude
import System.Directory qualified as D
import System.Exit (ExitCode (..))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

parent version bindings = "let S = ./schema/package.dhall in S.Module::{name=\"demo\",version=Some \"" <> version <> "\",dependencies=[S.Dependency::{module=\"child\"" <> bindings <> "}]}"

tests :: IO TestTree
tests = testSpec "rebinding update end-to-end" $ do
  it "keeps saved inputs through added, changed and removed bindings" $
    withSystemTempDirectory "rebinding-update" $ \root -> do
      (binary, modul, child) <- prepareProject root
      TIO.writeFile (modul </> "module.dhall") (parent "1.0.0" "")
      _ <- success binary root ["run", "demo", "--var", "project.name=demo", "--var", "child.opt=custom"]
      before <- BS.readFile (root </> ".seihou/manifest.json")
      let release version value = TIO.writeFile (modul </> "module.dhall") (parent version (",vars=[{name=\"child.extra\",value=\"" <> value <> "\"}]"))
      release "1.1.0" "x"
      preview <- success binary root ["update", "demo", "--dry-run"]
      preview `shouldSatisfy` T.isInfixOf "Rebinding:   child (no bindings) -> [child.extra=x]; saved inputs kept"
      preview `shouldNotSatisfy` T.isInfixOf "Removal policies changed:"
      planned <- success binary root ["update", "demo", "--json", "--dry-run"]
      case jsonField planned "rebindings" of
        A.Array entries -> [(field entry "module", field entry "from", field entry "to") | entry <- V.toList entries] `shouldBe` [(A.String "child", A.object [], A.object ["child.extra" A..= ("x" :: T.Text)])]
        _ -> expectationFailure "missing rebindings"
      BS.readFile (root </> ".seihou/manifest.json") `shouldReturn` before
      output <- success binary root ["update", "demo", "--json"]
      jsonField output "rebindings" `shouldBe` jsonField planned "rebindings"
      field (jsonField planned "inputs") "reused" `shouldBe` A.Number 2
      case jsonField output "versions" of
        A.Array versions -> filter (\value -> field value "name" == A.String "child") (V.toList versions) `shouldBe` []
        _ -> expectationFailure "missing versions"
      manifest <- readManifest root
      let children = [state | app <- manifest ^. #applications, state <- app ^. #instances, state ^. #name == "child"]
      map (^. #resolvedVars) children `shouldSatisfy` all ((== Just "custom") . Map.lookup "child.opt")
      TIO.readFile (root </> "values.txt") `shouldReturn` "name=demo opt=custom extra=x"
      release "1.2.0" "y"
      _ <- success binary root ["update", "demo", "--json"]
      TIO.readFile (root </> "values.txt") `shouldReturn` "name=demo opt=custom extra=y"
      TIO.writeFile (modul </> "module.dhall") (parent "1.3.0" "")
      _ <- success binary root ["update", "demo", "--json"]
      TIO.readFile (root </> "values.txt") `shouldReturn` "name=demo opt=custom extra=none"
      childDefinition <- TIO.readFile (child </> "module.dhall")
      TIO.writeFile (child </> "module.dhall") (T.replace "1.0.0" "1.1.0" childDefinition)
      release "1.4.0" "z"
      changed <- success binary root ["update", "demo", "--json", "--var", "child.opt=other"]
      case jsonField changed "versions" of
        A.Array versions -> [(field value "from", field value "to") | value <- V.toList versions, field value "name" == A.String "child"] `shouldBe` [(A.String "1.0.0", A.String "1.1.0")]
        _ -> expectationFailure "missing versions"
      TIO.readFile (root </> "values.txt") `shouldReturn` "name=demo opt=other extra=z"
      settled <- BS.readFile (root </> ".seihou/manifest.json")
      _ <- success binary root ["update", "demo", "--json"]
      BS.readFile (root </> ".seihou/manifest.json") `shouldReturn` settled

  it "names a changed edge when reconfiguration loses a required answer" $
    withSystemTempDirectory "rebinding-variable-error" $ \root -> do
      (binary, modul, _) <- prepareProject root
      TIO.writeFile (modul </> "module.dhall") (parent "1.0.0" "")
      _ <- success binary root ["run", "demo", "--var", "project.name=demo"]
      TIO.writeFile (modul </> "module.dhall") (parent "1.1.0" ",vars=[{name=\"child.extra\",value=\"x\"}]")
      before <- BS.readFile (root </> ".seihou/manifest.json")
      (code, out, _) <- invoke binary root ["update", "demo", "--json", "--reconfigure"]
      code `shouldBe` ExitFailure 1
      T.pack out `shouldSatisfy` T.isInfixOf "variable_errors"
      T.pack out `shouldSatisfy` T.isInfixOf "[child.extra=x]"
      BS.readFile (root </> ".seihou/manifest.json") `shouldReturn` before

  it "preserves exact multiple invocations and refuses ambiguity without writing" $
    withSystemTempDirectory "rebinding-ambiguous" $ \root -> do
      (binary, modul, child) <- prepareProject root
      definition <- TIO.readFile (child </> "module.dhall")
      TIO.writeFile (child </> "module.dhall") (T.replace "dest=\"values.txt\"" "dest=\"{{child.extra}}.txt\"" definition)
      let multiple version extra = "let S = ./schema/package.dhall in S.Module::{name=\"demo\",version=Some \"" <> version <> "\",dependencies=[S.Dependency::{module=\"child\",vars=[{name=\"child.extra\",value=\"a\"}" <> extra <> "]},S.Dependency::{module=\"child\",vars=[{name=\"child.extra\",value=\"b\"}" <> extra <> "]}]}"
      TIO.writeFile (modul </> "module.dhall") (multiple "1.0.0" "")
      _ <- success binary root ["run", "demo", "--var", "project.name=demo", "--var", "child.opt=custom"]
      TIO.writeFile (modul </> "module.dhall") (multiple "1.1.0" "")
      _ <- success binary root ["update", "demo", "--json"]
      TIO.readFile (root </> "a.txt") `shouldReturn` "name=demo opt=custom extra=a"
      TIO.readFile (root </> "b.txt") `shouldReturn` "name=demo opt=custom extra=b"
      before <- BS.readFile (root </> ".seihou/manifest.json")
      TIO.writeFile (modul </> "module.dhall") (multiple "1.2.0" ",{name=\"child.opt\",value=\"bound\"}")
      (code, out, _) <- invoke binary root ["update", "demo", "--json"]
      code `shouldBe` ExitFailure 1
      T.pack out `shouldSatisfy` T.isInfixOf "ambiguous_instance_rebinding"
      mapM_ (\text -> T.pack out `shouldSatisfy` T.isInfixOf text) ["[child.extra=a]", "[child.extra=b]", "[child.extra=a, child.opt=bound]", "[child.extra=b, child.opt=bound]"]
      BS.readFile (root </> ".seihou/manifest.json") `shouldReturn` before
      TIO.readFile (root </> "a.txt") `shouldReturn` "name=demo opt=custom extra=a"
      TIO.readFile (root </> "b.txt") `shouldReturn` "name=demo opt=custom extra=b"
      preview <- success binary root ["update", "demo", "--dry-run", "--reconfigure", "--var", "project.name=demo"]
      preview `shouldSatisfy` T.isInfixOf "could not be paired"
      _ <- success binary root ["update", "demo", "--json", "--reconfigure", "--var", "project.name=demo"]
      TIO.readFile (root </> "a.txt") `shouldReturn` "name=demo opt=bound extra=a"

field (A.Object fields) key = maybe A.Null id (KM.lookup key fields)
field _ _ = A.Null

jsonField text key = case A.decodeStrict (encodeUtf8 text) of
  Just value -> field value key
  Nothing -> A.Null

prepareProject root = do
  (binary, modul) <- prepare root
  let child = root </> ".seihou/modules/child"
  D.createDirectoryIfMissing True (child </> "files")
  TIO.writeFile (child </> "module.dhall") "let S = ../demo/schema/package.dhall in S.Module::{name=\"child\",version=Some \"1.0.0\",vars=[S.VarDecl::{name=\"project.name\",type=\"text\",required=True},S.VarDecl::{name=\"child.opt\",type=\"text\",default=Some \"default\"},S.VarDecl::{name=\"child.extra\",type=\"text\",default=Some \"none\"}],steps=[S.Step::{strategy=\"template\",src=\"values\",dest=\"values.txt\"}]}"
  TIO.writeFile (child </> "files/values") "name={{project.name}} opt={{child.opt}} extra={{child.extra}}"
  pure (binary, modul, child)
