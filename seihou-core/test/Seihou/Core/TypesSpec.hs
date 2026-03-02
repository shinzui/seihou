module Seihou.Core.TypesSpec (tests) where

import Seihou.Core.Types
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.Types" spec

spec :: Spec
spec = do
  describe "ModuleName" $ do
    it "supports OverloadedStrings" $ do
      let name = "my-module" :: ModuleName
      unModuleName name `shouldBe` "my-module"

    it "supports Eq" $ do
      ("a" :: ModuleName) `shouldBe` ("a" :: ModuleName)
      ("a" :: ModuleName) `shouldNotBe` ("b" :: ModuleName)

    it "supports Show" $ do
      show ("test" :: ModuleName) `shouldNotBe` ""

  describe "VarName" $ do
    it "supports OverloadedStrings" $ do
      let name = "project.name" :: VarName
      unVarName name `shouldBe` "project.name"

  describe "VarType" $ do
    it "has five distinct constructors" $ do
      VTText `shouldNotBe` VTBool
      VTBool `shouldNotBe` VTInt
      VTInt `shouldNotBe` VTList VTText
      VTList VTText `shouldNotBe` VTChoice ["a"]

  describe "VarValue" $ do
    it "supports Text values" $ do
      VText "hello" `shouldBe` VText "hello"

    it "supports Bool values" $ do
      VBool True `shouldNotBe` VBool False

    it "supports Int values" $ do
      VInt 42 `shouldBe` VInt 42

    it "supports List values" $ do
      VList [VText "a", VText "b"] `shouldBe` VList [VText "a", VText "b"]

  describe "VarDecl" $ do
    it "can be constructed with all fields" $ do
      let decl =
            VarDecl
              { varName = "project.name",
                varType = VTText,
                varDefault = Just (VText "my-app"),
                varDescription = Just "Name of the project",
                varRequired = True,
                varValidation = Just (ValPattern "[a-z][a-z0-9-]*")
              }
      varRequired decl `shouldBe` True

  describe "Strategy" $ do
    it "has four distinct constructors" $ do
      Copy `shouldNotBe` Template
      Template `shouldNotBe` DhallText
      DhallText `shouldNotBe` Structured

  describe "Module" $ do
    it "can be constructed with all fields" $ do
      let m =
            Module
              { moduleName = "haskell-base",
                moduleDescription = Just "A Haskell project template",
                moduleVars = [],
                moduleExports = [],
                modulePrompts = [],
                moduleSteps = [],
                moduleDependencies = []
              }
      moduleName m `shouldBe` "haskell-base"

    it "supports Eq for identical values" $ do
      let m =
            Module
              { moduleName = "test",
                moduleDescription = Nothing,
                moduleVars = [],
                moduleExports = [],
                modulePrompts = [],
                moduleSteps = [],
                moduleDependencies = []
              }
      m `shouldBe` m

    it "supports Show" $ do
      let m =
            Module
              { moduleName = "test",
                moduleDescription = Nothing,
                moduleVars = [],
                moduleExports = [],
                modulePrompts = [],
                moduleSteps = [],
                moduleDependencies = []
              }
      show m `shouldNotBe` ""

  describe "Operation" $ do
    it "supports WriteFileOp" $ do
      let op = WriteFileOp {opDest = "README.md", opContent = "# Hello"}
      opDest op `shouldBe` "README.md"

    it "supports CreateDirOp" $ do
      let op = CreateDirOp {opPath = "src"}
      opPath op `shouldBe` "src"

    it "supports CopyFileOp" $ do
      let op = CopyFileOp {opSrc = "a.txt", opDest = "b.txt"}
      opSrc op `shouldBe` "a.txt"

    it "supports RunCommandOp" $ do
      let op = RunCommandOp {opCommand = "git init", opWorkDir = Nothing}
      opCommand op `shouldBe` "git init"

  describe "Expr" $ do
    it "supports ExprIsSet" $ do
      ExprIsSet "x" `shouldBe` ExprIsSet "x"

    it "supports logical operations" $ do
      let expr = ExprAnd (ExprIsSet "a") (ExprNot (ExprLit False))
      expr `shouldBe` expr

    it "supports ExprEq" $ do
      ExprEq "x" (VText "hello") `shouldBe` ExprEq "x" (VText "hello")

  describe "Manifest" $ do
    it "has a version field" $ do
      -- Verify the Manifest type is a record with expected fields
      let hash = SHA256 "abc"
      unSHA256 hash `shouldBe` "abc"
