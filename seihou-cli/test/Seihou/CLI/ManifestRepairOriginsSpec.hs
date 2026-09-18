module Seihou.CLI.ManifestRepairOriginsSpec (tests) where

import Control.Lens ((&), (.~), (?~), (^.))
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime (..), fromGregorian)
import Seihou.CLI.ManifestRepairOrigins
import Seihou.Core.Application (mkApplicationId)
import Seihou.Core.ArtifactIdentity (sameArtifactIdentity)
import Seihou.Core.Types
import Seihou.Manifest.Types (emptyManifest)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (callProcess)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.ManifestRepairOrigins" spec

localPath :: Text
localPath = "/Users/alice/Keikaku/bokuno/seihou-modules"

remoteUrl :: Text
remoteUrl = "https://github.com/shinzui/seihou-modules.git"

testTime :: UTCTime
testTime = UTCTime (fromGregorian 2026 9 18) 0

origin :: Text -> Text -> ArtifactOrigin
origin url name = RemoteOrigin url name (Just "seihou-modules")

-- | A manifest recording @localPath@ in every one of the six origin-bearing
-- records, plus one module from a real remote that must be left alone.
manifestWithLocalPaths :: Manifest
manifestWithLocalPaths =
  emptyManifest testTime
    & #modules
      .~ [ AppliedModule "beta" emptyParentVars (origin localPath "beta") (Just "1.0.0") testTime Nothing,
           AppliedModule "other" emptyParentVars (RemoteOrigin "https://example.com/other.git" "other" Nothing) (Just "1.0.0") testTime Nothing
         ]
    & #applications .~ [betaApplication]
    & #recipe ?~ AppliedRecipe (RecipeName "stack") (origin (localPath <> "/") "stack") (Just "1.0.0") testTime
    & #blueprint ?~ AppliedBlueprint "service" (origin localPath "service") (Just "2.0.0") testTime [] False Nothing Nothing
    & #blueprintMigrations .~ [receipt]
  where
    betaApplication =
      AppliedComposition
        { applicationId = mkApplicationId (AppliedModuleTarget "beta") [],
          target = AppliedModuleTarget "beta",
          targetOrigin = origin localPath "beta",
          targetVersion = Just "1.0.0",
          additionalModules = [],
          namespace = Nothing,
          context = Nothing,
          instances = [AppliedInstanceState "beta" emptyParentVars (origin localPath "beta") (Just "1.0.0") Map.empty],
          commandReceipts = Map.empty,
          appliedAt = testTime
        }
    receipt =
      AppliedBlueprintMigration "service" (origin localPath "service") (Just "2.0.0") "1.0.0" "2.0.0" MigrationApplied testTime Nothing

sitesFor :: Manifest -> [OriginSite]
sitesFor manifest = concat (Map.elems (localOriginUrls manifest))

installed :: Text -> Text -> OriginEvidence
installed name url = FromInstalledCopy name url (Just "seihou-modules")

spec :: Spec
spec = do
  describe "localOriginUrls" $ do
    it "groups every origin-bearing record under one normalised path" $ do
      let grouped = localOriginUrls manifestWithLocalPaths
      Map.keys grouped `shouldBe` [localPath]
      map (^. #kind) (sitesFor manifestWithLocalPaths)
        `shouldBe` [ SiteModule,
                     SiteApplicationTarget,
                     SiteApplicationInstance,
                     SiteRecipe,
                     SiteBlueprint,
                     SiteBlueprintMigration
                   ]

    it "ignores origins that are real remotes" $
      map (^. #artifactName) (sitesFor manifestWithLocalPaths) `shouldNotContain` ["other"]

  describe "validateOverrides" $ do
    let sites = localOriginUrls manifestWithLocalPaths
    it "accepts a remote URL for a recorded artifact" $
      validateOverrides sites [("beta", remoteUrl)] `shouldBe` Right ()
    it "rejects a URL that is itself a local path" $
      validateOverrides sites [("beta", "~/src/seihou-modules")] `shouldSatisfy` isLeft
    it "rejects a name recorded under no local path" $
      validateOverrides sites [("gamma", remoteUrl)] `shouldSatisfy` isLeft

  describe "planRepair" $ do
    let sites = localOriginUrls manifestWithLocalPaths
        allSites = sitesFor manifestWithLocalPaths
        evidenceWith items = Map.singleton localPath items

    it "rewrites when checkout and installed evidence agree, preferring the installed spelling" $
      planRepair
        sites
        (evidenceWith [FromCheckoutRemote "git@github.com:shinzui/seihou-modules.git", installed "beta" remoteUrl])
        []
        `shouldBe` [ Rewrite
                       localPath
                       remoteUrl
                       [FromCheckoutRemote "git@github.com:shinzui/seihou-modules.git", installed "beta" remoteUrl]
                       allSites
                   ]

    it "reports a conflict when two installed copies name different repositories" $
      planRepair sites (evidenceWith [installed "beta" remoteUrl, installed "service" "https://example.com/blueprints.git"]) []
        `shouldSatisfy` \case
          [Conflicting old _ _] -> old == localPath
          _ -> False

    it "leaves a path with no evidence unresolved" $
      planRepair sites Map.empty [] `shouldBe` [Unresolved localPath allSites]

    it "lets an override win over conflicting evidence" $
      planRepair
        sites
        (evidenceWith [installed "service" "https://example.com/blueprints.git"])
        [("beta", remoteUrl)]
        `shouldSatisfy` \case
          [Rewrite _ new (FromOverride "beta" _ : _) _] -> new == remoteUrl
          _ -> False

  describe "applyRepair" $ do
    let sites = localOriginUrls manifestWithLocalPaths
        decisions = planRepair sites Map.empty [("beta", remoteUrl)]
        repaired = applyRepair decisions manifestWithLocalPaths

    it "rewrites every record under the path to the same URL" $
      localOriginUrls repaired `shouldBe` Map.empty

    it "keeps each artifact's name and repository name" $ do
      (repaired ^. #modules) `shouldSatisfy` \case
        (beta : _) -> beta ^. #origin == RemoteOrigin remoteUrl "beta" (Just "seihou-modules")
        [] -> False
      fmap (^. #origin) (repaired ^. #recipe) `shouldBe` Just (RemoteOrigin remoteUrl "stack" (Just "seihou-modules"))

    it "leaves an unrelated remote origin untouched" $
      map (^. #origin) (repaired ^. #modules)
        `shouldContain` [RemoteOrigin "https://example.com/other.git" "other" Nothing]

    it "fills a missing repository name from the installed copy that supplied the URL" $ do
      let bare = manifestWithLocalPaths & #modules .~ [AppliedModule "beta" emptyParentVars (RemoteOrigin localPath "beta" Nothing) (Just "1.0.0") testTime Nothing]
          bareDecisions = planRepair (localOriginUrls bare) (Map.singleton localPath [installed "beta" remoteUrl]) []
      map (^. #origin) (applyRepair bareDecisions bare ^. #modules)
        `shouldBe` [RemoteOrigin remoteUrl "beta" (Just "seihou-modules")]

    it "keeps blueprint migration receipts paired with the blueprint" $ do
      let blueprintOrigin = fmap (^. #origin) (repaired ^. #blueprint)
          receiptOrigins = map (^. #origin) (repaired ^. #blueprintMigrations)
      fmap (\o -> all (sameArtifactIdentity o) receiptOrigins) blueprintOrigin `shouldBe` Just True

    it "is idempotent: a repaired manifest has nothing left to plan" $
      planRepair (localOriginUrls repaired) Map.empty [] `shouldBe` []

  describe "renderRepairOutcome" $ do
    it "names the evidence and the records" $ do
      let decisions =
            planRepair
              (localOriginUrls manifestWithLocalPaths)
              (Map.singleton localPath [installed "beta" remoteUrl])
              []
          report = renderRepairOutcome (RepairWouldWrite decisions)
      report `shouldSatisfy` T.isInfixOf (localPath <> "\n  -> " <> remoteUrl)
      report `shouldSatisfy` T.isInfixOf "evidence: the installed copy of beta records this remote"
      report
        `shouldSatisfy` T.isInfixOf
          "records: modules[beta], applications[beta], recipe[stack], blueprint[service], 1 application instance, 1 blueprint migration receipt"
      report `shouldSatisfy` T.isSuffixOf "--dry-run: nothing was written.\n"

    it "tells the user how to resolve a path without evidence" $ do
      let report = renderRepairOutcome (RepairWouldWrite (planRepair (localOriginUrls manifestWithLocalPaths) Map.empty []))
      report `shouldSatisfy` T.isInfixOf "no remote found"
      report `shouldSatisfy` T.isInfixOf "pass --set beta=<url> for the artifact recorded under this path"

  describe "sameRepository" $ do
    it "treats ssh, scp-style and https spellings of one repository as the same" $ do
      sameRepository "git@github.com:shinzui/seihou-modules.git" remoteUrl `shouldBe` True
      sameRepository "ssh://git@github.com:22/shinzui/seihou-modules" remoteUrl `shouldBe` True
    it "tells different repositories apart" $
      sameRepository "https://github.com/shinzui/other.git" remoteUrl `shouldBe` False

  describe "gatherOriginEvidence" $
    it "reads the origin remote of a recorded path that is a checkout here" $
      withSystemTempDirectory "seihou-repair-origins" $ \tmp -> do
        let checkout = tmp </> "seihou-modules"
        callProcess "git" ["init", "-q", checkout]
        callProcess "git" ["-C", checkout, "remote", "add", "origin", T.unpack remoteUrl]
        let sites = localOriginUrls (manifestWithLocalPaths & #modules .~ [AppliedModule "beta" emptyParentVars (RemoteOrigin (T.pack checkout) "beta" Nothing) Nothing testTime Nothing])
        evidence <- gatherOriginEvidence tmp [tmp </> "no-installs-here"] sites
        Map.lookup (T.pack checkout) evidence `shouldBe` Just [FromCheckoutRemote remoteUrl]
  where
    isLeft = either (const True) (const False)
