module Seihou.CLI.CheckoutSyncE2ESpec (tests) where

import Control.Monad (forM_, unless)
import Data.Aeson qualified as A
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.List (isInfixOf)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.SeihouBinary (seihouBinary)
import System.Directory qualified as D
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, takeExtension, (</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode, readProcess)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

-- Every invocation has an empty personal configuration/cache and no inherited HOME.
invoke binary root home args = do
  inherited <- getEnvironment
  let overrides = [("HOME", home), ("XDG_CONFIG_HOME", home </> "config"), ("XDG_CACHE_HOME", home </> "cache")]
      environment = overrides <> filter (\(key, _) -> key `notElem` map fst overrides) inherited
  readCreateProcessWithExitCode ((proc binary args) {cwd = Just root, env = Just environment}) ""

success binary root home args = do
  (code, out, err) <- invoke binary root home args
  unless (code == ExitSuccess) (expectationFailure (unwords args <> ": " <> out <> err))
  pure out

git root args = readProcess "git" (["-C", root] <> args) ""

snapshot root = do
  names <- filter (not . null) . splitNul <$> git root ["ls-files", "-z"]
  blobs <- mapM (\path -> (path,) <$> BS.readFile (root </> path)) names
  index <- git root ["ls-files", "--stage", "-z"]
  pure (blobs, index)
  where
    splitNul [] = []
    splitNul input = let (a, b) = break (== '\0') input in a : splitNul (drop 1 b)

fixtureModule name source destination secondSource secondDestination version enabled =
  T.unlines
    [ "let S = ./schema/package.dhall",
      "in S.Module::{ name = \"" <> name <> "\", version = Some \"" <> version <> "\",",
      "vars = [S.VarDecl::{name = \"source\", type = \"text\", default = Some \"" <> source <> "\"}, S.VarDecl::{name = \"enabled\", type = \"bool\", default = Some \"" <> enabled <> "\"}],",
      "steps = [ S.Step::{strategy = \"symlink\", src = \"{{source}}\", dest = \"" <> destination <> "\", lifecycle = Some \"checkout\", when = Some \"Eq enabled true\"},",
      "S.Step::{strategy = \"symlink\", src = \"" <> secondSource <> "\", dest = \"" <> secondDestination <> "\", lifecycle = Some \"checkout\"}],",
      "commands = [S.Command::{run = \"touch command-sentinel\"}] }"
    ]

prepare root home source destination secondSource secondDestination = do
  binary <- seihouBinary
  cwd <- D.getCurrentDirectory
  schema <- D.canonicalizePath (takeDirectory cwd </> "schema")
  let moduleDir = root </> ".seihou/modules/demo"
  D.createDirectoryIfMissing True (moduleDir </> "schema")
  schemaFiles <- D.listDirectory schema
  forM_ schemaFiles $ \file ->
    if takeExtension file == ".dhall" then D.copyFile (schema </> file) (moduleDir </> "schema" </> file) else pure ()
  forM_ [source, secondSource, "config/next"] $ \dir -> do
    D.createDirectoryIfMissing True (root </> T.unpack dir)
    TIO.writeFile (root </> T.unpack dir </> "sentinel") "source bytes\n"
  let ignored = T.unlines [T.pack (takeDirectory (T.unpack destination)) <> "/", T.pack (takeDirectory (T.unpack secondDestination)) <> "/", ".seihou/modules/", ".seihou/config.dhall", "command-sentinel"]
  TIO.writeFile (root </> ".gitignore") ignored
  TIO.writeFile (moduleDir </> "module.dhall") (fixtureModule "demo" source destination secondSource secondDestination "1.0.0" "true")
  _ <- git root ["init", "-q"]
  _ <- git root ["config", "user.name", "Checkout fixture"]
  _ <- git root ["config", "user.email", "checkout@example.invalid"]
  _ <- success binary root home ["run", "demo", "--force"]
  D.removeFile (root </> "command-sentinel")
  _ <- git root ["add", "."]
  _ <- git root ["commit", "-qm", "test: record checkout output declarations"]
  pure (binary, moduleDir)

tests :: IO TestTree
tests = testSpec "manifest-only checkout sync" $ do
  forM_ [("agent", "agents/skills/demo", ".claude/skills/demo", "agents/skills/demo", ".agents/skills/demo"), ("editor and assets", "config/editor", ".editor-local/config", "assets/shared", ".tool-local/assets")] $ \(domain, source, destination, secondSource, secondDestination) ->
    it ("restores " <> domain <> " links in a clean clone without a producer or commands") $
      withSystemTempDirectory "checkout-clone" $ \temp -> do
        let original = temp </> "original"; clone = temp </> "clone"; home = temp </> "home"
        D.createDirectoryIfMissing True original
        D.createDirectoryIfMissing True home
        (binary, _) <- prepare original home source destination secondSource secondDestination
        _ <- git original ["clone", "-q", original, clone]
        D.doesDirectoryExist (clone </> ".seihou/modules") `shouldReturn` False
        TIO.writeFile (clone </> ".seihou/config.dhall") "deliberately invalid configuration; sync must never evaluate it"
        before <- snapshot clone
        manifest <- BS.readFile (clone </> ".seihou/manifest.json")
        dry <- success binary clone home ["sync", "--dry-run", "--json"]
        dry `shouldSatisfy` isInfixOf "\"not-applied\""
        snapshot clone `shouldReturn` before
        D.doesPathExist (clone </> takeDirectory (T.unpack destination)) `shouldReturn` False
        _ <- success binary clone home ["sync", "--json"]
        BS.readFile (clone </> ".seihou/manifest.json") `shouldReturn` manifest
        snapshot clone `shouldReturn` before
        git clone ["status", "--porcelain"] `shouldReturn` ""
        D.pathIsSymbolicLink (clone </> T.unpack destination) `shouldReturn` True
        D.doesFileExist (clone </> "command-sentinel") `shouldReturn` False
        -- Even a newer producer in the cache cannot change recorded intent.
        let newer = home </> "config/seihou/installed/demo"
        D.createDirectoryIfMissing True (newer </> "schema")
        schemaFiles <- D.listDirectory (original </> ".seihou/modules/demo/schema")
        forM_ schemaFiles $ \file ->
          D.copyFile (original </> ".seihou/modules/demo/schema" </> file) (newer </> "schema" </> file)
        TIO.writeFile (newer </> "module.dhall") (fixtureModule "demo" "config/next" destination secondSource secondDestination "99.0.0" "true")
        repeated <- success binary clone home ["sync", "--json"]
        repeated `shouldSatisfy` isInfixOf "\"plannedAction\":\"unchanged\""
        D.removeDirectoryLink (clone </> T.unpack destination)
        D.removeDirectoryLink (clone </> T.unpack secondDestination)
        D.createDirectoryLink "missing-target" (clone </> T.unpack secondDestination)
        status <- success binary clone home ["status"]
        status `shouldSatisfy` isInfixOf "seihou sync"
        _ <- success binary clone home ["sync", "--json"]
        snapshot clone `shouldReturn` before
        -- A regular collision refuses the whole plan, preserving source bytes.
        D.removeDirectoryLink (clone </> T.unpack destination)
        TIO.writeFile (clone </> T.unpack destination) "local sentinel"
        (code, refusal, _) <- invoke binary clone home ["sync", "--json"]
        code `shouldSatisfy` (/= ExitSuccess)
        refusal `shouldSatisfy` isInfixOf "checkout_destination_occupied"
        TIO.readFile (clone </> T.unpack destination) `shouldReturn` "local sentinel"
        D.removeFile (clone </> T.unpack destination)
        _ <- success binary clone home ["sync"]
        -- A linked worktree has a .git file and the same manifest-only contract.
        let worktree = temp </> "linked-worktree"
        _ <- git original ["worktree", "add", "--detach", "-q", worktree]
        _ <- success binary worktree home ["sync", "--json"]
        git worktree ["status", "--porcelain"] `shouldReturn` ""
        _ <- success binary clone home ["remove", "demo", "--force"]
        D.doesPathExist (clone </> T.unpack destination) `shouldReturn` False
        TIO.readFile (clone </> T.unpack source </> "sentinel") `shouldReturn` "source bytes\n"
  it "preserves agreeing application owners until the last owner is removed" $
    withSystemTempDirectory "checkout-owners" $ \temp -> do
      let root = temp </> "project"
          home = temp </> "home"
      D.createDirectoryIfMissing True root
      D.createDirectoryIfMissing True home
      (binary, demoDir) <- prepare root home "config/editor" ".local/config" "assets/shared" ".tool/assets"
      let other = root </> ".seihou/modules/other"
      D.createDirectoryIfMissing True (other </> "schema")
      files <- D.listDirectory (demoDir </> "schema")
      forM_ files $ \file -> D.copyFile (demoDir </> "schema" </> file) (other </> "schema" </> file)
      TIO.writeFile (other </> "module.dhall") (fixtureModule "other" "config/editor" ".local/config" "assets/shared" ".tool/assets" "1.0.0" "true")
      _ <- success binary root home ["run", "other", "--force", "--no-commands"]
      -- An unselected agreeing owner prevents a unilateral retarget.
      TIO.writeFile (demoDir </> "module.dhall") (fixtureModule "demo" "config/next" ".local/config" "assets/shared" ".tool/assets" "2.0.0" "true")
      (code, _, _) <- invoke binary root home ["update", "demo", "--reconfigure", "--force", "--no-commands"]
      code `shouldSatisfy` (/= ExitSuccess)
      D.getSymbolicLinkTarget (root </> ".local/config") `shouldReturn` "../config/editor"
      _ <- success binary root home ["remove", "demo", "--force"]
      D.pathIsSymbolicLink (root </> ".local/config") `shouldReturn` True
      _ <- success binary root home ["remove", "other", "--force"]
      D.doesPathExist (root </> ".local/config") `shouldReturn` False
      TIO.readFile (root </> "config/editor/sentinel") `shouldReturn` "source bytes\n"
  it "links a source generated in the same composition and preserves other applications" $
    withSystemTempDirectory "checkout-generated" $ \temp -> do
      let root = temp </> "project"; home = temp </> "home"
      D.createDirectoryIfMissing True root
      D.createDirectoryIfMissing True home
      (binary, demoDir) <- prepare root home "config/editor" ".local/config" "assets/shared" ".tool/assets"
      let generated = root </> ".seihou/modules/generated"
      D.createDirectoryIfMissing True (generated </> "files")
      D.createDirectoryIfMissing True (generated </> "schema")
      schemaFiles <- D.listDirectory (demoDir </> "schema")
      forM_ schemaFiles $ \file -> D.copyFile (demoDir </> "schema" </> file) (generated </> "schema" </> file)
      TIO.writeFile (generated </> "files/settings") "generated source bytes"
      TIO.appendFile (root </> ".gitignore") ".generated/\n"
      TIO.writeFile
        (generated </> "module.dhall")
        ( T.unlines
            [ "let S = ./schema/package.dhall in S.Module::{ name = \"generated\", version = Some \"1.0.0\", steps = [",
              "S.Step::{strategy = \"copy\", src = \"settings\", dest = \"generated/editor/settings\"},",
              "S.Step::{strategy = \"symlink\", src = \"generated/editor\", dest = \".generated/editor\", lifecycle = Some \"checkout\"}] }"
            ]
        )
      _ <- success binary root home ["run", "generated", "--dry-run", "--no-commands"]
      D.doesPathExist (root </> "generated") `shouldReturn` False
      D.doesPathExist (root </> ".generated") `shouldReturn` False
      _ <- success binary root home ["run", "generated", "--force", "--no-commands"]
      D.getSymbolicLinkTarget (root </> ".generated/editor") `shouldReturn` "../generated/editor"
      D.getSymbolicLinkTarget (root </> ".local/config") `shouldReturn` "../config/editor"
      TIO.readFile (root </> "generated/editor/settings") `shouldReturn` "generated source bytes"
  it "rolls back link targets and manifest bytes when an update command fails" $
    withSystemTempDirectory "checkout-update-failure" $ \temp -> do
      let root = temp </> "project"; home = temp </> "home"
      D.createDirectoryIfMissing True root
      D.createDirectoryIfMissing True home
      (binary, moduleDir) <- prepare root home "config/editor" ".local/config" "assets/shared" ".tool/assets"
      before <- BS.readFile (root </> ".seihou/manifest.json")
      let candidate = T.replace "touch command-sentinel" "exit 42" (fixtureModule "demo" "config/next" ".local/config" "assets/shared" ".tool/assets" "2.0.0" "true")
      TIO.writeFile (moduleDir </> "module.dhall") candidate
      (code, _, _) <- invoke binary root home ["update", "demo", "--reconfigure", "--force", "--json"]
      code `shouldSatisfy` (/= ExitSuccess)
      D.getSymbolicLinkTarget (root </> ".local/config") `shouldReturn` "../config/editor"
      BS.readFile (root </> ".seihou/manifest.json") `shouldReturn` before
      TIO.readFile (root </> "config/editor/sentinel") `shouldReturn` "source bytes\n"
  it "updates a link-only module, retires a false condition, and preserves an edited retirement" $
    withSystemTempDirectory "checkout-update" $ \temp -> do
      let root = temp </> "project"; home = temp </> "home"
      D.createDirectoryIfMissing True root
      D.createDirectoryIfMissing True home
      (binary, moduleDir) <- prepare root home "config/editor" ".local/config" "assets/shared" ".tool/assets"
      TIO.writeFile (moduleDir </> "module.dhall") (fixtureModule "demo" "config/next" ".local/config" "assets/shared" ".tool/assets" "2.0.0" "true")
      _ <- success binary root home ["update", "demo", "--reconfigure", "--no-commands", "--force", "--json"]
      D.getSymbolicLinkTarget (root </> ".local/config") `shouldReturn` "../config/next"
      D.removeDirectoryLink (root </> ".local/config")
      D.createDirectoryLink "locally-edited" (root </> ".local/config")
      TIO.writeFile (moduleDir </> "module.dhall") (fixtureModule "demo" "config/next" ".local/config" "assets/shared" ".tool/assets" "3.0.0" "false")
      _ <- success binary root home ["update", "demo", "--reconfigure", "--no-commands", "--force", "--json"]
      D.getSymbolicLinkTarget (root </> ".local/config") `shouldReturn` "locally-edited"
      D.doesFileExist (root </> "command-sentinel") `shouldReturn` False
