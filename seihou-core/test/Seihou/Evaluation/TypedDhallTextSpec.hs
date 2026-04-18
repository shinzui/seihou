module Seihou.Evaluation.TypedDhallTextSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.Core.Types
import Seihou.Engine.Template (renderTemplate)
import Seihou.Engine.TypedDhallText (fieldNameFor, renderTypedDhallText)
import System.Directory (getCurrentDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Evaluation.TypedDhallText" spec

commonVars :: Map.Map VarName VarValue
commonVars =
  Map.fromList
    [ ("project.name", VText "demo-app"),
      ("project.description", VText "A demo Haskell application"),
      ("ghc.version", VText "ghc912"),
      ("nix.process-compose", VBool True)
    ]

fixtureSource :: IO FilePath
fixtureSource = do
  cwd <- getCurrentDirectory
  pure
    ( cwd
        </> "test"
        </> "fixtures"
        </> "evaluation"
        </> "typed-dhall-text-flake"
        </> "files"
        </> "flake.nix.dhall"
    )

splitFlakeDir :: IO FilePath
splitFlakeDir = do
  cwd <- getCurrentDirectory
  pure (cwd </> "test" </> "fixtures" </> "evaluation" </> "split-flake")

renderSplitFlake :: FilePath -> Map.Map VarName VarValue -> IO Text
renderSplitFlake tplName vars = do
  base <- splitFlakeDir
  raw <- TIO.readFile (base </> "files" </> tplName)
  case renderTemplate raw vars of
    Left errs -> fail ("renderTemplate failed: " <> show errs)
    Right t -> pure t

spec :: Spec
spec = do
  describe "fieldNameFor" $ do
    it "replaces dots with underscores" $
      fieldNameFor "project.name" `shouldBe` "project_name"

    it "replaces dashes with underscores" $
      fieldNameFor "nix.process-compose" `shouldBe` "nix_process_compose"

  describe "typed-dhall-text-flake fixture (Prototype B)" $ do
    it "with nix.postgresql = false, produces bytes identical to the non-postgres baseline" $ do
      src <- fixtureSource
      let vars = Map.insert "nix.postgresql" (VBool False) commonVars
      result <- renderTypedDhallText src vars
      case result of
        Left err -> expectationFailure ("renderTypedDhallText failed: " <> T.unpack err)
        Right txt -> do
          expected <- renderSplitFlake "flake.nix.tpl" vars
          txt `shouldBe` expected

    it "with nix.postgresql = true, produces bytes identical to the postgres baseline" $ do
      src <- fixtureSource
      let vars = Map.insert "nix.postgresql" (VBool True) commonVars
      result <- renderTypedDhallText src vars
      case result of
        Left err -> expectationFailure ("renderTypedDhallText failed: " <> T.unpack err)
        Right txt -> do
          expected <- renderSplitFlake "flake-with-postgres.nix.tpl" vars
          txt `shouldBe` expected

    it "reports a field-name typo with the offending field in the error message" $ do
      -- Seed a typo: the source says nix_postgres but the record provides
      -- nix_postgresql. Dhall must report the mismatch mentioning one of them.
      withSystemTempDirectory "seihou-typed-dhall" $ \tmp -> do
        let typoSrc = tmp </> "typo.dhall"
            typoSource =
              T.unlines
                [ "\\(vars :",
                  "    { project_name         : Text",
                  "    , project_description  : Text",
                  "    , ghc_version          : Text",
                  "    , nix_process_compose  : Bool",
                  "    , nix_postgres         : Bool",
                  "    }",
                  "  ) ->",
                  "  \"${vars.project_name} ${vars.ghc_version}\""
                ]
        TIO.writeFile typoSrc typoSource
        let vars = Map.insert "nix.postgresql" (VBool False) commonVars
        result <- renderTypedDhallText typoSrc vars
        case result of
          Right _ -> expectationFailure "Expected a Dhall type error"
          Left err -> do
            -- The error text must mention either the missing field name from
            -- the lambda type annotation or the extra field on the record.
            T.isInfixOf "nix_postgres" err `shouldBe` True
