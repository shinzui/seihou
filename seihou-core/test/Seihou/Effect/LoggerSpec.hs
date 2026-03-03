module Seihou.Effect.LoggerSpec (tests) where

import Effectful
import Seihou.Core.Types (LogLevel (..))
import Seihou.Effect.Logger (logDebug, logError, logInfo, logWarn)
import Seihou.Effect.LoggerInterp (shouldLog)
import Seihou.Effect.LoggerPure (LoggerState (..), runLoggerPure)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Effect.Logger" spec

spec :: Spec
spec = do
  describe "runLoggerPure" $ do
    it "captures all four log levels in separate fields" $ do
      let ((), st) = runPureEff $ runLoggerPure $ do
            logDebug "d1"
            logInfo "i1"
            logWarn "w1"
            logError "e1"
      logDebugMsgs st `shouldBe` ["d1"]
      logInfoMsgs st `shouldBe` ["i1"]
      logWarnMsgs st `shouldBe` ["w1"]
      logErrorMsgs st `shouldBe` ["e1"]

    it "preserves message order within each field" $ do
      let ((), st) = runPureEff $ runLoggerPure $ do
            logInfo "first"
            logInfo "second"
            logInfo "third"
            logDebug "a"
            logDebug "b"
      logInfoMsgs st `shouldBe` ["first", "second", "third"]
      logDebugMsgs st `shouldBe` ["a", "b"]

    it "produces empty state when no messages are logged" $ do
      let ((), st) = runPureEff $ runLoggerPure $ pure ()
      logDebugMsgs st `shouldBe` []
      logInfoMsgs st `shouldBe` []
      logWarnMsgs st `shouldBe` []
      logErrorMsgs st `shouldBe` []

    it "returns the computation result alongside state" $ do
      let (result, st) = runPureEff $ runLoggerPure $ do
            logInfo "hello"
            pure (42 :: Int)
      result `shouldBe` 42
      logInfoMsgs st `shouldBe` ["hello"]

  describe "shouldLog" $ do
    it "LogVerbose configured shows all levels" $ do
      shouldLog LogVerbose LogVerbose `shouldBe` True
      shouldLog LogVerbose LogNormal `shouldBe` True
      shouldLog LogVerbose LogQuiet `shouldBe` True

    it "LogNormal configured shows Normal and Quiet" $ do
      shouldLog LogNormal LogVerbose `shouldBe` False
      shouldLog LogNormal LogNormal `shouldBe` True
      shouldLog LogNormal LogQuiet `shouldBe` True

    it "LogQuiet configured shows only Quiet" $ do
      shouldLog LogQuiet LogVerbose `shouldBe` False
      shouldLog LogQuiet LogNormal `shouldBe` False
      shouldLog LogQuiet LogQuiet `shouldBe` True
