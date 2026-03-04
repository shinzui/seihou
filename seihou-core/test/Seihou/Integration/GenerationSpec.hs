module Seihou.Integration.GenerationSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Seihou.Core.Module (loadModule)
import Seihou.Core.Types
import Seihou.Core.Variable (resolveVariables)
import Seihou.Engine.Plan (compilePlan)
import System.Directory (getCurrentDirectory)
import System.FilePath ((</>))
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Integration.Generation" spec

fixtureDir :: IO FilePath
fixtureDir = do
  cwd <- getCurrentDirectory
  pure (cwd </> "test" </> "fixtures")

-- | Helper to extract the resolved variable values map.
resolvedValues :: Map.Map VarName ResolvedVar -> Map.Map VarName VarValue
resolvedValues = Map.map resolvedValue

spec :: Spec
spec = do
  describe "full pipeline: load, resolve, compile" $ do
    it "produces correct README.md content" $ do
      fixtures <- fixtureDir
      result <- loadModule [fixtures] "haskell-base"
      case result of
        Left err -> expectationFailure ("Failed to load module: " <> show err)
        Right modul -> do
          let cli = Map.fromList [("project.name", "my-app")]
              env = Map.empty
          case resolveVariables (moduleVars modul) cli env "" Map.empty Map.empty Map.empty of
            Left errs -> expectationFailure ("Failed to resolve: " <> show errs)
            Right resolved -> do
              planResult <- compilePlan (fixtures </> "haskell-base") modul (resolvedValues resolved)
              case planResult of
                Left errs -> expectationFailure ("Plan failed: " <> show errs)
                Right ops -> do
                  let readmeOps = [op | op@(WriteFileOp d _ _) <- ops, d == "README.md"]
                  length readmeOps `shouldBe` 1
                  let (WriteFileOp _ content _) = readmeOps !! 0
                  content `shouldBe` "# my-app\n\nVersion: 0.1.0.0\n"

    it "produces correct cabal file with expanded destination" $ do
      fixtures <- fixtureDir
      result <- loadModule [fixtures] "haskell-base"
      case result of
        Left err -> expectationFailure ("Failed to load module: " <> show err)
        Right modul -> do
          let cli = Map.fromList [("project.name", "my-app")]
              env = Map.empty
          case resolveVariables (moduleVars modul) cli env "" Map.empty Map.empty Map.empty of
            Left errs -> expectationFailure ("Failed to resolve: " <> show errs)
            Right resolved -> do
              planResult <- compilePlan (fixtures </> "haskell-base") modul (resolvedValues resolved)
              case planResult of
                Left errs -> expectationFailure ("Plan failed: " <> show errs)
                Right ops -> do
                  let cabalOps = [op | op@(WriteFileOp d _ _) <- ops, d == "my-app.cabal"]
                  length cabalOps `shouldBe` 1
                  let (WriteFileOp _ content _) = cabalOps !! 0
                  T.isInfixOf "name: my-app" content `shouldBe` True
                  T.isInfixOf "version: 0.1.0.0" content `shouldBe` True
                  T.isInfixOf "license: MIT" content `shouldBe` True

    it "includes LICENSE step when license is set" $ do
      fixtures <- fixtureDir
      result <- loadModule [fixtures] "haskell-base"
      case result of
        Left err -> expectationFailure ("Failed to load module: " <> show err)
        Right modul -> do
          let cli = Map.fromList [("project.name", "my-app")]
              env = Map.empty
          case resolveVariables (moduleVars modul) cli env "" Map.empty Map.empty Map.empty of
            Left errs -> expectationFailure ("Failed to resolve: " <> show errs)
            Right resolved -> do
              planResult <- compilePlan (fixtures </> "haskell-base") modul (resolvedValues resolved)
              case planResult of
                Left errs -> expectationFailure ("Plan failed: " <> show errs)
                Right ops -> do
                  let licenseOps = [op | op@(WriteFileOp d _ _) <- ops, d == "LICENSE"]
                  length licenseOps `shouldBe` 1

    it "excludes LICENSE step when license is not set" $ do
      fixtures <- fixtureDir
      result <- loadModule [fixtures] "haskell-base"
      case result of
        Left err -> expectationFailure ("Failed to load module: " <> show err)
        Right modul -> do
          -- Provide all vars but use an empty var map for IsSet evaluation.
          -- The real scenario: license has a default so it's always set.
          -- To test the conditional, we use a stripped-down module with only the LICENSE step.
          let licenseStep = Step Copy "LICENSE" "LICENSE" (Just (ExprIsSet "license")) Nothing
              smallModule = modul {moduleSteps = [licenseStep]}
              vars = Map.empty -- no license variable set
          planResult <- compilePlan (fixtures </> "haskell-base") smallModule vars
          case planResult of
            Left errs -> expectationFailure ("Plan failed: " <> show errs)
            Right ops -> do
              let licenseOps = [op | op@(WriteFileOp d _ _) <- ops, d == "LICENSE"]
              length licenseOps `shouldBe` 0

    it "produces DhallText output for cabal.project" $ do
      fixtures <- fixtureDir
      result <- loadModule [fixtures] "haskell-base"
      case result of
        Left err -> expectationFailure ("Failed to load module: " <> show err)
        Right modul -> do
          let cli = Map.fromList [("project.name", "my-app")]
              env = Map.empty
          case resolveVariables (moduleVars modul) cli env "" Map.empty Map.empty Map.empty of
            Left errs -> expectationFailure ("Failed to resolve: " <> show errs)
            Right resolved -> do
              planResult <- compilePlan (fixtures </> "haskell-base") modul (resolvedValues resolved)
              case planResult of
                Left errs -> expectationFailure ("Plan failed: " <> show errs)
                Right ops -> do
                  let projectOps = [op | op@(WriteFileOp d _ _) <- ops, d == "cabal.project"]
                  length projectOps `shouldBe` 1
                  let (WriteFileOp _ content _) = projectOps !! 0
                  T.isInfixOf "my-app" content `shouldBe` True

    it "resolves variables from env and applies precedence" $ do
      fixtures <- fixtureDir
      result <- loadModule [fixtures] "haskell-base"
      case result of
        Left err -> expectationFailure ("Failed to load module: " <> show err)
        Right modul -> do
          -- CLI overrides project.name, env overrides license
          let cli = Map.fromList [("project.name", "cli-app")]
              env = Map.fromList [("SEIHOU_VAR_LICENSE", "BSD3")]
          case resolveVariables (moduleVars modul) cli env "" Map.empty Map.empty Map.empty of
            Left errs -> expectationFailure ("Failed to resolve: " <> show errs)
            Right resolved -> do
              resolvedValue (resolved Map.! "project.name") `shouldBe` VText "cli-app"
              resolvedSource (resolved Map.! "project.name") `shouldBe` FromCLI
              resolvedValue (resolved Map.! "license") `shouldBe` VText "BSD3"
              resolvedSource (resolved Map.! "license") `shouldBe` FromEnv "SEIHOU_VAR_LICENSE"
              resolvedValue (resolved Map.! "project.version") `shouldBe` VText "0.1.0.0"
              resolvedSource (resolved Map.! "project.version") `shouldBe` FromDefault
