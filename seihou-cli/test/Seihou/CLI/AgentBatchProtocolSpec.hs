module Seihou.CLI.AgentBatchProtocolSpec (tests) where

import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TE
import Seihou.CLI.AgentMigrationProtocol (batchRunRefusals, validateBatchRunOutput, validateMigrationOutput)
import Test.Hspec
import Test.Tasty (TestTree)
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.AgentMigrationProtocol batch runs" $ do
  describe "validateBatchRunOutput" $ do
    it "accepts a result object with no denials" $
      validateBatchRunOutput (bytes "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"permission_denials\":[],\"result\":\"done\"}")
        `shouldBe` Right "done"

    it "accepts the legacy shape without permission_denials or subtype" $
      validateBatchRunOutput (bytes "{\"result\":\"batch complete\",\"is_error\":false,\"session_id\":\"fake\"}")
        `shouldBe` Right "batch complete"

    it "accepts an event array whose last element is the result" $
      validateBatchRunOutput (bytes ("[{\"type\":\"system\",\"subtype\":\"init\"},{\"type\":\"assistant\",\"subtype\":null}," <> resultWith "[]" <> "]"))
        `shouldBe` Right "could not build"

    it "rejects a run that was refused one tool call, naming the command" $ do
      let output = "[{\"type\":\"system\",\"subtype\":\"init\"}," <> resultWith ("[" <> nixDenial <> "]") <> "]"
      err <- expectLeft (validateBatchRunOutput (bytes output))
      err `shouldSatisfy` Text.isInfixOf "Claude refused 1 tool call during this unattended run: Bash (nix build .#docs)."
      err `shouldSatisfy` Text.isInfixOf "allowedTools"

    it "counts every refusal but lists identical ones once" $ do
      let output = resultWith ("[" <> Text.intercalate "," [nixDenial, nixDenial, bunDenial] <> "]")
      err <- expectLeft (validateBatchRunOutput (bytes output))
      err `shouldSatisfy` Text.isInfixOf "Claude refused 3 tool calls during this unattended run: Bash (nix build .#docs), Bash (bun install)."

    it "names the file of a refused Write and the bare name of a tool with no input" $ do
      let output = resultWith "[{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/repo/.git/probe\",\"content\":\"x\"}},{\"tool_name\":\"WebFetch\"}]"
      err <- expectLeft (validateBatchRunOutput (bytes output))
      err `shouldSatisfy` Text.isInfixOf ": Write (/repo/.git/probe), WebFetch."

    it "lists ten refusals and summarises the rest" $ do
      let denial i = "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"step " <> Text.pack (show (i :: Int)) <> "\"}}"
          output = resultWith ("[" <> Text.intercalate "," (map denial [1 .. 12]) <> "]")
      err <- expectLeft (validateBatchRunOutput (bytes output))
      err `shouldSatisfy` Text.isInfixOf "Bash (step 10), and 2 more."
      err `shouldNotSatisfy` Text.isInfixOf "step 11"

    it "rejects an error result with its text" $ do
      err <- expectLeft (validateBatchRunOutput (bytes "{\"type\":\"result\",\"is_error\":true,\"result\":\"credit exhausted\"}"))
      err `shouldSatisfy` Text.isInfixOf "credit exhausted"

    it "rejects output that is not JSON" $ do
      err <- expectLeft (validateBatchRunOutput (bytes "not-json"))
      err `shouldSatisfy` Text.isInfixOf "not JSON"

    it "rejects a blank or missing result" $ do
      validateBatchRunOutput (bytes "{\"is_error\":false,\"result\":\"  \"}") `shouldBe` Left "Provider returned no assistant text."
      validateBatchRunOutput (bytes "{\"is_error\":false}") `shouldBe` Left "Provider returned no assistant text."
      _ <- expectLeft (validateBatchRunOutput (bytes "[]"))
      pure ()

  describe "batchRunRefusals" $ do
    it "reports refusals from parseable output and nothing otherwise" $ do
      batchRunRefusals (bytes (resultWith ("[" <> nixDenial <> "]"))) `shouldSatisfy` maybe False (Text.isInfixOf "Bash (nix build .#docs)")
      batchRunRefusals (bytes (resultWith "[]")) `shouldBe` Nothing
      batchRunRefusals (bytes "garbage") `shouldBe` Nothing

  describe "validateMigrationOutput" $
    it "keeps its wording and names each refused tool" $ do
      let output = "[" <> resultWith ("[" <> nixDenial <> "]") <> "]"
      err <- expectLeft (validateMigrationOutput True (bytes output))
      err `shouldSatisfy` Text.isPrefixOf "Claude reported permission denials: Bash (nix build .#docs). "
      err `shouldSatisfy` Text.isInfixOf "retry the same migration."

resultWith :: Text -> Text
resultWith denials =
  "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"result\":\"could not build\",\"permission_denials\":" <> denials <> "}"

nixDenial :: Text
nixDenial = "{\"tool_name\":\"Bash\",\"tool_use_id\":\"t1\",\"tool_input\":{\"command\":\"nix build .#docs\"}}"

bunDenial :: Text
bunDenial = "{\"tool_name\":\"Bash\",\"tool_use_id\":\"t2\",\"tool_input\":{\"command\":\"bun install\"}}"

bytes :: Text -> ByteString
bytes = TE.encodeUtf8

expectLeft :: Either Text Text -> IO Text
expectLeft (Left err) = pure err
expectLeft (Right body) = expectationFailure ("expected a failure, got " <> show body) >> pure ""
