module Seihou.CLI.InstallHistorySpec (tests) where

import Data.Text qualified as T
import Seihou.CLI.InstallHistory
  ( HistoryEntry (..),
    InstallHistory (..),
    maxHistoryEntries,
    readHistoryFrom,
    recordUrlTo,
    writeHistoryTo,
  )
import System.Directory (doesFileExist)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.InstallHistory" spec

spec :: Spec
spec = do
  describe "readHistoryFrom" $ do
    it "returns empty history when file does not exist" $ do
      withSystemTempDirectory "history-test" $ \tmp -> do
        h <- readHistoryFrom (tmp </> "nonexistent.json")
        h.entries `shouldBe` []

    it "returns empty history for malformed JSON" $ do
      withSystemTempDirectory "history-test" $ \tmp -> do
        let path = tmp </> "bad.json"
        writeFile path "not json"
        h <- readHistoryFrom path
        h.entries `shouldBe` []

  describe "writeHistoryTo / readHistoryFrom round-trip" $ do
    it "round-trips an empty history" $ do
      withSystemTempDirectory "history-test" $ \tmp -> do
        let path = tmp </> "history.json"
            original = InstallHistory []
        writeHistoryTo path original
        result <- readHistoryFrom path
        result `shouldBe` original

    it "round-trips a history with entries" $ do
      withSystemTempDirectory "history-test" $ \tmp -> do
        let path = tmp </> "history.json"
            original =
              InstallHistory
                [ HistoryEntry "https://github.com/a/b.git" "2026-01-01T00:00:00Z",
                  HistoryEntry "https://github.com/c/d.git" "2025-12-01T00:00:00Z"
                ]
        writeHistoryTo path original
        result <- readHistoryFrom path
        result `shouldBe` original

  describe "recordUrlTo" $ do
    it "creates a history file when none exists" $ do
      withSystemTempDirectory "history-test" $ \tmp -> do
        let path = tmp </> "history.json"
        recordUrlTo path "https://github.com/foo/bar.git"
        exists <- doesFileExist path
        exists `shouldBe` True
        h <- readHistoryFrom path
        length h.entries `shouldBe` 1
        (head h.entries).url `shouldBe` "https://github.com/foo/bar.git"

    it "deduplicates by URL, keeping most recent first" $ do
      withSystemTempDirectory "history-test" $ \tmp -> do
        let path = tmp </> "history.json"
        recordUrlTo path "https://github.com/a/first.git"
        recordUrlTo path "https://github.com/b/second.git"
        recordUrlTo path "https://github.com/a/first.git"
        h <- readHistoryFrom path
        length h.entries `shouldBe` 2
        (head h.entries).url `shouldBe` "https://github.com/a/first.git"

    it "caps history at maxHistoryEntries" $ do
      withSystemTempDirectory "history-test" $ \tmp -> do
        let path = tmp </> "history.json"
        mapM_
          (\i -> recordUrlTo path ("https://example.com/repo-" <> T.pack (show i) <> ".git"))
          [1 .. maxHistoryEntries + 5 :: Int]
        h <- readHistoryFrom path
        length h.entries `shouldBe` maxHistoryEntries
