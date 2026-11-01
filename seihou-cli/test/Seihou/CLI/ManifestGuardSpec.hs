module Seihou.CLI.ManifestGuardSpec (tests) where

import Control.Lens ((&), (.~), (^.))
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Seihou.CLI.ManifestGuard
  ( ArtifactCheck (..),
    ArtifactVerdict (..),
    blockingChecks,
    checkRecipeChain,
    formatGuardRefusal,
    judgeArtifact,
    summarizeCheck,
  )
import Seihou.Core.ArtifactRef (ArtifactRefError (..))
import Seihou.Core.Types
import Seihou.Manifest.Hash (hashContent)
import Seihou.Manifest.Types (emptyManifest)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.ManifestGuard" spec

demoUrl :: Text
demoUrl = "https://example.com/demo-modules.git"

otherUrl :: Text
otherUrl = "https://example.com/other-modules.git"

remote :: Text -> ArtifactOrigin
remote url = RemoteOrigin url "demo" (Just "demo-modules")

check :: ArtifactOrigin -> ArtifactVerdict -> ArtifactCheck
check origin verdict =
  ArtifactCheck {name = ModuleName "demo", origin = origin, verdict = verdict}

spec :: Spec
spec = do
  describe "application recipe-chain guard" $ do
    let origin name = RemoteOrigin demoUrl name Nothing
        base = AppliedRecipeNode "base" (origin "base") (Just "2") (hashContent "base")
        child = AppliedRecipeNode "child" (origin "child") (Just "1") (hashContent "child")
        selected = ApplicationId "selected"
        app = AppliedComposition selected (AppliedRecipeTarget "child") (origin "child") (Just "1") [] Nothing Nothing [] Map.empty [] Nothing (Just [base, child]) (read "2026-11-01 00:00:00 UTC")
        manifest = emptyManifest (read "2026-11-01 00:00:00 UTC") & #applications .~ [app]
    it "blocks a base-only downgrade while the derived version stays unchanged" $ do
      let (checks, _) = checkRecipeChain selected [base & #recipeVersion .~ Just "1", child] manifest
      map (^. #name) (blockingChecks checks) `shouldBe` [ModuleName "base"]
    it "blocks same-name substitution and reports metadata-only changes" $ do
      let (checks, changes) = checkRecipeChain selected [base & #origin .~ RemoteOrigin otherUrl "base" Nothing & #descriptorHash .~ hashContent "changed", child] manifest
      length (blockingChecks checks) `shouldBe` 1
      T.unlines changes `shouldSatisfy` T.isInfixOf "Recipe descriptor changed: base"
    it "keeps unknown history unknown and scopes guards to the selected application" $ do
      let unknown = manifest & #applications .~ [app & #recipeChain .~ Nothing]
          (_, changes) = checkRecipeChain selected [base, child] unknown
      T.unlines changes `shouldSatisfy` T.isInfixOf "prior chain is unknown"
      checkRecipeChain (ApplicationId "another") [base & #recipeVersion .~ Just "0", child] manifest `shouldBe` ([], [])
    it "reports chain removal without requiring the removed base to remain installed" $ do
      let (checks, changes) = checkRecipeChain selected [child] manifest
      blockingChecks checks `shouldBe` []
      T.unlines changes `shouldSatisfy` T.isInfixOf "Removed recipe from chain: base"

  describe "judgeArtifact version comparison" $ do
    it "reports a strictly older local copy as stale" $
      judgeArtifact (remote demoUrl) (Just "2.0.0") (remote demoUrl) (Just "1.4.0")
        `shouldBe` ArtifactStale "2.0.0" "1.4.0"

    it "accepts a newer local copy without comment" $
      judgeArtifact (remote demoUrl) (Just "1.4.0") (remote demoUrl) (Just "2.0.0")
        `shouldBe` ArtifactOk

    it "accepts an equal local copy" $
      judgeArtifact (remote demoUrl) (Just "2.0.0") (remote demoUrl) (Just "2.0.0")
        `shouldBe` ArtifactOk

    it "pads shorter versions with zeros, so 1.4 and 1.4.0 are equal" $
      judgeArtifact (remote demoUrl) (Just "1.4") (remote demoUrl) (Just "1.4.0")
        `shouldBe` ArtifactOk

    it "refuses to order a missing recorded version" $
      judgeArtifact (remote demoUrl) Nothing (remote demoUrl) (Just "1.4.0")
        `shouldBe` ArtifactVersionIncomparable Nothing (Just "1.4.0")

    it "refuses to order a missing local version" $
      judgeArtifact (remote demoUrl) (Just "2.0.0") (remote demoUrl) Nothing
        `shouldBe` ArtifactVersionIncomparable (Just "2.0.0") Nothing

    it "refuses to order a non-numeric version rather than guessing" $
      judgeArtifact (remote demoUrl) (Just "1.0.0-rc1") (remote demoUrl) (Just "1.0.0")
        `shouldBe` ArtifactVersionIncomparable (Just "1.0.0-rc1") (Just "1.0.0")

  describe "judgeArtifact identity comparison" $ do
    it "reports a differing origin URL as a mismatch" $
      judgeArtifact (remote demoUrl) (Just "2.0.0") (remote otherUrl) (Just "2.0.0")
        `shouldBe` ArtifactOriginMismatch (remote demoUrl) (remote otherUrl)

    it "prefers the mismatch over a version difference" $
      judgeArtifact (remote demoUrl) (Just "2.0.0") (remote otherUrl) (Just "1.4.0")
        `shouldBe` ArtifactOriginMismatch (remote demoUrl) (remote otherUrl)

    it "treats a trailing .git as the same repository" $
      judgeArtifact
        (remote "https://example.com/demo-modules")
        (Just "2.0.0")
        (remote "https://example.com/demo-modules.git")
        (Just "2.0.0")
        `shouldBe` ArtifactOk

    it "treats a trailing slash as the same repository" $
      judgeArtifact
        (remote "https://example.com/demo-modules.git")
        (Just "2.0.0")
        (remote "https://example.com/demo-modules/")
        (Just "2.0.0")
        `shouldBe` ArtifactOk

    it "reports a recorded LocalOrigin as unverifiable when versions agree" $
      judgeArtifact (LocalOrigin "demo") (Just "2.0.0") (LocalOrigin "demo") (Just "2.0.0")
        `shouldBe` ArtifactUnverifiableOrigin

    it "still reports staleness under a recorded LocalOrigin" $
      judgeArtifact (LocalOrigin "demo") (Just "2.0.0") (LocalOrigin "demo") (Just "1.4.0")
        `shouldBe` ArtifactStale "2.0.0" "1.4.0"

    it "reports a remote artifact shadowed by an unprovenanced copy as unverifiable" $
      judgeArtifact (remote demoUrl) (Just "2.0.0") (LocalOrigin "demo") (Just "2.0.0")
        `shouldBe` ArtifactUnverifiableOrigin

    it "accepts a project artifact resolved at the recorded path" $
      judgeArtifact
        (ProjectOrigin ".seihou/modules/demo")
        (Just "2.0.0")
        (ProjectOrigin ".seihou/modules/demo")
        (Just "2.0.0")
        `shouldBe` ArtifactOk

    it "reports a project artifact resolved at a different path as a mismatch" $
      judgeArtifact
        (ProjectOrigin ".seihou/modules/demo")
        (Just "2.0.0")
        (ProjectOrigin "vendor/demo")
        (Just "2.0.0")
        `shouldBe` ArtifactOriginMismatch (ProjectOrigin ".seihou/modules/demo") (ProjectOrigin "vendor/demo")

  describe "blockingChecks" $ do
    it "selects exactly the three blocking verdicts" $ do
      let notFound = ArtifactNotFoundLocally (remote demoUrl) ["/nowhere/demo"]
          all' =
            [ check (remote demoUrl) ArtifactOk,
              check (remote demoUrl) (ArtifactStale "2.0.0" "1.4.0"),
              check (remote demoUrl) (ArtifactOriginMismatch (remote demoUrl) (remote otherUrl)),
              check (remote demoUrl) (ArtifactUnresolvable notFound),
              check (remote demoUrl) (ArtifactVersionIncomparable Nothing Nothing),
              check (remote demoUrl) ArtifactUnverifiableOrigin
            ]
      map (^. #verdict) (blockingChecks all')
        `shouldBe` [ ArtifactStale "2.0.0" "1.4.0",
                     ArtifactOriginMismatch (remote demoUrl) (remote otherUrl),
                     ArtifactUnresolvable notFound
                   ]

    it "returns nothing when every artifact is fine" $
      blockingChecks [check (remote demoUrl) ArtifactOk] `shouldBe` []

  describe "formatGuardRefusal" $ do
    it "names both versions, the origin, the remedy, and the escape hatch" $ do
      let message = formatGuardRefusal [check (remote demoUrl) (ArtifactStale "2.0.0" "1.4.0")]
      message `shouldSatisfy` T.isInfixOf "older than"
      message `shouldSatisfy` T.isInfixOf "2.0.0"
      message `shouldSatisfy` T.isInfixOf "1.4.0"
      message `shouldSatisfy` T.isInfixOf demoUrl
      message `shouldSatisfy` T.isInfixOf "seihou upgrade demo"
      message `shouldSatisfy` T.isInfixOf "--allow-downgrade"

    it "names both URLs on a mismatch and does not talk about versions" $ do
      let message =
            formatGuardRefusal
              [check (remote demoUrl) (ArtifactOriginMismatch (remote demoUrl) (remote otherUrl))]
      message `shouldSatisfy` T.isInfixOf demoUrl
      message `shouldSatisfy` T.isInfixOf otherUrl
      message `shouldSatisfy` T.isInfixOf "different source"
      message `shouldSatisfy` (not . T.isInfixOf "older than")

    it "points a mismatch against a recorded path at repair-origins, not at installing the path" $ do
      let recordedPath = remote "/Users/alice/src/demo-modules"
          message =
            formatGuardRefusal
              [check recordedPath (ArtifactOriginMismatch recordedPath (remote demoUrl))]
      message `shouldSatisfy` T.isInfixOf "The manifest records /Users/alice/src/demo-modules, a path on the machine that wrote it;"
      message `shouldSatisfy` T.isInfixOf "run 'seihou manifest repair-origins'."
      message `shouldSatisfy` (not . T.isInfixOf "seihou install /Users/alice")

    it "keeps a mismatch between two remote URLs exactly as it was" $ do
      let message =
            formatGuardRefusal
              [check (remote demoUrl) (ArtifactOriginMismatch (remote demoUrl) (remote otherUrl))]
      message `shouldSatisfy` T.isInfixOf ("seihou install " <> demoUrl)
      message `shouldSatisfy` (not . T.isInfixOf "repair-origins")

    it "embeds the resolver's own wording for an unresolvable artifact" $ do
      let notFound = ArtifactNotFoundLocally (remote demoUrl) ["/nowhere/demo"]
          message = formatGuardRefusal [check (remote demoUrl) (ArtifactUnresolvable notFound)]
      message `shouldSatisfy` T.isInfixOf "not"
      message `shouldSatisfy` T.isInfixOf "/nowhere/demo"
      message `shouldSatisfy` T.isInfixOf "seihou install"

    it "is empty when nothing blocks" $
      formatGuardRefusal [] `shouldBe` ""

  describe "summarizeCheck" $ do
    it "says nothing about a healthy artifact" $
      summarizeCheck (check (remote demoUrl) ArtifactOk) `shouldBe` Nothing

    it "reports a stale artifact on one line" $
      summarizeCheck (check (remote demoUrl) (ArtifactStale "2.0.0" "1.4.0"))
        `shouldSatisfy` maybe False (T.isInfixOf "seihou upgrade demo")

    it "appends the repair-origins sentence for a recorded path" $ do
      let recordedPath = remote "/Users/alice/src/demo-modules"
      summarizeCheck (check recordedPath (ArtifactOriginMismatch recordedPath (remote demoUrl)))
        `shouldSatisfy` maybe
          False
          ( T.isSuffixOf
              ". The manifest records /Users/alice/src/demo-modules, a path on the machine that wrote it; run 'seihou manifest repair-origins'."
          )
      summarizeCheck (check (remote demoUrl) (ArtifactOriginMismatch (remote demoUrl) (remote otherUrl)))
        `shouldSatisfy` maybe False (not . T.isInfixOf "repair-origins")

    it "reports an unverifiable artifact without implying a fault" $
      summarizeCheck (check (LocalOrigin "demo") ArtifactUnverifiableOrigin)
        `shouldSatisfy` maybe False (T.isInfixOf "cannot be verified")
