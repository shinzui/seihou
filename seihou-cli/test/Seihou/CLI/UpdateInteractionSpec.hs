module Seihou.CLI.UpdateInteractionSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Seihou.CLI.Update (UpdatePlan (..))
import Seihou.CLI.Update.Interaction
  ( InteractionError (..),
    InteractionMode (..),
    ResolutionDecision (..),
    applyResolutionDecisions,
    forceResolveUpdatePlan,
    resolveInteractively,
  )
import Seihou.CLI.UpdateFixture (conflictPlan, orphanPlan, unavailableConflictPlan)
import Seihou.Engine.Reconcile
  ( FileConflictChoice (..),
    FileReconciliation (..),
    OrphanChoice (..),
    ReconciliationPlan (..),
    ResolvedFileConflict (..),
    unresolvedPaths,
  )
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.Update.Interaction" spec

spec :: Spec
spec = do
  it "refuses unresolved plans in non-interactive mode" $ do
    result <- resolveInteractively NonInteractive conflictPlan
    result `shouldBe` Left (InteractionRequired (Set.singleton "README.md"))

  it "force accepts ordinary generated conflicts" $ do
    resolved <- expectResolved conflictPlan (forceResolveUpdatePlan conflictPlan)
    unresolvedPaths resolved.reconciliation `shouldBe` Set.empty
    case Map.lookup "README.md" resolved.reconciliation.files of
      Just (FileConflict _ _ _ _ _ _ (Just choice)) ->
        choice.choice `shouldBe` AcceptGenerated
      other -> expectationFailure ("expected resolved conflict, got " <> show other)

  it "force retains edited orphans as tracked state" $ do
    resolved <- expectResolved orphanPlan (forceResolveUpdatePlan orphanPlan)
    case Map.lookup "README.md" resolved.reconciliation.files of
      Just (FileOrphanEdited _ _ _ _ (Just choice)) ->
        choice `shouldBe` RetainTrackedOrphan
      other -> expectationFailure ("expected resolved orphan, got " <> show other)

  it "force leaves merge-driver failures unresolved" $ do
    resolved <- expectResolved unavailableConflictPlan (forceResolveUpdatePlan unavailableConflictPlan)
    unresolvedPaths resolved.reconciliation `shouldBe` Set.singleton "README.md"

  it "applies explicit keep-current and detach-orphan choices without writing" $ do
    kept <- expectResolved conflictPlan (applyResolutionDecisions [ResolveFile "README.md" KeepCurrent] conflictPlan)
    case Map.lookup "README.md" kept.reconciliation.files of
      Just (FileConflict _ _ _ _ _ _ (Just choice)) -> choice.choice `shouldBe` KeepCurrent
      other -> expectationFailure ("expected keep-current conflict resolution, got " <> show other)
    detached <- expectResolved orphanPlan (applyResolutionDecisions [ResolveOrphan "README.md" DetachAndKeepOrphan] orphanPlan)
    case Map.lookup "README.md" detached.reconciliation.files of
      Just (FileOrphanEdited _ _ _ _ (Just choice)) -> choice `shouldBe` DetachAndKeepOrphan
      other -> expectationFailure ("expected detached orphan resolution, got " <> show other)

expectResolved fallback result = case result of
  Left err -> expectationFailure (show err) >> pure fallback
  Right resolved -> pure resolved
