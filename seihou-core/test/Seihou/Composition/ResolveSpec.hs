module Seihou.Composition.ResolveSpec (tests) where

import Data.Map.Strict qualified as Map
import Seihou.Composition.Resolve
import Seihou.Core.Types
import Seihou.Core.Variable (diagnoseResolution)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Composition.Resolve" spec

-- | Helper to create a minimal module.
mkModule :: ModuleName -> [ModuleName] -> [VarDecl] -> [VarExport] -> Module
mkModule name deps vars exports =
  Module
    { name = name,
      version = Nothing,
      description = Nothing,
      vars = vars,
      exports = exports,
      prompts = [],
      steps = [],
      commands = [],
      dependencies = map simpleDep deps
    }

-- | Helper to create a module with parameterized dependencies.
mkModuleWithDeps :: ModuleName -> [Dependency] -> [VarDecl] -> [VarExport] -> Module
mkModuleWithDeps name deps vars exports =
  Module
    { name = name,
      version = Nothing,
      description = Nothing,
      vars = vars,
      exports = exports,
      prompts = [],
      steps = [],
      commands = [],
      dependencies = deps
    }

-- | Helper to create a text variable declaration.
mkTextVar :: VarName -> Maybe VarValue -> Bool -> VarDecl
mkTextVar name defVal required =
  VarDecl
    { name = name,
      type_ = VTText,
      default_ = defVal,
      description = Nothing,
      required = required,
      validation = Nothing
    }

-- | Helper to create an export without alias.
mkExport :: VarName -> VarExport
mkExport name = VarExport {var = name, alias = Nothing}

-- | Helper to create an export with alias.
mkExportAs :: VarName -> VarName -> VarExport
mkExportAs name alias' = VarExport {var = name, alias = Just alias'}

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
      case resolveComposedVariables modules Map.empty Map.empty "" "" Map.empty Map.empty Map.empty Map.empty of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          Map.member "base" result `shouldBe` True
          let baseVars = result Map.! "base"
          (.value) (baseVars Map.! "project.name") `shouldBe` VText "default"

    it "flows exported variable from dependency to dependent" $ do
      let base = mkModule "base" [] [mkTextVar "project.name" (Just (VText "my-app")) False] [mkExport "project.name"]
          app = mkModule "app" ["base"] [mkTextVar "project.name" Nothing True] []
          modules = [(base, "/fake/base"), (app, "/fake/app")]
      case resolveComposedVariables modules Map.empty Map.empty "" "" Map.empty Map.empty Map.empty Map.empty of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let appVars = result Map.! "app"
          (.value) (appVars Map.! "project.name") `shouldBe` VText "my-app"

    it "export overrides module's own default" $ do
      let base = mkModule "base" [] [mkTextVar "project.name" (Just (VText "from-base")) False] [mkExport "project.name"]
          app = mkModule "app" ["base"] [mkTextVar "project.name" (Just (VText "from-app")) False] []
          modules = [(base, "/fake/base"), (app, "/fake/app")]
      case resolveComposedVariables modules Map.empty Map.empty "" "" Map.empty Map.empty Map.empty Map.empty of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let appVars = result Map.! "app"
          (.value) (appVars Map.! "project.name") `shouldBe` VText "from-base"

    it "CLI override beats exported value" $ do
      let base = mkModule "base" [] [mkTextVar "project.name" (Just (VText "from-base")) False] [mkExport "project.name"]
          app = mkModule "app" ["base"] [mkTextVar "project.name" Nothing True] []
          modules = [(base, "/fake/base"), (app, "/fake/app")]
          cliOverrides = Map.singleton "project.name" "from-cli"
      case resolveComposedVariables modules cliOverrides Map.empty "" "" Map.empty Map.empty Map.empty Map.empty of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let appVars = result Map.! "app"
          (.value) (appVars Map.! "project.name") `shouldBe` VText "from-cli"

    it "inherits non-declared exports from dependency" $ do
      let base = mkModule "base" [] [mkTextVar "project.name" (Just (VText "my-app")) False] [mkExport "project.name"]
          -- app does NOT declare project.name but depends on base
          app = mkModule "app" ["base"] [mkTextVar "app.version" (Just (VText "1.0")) False] []
          modules = [(base, "/fake/base"), (app, "/fake/app")]
      case resolveComposedVariables modules Map.empty Map.empty "" "" Map.empty Map.empty Map.empty Map.empty of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let appVars = result Map.! "app"
          -- app inherits project.name even though it doesn't declare it
          (.value) (appVars Map.! "project.name") `shouldBe` VText "my-app"
          -- app also has its own variable
          (.value) (appVars Map.! "app.version") `shouldBe` VText "1.0"

    it "handles aliased exports" $ do
      let base = mkModule "base" [] [mkTextVar "project.name" (Just (VText "my-app")) False] [mkExportAs "project.name" "app.name"]
          app = mkModule "app" ["base"] [mkTextVar "app.name" Nothing True] []
          modules = [(base, "/fake/base"), (app, "/fake/app")]
      case resolveComposedVariables modules Map.empty Map.empty "" "" Map.empty Map.empty Map.empty Map.empty of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let appVars = result Map.! "app"
          (.value) (appVars Map.! "app.name") `shouldBe` VText "my-app"

    it "handles diamond dependency with shared export" $ do
      let d = mkModule "d" [] [mkTextVar "sys.arch" (Just (VText "x86_64")) False] [mkExport "sys.arch"]
          b = mkModule "b" ["d"] [mkTextVar "sys.arch" Nothing True] [mkExport "sys.arch"]
          c = mkModule "c" ["d"] [mkTextVar "sys.arch" Nothing True] []
          a = mkModule "a" ["b", "c"] [mkTextVar "sys.arch" Nothing True] []
          modules = [(d, "/d"), (b, "/b"), (c, "/c"), (a, "/a")]
      case resolveComposedVariables modules Map.empty Map.empty "" "" Map.empty Map.empty Map.empty Map.empty of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          -- All modules should see sys.arch from d
          (.value) ((result Map.! "d") Map.! "sys.arch") `shouldBe` VText "x86_64"
          (.value) ((result Map.! "b") Map.! "sys.arch") `shouldBe` VText "x86_64"
          (.value) ((result Map.! "c") Map.! "sys.arch") `shouldBe` VText "x86_64"
          (.value) ((result Map.! "a") Map.! "sys.arch") `shouldBe` VText "x86_64"

  describe "resolveComposedVariables (with config layers)" $ do
    it "resolves from global config when no other source provides value" $ do
      let m = mkModule "base" [] [mkTextVar "license" Nothing True] []
          modules = [(m, "/fake/base")]
          globalCfg = Map.fromList [("license", "MIT")]
      case resolveComposedVariables modules Map.empty Map.empty "" "" Map.empty Map.empty Map.empty globalCfg of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let baseVars = result Map.! "base"
          (.value) (baseVars Map.! "license") `shouldBe` VText "MIT"
          (.source) (baseVars Map.! "license") `shouldBe` FromGlobalConfig

    it "local config overrides global config in composed resolution" $ do
      let m = mkModule "base" [] [mkTextVar "license" Nothing True] []
          modules = [(m, "/fake/base")]
          localCfg = Map.fromList [("license", "BSD3")]
          globalCfg = Map.fromList [("license", "MIT")]
      case resolveComposedVariables modules Map.empty Map.empty "" "" localCfg Map.empty Map.empty globalCfg of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let baseVars = result Map.! "base"
          (.value) (baseVars Map.! "license") `shouldBe` VText "BSD3"
          (.source) (baseVars Map.! "license") `shouldBe` FromLocalConfig

    it "CLI override beats config layers in composed resolution" $ do
      let m = mkModule "base" [] [mkTextVar "license" Nothing True] []
          modules = [(m, "/fake/base")]
          cliOverrides = Map.singleton "license" "cli-license"
          localCfg = Map.fromList [("license", "local-license")]
          globalCfg = Map.fromList [("license", "global-license")]
      case resolveComposedVariables modules cliOverrides Map.empty "" "" localCfg Map.empty Map.empty globalCfg of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let baseVars = result Map.! "base"
          (.value) (baseVars Map.! "license") `shouldBe` VText "cli-license"
          (.source) (baseVars Map.! "license") `shouldBe` FromCLI

    it "config layers flow through multi-module composition" $ do
      let base = mkModule "base" [] [mkTextVar "license" Nothing True] [mkExport "license"]
          app = mkModule "app" ["base"] [mkTextVar "license" Nothing True] []
          modules = [(base, "/fake/base"), (app, "/fake/app")]
          globalCfg = Map.fromList [("license", "MIT")]
      case resolveComposedVariables modules Map.empty Map.empty "" "" Map.empty Map.empty Map.empty globalCfg of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          -- base gets license from global config
          let baseVars = result Map.! "base"
          (.value) (baseVars Map.! "license") `shouldBe` VText "MIT"
          (.source) (baseVars Map.! "license") `shouldBe` FromGlobalConfig
          -- app also gets license from global config (it declares the var)
          let appVars = result Map.! "app"
          (.value) (appVars Map.! "license") `shouldBe` VText "MIT"

  describe "end-to-end config hierarchy auto-resolution" $ do
    it "resolves all variables from different config layers with correct precedence" $ do
      -- Scenario: A module with 4 variables, each resolved from a different layer
      let decls =
            [ mkTextVar "project.name" Nothing True,
              mkTextVar "license" Nothing False,
              mkTextVar "haskell.ghc" Nothing False,
              mkTextVar "author.name" Nothing False
            ]
          m = mkModule "haskell-app" [] decls [mkExport "project.name"]
          modules = [(m, "/fake/haskell-app")]
          cliOverrides = Map.singleton "project.name" "my-app"
          envVars = Map.singleton "SEIHOU_VAR_LICENSE" "Apache"
          localCfg = Map.fromList [("haskell.ghc", "9.12.2")]
          globalCfg = Map.fromList [("author.name", "Jane Doe"), ("license", "MIT")]
      case resolveComposedVariables modules cliOverrides envVars "haskell" "" localCfg Map.empty Map.empty globalCfg of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let vars = result Map.! "haskell-app"
          -- CLI wins for project.name
          (.value) (vars Map.! "project.name") `shouldBe` VText "my-app"
          (.source) (vars Map.! "project.name") `shouldBe` FromCLI
          -- Env wins over global config for license
          (.value) (vars Map.! "license") `shouldBe` VText "Apache"
          (.source) (vars Map.! "license") `shouldBe` FromEnv "SEIHOU_VAR_LICENSE"
          -- Local config provides haskell.ghc
          (.value) (vars Map.! "haskell.ghc") `shouldBe` VText "9.12.2"
          (.source) (vars Map.! "haskell.ghc") `shouldBe` FromLocalConfig
          -- Global config provides author.name
          (.value) (vars Map.! "author.name") `shouldBe` VText "Jane Doe"
          (.source) (vars Map.! "author.name") `shouldBe` FromGlobalConfig

    it "optional variables without values are omitted, not errors" $ do
      let decls =
            [ mkTextVar "project.name" Nothing True,
              mkTextVar "optional.missing" Nothing False
            ]
          m = mkModule "test" [] decls []
          modules = [(m, "/fake/test")]
          cliOverrides = Map.singleton "project.name" "app"
      case resolveComposedVariables modules cliOverrides Map.empty "" "" Map.empty Map.empty Map.empty Map.empty of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let vars = result Map.! "test"
          (.value) (vars Map.! "project.name") `shouldBe` VText "app"
          Map.member "optional.missing" vars `shouldBe` False

    it "diagnostics detect unused config keys and unresolved optional vars" $ do
      let decls =
            [ mkTextVar "project.name" Nothing True,
              mkTextVar "optional.unset" Nothing False
            ]
          m = mkModule "test" [] decls []
          modules = [(m, "/fake/test")]
          cliOverrides = Map.singleton "project.name" "app"
          globalCfg = Map.fromList [("typo.key", "oops")]
      case resolveComposedVariables modules cliOverrides Map.empty "" "" Map.empty Map.empty Map.empty globalCfg of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let allResolved = Map.unions (Map.elems result)
              allDecls = concatMap ((.vars) . fst) modules
              (unusedKeys, unresolvedOpt) = diagnoseResolution allResolved allDecls Map.empty Map.empty Map.empty globalCfg
          unusedKeys `shouldBe` [VarName "typo.key"]
          unresolvedOpt `shouldBe` [VarName "optional.unset"]

    it "context config overrides global config in composed resolution" $ do
      let m = mkModule "base" [] [mkTextVar "user.email" Nothing True] []
          modules = [(m, "/fake/base")]
          ctxCfg = Map.fromList [("user.email", "work@example.com")]
          globalCfg = Map.fromList [("user.email", "default@example.com")]
      case resolveComposedVariables modules Map.empty Map.empty "" "work" Map.empty Map.empty ctxCfg globalCfg of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let baseVars = result Map.! "base"
          (.value) (baseVars Map.! "user.email") `shouldBe` VText "work@example.com"
          (.source) (baseVars Map.! "user.email") `shouldBe` FromContextConfig "work"

    it "context flows through multi-module composition" $ do
      let base = mkModule "base" [] [mkTextVar "user.email" Nothing True] [mkExport "user.email"]
          app = mkModule "app" ["base"] [mkTextVar "user.email" Nothing True] []
          modules = [(base, "/fake/base"), (app, "/fake/app")]
          ctxCfg = Map.fromList [("user.email", "work@example.com")]
      case resolveComposedVariables modules Map.empty Map.empty "" "work" Map.empty Map.empty ctxCfg Map.empty of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let baseVars = result Map.! "base"
          (.value) (baseVars Map.! "user.email") `shouldBe` VText "work@example.com"
          let appVars = result Map.! "app"
          (.value) (appVars Map.! "user.email") `shouldBe` VText "work@example.com"

    it "multi-module composition: config values flow through exports" $ do
      let baseDecls =
            [ mkTextVar "project.name" Nothing True,
              mkTextVar "license" Nothing False
            ]
          base = mkModule "base" [] baseDecls [mkExport "project.name", mkExport "license"]
          appDecls =
            [ mkTextVar "project.name" Nothing True,
              mkTextVar "license" Nothing False
            ]
          app = mkModule "app" ["base"] appDecls []
          modules = [(base, "/fake/base"), (app, "/fake/app")]
          globalCfg = Map.fromList [("project.name", "global-app"), ("license", "MIT")]
          localCfg = Map.fromList [("project.name", "local-app")]
      case resolveComposedVariables modules Map.empty Map.empty "" "" localCfg Map.empty Map.empty globalCfg of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          -- base: local overrides global for project.name
          let baseVars = result Map.! "base"
          (.value) (baseVars Map.! "project.name") `shouldBe` VText "local-app"
          (.source) (baseVars Map.! "project.name") `shouldBe` FromLocalConfig
          (.value) (baseVars Map.! "license") `shouldBe` VText "MIT"
          (.source) (baseVars Map.! "license") `shouldBe` FromGlobalConfig
          -- app: same values, same precedence (declares its own vars, config wins)
          let appVars = result Map.! "app"
          (.value) (appVars Map.! "project.name") `shouldBe` VText "local-app"
          (.value) (appVars Map.! "license") `shouldBe` VText "MIT"

  describe "resolveComposedVariables (parameterized dependencies)" $ do
    it "parent-supplied var resolves in dependency" $ do
      let child = mkModule "child" [] [mkTextVar "skill.name" Nothing True] []
          parent' = mkModuleWithDeps "parent" [Dependency "child" (Map.singleton "skill.name" "exec-plan")] [] []
          modules = [(child, "/fake/child"), (parent', "/fake/parent")]
      case resolveComposedVariables modules Map.empty Map.empty "" "" Map.empty Map.empty Map.empty Map.empty of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let childVars = result Map.! "child"
          (.value) (childVars Map.! "skill.name") `shouldBe` VText "exec-plan"
          (.source) (childVars Map.! "skill.name") `shouldBe` FromParent "parent"

    it "parent-supplied var overrides dependency's default" $ do
      let child = mkModule "child" [] [mkTextVar "skill.name" (Just (VText "old")) False] []
          parent' = mkModuleWithDeps "parent" [Dependency "child" (Map.singleton "skill.name" "new")] [] []
          modules = [(child, "/fake/child"), (parent', "/fake/parent")]
      case resolveComposedVariables modules Map.empty Map.empty "" "" Map.empty Map.empty Map.empty Map.empty of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let childVars = result Map.! "child"
          (.value) (childVars Map.! "skill.name") `shouldBe` VText "new"
          (.source) (childVars Map.! "skill.name") `shouldBe` FromParent "parent"

    it "CLI override beats parent-supplied var" $ do
      let child = mkModule "child" [] [mkTextVar "skill.name" Nothing True] []
          parent' = mkModuleWithDeps "parent" [Dependency "child" (Map.singleton "skill.name" "from-parent")] [] []
          modules = [(child, "/fake/child"), (parent', "/fake/parent")]
          cliOverrides = Map.singleton "skill.name" "from-cli"
      case resolveComposedVariables modules cliOverrides Map.empty "" "" Map.empty Map.empty Map.empty Map.empty of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let childVars = result Map.! "child"
          (.value) (childVars Map.! "skill.name") `shouldBe` VText "from-cli"
          (.source) (childVars Map.! "skill.name") `shouldBe` FromCLI

    it "config beats parent-supplied var" $ do
      let child = mkModule "child" [] [mkTextVar "skill.name" (Just (VText "default")) False] []
          parent' = mkModuleWithDeps "parent" [Dependency "child" (Map.singleton "skill.name" "parent-val")] [] []
          modules = [(child, "/fake/child"), (parent', "/fake/parent")]
          globalCfg = Map.fromList [("skill.name", "global-val")]
      case resolveComposedVariables modules Map.empty Map.empty "" "" Map.empty Map.empty Map.empty globalCfg of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right result -> do
          let childVars = result Map.! "child"
          (.value) (childVars Map.! "skill.name") `shouldBe` VText "global-val"
          (.source) (childVars Map.! "skill.name") `shouldBe` FromGlobalConfig
