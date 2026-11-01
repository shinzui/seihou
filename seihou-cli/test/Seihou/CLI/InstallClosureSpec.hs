module Seihou.CLI.InstallClosureSpec (tests) where

import Data.Either (isLeft)
import Data.Text qualified as T
import Seihou.CLI.InstallClosure (installClosureInto, publishStagedClosure, stageClosuresInto)
import Seihou.CLI.InstallShared (installModuleDirInto)
import System.Directory
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.InstallClosure" $ do
  it "acquires same-registry recipe bases, materializes their source, and repairs a missing base" $
    withSystemTempDirectory "closure-recipes" $ \tmp -> do
      let repo = tmp </> "repo"
          cache = tmp </> "cache"
          source = "https://example.com/registry.git"
      moduleDir repo "member"
      recipeDir repo "base" "[\"member\"]" ""
      recipeDir repo "child" "[] : List Text" ", extends = Some {recipe = \"base\"}"
      registry repo ["member"] ["base", "child"]
      installClosureInto cache False repo source [("child", repo </> "child")] `shouldReturn` Right ()
      doesFileExist (cache </> "base/recipe.dhall") `shouldReturn` True
      normalized <- readFile (cache </> "child/recipe.dhall")
      T.pack normalized `shouldSatisfy` T.isInfixOf source
      removeDirectoryRecursive (cache </> "base")
      installClosureInto cache False repo source [("child", repo </> "child")] `shouldReturn` Right ()
      doesFileExist (cache </> "base/recipe.dhall") `shouldReturn` True

  it "rejects wrong-kind bases, range violations, cycles and invalid merged overrides before publishing" $
    withSystemTempDirectory "closure-recipe-refusals" $ \tmp -> do
      let repo = tmp </> "repo"
          cache = tmp </> "cache"
          source = "https://example.com/registry.git"
      moduleDir repo "member"
      recipeDir repo "base" "[\"member\"]" ""
      registry repo ["member"] ["base", "child"]
      mapM_
        ( \extension -> do
            recipeDir repo "child" "[] : List Text" extension
            result <- installClosureInto cache False repo source [("child", repo </> "child")]
            result `shouldSatisfy` isLeft
            doesDirectoryExist cache `shouldReturn` False
        )
        [ ", extends = Some {recipe = \"member\"}",
          ", extends = Some {recipe = \"base\", versionRange = Some {minimum = \"2\", before = \"3\"}}",
          ", extends = Some {recipe = \"child\"}",
          ", extends = Some {recipe = \"base\"}, moduleOverrides = [{module = \"missing\", vars = [{name = \"x\", value = \"new\"}]}]"
        ]

  it "rejects indirect recipe cycles and recipe names used as module edges" $
    withSystemTempDirectory "closure-recipe-kinds" $ \tmp -> do
      let repo = tmp </> "repo"
          cache = tmp </> "cache"
          source = "https://example.com/registry.git"
      moduleDir repo "member"
      recipeDir repo "base" "[] : List Text" ", extends = Some {recipe = \"child\"}"
      recipeDir repo "child" "[] : List Text" ", extends = Some {recipe = \"base\"}"
      registry repo ["member"] ["base", "child"]
      cycleResult <- installClosureInto cache False repo source [("child", repo </> "child")]
      cycleResult `shouldSatisfy` isLeft
      doesDirectoryExist cache `shouldReturn` False
      recipeDir repo "base" "[\"member\"]" ""
      recipeDir repo "child" "[\"base\"]" ""
      wrongKind <- installClosureInto cache False repo source [("child", repo </> "child")]
      wrongKind `shouldSatisfy` isLeft
      doesDirectoryExist cache `shouldReturn` False

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

  it "restores every cache entry if publishing a staged recipe refresh fails" $
    withSystemTempDirectory "closure-upgrade-rollback" $ \tmp -> do
      let repo = tmp </> "repo"
          staged = tmp </> "staged"
          cache = tmp </> "cache"
          source = "https://example.com/registry.git"
      moduleDir repo "first"
      moduleDir repo "second"
      installClosureInto cache False repo source [("first", repo </> "first"), ("second", repo </> "second")] `shouldReturn` Right ()
      writeFile (cache </> "first/marker") "original"
      result <- stageClosuresInto False staged False [(repo, source, [("first", repo </> "first"), ("second", repo </> "second")])]
      case result of
        Left err -> expectationFailure (T.unpack err)
        Right artifacts -> do
          removeDirectoryRecursive (staged </> "second")
          published <- publishStagedClosure cache artifacts
          published `shouldSatisfy` isLeft
          readFile (cache </> "first/marker") `shouldReturn` "original"
          doesFileExist (cache </> "second/module.dhall") `shouldReturn` True

moduleDir :: FilePath -> String -> IO ()
moduleDir root name = do
  schema <- canonicalizePath "../schema/Module.dhall"
  let dir = root </> name
  createDirectoryIfMissing True dir
  writeFile (dir </> "module.dhall") ("let Module = " <> schema <> " in Module::{ name = \"" <> name <> "\", version = Some \"1.0.0\" }")

recipeDir :: FilePath -> String -> String -> String -> IO ()
recipeDir root name members extension = do
  let dir = root </> name
  createDirectoryIfMissing True dir
  writeFile (dir </> "recipe.dhall") $
    "{ name = "
      <> show name
      <> ", version = Some \"1.0.0\", description = None Text, modules = "
      <> members
      <> ", vars = [] : List {name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text}"
      <> ", prompts = [] : List {var : Text, text : Text, when : Optional Text, choices : Optional (List Text)}"
      <> extension
      <> "}"

registry :: FilePath -> [String] -> [String] -> IO ()
registry root modules recipes =
  writeFile (root </> "seihou-registry.dhall") $
    "{repoName = \"fixture\", repoDescription = None Text, modules = " <> entries modules <> ", recipes = " <> entries recipes <> "}"
  where
    entries names = "[" <> concat (zipWith (\i name -> (if i == (0 :: Int) then "" else ",") <> "{name = " <> show name <> ", path = " <> show name <> ", version = None Text, description = None Text, tags = [] : List Text}") [0 ..] names) <> "]"
