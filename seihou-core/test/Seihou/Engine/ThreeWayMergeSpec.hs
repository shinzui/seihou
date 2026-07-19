module Seihou.Engine.ThreeWayMergeSpec (tests) where

import Control.Monad (unless)
import Data.Maybe (isJust)
import Data.Text qualified as T
import Seihou.Engine.ThreeWayMerge
import System.Directory (findExecutable)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Engine.ThreeWayMerge" spec

spec :: Spec
spec = do
  describe "pure safety cases" $ do
    it "takes newly generated content when current still equals baseline" $
      threeWayMerge "base" "base" "new" `shouldReturn` MergeClean "new"

    it "preserves current content when generation did not change" $
      threeWayMerge "base" "user" "base" `shouldReturn` MergeClean "user"

    it "returns identical current and generated content" $
      threeWayMerge "base" "same" "same" `shouldReturn` MergeClean "same"

    it "handles empty content through an identity without invoking Git" $
      threeWayMerge "" "" "generated" `shouldReturn` MergeClean "generated"

    it "rejects NUL-bearing binary content even when both sides match" $ do
      result <- threeWayMerge "a\NULb" "a\NULb" "a\NULb"
      result `shouldSatisfy` isUnavailable

    it "returns unavailable when the Git executable is missing" $ do
      result <- threeWayMergeWithGit "/definitely/missing/seihou-git" "base" "user" "generated"
      result `shouldSatisfy` isUnavailable

    it "returns unavailable for a fatal driver result without markers" $ do
      result <- threeWayMergeWithGit "/usr/bin/false" "base" "user" "generated"
      result `shouldSatisfy` isUnavailable

  describe "git merge-file driver" $ do
    it "merges non-overlapping user and module insertions" $ withGit $ do
      let baseline = "alpha\nshared\nomega\n"
          current = "alpha\nuser\nshared\nomega\n"
          generated = "alpha\nshared\nmodule\nomega\n"
      result <- threeWayMerge baseline current generated
      case result of
        MergeClean merged -> do
          merged `shouldSatisfy` T.isInfixOf "user"
          merged `shouldSatisfy` T.isInfixOf "module"
        other -> expectationFailure ("expected clean merge, got " <> show other)

    it "returns labeled diff3 markers for overlapping replacements" $ withGit $ do
      result <- threeWayMerge "alpha\nshared\nomega\n" "alpha\nuser\nomega\n" "alpha\nmodule\nomega\n"
      case result of
        MergeConflicted merged -> do
          merged `shouldSatisfy` T.isInfixOf "<<<<<<< current"
          merged `shouldSatisfy` T.isInfixOf "||||||| generated-base"
          merged `shouldSatisfy` T.isInfixOf ">>>>>>> new-generated"
        other -> expectationFailure ("expected conflict, got " <> show other)

    it "preserves a user-only deletion alongside a generated insertion" $ withGit $ do
      result <-
        threeWayMerge
          "alpha\nremove-me\nomega\n"
          "alpha\nomega\n"
          "alpha\nremove-me\nomega\nmodule\n"
      case result of
        MergeClean merged -> do
          merged `shouldNotSatisfy` T.isInfixOf "remove-me"
          merged `shouldSatisfy` T.isInfixOf "module"
        other -> expectationFailure ("expected clean merge, got " <> show other)

    it "preserves a generated deletion alongside a user insertion" $ withGit $ do
      result <-
        threeWayMerge
          "alpha\nuser-anchor\nmiddle\nremove-me\nomega\n"
          "alpha\nuser\nuser-anchor\nmiddle\nremove-me\nomega\n"
          "alpha\nuser-anchor\nmiddle\nomega\n"
      case result of
        MergeClean merged -> do
          merged `shouldNotSatisfy` T.isInfixOf "remove-me"
          merged `shouldSatisfy` T.isInfixOf "user"
        other -> expectationFailure ("expected clean merge, got " <> show other)

    it "handles missing trailing newlines" $ withGit $ do
      result <- threeWayMerge "alpha\nmiddle\nomega" "user-alpha\nmiddle\nomega" "alpha\nmiddle\nmodule-omega"
      case result of
        MergeClean merged -> do
          merged `shouldSatisfy` T.isInfixOf "user-alpha"
          merged `shouldSatisfy` T.isInfixOf "module-omega"
        other -> expectationFailure ("expected clean merge, got " <> show other)

    it "round-trips Unicode changes from both sides" $ withGit $ do
      result <-
        threeWayMerge
          "こんにちは\n共有\n終わり\n"
          "こんにちは\n利用者\n共有\n終わり\n"
          "こんにちは\n共有\nモジュール\n終わり\n"
      case result of
        MergeClean merged -> do
          merged `shouldSatisfy` T.isInfixOf "利用者"
          merged `shouldSatisfy` T.isInfixOf "モジュール"
        other -> expectationFailure ("expected clean merge, got " <> show other)

isUnavailable :: MergeOutcome -> Bool
isUnavailable (MergeUnavailable message) = not (T.null message)
isUnavailable _ = False

withGit :: Expectation -> Expectation
withGit action = do
  available <- gitAvailable
  unless available (pendingWith "git is not available")
  action

gitAvailable :: IO Bool
gitAvailable = isJust <$> findExecutable "git"
