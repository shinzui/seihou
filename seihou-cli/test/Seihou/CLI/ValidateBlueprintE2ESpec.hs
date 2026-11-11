module Seihou.CLI.ValidateBlueprintE2ESpec (tests) where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.SeihouBinary (seihouBinary)
import System.Directory (createDirectoryIfMissing)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode)
import Test.Hspec
import Test.Tasty (TestTree)
import Test.Tasty.Hspec (testSpec)

-- | A self-contained blueprint, offline with an empty Dhall cache, whose
-- @allowedTools@ field is the given Dhall expression.
blueprintWith :: Text -> Text
blueprintWith allowedTools =
  T.unlines
    [ "{ name = \"tool-check\"",
      ", version = Some \"1.0.0\"",
      ", description = Some \"Allowed tools fixture\"",
      ", prompt = \"Build the docs.\"",
      ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
      ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
      ", baseModules = [] : List { module : Text, vars : List { name : Text, value : Text } }",
      ", files = [] : List { src : Text, description : Optional Text }",
      ", allowedTools = " <> allowedTools,
      ", tags = [ \"test\" ]",
      ", migrations = [] : List { from : Text, to : Text, prompt : Text }",
      "}"
    ]

validate :: Text -> IO (ExitCode, Text)
validate allowedTools =
  withSystemTempDirectory "validate-blueprint" $ \root -> do
    binary <- seihouBinary
    let blueprintDir = root </> "tool-check"
    createDirectoryIfMissing True blueprintDir
    TIO.writeFile (blueprintDir </> "blueprint.dhall") (blueprintWith allowedTools)
    inherited <- getEnvironment
    let overrides = [("XDG_CONFIG_HOME", root </> "config"), ("XDG_CACHE_HOME", root </> "cache"), ("NO_COLOR", "1")]
        environment = overrides <> filter (\(key, _) -> key `notElem` map fst overrides) inherited
    (code, out, err) <-
      readCreateProcessWithExitCode
        (proc binary ["validate-blueprint", blueprintDir]) {cwd = Just root, env = Just environment}
        ""
    pure (code, T.pack (out <> err))

tests :: IO TestTree
tests = testSpec "ValidateBlueprint" $ do
  it "warns about a blueprint without allowedTools and still exits 0" $ do
    (code, output) <- validate "None (List Text)"
    code `shouldBe` ExitSuccess
    output `shouldSatisfy` T.isInfixOf "\x26A0 Allowed tools declared"
    output `shouldSatisfy` T.isInfixOf "allowedTools is not declared"
    output `shouldSatisfy` T.isInfixOf "Bash(seihou *)"
    output `shouldSatisfy` T.isInfixOf "is valid."

  it "treats an empty allowedTools list as undeclared" $ do
    (code, output) <- validate "Some ([] : List Text)"
    code `shouldBe` ExitSuccess
    output `shouldSatisfy` T.isInfixOf "\x26A0 Allowed tools declared"

  it "does not warn when the blueprint declares a tool" $ do
    (code, output) <- validate "Some [ \"Read\" ]"
    code `shouldBe` ExitSuccess
    output `shouldSatisfy` T.isInfixOf "\x2713 Allowed tools declared"
    output `shouldNotSatisfy` T.isInfixOf "allowedTools is not declared"
