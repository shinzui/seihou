module Seihou.Evaluation.SplitFlakeSpec (tests) where

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
tests = testSpec "Seihou.Evaluation.SplitFlake" spec

-- | Variable set common to both variants.
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
  pure (cwd </> "test" </> "fixtures" </> "evaluation" </> "split-flake")

renderFixtureFile :: FilePath -> Map.Map VarName VarValue -> IO Text
renderFixtureFile src vars = do
  base <- fixtureDir
  raw <- TIO.readFile (base </> "files" </> src)
  case renderTemplate raw vars of
    Left errs -> fail ("renderTemplate failed: " <> show errs)
    Right t -> pure t

spec :: Spec
spec = do
  describe "split-flake fixture" $ do
    it "with nix.postgresql = false, emits the non-postgres flake verbatim" $ do
      base <- fixtureDir
      Right modul <- loadModule [takeDirectory base] "split-flake"
      let vars = Map.insert "nix.postgresql" (VBool False) commonVars
      planResult <- compilePlan base modul vars
      case planResult of
        Left errs -> expectationFailure ("compilePlan failed: " <> show errs)
        Right ops -> do
          let writeOps = [op | op@WriteFileOp {} <- ops]
          writeOps `shouldSatisfy` (\xs -> length xs == 1)
          let op = writeOps !! 0
          op.dest `shouldBe` "flake.nix"
          expected <- renderFixtureFile "flake.nix.tpl" vars
          op.content `shouldBe` expected

    it "with nix.postgresql = true, emits the postgres flake verbatim" $ do
      base <- fixtureDir
      Right modul <- loadModule [takeDirectory base] "split-flake"
      let vars = Map.insert "nix.postgresql" (VBool True) commonVars
      planResult <- compilePlan base modul vars
      case planResult of
        Left errs -> expectationFailure ("compilePlan failed: " <> show errs)
        Right ops -> do
          let writeOps = [op | op@WriteFileOp {} <- ops]
          writeOps `shouldSatisfy` (\xs -> length xs == 1)
          let op = writeOps !! 0
          op.dest `shouldBe` "flake.nix"
          expected <- renderFixtureFile "flake-with-postgres.nix.tpl" vars
          op.content `shouldBe` expected
