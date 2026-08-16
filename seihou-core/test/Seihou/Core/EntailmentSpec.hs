-- | Tests for 'expandEntailedEdges', the pure heart of blueprint migration
-- fan-out. It turns the edges a version window selected into the flat, ordered
-- list of steps a run actually performs, following each edge's declared
-- entailments into other blueprints.
--
-- Most of the risk in the feature lives here: a subtle bug produces a
-- plausible-looking plan that runs the wrong work, in the wrong order, or
-- twice.
module Seihou.Core.EntailmentSpec (tests) where

import Control.Lens ((^.))
import Data.Generics.Labels ()
import Data.Text (Text)
import Seihou.Core.Migration
  ( BlueprintMigration (..),
    BlueprintMigrationStep (..),
    EntailedEdge (..),
    EntailmentError (..),
    EntailmentSite (..),
    expandEntailedEdges,
  )
import Test.Hspec
import Test.Tasty (TestTree)
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.Migration entailment" spec

spec :: Spec
spec = describe "expandEntailedEdges" $ do
  it "leaves a step with no entailed edges alone" $ do
    let step = ownedStep "keiro-upgrade" (edge "2.4.0" "3.0.0" [])
    expandEntailedEdges (const Nothing) [step] `shouldBe` Right [step]

  -- The ordering rule the whole design rests on: the entailed edge is the
  -- deeper change, and the declaring edge's guidance may assume it landed.
  it "runs one entailed edge before the edge that declares it" $ do
    let kirokuEdge = edge "1.9.0" "2.0.0" []
        keiroEdge = edge "2.4.0" "3.0.0" [EntailedEdge "kiroku-upgrade" "1.9.0" "2.0.0"]
        declared = library [("kiroku-upgrade", [kirokuEdge])]
    expandEntailedEdges declared [ownedStep "keiro-upgrade" keiroEdge]
      `shouldBe` Right
        [ entailedStep "kiroku-upgrade" kirokuEdge (EntailmentSite "keiro-upgrade" "2.4.0" "3.0.0"),
          ownedStep "keiro-upgrade" keiroEdge
        ]

  it "runs several entailed edges in declaration order, all before the declaring edge" $ do
    let firstEdge = edge "1.0.0" "1.1.0" []
        secondEdge = edge "5.0.0" "6.0.0" []
        declaring =
          edge
            "2.4.0"
            "3.0.0"
            [ EntailedEdge "alpha" "1.0.0" "1.1.0",
              EntailedEdge "beta" "5.0.0" "6.0.0"
            ]
        declared = library [("alpha", [firstEdge]), ("beta", [secondEdge])]
        site = EntailmentSite "keiro-upgrade" "2.4.0" "3.0.0"
    fmap (map label) (expandEntailedEdges declared [ownedStep "keiro-upgrade" declaring])
      `shouldBe` Right
        [ "alpha 1.0.0 -> 1.1.0",
          "beta 5.0.0 -> 6.0.0",
          "keiro-upgrade 2.4.0 -> 3.0.0"
        ]
    -- and the middle step remembers what pulled it in
    fmap (map (^. #entailedBy)) (expandEntailedEdges declared [ownedStep "keiro-upgrade" declaring])
      `shouldBe` Right [Just site, Just site, Nothing]

  -- Recursion is what lets a three-deep cohort work without every blueprint
  -- knowing the whole graph.
  it "expands transitive entailment depth first" $ do
    let deepest = edge "0.1.0" "0.2.0" []
        middle = edge "1.9.0" "2.0.0" [EntailedEdge "shibuya" "0.1.0" "0.2.0"]
        top = edge "2.4.0" "3.0.0" [EntailedEdge "kiroku-upgrade" "1.9.0" "2.0.0"]
        declared = library [("kiroku-upgrade", [middle]), ("shibuya", [deepest])]
    fmap (map label) (expandEntailedEdges declared [ownedStep "keiro-upgrade" top])
      `shouldBe` Right
        [ "shibuya 0.1.0 -> 0.2.0",
          "kiroku-upgrade 1.9.0 -> 2.0.0",
          "keiro-upgrade 2.4.0 -> 3.0.0"
        ]

  -- Two selected edges of one blueprint can both depend on the same upstream
  -- edge. It is one piece of work and must run once.
  it "emits a shared entailed edge only once" $ do
    let shared = edge "1.9.0" "2.0.0" []
        earlier = edge "2.0.0" "2.4.0" [EntailedEdge "kiroku-upgrade" "1.9.0" "2.0.0"]
        later = edge "2.4.0" "3.0.0" [EntailedEdge "kiroku-upgrade" "1.9.0" "2.0.0"]
        declared = library [("kiroku-upgrade", [shared])]
    fmap
      (map label)
      ( expandEntailedEdges
          declared
          [ownedStep "keiro-upgrade" earlier, ownedStep "keiro-upgrade" later]
      )
      `shouldBe` Right
        [ "kiroku-upgrade 1.9.0 -> 2.0.0",
          "keiro-upgrade 2.0.0 -> 2.4.0",
          "keiro-upgrade 2.4.0 -> 3.0.0"
        ]

  -- The over-eager cycle check this test exists to catch keys on blueprint
  -- name. Two blueprints may legitimately entail each other at *different*
  -- edges, which is a chain, not a cycle.
  it "does not mistake mutual entailment at different edges for a cycle" $ do
    let kirokuEarly = edge "1.0.0" "1.5.0" []
        kirokuLate = edge "1.9.0" "2.0.0" [EntailedEdge "keiro-upgrade" "1.0.0" "2.0.0"]
        keiroEarly = edge "1.0.0" "2.0.0" [EntailedEdge "kiroku-upgrade" "1.0.0" "1.5.0"]
        keiroLate = edge "2.4.0" "3.0.0" [EntailedEdge "kiroku-upgrade" "1.9.0" "2.0.0"]
        declared =
          library
            [ ("kiroku-upgrade", [kirokuEarly, kirokuLate]),
              ("keiro-upgrade", [keiroEarly, keiroLate])
            ]
    fmap (map label) (expandEntailedEdges declared [ownedStep "keiro-upgrade" keiroLate])
      `shouldBe` Right
        [ "kiroku-upgrade 1.0.0 -> 1.5.0",
          "keiro-upgrade 1.0.0 -> 2.0.0",
          "kiroku-upgrade 1.9.0 -> 2.0.0",
          "keiro-upgrade 2.4.0 -> 3.0.0"
        ]

  it "reports a cycle with its chain rather than looping" $ do
    let keiroEdge = edge "2.4.0" "3.0.0" [EntailedEdge "kiroku-upgrade" "1.9.0" "2.0.0"]
        kirokuEdge = edge "1.9.0" "2.0.0" [EntailedEdge "keiro-upgrade" "2.4.0" "3.0.0"]
        declared =
          library [("keiro-upgrade", [keiroEdge]), ("kiroku-upgrade", [kirokuEdge])]
    expandEntailedEdges declared [ownedStep "keiro-upgrade" keiroEdge]
      `shouldBe` Left
        ( EntailmentCycle
            [ "keiro-upgrade 2.4.0 -> 3.0.0",
              "kiroku-upgrade 1.9.0 -> 2.0.0",
              "keiro-upgrade 2.4.0 -> 3.0.0"
            ]
        )

  -- A cycle that does not include the edge the run started from. The reported
  -- chain should begin where the repetition begins, not at the entry point.
  it "reports a cycle deeper than the entry point from where it closes" $ do
    let top = edge "2.4.0" "3.0.0" [EntailedEdge "kiroku-upgrade" "1.9.0" "2.0.0"]
        kirokuEdge = edge "1.9.0" "2.0.0" [EntailedEdge "shibuya" "0.1.0" "0.2.0"]
        shibuyaEdge = edge "0.1.0" "0.2.0" [EntailedEdge "kiroku-upgrade" "1.9.0" "2.0.0"]
        declared =
          library [("kiroku-upgrade", [kirokuEdge]), ("shibuya", [shibuyaEdge])]
    expandEntailedEdges declared [ownedStep "keiro-upgrade" top]
      `shouldBe` Left
        ( EntailmentCycle
            [ "kiroku-upgrade 1.9.0 -> 2.0.0",
              "shibuya 0.1.0 -> 0.2.0",
              "kiroku-upgrade 1.9.0 -> 2.0.0"
            ]
        )

  -- Skipping an unresolvable member silently would leave a half-migrated
  -- project with no signal, because the consumer does not know the cohort.
  it "refuses when an entailed blueprint cannot be resolved" $ do
    let keiroEdge = edge "2.4.0" "3.0.0" [EntailedEdge "kiroku-upgrade" "1.9.0" "2.0.0"]
    expandEntailedEdges (const Nothing) [ownedStep "keiro-upgrade" keiroEdge]
      `shouldBe` Left
        ( EntailedBlueprintNotFound
            (EntailmentSite "keiro-upgrade" "2.4.0" "3.0.0")
            "kiroku-upgrade"
        )

  -- Entailment names one exact edge. Falling back to window planning inside
  -- the entailed blueprint would let a release silently change which upstream
  -- work it implies.
  it "refuses when the entailed blueprint declares no such edge" $ do
    let keiroEdge = edge "2.4.0" "3.0.0" [EntailedEdge "kiroku-upgrade" "1.9.0" "2.0.0"]
        declared =
          library [("kiroku-upgrade", [edge "1.0.0" "1.5.0" [], edge "1.5.0" "2.0.0" []])]
    expandEntailedEdges declared [ownedStep "keiro-upgrade" keiroEdge]
      `shouldBe` Left
        ( EntailedEdgeNotDeclared
            (EntailmentSite "keiro-upgrade" "2.4.0" "3.0.0")
            "kiroku-upgrade"
            "1.9.0"
            "2.0.0"
        )

  it "matches an entailed edge on both ends of its window, not just its start" $ do
    let keiroEdge = edge "2.4.0" "3.0.0" [EntailedEdge "kiroku-upgrade" "1.9.0" "2.0.0"]
        declared = library [("kiroku-upgrade", [edge "1.9.0" "1.9.5" []])]
    expandEntailedEdges declared [ownedStep "keiro-upgrade" keiroEdge]
      `shouldSatisfy` \result -> case result of
        Left (EntailedEdgeNotDeclared _ _ _ _) -> True
        _ -> False

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

edge :: Text -> Text -> [EntailedEdge] -> BlueprintMigration
edge fromVersion toVersion entailed =
  BlueprintMigration
    { from = fromVersion,
      to = toVersion,
      prompt = "migrate " <> fromVersion <> " -> " <> toVersion,
      entails = entailed
    }

ownedStep :: Text -> BlueprintMigration -> BlueprintMigrationStep
ownedStep owner declared =
  BlueprintMigrationStep {owner = owner, edge = declared, entailedBy = Nothing}

entailedStep :: Text -> BlueprintMigration -> EntailmentSite -> BlueprintMigrationStep
entailedStep owner declared site =
  BlueprintMigrationStep {owner = owner, edge = declared, entailedBy = Just site}

-- | A stand-in for the blueprints a run has loaded off disk.
library :: [(Text, [BlueprintMigration])] -> Text -> Maybe [BlueprintMigration]
library table name = lookup name table

-- | The shape a failure is easiest to read in: owner and window per step.
label :: BlueprintMigrationStep -> Text
label step =
  step ^. #owner <> " " <> step ^. #edge . #from <> " -> " <> step ^. #edge . #to
