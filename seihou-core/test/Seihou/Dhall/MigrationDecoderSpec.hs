module Seihou.Dhall.MigrationDecoderSpec (tests) where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.Core.Migration (Migration (..), MigrationOp (..))
import Seihou.Core.Types (Module (..), ModuleLoadError)
import Seihou.Dhall.Eval (evalModuleFromFile)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Dhall.MigrationDecoder" spec

spec :: Spec
spec = do
  describe "moduleDecoder migrations field" $ do
    it "decodes a module with no migrations field as []" $
      withModuleDhall noMigrationsField $ \result ->
        case result of
          Right m -> m.migrations `shouldBe` []
          Left err -> expectationFailure ("Expected Right, got: " <> show err)

    it "decodes a module with an empty migrations list" $
      withModuleDhall emptyMigrations $ \result ->
        case result of
          Right m -> m.migrations `shouldBe` []
          Left err -> expectationFailure ("Expected Right, got: " <> show err)

    it "decodes a single MoveFile migration" $
      withModuleDhall (oneMigration moveFileOp) $ \result ->
        case result of
          Right m -> case m.migrations of
            [Migration {from = "1.0.0", to = "2.0.0", ops = [op]}] ->
              op `shouldBe` MoveFile {src = "old/Path.hs", dest = "new/Path.hs"}
            other -> expectationFailure ("Unexpected migrations: " <> show other)
          Left err -> expectationFailure ("Expected Right, got: " <> show err)

    it "decodes a MoveDir migration" $
      withModuleDhall (oneMigration moveDirOp) $ \result ->
        case result of
          Right m -> case m.migrations of
            [Migration {ops = [op]}] ->
              op `shouldBe` MoveDir {src = "app", dest = "src"}
            other -> expectationFailure ("Unexpected migrations: " <> show other)
          Left err -> expectationFailure ("Expected Right, got: " <> show err)

    it "decodes a DeleteFile migration" $
      withModuleDhall (oneMigration deleteFileOp) $ \result ->
        case result of
          Right m -> case m.migrations of
            [Migration {ops = [op]}] ->
              op `shouldBe` DeleteFile {path = "Setup.hs"}
            other -> expectationFailure ("Unexpected migrations: " <> show other)
          Left err -> expectationFailure ("Expected Right, got: " <> show err)

    it "decodes a DeleteDir migration" $
      withModuleDhall (oneMigration deleteDirOp) $ \result ->
        case result of
          Right m -> case m.migrations of
            [Migration {ops = [op]}] ->
              op `shouldBe` DeleteDir {path = "obsolete"}
            other -> expectationFailure ("Unexpected migrations: " <> show other)
          Left err -> expectationFailure ("Expected Right, got: " <> show err)

    it "decodes a RunCommand migration without workDir" $
      withModuleDhall (oneMigration runCommandNoWorkDir) $ \result ->
        case result of
          Right m -> case m.migrations of
            [Migration {ops = [op]}] ->
              op `shouldBe` RunCommand {run = "echo hi", workDir = Nothing}
            other -> expectationFailure ("Unexpected migrations: " <> show other)
          Left err -> expectationFailure ("Expected Right, got: " <> show err)

    it "decodes a RunCommand migration with workDir" $
      withModuleDhall (oneMigration runCommandWithWorkDir) $ \result ->
        case result of
          Right m -> case m.migrations of
            [Migration {ops = [op]}] ->
              op `shouldBe` RunCommand {run = "make clean", workDir = Just "build"}
            other -> expectationFailure ("Unexpected migrations: " <> show other)
          Left err -> expectationFailure ("Expected Right, got: " <> show err)

    it "decodes multiple ops in a single migration in declaration order" $
      withModuleDhall multiOpMigration $ \result ->
        case result of
          Right m -> case m.migrations of
            [Migration {ops}] ->
              ops
                `shouldBe` [ MoveDir {src = "app", dest = "src"},
                             DeleteFile {path = "Setup.hs"},
                             RunCommand {run = "echo hi", workDir = Nothing}
                           ]
            other -> expectationFailure ("Unexpected migrations: " <> show other)
          Left err -> expectationFailure ("Expected Right, got: " <> show err)

    it "decodes multiple migrations in declaration order" $
      withModuleDhall twoChainedMigrations $ \result ->
        case result of
          Right m -> case m.migrations of
            [m1, m2] -> do
              m1.from `shouldBe` "1.0.0"
              m1.to `shouldBe` "2.0.0"
              m2.from `shouldBe` "2.0.0"
              m2.to `shouldBe` "3.0.0"
            other -> expectationFailure ("Unexpected migrations: " <> show other)
          Left err -> expectationFailure ("Expected Right, got: " <> show err)

-- ----------------------------------------------------------------------------
-- Helper: write a tmp module.dhall and run the file evaluator on it.
-- ----------------------------------------------------------------------------

withModuleDhall ::
  Text ->
  (Either ModuleLoadError Module -> IO ()) ->
  IO ()
withModuleDhall body action =
  withSystemTempDirectory "seihou-migration-decoder" $ \dir -> do
    createDirectoryIfMissing True (dir </> "files")
    let path = dir </> "module.dhall"
    TIO.writeFile path body
    result <- evalModuleFromFile path
    action result

-- ----------------------------------------------------------------------------
-- Module fixtures expressed inline as Dhall text.
-- ----------------------------------------------------------------------------

-- Bare-record skeleton for a module without the migrations field. The
-- decoder's withDefaults injects an empty list when the field is absent.
noMigrationsField :: Text
noMigrationsField =
  T.unlines
    [ "{ name = \"sample\"",
      ", version = Some \"1.0.0\"",
      ", description = None Text",
      ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
      ", exports = [] : List { var : Text, alias : Optional Text }",
      ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
      ", steps = [] : List { strategy : Text, src : Text, dest : Text, when : Optional Text, patch : Optional Text }",
      ", commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }",
      ", dependencies = [] : List { module : Text, vars : List { name : Text, value : Text } }",
      ", removal = None { steps : List { action : Text, dest : Text, src : Optional Text }, commands : List { run : Text, workDir : Optional Text, when : Optional Text } }",
      "}"
    ]

migrationFieldType :: Text
migrationFieldType =
  "List { from : Text, to : Text, ops : List < MoveFile : { src : Text, dest : Text } | MoveDir : { src : Text, dest : Text } | DeleteFile : { path : Text } | DeleteDir : { path : Text } | RunCommand : { run : Text, workDir : Optional Text } > }"

emptyMigrations :: Text
emptyMigrations = withMigrations ("[] : " <> migrationFieldType)

oneMigration :: Text -> Text
oneMigration opLit =
  withMigrations $
    T.intercalate
      "\n"
      [ "[ { from = \"1.0.0\"",
        "  , to = \"2.0.0\"",
        "  , ops = [ " <> opLit <> " ]",
        "  }",
        "]"
      ]

multiOpMigration :: Text
multiOpMigration =
  withMigrations $
    T.intercalate
      "\n"
      [ "[ { from = \"1.0.0\"",
        "  , to = \"2.0.0\"",
        "  , ops =",
        "      [ " <> moveDirOp,
        "      , " <> deleteFileOp,
        "      , " <> runCommandNoWorkDir,
        "      ]",
        "  }",
        "]"
      ]

twoChainedMigrations :: Text
twoChainedMigrations =
  withMigrations $
    T.intercalate
      "\n"
      [ "[ { from = \"1.0.0\"",
        "  , to = \"2.0.0\"",
        "  , ops = [ " <> moveDirOp <> " ]",
        "  }",
        ", { from = \"2.0.0\"",
        "  , to = \"3.0.0\"",
        "  , ops = [ " <> deleteFileOp <> " ]",
        "  }",
        "]"
      ]

-- | Splice an explicit migrations literal into the bare-record skeleton.
withMigrations :: Text -> Text
withMigrations migrationsLit =
  T.unlines
    [ "{ name = \"sample\"",
      ", version = Some \"1.0.0\"",
      ", description = None Text",
      ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
      ", exports = [] : List { var : Text, alias : Optional Text }",
      ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
      ", steps = [] : List { strategy : Text, src : Text, dest : Text, when : Optional Text, patch : Optional Text }",
      ", commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }",
      ", dependencies = [] : List { module : Text, vars : List { name : Text, value : Text } }",
      ", removal = None { steps : List { action : Text, dest : Text, src : Optional Text }, commands : List { run : Text, workDir : Optional Text, when : Optional Text } }",
      ", migrations = " <> migrationsLit,
      "}"
    ]

-- Dhall union literals for each MigrationOp variant. Each is a fully
-- qualified, type-annotated expression so it can be embedded in a list
-- without an enclosing type annotation on the list elements.

migrationOpType :: Text
migrationOpType =
  "< MoveFile : { src : Text, dest : Text } | MoveDir : { src : Text, dest : Text } | DeleteFile : { path : Text } | DeleteDir : { path : Text } | RunCommand : { run : Text, workDir : Optional Text } >"

opLit :: Text -> Text -> Text
opLit ctor body =
  "(" <> migrationOpType <> ").\n      " <> ctor <> " " <> body

moveFileOp :: Text
moveFileOp = opLit "MoveFile" "{ src = \"old/Path.hs\", dest = \"new/Path.hs\" }"

moveDirOp :: Text
moveDirOp = opLit "MoveDir" "{ src = \"app\", dest = \"src\" }"

deleteFileOp :: Text
deleteFileOp = opLit "DeleteFile" "{ path = \"Setup.hs\" }"

deleteDirOp :: Text
deleteDirOp = opLit "DeleteDir" "{ path = \"obsolete\" }"

runCommandNoWorkDir :: Text
runCommandNoWorkDir = opLit "RunCommand" "{ run = \"echo hi\", workDir = None Text }"

runCommandWithWorkDir :: Text
runCommandWithWorkDir = opLit "RunCommand" "{ run = \"make clean\", workDir = Some \"build\" }"
