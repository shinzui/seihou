module Seihou.Core.CommandVarSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Effectful (runPureEff)
import Numeric.Natural (Natural)
import Seihou.Core.CommandVar (planCommandVars, resolveCommandVars)
import Seihou.Core.Types
import Seihou.Effect.ProcessPure (ProcessMock (..), runProcessPure)
import System.Exit (ExitCode (..))
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.CommandVar" spec

textDecl :: VarName -> VarDecl
textDecl name = VarDecl name VTText Nothing Nothing False Nothing

boolDecl :: VarName -> VarDecl
boolDecl name = VarDecl name VTBool Nothing Nothing False Nothing

intDecl :: VarName -> VarDecl
intDecl name = VarDecl name VTInt Nothing Nothing False Nothing

patternDecl :: VarName -> VarDecl
patternDecl name = VarDecl name VTText Nothing Nothing False (Just (ValPattern "[a-z][a-z0-9-]*"))

cmdVar :: VarName -> T.Text -> CommandVar
cmdVar name run =
  CommandVar
    { name = name,
      run = run,
      workDir = Nothing,
      condition = Nothing,
      trim = True,
      maxBytes = Just 4096
    }

withCondition :: Maybe Expr -> CommandVar -> CommandVar
withCondition condition cv =
  CommandVar cv.name cv.run cv.workDir condition cv.trim cv.maxBytes

withTrim :: Bool -> CommandVar -> CommandVar
withTrim trim cv =
  CommandVar cv.name cv.run cv.workDir cv.condition trim cv.maxBytes

withMaxBytes :: Maybe Natural -> CommandVar -> CommandVar
withMaxBytes maxBytes cv =
  CommandVar cv.name cv.run cv.workDir cv.condition cv.trim maxBytes

commandVarName :: CommandVar -> VarName
commandVarName cv = cv.name

commandVarRun :: CommandVar -> T.Text
commandVarRun cv = cv.run

mock :: T.Text -> ExitCode -> T.Text -> T.Text -> ProcessMock
mock run exitCode stdoutText stderrText =
  ProcessMock
    { mockCommand = "sh",
      mockArgs = ["-c", run],
      mockResult = (exitCode, stdoutText, stderrText)
    }

runResolve ::
  [VarDecl] ->
  [CommandVar] ->
  Map.Map VarName ResolvedVar ->
  [ProcessMock] ->
  Either [VarError] (Map.Map VarName ResolvedVar)
runResolve decls commandVars existing mocks =
  runPureEff $
    runProcessPure mocks $
      resolveCommandVars decls commandVars existing

resolved :: VarDecl -> VarValue -> VarSource -> ResolvedVar
resolved decl value source = ResolvedVar {value = value, source = source, decl = decl}

spec :: Spec
spec = do
  describe "planCommandVars" $ do
    it "skips already-resolved variables and false conditions" $ do
      let branchDecl = textDecl "git.branch"
          readyDecl = boolDecl "release.ready"
          existing = Map.singleton "git.branch" (resolved branchDecl (VText "configured") FromLocalConfig)
          bindings = Map.singleton "release.ready" (VBool False)
          planned =
            planCommandVars
              [ cmdVar "git.branch" "git branch --show-current",
                withCondition (Just (ExprIsSet "git.branch")) (cmdVar "release.notes" "git log"),
                withCondition (Just (ExprEq "release.ready" (VBool True))) (cmdVar "release.ready" "echo true")
              ]
              existing
              bindings
      map commandVarName planned `shouldBe` ["release.notes"]

  describe "resolveCommandVars" $ do
    it "resolves text and bool values from command output" $ do
      let branch = cmdVar "git.branch" "git branch --show-current"
          ready = cmdVar "release.ready" "printf true"
          result =
            runResolve
              [textDecl "git.branch", boolDecl "release.ready"]
              [branch, ready]
              Map.empty
              [ mock (commandVarRun branch) ExitSuccess "main\n" "",
                mock (commandVarRun ready) ExitSuccess "true\n" ""
              ]
      case result of
        Right m -> do
          fmap (.value) (Map.lookup "git.branch" m) `shouldBe` Just (VText "main")
          fmap (.value) (Map.lookup "release.ready" m) `shouldBe` Just (VBool True)
          fmap (.source) (Map.lookup "git.branch" m) `shouldBe` Just (FromCommand "git branch --show-current")
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "does not override already-resolved config values" $ do
      let decl = textDecl "git.branch"
          existing = Map.singleton "git.branch" (resolved decl (VText "configured") FromLocalConfig)
          branch = cmdVar "git.branch" "git branch --show-current"
          result =
            runResolve
              [decl]
              [branch]
              existing
              [mock (commandVarRun branch) ExitSuccess "main\n" ""]
      result `shouldBe` Right existing

    it "coerces int output using the matching declaration" $ do
      let count = cmdVar "change.count" "git diff --numstat"
          result =
            runResolve
              [intDecl "change.count"]
              [count]
              Map.empty
              [mock (commandVarRun count) ExitSuccess "42\n" ""]
      fmap (fmap (.value) . Map.lookup "change.count") result `shouldBe` Right (Just (VInt 42))

    it "uses a text declaration for command-only prompt variables" $ do
      let branch = cmdVar "git.branch" "git branch --show-current"
          result =
            runResolve
              []
              [branch]
              Map.empty
              [mock (commandVarRun branch) ExitSuccess "main\n" ""]
      fmap (fmap (.value) . Map.lookup "git.branch") result `shouldBe` Right (Just (VText "main"))

    it "preserves untrimmed output when trim is false" $ do
      let branch = withTrim False (cmdVar "git.branch" "git branch --show-current")
          result =
            runResolve
              [textDecl "git.branch"]
              [branch]
              Map.empty
              [mock (commandVarRun branch) ExitSuccess "main\n" ""]
      fmap (fmap (.value) . Map.lookup "git.branch") result `shouldBe` Right (Just (VText "main\n"))

    it "rejects output that exceeds maxBytes" $ do
      let branch = withMaxBytes (Just 3) (cmdVar "git.branch" "git branch --show-current")
          result =
            runResolve
              [textDecl "git.branch"]
              [branch]
              Map.empty
              [mock (commandVarRun branch) ExitSuccess "main\n" ""]
      case result of
        Left [ValidationFailed "git.branch" msg] ->
          msg `shouldSatisfy` T.isInfixOf "exceeds maxBytes"
        other -> expectationFailure ("Expected maxBytes failure, got: " <> show other)

    it "reports non-zero command exits with stderr" $ do
      let branch = cmdVar "git.branch" "git branch --show-current"
          result =
            runResolve
              [textDecl "git.branch"]
              [branch]
              Map.empty
              [mock (commandVarRun branch) (ExitFailure 2) "" "not a git repo\n"]
      case result of
        Left [ValidationFailed "git.branch" msg] -> do
          msg `shouldSatisfy` T.isInfixOf "exit code 2"
          msg `shouldSatisfy` T.isInfixOf "not a git repo"
        other -> expectationFailure ("Expected command failure, got: " <> show other)

    it "skips commands with false conditions" $ do
      let branch =
            withCondition
              (Just (ExprEq "release.ready" (VBool True)))
              (cmdVar "git.branch" "git branch --show-current")
          result =
            runResolve
              [textDecl "git.branch"]
              [branch]
              (Map.singleton "release.ready" (resolved (boolDecl "release.ready") (VBool False) FromDefault))
              [mock (commandVarRun branch) ExitSuccess "main\n" ""]
      fmap (Map.member "git.branch") result `shouldBe` Right False

    it "validates coerced values against declaration validation" $ do
      let branch = cmdVar "git.branch" "git branch --show-current"
          result =
            runResolve
              [patternDecl "git.branch"]
              [branch]
              Map.empty
              [mock (commandVarRun branch) ExitSuccess "Bad_Branch\n" ""]
      case result of
        Left [ValidationFailed "git.branch" msg] ->
          msg `shouldSatisfy` T.isInfixOf "value does not match pattern"
        other -> expectationFailure ("Expected validation failure, got: " <> show other)
