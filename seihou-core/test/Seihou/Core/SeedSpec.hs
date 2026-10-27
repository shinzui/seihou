module Seihou.Core.SeedSpec (tests) where

import Control.Monad (forM_)
import Data.Either (isLeft)
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (UTCTime (..), fromGregorian)
import Seihou.Core.Module (checkSeedSteps)
import Seihou.Core.Seed
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalModuleFromFile)
import Seihou.Manifest.Types
import Seihou.Prelude
import System.Directory (getCurrentDirectory)
import System.FilePath (takeDirectory)
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "seed foundations" $ do
  let now = UTCTime (fromGregorian 2026 10 15) 0
      a = ApplicationId "a"
      b = ApplicationId "b"
      claims app names = KnownSeedOwners (Map.singleton app (Set.fromList names))
      first = SeedRecord "demo" (LegacySeedOwners (Set.singleton a)) SeedCreated now
      second = SeedRecord "demo" (LegacySeedOwners (Set.singleton b)) SeedFoundExisting now
      Right manifest = mergeSeedRecord "CHANGELOG.md" first (emptyManifest now) >>= mergeSeedRecord "CHANGELOG.md" second
      application app =
        AppliedComposition
          app
          (AppliedModuleTarget "demo")
          (LocalOrigin "demo")
          Nothing
          []
          Nothing
          Nothing
          [AppliedInstanceState name emptyParentVars (LocalOrigin (name ^. #unModuleName)) Nothing Map.empty | name <- ["demo", "second"]]
          Map.empty
          []
          now
      exact = first & #ownership .~ claims a ["demo", "second"]
      known = emptyManifest now & #applications .~ map application [a, b] & #seeds .~ Map.singleton "CHANGELOG.md" exact
  it "preserves the first settlement while merging legacy owners" $ do
    let Just receipt = Map.lookup "CHANGELOG.md" (manifest ^. #seeds)
    receipt ^. #outcome `shouldBe` SeedCreated
    seedApplicationIds receipt `shouldBe` Set.fromList [a, b]
  it "removes the supplier without erasing a second seeder in the application" $ do
    Right one <- pure (dropSeedOwners (Map.singleton a (Set.singleton "demo")) "CHANGELOG.md" known)
    let Just receipt = Map.lookup "CHANGELOG.md" (one ^. #seeds)
    receipt ^. #ownership `shouldBe` claims a ["second"]
    receipt ^. #moduleName `shouldBe` "demo"
    Right lastGone <- pure (dropSeedOwners (Map.singleton a (Set.singleton "second")) "CHANGELOG.md" one)
    lastGone ^. #seeds `shouldBe` Map.empty
  it "unions exact claims idempotently and associatively across applications" $ do
    let receipt = second & #ownership .~ claims b ["demo"]
    Right merged <- pure (mergeSeedRecord "CHANGELOG.md" receipt known)
    mergeSeedRecord "CHANGELOG.md" exact merged `shouldBe` Right merged
    mergeSeedRecord "CHANGELOG.md" receipt merged `shouldBe` Right merged
    Right reverseMerged <- pure (mergeSeedRecord "CHANGELOG.md" exact (known & #seeds .~ Map.singleton "CHANGELOG.md" receipt))
    fmap (^. #ownership) (Map.lookup "CHANGELOG.md" (merged ^. #seeds)) `shouldBe` fmap (^. #ownership) (Map.lookup "CHANGELOG.md" (reverseMerged ^. #seeds))
    validateManifestInvariants merged `shouldBe` Right ()
  it "replaces selected claims without resetting settlement or losing unrelated owners" $ do
    Right shared <- pure (mergeSeedRecord "CHANGELOG.md" (second & #ownership .~ claims b ["demo"]) known)
    let candidate = second & #ownership .~ claims a ["second"] & #moduleName .~ "second"
    Right replaced <- pure (replaceSelectedSeedClaims (Set.singleton a) (Map.singleton "CHANGELOG.md" candidate) shared)
    let Just receipt = Map.lookup "CHANGELOG.md" (replaced ^. #seeds)
    receipt ^. #moduleName `shouldBe` "demo"
    receipt ^. #outcome `shouldBe` SeedCreated
    receipt ^. #ownership `shouldBe` KnownSeedOwners (Map.fromList [(a, Set.singleton "second"), (b, Set.singleton "demo")])
    Right retired <- pure (replaceSelectedSeedClaims (Set.singleton a) Map.empty replaced)
    fmap (^. #ownership) (Map.lookup "CHANGELOG.md" (retired ^. #seeds)) `shouldBe` Just (claims b ["demo"])
    replaceSelectedSeedClaims (Set.singleton a) (Map.singleton "CHANGELOG.md" (second & #ownership .~ claims b ["demo"])) known `shouldSatisfy` isLeft
  it "never subtracts unresolved legacy claims or mixes exact and unknown facts" $ do
    dropSeedOwners (Map.singleton a (Set.singleton "demo")) "CHANGELOG.md" manifest `shouldSatisfy` isLeft
    mergeSeedRecord "CHANGELOG.md" exact manifest `shouldSatisfy` isLeft
    replaceSelectedSeedClaims (Set.singleton a) Map.empty manifest `shouldSatisfy` isLeft
    replaceSelectedSeedClaims (Set.singleton (ApplicationId "unrelated")) Map.empty manifest `shouldBe` Right manifest
  it "round trips known claims and reports downgrade loss" $ do
    manifestFromJSON (manifestToJSON known) `shouldBe` Right known
    manifestEncodingLoss (known & #version .~ ManifestSchemaVersion 10) `shouldContain` ["seed owner claims require manifest schema 11"]
  it "validates exact paths and owner references" $ do
    forM_ ["../escape", "/absolute", "./alias", "a//b", ".seihou/private"] $ \path ->
      validateManifestInvariants (known & #seeds .~ Map.singleton path exact) `shouldSatisfy` isLeft
    forM_ [KnownSeedOwners Map.empty, claims a [], claims (ApplicationId "missing") ["demo"], claims a ["missing"]] $ \owners ->
      validateManifestInvariants (known & #seeds .~ Map.singleton "a" (exact & #ownership .~ owners)) `shouldSatisfy` isLeft
    let file = FileRecord (SHA256 "hash") "demo" Copy now Nothing Set.empty SharedWriteUnknown
    validateManifestInvariants (known & #files .~ Map.singleton "CHANGELOG.md/child" file) `shouldSatisfy` isLeft
  it "round trips receipts without hashes or baselines" $ do
    manifestFromJSON (manifestToJSON manifest) `shouldBe` Right manifest
  it "rejects a managed/seed collision at decoding" $ do
    let file = FileRecord (SHA256 "hash") "demo" Copy now Nothing Set.empty SharedWriteUnknown
        invalid = manifest & #files .~ Map.singleton "CHANGELOG.md" file
    validateManifestInvariants invalid `shouldBe` Left (PathBothManagedAndSeeded "CHANGELOG.md")
    manifestFromJSON (manifestToJSON invalid) `shouldSatisfy` isLeft
  it "keeps schema 7 unchanged and diagnoses seed information loss" $ do
    let old = emptyManifest now & #version .~ ManifestSchemaVersion 7
    manifestFromJSON (manifestToJSON old) `shouldBe` Right old
  it "reports facts an older schema cannot encode" $ do
    manifestEncodingLoss (manifest & #version .~ ManifestSchemaVersion 7) `shouldSatisfy` (not . null)
  it "decodes omitted lifecycle and rejects invalid lifecycle values" $
    withSystemTempDirectory "lifecycle" $ \dir -> do
      cwd <- getCurrentDirectory
      let schema = takeDirectory cwd </> "schema/package.dhall"
          source field =
            T.unlines
              [ "let S = " <> T.pack schema,
                "in S.Module::{ name = \"demo\", version = Some \"1.0\" } // { steps = [S.Step::{ strategy = \"template\", src = \"a\", dest = \"b\" }" <> (if T.null field then "" else " // { " <> T.drop 2 field <> " }") <> "] }"
              ]
      TIO.writeFile (dir </> "module.dhall") (source "")
      Right old <- evalModuleFromFile (dir </> "module.dhall")
      map (^. #lifecycle) (old ^. #steps) `shouldBe` [Managed]
      TIO.writeFile (dir </> "module.dhall") (source ", lifecycle = Some \"seed\"")
      Right seed <- evalModuleFromFile (dir </> "module.dhall")
      checkSeedSteps seed `shouldBe` []
      let patched = seed & #steps %~ map (#patch ?~ AppendFile)
      checkSeedSteps patched `shouldSatisfy` (not . null)
      checkSeedSteps (seed & #steps %~ map (#strategy .~ Structured)) `shouldSatisfy` (not . null)
      checkSeedSteps (seed & #steps %~ (<> map (#lifecycle .~ Managed) (seed ^. #steps))) `shouldSatisfy` (not . null)
      checkSeedSteps (seed & #removal ?~ Removal [RemovalStep RemoveFileAction "b" Nothing] []) `shouldSatisfy` (not . null)
      TIO.writeFile (dir </> "module.dhall") (source ", lifecycle = Some \"sede\"")
      invalid <- evalModuleFromFile (dir </> "module.dhall")
      invalid `shouldSatisfy` isLeft
