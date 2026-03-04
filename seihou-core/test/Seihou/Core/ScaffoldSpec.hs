module Seihou.Core.ScaffoldSpec (tests) where

import Data.Text qualified as T
import Seihou.Core.Module (validateModule)
import Seihou.Core.Scaffold (moduleDhall, readmeTemplate)
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalModuleFromFile)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.Scaffold" spec

spec :: Spec
spec = do
  describe "moduleDhall" $ do
    it "generates Dhall that loads via evalModuleFromFile" $ do
      withSystemTempDirectory "seihou-scaffold-test" $ \tmpDir -> do
        let modDir = tmpDir </> "test-mod"
            dhallFile = modDir </> "module.dhall"
            filesDir = modDir </> "files"
        createDirectoryIfMissing True filesDir
        writeFile dhallFile (T.unpack (moduleDhall "test-mod"))
        writeFile (filesDir </> "README.md.tpl") (T.unpack readmeTemplate)
        result <- evalModuleFromFile dhallFile
        case result of
          Left err -> expectationFailure $ "Failed to load generated module: " ++ show err
          Right m -> moduleName m `shouldBe` "test-mod"

    it "generates a module that passes validateModule" $ do
      withSystemTempDirectory "seihou-scaffold-test" $ \tmpDir -> do
        let modDir = tmpDir </> "test-mod"
            dhallFile = modDir </> "module.dhall"
            filesDir = modDir </> "files"
        createDirectoryIfMissing True filesDir
        writeFile dhallFile (T.unpack (moduleDhall "test-mod"))
        writeFile (filesDir </> "README.md.tpl") (T.unpack readmeTemplate)
        result <- evalModuleFromFile dhallFile
        case result of
          Left err -> expectationFailure $ "Failed to load: " ++ show err
          Right m -> do
            validated <- validateModule modDir m
            case validated of
              Left err -> expectationFailure $ "Validation failed: " ++ show err
              Right _ -> pure ()

    it "generates expected module structure" $ do
      withSystemTempDirectory "seihou-scaffold-test" $ \tmpDir -> do
        let modDir = tmpDir </> "test-mod"
            dhallFile = modDir </> "module.dhall"
            filesDir = modDir </> "files"
        createDirectoryIfMissing True filesDir
        writeFile dhallFile (T.unpack (moduleDhall "test-mod"))
        writeFile (filesDir </> "README.md.tpl") (T.unpack readmeTemplate)
        result <- evalModuleFromFile dhallFile
        case result of
          Left err -> expectationFailure $ "Failed to load: " ++ show err
          Right m -> do
            length (moduleVars m) `shouldBe` 1
            varName (head (moduleVars m)) `shouldBe` "project.name"
            length (moduleSteps m) `shouldBe` 1
            length (modulePrompts m) `shouldBe` 1
            length (moduleCommands m) `shouldBe` 0
            length (moduleExports m) `shouldBe` 0
            length (moduleDependencies m) `shouldBe` 0

  describe "readmeTemplate" $ do
    it "contains the project.name placeholder" $ do
      T.isInfixOf "{{project.name}}" readmeTemplate `shouldBe` True
