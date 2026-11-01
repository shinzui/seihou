module Seihou.Composition.RecipeSpec (tests) where

import Control.Lens ((&), (.~), (^.))
import Data.Either (isLeft)
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Seihou.Composition.Recipe
import Seihou.Composition.RecipeChain (loadRecipeChain)
import Seihou.Core.Recipe (validateRecipe)
import Seihou.Core.Types
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Composition.Recipe" spec

expectExpanded :: Recipe -> (ModuleName, [ModuleName], Map.Map VarName Text, [VarDecl], [Prompt], [Dependency])
expectExpanded recipe =
  case expandRecipe recipe of
    Right expanded -> expanded
    Left errs -> error ("expected recipe expansion, got errors: " <> show errs)

spec :: Spec
spec = do
  describe "loadRecipeChain" $ do
    it "reports indirect base cycles before looking up members" $ do
      withSystemTempDirectory "recipe-chain-cycle" $ \dir -> do
        let child = derived "child" "base"
        createDirectoryIfMissing True (dir </> "base")
        writeFile
          (dir </> "base" </> "recipe.dhall")
          "{ name = \"base\", version = None Text, description = None Text, modules = [] : List Text, vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }, prompts = [] : List {var : Text, text : Text, when : Optional Text, choices : Optional (List Text)}, extends = Some {recipe = \"child\"} }"
        writeChildDescriptor dir
        result <- loadRecipeChain dir [dir] child (dir </> "child")
        case result of
          Left (ValidationError _ messages) -> T.unwords messages `shouldSatisfy` T.isInfixOf "child -> base -> child"
          other -> expectationFailure (show other)

    it "rejects an explicit source with unknown local provenance" $ do
      withSystemTempDirectory "recipe-chain-origin" $ \dir -> do
        let child = derived "child" "base" & #extends .~ Just (RecipeReference "base" (Just "https://example.com/registry") Nothing)
        createDirectoryIfMissing True (dir </> "base")
        writeFile
          (dir </> "base" </> "recipe.dhall")
          "{ name = \"base\", version = None Text, description = None Text, modules = [\"one\"], vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }, prompts = [] : List {var : Text, text : Text, when : Optional Text, choices : Optional (List Text)} }"
        result <- loadRecipeChain dir [dir] child (dir </> "child")
        case result of
          Left (ValidationError _ messages) -> T.unwords messages `shouldSatisfy` T.isInfixOf "different or unknown"
          other -> expectationFailure (show other)

  describe "mergeRecipeChain" $ do
    it "keeps oldest primary, deduplicates members, and preserves override attribution across three layers" $ do
      let base = flat "base" [bound "one" "old", bound "two" "old"]
          child = derived "child" "base" & #moduleOverrides .~ [RecipeModuleOverride "one" (Map.singleton "x" "new")]
          grandchild = derived "grandchild" "child"
      case mergeRecipeChain (map node [base, child, grandchild]) of
        Left errs -> expectationFailure (show errs)
        Right expanded -> do
          expanded ^. #primary `shouldBe` "one"
          map (^. #dependency . #module_) (expanded ^. #members) `shouldBe` ["one", "two"]
          fmap (^. #value) (Map.lookup "x" (expanded ^. #literals)) `shouldBe` Just "new"
          fmap (^. #recipe) (Map.lookup "x" (expanded ^. #literals)) `shouldBe` Just "child"

    it "rejects unequal same-layer literals across additions and overrides" $ do
      let base = flat "base" [bound "one" "old"]
          child =
            derived "child" "base"
              & #modules .~ [bound "two" "different"]
              & #moduleOverrides .~ [RecipeModuleOverride "one" (Map.singleton "x" "new")]
      mergeRecipeChain (map node [base, child]) `shouldSatisfy` isLeft

    it "retains a literal when a child supplies only a declaration default" $ do
      let decl = VarDecl "x" VTText Nothing Nothing False Nothing
          base = flat "base" [bound "one" "literal"] & #vars .~ [decl]
          child = derived "child" "base" & #vars .~ [decl & #default_ .~ Just (VText "default")]
      case mergeRecipeChain (map node [base, child]) of
        Left errs -> expectationFailure (show errs)
        Right expanded -> fmap (^. #value) (Map.lookup "x" (expanded ^. #literals)) `shouldBe` Just "literal"

    it "rejects constraint changes and preserves explicitly empty descriptions" $ do
      let decl = VarDecl "x" VTText Nothing (Just "parent") False Nothing
          base = flat "base" [simpleDep "one"] & #vars .~ [decl]
          child = derived "child" "base" & #vars .~ [decl & #description .~ Just ""]
      fmap (^. #declarations) (mergeRecipeChain (map node [base, child])) `shouldBe` Right [decl & #description .~ Just ""]
      mergeRecipeChain (map node [base, child & #vars .~ [decl & #required .~ True]]) `shouldSatisfy` isLeft

    it "replaces inherited prompts in place and resolves inherited declarations" $ do
      let decl = VarDecl "x" VTText Nothing Nothing False Nothing
          question = Prompt "x" "Old?" Nothing Nothing
          replacement = question & #text .~ "New?"
          base = flat "base" [simpleDep "one"] & #vars .~ [decl] & #prompts .~ [question]
          child = derived "child" "base" & #promptOverrides .~ [replacement]
      fmap (^. #prompts) (mergeRecipeChain (map node [base, child])) `shouldBe` Right [replacement]
      mergeRecipeChain (map node [base, child & #promptOverrides .~ [] & #prompts .~ [replacement]]) `shouldSatisfy` isLeft

    it "rejects a repeated member from another origin" $ do
      let base = flat "base" [simpleDep "one"]
          child = derived "child" "base" & #modules .~ [simpleDep "one"]
          childNode = node child & #members .~ [m & #memberOrigin .~ RemoteOrigin "https://other.example/repo" "one" Nothing | m <- node child ^. #members]
      mergeRecipeChain [node base, childNode] `shouldSatisfy` isLeft

    it "deduplicates compatible repeated members and rejects missing override targets" $ do
      let base = flat "base" [simpleDep "one"]
          child = derived "child" "base" & #modules .~ [simpleDep "one"]
      fmap (length . (^. #members)) (mergeRecipeChain (map node [base, child])) `shouldBe` Right 1
      mergeRecipeChain (map node [base, derived "child" "base" & #moduleOverrides .~ [RecipeModuleOverride "missing" mempty]]) `shouldSatisfy` isLeft

    it "enforces exclusive upper bounds and trailing-zero version equivalence" $ do
      let base = flat "base" [simpleDep "one"] & #version .~ Just "1.0.0"
          child = derived "child" "base" & #extends .~ Just (RecipeReference "base" Nothing (Just (RecipeVersionRange "1" "2")))
      mergeRecipeChain (map node [base, child]) `shouldSatisfy` either (const False) (const True)
      mergeRecipeChain (map node [base & #version .~ Just "2", child]) `shouldSatisfy` isLeft
      mergeRecipeChain (map node [base & #version .~ Nothing, child]) `shouldSatisfy` isLeft

    it "does not silently expand an unresolved base through the legacy API" $ do
      expandRecipe (derived "child" "base") `shouldSatisfy` isLeft

  describe "expandRecipe" $ do
    it "keeps the first camelCase binding across the flattened composition" $ do
      let recipe = Recipe "policy" Nothing Nothing [Dependency "one" (Map.singleton "git.githubOwner" "first") Nothing, Dependency "two" (Map.singleton "git.githubOwner" "second") Nothing] [] [] Nothing [] []
          (_, _, overrides, _, _, _) = expectExpanded recipe
      Map.lookup "git.githubOwner" overrides `shouldBe` Just "first"

    it "returns correct primary and additional module names" $ do
      let recipe =
            Recipe
              { name = "combo",
                version = Just "1.0.0",
                description = Nothing,
                modules =
                  [ simpleDep "mod-a",
                    Dependency "mod-b" mempty (Just "https://example.com/registry"),
                    simpleDep "mod-c"
                  ],
                vars = [],
                prompts = [],
                extends = Nothing,
                moduleOverrides = [],
                promptOverrides = []
              }
          (primary, additional, _, _, _, requirements) = expectExpanded recipe
      primary `shouldBe` ModuleName "mod-a"
      additional `shouldBe` [ModuleName "mod-b", ModuleName "mod-c"]
      requirements `shouldBe` [simpleDep "mod-a", Dependency "mod-b" mempty (Just "https://example.com/registry"), simpleDep "mod-c"]

    it "collects variable overrides from module entries" $ do
      let recipe =
            Recipe
              { name = "pinned",
                version = Nothing,
                description = Nothing,
                modules =
                  [ Dependency (ModuleName "base") (Map.singleton "project.name" "my-app") Nothing,
                    Dependency (ModuleName "nix") (Map.singleton "nix.system" "aarch64-darwin") Nothing
                  ],
                vars = [],
                prompts = [],
                extends = Nothing,
                moduleOverrides = [],
                promptOverrides = []
              }
          (_, _, overrides, _, _, _) = expectExpanded recipe
      Map.lookup (VarName "project.name") overrides `shouldBe` Just "my-app"
      Map.lookup (VarName "nix.system") overrides `shouldBe` Just "aarch64-darwin"

    it "passes through recipe-level vars and prompts" $ do
      let recipeVar =
            VarDecl
              { name = "project.name",
                type_ = VTText,
                default_ = Nothing,
                description = Just "Project name",
                required = True,
                validation = Nothing
              }
          recipePrompt =
            Prompt
              { var = "project.name",
                text = "Enter name:",
                condition = Nothing,
                choices = Nothing
              }
          recipe =
            Recipe
              { name = "prompted",
                version = Nothing,
                description = Nothing,
                modules = [simpleDep "base"],
                vars = [recipeVar],
                prompts = [recipePrompt],
                extends = Nothing,
                moduleOverrides = [],
                promptOverrides = []
              }
          (_, _, _, vars, prompts, _) = expectExpanded recipe
      vars `shouldBe` [recipeVar]
      prompts `shouldBe` [recipePrompt]

    it "handles a single-module recipe (alias)" $ do
      let recipe =
            Recipe
              { name = "alias",
                version = Nothing,
                description = Nothing,
                modules = [simpleDep "the-module"],
                vars = [],
                prompts = [],
                extends = Nothing,
                moduleOverrides = [],
                promptOverrides = []
              }
          (primary, additional, overrides, _, _, _) = expectExpanded recipe
      primary `shouldBe` ModuleName "the-module"
      additional `shouldBe` []
      Map.null overrides `shouldBe` True

    it "returns validation errors for an empty recipe" $ do
      let recipe =
            Recipe
              { name = "empty",
                version = Nothing,
                description = Nothing,
                modules = [],
                vars = [],
                prompts = [],
                extends = Nothing,
                moduleOverrides = [],
                promptOverrides = []
              }
      expandRecipe recipe `shouldBe` Left ["modules: recipe must list at least one module"]

    it "shares rejection of malformed prompt targets and conditions with descriptor validation" $ do
      let recipe =
            Recipe
              "bad-prompts"
              Nothing
              Nothing
              [simpleDep "unavailable"]
              []
              [Prompt "missing-target" "Question" (Just (ExprNot (ExprIsSet "missing-condition"))) Nothing]
              Nothing
              []
              []
      case validateRecipe recipe of
        Left errors -> do
          length errors `shouldBe` 2
          expandRecipe recipe `shouldBe` Left errors
        Right _ -> expectationFailure "Expected malformed prompt references to fail"

flat :: RecipeName -> [Dependency] -> Recipe
flat name deps = Recipe name Nothing Nothing deps [] [] Nothing [] []

derived :: RecipeName -> RecipeName -> Recipe
derived name base = flat name [] & #extends .~ Just (RecipeReference base Nothing Nothing)

bound :: ModuleName -> Text -> Dependency
bound name value = Dependency name (Map.singleton "x" value) Nothing

node :: Recipe -> ResolvedRecipeNode
node recipe = ResolvedRecipeNode recipe origin "." [ResolvedRecipeMember dep (recipe ^. #name) origin "." (LocalOrigin (dep ^. #module_ . #unModuleName)) | dep <- recipe ^. #modules]
  where
    origin = LocalOrigin (recipe ^. #name . #unRecipeName)

writeChildDescriptor :: FilePath -> IO ()
writeChildDescriptor dir = do
  createDirectoryIfMissing True (dir </> "child")
  writeFile
    (dir </> "child" </> "recipe.dhall")
    "{ name = \"child\", version = None Text, description = None Text, modules = [] : List Text, vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }, prompts = [] : List {var : Text, text : Text, when : Optional Text, choices : Optional (List Text)}, extends = Some {recipe = \"base\"} }"
