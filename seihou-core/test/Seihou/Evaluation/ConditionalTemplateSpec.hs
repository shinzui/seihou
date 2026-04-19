module Seihou.Evaluation.ConditionalTemplateSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text.IO qualified as TIO
import Seihou.Core.Module (loadModule)
import Seihou.Core.Types
import Seihou.Engine.Plan (compilePlan)
import Seihou.Engine.Template (renderTemplate)
import System.Directory (getCurrentDirectory)
import System.FilePath (takeDirectory, (</>))
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Evaluation.ConditionalTemplate" spec

-- | Variable set shared by both postgres on/off runs.
commonVars :: Map.Map VarName VarValue
commonVars =
  Map.fromList
    [ ("project.name", VText "demo-app"),
      ("project.description", VText "A demo Haskell application"),
      ("ghc.version", VText "ghc912"),
      ("nix.process-compose", VBool True)
    ]

fixtureDir :: IO FilePath
fixtureDir = do
  cwd <- getCurrentDirectory
  pure (cwd </> "test" </> "fixtures" </> "evaluation" </> "conditional-template-flake")

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
  describe "conditional-template-flake fixture (compilePlan)" $ do
    it "with nix.postgresql = false, emits bytes identical to the non-postgres split-flake baseline" $ do
      base <- fixtureDir
      Right modul <- loadModule [takeDirectory base] "conditional-template-flake"
      let vars = Map.insert "nix.postgresql" (VBool False) commonVars
      planResult <- compilePlan base modul vars
      case planResult of
        Left errs -> expectationFailure ("compilePlan failed: " <> show errs)
        Right ops -> do
          let writeOps = [op | op@WriteFileOp {} <- ops]
          writeOps `shouldSatisfy` (\xs -> length xs == 1)
          let op = writeOps !! 0
          op.dest `shouldBe` "flake.nix"
          expected <- splitFlakeBaseline "flake.nix.tpl" vars
          op.content `shouldBe` expected

    it "with nix.postgresql = true, emits bytes identical to the postgres split-flake baseline" $ do
      base <- fixtureDir
      Right modul <- loadModule [takeDirectory base] "conditional-template-flake"
      let vars = Map.insert "nix.postgresql" (VBool True) commonVars
      planResult <- compilePlan base modul vars
      case planResult of
        Left errs -> expectationFailure ("compilePlan failed: " <> show errs)
        Right ops -> do
          let writeOps = [op | op@WriteFileOp {} <- ops]
          writeOps `shouldSatisfy` (\xs -> length xs == 1)
          let op = writeOps !! 0
          op.dest `shouldBe` "flake.nix"
          expected <- splitFlakeBaseline "flake-with-postgres.nix.tpl" vars
          op.content `shouldBe` expected
