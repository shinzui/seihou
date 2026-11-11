module Seihou.CLI.RemoteVersionSpec (tests) where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.RemoteVersion (FetchError (..), fetchTrueModuleVersion, fetchTrueRunnableVersion)
import Seihou.Core.Module (RunnableKind (..))
import Seihou.Core.Types (ModuleName (..))
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.RemoteVersion" spec

spec :: Spec
spec = do
  describe "fetchTrueModuleVersion (multi-module repo)" $ do
    it "returns the module.dhall version even when the registry says otherwise" $
      withSystemTempDirectory "seihou-rv-stale" $ \dir -> do
        -- Stale registry: registry declares 1.0.0, module.dhall declares 2.0.0.
        createDirectoryIfMissing True (dir </> "modules" </> "demo")
        writeModuleDhall (dir </> "modules" </> "demo" </> "module.dhall") "demo" (Just "2.0.0")
        TIO.writeFile (dir </> "seihou-registry.dhall") (registryDhall "demo" (Just "1.0.0") "modules/demo")

        result <- fetchTrueModuleVersion dir (ModuleName "demo")
        result `shouldBe` Right (Just "2.0.0")

    it "returns Right Nothing when module.dhall declares no version" $
      withSystemTempDirectory "seihou-rv-unver" $ \dir -> do
        createDirectoryIfMissing True (dir </> "modules" </> "demo")
        writeModuleDhall (dir </> "modules" </> "demo" </> "module.dhall") "demo" Nothing
        TIO.writeFile (dir </> "seihou-registry.dhall") (registryDhall "demo" (Just "1.0.0") "modules/demo")

        result <- fetchTrueModuleVersion dir (ModuleName "demo")
        result `shouldBe` Right Nothing

    it "returns EntryNotFound when the registry has no matching module" $
      withSystemTempDirectory "seihou-rv-missing" $ \dir -> do
        createDirectoryIfMissing True (dir </> "modules" </> "demo")
        writeModuleDhall (dir </> "modules" </> "demo" </> "module.dhall") "demo" (Just "2.0.0")
        TIO.writeFile (dir </> "seihou-registry.dhall") (registryDhall "demo" (Just "1.0.0") "modules/demo")

        result <- fetchTrueModuleVersion dir (ModuleName "other")
        result `shouldBe` Left (EntryNotFound (ModuleName "other"))

    it "returns ModuleDhallNotFound when the registry path doesn't have module.dhall" $
      withSystemTempDirectory "seihou-rv-broken" $ \dir -> do
        createDirectoryIfMissing True (dir </> "modules" </> "demo")
        TIO.writeFile (dir </> "seihou-registry.dhall") (registryDhall "demo" (Just "1.0.0") "modules/demo")

        result <- fetchTrueModuleVersion dir (ModuleName "demo")
        case result of
          Left (ModuleDhallNotFound _) -> pure ()
          other -> expectationFailure ("expected ModuleDhallNotFound, got " <> show other)

  describe "fetchTrueRunnableVersion" $ do
    it "reads a registry blueprint's blueprint.dhall, not the registry's version" $
      withSystemTempDirectory "seihou-rv-blueprint" $ \dir -> do
        createDirectoryIfMissing True (dir </> "blueprints" </> "bp")
        TIO.writeFile (dir </> "blueprints" </> "bp" </> "blueprint.dhall") (blueprintDhall "bp" "0.2.0")
        TIO.writeFile (dir </> "seihou-registry.dhall") (blueprintRegistryDhall "bp" "0.1.0" "blueprints/bp")

        fetchTrueRunnableVersion dir KindBlueprint "bp" `shouldReturn` Right (Just "0.2.0")
        fetchTrueRunnableVersion dir KindBlueprint "other" `shouldReturn` Left (EntryNotFound (ModuleName "other"))

    it "reads a single-prompt repository's prompt.dhall and reports a missing descriptor" $
      withSystemTempDirectory "seihou-rv-prompt" $ \dir -> do
        TIO.writeFile (dir </> "prompt.dhall") (promptDhall "review" "0.3.0")

        fetchTrueRunnableVersion dir KindPrompt "review" `shouldReturn` Right (Just "0.3.0")
        fetchTrueRunnableVersion dir KindBlueprint "review" `shouldReturn` Left (RegistryNotFound dir)

        createDirectoryIfMissing True (dir </> "bp")
        TIO.writeFile (dir </> "seihou-registry.dhall") (blueprintRegistryDhall "bp" "0.1.0" "bp")
        result <- fetchTrueRunnableVersion dir KindBlueprint "bp"
        case result of
          Left (DefinitionNotFound _) -> pure ()
          other -> expectationFailure ("expected DefinitionNotFound, got " <> show other)

  describe "fetchTrueModuleVersion (single-module repo)" $ do
    it "reads module.dhall at the repo root" $
      withSystemTempDirectory "seihou-rv-single" $ \dir -> do
        writeModuleDhall (dir </> "module.dhall") "demo" (Just "3.4.5")

        result <- fetchTrueModuleVersion dir (ModuleName "demo")
        result `shouldBe` Right (Just "3.4.5")

  describe "fetchTrueModuleVersion (empty repo)" $ do
    it "returns RegistryNotFound when nothing recognizable is present" $
      withSystemTempDirectory "seihou-rv-empty" $ \dir -> do
        result <- fetchTrueModuleVersion dir (ModuleName "demo")
        case result of
          Left (RegistryNotFound _) -> pure ()
          other -> expectationFailure ("expected RegistryNotFound, got " <> show other)

-- ----------------------------------------------------------------------------
-- Fixture helpers
-- ----------------------------------------------------------------------------

writeModuleDhall :: FilePath -> Text -> Maybe Text -> IO ()
writeModuleDhall path name mver =
  TIO.writeFile path (moduleDhallBody name mver)

moduleDhallBody :: Text -> Maybe Text -> Text
moduleDhallBody name mver =
  T.unlines
    [ "{ name = \"" <> name <> "\"",
      ", version = " <> optText mver,
      ", description = None Text",
      ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
      ", exports = [] : List { var : Text, alias : Optional Text }",
      ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
      ", steps = [] : List { strategy : Text, src : Text, dest : Text, when : Optional Text, patch : Optional Text }",
      ", commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }",
      ", dependencies = [] : List Text",
      ", removal = None { steps : List { action : Text, dest : Text, src : Optional Text }, commands : List { run : Text, workDir : Optional Text, when : Optional Text } }",
      "}"
    ]

registryDhall :: Text -> Maybe Text -> Text -> Text
registryDhall name mver path =
  T.unlines
    [ "{ repoName = \"Test\"",
      ", repoDescription = None Text",
      ", modules =",
      "  [ { name = \"" <> name <> "\"",
      "    , version = " <> optText mver,
      "    , path = \"" <> path <> "\"",
      "    , description = None Text",
      "    , tags = [] : List Text",
      "    }",
      "  ]",
      "}"
    ]

optText :: Maybe Text -> Text
optText Nothing = "None Text"
optText (Just v) = "Some \"" <> v <> "\""

blueprintDhall :: Text -> Text -> Text
blueprintDhall name version =
  T.unlines
    [ "{ name = \"" <> name <> "\"",
      ", version = Some \"" <> version <> "\"",
      ", description = None Text",
      ", prompt = \"Do the work.\"",
      ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
      ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
      ", baseModules = [] : List { module : Text, vars : List { name : Text, value : Text } }",
      ", files = [] : List { src : Text, description : Optional Text }",
      ", allowedTools = None (List Text)",
      ", tags = [] : List Text",
      "}"
    ]

promptDhall :: Text -> Text -> Text
promptDhall name version =
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

blueprintRegistryDhall :: Text -> Text -> Text -> Text
blueprintRegistryDhall name version path =
  T.unlines
    [ "{ repoName = \"Test\"",
      ", repoDescription = None Text",
      ", modules = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }",
      ", blueprints =",
      "  [ { name = \"" <> name <> "\", version = Some \"" <> version <> "\", path = \"" <> path <> "\", description = None Text, tags = [] : List Text } ]",
      "}"
    ]
