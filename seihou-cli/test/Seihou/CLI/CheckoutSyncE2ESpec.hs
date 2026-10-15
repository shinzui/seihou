module Seihou.CLI.CheckoutSyncE2ESpec (tests) where

import Control.Monad (forM_, unless, when)
import Data.Aeson qualified as A
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.List (isInfixOf)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
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
  blobs <-
    mapM
      ( \path -> do
          linked <- D.pathIsSymbolicLink (root </> path)
          bytes <- if linked then TE.encodeUtf8 . T.pack <$> D.getSymbolicLinkTarget (root </> path) else BS.readFile (root </> path)
          pure (path, bytes)
      )
      names
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

-- Establish a real old command-producing application, then publish a declaring
-- release. Adoption itself runs in a different, empty personal configuration.
prepareAdoption temp failing = prepareAdoptionWithTracking temp failing True

prepareAdoptionWithTracking temp failing tracked = do
  binary <- seihouBinary
  cwd <- D.getCurrentDirectory
  schema <- D.canonicalizePath (takeDirectory cwd </> "schema")
  let root = temp </> "project"
      remote = temp </> "producer"
      initialHome = temp </> "initial-home"
      home = temp </> "empty-home"
      remoteUrl = "https://seihou-fixture.invalid/demo.git"
      moduleBody version steps commands =
        T.unlines
          [ "let S = ./schema/package.dhall in S.Module::{name = \"demo\", version = Some \"" <> version <> "\",",
            "steps = " <> steps <> ", commands = " <> commands <> "}"
          ]
      commit repo message = do
        _ <- git repo ["add", "."]
        git repo ["-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", message]
  forM_ [root </> "config/editor", remote </> "schema", initialHome, home] (D.createDirectoryIfMissing True)
  -- Keep the recorded origin portable while Git routes this fixture remote to
  -- disk. The adoption home has Git configuration but no producer cache.
  forM_ [initialHome, home] $ \gitHome -> do
    _ <- git gitHome ["config", "--file", gitHome </> ".gitconfig", "url." <> remote <> ".insteadOf", remoteUrl]
    pure ()
  files <- D.listDirectory schema
  forM_ files $ \file -> if takeExtension file == ".dhall" then D.copyFile (schema </> file) (remote </> "schema" </> file) else pure ()
  TIO.writeFile
    (remote </> "module.dhall")
    ( moduleBody
        "1.0.0"
        "[] : List S.Step.Type"
        "[S.Command::{run = \"mkdir -p .local && ln -s ../config/editor .local/config\"}]"
    )
  _ <- git remote ["init", "-q"]
  _ <- commit remote "test: publish command producer"
  _ <- git root ["init", "-q"]
  TIO.writeFile (root </> ".gitignore") ".local/\n.seihou/transactions/\n"
  TIO.writeFile (root </> "config/editor/sentinel") "tracked source\n"
  TIO.writeFile (root </> "unrelated") "committed\n"
  _ <- success binary root initialHome ["install", remoteUrl]
  _ <- success binary root initialHome ["run", "demo", "--force"]
  D.createDirectoryLink "../config/editor" (root </> ".local/unrelated")
  when tracked $ do
    _ <- git root ["add", "-f", ".local/config"]
    pure ()
  _ <- git root ["add", "-f", ".local/unrelated"]
  _ <- commit root "test: record legacy application and discovery links"
  let commands = if failing then "[S.Command::{run = \"exit 42\"}]" else "[] : List S.Command.Type"
  TIO.writeFile
    (remote </> "module.dhall")
    ( moduleBody
        "2.0.0"
        "[S.Step::{strategy = \"symlink\", lifecycle = Some \"checkout\", src = \"config/editor\", dest = \".local/config\"}]"
        commands
    )
  _ <- commit remote "test: publish checkout declarations"
  pure (binary, root, home)

tests :: IO TestTree
tests = testSpec "checkout sync and adoption" $ do
  it "owns adoption from an old clone and restores a teammate's fresh clone" $
    withSystemTempDirectory "sync-team-adoption" $ \temp -> do
      (binary, original, home) <- prepareAdoptionWithTracking temp True False
      let root = temp </> "older-clone"
      _ <- git original ["clone", "-q", original, root]
      before <- snapshot root
      D.doesPathExist (root </> ".local/config") `shouldReturn` False
      status <- success binary root home ["status"]
      status `shouldSatisfy` isInfixOf "Checkout outputs: none declared."
      status `shouldSatisfy` isInfixOf "Run seihou sync"
      dry <- success binary root home ["sync", "--dry-run", "--json"]
      dry `shouldSatisfy` isInfixOf "\"approvalRequired\":true"
      dry `shouldSatisfy` isInfixOf "\"plannedAction\":\"create\""
      snapshot root `shouldReturn` before
      D.doesPathExist (root </> ".local/config") `shouldReturn` False
      (cancelCode, _, _) <- invoke binary root home ["sync"]
      cancelCode `shouldSatisfy` (/= ExitSuccess)
      (jsonCode, _, _) <- invoke binary root home ["sync", "--json"]
      jsonCode `shouldSatisfy` (/= ExitSuccess)
      snapshot root `shouldReturn` before
      adopted <- success binary root home ["sync", "--yes"]
      adopted `shouldSatisfy` isInfixOf "Links: 1 created, 0 repaired, 0 unchanged."
      D.getSymbolicLinkTarget (root </> ".local/config") `shouldReturn` "../config/editor"
      TIO.readFile (root </> ".local/config/sentinel") `shouldReturn` "tracked source\n"
      _ <- git root ["add", ".seihou"]
      _ <- git root ["-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "test: share link setup"]
      let clone = temp </> "teammate"; cloneHome = temp </> "teammate-home"
      D.createDirectoryIfMissing True cloneHome
      _ <- git root ["clone", "-q", root, clone]
      cloneBefore <- snapshot clone
      first <- success binary clone cloneHome ["sync"]
      first `shouldSatisfy` isInfixOf "Links: 1 created, 0 repaired, 0 unchanged."
      second <- success binary clone cloneHome ["sync"]
      second `shouldSatisfy` isInfixOf "Links: 0 created, 0 repaired, 1 unchanged."
      snapshot clone `shouldReturn` cloneBefore
      D.doesDirectoryExist (cloneHome </> "config/seihou/installed") `shouldReturn` False
  it "adopts tracked links through sync while preserving unrelated staging" $
    withSystemTempDirectory "sync-tracked-adoption" $ \temp -> do
      (binary, root, home) <- prepareAdoption temp False
      TIO.writeFile (root </> "unrelated") "staged edit\n"
      _ <- git root ["add", "unrelated"]
      TIO.writeFile (root </> "unrelated") "unstaged edit\n"
      dry <- success binary root home ["sync", "--dry-run"]
      dry `shouldSatisfy` isInfixOf "Adopt link: .local/config"
      _ <- success binary root home ["sync", "--yes", "--json"]
      git root ["ls-files", "--", ".local/config"] `shouldReturn` ""
      git root ["show", ":unrelated"] `shouldReturn` "staged edit\n"
      TIO.readFile (root </> "unrelated") `shouldReturn` "unstaged edit\n"
      D.getSymbolicLinkTarget (root </> ".local/config") `shouldReturn` "../config/editor"
  it "does not upgrade or prompt for an unrelated application during link setup" $
    withSystemTempDirectory "sync-unrelated-application" $ \temp -> do
      (binary, root, home) <- prepareAdoption temp False
      let other = root </> ".seihou/modules/other"
          body version vars = "let S = ./schema/package.dhall in S.Module::{name = \"other\", version = Some \"" <> version <> "\", vars = " <> vars <> ", steps = [S.Step::{strategy = \"copy\", src = \"sentinel\", dest = \"other-output\"}]}"
      D.createDirectoryIfMissing True (other </> "files")
      D.createDirectoryIfMissing True (other </> "schema")
      schemaFiles <- D.listDirectory (temp </> "producer/schema")
      forM_ schemaFiles $ \file -> D.copyFile (temp </> "producer/schema" </> file) (other </> "schema" </> file)
      TIO.writeFile (other </> "files/sentinel") "original other output\n"
      TIO.writeFile (other </> "module.dhall") (body "1.0.0" "[] : List S.VarDecl.Type")
      _ <- success binary root home ["run", "other", "--force"]
      oldManifest <- A.eitherDecode <$> LBS.readFile (root </> ".seihou/manifest.json")
      TIO.writeFile (other </> "files/sentinel") "unrelated proposed update\n"
      TIO.writeFile (other </> "module.dhall") (body "2.0.0" "[S.VarDecl::{name = \"new-input\", type = \"text\", required = True}]")
      _ <- success binary root home ["sync", "--yes"]
      TIO.readFile (root </> "other-output") `shouldReturn` "original other output\n"
      newManifest <- A.eitherDecode <$> LBS.readFile (root </> ".seihou/manifest.json")
      let otherApplication decoded = case decoded of
            Right (A.Object fields) -> case KM.lookup "applications" fields of
              Just (A.Array applications) -> [app | app@(A.Object values) <- foldr (:) [] applications, KM.lookup "target" values == Just (A.object ["kind" A..= ("module" :: T.Text), "name" A..= ("other" :: T.Text)])]
              _ -> []
            _ -> []
      length (otherApplication oldManifest) `shouldBe` 1
      otherApplication newManifest `shouldBe` otherApplication oldManifest
  it "refuses occupied directories during adoption without losing user files" $
    withSystemTempDirectory "sync-adoption-collision" $ \temp -> do
      (binary, root, home) <- prepareAdoptionWithTracking temp False False
      D.removeDirectoryLink (root </> ".local/config")
      D.createDirectoryIfMissing True (root </> ".local/config")
      TIO.writeFile (root </> ".local/config/user-file") "keep me\n"
      before <- snapshot root
      (code, _, _) <- invoke binary root home ["sync", "--yes"]
      code `shouldSatisfy` (/= ExitSuccess)
      snapshot root `shouldReturn` before
      TIO.readFile (root </> ".local/config/user-file") `shouldReturn` "keep me\n"
  it "adopts a tracked link using remote update alone, then syncs a fresh clone" $
    withSystemTempDirectory "checkout-adoption" $ \temp -> do
      (binary, root, home) <- prepareAdoption temp False
      D.doesDirectoryExist (home </> "config/seihou/installed") `shouldReturn` False
      notice <- success binary root home ["sync", "--dry-run"]
      notice `shouldSatisfy` isInfixOf "One-time link setup is available"
      TIO.writeFile (root </> "unrelated") "staged edit\n"
      _ <- git root ["add", "unrelated"]
      TIO.writeFile (root </> "unrelated") "unstaged edit\n"
      indexBefore <- git root ["ls-files", "--stage", "-z"]
      manifestBefore <- BS.readFile (root </> ".seihou/manifest.json")
      dry <- success binary root home ["update", "demo", "--dry-run"]
      dry `shouldSatisfy` isInfixOf "Adopt link: .local/config"
      git root ["ls-files", "--stage", "-z"] `shouldReturn` indexBefore
      BS.readFile (root </> ".seihou/manifest.json") `shouldReturn` manifestBefore
      _ <- success binary root home ["update", "demo"]
      git root ["ls-files", "--stage", "-z"] `shouldReturn` indexBefore
      BS.readFile (root </> ".seihou/manifest.json") `shouldReturn` manifestBefore
      applied <- success binary root home ["update", "demo", "--json"]
      applied `shouldSatisfy` isInfixOf "\"adoptedLinks\":[\".local/config\"]"
      git root ["ls-files", "--", ".local/config"] `shouldReturn` ""
      git root ["ls-files", "--", ".local/unrelated"] `shouldReturn` ".local/unrelated\n"
      git root ["show", ":unrelated"] `shouldReturn` "staged edit\n"
      TIO.readFile (root </> "unrelated") `shouldReturn` "unstaged edit\n"
      D.getSymbolicLinkTarget (root </> ".local/config") `shouldReturn` "../config/editor"
      _ <- git root ["add", ".seihou/manifest.json"]
      _ <- git root ["-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "test: adopt links"]
      let clone = temp </> "clone"; cloneHome = temp </> "clone-home"
      D.createDirectoryIfMissing True cloneHome
      _ <- git root ["clone", "-q", root, clone]
      before <- snapshot clone
      D.doesPathExist (clone </> ".local/config") `shouldReturn` False
      first <- success binary clone cloneHome ["sync"]
      first `shouldSatisfy` isInfixOf "Links: 1 created, 0 repaired, 0 unchanged."
      second <- success binary clone cloneHome ["sync"]
      second `shouldSatisfy` isInfixOf "Links: 0 created, 0 repaired, 1 unchanged."
      status <- success binary clone cloneHome ["status"]
      status `shouldSatisfy` isInfixOf "Checkout outputs: 1 declared, 0 need attention."
      status `shouldSatisfy` isInfixOf "Remote producer cache: 1 not cached locally (optional)"
      status `shouldNotSatisfy` isInfixOf "Artifacts that differ"
      snapshot clone `shouldReturn` before
      D.doesDirectoryExist (cloneHome </> "config/seihou/installed") `shouldReturn` False
  it "restores the original index and working links if an adopted update fails" $
    withSystemTempDirectory "checkout-adoption-failed" $ \temp -> do
      (binary, root, home) <- prepareAdoption temp True
      before <- snapshot root
      (code, _, _) <- invoke binary root home ["update", "demo", "--json"]
      code `shouldSatisfy` (/= ExitSuccess)
      snapshot root `shouldReturn` before
  forM_ ["staged link", "unstaged link", "regular file"] $ \kind ->
    it ("protects a " <> kind <> " during adoption") $
      withSystemTempDirectory "checkout-adoption-refused" $ \temp -> do
        (binary, root, home) <- prepareAdoption temp False
        D.removeDirectoryLink (root </> ".local/config")
        if kind == "regular file"
          then TIO.writeFile (root </> ".local/config") "user bytes"
          else D.createDirectoryLink "../other-target" (root </> ".local/config")
        if kind == "staged link"
          then do
            _ <- git root ["add", "-f", ".local/config"]
            -- The working link matches the new declaration, but the index does not.
            D.removeDirectoryLink (root </> ".local/config")
            D.createDirectoryLink "../config/editor" (root </> ".local/config")
          else pure ()
        before <- snapshot root
        (code, _, _) <- invoke binary root home ["update", "demo", "--json"]
        code `shouldSatisfy` (/= ExitSuccess)
        snapshot root `shouldReturn` before
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
