module Seihou.CLI.CheckoutSyncSpec (tests) where

import Data.Aeson qualified as A
import Data.Aeson.KeyMap qualified as KM
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Seihou.CLI.CheckoutSync
import Seihou.Core.Checkout
import Seihou.Effect.Filesystem (PathEntry (..))
import Seihou.Engine.Checkout
import Seihou.Prelude
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "checkout reports" $ do
  let entry action = CheckoutEntry ".local/config" Nothing Nothing (CheckoutObservation EntryMissing True [] True True) action [] []
      result dry plan outcomes = CheckoutSyncResult "/project" dry plan (CheckoutExecution outcomes [] Nothing) []
  it "distinguishes proposed dry-run work from successful writes" $ do
    let report = checkoutReportJSON (result True (CheckoutPlan [entry CreateLink]) Map.empty)
    case report of
      A.Object fields -> do
        KM.lookup "mode" fields `shouldBe` Just (A.String "dry-run")
        KM.lookup "summary" fields
          `shouldBe` Just
            ( A.object
                [ "planned" A..= A.object ["created" A..= (1 :: Int), "replaced" A..= (0 :: Int), "retired" A..= (0 :: Int), "unchanged" A..= (0 :: Int), "refused" A..= (0 :: Int)],
                  "applied" A..= A.object ["created" A..= (0 :: Int), "replaced" A..= (0 :: Int), "retired" A..= (0 :: Int), "unchanged" A..= (0 :: Int), "refused" A..= (0 :: Int)]
                ]
            )
      _ -> expectationFailure "expected a JSON object"
  it "renders every action and keeps rollback outcomes separate" $ do
    let actions = [CreateLink, ReplaceLink, RetireLink, UnchangedLink, AlreadyAbsent, PreserveModified, RefusedLink]
    mapM_ (\action -> renderCheckoutPlan True (CheckoutPlan [entry action]) `shouldSatisfy` (not . T.null)) actions
    let report = checkoutReportJSON (result False (CheckoutPlan [entry CreateLink]) (Map.singleton ".local/config" "rolled-back"))
    T.pack (show report) `shouldSatisfy` T.isInfixOf "rolled-back"
  it "never counts a failed or rolled-back mutation as a created link" $ do
    let rendered = renderCheckoutReport (result False (CheckoutPlan [entry CreateLink]) (Map.singleton ".local/config" "rolled-back"))
    rendered `shouldSatisfy` T.isInfixOf "0 created"
    rendered `shouldSatisfy` T.isInfixOf "rolled-back"
    rendered `shouldNotSatisfy` T.isInfixOf "1 created"
  it "summarizes proposed dry-run work without claiming writes" $ do
    renderCheckoutReport (result True (CheckoutPlan [entry CreateLink]) Map.empty)
      `shouldSatisfy` T.isInfixOf "Would sync links: 1 created"
  it "bounds status to ten sorted paths and supplies the sync remedy" $ do
    let entries = [entry CreateLink & #dest .~ ("path-" <> show n) | n <- [1 :: Int .. 12]]
        rendered = renderCheckoutStatus (CheckoutPlan entries)
    rendered `shouldSatisfy` T.isInfixOf "2 more affected paths"
    T.count "run seihou sync" rendered `shouldBe` 10
  it "names a collision's cause without promising repair" $ do
    let blocked = entry RefusedLink & #errors .~ [checkoutError "checkout_path_tracked" "destination is tracked; untrack it explicitly"]
    renderCheckoutStatus (CheckoutPlan [blocked]) `shouldSatisfy` T.isInfixOf "untrack it explicitly"
