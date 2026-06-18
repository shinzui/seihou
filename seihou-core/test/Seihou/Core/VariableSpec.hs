module Seihou.Core.VariableSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Seihou.Core.Expr (evalExpr, parseExpr)
import Seihou.Core.Types
import Seihou.Core.Variable
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.Variable" spec

-- | Helper to build a simple text var declaration.
textVar :: VarName -> Bool -> Maybe VarValue -> Maybe Validation -> VarDecl
textVar name req def val =
  VarDecl
    { name = name,
      type_ = VTText,
      default_ = def,
      description = Nothing,
      required = req,
      validation = val
    }

-- | Helper to build a bool var declaration.
boolVar :: VarName -> Bool -> Maybe VarValue -> VarDecl
boolVar name req def =
  VarDecl
    { name = name,
      type_ = VTBool,
      default_ = def,
      description = Nothing,
      required = req,
      validation = Nothing
    }

-- | Helper to build an int var declaration.
intVar :: VarName -> Bool -> Maybe VarValue -> Maybe Validation -> VarDecl
intVar name req def val =
  VarDecl
    { name = name,
      type_ = VTInt,
      default_ = def,
      description = Nothing,
      required = req,
      validation = val
    }

-- | Helper to build a choice var declaration.
choiceVar :: VarName -> Bool -> [T.Text] -> Maybe VarValue -> VarDecl
choiceVar name req options def =
  VarDecl
    { name = name,
      type_ = VTChoice options,
      default_ = def,
      description = Nothing,
      required = req,
      validation = Nothing
    }

spec :: Spec
spec = do
  describe "envVarName" $ do
    it "converts project.name to SEIHOU_VAR_PROJECT_NAME" $ do
      envVarName "project.name" `shouldBe` "SEIHOU_VAR_PROJECT_NAME"

    it "converts license to SEIHOU_VAR_LICENSE" $ do
      envVarName "license" `shouldBe` "SEIHOU_VAR_LICENSE"

    it "converts project.version to SEIHOU_VAR_PROJECT_VERSION" $ do
      envVarName "project.version" `shouldBe` "SEIHOU_VAR_PROJECT_VERSION"

  describe "coerceValue" $ do
    it "coerces text as-is" $ do
      coerceValue "x" VTText "hello" `shouldBe` Right (VText "hello")

    it "coerces true string to VBool True" $ do
      coerceValue "x" VTBool "true" `shouldBe` Right (VBool True)

    it "coerces yes string to VBool True" $ do
      coerceValue "x" VTBool "yes" `shouldBe` Right (VBool True)

    it "coerces 1 string to VBool True" $ do
      coerceValue "x" VTBool "1" `shouldBe` Right (VBool True)

    it "coerces false string to VBool False" $ do
      coerceValue "x" VTBool "false" `shouldBe` Right (VBool False)

    it "coerces no string to VBool False" $ do
      coerceValue "x" VTBool "no" `shouldBe` Right (VBool False)

    it "rejects invalid bool string" $ do
      coerceValue "x" VTBool "maybe" `shouldBe` Left (CoercionFailed "x" VTBool "maybe")

    it "coerces integer string" $ do
      coerceValue "x" VTInt "42" `shouldBe` Right (VInt 42)

    it "coerces negative integer" $ do
      coerceValue "x" VTInt "-5" `shouldBe` Right (VInt (-5))

    it "rejects non-integer string" $ do
      coerceValue "x" VTInt "abc" `shouldBe` Left (CoercionFailed "x" VTInt "abc")

    it "coerces comma-separated list" $ do
      coerceValue "x" (VTList VTText) "a,b,c"
        `shouldBe` Right (VList [VText "a", VText "b", VText "c"])

    it "strips whitespace in list elements" $ do
      coerceValue "x" (VTList VTText) "a , b , c"
        `shouldBe` Right (VList [VText "a", VText "b", VText "c"])

    it "coerces valid choice" $ do
      coerceValue "x" (VTChoice ["MIT", "BSD3", "Apache"]) "MIT"
        `shouldBe` Right (VText "MIT")

    it "rejects invalid choice" $ do
      coerceValue "x" (VTChoice ["MIT", "BSD3"]) "GPL"
        `shouldBe` Left (CoercionFailed "x" (VTChoice ["MIT", "BSD3"]) "GPL")

  describe "coerceDefault" $ do
    it "coerces a raw-text bool default to VBool" $ do
      coerceDefault "x" VTBool (VText "true") `shouldBe` Right (VBool True)

    it "coerces a raw-text int default to VInt" $ do
      coerceDefault "x" VTInt (VText "42") `shouldBe` Right (VInt 42)

    it "keeps a text default as VText" $ do
      coerceDefault "x" VTText (VText "hello") `shouldBe` Right (VText "hello")

    it "validates a constrained choice default" $ do
      coerceDefault "x" (VTChoice ["MIT", "BSD3"]) (VText "MIT")
        `shouldBe` Right (VText "MIT")

    it "keeps an unconstrained (empty) choice default as VText" $ do
      coerceDefault "x" (VTChoice []) (VText "MIT") `shouldBe` Right (VText "MIT")

    it "passes an already-typed default through unchanged" $ do
      coerceDefault "x" VTBool (VBool True) `shouldBe` Right (VBool True)

    it "fails on a malformed bool default" $ do
      coerceDefault "x" VTBool (VText "treu")
        `shouldBe` Left (CoercionFailed "x" VTBool "treu")

  describe "validateVarValue" $ do
    it "passes when no validation is set" $ do
      let decl = textVar "x" True Nothing Nothing
      validateVarValue decl (VText "anything") `shouldBe` Right ()

    it "passes pattern validation" $ do
      let decl = textVar "x" True Nothing (Just (ValPattern "[a-z][a-z0-9-]*"))
      validateVarValue decl (VText "my-app") `shouldBe` Right ()

    it "rejects pattern validation" $ do
      let decl = textVar "x" True Nothing (Just (ValPattern "[a-z][a-z0-9-]*"))
      case validateVarValue decl (VText "MyApp") of
        Left (ValidationFailed _ _) -> pure ()
        other -> expectationFailure ("Expected ValidationFailed, got: " <> show other)

    it "passes range validation" $ do
      let decl = intVar "x" True Nothing (Just (ValRange 1 100))
      validateVarValue decl (VInt 50) `shouldBe` Right ()

    it "rejects out-of-range value" $ do
      let decl = intVar "x" True Nothing (Just (ValRange 1 100))
      case validateVarValue decl (VInt 200) of
        Left (ValidationFailed _ _) -> pure ()
        other -> expectationFailure ("Expected ValidationFailed, got: " <> show other)

    it "passes min-length validation" $ do
      let decl = textVar "x" True Nothing (Just (ValMinLength 3))
      validateVarValue decl (VText "hello") `shouldBe` Right ()

    it "rejects too-short value" $ do
      let decl = textVar "x" True Nothing (Just (ValMinLength 3))
      case validateVarValue decl (VText "ab") of
        Left (ValidationFailed _ _) -> pure ()
        other -> expectationFailure ("Expected ValidationFailed, got: " <> show other)

    it "passes max-length validation" $ do
      let decl = textVar "x" True Nothing (Just (ValMaxLength 5))
      validateVarValue decl (VText "hello") `shouldBe` Right ()

    it "rejects too-long value" $ do
      let decl = textVar "x" True Nothing (Just (ValMaxLength 3))
      case validateVarValue decl (VText "hello") of
        Left (ValidationFailed _ _) -> pure ()
        other -> expectationFailure ("Expected ValidationFailed, got: " <> show other)

  describe "resolveVariables" $ do
    it "resolves from CLI overrides" $ do
      let decls = [textVar "project.name" True Nothing Nothing]
          cli = Map.fromList [("project.name", "my-app")]
          env = Map.empty
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty Map.empty Map.empty of
        Right resolved -> do
          let rv = resolved Map.! "project.name"
          rv.value `shouldBe` VText "my-app"
          rv.source `shouldBe` FromCLI
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "resolves from environment variables" $ do
      let decls = [textVar "project.name" True Nothing Nothing]
          cli = Map.empty
          env = Map.fromList [("SEIHOU_VAR_PROJECT_NAME", "env-app")]
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty Map.empty Map.empty of
        Right resolved -> do
          let rv = resolved Map.! "project.name"
          rv.value `shouldBe` VText "env-app"
          rv.source `shouldBe` FromEnv "SEIHOU_VAR_PROJECT_NAME"
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "resolves from module defaults" $ do
      let decls = [textVar "project.version" False (Just (VText "0.1.0.0")) Nothing]
          cli = Map.empty
          env = Map.empty
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty Map.empty Map.empty of
        Right resolved -> do
          let rv = resolved Map.! "project.version"
          rv.value `shouldBe` VText "0.1.0.0"
          rv.source `shouldBe` FromDefault
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "rejects missing required variable" $ do
      let decls = [textVar "project.name" True Nothing Nothing]
          cli = Map.empty
          env = Map.empty
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty Map.empty Map.empty of
        Left errs -> errs `shouldBe` [MissingRequiredVar "project.name"]
        Right _ -> expectationFailure "Expected Left"

    it "CLI override beats environment variable" $ do
      let decls = [textVar "project.name" True Nothing Nothing]
          cli = Map.fromList [("project.name", "cli-app")]
          env = Map.fromList [("SEIHOU_VAR_PROJECT_NAME", "env-app")]
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty Map.empty Map.empty of
        Right resolved -> do
          (.value) (resolved Map.! "project.name") `shouldBe` VText "cli-app"
          (.source) (resolved Map.! "project.name") `shouldBe` FromCLI
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "environment variable beats module default" $ do
      let decls = [textVar "project.name" True (Just (VText "default-app")) Nothing]
          cli = Map.empty
          env = Map.fromList [("SEIHOU_VAR_PROJECT_NAME", "env-app")]
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty Map.empty Map.empty of
        Right resolved -> do
          (.value) (resolved Map.! "project.name") `shouldBe` VText "env-app"
          (.source) (resolved Map.! "project.name") `shouldBe` FromEnv "SEIHOU_VAR_PROJECT_NAME"
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "CLI override beats module default" $ do
      let decls = [textVar "project.name" True (Just (VText "default-app")) Nothing]
          cli = Map.fromList [("project.name", "cli-app")]
          env = Map.empty
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty Map.empty Map.empty of
        Right resolved ->
          (.value) (resolved Map.! "project.name") `shouldBe` VText "cli-app"
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "resolves multiple variables with mixed sources" $ do
      let decls =
            [ textVar "project.name" True Nothing Nothing,
              textVar "project.version" False (Just (VText "0.1.0.0")) Nothing,
              textVar "license" False (Just (VText "MIT")) Nothing
            ]
          cli = Map.fromList [("project.name", "my-app")]
          env = Map.fromList [("SEIHOU_VAR_LICENSE", "BSD3")]
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty Map.empty Map.empty of
        Right resolved -> do
          (.value) (resolved Map.! "project.name") `shouldBe` VText "my-app"
          (.source) (resolved Map.! "project.name") `shouldBe` FromCLI
          (.value) (resolved Map.! "project.version") `shouldBe` VText "0.1.0.0"
          (.source) (resolved Map.! "project.version") `shouldBe` FromDefault
          (.value) (resolved Map.! "license") `shouldBe` VText "BSD3"
          (.source) (resolved Map.! "license") `shouldBe` FromEnv "SEIHOU_VAR_LICENSE"
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "coerces CLI bool override" $ do
      let decls = [boolVar "enable.tests" True Nothing]
          cli = Map.fromList [("enable.tests", "true")]
          env = Map.empty
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty Map.empty Map.empty of
        Right resolved ->
          (.value) (resolved Map.! "enable.tests") `shouldBe` VBool True
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "coerces env int override" $ do
      let decls = [intVar "port" True Nothing Nothing]
          cli = Map.empty
          env = Map.fromList [("SEIHOU_VAR_PORT", "8080")]
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty Map.empty Map.empty of
        Right resolved ->
          (.value) (resolved Map.! "port") `shouldBe` VInt 8080
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "returns coercion error for bad int" $ do
      let decls = [intVar "port" True Nothing Nothing]
          cli = Map.fromList [("port", "abc")]
          env = Map.empty
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty Map.empty Map.empty of
        Left errs -> errs `shouldBe` [CoercionFailed "port" VTInt "abc"]
        Right _ -> expectationFailure "Expected Left"

    it "validates after coercion" $ do
      let decls = [textVar "project.name" True Nothing (Just (ValPattern "[a-z][a-z0-9-]*"))]
          cli = Map.fromList [("project.name", "MyBad")]
          env = Map.empty
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty Map.empty Map.empty of
        Left (err : _) -> case err of
          ValidationFailed _ _ -> pure ()
          other -> expectationFailure ("Expected ValidationFailed, got: " <> show other)
        Left [] -> expectationFailure "Expected non-empty error list"
        Right _ -> expectationFailure "Expected Left"

    it "resolves choice variable from CLI" $ do
      let decls = [choiceVar "license" True ["MIT", "BSD3", "Apache"] Nothing]
          cli = Map.fromList [("license", "MIT")]
          env = Map.empty
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty Map.empty Map.empty of
        Right resolved ->
          (.value) (resolved Map.! "license") `shouldBe` VText "MIT"
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "coerces a raw-text bool default to VBool when falling through to default" $ do
      -- Mirrors the Dhall decode of @default = Some "true"@ on a @bool@ var:
      -- the default reaches resolution as 'VText' and must arrive typed.
      let decls = [boolVar "feature.on" False (Just (VText "true"))]
          cli = Map.empty
          env = Map.empty
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty Map.empty Map.empty of
        Right resolved -> do
          (.value) (resolved Map.! "feature.on") `shouldBe` VBool True
          (.source) (resolved Map.! "feature.on") `shouldBe` FromDefault
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "coerces a raw-text int default to VInt when falling through to default" $ do
      let decls = [intVar "retries" False (Just (VText "3")) Nothing]
          cli = Map.empty
          env = Map.empty
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty Map.empty Map.empty of
        Right resolved ->
          (.value) (resolved Map.! "retries") `shouldBe` VInt 3
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "errors when a bool default cannot be coerced" $ do
      let decls = [boolVar "feature.on" False (Just (VText "treu"))]
          cli = Map.empty
          env = Map.empty
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty Map.empty Map.empty of
        Left errs -> errs `shouldBe` [CoercionFailed "feature.on" VTBool "treu"]
        Right _ -> expectationFailure "Expected Left"

    it "re-coerces a manifest-round-tripped bool value to VBool" $ do
      -- The manifest stores resolved variables as raw text (a 'VBool' is
      -- serialized to "true"). On a re-run such a value can only re-enter
      -- resolution through a config-style 'Map VarName Text' source, which
      -- routes through 'coerceValue' — so a stored bool round-trips back to
      -- 'VBool', never reaching evaluation as 'VText "true"'.
      let manifestStoredText = "true" -- i.e. varValueToText (VBool True)
          decls = [boolVar "feature.on" True Nothing]
          cli = Map.empty
          env = Map.empty
          local = Map.fromList [("feature.on", manifestStoredText)]
      case resolveVariables decls cli env "" "" local Map.empty Map.empty Map.empty Map.empty of
        Right resolved ->
          (.value) (resolved Map.! "feature.on") `shouldBe` VBool True
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "Eq <var> true evaluates True for a defaulted bool" $ do
      -- The end-to-end bug: a bool default must make @Eq feature.on true@ match.
      let decls = [boolVar "feature.on" False (Just (VText "true"))]
          cli = Map.empty
          env = Map.empty
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty Map.empty Map.empty of
        Right resolved -> do
          let varMap = Map.map (.value) resolved
          case parseExpr "Eq feature.on true" of
            Right expr -> evalExpr varMap expr `shouldBe` True
            Left err -> expectationFailure ("Expected parse, got: " <> show err)
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

  describe "formatExplain" $ do
    it "formats a provenance report with bracket notation" $ do
      let decl1 = textVar "project.name" True Nothing Nothing
          decl2 = textVar "project.version" False (Just (VText "0.1.0.0")) Nothing
          resolved =
            Map.fromList
              [ ("project.name", ResolvedVar (VText "my-app") FromCLI decl1),
                ("project.version", ResolvedVar (VText "0.1.0.0") FromDefault decl2)
              ]
          output = formatExplain resolved
      T.isInfixOf "project.name" output `shouldBe` True
      T.isInfixOf "\"my-app\"" output `shouldBe` True
      T.isInfixOf "[--var]" output `shouldBe` True
      T.isInfixOf "project.version" output `shouldBe` True
      T.isInfixOf "\"0.1.0.0\"" output `shouldBe` True
      T.isInfixOf "[default]" output `shouldBe` True

    it "formats env source with bracket notation" $ do
      let decl = textVar "license" True Nothing Nothing
          resolved =
            Map.fromList
              [("license", ResolvedVar (VText "MIT") (FromEnv "SEIHOU_VAR_LICENSE") decl)]
          output = formatExplain resolved
      T.isInfixOf "[env SEIHOU_VAR_LICENSE]" output `shouldBe` True

    it "formats local config source with bracket notation" $ do
      let decl = textVar "license" True Nothing Nothing
          resolved =
            Map.fromList
              [("license", ResolvedVar (VText "MIT") FromLocalConfig decl)]
          output = formatExplain resolved
      T.isInfixOf "[local config]" output `shouldBe` True

    it "formats namespace config source with bracket notation" $ do
      let decl = textVar "haskell.ghc" True Nothing Nothing
          resolved =
            Map.fromList
              [("haskell.ghc", ResolvedVar (VText "9.12.2") (FromNamespaceConfig "haskell") decl)]
          output = formatExplain resolved
      T.isInfixOf "[namespace: haskell]" output `shouldBe` True

    it "formats context config source with bracket notation" $ do
      let decl = textVar "user.email" True Nothing Nothing
          resolved =
            Map.fromList
              [("user.email", ResolvedVar (VText "me@work.com") (FromContextConfig "work") decl)]
          output = formatExplain resolved
      T.isInfixOf "[context: work]" output `shouldBe` True

    it "formats global config source with bracket notation" $ do
      let decl = textVar "license" True Nothing Nothing
          resolved =
            Map.fromList
              [("license", ResolvedVar (VText "MIT") FromGlobalConfig decl)]
          output = formatExplain resolved
      T.isInfixOf "[global config]" output `shouldBe` True

    it "formats parent source with bracket notation" $ do
      let decl = textVar "skill.name" True Nothing Nothing
          resolved =
            Map.fromList
              [("skill.name", ResolvedVar (VText "exec-plan") (FromParent "exec-plan") decl)]
          output = formatExplain resolved
      T.isInfixOf "[parent: exec-plan]" output `shouldBe` True

    it "uses 2-space indentation" $ do
      let decl = textVar "license" True Nothing Nothing
          resolved =
            Map.fromList
              [("license", ResolvedVar (VText "MIT") FromCLI decl)]
          output = formatExplain resolved
      T.isInfixOf "  license" output `shouldBe` True

  describe "formatDeclarations" $ do
    it "formats required variables without defaults" $ do
      let decls = [VarDecl "project.name" VTText Nothing (Just "Name") True Nothing]
          output = formatDeclarations decls
      T.isInfixOf "project.name" output `shouldBe` True
      T.isInfixOf "(required, no default)" output `shouldBe` True

    it "formats variables with default values" $ do
      let decls = [VarDecl "project.version" VTText (Just (VText "0.1.0.0")) Nothing False Nothing]
          output = formatDeclarations decls
      T.isInfixOf "\"0.1.0.0\"" output `shouldBe` True
      T.isInfixOf "(required, no default)" output `shouldBe` False

    it "formats variables with defaults using = sign" $ do
      let decls =
            [ VarDecl
                { name = "project.version",
                  type_ = VTText,
                  default_ = Just (VText "0.1.0.0"),
                  description = Nothing,
                  required = False,
                  validation = Nothing
                }
            ]
          output = formatDeclarations decls
      T.isInfixOf "project.version" output `shouldBe` True
      T.isInfixOf "= \"0.1.0.0\"" output `shouldBe` True

    it "aligns columns for multiple variables" $ do
      let decls =
            [ VarDecl "project.name" VTText Nothing (Just "Name") True Nothing,
              VarDecl "project.version" VTText (Just (VText "0.1.0.0")) Nothing False Nothing
            ]
          output = formatDeclarations decls
          outputLines = T.lines output
      -- Both lines should have the same position for "="
      length (filter (T.isInfixOf "=") outputLines) `shouldBe` 2

    it "uses 2-space indentation" $ do
      let decls = [VarDecl "x" VTText Nothing Nothing True Nothing]
          output = formatDeclarations decls
      T.isInfixOf "  x" output `shouldBe` True

  describe "resolveVariables (six-layer precedence)" $ do
    it "resolves from local config" $ do
      let decls = [textVar "license" True Nothing Nothing]
          cli = Map.empty
          env = Map.empty
          local = Map.fromList [("license", "MIT")]
      case resolveVariables decls cli env "" "" local Map.empty Map.empty Map.empty Map.empty of
        Right resolved -> do
          (.value) (resolved Map.! "license") `shouldBe` VText "MIT"
          (.source) (resolved Map.! "license") `shouldBe` FromLocalConfig
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "resolves from namespace config" $ do
      let decls = [textVar "haskell.ghc" True Nothing Nothing]
          cli = Map.empty
          env = Map.empty
          nsCfg = Map.fromList [("haskell.ghc", "9.12.2")]
      case resolveVariables decls cli env "haskell" "" Map.empty nsCfg Map.empty Map.empty Map.empty of
        Right resolved -> do
          (.value) (resolved Map.! "haskell.ghc") `shouldBe` VText "9.12.2"
          (.source) (resolved Map.! "haskell.ghc") `shouldBe` FromNamespaceConfig "haskell"
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "resolves from global config" $ do
      let decls = [textVar "license" True Nothing Nothing]
          cli = Map.empty
          env = Map.empty
          global = Map.fromList [("license", "MIT")]
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty global Map.empty of
        Right resolved -> do
          (.value) (resolved Map.! "license") `shouldBe` VText "MIT"
          (.source) (resolved Map.! "license") `shouldBe` FromGlobalConfig
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "local config overrides global config" $ do
      let decls = [textVar "license" True Nothing Nothing]
          cli = Map.empty
          env = Map.empty
          local = Map.fromList [("license", "BSD3")]
          global = Map.fromList [("license", "MIT")]
      case resolveVariables decls cli env "" "" local Map.empty Map.empty global Map.empty of
        Right resolved -> do
          (.value) (resolved Map.! "license") `shouldBe` VText "BSD3"
          (.source) (resolved Map.! "license") `shouldBe` FromLocalConfig
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "namespace config overrides global config" $ do
      let decls = [textVar "license" True Nothing Nothing]
          cli = Map.empty
          env = Map.empty
          nsCfg = Map.fromList [("license", "Apache")]
          global = Map.fromList [("license", "MIT")]
      case resolveVariables decls cli env "haskell" "" Map.empty nsCfg Map.empty global Map.empty of
        Right resolved -> do
          (.value) (resolved Map.! "license") `shouldBe` VText "Apache"
          (.source) (resolved Map.! "license") `shouldBe` FromNamespaceConfig "haskell"
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "context config resolves when namespace and local don't have variable" $ do
      let decls = [textVar "user.email" True Nothing Nothing]
          cli = Map.empty
          env = Map.empty
          ctxCfg = Map.fromList [("user.email", "me@work.com")]
      case resolveVariables decls cli env "" "work" Map.empty Map.empty ctxCfg Map.empty Map.empty of
        Right resolved -> do
          (.value) (resolved Map.! "user.email") `shouldBe` VText "me@work.com"
          (.source) (resolved Map.! "user.email") `shouldBe` FromContextConfig "work"
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "context config is lower priority than namespace config" $ do
      let decls = [textVar "user.email" True Nothing Nothing]
          cli = Map.empty
          env = Map.empty
          nsCfg = Map.fromList [("user.email", "ns@example.com")]
          ctxCfg = Map.fromList [("user.email", "ctx@example.com")]
      case resolveVariables decls cli env "haskell" "work" Map.empty nsCfg ctxCfg Map.empty Map.empty of
        Right resolved -> do
          (.value) (resolved Map.! "user.email") `shouldBe` VText "ns@example.com"
          (.source) (resolved Map.! "user.email") `shouldBe` FromNamespaceConfig "haskell"
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "context config is higher priority than global config" $ do
      let decls = [textVar "user.email" True Nothing Nothing]
          cli = Map.empty
          env = Map.empty
          ctxCfg = Map.fromList [("user.email", "ctx@example.com")]
          global = Map.fromList [("user.email", "global@example.com")]
      case resolveVariables decls cli env "" "work" Map.empty Map.empty ctxCfg global Map.empty of
        Right resolved -> do
          (.value) (resolved Map.! "user.email") `shouldBe` VText "ctx@example.com"
          (.source) (resolved Map.! "user.email") `shouldBe` FromContextConfig "work"
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "local config overrides namespace config" $ do
      let decls = [textVar "license" True Nothing Nothing]
          cli = Map.empty
          env = Map.empty
          local = Map.fromList [("license", "GPL")]
          nsCfg = Map.fromList [("license", "Apache")]
      case resolveVariables decls cli env "haskell" "" local nsCfg Map.empty Map.empty Map.empty of
        Right resolved -> do
          (.value) (resolved Map.! "license") `shouldBe` VText "GPL"
          (.source) (resolved Map.! "license") `shouldBe` FromLocalConfig
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "env overrides local config" $ do
      let decls = [textVar "license" True Nothing Nothing]
          cli = Map.empty
          env = Map.fromList [("SEIHOU_VAR_LICENSE", "env-license")]
          local = Map.fromList [("license", "local-license")]
      case resolveVariables decls cli env "" "" local Map.empty Map.empty Map.empty Map.empty of
        Right resolved -> do
          (.value) (resolved Map.! "license") `shouldBe` VText "env-license"
          (.source) (resolved Map.! "license") `shouldBe` FromEnv "SEIHOU_VAR_LICENSE"
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "CLI overrides all config layers" $ do
      let decls = [textVar "license" True Nothing Nothing]
          cli = Map.fromList [("license", "cli-license")]
          env = Map.fromList [("SEIHOU_VAR_LICENSE", "env-license")]
          local = Map.fromList [("license", "local-license")]
          nsCfg = Map.fromList [("license", "ns-license")]
          global = Map.fromList [("license", "global-license")]
      case resolveVariables decls cli env "haskell" "" local nsCfg Map.empty global Map.empty of
        Right resolved -> do
          (.value) (resolved Map.! "license") `shouldBe` VText "cli-license"
          (.source) (resolved Map.! "license") `shouldBe` FromCLI
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "global config overrides module default" $ do
      let decls = [textVar "license" False (Just (VText "default-license")) Nothing]
          cli = Map.empty
          env = Map.empty
          global = Map.fromList [("license", "global-license")]
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty global Map.empty of
        Right resolved -> do
          (.value) (resolved Map.! "license") `shouldBe` VText "global-license"
          (.source) (resolved Map.! "license") `shouldBe` FromGlobalConfig
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "resolves mixed sources across multiple variables" $ do
      let decls =
            [ textVar "project.name" True Nothing Nothing,
              textVar "license" False (Just (VText "MIT")) Nothing,
              textVar "haskell.ghc" False (Just (VText "9.8.1")) Nothing
            ]
          cli = Map.fromList [("project.name", "cli-app")]
          env = Map.empty
          local = Map.fromList [("license", "BSD3")]
          nsCfg = Map.fromList [("haskell.ghc", "9.12.2")]
      case resolveVariables decls cli env "haskell" "" local nsCfg Map.empty Map.empty Map.empty of
        Right resolved -> do
          (.value) (resolved Map.! "project.name") `shouldBe` VText "cli-app"
          (.source) (resolved Map.! "project.name") `shouldBe` FromCLI
          (.value) (resolved Map.! "license") `shouldBe` VText "BSD3"
          (.source) (resolved Map.! "license") `shouldBe` FromLocalConfig
          (.value) (resolved Map.! "haskell.ghc") `shouldBe` VText "9.12.2"
          (.source) (resolved Map.! "haskell.ghc") `shouldBe` FromNamespaceConfig "haskell"
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "omits non-required variable with no value from any source" $ do
      let decls = [textVar "optional.var" False Nothing Nothing]
          cli = Map.empty
          env = Map.empty
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty Map.empty Map.empty of
        Right resolved -> Map.member "optional.var" resolved `shouldBe` False
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "still errors on missing required variable with no value" $ do
      let decls = [textVar "required.var" True Nothing Nothing]
          cli = Map.empty
          env = Map.empty
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty Map.empty Map.empty of
        Left errs -> errs `shouldBe` [MissingRequiredVar "required.var"]
        Right _ -> expectationFailure "Expected Left"

    it "resolves non-required variable when value is provided" $ do
      let decls = [textVar "optional.var" False Nothing Nothing]
          cli = Map.empty
          env = Map.empty
          global = Map.fromList [("optional.var", "from-global")]
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty global Map.empty of
        Right resolved -> do
          (.value) (resolved Map.! "optional.var") `shouldBe` VText "from-global"
          (.source) (resolved Map.! "optional.var") `shouldBe` FromGlobalConfig
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "resolves mix of required, optional-with-value, and optional-without-value" $ do
      let decls =
            [ textVar "project.name" True Nothing Nothing,
              textVar "optional.missing" False Nothing Nothing,
              textVar "optional.present" False Nothing Nothing
            ]
          cli = Map.fromList [("project.name", "my-app")]
          env = Map.empty
          global = Map.fromList [("optional.present", "found")]
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty global Map.empty of
        Right resolved -> do
          (.value) (resolved Map.! "project.name") `shouldBe` VText "my-app"
          Map.member "optional.missing" resolved `shouldBe` False
          (.value) (resolved Map.! "optional.present") `shouldBe` VText "found"
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "coerces config values through type system" $ do
      let decls = [boolVar "enable.tests" True Nothing]
          cli = Map.empty
          env = Map.empty
          local = Map.fromList [("enable.tests", "true")]
      case resolveVariables decls cli env "" "" local Map.empty Map.empty Map.empty Map.empty of
        Right resolved ->
          (.value) (resolved Map.! "enable.tests") `shouldBe` VBool True
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "resolves from parent-supplied vars" $ do
      let decls = [textVar "skill.name" True Nothing Nothing]
          cli = Map.empty
          env = Map.empty
          parentVars = Map.fromList [("skill.name", ("exec-plan", "parent-mod"))]
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty Map.empty parentVars of
        Right resolved -> do
          (.value) (resolved Map.! "skill.name") `shouldBe` VText "exec-plan"
          (.source) (resolved Map.! "skill.name") `shouldBe` FromParent "parent-mod"
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "parent-supplied var overrides module default" $ do
      let decls = [textVar "skill.name" False (Just (VText "default-val")) Nothing]
          cli = Map.empty
          env = Map.empty
          parentVars = Map.fromList [("skill.name", ("parent-val", "parent-mod"))]
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty Map.empty parentVars of
        Right resolved -> do
          (.value) (resolved Map.! "skill.name") `shouldBe` VText "parent-val"
          (.source) (resolved Map.! "skill.name") `shouldBe` FromParent "parent-mod"
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "global config overrides parent-supplied var" $ do
      let decls = [textVar "skill.name" True Nothing Nothing]
          cli = Map.empty
          env = Map.empty
          global = Map.fromList [("skill.name", "global-val")]
          parentVars = Map.fromList [("skill.name", ("parent-val", "parent-mod"))]
      case resolveVariables decls cli env "" "" Map.empty Map.empty Map.empty global parentVars of
        Right resolved -> do
          (.value) (resolved Map.! "skill.name") `shouldBe` VText "global-val"
          (.source) (resolved Map.! "skill.name") `shouldBe` FromGlobalConfig
        Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

  describe "diagnoseResolution" $ do
    it "reports unused config keys" $ do
      let decl = textVar "project.name" True Nothing Nothing
          resolved = Map.fromList [("project.name", ResolvedVar (VText "app") FromCLI decl)]
          global = Map.fromList [("project.name", "app"), ("auther.name", "typo")]
          (unused, _) = diagnoseResolution resolved [decl] Map.empty Map.empty Map.empty global
      unused `shouldBe` [VarName "auther.name"]

    it "reports unresolved optional variables" $ do
      let decls =
            [ textVar "project.name" True Nothing Nothing,
              textVar "optional.var" False Nothing Nothing
            ]
          resolved = Map.fromList [("project.name", ResolvedVar (VText "app") FromCLI (head decls))]
          (_, unresolved) = diagnoseResolution resolved decls Map.empty Map.empty Map.empty Map.empty
      unresolved `shouldBe` [VarName "optional.var"]

    it "returns empty lists when everything matches" $ do
      let decl = textVar "license" True Nothing Nothing
          resolved = Map.fromList [("license", ResolvedVar (VText "MIT") FromGlobalConfig decl)]
          global = Map.fromList [("license", "MIT")]
          (unused, unresolved) = diagnoseResolution resolved [decl] Map.empty Map.empty Map.empty global
      unused `shouldBe` []
      unresolved `shouldBe` []

    it "detects unused keys across all config layers" $ do
      let decl = textVar "project.name" True Nothing Nothing
          resolved = Map.fromList [("project.name", ResolvedVar (VText "app") FromCLI decl)]
          local = Map.fromList [("local.extra", "x")]
          nsCfg = Map.fromList [("ns.extra", "y")]
          global = Map.fromList [("global.extra", "z")]
          (unused, _) = diagnoseResolution resolved [decl] local nsCfg Map.empty global
      unused `shouldBe` [VarName "global.extra", VarName "local.extra", VarName "ns.extra"]
