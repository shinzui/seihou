module Seihou.CLI.JudgementCheckSpec (tests) where

import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Either (isLeft)
import Data.Generics.Labels ()
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Seihou.CLI.AgentCompletion (AgentProvider (..))
import Seihou.CLI.Judgement.Adopt
import Seihou.CLI.Judgement.Check
import Seihou.CLI.Judgement.Evidence (gitBytes)
import Seihou.CLI.Judgement.Hooks
import Seihou.CLI.Judgement.Runtime (JudgementBackend (..), JudgementRoute (..))
import Seihou.CLI.Judgement.Scanner (findScanner)
import Seihou.Core.Judgement
import Seihou.Core.Types (ActiveJudgement (..), JudgementSource (..), ManifestSchemaVersion (..))
import Seihou.Dhall.Eval (evalJudgementFromFile)
import Seihou.Manifest.Judgement (definitionDigest)
import Seihou.Manifest.Types (manifestFromJSON)
import Seihou.Prelude
import System.Directory (createDirectoryIfMissing, doesFileExist, executable, getPermissions)
import System.FilePath (takeDirectory)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (callProcess)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

git :: FilePath -> [String] -> IO ()
git dir args = callProcess "git" (["-C", dir, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "-c", "commit.gpgsign=false"] <> args)

writeAt :: FilePath -> FilePath -> Text -> IO ()
writeAt dir p body = do
  createDirectoryIfMissing True (takeDirectory (dir </> p))
  BS.writeFile (dir </> p) (TE.encodeUtf8 body)

withRepo :: (FilePath -> IO a) -> IO a
withRepo act = withSystemTempDirectory "judgement-check" $ \dir -> do
  git dir ["init", "-q"]
  git dir ["commit", "-q", "--allow-empty", "-m", "init"]
  act dir

-- | A judgement with nothing to do with secrets: two checks with different
-- thresholds, the second asked in the direction where no is the concern.
docsJudgement :: JudgementDefinition
docsJudgement =
  JudgementDefinition
    { name = "docs-review",
      version = Just "1.0.0",
      description = Nothing,
      instructions = "Review documentation changes.",
      evidence = EvidenceDeclaration [StagedChangesScope] ["docs/**"] [],
      limits = defaultCoverageLimits,
      deterministicChecks = [],
      checks =
        JudgementCheck "stale-docs" "Does this change leave documented behaviour out of date?" Yes Nothing Nothing [] Enforced High (Thresholds 0.5 0.1) (Thresholds 0.9 0.05) True
          :| [JudgementCheck "has-example" "Does every new command in this change come with an example?" No Nothing Nothing [] Advisory High (Thresholds 0.8 0.4) (Thresholds 0.9 0.05) True]
    }

active :: JudgementDefinition -> ActiveJudgement
active def = ActiveJudgement BundledJudgement def (definitionDigest def) (defaultPolicy ApprovedRemote False def)

-- | A backend that answers each check with a fixed probability of yes and
-- counts requests.
stub :: IORef Int -> (Text -> Double) -> JudgementBackend
stub calls yesFor =
  JudgementBackend
    { review = \_ c _ -> modifyIORef' calls (+ 1) >> pure (Right (RawReview (concernProbability (c ^. #concernWhen) (yesFor (c ^. #name))) [] False)),
      gate = Nothing,
      observed = pure []
    }

servicesWith :: FilePath -> Maybe JudgementBackend -> IO CheckServices
servicesWith root be = do
  sc <- findScanner
  pure (CheckServices (gitBytes root) sc (\_ -> pure (Right (BackendChoice be True (Just "stub model")))))

request :: CheckRequest
request = CheckRequest Nothing Nothing False False

tests :: IO TestTree
tests = testSpec "judgement check, adoption and hooks" $ do
  describe "the bundled catalogue" $
    it "decodes and validates security-review with the secret scan declared" $ do
      r <- evalJudgementFromFile "data/judgements/security-review/judgement.dhall"
      case r of
        Left e -> expectationFailure (show e)
        Right d -> do
          d ^. #name `shouldBe` "security-review"
          d ^. #deterministicChecks `shouldBe` [SecretScan]
          validateDefinition d `shouldBe` Right ()

  describe "seihou check" $ do
    it "reports nothing to check when no judgement is active" $ withRepo $ \dir -> do
      services <- servicesWith dir Nothing
      out <- runCheck services [] request
      out ^. #exitCode `shouldBe` 0
      out ^. #output `shouldSatisfy` T.isInfixOf "nothing was checked"
    it "refuses a named judgement that is not active" $ withRepo $ \dir -> do
      services <- servicesWith dir Nothing
      out <- runCheck services [active docsJudgement] (request & #judgement ?~ "other")
      out ^. #exitCode `shouldBe` 1
      out ^. #output `shouldSatisfy` T.isInfixOf "seihou run other"
    it "runs a non-security judgement whose two checks reach their own outcomes" $ withRepo $ \dir -> do
      writeAt dir "docs/guide.md" "Run `demo sync` to refresh the cache.\n"
      writeAt dir "src/Main.hs" "main = pure ()\n"
      git dir ["add", "."]
      calls <- newIORef 0
      services <- servicesWith dir (Just (stub calls (\case "stale-docs" -> 0.3; _ -> 0.5)))
      out <- runCheck services [active docsJudgement] request
      -- stale-docs: 0.3 sits between pass 0.1 and block 0.5. has-example is
      -- advisory with a concern of 1 - 0.5 = 0.5, inside its own band.
      out ^. #exitCode `shouldBe` 11
      out ^. #output `shouldSatisfy` T.isInfixOf "stale-docs  needs review"
      out ^. #output `shouldSatisfy` T.isInfixOf "has-example  needs review (advisory)"
      out ^. #output `shouldSatisfy` T.isInfixOf "one minus the model's probability of yes"
      readIORef calls >>= (`shouldBe` 2)
    it "passes when every enforced check is at or below its pass threshold, and agrees in JSON" $ withRepo $ \dir -> do
      writeAt dir "docs/guide.md" "Run `demo sync` to refresh the cache.\n"
      git dir ["add", "."]
      calls <- newIORef 0
      services <- servicesWith dir (Just (stub calls (\case "stale-docs" -> 0.05; _ -> 0.95)))
      out <- runCheck services [active docsJudgement] request
      out ^. #exitCode `shouldBe` 0
      json <- runCheck services [active docsJudgement] (request & #json .~ True)
      json ^. #exitCode `shouldBe` 0
      json ^. #output `shouldSatisfy` T.isInfixOf "\"exitCode\":0"
    it "makes no model request on a dry run and never claims approval" $ withRepo $ \dir -> do
      writeAt dir "docs/guide.md" "Text.\n"
      git dir ["add", "."]
      calls <- newIORef 0
      services <- servicesWith dir (Just (stub calls (const 0.0)))
      out <- runCheck services [active docsJudgement] (request & #dryRun .~ True)
      out ^. #exitCode `shouldBe` 0
      out ^. #output `shouldSatisfy` T.isInfixOf "nothing was approved"
      readIORef calls >>= (`shouldBe` 0)

  describe "pre-commit hooks" $ do
    it "installs an owned hook, then recognises it" $ withRepo $ \dir -> do
      Right plan <- planHook dir (gitBytes dir)
      plan `shouldBe` HookInstall (dir </> ".git" </> "hooks" </> "pre-commit")
      applyHook plan `shouldReturn` Right ()
      body <- TIO.readFile (dir </> ".git" </> "hooks" </> "pre-commit")
      body `shouldSatisfy` T.isInfixOf hookMarker
      executable <$> getPermissions (dir </> ".git" </> "hooks" </> "pre-commit") `shouldReturn` True
      planHook dir (gitBytes dir) `shouldReturn` Right (HookAlreadyInstalled (dir </> ".git" </> "hooks" </> "pre-commit"))
    it "preserves a user's hook byte for byte and runs it first" $ withRepo $ \dir -> do
      let hook = dir </> ".git" </> "hooks" </> "pre-commit"
          original = "#!/bin/sh\necho mine\n"
      writeAt dir ".git/hooks/pre-commit" original
      Right plan <- planHook dir (gitBytes dir)
      plan `shouldBe` HookChain hook (hook <> ".seihou-original")
      applyHook plan `shouldReturn` Right ()
      TIO.readFile (hook <> ".seihou-original") `shouldReturn` original
      TIO.readFile hook >>= (`shouldSatisfy` T.isInfixOf "pre-commit.seihou-original")
    it "sits beside a pre-commit framework hook without replacing it" $ withRepo $ \dir -> do
      let framework = "#!/usr/bin/env bash\n# File generated by pre-commit: https://pre-commit.com\n"
      writeAt dir ".git/hooks/pre-commit" framework
      Right plan <- planHook dir (gitBytes dir)
      plan `shouldBe` HookBesideFramework (dir </> ".git" </> "hooks" </> "pre-commit.legacy")
      applyHook plan `shouldReturn` Right ()
      TIO.readFile (dir </> ".git" </> "hooks" </> "pre-commit") `shouldReturn` framework
    it "refuses a core.hooksPath outside the repository but accepts one inside it" $ withRepo $ \dir -> withSystemTempDirectory "shared-hooks" $ \shared -> do
      git dir ["config", "core.hooksPath", shared]
      planHook dir (gitBytes dir) >>= (`shouldSatisfy` isLeft)
      git dir ["config", "core.hooksPath", ".git/hooks"]
      planHook dir (gitBytes dir) >>= (`shouldSatisfy` \case Right (HookInstall _) -> True; _ -> False)

  describe "adoption" $ do
    let route = Just (JudgementRoute AgentProviderClaudeCli "claude-sonnet-5")
    it "names the configuration to set when no route or consent is given" $ withRepo $ \dir -> do
      sc <- findScanner
      Left noRoute <- planAdoption dir (AdoptionInputs Nothing Nothing sc) (Just ApprovedRemote) BundledJudgement docsJudgement
      noRoute `shouldSatisfy` T.isInfixOf "seihou config set judgement.provider"
      Left noConsent <- planAdoption dir (AdoptionInputs route Nothing sc) Nothing BundledJudgement docsJudgement
      noConsent `shouldSatisfy` T.isInfixOf "judgement.dataPolicy approved-remote"
      doesFileExist (dir </> ".seihou" </> "manifest.json") `shouldReturn` False
    it "records the snapshot at schema 15 and installs the hook, idempotently" $ withRepo $ \dir -> do
      sc <- findScanner
      case sc of
        Nothing -> pendingWith "gitleaks is not on PATH"
        Just _ -> do
          Right plan <- planAdoption dir (AdoptionInputs route (Just ApprovedRemote) sc) (Just ApprovedRemote) BundledJudgement docsJudgement
          applyAdoption plan `shouldReturn` Right ()
          Right m <- manifestFromJSON . LBS.fromStrict <$> BS.readFile (dir </> ".seihou" </> "manifest.json")
          m ^. #version `shouldBe` ManifestSchemaVersion 15
          map (^. #definition . #name) (m ^. #judgements) `shouldBe` ["docs-review"]
          TIO.readFile (dir </> ".git" </> "hooks" </> "pre-commit") >>= (`shouldSatisfy` T.isInfixOf hookMarker)
          Right again <- planAdoption dir (AdoptionInputs route (Just ApprovedRemote) sc) (Just ApprovedRemote) BundledJudgement docsJudgement
          renderAdoptionPlan again `shouldSatisfy` T.isInfixOf "nothing changes"
          applyAdoption again `shouldReturn` Right ()
          Right m' <- manifestFromJSON . LBS.fromStrict <$> BS.readFile (dir </> ".seihou" </> "manifest.json")
          length (m' ^. #judgements) `shouldBe` 1
