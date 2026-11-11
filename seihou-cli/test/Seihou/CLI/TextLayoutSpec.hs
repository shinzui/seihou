module Seihou.CLI.TextLayoutSpec (tests) where

import Data.Text qualified as T
import Seihou.CLI.TextLayout (truncateForSummary, wrapParagraphs)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.TextLayout" spec

spec :: Spec
spec = do
  describe "truncateForSummary" $ do
    it "keeps text that already fits" $
      truncateForSummary 20 "short text" `shouldBe` "short text"

    it "cuts long text to exactly the width, ending in an ellipsis" $ do
      let result = truncateForSummary 10 "abcdefghijklmnopqrstuvwxyz"
      result `shouldBe` "abcdefghi…"
      T.length result `shouldBe` 10

    it "collapses newlines and whitespace runs to single spaces" $
      truncateForSummary 40 "one\n  two\t\tthree\n\nfour" `shouldBe` "one two three four"

    it "strips a trailing space before the ellipsis" $
      truncateForSummary 7 "hello world" `shouldBe` "hello…"

  describe "wrapParagraphs" $ do
    let prose =
          "Claude skill for creating, implementing, and managing execution plans \
          \(ExecPlans) — self-contained design documents that guide implementation \
          \of features and system changes."

    it "never returns a line longer than the width" $ do
      let ls = wrapParagraphs 20 (T.replicate 30 "word and ")
      ls `shouldSatisfy` (not . null)
      ls `shouldSatisfy` all ((<= 20) . T.length)

    it "fills lines greedily word by word" $
      wrapParagraphs 72 prose
        `shouldBe` [ "Claude skill for creating, implementing, and managing execution plans",
                     "(ExecPlans) — self-contained design documents that guide implementation",
                     "of features and system changes."
                   ]

    it "keeps a word longer than the width whole, on its own line" $ do
      let url = "https://example.com/" <> T.replicate 40 "x"
      wrapParagraphs 20 ("see " <> url <> " now")
        `shouldBe` ["see", url, "now"]

    it "collapses whitespace inside a paragraph" $
      wrapParagraphs 40 "one\ntwo   three\n\tfour" `shouldBe` ["one two three four"]

    it "preserves a paragraph break as one empty line" $
      wrapParagraphs 40 "first paragraph\n\n\n  \nsecond paragraph"
        `shouldBe` ["first paragraph", "", "second paragraph"]

    it "returns no lines for blank input" $ do
      wrapParagraphs 40 "" `shouldBe` []
      wrapParagraphs 40 "  \n\t\n  " `shouldBe` []
