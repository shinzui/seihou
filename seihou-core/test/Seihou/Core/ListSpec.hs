module Seihou.Core.ListSpec (tests) where

import Data.Text qualified as T
import Seihou.Core.Module (DiscoveredModule (..), ModuleSource (..), discoverAllModules)
import Seihou.Core.Types (ModuleLoadError (..))
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.Module.discoverAllModules" spec

-- | Write a minimal valid module.dhall that the Dhall evaluator can parse.
writeMinimalModule :: FilePath -> String -> String -> IO ()
writeMinimalModule baseDir name desc = do
  let modDir = baseDir </> name
  createDirectoryIfMissing True (modDir </> "files")
  writeFile
    (modDir </> "module.dhall")
    ( "{ name = \""
        ++ name
        ++ "\", version = None Text, description = Some \""
        ++ desc
        ++ "\", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }, exports = [] : List { var : Text, as : Optional Text }, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }, steps = [] : List { strategy : Text, src : Text, dest : Text, when : Optional Text, patch : Optional Text }, commands = [] : List { run : Text, workDir : Optional Text }, dependencies = [] : List Text, removable = False }"
    )

spec :: Spec
spec = do
  describe "discoverAllModules" $ do
    it "returns empty list when no search paths have modules" $ do
      withSystemTempDirectory "seihou-list-test" $ \tmp -> do
        let paths = [tmp </> "project", tmp </> "user", tmp </> "installed"]
        result <- discoverAllModules paths
        length result `shouldBe` 0

    it "discovers modules in a search path" $ do
      withSystemTempDirectory "seihou-list-test" $ \tmp -> do
        let userDir = tmp </> "user"
        createDirectoryIfMissing True userDir
        writeMinimalModule userDir "my-mod" "A test module"
        let paths = [tmp </> "project", userDir, tmp </> "installed"]
        result <- discoverAllModules paths
        length result `shouldBe` 1
        (head result).discoveredSource `shouldBe` SourceUser

    it "tags sources correctly across paths" $ do
      withSystemTempDirectory "seihou-list-test" $ \tmp -> do
        let projectDir = tmp </> "project"
            installedDir = tmp </> "installed"
        createDirectoryIfMissing True projectDir
        createDirectoryIfMissing True installedDir
        writeMinimalModule projectDir "mod-a" "Project module"
        writeMinimalModule installedDir "mod-b" "Installed module"
        let paths = [projectDir, tmp </> "user", installedDir]
        result <- discoverAllModules paths
        length result `shouldBe` 2
        let srcs = map (.discoveredSource) result
        SourceProject `elem` srcs `shouldBe` True
        SourceInstalled `elem` srcs `shouldBe` True

    it "captures load errors for broken modules" $ do
      withSystemTempDirectory "seihou-list-test" $ \tmp -> do
        let userDir = tmp </> "user"
            brokenDir = userDir </> "broken"
        createDirectoryIfMissing True brokenDir
        writeFile (brokenDir </> "module.dhall") "this is not valid dhall"
        let paths = [tmp </> "project", userDir, tmp </> "installed"]
        result <- discoverAllModules paths
        length result `shouldBe` 1
        case (head result).discoveredResult of
          Left _ -> pure ()
          Right _ -> expectationFailure "Expected Left for broken module"

    it "skips directories without module.dhall" $ do
      withSystemTempDirectory "seihou-list-test" $ \tmp -> do
        let userDir = tmp </> "user"
            emptyDir = userDir </> "not-a-module"
        createDirectoryIfMissing True emptyDir
        writeMinimalModule userDir "real-mod" "Real module"
        let paths = [tmp </> "project", userDir, tmp </> "installed"]
        result <- discoverAllModules paths
        length result `shouldBe` 1
