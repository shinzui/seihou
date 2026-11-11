module Seihou.CLI.InstalledRunnablesSpec (tests) where

import Control.Lens ((^.))
import Control.Monad (forM)
import Data.ByteString qualified as BS
import Data.Generics.Labels ()
import Data.List (sort, sortOn)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.InstallClosure (installClosureInto)
import Seihou.CLI.InstallShared (OriginInfo (..), readOriginInfo)
import Seihou.CLI.InstalledRunnables (RefreshOptions (..), refreshInstalledRunnables)
import Seihou.CLI.UpgradeReport (UpgradeEntry (..), UpgradeStatus (..))
import Seihou.Core.Module (DiscoveredRunnable (..), ModuleSource (..), RunnableKind (..))
import System.Directory
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (callProcess)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.InstalledRunnables" $ do
  it "refreshes a single-blueprint repository, then reports it up to date" $
    withSystemTempDirectory "runnables-single" $ \tmp -> do
      let producer = tmp </> "producer"
          cache = tmp </> "cache"
      createDirectoryIfMissing True producer
      writeBlueprint (producer </> "blueprint.dhall") "bp" "0.1.0" noBaseModules
      initProducer producer
      installClosureInto cache False producer (fileUrl producer) [("bp", producer)] `shouldReturn` Right ()
      writeBlueprint (producer </> "blueprint.dhall") "bp" "0.1.1" noBaseModules
      commitProducer producer
      (rows, names) <- refresh (RefreshOptions False False) cache "bp" KindBlueprint
      rows `shouldBe` [UpgradeEntry "bp" (Just "0.1.0") (Just "0.1.1") Upgraded]
      names `shouldBe` ["bp"]
      TIO.readFile (cache </> "bp" </> "blueprint.dhall") >>= (`shouldSatisfy` T.isInfixOf "0.1.1")
      fmap (^. #version) <$> readOriginInfo (cache </> "bp") `shouldReturn` Just (Just "0.1.1")
      (again, _) <- refresh (RefreshOptions False False) cache "bp" KindBlueprint
      again `shouldBe` [UpgradeEntry "bp" (Just "0.1.1") (Just "0.1.1") AlreadyUpToDate]

  it "previews a refresh under dry run without changing the cache" $
    withSystemTempDirectory "runnables-dry-run" $ \tmp -> do
      let producer = tmp </> "producer"
          cache = tmp </> "cache"
      createDirectoryIfMissing True producer
      writeBlueprint (producer </> "blueprint.dhall") "bp" "0.1.0" noBaseModules
      initProducer producer
      installClosureInto cache False producer (fileUrl producer) [("bp", producer)] `shouldReturn` Right ()
      before <- snapshot cache
      writeBlueprint (producer </> "blueprint.dhall") "bp" "0.1.1" noBaseModules
      commitProducer producer
      (rows, _) <- refresh (RefreshOptions True False) cache "bp" KindBlueprint
      rows `shouldBe` [UpgradeEntry "bp" (Just "0.1.0") (Just "0.1.1") Upgraded]
      snapshot cache `shouldReturn` before

  it "refreshes a baseline module through its blueprint's closure" $
    withSystemTempDirectory "runnables-closure" $ \tmp -> do
      let producer = tmp </> "producer"
          cache = tmp </> "cache"
      registryProducer producer "1.0.0"
      installClosureInto cache False producer (fileUrl producer) [("bp", producer </> "bp")] `shouldReturn` Right ()
      doesFileExist (cache </> "demo" </> "module.dhall") `shouldReturn` True
      writeModule producer "demo" "1.1.0"
      commitProducer producer
      (rows, names) <- refresh (RefreshOptions False False) cache "bp" KindBlueprint
      sortOn (^. #moduleName) rows
        `shouldBe` sortOn
          (^. #moduleName)
          [ UpgradeEntry "demo" (Just "1.0.0") (Just "1.1.0") Upgraded,
            UpgradeEntry "bp" (Just "0.1.0") (Just "0.1.0") AlreadyUpToDate
          ]
      sort names `shouldBe` ["bp", "demo"]
      TIO.readFile (cache </> "demo" </> "module.dhall") >>= (`shouldSatisfy` T.isInfixOf "1.1.0")

  it "refuses a closure member whose provenance names another source and leaves it byte-identical" $
    withSystemTempDirectory "runnables-refusal" $ \tmp -> do
      let producer = tmp </> "producer"
          cache = tmp </> "cache"
          elsewhere = "file:///elsewhere/other.git"
      registryProducer producer "1.0.0"
      installClosureInto cache False producer (fileUrl producer) [("bp", producer </> "bp")] `shouldReturn` Right ()
      TIO.writeFile
        (cache </> "demo" </> ".seihou-origin.json")
        ("{\"sourceUrl\":\"" <> elsewhere <> "\",\"version\":\"1.0.0\",\"tags\":[],\"installedAt\":\"2026-11-11T00:00:00Z\"}")
      writeFile (cache </> "demo" </> "marker") "original"
      before <- snapshot (cache </> "demo")
      writeModule producer "demo" "1.1.0"
      commitProducer producer
      (rows, _) <- refresh (RefreshOptions False False) cache "bp" KindBlueprint
      case [entry | entry <- rows, entry ^. #moduleName == "demo"] of
        [entry] -> case entry ^. #upgradeStatus of
          UpgradeFailed reason -> do
            reason `shouldSatisfy` T.isInfixOf elsewhere
            reason `shouldSatisfy` T.isInfixOf (fileUrl producer)
          other -> expectationFailure ("expected a refusal, got " <> show other)
        other -> expectationFailure ("expected one demo row, got " <> show other)
      snapshot (cache </> "demo") `shouldReturn` before

  it "refreshes a single-prompt repository" $
    withSystemTempDirectory "runnables-prompt" $ \tmp -> do
      let producer = tmp </> "producer"
          cache = tmp </> "cache"
      createDirectoryIfMissing True producer
      writePrompt (producer </> "prompt.dhall") "review" "0.2.0"
      initProducer producer
      installClosureInto cache False producer (fileUrl producer) [("review", producer)] `shouldReturn` Right ()
      writePrompt (producer </> "prompt.dhall") "review" "0.3.0"
      commitProducer producer
      (rows, _) <- refresh (RefreshOptions False False) cache "review" KindPrompt
      rows `shouldBe` [UpgradeEntry "review" (Just "0.2.0") (Just "0.3.0") Upgraded]
      TIO.readFile (cache </> "review" </> "prompt.dhall") >>= (`shouldSatisfy` T.isInfixOf "0.3.0")

-- | Refresh one installed entry, read from the cache as discovery would.
refresh :: RefreshOptions -> FilePath -> Text -> RunnableKind -> IO ([UpgradeEntry], [Text])
refresh opts cache key kind = do
  let dir = cache </> T.unpack key
  origin <- readOriginInfo dir
  case origin of
    Nothing -> fail ("no origin metadata in " <> dir)
    Just info ->
      refreshInstalledRunnables opts cache [(DiscoveredRunnable key Nothing kind SourceInstalled dir False Nothing, info)]

fileUrl :: FilePath -> Text
fileUrl path = "file://" <> T.pack path

initProducer :: FilePath -> IO ()
initProducer repo = do
  callProcess "git" ["-C", repo, "init", "-q"]
  commitProducer repo

commitProducer :: FilePath -> IO ()
commitProducer repo = do
  callProcess "git" ["-C", repo, "add", "-A"]
  callProcess "git" ["-C", repo, "-c", "user.name=Seihou Test", "-c", "user.email=test@example.invalid", "commit", "--allow-empty", "-qm", "test: producer"]

-- | A registry with module @demo@ and blueprint @bp@, which names @demo@ as
-- its baseline.
registryProducer :: FilePath -> String -> IO ()
registryProducer producer moduleVersion = do
  writeModule producer "demo" moduleVersion
  createDirectoryIfMissing True (producer </> "bp")
  writeBlueprint (producer </> "bp" </> "blueprint.dhall") "bp" "0.1.0" demoBaseModule
  TIO.writeFile (producer </> "seihou-registry.dhall") $
    T.unlines
      [ "{ repoName = \"fixture\"",
        ", repoDescription = None Text",
        ", modules = [ { name = \"demo\", version = None Text, path = \"demo\", description = None Text, tags = [] : List Text } ]",
        ", recipes = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }",
        ", blueprints = [ { name = \"bp\", version = None Text, path = \"bp\", description = None Text, tags = [] : List Text } ]",
        ", prompts = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }",
        "}"
      ]
  initProducer producer

writeModule :: FilePath -> String -> String -> IO ()
writeModule root name version = do
  schema <- canonicalizePath "../schema/Module.dhall"
  let dir = root </> name
  createDirectoryIfMissing True dir
  writeFile (dir </> "module.dhall") ("let Module = " <> schema <> " in Module::{ name = \"" <> name <> "\", version = Some \"" <> version <> "\" }")

writeBlueprint :: FilePath -> Text -> Text -> Text -> IO ()
writeBlueprint path name version baseModules =
  TIO.writeFile path $
    T.unlines
      [ "{ name = \"" <> name <> "\"",
        ", version = Some \"" <> version <> "\"",
        ", description = Some \"Refresh fixture\"",
        ", prompt = \"Do the work.\"",
        ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
        ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
        ", baseModules = " <> baseModules,
        ", files = [] : List { src : Text, description : Optional Text }",
        ", allowedTools = None (List Text)",
        ", tags = [] : List Text",
        "}"
      ]

writePrompt :: FilePath -> Text -> Text -> IO ()
writePrompt path name version =
  TIO.writeFile path $
    T.unlines
      [ "{ name = \"" <> name <> "\"",
        ", version = Some \"" <> version <> "\"",
        ", description = None Text",
        ", prompt = \"Review the current changes.\"",
        ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
        ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
        ", commandVars = [] : List { name : Text, run : Text, workDir : Optional Text, when : Optional Text, trim : Bool, maxBytes : Optional Natural }",
        ", files = [] : List { src : Text, description : Optional Text }",
        ", allowedTools = None (List Text)",
        ", tags = [] : List Text",
        ", launch = None { provider : Optional Text, mode : Optional Text, model : Optional Text }",
        "}"
      ]

noBaseModules :: Text
noBaseModules = "[] : List { module : Text, vars : List { name : Text, value : Text } }"

demoBaseModule :: Text
demoBaseModule = "[ { module = \"demo\", vars = [] : List { name : Text, value : Text } } ]"

-- | Every file under a directory with its bytes.
snapshot :: FilePath -> IO (Map.Map FilePath BS.ByteString)
snapshot root = Map.fromList <$> walk ""
  where
    walk relative = do
      let dir = if null relative then root else root </> relative
      names <- sort <$> listDirectory dir
      fmap concat $ forM names $ \name -> do
        let child = if null relative then name else relative </> name
        isDir <- doesDirectoryExist (root </> child)
        if isDir
          then walk child
          else do
            bytes <- BS.readFile (root </> child)
            pure [(child, bytes)]
