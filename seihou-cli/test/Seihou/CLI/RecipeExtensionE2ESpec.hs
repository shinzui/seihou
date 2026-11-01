module Seihou.CLI.RecipeExtensionE2ESpec (tests) where

import Control.Monad (forM_)
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.SeedRunE2ESpec (prepare)
import System.Directory qualified as D
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

invoke binary root flags = do
  inherited <- getEnvironment
  let keys = ["HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]
      environment = zip keys [root </> "home", root </> "config", root </> "cache"] <> filter (\(key, _) -> key `notElem` keys && not ("SEIHOU_VAR_" `T.isPrefixOf` T.pack key)) inherited
  (code, out, err) <- readCreateProcessWithExitCode (proc binary ("run" : "child" : flags)) {cwd = Just root, env = Just environment} ""
  pure (code, T.pack (out <> err))

fixture root = do
  (binary, member) <- prepare root
  TIO.writeFile (member </> "module.dhall") "let S = ./schema/package.dhall in S.Module::{name=\"demo\",version=Some \"1\",steps=[S.Step::{strategy=\"copy\",src=\"starter\",dest=\"value.txt\"}],commands=[S.Command::{action=S.Command.Action.Apply \"printf once >> command-marker\"}]}"
  writeRecipe root "base" "1" "[\"demo\"]" ""
  writeRecipe root "child" "1" "[] : List Text" ", extends = Some {recipe = \"base\"}"
  pure binary

writeRecipe root name version members extra = do
  let dir = root </> ".seihou/modules" </> name
  D.createDirectoryIfMissing True dir
  writeFile (dir </> "recipe.dhall") $ "{name=" <> show name <> ",version=Some " <> show version <> ",description=None Text,modules=" <> members <> ",vars=[] : List {name : Text,type : Text,default : Optional Text,description : Optional Text,required : Bool,validation : Optional Text},prompts=[] : List {var : Text,text : Text,when : Optional Text,choices : Optional (List Text)}" <> extra <> "}"

readManifest root = LBS.fromStrict <$> BS.readFile (root </> ".seihou/manifest.json")

tests :: IO TestTree
tests = testSpec "RecipeExtension" $ do
  it "records the chain and refuses base-only downgrades before files, commands or manifest writes" $
    withSystemTempDirectory "recipe-chain-guard" $ \root -> do
      binary <- fixture root
      (code, output) <- invoke binary root []
      if code == ExitSuccess then pure () else expectationFailure (T.unpack output)
      before <- readManifest root
      case Aeson.eitherDecode before :: Either String Aeson.Value of
        Right (Aeson.Object fields) -> do
          KM.lookup "version" fields `shouldBe` Just (Aeson.toJSON (13 :: Int))
          T.pack (show fields) `shouldSatisfy` T.isInfixOf "recipeChain"
          T.pack (show fields) `shouldSatisfy` T.isInfixOf "descriptorHash"
        other -> expectationFailure (show other)
      writeRecipe root "base" "0.9" "[\"demo\"]" ""
      (refused, diagnostic) <- invoke binary root []
      refused `shouldBe` ExitFailure 1
      diagnostic `shouldSatisfy` T.isInfixOf "base"
      readManifest root `shouldReturn` before
      readFile (root </> "command-marker") `shouldReturn` "once"
      (allowed, visible) <- invoke binary root ["--allow-downgrade"]
      allowed `shouldBe` ExitSuccess
      visible `shouldSatisfy` T.isInfixOf "allow-downgrade"
      readFile (root </> "command-marker") `shouldReturn` "onceonce"

  it "previews same-version descriptor changes without writing provenance" $
    withSystemTempDirectory "recipe-chain-digest" $ \root -> do
      binary <- fixture root
      (code, _) <- invoke binary root []
      code `shouldBe` ExitSuccess
      before <- readManifest root
      let descriptor = root </> ".seihou/modules/base/recipe.dhall"
      original <- TIO.readFile descriptor
      TIO.writeFile descriptor (T.replace "description=None Text" "description=Some \"New base description\"" original)
      (previewed, output) <- invoke binary root ["--dry-run"]
      previewed `shouldBe` ExitSuccess
      output `shouldSatisfy` T.isInfixOf "Recipe descriptor changed: base"
      readManifest root `shouldReturn` before
      readFile (root </> "command-marker") `shouldReturn` "once"

  it "prepares old unknown history in memory and adopts it only on an accepted run" $
    withSystemTempDirectory "recipe-chain-adoption" $ \root -> do
      binary <- fixture root
      (code, _) <- invoke binary root []
      code `shouldBe` ExitSuccess
      bytes <- readManifest root
      let Right (Aeson.Object fields) = Aeson.eitherDecode bytes
          withoutChain (Aeson.Object app) = Aeson.Object (KM.delete "recipeChain" app)
          withoutChain other = other
          Just (Aeson.Array apps) = KM.lookup "applications" fields
          legacy = Aeson.Object (KM.insert "version" (Aeson.toJSON (12 :: Int)) (KM.insert "applications" (Aeson.Array (fmap withoutChain apps)) fields))
      LBS.writeFile (root </> ".seihou/manifest.json") (Aeson.encode legacy)
      old <- readManifest root
      (previewed, output) <- invoke binary root ["--dry-run"]
      previewed `shouldBe` ExitSuccess
      output `shouldSatisfy` T.isInfixOf "prior chain is unknown"
      readManifest root `shouldReturn` old
      (accepted, _) <- invoke binary root []
      accepted `shouldBe` ExitSuccess
      adopted <- readManifest root
      adopted `shouldSatisfy` (/= old)

  it "retains generated provenance but no command receipt when a run command fails" $
    withSystemTempDirectory "recipe-chain-command-failure" $ \root -> do
      binary <- fixture root
      let descriptor = root </> ".seihou/modules/demo/module.dhall"
      source <- TIO.readFile descriptor
      TIO.writeFile descriptor (T.replace "printf once >> command-marker" "printf once >> command-marker; exit 1" source)
      (code, _) <- invoke binary root []
      code `shouldBe` ExitFailure 1
      D.doesFileExist (root </> "value.txt") `shouldReturn` True
      readFile (root </> "command-marker") `shouldReturn` "once"
      bytes <- readManifest root
      case Aeson.eitherDecode bytes :: Either String Aeson.Value of
        Right (Aeson.Object fields) -> case KM.lookup "applications" fields of
          Just (Aeson.Array apps) -> forM_ apps $ \case
            Aeson.Object app -> do
              KM.lookup "recipeChain" app `shouldSatisfy` (\value -> value /= Nothing && value /= Just Aeson.Null)
              KM.lookup "commandReceipts" app `shouldSatisfy` (\value -> value == Nothing || value == Just (Aeson.object []))
            other -> expectationFailure (show other)
          other -> expectationFailure (show other)
        other -> expectationFailure (show other)

  it "does not create a manifest directory during preview of a cache-only recipe" $
    withSystemTempDirectory "recipe-chain-no-write" $ \root -> do
      binary <- fixture root
      let cache = root </> "config/seihou/installed"
      D.createDirectoryIfMissing True cache
      forM_ ["base", "child", "demo"] $ \name -> D.renameDirectory (root </> ".seihou/modules" </> name) (cache </> name)
      D.removeDirectory (root </> ".seihou/modules")
      D.removeDirectory (root </> ".seihou")
      (code, output) <- invoke binary root ["--dry-run"]
      if code == ExitSuccess then pure () else expectationFailure (T.unpack output)
      D.doesDirectoryExist (root </> ".seihou") `shouldReturn` False
