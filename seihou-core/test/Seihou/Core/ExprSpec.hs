module Seihou.Core.ExprSpec (tests) where

import Data.Map.Strict qualified as Map
import Seihou.Core.Expr (evalExpr, parseExpr)
import Seihou.Core.Types
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.Expr" spec

spec :: Spec
spec = do
  describe "parseExpr" $ do
    it "parses true literal" $ do
      parseExpr "true" `shouldBe` Right (ExprLit True)

    it "parses false literal" $ do
      parseExpr "false" `shouldBe` Right (ExprLit False)

    it "parses IsSet atom" $ do
      parseExpr "IsSet license" `shouldBe` Right (ExprIsSet "license")

    it "parses IsSet with dotted var name" $ do
      parseExpr "IsSet project.name" `shouldBe` Right (ExprIsSet "project.name")

    it "parses Eq with quoted value" $ do
      parseExpr "Eq license \"MIT\""
        `shouldBe` Right (ExprEq "license" (VText "MIT"))

    it "parses Eq with bare word value" $ do
      parseExpr "Eq license MIT"
        `shouldBe` Right (ExprEq "license" (VText "MIT"))

    it "parses && expression" $ do
      parseExpr "IsSet a && IsSet b"
        `shouldBe` Right (ExprAnd (ExprIsSet "a") (ExprIsSet "b"))

    it "parses || expression" $ do
      parseExpr "IsSet a || IsSet b"
        `shouldBe` Right (ExprOr (ExprIsSet "a") (ExprIsSet "b"))

    it "parses ! negation" $ do
      parseExpr "!true"
        `shouldBe` Right (ExprNot (ExprLit True))

    it "parses negation with space" $ do
      parseExpr "! false"
        `shouldBe` Right (ExprNot (ExprLit False))

    it "parses parenthesized expression" $ do
      parseExpr "(true)"
        `shouldBe` Right (ExprLit True)

    it "respects operator precedence: && binds tighter than ||" $ do
      parseExpr "IsSet a && IsSet b || IsSet c"
        `shouldBe` Right (ExprOr (ExprAnd (ExprIsSet "a") (ExprIsSet "b")) (ExprIsSet "c"))

    it "parentheses override precedence" $ do
      parseExpr "IsSet a && (IsSet b || IsSet c)"
        `shouldBe` Right (ExprAnd (ExprIsSet "a") (ExprOr (ExprIsSet "b") (ExprIsSet "c")))

    it "parses compound expression from design doc" $ do
      parseExpr "IsSet license && Eq license \"MIT\""
        `shouldBe` Right
          ( ExprAnd
              (ExprIsSet "license")
              (ExprEq "license" (VText "MIT"))
          )

    it "rejects empty expression" $ do
      parseExpr "" `shouldBe` Left "empty expression"

    it "rejects malformed expression" $ do
      case parseExpr "@#$" of
        Left _ -> pure ()
        Right r -> expectationFailure ("Expected parse error, got: " <> show r)

    it "handles whitespace" $ do
      parseExpr "  true  " `shouldBe` Right (ExprLit True)

  describe "evalExpr" $ do
    let vars =
          Map.fromList
            [ (VarName "license", VText "MIT"),
              (VarName "project.name", VText "my-app"),
              (VarName "enabled", VBool True)
            ]

    it "evaluates ExprLit True" $ do
      evalExpr vars (ExprLit True) `shouldBe` True

    it "evaluates ExprLit False" $ do
      evalExpr vars (ExprLit False) `shouldBe` False

    it "evaluates ExprIsSet for present variable" $ do
      evalExpr vars (ExprIsSet "license") `shouldBe` True

    it "evaluates ExprIsSet for absent variable" $ do
      evalExpr vars (ExprIsSet "missing") `shouldBe` False

    it "evaluates ExprEq when values match" $ do
      evalExpr vars (ExprEq "license" (VText "MIT")) `shouldBe` True

    it "evaluates ExprEq when values differ" $ do
      evalExpr vars (ExprEq "license" (VText "BSD")) `shouldBe` False

    it "evaluates ExprNot" $ do
      evalExpr vars (ExprNot (ExprLit True)) `shouldBe` False
      evalExpr vars (ExprNot (ExprLit False)) `shouldBe` True

    it "evaluates ExprAnd" $ do
      evalExpr vars (ExprAnd (ExprLit True) (ExprLit True)) `shouldBe` True
      evalExpr vars (ExprAnd (ExprLit True) (ExprLit False)) `shouldBe` False

    it "evaluates ExprOr" $ do
      evalExpr vars (ExprOr (ExprLit True) (ExprLit False)) `shouldBe` True
      evalExpr vars (ExprOr (ExprLit False) (ExprLit False)) `shouldBe` False

    it "evaluates compound expression from design doc" $ do
      let expr = ExprAnd (ExprIsSet "license") (ExprEq "license" (VText "MIT"))
      evalExpr vars expr `shouldBe` True
      evalExpr Map.empty expr `shouldBe` False
