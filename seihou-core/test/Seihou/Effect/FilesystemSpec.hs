module Seihou.Effect.FilesystemSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Effectful
import Seihou.Effect.Filesystem
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.FilesystemPure (PureFS (..), emptyFS, runFilesystemPure)
import System.Directory (removeDirectoryRecursive)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Effect.Filesystem" spec

-- | Run an action with the pure filesystem interpreter.
runPure :: PureFS -> Eff '[Filesystem] a -> (a, PureFS)
runPure fs action = runPureEff $ runFilesystemPure fs action

-- | Run an action with the real filesystem interpreter in a temp directory.
runReal :: (FilePath -> Eff '[Filesystem, IOE] a) -> IO a
runReal action =
  withSystemTempDirectory "seihou-fs-test" $ \tmpDir ->
    runEff $ runFilesystem (action tmpDir)

spec :: Spec
spec = do
  describe "pure interpreter" $ do
    it "writes and reads a file" $ do
      let (content, _) = runPure emptyFS $ do
            writeFileText "hello.txt" "hello world"
            readFileText "hello.txt"
      content `shouldBe` "hello world"

    it "doesFileExist returns False before write" $ do
      let (exists, _) = runPure emptyFS $ doesFileExist "missing.txt"
      exists `shouldBe` False

    it "doesFileExist returns True after write" $ do
      let (exists, _) = runPure emptyFS $ do
            writeFileText "test.txt" "data"
            doesFileExist "test.txt"
      exists `shouldBe` True

    it "copyFile copies content" $ do
      let initial = PureFS (Map.singleton "src.txt" "source content") Set.empty
          (content, _) = runPure initial $ do
            copyFile "src.txt" "dest.txt"
            readFileText "dest.txt"
      content `shouldBe` "source content"

    it "createDirectoryIfMissing creates a directory" $ do
      let (exists, _) = runPure emptyFS $ do
            createDirectoryIfMissing True "my/dir"
            doesDirectoryExist "my/dir"
      exists `shouldBe` True

    it "createDirectoryIfMissing is idempotent" $ do
      let (exists, _) = runPure emptyFS $ do
            createDirectoryIfMissing True "my/dir"
            createDirectoryIfMissing True "my/dir"
            doesDirectoryExist "my/dir"
      exists `shouldBe` True

    it "overwrite replaces content" $ do
      let (content, _) = runPure emptyFS $ do
            writeFileText "file.txt" "first"
            writeFileText "file.txt" "second"
            readFileText "file.txt"
      content `shouldBe` "second"

    it "returns final filesystem state" $ do
      let (_, fs) = runPure emptyFS $ do
            writeFileText "a.txt" "aaa"
            writeFileText "b.txt" "bbb"
      Map.size fs.files `shouldBe` 2

    it "getCurrentDirectory returns /pure-fs" $ do
      let (cwd, _) = runPure emptyFS getCurrentDirectory
      cwd `shouldBe` "/pure-fs"

  describe "real interpreter" $ do
    it "writes and reads a file" $ do
      content <- runReal $ \tmpDir -> do
        let path = tmpDir </> "hello.txt"
        writeFileText path "hello world"
        readFileText path
      content `shouldBe` "hello world"

    it "doesFileExist returns True after write" $ do
      exists <- runReal $ \tmpDir -> do
        let path = tmpDir </> "test.txt"
        writeFileText path "data"
        doesFileExist path
      exists `shouldBe` True

    it "doesFileExist returns False for nonexistent file" $ do
      exists <- runReal $ \tmpDir -> do
        doesFileExist (tmpDir </> "nope.txt")
      exists `shouldBe` False

    it "createDirectoryIfMissing creates nested directories" $ do
      exists <- runReal $ \tmpDir -> do
        let dirPath = tmpDir </> "a" </> "b" </> "c"
        createDirectoryIfMissing True dirPath
        doesDirectoryExist dirPath
      exists `shouldBe` True

    it "copyFile copies content" $ do
      content <- runReal $ \tmpDir -> do
        let src = tmpDir </> "src.txt"
            dest = tmpDir </> "dest.txt"
        writeFileText src "copy me"
        copyFile src dest
        readFileText dest
      content `shouldBe` "copy me"
