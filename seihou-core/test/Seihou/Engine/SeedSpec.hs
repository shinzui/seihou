module Seihou.Engine.SeedSpec (tests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.Either (isLeft)
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text.IO qualified as TIO
import Data.Time (UTCTime (..), fromGregorian)
import Effectful (runPureEff)
import Seihou.Core.Types
import Seihou.Effect.Filesystem
import Seihou.Effect.FilesystemInterp (createFileExclusiveWith, runFilesystem)
import Seihou.Effect.FilesystemPure
import Seihou.Engine.Seed
import Seihou.Manifest.Types (emptyManifest)
import Seihou.Prelude
import System.Directory qualified as D
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "seed planning and exclusive creation" $ do
  let now = UTCTime (fromGregorian 2026 10 26) 0
      receipt = SeedRecord "supplier" (KnownSeedOwners (Map.singleton (ApplicationId "a") (Set.singleton "supplier"))) SeedCreated now
      managed = FileRecord (SHA256 "hash") "supplier" Copy now Nothing Set.empty SharedWriteUnknown
      operation = SeedFileOp "nested/start.txt" "starter\n" Copy "supplier"
      claims = Map.singleton "nested/start.txt" (Set.fromList ["supplier", "second"])
  it "uses one decision tree for every observed entry and lifecycle" $ do
    classifySeed Nothing Nothing EntryMissing `shouldBe` Right SeedWrite
    classifySeed Nothing Nothing EntryFile `shouldBe` Right SeedKeepExisting
    forM_ [EntryDirectory, EntrySymlink "missing"] $ \entry -> classifySeed Nothing Nothing entry `shouldSatisfy` isLeft
    forM_ [EntryMissing, EntryFile, EntryDirectory, EntrySymlink "missing"] $ \entry -> do
      classifySeed (Just receipt) Nothing entry `shouldBe` Right (if entry == EntryMissing then SeedRespectDeletion else SeedAlreadySettled)
      classifySeed Nothing (Just managed) entry `shouldBe` Right SeedReleaseManaged
  it "uses an explicit root, records every claimant, and never hashes a seed" $ do
    let ((planned, created), fs) = runPureEff $ runFilesystemPure emptyFS $ do
          result <- planSeeds "/project" (emptyManifest now) claims [operation]
          let Right planned = result
          created <- executeSeeds "/project" (ApplicationId "a") now planned (emptyManifest now)
          pure (planned, created)
    map (^. #supplier) planned `shouldBe` ["supplier"]
    fs ^. #files `shouldBe` Map.singleton "/project/nested/start.txt" "starter\n"
    fmap (fmap (^. #ownership)) created `shouldBe` Right (Map.singleton "nested/start.txt" (KnownSeedOwners (Map.singleton (ApplicationId "a") (Set.fromList ["supplier", "second"]))))
  it "does not read, repair, or create parents for a settled deleted seed" $ do
    let manifest = emptyManifest now & #seeds .~ Map.singleton "nested/start.txt" receipt
        ((planned, result), fs) = runPureEff $ runFilesystemPure emptyFS $ do
          result <- planSeeds "/project" manifest claims [operation]
          let Right planned = result
          executed <- executeSeeds "/project" (ApplicationId "a") now planned manifest
          pure (planned, executed)
    map (^. #decision) planned `shouldBe` [SeedRespectDeletion]
    result `shouldSatisfy` either (const False) (const True)
    fs `shouldBe` emptyFS
  it "refuses lifecycle transitions even when managed content is missing" $ do
    validateSeedRun (emptyManifest now & #files .~ Map.singleton "nested/start.txt" managed) [operation] `shouldSatisfy` isLeft
    validateSeedRun (emptyManifest now & #seeds .~ Map.singleton "nested/start.txt" receipt) [WriteFileOp "nested/start.txt" "replacement" Copy] `shouldSatisfy` isLeft
  it "publishes complete bytes once and cannot replace files, directories or dangling links" $
    withSystemTempDirectory "seed-exclusive" $ \root -> do
      runEff (runFilesystem (createFileExclusive (root </> "file") "complete\n")) `shouldReturn` ExclusiveCreated
      runEff (runFilesystem (createFileExclusive (root </> "file") "replacement\n")) `shouldReturn` ExclusiveOccupied
      TIO.readFile (root </> "file") `shouldReturn` "complete\n"
      D.createDirectory (root </> "dir")
      D.createFileLink "missing" (root </> "link")
      forM_ ["dir", "link"] $ \path -> runEff (runFilesystem (createFileExclusive (root </> path) "replacement")) `shouldReturn` ExclusiveOccupied
      D.getSymbolicLinkTarget (root </> "link") `shouldReturn` "missing"
  it "cleans a failed partial private write without exposing a destination" $
    withSystemTempDirectory "seed-partial" $ \root -> do
      let failWriting handle = BS.hPut handle "partial" >> ioError (userError "injected write failure")
      result <- createFileExclusiveWith failWriting (root </> "seed")
      result `shouldSatisfy` (\case ExclusiveFailure _ -> True; _ -> False)
      D.listDirectory root `shouldReturn` []
  it "keeps a file appearing after preview and refuses a newly appearing link" $
    withSystemTempDirectory "seed-race" $ \root -> do
      Right planned <- runEff $ runFilesystem $ planSeeds root (emptyManifest now) claims [operation]
      D.createDirectory (root </> "nested")
      TIO.writeFile (root </> "nested/start.txt") "concurrent owner\n"
      Right actual <- runEff $ runFilesystem $ executeSeeds root (ApplicationId "a") now planned (emptyManifest now)
      fmap (^. #outcome) (Map.lookup "nested/start.txt" actual) `shouldBe` Just SeedFoundExisting
      TIO.readFile (root </> "nested/start.txt") `shouldReturn` "concurrent owner\n"
      D.removeFile (root </> "nested/start.txt")
      D.createFileLink "missing" (root </> "nested/start.txt")
      runEff (runFilesystem (executeSeeds root (ApplicationId "a") now planned (emptyManifest now))) >>= (`shouldSatisfy` isLeft)
  it "does not traverse a symlink parent" $
    withSystemTempDirectory "seed-parent" $ \root -> do
      D.createDirectory (root </> "elsewhere")
      D.createDirectoryLink "elsewhere" (root </> "nested")
      runEff (runFilesystem (planSeeds root (emptyManifest now) claims [operation])) >>= (`shouldSatisfy` isLeft)
      D.listDirectory (root </> "elsewhere") `shouldReturn` []
