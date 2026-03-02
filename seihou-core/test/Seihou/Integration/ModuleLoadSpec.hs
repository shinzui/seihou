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
          moduleName m `shouldBe` "haskell-base"
          moduleDescription m `shouldBe` Just "A Haskell project template"
          length (moduleVars m) `shouldBe` 3
          length (moduleSteps m) `shouldBe` 5
          length (modulePrompts m) `shouldBe` 1
          moduleDependencies m `shouldBe` []

    it "has correct variable declarations" $ do
      fixtures <- fixtureDir
      result <- loadModule [fixtures] "haskell-base"
      case result of
        Left err -> expectationFailure ("Expected Right, got: " <> show err)
        Right m -> do
          let vars = moduleVars m
          let names = map (unVarName . varName) vars
          names `shouldBe` ["project.name", "project.version", "license"]

          let (projectName : projectVersion : license : _) = vars
          varRequired projectName `shouldBe` True
          varDefault projectName `shouldBe` Nothing

          varDefault projectVersion `shouldBe` Just (VText "0.1.0.0")

          varDefault license `shouldBe` Just (VText "MIT")

    it "has a when expression on the LICENSE step" $ do
      fixtures <- fixtureDir
      result <- loadModule [fixtures] "haskell-base"
      case result of
        Left err -> expectationFailure ("Expected Right, got: " <> show err)
        Right m -> do
          let steps = moduleSteps m
          let licenseStep = steps !! 2
          stepStrategy licenseStep `shouldBe` Copy
          stepWhen licenseStep `shouldBe` Just (ExprIsSet "license")

    it "has a dest with placeholder variable" $ do
      fixtures <- fixtureDir
      result <- loadModule [fixtures] "haskell-base"
      case result of
        Left err -> expectationFailure ("Expected Right, got: " <> show err)
        Right m -> do
          let cabalStep = moduleSteps m !! 3
          stepDest cabalStep `shouldBe` "{{project.name}}.cabal"

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
          unModuleName name `shouldBe` "no-such-module"
        Left other -> expectationFailure ("Expected ModuleNotFound, got: " <> show other)
        Right _ -> expectationFailure "Expected Left"

  describe "pure DhallEval interpreter" $ do
    it "returns modules from the in-memory map" $ do
      let testModule =
            Module
              { moduleName = "test",
                moduleDescription = Nothing,
                moduleVars = [],
                moduleExports = [],
                modulePrompts = [],
                moduleSteps = [],
                moduleDependencies = []
              }
          modules = Map.fromList [("test/module.dhall", testModule)]
      result <- runEff $ runDhallEvalPure modules $ do
        evalModuleFile "test/module.dhall"
      moduleName result `shouldBe` "test"
