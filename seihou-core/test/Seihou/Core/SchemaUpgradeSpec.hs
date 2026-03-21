module Seihou.Core.SchemaUpgradeSpec (tests) where

import Data.Text qualified as T
import Seihou.Core.SchemaUpgrade
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.SchemaUpgrade" spec

-- | A module.dhall missing version, patch, and commands (pre-schema-evolution).
oldModuleText :: T.Text
oldModuleText =
  T.unlines
    [ "{ name = \"old-module\"",
      ", description = Some \"Pre-commands era module\"",
      ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
      ", exports = [] : List { var : Text, alias : Optional Text }",
      ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
      ", steps =",
      "  [ { strategy = \"copy\"",
      "    , src = \"foo\"",
      "    , dest = \"foo\"",
      "    , when = None Text",
      "    }",
      "  ]",
      ", dependencies = [] : List Text",
      "}"
    ]

-- | A module with bare string dependencies.
bareStringDepsText :: T.Text
bareStringDepsText =
  T.unlines
    [ "{ name = \"with-deps\"",
      ", version = None Text",
      ", description = Some \"Has bare string deps\"",
      ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
      ", exports = [] : List { var : Text, alias : Optional Text }",
      ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
      ", steps = [] : List { strategy : Text, src : Text, dest : Text, when : Optional Text, patch : Optional Text }",
      ", commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }",
      ", dependencies = [ \"haskell-base\", \"nix-flake\" ]",
      "}"
    ]

-- | A fully current module.
currentModuleText :: T.Text
currentModuleText =
  T.unlines
    [ "{ name = \"current-module\"",
      ", version = None Text",
      ", description = Some \"Fully current module\"",
      ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
      ", exports = [] : List { var : Text, alias : Optional Text }",
      ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
      ", steps =",
      "  [ { strategy = \"template\"",
      "    , src = \"foo.tpl\"",
      "    , dest = \"foo\"",
      "    , when = None Text",
      "    , patch = None Text",
      "    }",
      "  ]",
      ", commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }",
      ", dependencies = [] : List { module : Text, vars : List { name : Text, value : Text } }",
      "}"
    ]

-- | A module missing only version (has patch and commands).
missingVersionOnlyText :: T.Text
missingVersionOnlyText =
  T.unlines
    [ "{ name = \"no-version\"",
      ", description = Some \"Missing version only\"",
      ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
      ", exports = [] : List { var : Text, alias : Optional Text }",
      ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
      ", steps = [] : List { strategy : Text, src : Text, dest : Text, when : Optional Text, patch : Optional Text }",
      ", commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }",
      ", dependencies = [] : List { module : Text, vars : List { name : Text, value : Text } }",
      "}"
    ]

-- | A module with multiple steps, some missing patch.
multiStepText :: T.Text
multiStepText =
  T.unlines
    [ "{ name = \"multi-step\"",
      ", version = None Text",
      ", description = None Text",
      ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
      ", exports = [] : List { var : Text, alias : Optional Text }",
      ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
      ", steps =",
      "  [ { strategy = \"copy\"",
      "    , src = \"a\"",
      "    , dest = \"a\"",
      "    , when = None Text",
      "    }",
      "  , { strategy = \"template\"",
      "    , src = \"b.tpl\"",
      "    , dest = \"b\"",
      "    , when = None Text",
      "    , patch = None Text",
      "    }",
      "  , { strategy = \"copy\"",
      "    , src = \"c\"",
      "    , dest = \"c\"",
      "    , when = None Text",
      "    }",
      "  ]",
      ", commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }",
      ", dependencies = [] : List { module : Text, vars : List { name : Text, value : Text } }",
      "}"
    ]

spec :: Spec
spec = do
  describe "detectIssues" $ do
    it "detects all issues in an old module" $ do
      let issues = detectIssues oldModuleText
      issues `shouldContain` [MissingVersion]
      issues `shouldContain` [MissingCommands]
      issues `shouldContain` [MissingStepPatch 0]
      issues `shouldContain` [BareStringDepTypeAnnotation]

    it "returns empty list for a current module" $ do
      detectIssues currentModuleText `shouldBe` []

    it "detects only missing version when other fields present" $ do
      detectIssues missingVersionOnlyText `shouldBe` [MissingVersion]

    it "detects bare string dependencies" $ do
      let issues = detectIssues bareStringDepsText
      issues `shouldContain` [BareStringDep "haskell-base"]
      issues `shouldContain` [BareStringDep "nix-flake"]

    it "detects missing patch only on steps that lack it" $ do
      let issues = detectIssues multiStepText
      issues `shouldContain` [MissingStepPatch 0]
      issues `shouldContain` [MissingStepPatch 2]
      issues `shouldNotContain` [MissingStepPatch 1]

  describe "upgradeModuleText" $ do
    it "returns AlreadyCurrent for a current module" $ do
      upgradeModuleText currentModuleText `shouldBe` AlreadyCurrent

    it "inserts version field after name" $ do
      case upgradeModuleText missingVersionOnlyText of
        Upgraded text _ -> do
          T.isInfixOf ", version = None Text" text `shouldBe` True
          -- version should appear after name and before description
          let ls = T.lines text
              nameIdx = findIndex (T.isInfixOf "{ name =") ls
              versionIdx = findIndex (T.isInfixOf ", version =") ls
              descIdx = findIndex (T.isInfixOf ", description =") ls
          case (nameIdx, versionIdx, descIdx) of
            (Just n, Just v, Just d) -> do
              v `shouldBe` n + 1
              d `shouldSatisfy` (> v)
            _ -> expectationFailure "could not find expected fields"
        AlreadyCurrent -> expectationFailure "expected Upgraded"

    it "inserts commands field" $ do
      case upgradeModuleText oldModuleText of
        Upgraded text _ ->
          T.isInfixOf ", commands =" text `shouldBe` True
        AlreadyCurrent -> expectationFailure "expected Upgraded"

    it "inserts patch in steps that lack it" $ do
      case upgradeModuleText multiStepText of
        Upgraded text _ -> do
          -- Should have 3 occurrences of patch now (step 1 already had it)
          let patchCount = length (filter (T.isInfixOf ", patch =") (T.lines text))
          patchCount `shouldBe` 3
        AlreadyCurrent -> expectationFailure "expected Upgraded"

    it "converts bare string deps to record form" $ do
      case upgradeModuleText bareStringDepsText of
        Upgraded text _ -> do
          T.isInfixOf "{ module = \"haskell-base\"" text `shouldBe` True
          T.isInfixOf "{ module = \"nix-flake\"" text `shouldBe` True
          -- The old bare format "haskell-base", "nix-flake" should be gone
          T.isInfixOf "\"haskell-base\", \"nix-flake\"" text `shouldBe` False
        AlreadyCurrent -> expectationFailure "expected Upgraded"

    it "converts List Text annotation to record type" $ do
      case upgradeModuleText oldModuleText of
        Upgraded text _ -> do
          -- The dependencies line should no longer use "[] : List Text"
          T.isInfixOf "[] : List Text" text `shouldBe` False
          -- It should use the record type annotation instead
          T.isInfixOf "List { module : Text" text `shouldBe` True
        AlreadyCurrent -> expectationFailure "expected Upgraded"

    it "is idempotent" $ do
      case upgradeModuleText oldModuleText of
        Upgraded text _ ->
          upgradeModuleText text `shouldBe` AlreadyCurrent
        AlreadyCurrent -> expectationFailure "expected first upgrade to produce changes"

  describe "issueMessage" $ do
    it "produces human-readable messages" $ do
      issueMessage MissingVersion `shouldBe` "missing field: version"
      issueMessage (MissingStepPatch 0) `shouldBe` "missing field: patch (in step 1)"
      issueMessage MissingCommands `shouldBe` "missing field: commands"
      issueMessage (BareStringDep "foo") `shouldBe` "bare string dependency: foo"
  where
    findIndex p xs = go 0 xs
      where
        go _ [] = Nothing
        go i (x : rest')
          | p x = Just i
          | otherwise = go (i + 1) rest'
