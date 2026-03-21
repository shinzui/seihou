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

-- Test schema URL and hash — uses the local schema path for offline testing
testSchemaUrl :: T.Text
testSchemaUrl = "https://raw.githubusercontent.com/shinzui/seihou-schema/6df1496a7ce06a693d8b63bd4cf2c5d4a136670c/package.dhall"

testSchemaHash :: T.Text
testSchemaHash = "sha256:4946704e8c2dd295179003832428b82273fb0a0cff8eae9282b64ae7e18b89f4"

spec :: Spec
spec = do
  describe "moduleDhall" $ do
    it "generates Dhall that includes schema import" $ do
      let content = moduleDhall "test-mod" testSchemaUrl testSchemaHash
      T.isInfixOf "let S =" content `shouldBe` True
      T.isInfixOf "seihou-schema" content `shouldBe` True
      T.isInfixOf "S.Module::" content `shouldBe` True

    it "generates Dhall that loads via evalModuleFromFile" $ do
      withSystemTempDirectory "seihou-scaffold-test" $ \tmpDir -> do
        let modDir = tmpDir </> "test-mod"
            dhallFile = modDir </> "module.dhall"
            filesDir = modDir </> "files"
        createDirectoryIfMissing True filesDir
        writeFile dhallFile (T.unpack (moduleDhall "test-mod" testSchemaUrl testSchemaHash))
        writeFile (filesDir </> "README.md.tpl") (T.unpack readmeTemplate)
        result <- evalModuleFromFile dhallFile
        case result of
          Left err -> expectationFailure $ "Failed to load generated module: " ++ show err
          Right m -> m.name `shouldBe` "test-mod"

    it "generates a module that passes validateModule" $ do
      withSystemTempDirectory "seihou-scaffold-test" $ \tmpDir -> do
        let modDir = tmpDir </> "test-mod"
            dhallFile = modDir </> "module.dhall"
            filesDir = modDir </> "files"
        createDirectoryIfMissing True filesDir
        writeFile dhallFile (T.unpack (moduleDhall "test-mod" testSchemaUrl testSchemaHash))
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
        writeFile dhallFile (T.unpack (moduleDhall "test-mod" testSchemaUrl testSchemaHash))
        writeFile (filesDir </> "README.md.tpl") (T.unpack readmeTemplate)
        result <- evalModuleFromFile dhallFile
        case result of
          Left err -> expectationFailure $ "Failed to load: " ++ show err
          Right m -> do
            length (m.vars) `shouldBe` 1
            (head m.vars).name `shouldBe` "project.name"
            length (m.steps) `shouldBe` 1
            length (m.prompts) `shouldBe` 1
            length (m.commands) `shouldBe` 0
            length (m.exports) `shouldBe` 0
            length (m.dependencies) `shouldBe` 0

  describe "readmeTemplate" $ do
    it "contains the project.name placeholder" $ do
      T.isInfixOf "{{project.name}}" readmeTemplate `shouldBe` True
