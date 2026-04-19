module Seihou.Evaluation.ConditionalTemplateSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text.IO qualified as TIO
import Seihou.Core.Types
import Seihou.Engine.Template (renderTemplate)
import Seihou.Engine.TemplatePrototype (renderTemplatePrototype)
import Seihou.Engine.TemplatePrototype qualified as Proto
import System.Directory (getCurrentDirectory)
import System.FilePath ((</>))
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Evaluation.ConditionalTemplate" spec

commonVars :: Map.Map VarName VarValue
commonVars =
  Map.fromList
    [ ("project.name", VText "demo-app"),
      ("project.description", VText "A demo Haskell application"),
      ("ghc.version", VText "ghc912"),
      ("nix.process-compose", VBool True)
    ]

fixtureSource :: IO Text
fixtureSource = do
  cwd <- getCurrentDirectory
  let path =
        cwd
          </> "test"
          </> "fixtures"
          </> "evaluation"
          </> "conditional-template-flake"
          </> "files"
          </> "flake.nix.tpl"
  TIO.readFile path

splitFlakeBaseline :: FilePath -> Map.Map VarName VarValue -> IO Text
splitFlakeBaseline tplName vars = do
  cwd <- getCurrentDirectory
  raw <-
    TIO.readFile
      ( cwd
          </> "test"
          </> "fixtures"
          </> "evaluation"
          </> "split-flake"
          </> "files"
          </> tplName
      )
  case renderTemplate raw vars of
    Left errs -> fail ("renderTemplate failed: " <> show errs)
    Right t -> pure t

spec :: Spec
spec = do
  describe "conditional-template-flake fixture (Prototype C)" $ do
    it "with nix.postgresql = false, produces bytes identical to the non-postgres baseline" $ do
      tpl <- fixtureSource
      let vars = Map.insert "nix.postgresql" (VBool False) commonVars
      case renderTemplatePrototype tpl vars of
        Left errs -> expectationFailure ("renderTemplatePrototype failed: " <> show errs)
        Right rendered -> do
          expected <- splitFlakeBaseline "flake.nix.tpl" vars
          rendered `shouldBe` expected

    it "with nix.postgresql = true, produces bytes identical to the postgres baseline" $ do
      tpl <- fixtureSource
      let vars = Map.insert "nix.postgresql" (VBool True) commonVars
      case renderTemplatePrototype tpl vars of
        Left errs -> expectationFailure ("renderTemplatePrototype failed: " <> show errs)
        Right rendered -> do
          expected <- splitFlakeBaseline "flake-with-postgres.nix.tpl" vars
          rendered `shouldBe` expected

    it "reports UnterminatedIf with the opener's line number" $ do
      let tpl = "line one\nline two\n{{#if Eq x true}}never closed\nline four\n"
          vars = Map.fromList [("x", VBool True)]
      case renderTemplatePrototype tpl vars of
        Right _ -> expectationFailure "expected UnterminatedIf"
        Left [Proto.UnterminatedIf lineNum] -> lineNum `shouldBe` 3
        Left other -> expectationFailure ("expected UnterminatedIf 3, got " <> show other)

    it "evaluates IsSet against an unset variable as False and excludes the block" $ do
      let tpl = "before\n{{#if IsSet maybe}}present\n{{/if}}after\n"
          vars = Map.empty
      case renderTemplatePrototype tpl vars of
        Left errs -> expectationFailure ("renderTemplatePrototype failed: " <> show errs)
        Right rendered -> rendered `shouldBe` "before\nafter\n"
