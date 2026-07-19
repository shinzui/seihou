module Seihou.Core.CommandFingerprintSpec (tests) where

import Data.Text (Text)
import Seihou.Core.CommandFingerprint (fingerprintCommand)
import Seihou.Core.Types
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.CommandFingerprint" spec

commandOp :: Text -> Maybe FilePath -> ModuleName -> Int -> Operation
commandOp command workDir moduleName occurrence =
  RunCommandOp
    { command = command,
      workDir = workDir,
      moduleName = moduleName,
      occurrence = occurrence
    }

spec :: Spec
spec = do
  describe "fingerprintCommand" $ do
    it "is stable for the same rendered command" $ do
      let operation = commandOp "cabal build" (Just "packages/app") "app" 0
      fingerprintCommand operation `shouldBe` fingerprintCommand operation

    it "normalizes project-relative work directories" $ do
      fingerprintCommand (commandOp "cabal build" (Just "packages/./app") "app" 0)
        `shouldBe` fingerprintCommand (commandOp "cabal build" (Just "packages/app") "app" 0)

    it "distinguishes command text, work directory, owner, and occurrence" $ do
      let original = fingerprintCommand (commandOp "cabal build" Nothing "app" 0)
      original `shouldNotBe` fingerprintCommand (commandOp "cabal test" Nothing "app" 0)
      original `shouldNotBe` fingerprintCommand (commandOp "cabal build" (Just "app") "app" 0)
      original `shouldNotBe` fingerprintCommand (commandOp "cabal build" Nothing "other" 0)
      original `shouldNotBe` fingerprintCommand (commandOp "cabal build" Nothing "app" 1)

    it "does not fingerprint file operations" $ do
      fingerprintCommand (WriteFileOp "README.md" "content" Template) `shouldBe` Nothing
