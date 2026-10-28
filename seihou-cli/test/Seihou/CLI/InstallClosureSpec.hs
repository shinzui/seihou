module Seihou.CLI.InstallClosureSpec (tests) where

import Data.Either (isLeft)
import Seihou.CLI.InstallClosure (installClosureInto)
import Seihou.CLI.InstallShared (installModuleDirInto)
import System.Directory
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.InstallClosure" $ do
  it "refuses an escaping selected path without creating a cache" $
    withSystemTempDirectory "closure" $ \tmp -> do
      let repo = tmp </> "repo"
          cache = tmp </> "cache"
      createDirectory repo
      result <- installClosureInto cache False repo "https://example.com/registry" [("escape", tmp)]
      result `shouldSatisfy` isLeft
      doesDirectoryExist cache `shouldReturn` False

  it "preflights all roots before replacing any existing artifact" $
    withSystemTempDirectory "closure" $ \tmp -> do
      let repo = tmp </> "repo"
          cache = tmp </> "cache"
      moduleDir repo "good"
      _ <- installModuleDirInto cache False (repo </> "good") "good" "https://example.com/registry" Nothing Nothing []
      writeFile (cache </> "good" </> "marker") "original"
      createDirectory (repo </> "bad")
      writeFile (repo </> "bad" </> "recipe.dhall") "this is not Dhall"
      result <- installClosureInto cache False repo "https://example.com/registry" [("good", repo </> "good"), ("bad", repo </> "bad")]
      result `shouldSatisfy` isLeft
      readFile (cache </> "good" </> "marker") `shouldReturn` "original"
      doesDirectoryExist (cache </> "bad") `shouldReturn` False

  it "restores an earlier replacement when a later destination cannot be written" $
    withSystemTempDirectory "closure" $ \tmp -> do
      let repo = tmp </> "repo"
          cache = tmp </> "cache"
      moduleDir repo "good"
      moduleDir repo "blocked"
      _ <- installModuleDirInto cache False (repo </> "good") "good" "https://example.com/registry" Nothing Nothing []
      writeFile (cache </> "good" </> "marker") "original"
      writeFile (cache </> "blocked") "occupied file"
      result <- installClosureInto cache False repo "https://example.com/registry" [("good", repo </> "good"), ("blocked", repo </> "blocked")]
      result `shouldSatisfy` isLeft
      readFile (cache </> "good" </> "marker") `shouldReturn` "original"
      readFile (cache </> "blocked") `shouldReturn` "occupied file"

moduleDir :: FilePath -> String -> IO ()
moduleDir root name = do
  schema <- canonicalizePath "../schema/Module.dhall"
  let dir = root </> name
  createDirectoryIfMissing True dir
  writeFile (dir </> "module.dhall") ("let Module = " <> schema <> " in Module::{ name = \"" <> name <> "\", version = Some \"1.0.0\" }")
