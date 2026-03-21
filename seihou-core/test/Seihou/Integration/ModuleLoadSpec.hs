module Seihou.Integration.ModuleLoadSpec (tests) where

import Data.Map.Strict qualified as Map
import Effectful
-- Re-use the real loader for end-to-end tests
import Seihou.Core.Module (loadModule)
import Seihou.Core.Types
import Seihou.Effect.DhallEval (evalModuleFile)
import Seihou.Effect.DhallEvalInterp (runDhallEvalPure)
import System.Directory (getCurrentDirectory)
import System.FilePath ((</>))
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Integration.ModuleLoad" spec

fixtureDir :: IO FilePath
fixtureDir = do
  cwd <- getCurrentDirectory
  pure (cwd </> "test" </> "fixtures")

spec :: Spec
spec = do
  describe "haskell-base end-to-end" $ do
    it "loads with correct name, vars, steps, and prompt" $ do
      fixtures <- fixtureDir
      result <- loadModule [fixtures] "haskell-base"
      case result of
        Left err -> expectationFailure ("Expected Right, got: " <> show err)
        Right m -> do
          m.name `shouldBe` "haskell-base"
          m.description `shouldBe` Just "A Haskell project template"
          length (m.vars) `shouldBe` 3
          length (m.steps) `shouldBe` 5
          length (m.prompts) `shouldBe` 1
          m.dependencies `shouldBe` []

    it "has correct variable declarations" $ do
      fixtures <- fixtureDir
      result <- loadModule [fixtures] "haskell-base"
      case result of
        Left err -> expectationFailure ("Expected Right, got: " <> show err)
        Right m -> do
          let vars = m.vars
          let names = map ((.unVarName) . (.name)) vars
          names `shouldBe` ["project.name", "project.version", "license"]

          let (projectName : projectVersion : license : _) = vars
          projectName.required `shouldBe` True
          projectName.default_ `shouldBe` Nothing

          projectVersion.default_ `shouldBe` Just (VText "0.1.0.0")

          license.default_ `shouldBe` Just (VText "MIT")

    it "has a when expression on the LICENSE step" $ do
      fixtures <- fixtureDir
      result <- loadModule [fixtures] "haskell-base"
      case result of
        Left err -> expectationFailure ("Expected Right, got: " <> show err)
        Right m -> do
          let steps = m.steps
          let licenseStep = steps !! 2
          licenseStep.strategy `shouldBe` Copy
          licenseStep.condition `shouldBe` Just (ExprIsSet "license")

    it "has a dest with placeholder variable" $ do
      fixtures <- fixtureDir
      result <- loadModule [fixtures] "haskell-base"
      case result of
        Left err -> expectationFailure ("Expected Right, got: " <> show err)
        Right m -> do
          let cabalStep = m.steps !! 3
          cabalStep.dest `shouldBe` "{{project.name}}.cabal"

  describe "invalid-module" $ do
    it "produces ValidationError with multiple violations" $ do
      fixtures <- fixtureDir
      result <- loadModule [fixtures] "invalid-module"
      case result of
        Left (ValidationError _ errs) -> do
          length errs `shouldSatisfy` (>= 4)
        Left other -> expectationFailure ("Expected ValidationError, got: " <> show other)
        Right _ -> expectationFailure "Expected validation failure"

  describe "nonexistent module" $ do
    it "produces ModuleNotFound" $ do
      result <- loadModule ["/nonexistent"] "no-such-module"
      case result of
        Left (ModuleNotFound name _) ->
          name.unModuleName `shouldBe` "no-such-module"
        Left other -> expectationFailure ("Expected ModuleNotFound, got: " <> show other)
        Right _ -> expectationFailure "Expected Left"

  describe "pure DhallEval interpreter" $ do
    it "returns modules from the in-memory map" $ do
      let testModule =
            Module
              { name = "test",
                version = Nothing,
                description = Nothing,
                vars = [],
                exports = [],
                prompts = [],
                steps = [],
                commands = [],
                dependencies = [],
                removal = Nothing
              }
          modules = Map.fromList [("test/module.dhall", testModule)]
      result <- runEff $ runDhallEvalPure modules $ do
        evalModuleFile "test/module.dhall"
      case result of
        Left err -> expectationFailure ("Expected Right, got: " <> show err)
        Right m -> m.name `shouldBe` "test"
