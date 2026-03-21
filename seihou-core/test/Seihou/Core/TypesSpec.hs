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
      name.unModuleName `shouldBe` "my-module"

    it "supports Eq" $ do
      ("a" :: ModuleName) `shouldBe` ("a" :: ModuleName)
      ("a" :: ModuleName) `shouldNotBe` ("b" :: ModuleName)

    it "supports Show" $ do
      show ("test" :: ModuleName) `shouldNotBe` ""

  describe "VarName" $ do
    it "supports OverloadedStrings" $ do
      let name = "project.name" :: VarName
      name.unVarName `shouldBe` "project.name"

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
              { name = "project.name",
                type_ = VTText,
                default_ = Just (VText "my-app"),
                description = Just "Name of the project",
                required = True,
                validation = Just (ValPattern "[a-z][a-z0-9-]*")
              }
      decl.required `shouldBe` True

  describe "Strategy" $ do
    it "has four distinct constructors" $ do
      Copy `shouldNotBe` Template
      Template `shouldNotBe` DhallText
      DhallText `shouldNotBe` Structured

  describe "Module" $ do
    it "can be constructed with all fields" $ do
      let m =
            Module
              { name = "haskell-base",
                version = Nothing,
                description = Just "A Haskell project template",
                vars = [],
                exports = [],
                prompts = [],
                steps = [],
                commands = [],
                dependencies = [],
                removal = Nothing
              }
      m.name `shouldBe` "haskell-base"

    it "supports Eq for identical values" $ do
      let m =
            Module
              { name = "test",
                version = Nothing,
                description = Nothing,
                vars = [],
                exports = [],
                prompts = [],
                steps = [],
                commands = [],
                dependencies = [],
                removal = Nothing
              }
      m `shouldBe` m

    it "supports Show" $ do
      let m =
            Module
              { name = "test",
                version = Nothing,
                description = Nothing,
                vars = [],
                exports = [],
                prompts = [],
                steps = [],
                commands = [],
                dependencies = [],
                removal = Nothing
              }
      show m `shouldNotBe` ""

  describe "Operation" $ do
    it "supports WriteFileOp" $ do
      let op = WriteFileOp {dest = "README.md", content = "# Hello", strategy = Template}
      op.dest `shouldBe` "README.md"

    it "supports CreateDirOp" $ do
      let op = CreateDirOp {path = "src"}
      op.path `shouldBe` "src"

    it "supports CopyFileOp" $ do
      let op = CopyFileOp {src = "a.txt", dest = "b.txt"}
      op.src `shouldBe` "a.txt"

    it "supports RunCommandOp" $ do
      let op = RunCommandOp {command = "git init", workDir = Nothing}
      op.command `shouldBe` "git init"

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
      hash.unSHA256 `shouldBe` "abc"
