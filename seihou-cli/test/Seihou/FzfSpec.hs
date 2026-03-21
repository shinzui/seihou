module Seihou.FzfSpec (tests) where

import Data.Text qualified as T
import Seihou.Core.Module (DiscoveredModule (..), ModuleSource (..))
import Seihou.Core.Types
import Seihou.Effect.Fzf (selectOne)
import Seihou.Effect.FzfInterp (runFzfPure)
import Seihou.Fzf
  ( Candidate (..),
    FzfOpts,
    FzfResult (..),
    optsToArgs,
    withAnsi,
    withHeader,
    withHeight,
    withNoSort,
    withPreview,
    withPrompt,
  )
import Seihou.Fzf.Selector.Module (formatModuleCandidate)
import Seihou.Prelude
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Fzf" spec

spec :: Spec
spec = do
  describe "optsToArgs" $ do
    it "produces empty args for mempty" $ do
      optsToArgs mempty `shouldBe` []

    it "produces --prompt flag" $ do
      optsToArgs (withPrompt "test> ") `shouldBe` ["--prompt", "test> "]

    it "produces --header flag" $ do
      optsToArgs (withHeader "Pick one") `shouldBe` ["--header", "Pick one"]

    it "produces --height flag" $ do
      optsToArgs (withHeight "40%") `shouldBe` ["--height", "40%"]

    it "produces --ansi flag" $ do
      optsToArgs withAnsi `shouldBe` ["--ansi"]

    it "produces --no-sort flag" $ do
      optsToArgs withNoSort `shouldBe` ["--no-sort"]

    it "produces --preview flag" $ do
      optsToArgs (withPreview "cat {}") `shouldBe` ["--preview", "cat {}"]

    it "combines options with <>" $ do
      let opts = withPrompt "p> " <> withHeight "50%" <> withAnsi
      optsToArgs opts `shouldBe` ["--prompt", "p> ", "--height", "50%", "--ansi"]

  describe "FzfOpts Monoid" $ do
    it "mempty is left identity" $ do
      let opts = withPrompt "test> "
      optsToArgs (mempty <> opts) `shouldBe` optsToArgs opts

    it "mempty is right identity" $ do
      let opts = withPrompt "test> "
      optsToArgs (opts <> mempty) `shouldBe` optsToArgs opts

    it "right-biases Maybe fields" $ do
      let a = withPrompt "first> "
          b = withPrompt "second> "
      optsToArgs (a <> b) `shouldBe` ["--prompt", "second> "]

    it "sticky-true for Bool fields" $ do
      let opts = withAnsi <> mempty
      optsToArgs opts `shouldBe` ["--ansi"]

  describe "runFzfPure" $ do
    it "selects candidate at given index" $ do
      let candidates =
            [ Candidate "alpha" ("a" :: Text),
              Candidate "beta" "b",
              Candidate "gamma" "c"
            ]
      result <- runEff $ runFzfPure 1 $ selectOne mempty candidates
      case result of
        FzfSelected val -> val `shouldBe` "b"
        _ -> expectationFailure "expected FzfSelected"

    it "returns FzfNoMatch for negative index" $ do
      let candidates = [Candidate "alpha" ("a" :: Text)]
      result <- runEff $ runFzfPure (-1) $ selectOne mempty candidates
      case result of
        FzfNoMatch -> pure ()
        _ -> expectationFailure "expected FzfNoMatch"

    it "returns FzfNoMatch for out-of-bounds index" $ do
      let candidates = [Candidate "alpha" ("a" :: Text)]
      result <- runEff $ runFzfPure 5 $ selectOne mempty candidates
      case result of
        FzfNoMatch -> pure ()
        _ -> expectationFailure "expected FzfNoMatch"

    it "returns FzfNoMatch for empty candidates" $ do
      result <- runEff $ runFzfPure 0 $ selectOne mempty ([] :: [Candidate Text])
      case result of
        FzfNoMatch -> pure ()
        _ -> expectationFailure "expected FzfNoMatch"

  describe "formatModuleCandidate" $ do
    it "returns Just for a valid module" $ do
      let dm = validModule "test-mod" "A test module" SourceUser
      case formatModuleCandidate dm of
        Just c -> do
          c.candidateValue `shouldBe` ModuleName "test-mod"
          T.isInfixOf "test-mod" c.candidateDisplay `shouldBe` True
          T.isInfixOf "[user]" c.candidateDisplay `shouldBe` True
        Nothing -> expectationFailure "expected Just"

    it "returns Nothing for a failed module" $ do
      let dm =
            DiscoveredModule
              { discoveredResult = Left (ModuleNotFound (ModuleName "bad") []),
                discoveredSource = SourceProject,
                discoveredDir = "/tmp/bad"
              }
      case formatModuleCandidate dm of
        Nothing -> pure ()
        Just _ -> expectationFailure "expected Nothing"

    it "includes description when present" $ do
      let dm = validModule "mod" "My description" SourceInstalled
      case formatModuleCandidate dm of
        Just c -> T.isInfixOf "My description" c.candidateDisplay `shouldBe` True
        Nothing -> expectationFailure "expected Just"

    it "tags source correctly" $ do
      let dmProject = validModule "m" "d" SourceProject
          dmUser = validModule "m" "d" SourceUser
          dmInstalled = validModule "m" "d" SourceInstalled
      case (formatModuleCandidate dmProject, formatModuleCandidate dmUser, formatModuleCandidate dmInstalled) of
        (Just p, Just u, Just i) -> do
          T.isInfixOf "[project]" p.candidateDisplay `shouldBe` True
          T.isInfixOf "[user]" u.candidateDisplay `shouldBe` True
          T.isInfixOf "[installed]" i.candidateDisplay `shouldBe` True
        _ -> expectationFailure "expected all Just"

-- | Helper to create a valid discovered module for testing.
validModule :: String -> String -> ModuleSource -> DiscoveredModule
validModule name desc src =
  DiscoveredModule
    { discoveredResult =
        Right
          Module
            { name = ModuleName (T.pack name),
              version = Nothing,
              description = Just (T.pack desc),
              vars = [],
              exports = [],
              prompts = [],
              steps = [],
              commands = [],
              dependencies = [],
              removal = Nothing
            },
      discoveredSource = src,
      discoveredDir = "/tmp/" ++ name
    }
