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
      st.debugMsgs `shouldBe` ["d1"]
      st.infoMsgs `shouldBe` ["i1"]
      st.warnMsgs `shouldBe` ["w1"]
      st.errorMsgs `shouldBe` ["e1"]

    it "preserves message order within each field" $ do
      let ((), st) = runPureEff $ runLoggerPure $ do
            logInfo "first"
            logInfo "second"
            logInfo "third"
            logDebug "a"
            logDebug "b"
      st.infoMsgs `shouldBe` ["first", "second", "third"]
      st.debugMsgs `shouldBe` ["a", "b"]

    it "produces empty state when no messages are logged" $ do
      let ((), st) = runPureEff $ runLoggerPure $ pure ()
      st.debugMsgs `shouldBe` []
      st.infoMsgs `shouldBe` []
      st.warnMsgs `shouldBe` []
      st.errorMsgs `shouldBe` []

    it "returns the computation result alongside state" $ do
      let (result, st) = runPureEff $ runLoggerPure $ do
            logInfo "hello"
            pure (42 :: Int)
      result `shouldBe` 42
      st.infoMsgs `shouldBe` ["hello"]

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
