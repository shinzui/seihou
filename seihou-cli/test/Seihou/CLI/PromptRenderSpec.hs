module Seihou.CLI.PromptRenderSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Seihou.CLI.AgentLaunch (AgentContext (..))
import Seihou.CLI.PromptRender (formatPromptGuidance, renderPromptBody, renderPromptSystemPrompt)
import Seihou.Core.Types
import Test.Hspec
import Test.Tasty (TestTree)
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.PromptRender" $ do
  describe "formatPromptGuidance" $ do
    it "includes guidance whose condition is true and omits false guidance" $ do
      let rendered = formatPromptGuidance resolvedVars sampleGuidance
      rendered `shouldSatisfy` T.isInfixOf "### Haskell repository"
      rendered `shouldSatisfy` T.isInfixOf "Use cabal build all."
      rendered `shouldNotSatisfy` T.isInfixOf "Use npm test."

    it "renders a stable empty message when no guidance is selected" $
      formatPromptGuidance resolvedVars [PromptGuidance "Node" "Use npm test." (Just (ExprEq "repo.kind" (VText "node")))]
        `shouldBe` "(no prompt guidance)"

  describe "renderPromptSystemPrompt" $ do
    it "renders context, prompt identity, selected guidance, and the prompt body" $ do
      let body = renderPromptBody resolvedVars "Review {{project.name}}."
          rendered = renderPromptSystemPrompt sampleContext samplePrompt resolvedVars body (Just "Focus on tests.")
      rendered `shouldSatisfy` T.isInfixOf "## Current Environment"
      rendered `shouldSatisfy` T.isInfixOf "## Prompt Identity"
      rendered `shouldSatisfy` T.isInfixOf "## Reference Files"
      rendered `shouldSatisfy` T.isInfixOf "## Prompt Guidance"
      rendered `shouldSatisfy` T.isInfixOf "Use cabal build all."
      rendered `shouldNotSatisfy` T.isInfixOf "Use npm test."
      rendered `shouldSatisfy` T.isInfixOf "Review seihou."
      rendered `shouldSatisfy` T.isInfixOf "Focus on tests."

sampleContext :: AgentContext
sampleContext =
  AgentContext
    { cwd = "/tmp/project",
      seihouInitialized = True,
      hasManifest = False,
      localModuleDhall = False,
      localModules = [],
      availableModules = []
    }

samplePrompt :: AgentPrompt
samplePrompt =
  AgentPrompt
    { name = "review-guided",
      version = Just "0.1.0",
      description = Just "Review with guidance",
      prompt = "Review {{project.name}}.",
      vars = [projectNameDecl],
      prompts = [],
      commandVars = [repoKindCommand],
      guidance = sampleGuidance,
      files = [BlueprintFile {src = "style.md", description = Just "Style notes"}],
      allowedTools = Nothing,
      tags = ["review"],
      launch = Nothing
    }

sampleGuidance :: [PromptGuidance]
sampleGuidance =
  [ PromptGuidance "Haskell repository" "Use cabal build all." (Just (ExprEq "repo.kind" (VText "haskell"))),
    PromptGuidance "Node repository" "Use npm test." (Just (ExprEq "repo.kind" (VText "node")))
  ]

resolvedVars :: Map.Map VarName ResolvedVar
resolvedVars =
  Map.fromList
    [ ("project.name", ResolvedVar (VText "seihou") FromDefault projectNameDecl),
      ("repo.kind", ResolvedVar (VText "haskell") (FromCommand "detect repo") repoKindDecl)
    ]

projectNameDecl :: VarDecl
projectNameDecl = VarDecl "project.name" VTText Nothing Nothing False Nothing

repoKindDecl :: VarDecl
repoKindDecl = VarDecl "repo.kind" VTText Nothing Nothing False Nothing

repoKindCommand :: CommandVar
repoKindCommand = CommandVar "repo.kind" "echo haskell" Nothing Nothing True (Just 100)
