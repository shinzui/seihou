module Seihou.Core.SeedSpec (tests) where

import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Time (UTCTime (..), fromGregorian)
import Seihou.Core.Module (checkSeedSteps)
import Seihou.Core.Seed
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalModuleFromFile)
import Seihou.Manifest.Types
import Seihou.Prelude
import Data.Either (isLeft)
import System.Directory (getCurrentDirectory)
import System.FilePath (takeDirectory)
import System.IO.Temp (withSystemTempDirectory)
import Data.Text.IO qualified as TIO
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "seed foundations" $ do
  let now = UTCTime (fromGregorian 2026 10 15) 0
      first = SeedRecord "demo" (Set.singleton (ApplicationId "a")) SeedCreated now
      second = SeedRecord "demo" (Set.singleton (ApplicationId "b")) SeedFoundExisting now
      manifest = mergeSeedRecord "CHANGELOG.md" second (mergeSeedRecord "CHANGELOG.md" first (emptyManifest now))
  it "preserves the first settlement while merging owners" $ do
    let Just receipt = Map.lookup "CHANGELOG.md" (manifest ^. #seeds)
    receipt ^. #outcome `shouldBe` SeedCreated
    receipt ^. #applicationIds `shouldBe` Set.fromList [ApplicationId "a", ApplicationId "b"]
  it "releases only selected owners and drops the last claim" $ do
    let one = dropSeedOwner (Set.singleton (ApplicationId "a")) "CHANGELOG.md" manifest
    Map.size (one ^. #seeds) `shouldBe` 1
    Map.null (dropSeedOwner (Set.singleton (ApplicationId "b")) "CHANGELOG.md" one ^. #seeds) `shouldBe` True
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
          source field = T.unlines
            [ "let S = " <> T.pack schema,
              "in S.Module::{ name = \"demo\", version = Some \"1.0\", steps = [S.Step::{ strategy = \"template\", src = \"a\", dest = \"b\"" <> field <> " }] }" ]
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
