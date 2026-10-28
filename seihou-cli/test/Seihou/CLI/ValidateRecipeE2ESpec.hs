module Seihou.CLI.ValidateRecipeE2ESpec (tests) where

import Control.Monad (forM, forM_)
import Data.ByteString qualified as BS
import Data.List (sort)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.SeedRunE2ESpec (prepare)
import Seihou.CLI.SeihouBinary (seihouBinary)
import System.Directory qualified as D
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode)
import System.Timeout (timeout)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

-- Self-contained descriptors: offline with an empty Dhall cache.
recipe :: Text
recipe =
  T.unlines
    [ "let Var = { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
      "let Prompt = { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
      "in { name = \"my-stack\", version = None Text, description = None Text",
      ", modules = [{module = \"demo\", vars = [{name = \"member.only\", value = \"literal\"}]}]",
      ", vars = [ { name = \"github.enabled\", type = \"bool\", default = None Text, description = None Text, required = True, validation = None Text }",
      "         , { name = \"redpanda.enabled\", type = \"bool\", default = None Text, description = None Text, required = True, validation = None Text }",
      "         , { name = \"github.owner\", type = \"text\", default = None Text, description = None Text, required = True, validation = None Text } ]",
      ", prompts = [{var = \"github.owner\", text = \"Owner?\", when = Some \"Eq github.enabled true\", choices = None (List Text)}]",
      "}"
    ]

invoke :: FilePath -> FilePath -> FilePath -> [String] -> IO (ExitCode, Text)
invoke binary root cwd args = do
  inherited <- getEnvironment
  let overrides = [("XDG_CONFIG_HOME", root </> "config"), ("XDG_CACHE_HOME", root </> "cache"), ("XDG_DATA_HOME", root </> "data"), ("XDG_STATE_HOME", root </> "state")]
      environment = overrides <> filter (\(key, _) -> key `notElem` map fst overrides) inherited
  result <- timeout (15 * 1000000) $ readCreateProcessWithExitCode (proc binary args) {cwd = Just cwd, env = Just environment} ""
  case result of
    Nothing -> expectationFailure "validate-recipe did not terminate with closed stdin" >> pure (ExitFailure 99, "timeout")
    Just (code, out, err) -> pure (code, T.pack (out <> err))

-- Record directory entries as well as bytes. Only Dhall's evaluator cache is
-- excluded; Seihou's cache and all configuration/install state are included.
snapshot :: FilePath -> IO [(FilePath, Maybe BS.ByteString)]
snapshot root = go ""
  where
    go relative = do
      entries <- sort <$> D.listDirectory (root </> relative)
      fmap concat $ forM entries $ \entry -> do
        let path = relative </> entry
        if path == "cache/dhall"
          then pure []
          else do
            directory <- D.doesDirectoryExist (root </> path)
            if directory
              then ((path, Nothing) :) <$> go path
              else do
                bytes <- BS.readFile (root </> path)
                pure [(path, Just bytes)]

prepareState :: FilePath -> IO ()
prepareState root = do
  forM_ ["config/seihou/installed", "cache", "data", "state"] $ \dir -> D.createDirectoryIfMissing True (root </> dir)
  -- An invalid personal configuration must not be read by this command.
  TIO.writeFile (root </> "config/seihou/config.dhall") "not valid configuration"
  TIO.writeFile (root </> "config/seihou/installed/sentinel") "preserve me"

tests :: IO TestTree
tests = testSpec "ValidateRecipe" $ do
  it "validates unanswered conditional inputs with effectful members present, absent and on repeat" $
    withSystemTempDirectory "validate-recipe" $ \root -> do
      (binary, member) <- prepare root
      prepareState root
      TIO.writeFile
        (member </> "module.dhall")
        "let S = ./schema/package.dhall in S.Module::{name=\"demo\",version=Some \"1.0.0\",vars=[S.VarDecl::{name=\"answer\",type=\"text\",required=True}],prompts=[S.Prompt::{var=\"answer\",text=\"Answer?\"}],steps=[S.Step::{strategy=\"copy\",src=\"starter\",dest=\"generated.txt\"}],commands=[S.Command::{action=S.Command.Action.Apply \"touch command-marker\"}]}"
      (memberCode, memberOutput) <- invoke binary root root ["validate-module", member]
      if memberCode == ExitSuccess then pure () else expectationFailure (T.unpack memberOutput)
      let dir = root </> "recipe with spaces"
      D.createDirectory dir
      TIO.writeFile (dir </> "recipe.dhall") recipe
      forM_ [False, True] $ \removeMember -> do
        if removeMember then D.removePathForcibly member else pure ()
        forM_ [["validate-recipe", "recipe with spaces"], ["validate-recipe"]] $ \args -> do
          before <- snapshot root
          (code, output) <- invoke binary root (if length args == 1 then dir else root) args
          (code, output) `shouldBe` (ExitSuccess, "Recipe 'my-stack' is valid.\n")
          snapshot root `shouldReturn` before

  it "supports the ordinary new-recipe workflow without members or configuration" $
    withSystemTempDirectory "validate-recipe-scaffold" $ \root -> do
      binary <- seihouBinary
      (created, _) <- invoke binary root root ["new-recipe", "my-stack", "--module", "unpublished-member"]
      created `shouldBe` ExitSuccess
      before <- snapshot root
      (code, output) <- invoke binary root root ["validate-recipe", "my-stack"]
      code `shouldBe` ExitSuccess
      output `shouldSatisfy` T.isInfixOf "Recipe 'my-stack' is valid."
      snapshot root `shouldReturn` before

  it "reports missing descriptors with exit 4" $
    withSystemTempDirectory "validate-recipe-missing" $ \root -> do
      binary <- seihouBinary
      (code, output) <- invoke binary root root ["validate-recipe"]
      code `shouldBe` ExitFailure 4
      output `shouldSatisfy` T.isInfixOf "recipe.dhall not found"

  forM_ negativeCases $ \(label, descriptor, contexts) ->
    it ("rejects " <> label <> " without effects") $
      withSystemTempDirectory "validate-recipe-invalid" $ \root -> do
        binary <- seihouBinary
        prepareState root
        TIO.writeFile (root </> "recipe.dhall") descriptor
        before <- snapshot root
        (code, output) <- invoke binary root root ["validate-recipe"]
        code `shouldBe` ExitFailure 1
        forM_ ("recipe.dhall" : "invalid" : contexts) $ \context -> output `shouldSatisfy` T.isInfixOf context
        output `shouldSatisfy` (not . T.isInfixOf "DhallEvalError")
        snapshot root `shouldReturn` before

negativeCases :: [(String, Text, [Text])]
negativeCases =
  [ ("malformed Dhall", "{ invalid =", ["Invalid input"]),
    ("missing fields", "{name = \"my-stack\"}", ["missing fields", "modules", "vars", "prompts"]),
    ("non-record descriptor", "True", ["recipe record"]),
    ("wrong vars shape", replace "required = True" "required = \"yes\"", ["vars", "required"]),
    ("wrong field shape", replace "modules = [{module = \"demo\", vars = [{name = \"member.only\", value = \"literal\"}]}]" "modules = True", ["modules"]),
    ("invalid type", replace "type = \"bool\"" "type = \"mystery\"", ["type", "mystery"]),
    ("invalid nested type", replace "type = \"bool\"" "type = \"list mystery\"", ["type", "mystery"]),
    ("invalid default", replace "type = \"bool\", default = None Text" "type = \"bool\", default = Some \"invalid\"", ["default", "github.enabled"]),
    ("invalid condition syntax", replace "Eq github.enabled true" "Eq github.enabled", ["prompts", "github.owner", "when"]),
    ("empty members", replace "modules = [{module = \"demo\", vars = [{name = \"member.only\", value = \"literal\"}]}]" "modules = [] : List Text", ["modules", "at least one"]),
    ("invalid name", replace "name = \"my-stack\"" "name = \"BadName\"", ["name", "BadName"]),
    ("duplicate members", replace "modules = [{module = \"demo\", vars = [{name = \"member.only\", value = \"literal\"}]}]" "modules = [\"demo\", \"demo\"]", ["modules", "duplicate", "demo"]),
    ("invalid binding", replace "member.only" "INVALID", ["modules.vars", "INVALID", "demo"]),
    ("duplicate declarations", replace "name = \"redpanda.enabled\"" "name = \"github.enabled\"", ["vars", "duplicate", "github.enabled"]),
    ("undeclared target", replace "var = \"github.owner\"" "var = \"missing\"", ["prompts", "missing", "vars"]),
    ("nested undeclared condition", replace "Eq github.enabled true" "Eq github.enabled true || !(IsSet missing)", ["prompts", "github.owner", "when", "missing"]),
    ("multiple semantic errors", T.replace "var = \"github.owner\"" "var = \"missing\"" (replace "name = \"my-stack\"" "name = \"BadName\""), ["name", "BadName", "prompts", "missing"]),
    ("missing local import", "./missing.dhall", ["missing.dhall"])
  ]
  where
    replace old new = T.replace old new recipe
