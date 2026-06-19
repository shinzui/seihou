module Seihou.Core.AgentPromptSpec (tests) where

import Data.Text qualified as T
import Seihou.Core.AgentPrompt (validateAgentPrompt)
import Seihou.Core.Module (DiscoveredRunnable (..), RunnableKind (..), discoverAllRunnables, discoverRunnable)
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalAgentPromptFromFile)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.AgentPrompt" spec

goodAgentPrompt :: AgentPrompt
goodAgentPrompt =
  AgentPrompt
    "review-changes"
    (Just "0.1.0")
    (Just "Review local changes")
    "Review the current repository."
    [VarDecl "project.name" VTText Nothing Nothing True Nothing]
    [Prompt {var = "project.name", text = "Project?", condition = Nothing, choices = Nothing}]
    [CommandVar "git.branch" "git branch --show-current" Nothing Nothing True (Just 4096)]
    []
    Nothing
    ["review"]
    Nothing

withAgentPromptName :: ModuleName -> AgentPrompt -> AgentPrompt
withAgentPromptName n p =
  AgentPrompt n p.version p.description p.prompt p.vars p.prompts p.commandVars p.files p.allowedTools p.tags p.launch

withAgentPromptPrompt :: T.Text -> AgentPrompt -> AgentPrompt
withAgentPromptPrompt body p =
  AgentPrompt p.name p.version p.description body p.vars p.prompts p.commandVars p.files p.allowedTools p.tags p.launch

withAgentPromptVars :: [VarDecl] -> AgentPrompt -> AgentPrompt
withAgentPromptVars vars p =
  AgentPrompt p.name p.version p.description p.prompt vars p.prompts p.commandVars p.files p.allowedTools p.tags p.launch

withAgentPromptPrompts :: [Prompt] -> AgentPrompt -> AgentPrompt
withAgentPromptPrompts prompts p =
  AgentPrompt p.name p.version p.description p.prompt p.vars prompts p.commandVars p.files p.allowedTools p.tags p.launch

withAgentPromptCommandVars :: [CommandVar] -> AgentPrompt -> AgentPrompt
withAgentPromptCommandVars commandVars p =
  AgentPrompt p.name p.version p.description p.prompt p.vars p.prompts commandVars p.files p.allowedTools p.tags p.launch

withAgentPromptFiles :: [BlueprintFile] -> AgentPrompt -> AgentPrompt
withAgentPromptFiles files p =
  AgentPrompt p.name p.version p.description p.prompt p.vars p.prompts p.commandVars files p.allowedTools p.tags p.launch

hasError :: T.Text -> [T.Text] -> Bool
hasError needle = any (T.isInfixOf needle)

spec :: Spec
spec = do
  describe "evalAgentPromptFromFile" $ do
    it "decodes prompt.dhall with command variables and launch metadata" $ do
      withSystemTempDirectory "seihou-prompt" $ \tmpDir -> do
        let promptDir = tmpDir </> "review-changes"
        createDirectoryIfMissing True promptDir
        writeFile (promptDir </> "prompt.dhall") (samplePromptDhall "review-changes")
        result <- evalAgentPromptFromFile (promptDir </> "prompt.dhall")
        case result of
          Right p -> do
            p.name `shouldBe` "review-changes"
            p.description `shouldBe` Just "Review local changes"
            length p.commandVars `shouldBe` 1
            fmap (.provider) p.launch `shouldBe` Just (Just "codex-cli")
          Left err -> expectationFailure ("Expected Right, got: " <> show err)

  describe "validateAgentPrompt" $ do
    it "accepts a well-formed prompt" $ do
      withSystemTempDirectory "seihou-prompt" $ \tmpDir -> do
        result <- validateAgentPrompt tmpDir goodAgentPrompt
        case result of
          Right p -> p.name `shouldBe` "review-changes"
          Left err -> expectationFailure ("Expected Right, got: " <> show err)

    it "rejects an invalid prompt name" $ do
      withSystemTempDirectory "seihou-prompt" $ \tmpDir -> do
        result <- validateAgentPrompt tmpDir (withAgentPromptName "Bad_Name" goodAgentPrompt)
        case result of
          Left (ValidationError _ errs) ->
            hasError "prompt name must match" errs `shouldBe` True
          other -> expectationFailure ("Expected ValidationError, got: " <> show other)

    it "rejects an empty prompt body" $ do
      withSystemTempDirectory "seihou-prompt" $ \tmpDir -> do
        result <- validateAgentPrompt tmpDir (withAgentPromptPrompt "   \n " goodAgentPrompt)
        case result of
          Left (ValidationError _ errs) ->
            hasError "prompt body must not be empty" errs `shouldBe` True
          other -> expectationFailure ("Expected ValidationError, got: " <> show other)

    it "rejects duplicate typed variables" $ do
      withSystemTempDirectory "seihou-prompt" $ \tmpDir -> do
        let bad =
              withAgentPromptVars
                [ VarDecl "x" VTText Nothing Nothing True Nothing,
                  VarDecl "x" VTBool Nothing Nothing False Nothing
                ]
                goodAgentPrompt
        result <- validateAgentPrompt tmpDir bad
        case result of
          Left (ValidationError _ errs) ->
            hasError "duplicate variable name" errs `shouldBe` True
          other -> expectationFailure ("Expected ValidationError, got: " <> show other)

    it "rejects prompts that reference undeclared variables" $ do
      withSystemTempDirectory "seihou-prompt" $ \tmpDir -> do
        let bad =
              withAgentPromptPrompts
                [Prompt {var = "missing", text = "?", condition = Nothing, choices = Nothing}]
                goodAgentPrompt
        result <- validateAgentPrompt tmpDir bad
        case result of
          Left (ValidationError _ errs) ->
            hasError "prompt references undeclared variable" errs `shouldBe` True
          other -> expectationFailure ("Expected ValidationError, got: " <> show other)

    it "rejects unsafe command variables" $ do
      withSystemTempDirectory "seihou-prompt" $ \tmpDir -> do
        let bad =
              withAgentPromptCommandVars
                [ CommandVar "git.branch" "" (Just "../outside") Nothing True (Just 0),
                  CommandVar "git.branch" "git status" Nothing Nothing True Nothing
                ]
                goodAgentPrompt
        result <- validateAgentPrompt tmpDir bad
        case result of
          Left (ValidationError _ errs) -> do
            hasError "duplicate command variable name" errs `shouldBe` True
            hasError "run must not be empty" errs `shouldBe` True
            hasError "must not contain '..'" errs `shouldBe` True
            hasError "maxBytes must be greater than zero" errs `shouldBe` True
          other -> expectationFailure ("Expected ValidationError, got: " <> show other)

    it "checks referenced prompt files under files/" $ do
      withSystemTempDirectory "seihou-prompt" $ \tmpDir -> do
        let bad =
              withAgentPromptFiles
                [BlueprintFile {src = "missing.md", description = Nothing}]
                goodAgentPrompt
        result <- validateAgentPrompt tmpDir bad
        case result of
          Left (ValidationError _ errs) ->
            hasError "prompt file not found" errs `shouldBe` True
          other -> expectationFailure ("Expected ValidationError, got: " <> show other)

  describe "prompt discovery" $ do
    it "finds a prompt when only prompt.dhall is present" $ do
      withSystemTempDirectory "seihou-prompt" $ \tmpDir -> do
        let promptDir = tmpDir </> "review-changes"
        createDirectoryIfMissing True promptDir
        writeFile (promptDir </> "prompt.dhall") (samplePromptDhall "review-changes")
        result <- discoverRunnable [tmpDir] "review-changes"
        case result of
          Right (RunnableAgentPrompt p dir) -> do
            p.name `shouldBe` "review-changes"
            dir `shouldBe` promptDir
          other -> expectationFailure ("Expected RunnableAgentPrompt, got: " <> show other)

    it "tags prompts as KindPrompt during enumeration" $ do
      withSystemTempDirectory "seihou-prompt" $ \tmpDir -> do
        let promptDir = tmpDir </> "review-changes"
        createDirectoryIfMissing True promptDir
        writeFile (promptDir </> "prompt.dhall") (samplePromptDhall "review-changes")
        found <- discoverAllRunnables [tmpDir]
        case found of
          [DiscoveredRunnable {drKind = kind}] -> kind `shouldBe` KindPrompt
          other -> expectationFailure ("Expected one discovered prompt, got: " <> show other)

    it "prefers blueprint.dhall over prompt.dhall in the same directory" $ do
      withSystemTempDirectory "seihou-prompt" $ \tmpDir -> do
        let entryDir = tmpDir </> "ambiguous"
        createDirectoryIfMissing True entryDir
        writeFile (entryDir </> "blueprint.dhall") (sampleBlueprintDhall "ambiguous")
        writeFile (entryDir </> "prompt.dhall") (samplePromptDhall "ambiguous")
        result <- discoverRunnable [tmpDir] "ambiguous"
        case result of
          Right (RunnableBlueprint _ _) -> pure ()
          other -> expectationFailure ("Expected RunnableBlueprint, got: " <> show other)

samplePromptDhall :: T.Text -> String
samplePromptDhall n =
  unlines
    [ "{ name = \"" ++ T.unpack n ++ "\"",
      ", version = Some \"0.1.0\"",
      ", description = Some \"Review local changes\"",
      ", prompt = \"Review the current repository.\"",
      ", vars =",
      "    [] : List",
      "          { name : Text",
      "          , type : Text",
      "          , default : Optional Text",
      "          , description : Optional Text",
      "          , required : Bool",
      "          , validation : Optional Text",
      "          }",
      ", prompts =",
      "    [] : List",
      "          { var : Text",
      "          , text : Text",
      "          , when : Optional Text",
      "          , choices : Optional (List Text)",
      "          }",
      ", commandVars =",
      "    [ { name = \"git.branch\"",
      "      , run = \"git branch --show-current\"",
      "      , workDir = None Text",
      "      , when = None Text",
      "      , trim = True",
      "      , maxBytes = Some 4096",
      "      }",
      "    ]",
      ", files = [] : List { src : Text, description : Optional Text }",
      ", allowedTools = None (List Text)",
      ", tags = [ \"review\" ]",
      ", launch = Some { provider = Some \"codex-cli\", mode = None Text, model = None Text }",
      "}"
    ]

sampleBlueprintDhall :: T.Text -> String
sampleBlueprintDhall n =
  unlines
    [ "{ name = \"" ++ T.unpack n ++ "\"",
      ", version = Some \"0.1.0\"",
      ", description = None Text",
      ", prompt = \"hello\"",
      ", vars =",
      "    [] : List",
      "          { name : Text",
      "          , type : Text",
      "          , default : Optional Text",
      "          , description : Optional Text",
      "          , required : Bool",
      "          , validation : Optional Text",
      "          }",
      ", prompts =",
      "    [] : List",
      "          { var : Text",
      "          , text : Text",
      "          , when : Optional Text",
      "          , choices : Optional (List Text)",
      "          }",
      ", baseModules =",
      "    [] : List { module : Text, vars : List { name : Text, value : Text } }",
      ", files =",
      "    [] : List { src : Text, description : Optional Text }",
      ", allowedTools = None (List Text)",
      ", tags = [] : List Text",
      "}"
    ]
