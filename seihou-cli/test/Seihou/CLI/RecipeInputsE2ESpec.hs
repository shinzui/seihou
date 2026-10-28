module Seihou.CLI.RecipeInputsE2ESpec (tests) where

import Control.Monad (forM_)
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.SeedRunE2ESpec (invoke, prepare, readManifest, success)
import Seihou.Core.Types
import Seihou.Prelude
import System.Directory qualified as D
import System.Exit (ExitCode (..))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

prepareRecipe root = do
  (binary, modul) <- prepare root
  let other = root </> ".seihou/modules/other"
      recipe = root </> ".seihou/modules/recipe-input-probe"
      body name = "let S = ../demo/schema/package.dhall in S.Module::{name=\"" <> name <> "\",version=Some \"1.0.0\",vars=[S.VarDecl::{name=\"feature\",type=\"bool\",default=Some \"false\"}],steps=[S.Step::{strategy=\"template\",src=\"value\",dest=\"" <> name <> ".txt\"}]}"
  D.createDirectoryIfMissing True (other </> "files")
  D.createDirectoryIfMissing True recipe
  TIO.writeFile (modul </> "module.dhall") (body "demo")
  TIO.writeFile (other </> "module.dhall") (body "other")
  TIO.writeFile (modul </> "files/value") "{{feature}}"
  TIO.writeFile (other </> "files/value") "{{feature}}"
  TIO.writeFile (recipe </> "recipe.dhall") "let S = ../demo/schema/package.dhall in S.Recipe::{name=\"recipe-input-probe\",version=Some \"1.0.0\",modules=[S.Dependency::{module=\"demo\"},S.Dependency::{module=\"other\"}],vars=[S.VarDecl::{name=\"feature\",type=\"bool\",required=True}],prompts=[S.Prompt::{var=\"feature\",text=\"Enable feature?\"}]}"
  pure binary

tests :: IO TestTree
tests = testSpec "Recipe inputs" $ do
  it "refuses missing recipe decisions before writing files or manifest" $
    withSystemTempDirectory "recipe-missing" $ \root -> do
      binary <- prepareRecipe root
      (code, out, err) <- invoke binary root ["run", "recipe-input-probe"]
      code `shouldBe` ExitFailure 1
      T.pack (out <> err) `shouldSatisfy` T.isInfixOf "feature"
      D.doesPathExist (root </> "demo.txt") `shouldReturn` False
      D.doesPathExist (root </> ".seihou/manifest.json") `shouldReturn` False
  forM_ ["true", "false"] $ \choice ->
    it ("broadcasts and records " <> T.unpack choice) $
      withSystemTempDirectory "recipe-choice" $ \root -> do
        binary <- prepareRecipe root
        _ <- success binary root ["run", "recipe-input-probe", "--var", "feature=" <> T.unpack choice]
        TIO.readFile (root </> "demo.txt") `shouldReturn` choice
        TIO.readFile (root </> "other.txt") `shouldReturn` choice
        manifest <- readManifest root
        map (^. #recipeInputs) (manifest ^. #applications) `shouldBe` [Just (Map.singleton "feature" choice)]

  it "adopts an older application through ordinary preview and atomic apply" $
    withSystemTempDirectory "recipe-adoption" $ \root -> do
      binary <- prepareRecipe root
      _ <- success binary root ["run", "recipe-input-probe", "--var", "feature=false"]
      accepted <- readManifest root
      -- Construct a supported historical input, as emitted before schema 12.
      let older = accepted & #version .~ ManifestSchemaVersion 11 & #applications %~ map (\app -> app & #recipeInputs .~ Nothing)
          path = root </> ".seihou/manifest.json"
      LBS.writeFile path (Aeson.encode older)
      before <- LBS.readFile path
      _ <- success binary root ["update", "recipe-input-probe", "--dry-run", "--json"]
      LBS.readFile path `shouldReturn` before
      _ <- success binary root ["update", "recipe-input-probe", "--json"]
      adopted <- readManifest root
      map (^. #recipeInputs) (adopted ^. #applications) `shouldBe` [Just (Map.singleton "feature" "false")]
      unchanged <- success binary root ["update", "recipe-input-probe", "--json"]
      unchanged `shouldSatisfy` T.isInfixOf "\"alreadyUpToDate\":true"
  it "replays a recipe-only input after declining config saving" $
    withSystemTempDirectory "recipe-only" $ \root -> do
      binary <- prepareRecipe root
      let recipe = root </> ".seihou/modules/recipe-input-probe/recipe.dhall"
      definition <- TIO.readFile recipe
      TIO.writeFile recipe (T.replace "vars=[S.VarDecl" "vars=[S.VarDecl::{name=\"recipe.only\",type=\"bool\",required=True},S.VarDecl" definition)
      _ <- success binary root ["run", "recipe-input-probe", "--var", "feature=false", "--var", "recipe.only=true", "--no-save-prompted"]
      output <- success binary root ["update", "recipe-input-probe", "--dry-run", "--json"]
      output `shouldSatisfy` T.isInfixOf "\"alreadyUpToDate\":true"
      manifest <- readManifest root
      map (^. #recipeInputs) (manifest ^. #applications) `shouldBe` [Just (Map.fromList [("feature", "false"), ("recipe.only", "true")])]
