module Seihou.CLI.InitSpec (tests) where

import Data.Text qualified as T
import Seihou.CLI.Init (formatInitOutput)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.Init" spec

spec :: Spec
spec = do
  describe "formatInitOutput" $ do
    it "includes header with base path" $ do
      let result = formatInitOutput "~/.config/seihou" []
      T.isInfixOf "Initialized Seihou configuration at ~/.config/seihou/" result
        `shouldBe` True

    it "shows Created: for newly created items" $ do
      let items = [("config.dhall", "global defaults", True)]
          result = formatInitOutput "~/.config/seihou" items
      T.isInfixOf "Created: config.dhall (global defaults)" result
        `shouldBe` True

    it "shows Exists: for already existing items" $ do
      let items = [("config.dhall", "global defaults", False)]
          result = formatInitOutput "~/.config/seihou" items
      T.isInfixOf "Exists:  config.dhall (global defaults)" result
        `shouldBe` True

    it "formats all three spec items correctly when all created" $ do
      let items =
            [ ("config.dhall", "global defaults", True),
              ("modules/", "user modules", True),
              ("installed/", "git-installed modules", True)
            ]
          result = formatInitOutput "~/.config/seihou" items
          resultLines = T.lines result
      length resultLines `shouldBe` 4
      (resultLines !! 0) `shouldBe` "Initialized Seihou configuration at ~/.config/seihou/"
      (resultLines !! 1) `shouldBe` "  Created: config.dhall (global defaults)"
      (resultLines !! 2) `shouldBe` "  Created: modules/ (user modules)"
      (resultLines !! 3) `shouldBe` "  Created: installed/ (git-installed modules)"

    it "formats mixed created and existing items" $ do
      let items =
            [ ("config.dhall", "global defaults", False),
              ("modules/", "user modules", True),
              ("installed/", "git-installed modules", False)
            ]
          result = formatInitOutput "~/.config/seihou" items
          resultLines = T.lines result
      (resultLines !! 1) `shouldBe` "  Exists:  config.dhall (global defaults)"
      (resultLines !! 2) `shouldBe` "  Created: modules/ (user modules)"
      (resultLines !! 3) `shouldBe` "  Exists:  installed/ (git-installed modules)"

    it "uses two-space indentation for items" $ do
      let items = [("test.txt", "test file", True)]
          result = formatInitOutput "~/path" items
          resultLines = T.lines result
      T.isPrefixOf "  " (resultLines !! 1) `shouldBe` True
