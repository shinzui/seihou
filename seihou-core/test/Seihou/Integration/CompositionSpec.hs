module Seihou.Integration.CompositionSpec (tests) where

import Data.Either (isLeft)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Seihou.Composition.Graph (buildGraph, topoSort)
import Seihou.Composition.Instance (ModuleInstance (..), primaryInstance)
import Seihou.Composition.Plan (compileComposedPlan)
import Seihou.Composition.Resolve (loadComposition, resolveComposedVariables)
import Seihou.Core.Types
import System.FilePath ((</>))
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Integration.Composition" spec

fixtureDir :: FilePath
fixtureDir = "test/fixtures"

spec :: Spec
spec = do
  describe "loadComposition" $ do
    it "loads haskell-with-nix with all four modules" $ do
      result <- loadComposition [fixtureDir] "haskell-with-nix" []
      case result of
        Left err -> expectationFailure $ "Expected Right, got: " ++ show err
        Right modules -> do
          let names = map (\(_, m, _) -> m.name) modules
          length names `shouldBe` 4
          -- All four modules should be present
          elem "nix-base" names `shouldBe` True
          elem "haskell-base" names `shouldBe` True
          elem "nix-flake" names `shouldBe` True
          elem "haskell-with-nix" names `shouldBe` True

    it "orders dependencies before dependents" $ do
      result <- loadComposition [fixtureDir] "haskell-with-nix" []
      case result of
        Left err -> expectationFailure $ "Expected Right, got: " ++ show err
        Right modules -> do
          let names = map (\(_, m, _) -> m.name) modules
              indexOf n = case lookup n (zip names [0 :: Int ..]) of
                Just i -> i
                Nothing -> error $ "Module not found: " ++ show n
          -- nix-base before nix-flake
          indexOf "nix-base" `shouldSatisfy` (< indexOf "nix-flake")
          -- haskell-base before haskell-with-nix
          indexOf "haskell-base" `shouldSatisfy` (< indexOf "haskell-with-nix")
          -- nix-flake before haskell-with-nix
          indexOf "nix-flake" `shouldSatisfy` (< indexOf "haskell-with-nix")
          -- haskell-with-nix should be last
          indexOf "haskell-with-nix" `shouldBe` 3

    it "loads a single module with no dependencies" $ do
      result <- loadComposition [fixtureDir] "nix-base" []
      case result of
        Left err -> expectationFailure $ "Expected Right, got: " ++ show err
        Right modules -> do
          length modules `shouldBe` 1
          case modules of
            [(_, m, _)] -> m.name `shouldBe` "nix-base"
            _ -> expectationFailure "Expected exactly one module"

    it "handles additional modules via --module flag" $ do
      result <- loadComposition [fixtureDir] "haskell-base" ["nix-base"]
      case result of
        Left err -> expectationFailure $ "Expected Right, got: " ++ show err
        Right modules -> do
          let names = map (\(_, m, _) -> m.name) modules
          length names `shouldBe` 2
          elem "haskell-base" names `shouldBe` True
          elem "nix-base" names `shouldBe` True

    it "returns error for nonexistent dependency" $ do
      result <- loadComposition [fixtureDir] "haskell-with-nix" ["nonexistent"]
      result `shouldSatisfy` isLeft

  describe "resolveComposedVariables" $ do
    it "flows nix.system from nix-base to nix-flake" $ do
      result <- loadComposition [fixtureDir] "nix-flake" []
      case result of
        Left err -> expectationFailure $ "Load failed: " ++ show err
        Right modules -> do
          case resolveComposedVariables modules Map.empty Map.empty "" "" Map.empty Map.empty Map.empty Map.empty of
            Left errs -> expectationFailure $ "Resolve failed: " ++ show errs
            Right resolved -> do
              let flakeVars = resolved Map.! primaryInstance "nix-flake"
              -- nix-flake should see nix.system from nix-base's export
              (.value) (flakeVars Map.! "nix.system") `shouldBe` VText "x86_64-linux"
              -- nix-flake should also have its own variable
              (.value) (flakeVars Map.! "nix.description") `shouldBe` VText "A Nix project"

    it "flows exports through diamond dependency" $ do
      result <- loadComposition [fixtureDir] "haskell-with-nix" []
      case result of
        Left err -> expectationFailure $ "Load failed: " ++ show err
        Right modules -> do
          let cliOverrides = Map.singleton "project.name" "my-app"
          case resolveComposedVariables modules cliOverrides Map.empty "" "" Map.empty Map.empty Map.empty Map.empty of
            Left errs -> expectationFailure $ "Resolve failed: " ++ show errs
            Right resolved -> do
              -- haskell-base should have project.name from CLI
              let baseVars = resolved Map.! primaryInstance "haskell-base"
              (.value) (baseVars Map.! "project.name") `shouldBe` VText "my-app"
              -- haskell-with-nix should inherit project.name via haskell-base's export
              let topVars = resolved Map.! primaryInstance "haskell-with-nix"
              Map.member "project.name" topVars `shouldBe` True
              (.value) (topVars Map.! "project.name") `shouldBe` VText "my-app"

  describe "compileComposedPlan" $ do
    it "produces operations from all composed modules" $ do
      result <- loadComposition [fixtureDir] "haskell-with-nix" []
      case result of
        Left err -> expectationFailure $ "Load failed: " ++ show err
        Right modules -> do
          let cliOverrides = Map.singleton "project.name" "my-app"
          case resolveComposedVariables modules cliOverrides Map.empty "" "" Map.empty Map.empty Map.empty Map.empty of
            Left errs -> expectationFailure $ "Resolve failed: " ++ show errs
            Right resolved -> do
              let quads =
                    [ (inst, m, dir, Map.map (.value) (resolved Map.! inst))
                    | (inst, m, dir) <- modules
                    ]
              planResult <- compileComposedPlan quads
              case planResult of
                Left errs -> expectationFailure $ "Plan failed: " ++ show errs
                Right (ops, warnings, _) -> do
                  -- Should have operations for shell.nix, flake.nix, README.md,
                  -- src/Lib.hs, LICENSE, *.cabal, cabal.project, Makefile (+ dirs)
                  let writeOps = [d | WriteFileOp d _ _ <- ops]
                  elem "shell.nix" writeOps `shouldBe` True
                  elem "flake.nix" writeOps `shouldBe` True
                  elem "Makefile" writeOps `shouldBe` True
                  elem "README.md" writeOps `shouldBe` True

  describe "text patching integration" $ do
    it "haskell-shared-readme appends section to haskell-base README" $ do
      result <- loadComposition [fixtureDir] "haskell-shared-readme" []
      case result of
        Left err -> expectationFailure $ "Load failed: " ++ show err
        Right modules -> do
          let cliOverrides = Map.singleton "project.name" "my-app"
          case resolveComposedVariables modules cliOverrides Map.empty "" "" Map.empty Map.empty Map.empty Map.empty of
            Left errs -> expectationFailure $ "Resolve failed: " ++ show errs
            Right resolved -> do
              let quads =
                    [ (inst, m, dir, Map.map (.value) (resolved Map.! inst))
                    | (inst, m, dir) <- modules
                    ]
              planResult <- compileComposedPlan quads
              case planResult of
                Left errs -> expectationFailure $ "Plan failed: " ++ show errs
                Right (ops, warnings, _) -> do
                  -- Find the merged README.md
                  let readmeOps = [content | WriteFileOp dest content _ <- ops, dest == "README.md"]
                  length readmeOps `shouldBe` 1
                  let readmeContent = head readmeOps
                  -- Should contain the base content from haskell-base
                  T.isInfixOf "# my-app" readmeContent `shouldBe` True
                  -- Should contain the patched section from haskell-shared-readme
                  T.isInfixOf "Additional Section" readmeContent `shouldBe` True
                  T.isInfixOf "seihou:haskell-shared-readme" readmeContent `shouldBe` True
                  -- Should have a ContentMerged warning
                  any isContentMerged warnings `shouldBe` True

  describe "structured merge integration" $ do
    it "two modules contributing to same JSON get deep-merged" $ do
      result <- loadComposition [fixtureDir] "structured-merge-b" []
      case result of
        Left err -> expectationFailure $ "Load failed: " ++ show err
        Right modules -> do
          case resolveComposedVariables modules Map.empty Map.empty "" "" Map.empty Map.empty Map.empty Map.empty of
            Left errs -> expectationFailure $ "Resolve failed: " ++ show errs
            Right resolved -> do
              let quads =
                    [ (inst, m, dir, Map.map (.value) (resolved Map.! inst))
                    | (inst, m, dir) <- modules
                    ]
              planResult <- compileComposedPlan quads
              case planResult of
                Left errs -> expectationFailure $ "Plan failed: " ++ show errs
                Right (ops, warnings, _) -> do
                  -- Find the merged config.json
                  let configOps = [content | WriteFileOp dest content _ <- ops, dest == "config.json"]
                  length configOps `shouldBe` 1
                  let configContent = head configOps
                  -- Should contain keys from module A
                  T.isInfixOf "name" configContent `shouldBe` True
                  T.isInfixOf "my-project" configContent `shouldBe` True
                  -- Should contain keys from module B
                  T.isInfixOf "debug" configContent `shouldBe` True
                  T.isInfixOf "logLevel" configContent `shouldBe` True
                  -- Should have a ContentMerged warning
                  any isContentMerged warnings `shouldBe` True

  describe "multi-instantiation diamond" $ do
    -- These three fixtures (multi-instance-helper/leaf/diamond) model the
    -- agent-seihou master-plan pattern: a parent depends on a leaf that
    -- binds the helper one way, and also directly on the helper bound
    -- the other way. Before ExecPlan 10, only one invocation survived.
    it "loadComposition produces two helper instances with different bindings" $ do
      result <- loadComposition [fixtureDir] "multi-instance-diamond" []
      case result of
        Left err -> expectationFailure $ "Load failed: " ++ show err
        Right modules -> do
          -- Expect: helper (skill.name=diamond), helper (skill.name=leaf),
          --         leaf, diamond — four entries total.
          length modules `shouldBe` 4
          let helperInstances =
                [ inst
                | (inst, m, _) <- modules,
                  m.name == "multi-instance-helper"
                ]
          length helperInstances `shouldBe` 2
          let bindings =
                Map.fromList
                  [ ("diamond" :: Text, True),
                    ("leaf", True)
                  ]
              haveSkill vn =
                any
                  ( \inst ->
                      Map.lookup "skill.name" inst.instanceParentVars.unParentVars == Just vn
                  )
                  helperInstances
          all haveSkill (Map.keys bindings) `shouldBe` True

    it "compileComposedPlan produces two helper output files with distinct names" $ do
      result <- loadComposition [fixtureDir] "multi-instance-diamond" []
      case result of
        Left err -> expectationFailure $ "Load failed: " ++ show err
        Right modules -> do
          case resolveComposedVariables modules Map.empty Map.empty "" "" Map.empty Map.empty Map.empty Map.empty of
            Left errs -> expectationFailure $ "Resolve failed: " ++ show errs
            Right resolved -> do
              let quads =
                    [ (inst, m, dir, Map.map (.value) (resolved Map.! inst))
                    | (inst, m, dir) <- modules
                    ]
              planResult <- compileComposedPlan quads
              case planResult of
                Left errs -> expectationFailure $ "Plan failed: " ++ show errs
                Right (ops, _, _) -> do
                  let writeDests = [d | WriteFileOp d _ _ <- ops]
                  elem "out/leaf.txt" writeDests `shouldBe` True
                  elem "out/diamond.txt" writeDests `shouldBe` True

  describe "cycle detection" $ do
    it "detects a circular dependency" $ do
      let mkMod name deps =
            Module
              { name = name,
                version = Nothing,
                description = Nothing,
                vars = [],
                exports = [],
                prompts = [],
                steps = [],
                commands = [],
                dependencies = map simpleDep deps,
                removal = Nothing
              }
          a = mkMod "a" ["b"]
          b = mkMod "b" ["c"]
          c = mkMod "c" ["a"]
          graph = buildGraph [(primaryInstance m.name, m) | m <- [a, b, c]]
      topoSort graph `shouldSatisfy` isLeft

isContentMerged :: CompositionWarning -> Bool
isContentMerged (ContentMerged {}) = True
isContentMerged _ = False
