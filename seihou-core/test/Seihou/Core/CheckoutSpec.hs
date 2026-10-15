module Seihou.Core.CheckoutSpec (tests) where

import Control.Monad (forM_)
import Data.Aeson qualified as Aeson
import Data.Either (isLeft)
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Time (UTCTime (..), fromGregorian)
import Seihou.Core.Checkout
import Seihou.Core.Types
import Seihou.Effect.Filesystem (PathEntry (..))
import Seihou.Manifest.Types
import Seihou.Manifest.Upgrade
import Seihou.Prelude
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

record :: FilePath -> Text -> CheckoutOutputRecord
record source app = CheckoutOutputRecord (DirectorySymlink source) (Map.singleton (ApplicationId app) (Set.singleton "demo"))

tests :: IO TestTree
tests = testSpec "checkout declarations and planning" $ do
  let dest = ".local/config"
      old = Map.singleton dest (record "config/editor" "a")
      next = Map.singleton dest (record "config/new" "a")
      obs entry = Map.singleton dest (CheckoutObservation entry True [] True True)
      actions intent prior candidate entry = map (^. #action) (planCheckoutOutputs intent SyncIgnoredOnly prior candidate (obs entry) ^. #entries)
  it "rejects portable path escapes, reserved metadata and overlapping paths" $
    forM_ ["", ".", "../escape", "a/../b", "/abs", "C:local", "a\\b", "a//b", "a/./b", "a/", ".GIT/config", ".seihou/x", "a\0b"] $ \source ->
      validateCheckoutPaths source dest `shouldSatisfy` isLeft
  it "rejects source/destination ancestry in either direction" $ do
    validateCheckoutPaths "config" "config/local" `shouldSatisfy` isLeft
    validateCheckoutPaths "config/local" "config" `shouldSatisfy` isLeft
  it "uses canonical relative link text" $ do
    expectedTarget ".local/config" (DirectorySymlink "config/editor") `shouldBe` "../config/editor"
    expectedTarget ".claude/skills/demo" (DirectorySymlink "agents/skills/demo") `shouldBe` "../../agents/skills/demo"
  it "merges agreeing claims associatively, commutatively and idempotently" $ do
    let add a = mergeCheckoutRecord dest (record "config/editor" a)
        merge names = foldl (\acc app -> acc >>= add app) (Right Map.empty) names
    merge ["a", "b", "c"] `shouldBe` merge ["c", "a", "b"]
    merge ["a", "a"] `shouldBe` merge ["a"]
    merge ["a", "b", "c"] `shouldBe` (merge ["a"] >>= add "b" >>= add "c")
  it "refuses conflicting owners regardless of contribution order" $ do
    mergeCheckoutRecord dest (record "other" "b") old `shouldSatisfy` isLeft
    mergeCheckoutRecord dest (record "config/editor" "a") (Map.singleton dest (record "other" "b")) `shouldSatisfy` isLeft
  it "drops only selected owners" $ do
    Right shared <- pure (mergeCheckoutRecord dest (record "config/editor" "b") old)
    dropCheckoutOwners (Map.singleton (ApplicationId "a") (Set.singleton "demo")) shared `shouldBe` Map.singleton dest (record "config/editor" "b")
  it "rebuilds missing and wrong links but preserves correct links" $ do
    actions Rebuild old old EntryMissing `shouldBe` [CreateLink]
    actions Rebuild old old (EntrySymlink "wrong") `shouldBe` [ReplaceLink]
    actions Rebuild old old (EntrySymlink "../config/editor") `shouldBe` [UnchangedLink]
  it "refuses real objects without discarding other classifications" $ do
    let records = Map.insert ".local/second" (record "assets/shared" "a") old
        observations = Map.insert ".local/second" (CheckoutObservation EntryMissing True [] True True) (obs EntryDirectory)
        plan = planCheckoutOutputs Rebuild SyncIgnoredOnly records records observations
    checkoutApplicable plan `shouldBe` False
    map (^. #action) (plan ^. #entries) `shouldBe` [RefusedLink, CreateLink]
  it "does no repair for unchanged declarations or owner-only changes" $ do
    actions Reconcile old old EntryMissing `shouldBe` [UnchangedLink]
    actions Reconcile old (Map.singleton dest (record "config/editor" "b")) (EntrySymlink "edited") `shouldBe` [UnchangedLink]
  it "retires only matching links even with a missing source" $ do
    let observations = Map.singleton dest (CheckoutObservation (EntrySymlink "../config/editor") False [] True False)
    map (^. #action) (planCheckoutOutputs Reconcile ApplyDeclaration old Map.empty observations ^. #entries) `shouldBe` [RetireLink]
    actions Reconcile old Map.empty (EntrySymlink "edited") `shouldBe` [PreserveModified]
    actions Reconcile old Map.empty EntryDirectory `shouldBe` [PreserveModified]
    actions Reconcile old Map.empty EntryMissing `shouldBe` [AlreadyAbsent]
  it "retargets old or already-correct links but refuses third targets" $ do
    actions Reconcile old next (EntrySymlink "../config/editor") `shouldBe` [ReplaceLink]
    actions Reconcile old next (EntrySymlink "../config/new") `shouldBe` [UnchangedLink]
    actions Reconcile old next (EntrySymlink "edited") `shouldBe` [RefusedLink]
  it "rejects a rebuild contract with changed declarations" $
    checkoutApplicable (planCheckoutOutputs Rebuild SyncIgnoredOnly old next (obs EntryMissing)) `shouldBe` False
  it "keeps the warning policy distinct from sync's ignored-only policy" $ do
    let observations = Map.singleton dest (CheckoutObservation EntryMissing True [] False False)
    checkoutApplicable (planCheckoutOutputs Rebuild SyncIgnoredOnly old old observations) `shouldBe` False
    let apply = planCheckoutOutputs Reconcile ApplyDeclaration Map.empty old observations
    checkoutApplicable apply `shouldBe` True
    concatMap (^. #warnings) (apply ^. #entries) `shouldSatisfy` (not . null)
  it "adds schema 9 losslessly without inventing declarations" $ do
    let now = UTCTime (fromGregorian 2026 10 15) 0
        original = emptyManifest now & #version .~ ManifestSchemaVersion 8
    Right (_, document) <- pure (upgradeDocumentLosslessly (ManifestSchemaVersion 9) =<< decode original)
    case manifestFromJSON (encode document) of
      Right result -> Map.null (result ^. #checkoutOutputs) `shouldBe` True
      Left err -> expectationFailure err
  it "rejects duplicate keys before JSON object construction, including escaped-equivalent keys" $ do
    manifestFromJSON "{\"version\":9,\"version\":9}" `shouldSatisfy` isLeft
    manifestFromJSON "{\"version\":9,\"owners\":{\"a\":[],\"\\u0061\":[]}}" `shouldSatisfy` either (T.isInfixOf "duplicate" . T.pack) (const False)
  where
    decode manifest = first (const (MalformedDocument (ManifestSchemaVersion 8) "invalid fixture")) (Aeson.eitherDecode (manifestToJSON manifest))
    encode = Aeson.encode
