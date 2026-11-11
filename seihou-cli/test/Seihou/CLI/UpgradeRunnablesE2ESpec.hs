-- | @seihou upgrade@ refreshes an installed blueprint end to end, through the
-- real binary, from a producer repository reached at a portable URL.
module Seihou.CLI.UpgradeRunnablesE2ESpec (tests) where

import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Data.Vector qualified as V
import Seihou.CLI.SeihouBinary (seihouBinary)
import System.Directory
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath (searchPathSeparator, (</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), callProcess, proc, readCreateProcessWithExitCode)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "UpgradeRunnablesE2E" $ do
  it "refreshes an installed blueprint, reports it, and refuses one without provenance" $
    withSystemTempDirectory "upgrade-runnables" $ \root -> do
      run <- fixture root
      let producer = root </> "producers" </> "bp"
          installed = root </> "config" </> "seihou" </> "installed" </> "bp"
          bump version = writeBlueprint (producer </> "blueprint.dhall") version >> commit producer

      -- 1. Install 0.1.0 from the portable URL.
      writeBlueprint (producer </> "blueprint.dhall") "0.1.0"
      callProcess "git" ["-C", producer, "init", "-q"]
      commit producer
      _ <- expectExit ExitSuccess =<< run ["install", "https://example.invalid/bp.git"]

      -- 2-3. A newer version is published. Outdated sees it; a named upgrade
      -- picks it up and reports old and new versions in a clean JSON document.
      bump "0.1.1"
      (outdated, _) <- expectExit ExitSuccess =<< run ["outdated"]
      outdated `shouldSatisfy` hasRow "bp" "outdated"
      upgraded <- expectExit ExitSuccess =<< run ["upgrade", "bp", "--json"]
      case Aeson.eitherDecode (LBS.fromStrict (TE.encodeUtf8 (fst upgraded))) of
        Right (Aeson.Array entries) ->
          V.toList entries
            `shouldContain` [ Aeson.Object
                                ( KM.fromList
                                    [ ("module", Aeson.String "bp"),
                                      ("oldVersion", Aeson.String "0.1.0"),
                                      ("newVersion", Aeson.String "0.1.1"),
                                      ("status", Aeson.String "upgraded")
                                    ]
                                )
                            ]
        other -> expectationFailure ("stdout is not a JSON array: " <> show other <> "\n" <> T.unpack (fst upgraded))

      -- 4. The agent now sees the refreshed blueprint.
      (debugOut, debugErr) <- expectExit ExitSuccess =<< run ["agent", "--debug", "run", "bp"]
      (debugOut <> debugErr) `shouldSatisfy` T.isInfixOf "Version: 0.1.1"

      -- 5. A second run has nothing to do.
      (current, _) <- expectExit ExitSuccess =<< run ["upgrade", "bp"]
      current `shouldSatisfy` T.isInfixOf "up to date"

      -- 6. With no names, installed blueprints are refreshed too.
      bump "0.1.2"
      (everything, _) <- expectExit ExitSuccess =<< run ["upgrade"]
      everything `shouldSatisfy` hasRow "bp" "upgraded"
      TIO.readFile (installed </> "blueprint.dhall") >>= (`shouldSatisfy` T.isInfixOf "0.1.2")

      -- 7. Without provenance a named refresh is refused and the cache kept;
      -- an unnamed run leaves the entry alone, as it does unprovenanced modules.
      removeFile (installed </> ".seihou-origin.json")
      bump "0.1.3"
      before <- BS.readFile (installed </> "blueprint.dhall")
      (refused, refusedErr) <- expectExit (ExitFailure 1) =<< run ["upgrade", "bp"]
      (refused <> refusedErr) `shouldSatisfy` T.isInfixOf "no origin metadata"
      refused `shouldSatisfy` hasRow "bp" "failed"
      BS.readFile (installed </> "blueprint.dhall") `shouldReturn` before
      (unnamed, _) <- expectExit ExitSuccess =<< run ["upgrade"]
      unnamed `shouldNotSatisfy` T.isInfixOf "no origin metadata"
      BS.readFile (installed </> "blueprint.dhall") `shouldReturn` before

-- | A row in the text table whose first column is the name and whose status
-- column starts with the given word.
hasRow :: Text -> Text -> Text -> Bool
hasRow name status output =
  any
    ( \line -> case T.words line of
        (first : rest) -> first == name && any (T.isPrefixOf status) rest
        [] -> False
    )
    (T.lines output)

expectExit :: ExitCode -> (ExitCode, Text, Text) -> IO (Text, Text)
expectExit expected (code, out, err) = do
  if code == expected
    then pure ()
    else expectationFailure ("expected " <> show expected <> ", got " <> show code <> "\nstdout:\n" <> T.unpack out <> "\nstderr:\n" <> T.unpack err)
  pure (out, err)

-- | Build the isolated environment and return a runner for the real binary.
-- The producer is reached at a portable URL rewritten to the local repository
-- by a fixture git config; the configuration root, home, and agent provider
-- are all private to this test. The fake @claude@ exists so @agent run@ never
-- reaches a real provider.
fixture :: FilePath -> IO ([String] -> IO (ExitCode, Text, Text))
fixture root = do
  binary <- seihouBinary
  let project = root </> "project"
      fakeBin = root </> "bin"
      fakeClaude = fakeBin </> "claude"
  mapM_ (createDirectoryIfMissing True) [project </> ".seihou", root </> "home", root </> "config", root </> "cache", fakeBin, root </> "producers" </> "bp"]
  TIO.writeFile
    fakeClaude
    "#!/bin/sh\nprintf '%s\\n' '{\"result\":\"agent complete\",\"is_error\":false,\"session_id\":\"fake\"}'\n"
  permissions <- getPermissions fakeClaude
  -- Permissions has no Generic instance, so it has no #executable label.
  setPermissions fakeClaude (permissions {executable = True})
  writeFile (root </> "fixture-gitconfig") ("[url \"file://" <> root </> "producers" </> "bp\"]\n    insteadOf = https://example.invalid/bp.git\n")
  callProcess "git" ["-C", project, "init", "-q"]
  inherited <- getEnvironment
  let inheritedPath = fromMaybe "" (lookup "PATH" inherited)
      overrides =
        [ ("PATH", fakeBin <> [searchPathSeparator] <> inheritedPath),
          ("HOME", root </> "home"),
          ("XDG_CONFIG_HOME", root </> "config"),
          ("XDG_CACHE_HOME", root </> "cache"),
          ("GIT_CONFIG_GLOBAL", root </> "fixture-gitconfig"),
          ("SEIHOU_AGENT_PROVIDER", "claude-cli")
        ]
      dropped = map fst overrides <> ["SEIHOU_AGENT_MODEL", "SEIHOU_AGENT_EFFORT", "SEIHOU_CONTEXT"]
      environment = overrides <> filter (\(key, _) -> key `notElem` dropped && not ("SEIHOU_VAR_" `T.isPrefixOf` T.pack key)) inherited
  pure $ \args -> do
    (code, out, err) <- readCreateProcessWithExitCode (proc binary args) {cwd = Just project, env = Just environment} ""
    pure (code, T.pack out, T.pack err)

commit :: FilePath -> IO ()
commit repo = do
  callProcess "git" ["-C", repo, "add", "-A"]
  callProcess "git" ["-C", repo, "-c", "user.name=Seihou Test", "-c", "user.email=test@example.invalid", "commit", "--allow-empty", "-qm", "test: blueprint release"]

writeBlueprint :: FilePath -> Text -> IO ()
writeBlueprint path version =
  TIO.writeFile path $
    T.unlines
      [ "{ name = \"bp\"",
        ", version = Some \"" <> version <> "\"",
        ", description = Some \"Upgrade fixture\"",
        ", prompt = \"Do the work.\"",
        ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
        ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
        ", baseModules = [] : List { module : Text, vars : List { name : Text, value : Text } }",
        ", files = [] : List { src : Text, description : Optional Text }",
        ", allowedTools = None (List Text)",
        ", tags = [] : List Text",
        "}"
      ]
