-- | Judgements as ordinary artifacts: registry entries, registry validation
-- and synchronization, discovery, enumeration, and the ambiguity rule for a
-- @judgement.dhall@ that shares its directory with another definition file.
module Seihou.Core.JudgementArtifactSpec (tests) where

import Data.Generics.Labels ()
import Data.List (isInfixOf)
import Data.Text qualified as T
import Seihou.Core.Module (DiscoveredRunnable (..), RunnableKind (..), discoverAllRunnables, discoverRunnable)
import Seihou.Core.Registry
import Seihou.Core.Types (ModuleLoadError (..), ModuleName (..), Runnable (..))
import Seihou.Dhall.Eval (evalRegistryFromFile)
import Seihou.Prelude
import System.Directory (createDirectoryIfMissing, getCurrentDirectory)
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.JudgementArtifact" spec

entry :: Text -> FilePath -> RegistryEntry
entry n p = RegistryEntry (ModuleName n) Nothing p Nothing []

registry :: [RegistryEntry] -> [RegistryEntry] -> Registry
registry mods judgements =
  Registry
    { repoName = "fixture",
      repoDescription = Nothing,
      modules = mods,
      recipes = [],
      blueprints = [],
      prompts = [],
      judgements = judgements
    }

-- | A minimal judgement definition importing the local schema.
writeJudgement :: FilePath -> Text -> Text -> IO ()
writeJudgement dir name version = do
  cwd <- getCurrentDirectory
  createDirectoryIfMissing True dir
  writeFile (dir </> "judgement.dhall") $
    "let S = "
      <> cwd
      <> "/../schema/package.dhall in S.Judgement::{ name = \""
      <> T.unpack name
      <> "\", version = Some \""
      <> T.unpack version
      <> "\", description = Some \"Guards data\", checks = [ S.Check::{ name = \"c\", question = \"q?\" } ] }"

writeModule :: FilePath -> Text -> IO ()
writeModule dir name = do
  cwd <- getCurrentDirectory
  createDirectoryIfMissing True dir
  writeFile (dir </> "module.dhall") ("let S = " <> cwd <> "/../schema/package.dhall in S.Module::{ name = \"" <> T.unpack name <> "\" }")

spec :: Spec
spec = do
  describe "registry judgements" $ do
    it "decodes a registry with a judgement entry" $
      withSystemTempDirectory "judgement-registry" $ \tmp -> do
        writeFile (tmp </> "seihou-registry.dhall") $
          "{ repoName = \"r\", repoDescription = None Text\n\
          \, modules = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }\n\
          \, judgements = [ { name = \"guard\", version = Some \"0.1.0\", path = \"judgements/guard\", description = Some \"Guards data\", tags = [ \"review\" ] } ]\n\
          \}"
        result <- evalRegistryFromFile (tmp </> "seihou-registry.dhall")
        case result of
          Left err -> expectationFailure (show err)
          Right reg -> do
            reg ^. #judgements `shouldBe` [RegistryEntry (ModuleName "guard") (Just "0.1.0") "judgements/guard" (Just "Guards data") ["review"]]
            reg ^. #prompts `shouldBe` []

    it "decodes a legacy registry without a judgements field as an empty list" $
      withSystemTempDirectory "judgement-registry-legacy" $ \tmp -> do
        writeFile (tmp </> "seihou-registry.dhall") $
          "{ repoName = \"r\", repoDescription = None Text\n\
          \, modules = [ { name = \"m\", version = None Text, path = \"m\", description = None Text, tags = [] : List Text } ]\n\
          \, recipes = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }\n\
          \, blueprints = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }\n\
          \, prompts = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }\n\
          \}"
        result <- evalRegistryFromFile (tmp </> "seihou-registry.dhall")
        fmap (^. #judgements) result `shouldBe` Right []

    it "round-trips judgement entries through renderRegistryDhall" $
      withSystemTempDirectory "judgement-registry-emit" $ \tmp -> do
        let reg = registry [entry "m" "m"] [RegistryEntry (ModuleName "guard") (Just "0.1.0") "guard" (Just "Guards") ["a"]]
        writeFile (tmp </> "seihou-registry.dhall") (T.unpack (renderRegistryDhall reg))
        evalRegistryFromFile (tmp </> "seihou-registry.dhall") `shouldReturn` Right reg

    it "accepts a well-formed judgement entry" $
      withSystemTempDirectory "judgement-validate-ok" $ \tmp -> do
        writeJudgement (tmp </> "guard") "guard" "0.1.0"
        validateRegistry tmp (registry [] [entry "guard" "guard"]) `shouldReturn` []

    it "reports a judgement entry whose judgement.dhall is missing" $
      withSystemTempDirectory "judgement-validate-missing" $ \tmp -> do
        errs <- validateRegistry tmp (registry [] [entry "ghost" "ghost"])
        errs `shouldBe` ["registry judgement entry 'ghost' points to missing judgement.dhall at ghost"]

    it "reports an invalid name and an unsafe path" $
      withSystemTempDirectory "judgement-validate-unsafe" $ \tmp -> do
        errs <- validateRegistry tmp (registry [] [entry "Bad_Name" "../escape"])
        errs `shouldSatisfy` elem "registry judgement name must match [a-z][a-z0-9-]*, got: Bad_Name"
        errs `shouldSatisfy` elem "registry judgement path must not contain '..': ../escape"

    it "reports a judgement whose name collides with a module" $
      withSystemTempDirectory "judgement-validate-collision" $ \tmp -> do
        writeModule (tmp </> "modules" </> "shared") "shared"
        writeJudgement (tmp </> "judgements" </> "shared") "shared" "0.1.0"
        errs <- validateRegistry tmp (registry [entry "shared" "modules/shared"] [entry "shared" "judgements/shared"])
        errs `shouldBe` ["name collision: 'shared' appears as both a module and a judgement"]

    it "reports an entry directory where judgement.dhall sits next to module.dhall" $
      withSystemTempDirectory "judgement-validate-ambiguous" $ \tmp -> do
        writeModule (tmp </> "mixed") "mixed"
        writeJudgement (tmp </> "mixed") "mixed" "0.1.0"
        errs <- validateRegistry tmp (registry [] [entry "mixed" "mixed"])
        errs `shouldSatisfy` any (T.isInfixOf "ambiguous artifact 'mixed'")
        errs `shouldSatisfy` any (T.isInfixOf "module.dhall, judgement.dhall")

    it "classifies judgement version drift and counts judgements" $
      withSystemTempDirectory "judgement-validate-full" $ \tmp -> do
        writeJudgement (tmp </> "guard") "guard" "0.2.0"
        let reg = registry [] [RegistryEntry (ModuleName "guard") (Just "0.1.0") "guard" Nothing []]
            lookups = [(JudgementEntry, ModuleName "guard", Just "0.2.0")]
            report = computeRegistrySync reg lookups
        map (^. #status) (report ^. #diffs) `shouldBe` [SyncStale "0.2.0"]
        map (^. #kind) (report ^. #diffs) `shouldBe` [JudgementEntry]
        fmap (^. #version) (report ^. #updated . #judgements) `shouldBe` [Just "0.2.0"]
        full <- validateRegistryFull tmp reg lookups
        full ^. #judgementCount `shouldBe` 1
        map formatValidationIssue (full ^. #issues)
          `shouldBe` ["judgements.guard: registry version 0.1.0 does not match judgement.dhall version 0.2.0"]

    it "recognises a single-judgement repository root" $
      withSystemTempDirectory "judgement-single-root" $ \tmp -> do
        writeJudgement tmp "guard" "0.1.0"
        contents <- discoverRepoContents evalRegistryFromFile tmp
        case contents of
          SingleJudgement root -> root `shouldBe` tmp
          other -> expectationFailure ("expected SingleJudgement, got " <> show other)

  describe "judgement discovery" $ do
    it "discovers a judgement directory by name" $
      withSystemTempDirectory "judgement-discover" $ \tmp -> do
        writeJudgement (tmp </> "guard") "guard" "0.1.0"
        result <- discoverRunnable [tmp] (ModuleName "guard")
        case result of
          Right (RunnableJudgement def dir) -> do
            def ^. #name `shouldBe` "guard"
            dir `shouldBe` tmp </> "guard"
          Right _ -> expectationFailure "expected a judgement"
          Left err -> expectationFailure (show err)

    it "rejects a judgement co-located with a module as AmbiguousArtifact" $
      withSystemTempDirectory "judgement-ambiguous" $ \tmp -> do
        writeModule (tmp </> "mixed") "mixed"
        writeJudgement (tmp </> "mixed") "mixed" "0.1.0"
        result <- discoverRunnable [tmp] (ModuleName "mixed")
        case result of
          Left (AmbiguousArtifact name dir files) -> do
            name `shouldBe` ModuleName "mixed"
            dir `shouldBe` tmp </> "mixed"
            files `shouldBe` ["module.dhall", "judgement.dhall"]
          Left err -> expectationFailure ("expected AmbiguousArtifact, got " <> show err)
          Right _ -> expectationFailure "expected AmbiguousArtifact, got a runnable"

    it "keeps module precedence for combinations without a judgement" $
      withSystemTempDirectory "judgement-no-ambiguity" $ \tmp -> do
        writeModule (tmp </> "plain") "plain"
        writeFile (tmp </> "plain" </> "prompt.dhall") "this is never read"
        result <- discoverRunnable [tmp] (ModuleName "plain")
        case result of
          Right (RunnableModule _ _) -> pure ()
          Right _ -> expectationFailure "expected the module"
          Left err -> expectationFailure (show err)

    it "enumerates judgements with their kind, and an ambiguous directory as an error" $
      withSystemTempDirectory "judgement-enumerate" $ \tmp -> do
        writeJudgement (tmp </> "guard") "guard" "0.1.0"
        writeModule (tmp </> "mixed") "mixed"
        writeJudgement (tmp </> "mixed") "mixed" "0.1.0"
        found <- discoverAllRunnables [tmp]
        let rows = [(r ^. #name, r ^. #kind, r ^. #isError, r ^. #description) | r <- found]
        rows `shouldSatisfy` elem ("guard", KindJudgement, False, Just "Guards data")
        case [r | r <- found, r ^. #name == "mixed"] of
          [r] -> do
            r ^. #kind `shouldBe` KindJudgement
            r ^. #isError `shouldBe` True
            fmap T.unpack (r ^. #error) `shouldSatisfy` maybe False ("judgement.dhall" `isInfixOf`)
          other -> expectationFailure ("expected one row for mixed, got " <> show (length other))
