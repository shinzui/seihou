module Seihou.Manifest.UpgradeSpec (tests) where

import Control.Lens ((^.))
import Control.Monad (forM_)
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Seihou.Core.Types
import Seihou.Manifest.Types
import Seihou.Manifest.Upgrade
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Manifest.Upgrade" spec

v :: Int -> ManifestSchemaVersion
v = ManifestSchemaVersion

-- | A schema-6 document with an additive path, a path with no evidence, an
-- explicit false, and keys this build does not model at every level.
schema6Document :: Aeson.Value
schema6Document =
  Aeson.object
    [ "version" Aeson..= (6 :: Int),
      "generatedAt" Aeson..= ("2026-03-01T10:30:00Z" :: String),
      "modules" Aeson..= ([] :: [Aeson.Value]),
      "variables" Aeson..= Aeson.object [],
      "applications" Aeson..= ([] :: [Aeson.Value]),
      "producerOwned" Aeson..= Aeson.object ["keep" Aeson..= True],
      "files"
        Aeson..= Aeson.object
          [ ".gitignore" Aeson..= record [("additiveOnly", Aeson.Bool True), ("applications", Aeson.toJSON ["a" :: String, "b"])],
            "README.md" Aeson..= record [("futureKey", Aeson.String "survives")],
            "flake.nix" Aeson..= record [("additiveOnly", Aeson.Bool False)]
          ]
    ]
  where
    record extra =
      Aeson.Object
        ( KeyMap.fromList
            ( [ ("hash", Aeson.String "aaa"),
                ("module", Aeson.String "base"),
                ("strategy", Aeson.String "template"),
                ("generatedAt", Aeson.String "2026-03-01T10:30:00Z")
              ]
                <> extra
            )
        )

fileField :: String -> Aeson.Key -> Aeson.Value -> Maybe Aeson.Value
fileField path key (Aeson.Object top) = case KeyMap.lookup "files" top of
  Just (Aeson.Object files) -> case KeyMap.lookup (Key.fromString path) files of
    Just (Aeson.Object record) -> KeyMap.lookup key record
    _ -> Nothing
  _ -> Nothing
fileField _ _ _ = Nothing

spec :: Spec
spec = do
  it "upgrades schema 11 with unknown recipe inputs without manufacturing answers" $ do
    let document = Aeson.object ["version" Aeson..= (11 :: Int), "applications" Aeson..= [Aeson.object ["producerOwned" Aeson..= True]]]
    case upgradeDocumentLosslessly (v 12) document of
      Left err -> expectationFailure (show err)
      Right (_, Aeson.Object fields) -> KeyMap.lookup "applications" fields `shouldBe` Just (Aeson.toJSON [Aeson.object ["producerOwned" Aeson..= True, "recipeInputs" Aeson..= Aeson.Null]])
      Right _ -> expectationFailure "expected manifest object"

  describe "the step registry" $ do
    it "plans a contiguous path from every supported version to the current one" $
      -- ADR 0014's mechanical gap check: a schema bump without its adjacent
      -- step fails here.
      forM_ [oldestUpgradableManifestVersion ^. #unManifestSchemaVersion .. currentManifestVersion ^. #unManifestSchemaVersion] $ \source ->
        case planManifestUpgrade (v source) currentManifestVersion of
          Left err -> expectationFailure ("no path from schema " <> show source <> ": " <> show err)
          Right steps -> do
            map (^. #fromVersion) steps `shouldBe` map v [source .. currentManifestVersion ^. #unManifestSchemaVersion - 1]
            map (^. #toVersion) steps `shouldBe` map v [source + 1 .. currentManifestVersion ^. #unManifestSchemaVersion]

    it "defines exactly one step per source version" $ do
      let sources = map (^. #fromVersion) manifestUpgradeSteps
      length sources `shouldBe` Map.size (Map.fromList [(s, ()) | s <- sources])

    it "returns an empty path from a version to itself" $
      planManifestUpgrade (v 7) (v 7) `shouldBe` Right []

    it "stops at a requested intermediate target" $
      map (^. #toVersion) <$> planManifestUpgrade (v 5) (v 6) `shouldBe` Right [v 6]

    it "reports a missing adjacent step instead of jumping over it" $ do
      let gappy = filter ((/= v 6) . (^. #fromVersion)) manifestUpgradeSteps
      planUpgradeWith gappy (v 7) (v 5) (v 7) `shouldBe` Left (MissingUpgradeStep (v 6))

    it "rejects targets above current and below the source" $ do
      planManifestUpgrade (v 6) (v 99) `shouldBe` Left (TargetAboveCurrent (v 99))
      planManifestUpgrade (v 7) (v 6) `shouldBe` Left (TargetBelowSource (v 7) (v 6))
      planManifestUpgrade (v 99) (v 99) `shouldBe` Left (SourceNewerThanBinary (v 99))
      planManifestUpgrade (v 0) (v 7) `shouldBe` Left (SourceVersionUnsupported (v 0))

    it "classifies the path conversion as inference-bearing and 6 -> 7 as lossless" $ do
      let kindFrom source = upgradeStepKind . (^. #action) <$> lookup (v source) [(s ^. #fromVersion, s) | s <- manifestUpgradeSteps]
      kindFrom 5 `shouldBe` Just InferenceBearingUpgrade
      kindFrom 6 `shouldBe` Just LosslessUpgrade

  describe "the 10 -> 11 seed ownership step" $ do
    let legacy apps extra =
          Aeson.object
            ( [ "module" Aeson..= ("first" :: String),
                "applications" Aeson..= apps,
                "outcome" Aeson..= ("created" :: String),
                "settledAt" Aeson..= ("2026-03-01T10:30:00Z" :: String)
              ]
                <> extra
            )
        document receipt = case upgradeDocumentLosslessly (v 10) schema6Document of
          Right (_, Aeson.Object top) -> Aeson.Object (KeyMap.insert "seeds" (Aeson.object ["CHANGELOG.md" Aeson..= receipt]) top)
          _ -> error "invalid fixture"
    it "preserves application-only uncertainty and unknown fields losslessly" $ do
      let old = document (legacy (["a", "b"] :: [String]) ["futureKey" Aeson..= True])
      Right (steps, upgraded) <- pure (upgradeDocumentLosslessly (v 11) old)
      map (^. #action) steps `shouldBe` [MakeSeedOwnershipExplicit]
      map (upgradeStepKind . (^. #action)) steps `shouldBe` [LosslessUpgrade]
      case upgraded of
        Aeson.Object top -> do
          KeyMap.lookup "producerOwned" top `shouldBe` Just (Aeson.object ["keep" Aeson..= True])
          KeyMap.lookup "checkoutOutputs" top `shouldBe` Just (Aeson.object [])
          case KeyMap.lookup "seeds" top of
            Just (Aeson.Object seeds) -> case KeyMap.lookup "CHANGELOG.md" seeds of
              Just (Aeson.Object receipt) -> do
                KeyMap.lookup "applications" receipt `shouldBe` Nothing
                KeyMap.lookup "futureKey" receipt `shouldBe` Just (Aeson.Bool True)
                KeyMap.lookup "ownership" receipt `shouldBe` Just (Aeson.object ["kind" Aeson..= ("legacy-applications" :: String), "applications" Aeson..= (["a", "b"] :: [String])])
              _ -> expectationFailure "missing receipt"
            _ -> expectationFailure "missing seeds"
        _ -> expectationFailure "not an object"
      Right decoded <- pure (manifestFromJSON (Aeson.encode upgraded))
      fmap (^. #ownership) (Map.lookup "CHANGELOG.md" (decoded ^. #seeds)) `shouldBe` Just (LegacySeedOwners (Set.fromList [ApplicationId "a", ApplicationId "b"]))
      manifestFromJSON (manifestToJSON decoded) `shouldBe` Right decoded
    it "preserves the old representation on every supported seed schema" $
      forM_ [8, 9, 10] $ \version -> do
        let old = setDocumentSchemaVersion (v version) (document (legacy (["a"] :: [String]) []))
        Right decoded <- pure (manifestFromJSON (Aeson.encode old))
        manifestFromJSON (manifestToJSON decoded) `shouldBe` Right decoded
        fmap (^. #ownership) (Map.lookup "CHANGELOG.md" (decoded ^. #seeds)) `shouldBe` Just (LegacySeedOwners (Set.singleton (ApplicationId "a")))
    it "rejects malformed legacy owners without stamping" $
      forM_ [Aeson.Bool True, Aeson.String "a", Aeson.toJSON [False]] $ \apps ->
        upgradeDocumentLosslessly (v 11) (document (legacy apps [])) `shouldSatisfy` either (const True) (const False)
    it "rejects unknown ownership kinds and duplicate authoritative fields" $ do
      let malformed = [Aeson.object ["kind" Aeson..= ("future" :: String)], Aeson.object ["kind" Aeson..= ("instances" :: String), "owners" Aeson..= True]]
      forM_ malformed $ \ownership -> do
        let raw = setDocumentSchemaVersion (v 11) (document (legacy (["a"] :: [String]) ["ownership" Aeson..= ownership]))
        manifestFromJSON (Aeson.encode raw) `shouldSatisfy` either (const True) (const False)

    it "requires valid tagged ownership without relying on duplicate field rejection" $ do
      let receipt ownership = Aeson.object ["module" Aeson..= ("first" :: String), "outcome" Aeson..= ("created" :: String), "settledAt" Aeson..= ("2026-03-01T10:30:00Z" :: String), "ownership" Aeson..= ownership]
          malformed = [Aeson.object ["kind" Aeson..= ("future" :: String)], Aeson.object ["kind" Aeson..= ("instances" :: String), "owners" Aeson..= True], Aeson.object ["kind" Aeson..= ("instances" :: String), "owners" Aeson..= Aeson.object []], Aeson.object ["kind" Aeson..= ("instances" :: String), "owners" Aeson..= Aeson.object ["a" Aeson..= (["x", "x"] :: [String])]]]
      forM_ malformed $ \ownership ->
        manifestFromJSON (Aeson.encode (setDocumentSchemaVersion (v 11) (document (receipt ownership)))) `shouldSatisfy` either (const True) (const False)

  describe "the 7 -> 8 step" $ do
    it "preserves unrelated raw fields and adds seed receipts" $ do
      Right (_, upgraded) <- pure (upgradeDocumentLosslessly (v 8) schema6Document)
      documentSchemaVersion upgraded `shouldBe` Right (v 8)
      case upgraded of
        Aeson.Object fields -> do
          KeyMap.lookup "seeds" fields `shouldBe` Just (Aeson.object [])
          KeyMap.lookup "producerOwned" fields `shouldBe` Just (Aeson.object ["keep" Aeson..= True])
        _ -> expectationFailure "expected object"
      case Aeson.fromJSON upgraded :: Aeson.Result Manifest of
        Aeson.Success manifest -> manifestFromJSON (manifestToJSON manifest) `shouldBe` Right manifest
        Aeson.Error err -> expectationFailure err
    it "rejects malformed seed containers before stamping" $ do
      let document = Aeson.object ["version" Aeson..= (7 :: Int), "seeds" Aeson..= False]
      upgradeDocumentLosslessly (v 8) document `shouldSatisfy` either (const True) (const False)

  describe "the 6 -> 7 step" $ do
    let upgraded = upgradeDocumentLosslessly (v 7) schema6Document

    it "maps additiveOnly: true to additive-only and absent or false to unknown" $ do
      (fileField ".gitignore" "sharedWriteMode" . snd <$> upgraded) `shouldBe` Right (Just (Aeson.String "additive-only"))
      (fileField "README.md" "sharedWriteMode" . snd <$> upgraded) `shouldBe` Right (Just (Aeson.String "unknown"))
      (fileField "flake.nix" "sharedWriteMode" . snd <$> upgraded) `shouldBe` Right (Just (Aeson.String "unknown"))

    it "removes the schema-6 key and keeps unrelated members at every level" $ do
      (fileField ".gitignore" "additiveOnly" . snd <$> upgraded) `shouldBe` Right Nothing
      (fileField "README.md" "futureKey" . snd <$> upgraded) `shouldBe` Right (Just (Aeson.String "survives"))
      (fileField ".gitignore" "applications" . snd <$> upgraded) `shouldBe` Right (Just (Aeson.toJSON ["a" :: String, "b"]))
      case snd <$> upgraded of
        Right (Aeson.Object top) -> KeyMap.lookup "producerOwned" top `shouldBe` Just (Aeson.object ["keep" Aeson..= True])
        other -> expectationFailure ("unexpected result: " <> show other)

    it "stamps version 7 and reports the one step it ran" $ do
      (documentSchemaVersion . snd =<< upgraded) `shouldBe` Right (v 7)
      (map (^. #fromVersion) . fst <$> upgraded) `shouldBe` Right [v 6]

    it "produces a document the typed decoder reads and round-trips" $
      case upgraded of
        Left err -> expectationFailure (show err)
        Right (_, document) -> case manifestFromJSON (Aeson.encode document) of
          Left err -> expectationFailure err
          Right manifest -> do
            (manifest ^. #version) `shouldBe` v 7
            fmap (^. #sharedWriteMode) (Map.lookup ".gitignore" (manifest ^. #files)) `shouldBe` Just SharedWriteAdditiveOnly
            fmap (^. #sharedWriteMode) (Map.lookup "README.md" (manifest ^. #files)) `shouldBe` Just SharedWriteUnknown
            manifestSupports TargetedAdditiveSharedPathUpdate manifest `shouldBe` True
            manifestFromJSON (manifestToJSON manifest) `shouldBe` Right manifest

    it "is a no-op from 7 to 7" $
      case upgraded of
        Left err -> expectationFailure (show err)
        Right (_, document) -> upgradeDocumentLosslessly (v 7) document `shouldBe` Right ([], document)

    it "rejects a malformed additiveOnly value" $ do
      let bad = Aeson.object ["version" Aeson..= (6 :: Int), "files" Aeson..= Aeson.object ["x" Aeson..= Aeson.object ["additiveOnly" Aeson..= ("yes" :: String)]]]
      case upgradeDocumentLosslessly (v 7) bad of
        Left (MalformedDocument source _) -> source `shouldBe` v 6
        other -> expectationFailure ("expected a malformed-document error, got " <> show other)

    it "refuses to run on a document at another version" $ do
      let sixToSeven = last manifestUpgradeSteps
          atFive = setDocumentSchemaVersion (v 5) schema6Document
      applyLosslessUpgradeStep sixToSeven atFive `shouldBe` Left (StepVersionMismatch sixToSeven (v 5))

  describe "lossless staging" $ do
    it "refuses to cross the inference-bearing 5 -> 6 conversion" $ do
      let atFive = setDocumentSchemaVersion (v 5) schema6Document
      case upgradeDocumentLosslessly (v 7) atFive of
        Left (StepRequiresInference s) -> (s ^. #fromVersion) `shouldBe` v 5
        other -> expectationFailure ("expected the path conversion to block, got " <> show other)

    it "names the explicit upgrade command when it refuses" $
      forM_ [s | s <- manifestUpgradeSteps, s ^. #fromVersion == v 5] $ \step5 ->
        renderManifestUpgradeError (StepRequiresInference step5) `shouldSatisfy` T.isInfixOf "seihou manifest upgrade"
