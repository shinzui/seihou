module Seihou.Core.ScaffoldSpec (tests) where

import Data.Text qualified as T
import Seihou.Core.Module (validateModule)
import Seihou.Core.Scaffold (moduleDhall, readmeTemplate)
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalModuleFromFile)
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, makeAbsolute)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.Scaffold" spec

-- | Resolve the local schema path for tests, trying both package-relative and
-- project root-relative locations (like mori's fixturePath pattern).
-- Uses an absolute path since generated Dhall is written to a temp directory.
resolveSchemaPath :: IO T.Text
resolveSchemaPath = do
  let pkgRelative = "../schema/package.dhall"
      rootRelative = "schema/package.dhall"
  pkgExists <- doesDirectoryExist "../schema"
  path <-
    if pkgExists
      then makeAbsolute pkgRelative
      else makeAbsolute rootRelative
  pure (T.pack path)

spec :: Spec
spec = do
  describe "moduleDhall" $ do
    it "generates Dhall that includes schema import" $ do
      schemaPath <- resolveSchemaPath
      let content = moduleDhall "test-mod" schemaPath ""
      T.isInfixOf "let S =" content `shouldBe` True
      T.isInfixOf "S.Module::" content `shouldBe` True

    it "generates Dhall that loads via evalModuleFromFile" $ do
      schemaPath <- resolveSchemaPath
      withSystemTempDirectory "seihou-scaffold-test" $ \tmpDir -> do
        let modDir = tmpDir </> "test-mod"
            dhallFile = modDir </> "module.dhall"
            filesDir = modDir </> "files"
        createDirectoryIfMissing True filesDir
        writeFile dhallFile (T.unpack (moduleDhall "test-mod" schemaPath ""))
        writeFile (filesDir </> "README.md.tpl") (T.unpack readmeTemplate)
        result <- evalModuleFromFile dhallFile
        case result of
          Left err -> expectationFailure $ "Failed to load generated module: " ++ show err
          Right m -> m.name `shouldBe` "test-mod"

    it "generates a module that passes validateModule" $ do
      schemaPath <- resolveSchemaPath
      withSystemTempDirectory "seihou-scaffold-test" $ \tmpDir -> do
        let modDir = tmpDir </> "test-mod"
            dhallFile = modDir </> "module.dhall"
            filesDir = modDir </> "files"
        createDirectoryIfMissing True filesDir
        writeFile dhallFile (T.unpack (moduleDhall "test-mod" schemaPath ""))
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
      schemaPath <- resolveSchemaPath
      withSystemTempDirectory "seihou-scaffold-test" $ \tmpDir -> do
        let modDir = tmpDir </> "test-mod"
            dhallFile = modDir </> "module.dhall"
            filesDir = modDir </> "files"
        createDirectoryIfMissing True filesDir
        writeFile dhallFile (T.unpack (moduleDhall "test-mod" schemaPath ""))
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
