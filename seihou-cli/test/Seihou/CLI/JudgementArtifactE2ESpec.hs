-- | A judgement is an ordinary installable artifact: through the real binary,
-- a registry entry is installed with @seihou install@, shown by @list@ and
-- @browse@, reported by @outdated@, and refreshed by @upgrade@. A judgement
-- that shares its directory with another definition file is refused.
module Seihou.CLI.JudgementArtifactE2ESpec (tests) where

import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KM
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
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), callProcess, proc, readCreateProcessWithExitCode)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "JudgementArtifactE2E" $ do
  it "installs a judgement from a registry, lists, browses, reports, and upgrades it" $
    withSystemTempDirectory "judgement-artifact" $ \root -> do
      run <- fixture root
      let producer = root </> "producers" </> "registry"
          installed = root </> "config" </> "seihou" </> "installed" </> "guard"
          source = "https://example.invalid/registry.git"
      writeProducer producer "0.1.0"
      callProcess "git" ["-C", producer, "init", "-q"]
      commit producer

      -- Install the judgement entry exactly as a prompt entry is installed.
      (installOut, _) <- expectExit ExitSuccess =<< run ["install", T.unpack source, "--module", "guard"]
      installOut `shouldSatisfy` T.isInfixOf "Installed guard"
      doesFileExist (installed </> "judgement.dhall") `shouldReturn` True
      doesFileExist (installed </> ".seihou-origin.json") `shouldReturn` True

      -- `seihou run` resolves the installed judgement through the ordinary
      -- search paths and reaches adoption (unconfigured here, so it stops
      -- before activating anything).
      (_, runOut, runErr) <- run ["run", "guard"]
      T.toLower (runOut <> runErr) `shouldSatisfy` T.isInfixOf "judgement 'guard'"
      (runOut <> runErr) `shouldNotSatisfy` T.isInfixOf "not found"

      -- List shows it in its own section; the kind filter narrows to it.
      (listed, _) <- expectExit ExitSuccess =<< run ["list"]
      listed `shouldSatisfy` T.isInfixOf "Judgements (1)"
      listed `shouldSatisfy` T.isInfixOf "Guards customer data"
      (filtered, _) <- expectExit ExitSuccess =<< run ["list", "--judgements"]
      filtered `shouldSatisfy` T.isInfixOf "1 judgement found"
      filtered `shouldNotSatisfy` T.isInfixOf "helper"

      -- Browse labels the registry entry with its kind.
      (browsed, _) <- expectExit ExitSuccess =<< run ["browse", T.unpack source]
      browsed `shouldSatisfy` T.isInfixOf "[judgement]  guard"

      -- A newer version is published: outdated sees it, upgrade refreshes it.
      writeJudgement (producer </> "guard") "guard" "0.2.0"
      commit producer
      (outdated, _) <- expectExit ExitSuccess =<< run ["outdated"]
      outdated `shouldSatisfy` hasRow "guard" "outdated"
      (upgraded, _) <- expectExit ExitSuccess =<< run ["upgrade", "guard", "--json"]
      case Aeson.eitherDecode (LBS.fromStrict (TE.encodeUtf8 upgraded)) of
        Right (Aeson.Array entries) ->
          V.toList entries
            `shouldContain` [ Aeson.Object
                                ( KM.fromList
                                    [ ("module", Aeson.String "guard"),
                                      ("oldVersion", Aeson.String "0.1.0"),
                                      ("newVersion", Aeson.String "0.2.0"),
                                      ("status", Aeson.String "upgraded")
                                    ]
                                )
                            ]
        other -> expectationFailure ("stdout is not a JSON array: " <> show other <> "\n" <> T.unpack upgraded)
      TIO.readFile (installed </> "judgement.dhall") >>= (`shouldSatisfy` T.isInfixOf "0.2.0")

      -- An entry whose directory also holds a module.dhall is ambiguous.
      (code, out, err) <- run ["install", T.unpack source, "--module", "mixed"]
      code `shouldBe` ExitFailure 1
      (out <> err) `shouldSatisfy` T.isInfixOf "ambiguous artifact"
      doesDirectoryExist (root </> "config" </> "seihou" </> "installed" </> "mixed") `shouldReturn` False

-- | A registry with a module @helper@, a judgement @guard@, and a judgement
-- entry @mixed@ whose directory also holds a module definition.
writeProducer :: FilePath -> Text -> IO ()
writeProducer producer version = do
  writeModule (producer </> "helper") "helper"
  writeJudgement (producer </> "guard") "guard" version
  writeModule (producer </> "mixed") "mixed"
  writeJudgement (producer </> "mixed") "mixed" "0.1.0"
  TIO.writeFile (producer </> "seihou-registry.dhall") $
    T.unlines
      [ "{ repoName = \"fixture\"",
        ", repoDescription = None Text",
        ", modules = [ { name = \"helper\", version = None Text, path = \"helper\", description = None Text, tags = [] : List Text } ]",
        ", judgements =",
        "  [ { name = \"guard\", version = None Text, path = \"guard\", description = Some \"Guards customer data\", tags = [] : List Text }",
        "  , { name = \"mixed\", version = None Text, path = \"mixed\", description = None Text, tags = [] : List Text }",
        "  ]",
        "}"
      ]

writeModule :: FilePath -> Text -> IO ()
writeModule dir name = do
  schema <- canonicalizePath "../schema/Module.dhall"
  createDirectoryIfMissing True dir
  TIO.writeFile (dir </> "module.dhall") ("let Module = " <> T.pack schema <> " in Module::{ name = \"" <> name <> "\", version = Some \"1.0.0\" }")

writeJudgement :: FilePath -> Text -> Text -> IO ()
writeJudgement dir name version = do
  schema <- canonicalizePath "../schema/package.dhall"
  createDirectoryIfMissing True dir
  TIO.writeFile (dir </> "judgement.dhall") $
    T.unlines
      [ "let S = " <> T.pack schema,
        "in  S.Judgement::{",
        "    , name = \"" <> name <> "\"",
        "    , version = Some \"" <> version <> "\"",
        "    , description = Some \"Guards customer data\"",
        "    , checks = [ S.Check::{ name = \"exposure\", question = \"Does this change expose customer data?\" } ]",
        "    }"
      ]

commit :: FilePath -> IO ()
commit repo = do
  callProcess "git" ["-C", repo, "add", "-A"]
  callProcess "git" ["-C", repo, "-c", "user.name=Seihou Test", "-c", "user.email=test@example.invalid", "commit", "--allow-empty", "-qm", "test: producer"]

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

-- | An isolated environment and a runner for the real binary. The producer is
-- reached at a portable URL rewritten to the local repository by a fixture git
-- config; configuration root, cache and home are private to this test.
fixture :: FilePath -> IO ([String] -> IO (ExitCode, Text, Text))
fixture root = do
  binary <- seihouBinary
  let project = root </> "project"
  mapM_ (createDirectoryIfMissing True) [project </> ".seihou", root </> "home", root </> "config", root </> "cache", root </> "producers" </> "registry"]
  writeFile (root </> "fixture-gitconfig") ("[url \"file://" <> root </> "producers" </> "registry\"]\n    insteadOf = https://example.invalid/registry.git\n")
  callProcess "git" ["-C", project, "init", "-q"]
  inherited <- getEnvironment
  let overrides =
        [ ("HOME", root </> "home"),
          ("XDG_CONFIG_HOME", root </> "config"),
          ("XDG_CACHE_HOME", root </> "cache"),
          ("GIT_CONFIG_GLOBAL", root </> "fixture-gitconfig"),
          ("PATH", fromMaybe "" (lookup "PATH" inherited))
        ]
      dropped = map fst overrides <> ["SEIHOU_CONTEXT"]
      environment = overrides <> filter (\(key, _) -> key `notElem` dropped && not ("SEIHOU_VAR_" `T.isPrefixOf` T.pack key)) inherited
  pure $ \args -> do
    (code, out, err) <- readCreateProcessWithExitCode (proc binary args) {cwd = Just project, env = Just environment} ""
    pure (code, T.pack out, T.pack err)
