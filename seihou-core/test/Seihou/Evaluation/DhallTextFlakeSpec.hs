module Seihou.Evaluation.DhallTextFlakeSpec (tests) where

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
tests = testSpec "Seihou.Evaluation.DhallTextFlake" spec

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
  pure (cwd </> "test" </> "fixtures" </> "evaluation" </> "dhall-text-flake")

splitFlakeDir :: IO FilePath
splitFlakeDir = do
  cwd <- getCurrentDirectory
  pure (cwd </> "test" </> "fixtures" </> "evaluation" </> "split-flake")

-- | Render one of the split-flake baseline templates to produce the expected
-- byte string that the Prototype A output must match.
renderSplitFlake :: FilePath -> Map.Map VarName VarValue -> IO Text
renderSplitFlake tplName vars = do
  base <- splitFlakeDir
  raw <- TIO.readFile (base </> "files" </> tplName)
  case renderTemplate raw vars of
    Left errs -> fail ("renderTemplate failed: " <> show errs)
    Right t -> pure t

spec :: Spec
spec = do
  describe "dhall-text-flake fixture (Prototype A)" $ do
    it "with nix.postgresql = false, produces bytes identical to the non-postgres baseline" $ do
      base <- fixtureDir
      Right modul <- loadModule [takeDirectory base] "dhall-text-flake"
      let vars = Map.insert "nix.postgresql" (VBool False) commonVars
      planResult <- compilePlan base modul vars
      case planResult of
        Left errs -> expectationFailure ("compilePlan failed: " <> show errs)
        Right ops -> do
          let writeOps = [op | op@WriteFileOp {} <- ops]
          writeOps `shouldSatisfy` (\xs -> length xs == 1)
          let op = writeOps !! 0
          op.dest `shouldBe` "flake.nix"
          expected <- renderSplitFlake "flake.nix.tpl" vars
          op.content `shouldBe` expected

    it "with nix.postgresql = true, produces bytes identical to the postgres baseline" $ do
      base <- fixtureDir
      Right modul <- loadModule [takeDirectory base] "dhall-text-flake"
      let vars = Map.insert "nix.postgresql" (VBool True) commonVars
      planResult <- compilePlan base modul vars
      case planResult of
        Left errs -> expectationFailure ("compilePlan failed: " <> show errs)
        Right ops -> do
          let writeOps = [op | op@WriteFileOp {} <- ops]
          writeOps `shouldSatisfy` (\xs -> length xs == 1)
          let op = writeOps !! 0
          op.dest `shouldBe` "flake.nix"
          expected <- renderSplitFlake "flake-with-postgres.nix.tpl" vars
          op.content `shouldBe` expected
