module Seihou.CLI.DiffSpec (tests) where

import Data.Text qualified as T
import Seihou.CLI.Diff (formatDiffOutput)
import Seihou.Core.Types (ModuleName (..), TrackedFile (..), TrackedFileStatus (..))
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.Diff" spec

spec :: Spec
spec = do
  describe "formatDiffOutput" $ do
    it "shows no-changes message when all files unchanged" $ do
      let tracked =
            [ TrackedFile "README.md" (ModuleName "haskell-base") TfsUnchanged,
              TrackedFile "src/Lib.hs" (ModuleName "haskell-base") TfsUnchanged
            ]
          result = formatDiffOutput False tracked
      result `shouldBe` "No changes since last generation.\n"

    it "includes header line" $ do
      let tracked =
            [ TrackedFile "src/Lib.hs" (ModuleName "haskell-base") TfsModified
            ]
          result = formatDiffOutput False tracked
      T.isInfixOf "Seihou Diff:" result `shouldBe` True

    it "shows modified files" $ do
      let tracked =
            [ TrackedFile "src/Lib.hs" (ModuleName "haskell-base") TfsModified
            ]
          result = formatDiffOutput False tracked
      T.isInfixOf "modified" result `shouldBe` True
      T.isInfixOf "src/Lib.hs" result `shouldBe` True

    it "shows deleted files" $ do
      let tracked =
            [ TrackedFile "app/Main.hs" (ModuleName "haskell-base") TfsDeleted
            ]
          result = formatDiffOutput False tracked
      T.isInfixOf "deleted" result `shouldBe` True
      T.isInfixOf "app/Main.hs" result `shouldBe` True

    it "shows summary count line" $ do
      let tracked =
            [ TrackedFile "README.md" (ModuleName "haskell-base") TfsUnchanged,
              TrackedFile "src/Lib.hs" (ModuleName "haskell-base") TfsModified,
              TrackedFile "app/Main.hs" (ModuleName "haskell-base") TfsDeleted
            ]
          result = formatDiffOutput False tracked
      T.isInfixOf "1 unchanged, 1 modified, 1 deleted" result `shouldBe` True

    it "shows module attribution in parentheses" $ do
      let tracked =
            [ TrackedFile "src/Lib.hs" (ModuleName "haskell-base") TfsModified
            ]
          result = formatDiffOutput False tracked
      T.isInfixOf "(haskell-base)" result `shouldBe` True

    it "hides unchanged files from main listing" $ do
      let tracked =
            [ TrackedFile "README.md" (ModuleName "haskell-base") TfsUnchanged,
              TrackedFile "src/Lib.hs" (ModuleName "haskell-base") TfsModified
            ]
          result = formatDiffOutput False tracked
          bodyLines = filter (T.isInfixOf "README.md") (T.lines result)
      bodyLines `shouldBe` []
