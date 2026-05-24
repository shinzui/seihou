module Seihou.CLI.KitPathsSpec (tests) where

import Data.Text qualified as T
import Seihou.CLI.KitPaths
import System.Directory
  ( createDirectoryIfMissing,
  )
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.KitPaths" spec

spec :: Spec
spec = do
  describe "provider target paths" $ do
    it "keeps Claude skills and agents under the Claude Code layout" $ do
      skillTargetDir ClaudeLayout "/tmp/seihou-agents" "review"
        `shouldBe` "/tmp/seihou-agents/.claude/skills/review"
      agentTargetFile ClaudeLayout "/tmp/seihou-agents" "reviewer"
        `shouldBe` "/tmp/seihou-agents/.claude/agents/reviewer.md"

    it "places Codex skills and custom agents in documented Codex layouts" $ do
      skillTargetDir CodexLayout "/tmp/project" "review"
        `shouldBe` "/tmp/project/.agents/skills/review"
      agentTargetFile CodexLayout "/tmp/project" "reviewer"
        `shouldBe` "/tmp/project/.codex/agents/reviewer.toml"

  describe "codexAgentToml" $ do
    it "wraps kit agent markdown as Codex custom-agent instructions" $ do
      let toml = codexAgentToml "reviewer" "Review PRs" "Line 1\nLine 2"
      toml `shouldSatisfy` T.isInfixOf "name = \"reviewer\""
      toml `shouldSatisfy` T.isInfixOf "description = \"Review PRs\""
      toml `shouldSatisfy` T.isInfixOf "developer_instructions = \"\"\""
      toml `shouldSatisfy` T.isInfixOf "Line 1\nLine 2"

  describe "scanInstalledForProvider" $ do
    it "discovers installed Claude skills and agents" $
      withSystemTempDirectory "seihou-kit-claude" $ \dir -> do
        createDirectoryIfMissing True (dir </> ".claude" </> "skills" </> "module-readme")
        createDirectoryIfMissing True (dir </> ".claude" </> "agents")
        writeFile (dir </> ".claude" </> "agents" </> "reviewer.md") "agent"
        items <- scanInstalledForProvider ClaudeLayout dir
        items
          `shouldMatchList` [ InstalledKitItem "module-readme" "skill" "claude",
                              InstalledKitItem "reviewer" "agent" "claude"
                            ]

    it "discovers installed Codex skills and custom agents" $
      withSystemTempDirectory "seihou-kit-codex" $ \dir -> do
        createDirectoryIfMissing True (dir </> ".agents" </> "skills" </> "module-readme")
        createDirectoryIfMissing True (dir </> ".codex" </> "agents")
        writeFile (dir </> ".codex" </> "agents" </> "reviewer.toml") "agent"
        items <- scanInstalledForProvider CodexLayout dir
        items
          `shouldMatchList` [ InstalledKitItem "module-readme" "skill" "codex",
                              InstalledKitItem "reviewer" "agent" "codex"
                            ]
