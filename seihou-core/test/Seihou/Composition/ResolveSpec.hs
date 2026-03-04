module Seihou.Composition.ResolveSpec (tests) where

import Data.Map.Strict qualified as Map
import Seihou.Composition.Resolve
import Seihou.Core.Types
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Composition.Resolve" spec

-- | Helper to create a minimal module.
mkModule :: ModuleName -> [ModuleName] -> [VarDecl] -> [VarExport] -> Module
mkModule name deps vars exports =
  Module
    { moduleName = name,
      moduleDescription = Nothing,
      moduleVars = vars,
      moduleExports = exports,
      modulePrompts = [],
      moduleSteps = [],
      moduleCommands = [],
      moduleDependencies = deps
    }

-- | Helper to create a text variable declaration.
mkTextVar :: VarName -> Maybe VarValue -> Bool -> VarDecl
mkTextVar name defVal required =
  VarDecl
    { varName = name,
      varType = VTText,
      varDefault = defVal,
      varDescription = Nothing,
      varRequired = required,
      varValidation = Nothing
    }

-- | Helper to create an export without alias.
mkExport :: VarName -> VarExport
mkExport name = VarExport {exportVar = name, exportAs = Nothing}

-- | Helper to create an export with alias.
mkExportAs :: VarName -> VarName -> VarExport
mkExportAs name alias = VarExport {exportVar = name, exportAs = Just alias}

spec :: Spec
spec = do
  describe "exportedVars" $ do
    it "exports a variable under its original name" $ do
      let m = mkModule "base" [] [mkTextVar "project.name" (Just (VText "test")) False] [mkExport "project.name"]
          resolved = Map.singleton "project.name" (ResolvedVar (VText "my-app") FromDefault (mkTextVar "project.name" (Just (VText "test")) False))
          result = exportedVars m resolved
      Map.lookup "project.name" result `shouldBe` Just (VText "my-app")

    it "exports a variable under its alias" $ do
      let m = mkModule "base" [] [mkTextVar "project.name" (Just (VText "test")) False] [mkExportAs "project.name" "app.name"]
          resolved = Map.singleton "project.name" (ResolvedVar (VText "my-app") FromDefault (mkTextVar "project.name" (Just (VText "test")) False))
          result = exportedVars m resolved
      Map.lookup "app.name" result `shouldBe` Just (VText "my-app")
      Map.lookup "project.name" result `shouldBe` Nothing

    it "skips exports for unresolved variables" $ do
      let m = mkModule "base" [] [] [mkExport "missing.var"]
          resolved = Map.empty
          result = exportedVars m resolved
      Map.null result `shouldBe` True

  describe "resolveComposedVariables" $ do
    it "resolves a single module with no dependencies" $ do
      let m = mkModule "base" [] [mkTextVar "project.name" (Just (VText "default")) False] []
          modules = [(m, "/fake/base")]
      case resolveComposedVariables modules Map.empty Map.empty "" Map.empty Map.empty Map.empty of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          Map.member "base" result `shouldBe` True
          let baseVars = result Map.! "base"
          resolvedValue (baseVars Map.! "project.name") `shouldBe` VText "default"

    it "flows exported variable from dependency to dependent" $ do
      let base = mkModule "base" [] [mkTextVar "project.name" (Just (VText "my-app")) False] [mkExport "project.name"]
          app = mkModule "app" ["base"] [mkTextVar "project.name" Nothing True] []
          modules = [(base, "/fake/base"), (app, "/fake/app")]
      case resolveComposedVariables modules Map.empty Map.empty "" Map.empty Map.empty Map.empty of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let appVars = result Map.! "app"
          resolvedValue (appVars Map.! "project.name") `shouldBe` VText "my-app"

    it "export overrides module's own default" $ do
      let base = mkModule "base" [] [mkTextVar "project.name" (Just (VText "from-base")) False] [mkExport "project.name"]
          app = mkModule "app" ["base"] [mkTextVar "project.name" (Just (VText "from-app")) False] []
          modules = [(base, "/fake/base"), (app, "/fake/app")]
      case resolveComposedVariables modules Map.empty Map.empty "" Map.empty Map.empty Map.empty of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let appVars = result Map.! "app"
          resolvedValue (appVars Map.! "project.name") `shouldBe` VText "from-base"

    it "CLI override beats exported value" $ do
      let base = mkModule "base" [] [mkTextVar "project.name" (Just (VText "from-base")) False] [mkExport "project.name"]
          app = mkModule "app" ["base"] [mkTextVar "project.name" Nothing True] []
          modules = [(base, "/fake/base"), (app, "/fake/app")]
          cliOverrides = Map.singleton "project.name" "from-cli"
      case resolveComposedVariables modules cliOverrides Map.empty "" Map.empty Map.empty Map.empty of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let appVars = result Map.! "app"
          resolvedValue (appVars Map.! "project.name") `shouldBe` VText "from-cli"

    it "inherits non-declared exports from dependency" $ do
      let base = mkModule "base" [] [mkTextVar "project.name" (Just (VText "my-app")) False] [mkExport "project.name"]
          -- app does NOT declare project.name but depends on base
          app = mkModule "app" ["base"] [mkTextVar "app.version" (Just (VText "1.0")) False] []
          modules = [(base, "/fake/base"), (app, "/fake/app")]
      case resolveComposedVariables modules Map.empty Map.empty "" Map.empty Map.empty Map.empty of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let appVars = result Map.! "app"
          -- app inherits project.name even though it doesn't declare it
          resolvedValue (appVars Map.! "project.name") `shouldBe` VText "my-app"
          -- app also has its own variable
          resolvedValue (appVars Map.! "app.version") `shouldBe` VText "1.0"

    it "handles aliased exports" $ do
      let base = mkModule "base" [] [mkTextVar "project.name" (Just (VText "my-app")) False] [mkExportAs "project.name" "app.name"]
          app = mkModule "app" ["base"] [mkTextVar "app.name" Nothing True] []
          modules = [(base, "/fake/base"), (app, "/fake/app")]
      case resolveComposedVariables modules Map.empty Map.empty "" Map.empty Map.empty Map.empty of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let appVars = result Map.! "app"
          resolvedValue (appVars Map.! "app.name") `shouldBe` VText "my-app"

    it "handles diamond dependency with shared export" $ do
      let d = mkModule "d" [] [mkTextVar "sys.arch" (Just (VText "x86_64")) False] [mkExport "sys.arch"]
          b = mkModule "b" ["d"] [mkTextVar "sys.arch" Nothing True] [mkExport "sys.arch"]
          c = mkModule "c" ["d"] [mkTextVar "sys.arch" Nothing True] []
          a = mkModule "a" ["b", "c"] [mkTextVar "sys.arch" Nothing True] []
          modules = [(d, "/d"), (b, "/b"), (c, "/c"), (a, "/a")]
      case resolveComposedVariables modules Map.empty Map.empty "" Map.empty Map.empty Map.empty of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          -- All modules should see sys.arch from d
          resolvedValue ((result Map.! "d") Map.! "sys.arch") `shouldBe` VText "x86_64"
          resolvedValue ((result Map.! "b") Map.! "sys.arch") `shouldBe` VText "x86_64"
          resolvedValue ((result Map.! "c") Map.! "sys.arch") `shouldBe` VText "x86_64"
          resolvedValue ((result Map.! "a") Map.! "sys.arch") `shouldBe` VText "x86_64"

  describe "resolveComposedVariables (with config layers)" $ do
    it "resolves from global config when no other source provides value" $ do
      let m = mkModule "base" [] [mkTextVar "license" Nothing True] []
          modules = [(m, "/fake/base")]
          globalCfg = Map.fromList [("license", "MIT")]
      case resolveComposedVariables modules Map.empty Map.empty "" Map.empty Map.empty globalCfg of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let baseVars = result Map.! "base"
          resolvedValue (baseVars Map.! "license") `shouldBe` VText "MIT"
          resolvedSource (baseVars Map.! "license") `shouldBe` FromGlobalConfig

    it "local config overrides global config in composed resolution" $ do
      let m = mkModule "base" [] [mkTextVar "license" Nothing True] []
          modules = [(m, "/fake/base")]
          localCfg = Map.fromList [("license", "BSD3")]
          globalCfg = Map.fromList [("license", "MIT")]
      case resolveComposedVariables modules Map.empty Map.empty "" localCfg Map.empty globalCfg of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let baseVars = result Map.! "base"
          resolvedValue (baseVars Map.! "license") `shouldBe` VText "BSD3"
          resolvedSource (baseVars Map.! "license") `shouldBe` FromLocalConfig

    it "CLI override beats config layers in composed resolution" $ do
      let m = mkModule "base" [] [mkTextVar "license" Nothing True] []
          modules = [(m, "/fake/base")]
          cliOverrides = Map.singleton "license" "cli-license"
          localCfg = Map.fromList [("license", "local-license")]
          globalCfg = Map.fromList [("license", "global-license")]
      case resolveComposedVariables modules cliOverrides Map.empty "" localCfg Map.empty globalCfg of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let baseVars = result Map.! "base"
          resolvedValue (baseVars Map.! "license") `shouldBe` VText "cli-license"
          resolvedSource (baseVars Map.! "license") `shouldBe` FromCLI

    it "config layers flow through multi-module composition" $ do
      let base = mkModule "base" [] [mkTextVar "license" Nothing True] [mkExport "license"]
          app = mkModule "app" ["base"] [mkTextVar "license" Nothing True] []
          modules = [(base, "/fake/base"), (app, "/fake/app")]
          globalCfg = Map.fromList [("license", "MIT")]
      case resolveComposedVariables modules Map.empty Map.empty "" Map.empty Map.empty globalCfg of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          -- base gets license from global config
          let baseVars = result Map.! "base"
          resolvedValue (baseVars Map.! "license") `shouldBe` VText "MIT"
          resolvedSource (baseVars Map.! "license") `shouldBe` FromGlobalConfig
          -- app also gets license from global config (it declares the var)
          let appVars = result Map.! "app"
          resolvedValue (appVars Map.! "license") `shouldBe` VText "MIT"
