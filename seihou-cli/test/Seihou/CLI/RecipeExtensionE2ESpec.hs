module Seihou.CLI.RecipeExtensionE2ESpec (tests) where

import Control.Exception (bracket)
import Control.Lens ((^.))
import Control.Monad (forM_)
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.List (find)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Seihou.CLI.CommandExecution (CommandPolicy (..))
import Seihou.CLI.SeedRunE2ESpec (prepare)
import Seihou.CLI.Update qualified as U
import Seihou.CLI.Update.Types (UpdateError (..))
import System.Directory qualified as D
import System.Environment (getEnvironment, lookupEnv, setEnv, unsetEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), callProcess, proc, readCreateProcessWithExitCode)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

invoke binary root flags = invokeCommand binary root ("run" : "child" : flags)

invokeCommand binary root args = do
  inherited <- getEnvironment
  configured <- D.doesFileExist (root </> "fixture-gitconfig")
  let overrides = zip ["HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"] [root </> "home", root </> "config", root </> "cache"] <> [("GIT_CONFIG_GLOBAL", root </> "fixture-gitconfig") | configured]
      keys = map fst overrides
      environment = overrides <> filter (\(key, _) -> key `notElem` keys && not ("SEIHOU_VAR_" `T.isPrefixOf` T.pack key)) inherited
  (code, out, err) <- readCreateProcessWithExitCode (proc binary args) {cwd = Just (if configured then root </> "project" else root), env = Just environment} ""
  pure (code, T.pack (out <> err))

fixture root = do
  (binary, member) <- prepare root
  TIO.writeFile (member </> "module.dhall") "let S = ./schema/package.dhall in S.Module::{name=\"demo\",version=Some \"1\",steps=[S.Step::{strategy=\"copy\",src=\"starter\",dest=\"value.txt\"}],commands=[S.Command::{action=S.Command.Action.Apply \"printf once >> command-marker\"}]}"
  writeRecipe root "base" "1" "[\"demo\"]" ""
  writeRecipe root "child" "1" "[] : List Text" ", extends = Some {recipe = \"base\"}"
  pure binary

writeRecipe root name version members extra = do
  let dir = root </> ".seihou/modules" </> name
  D.createDirectoryIfMissing True dir
  writeFile (dir </> "recipe.dhall") $ "{name=" <> show name <> ",version=Some " <> show version <> ",description=None Text,modules=" <> members <> ",vars=[] : List {name : Text,type : Text,default : Optional Text,description : Optional Text,required : Bool,validation : Optional Text},prompts=[] : List {var : Text,text : Text,when : Optional Text,choices : Optional (List Text)}" <> extra <> "}"

readManifest root = LBS.fromStrict <$> BS.readFile (root </> ".seihou/manifest.json")

tests :: IO TestTree
tests = testSpec "RecipeExtension" $ do
  it "inspects inherited declarations and literal sources through vars without generation" $
    withSystemTempDirectory "recipe-chain-vars" $ \root -> do
      binary <- fixture root
      let base = root </> ".seihou/modules/base/recipe.dhall"
      body <- TIO.readFile base
      TIO.writeFile base (T.replace "vars=[] : List {name : Text,type : Text,default : Optional Text,description : Optional Text,required : Bool,validation : Optional Text}" "vars=[{name=\"project.owner\",type=\"text\",default=Some \"base\",description=None Text,required=False,validation=None Text}]" body)
      writeRecipe root "child" "1" "[] : List Text" ", extends=Some {recipe=\"base\"},moduleOverrides=[{module=\"demo\",vars=[{name=\"project.owner\",value=\"child\"}]}]"
      declarations <- successful binary root ["vars", "child"]
      declarations `shouldSatisfy` T.isInfixOf "project.owner"
      explained <- successful binary root ["vars", "child", "--explain"]
      explained `shouldSatisfy` T.isInfixOf "literal recipe binding from 'child'"
      explained `shouldSatisfy` T.isInfixOf "project.owner"
      explained `shouldNotSatisfy` T.isInfixOf "Unresolved optional variables:"
      D.doesFileExist (root </> ".seihou/manifest.json") `shouldReturn` False
      D.doesFileExist (root </> "command-marker") `shouldReturn` False

  it "records the chain and refuses base-only downgrades before files, commands or manifest writes" $
    withSystemTempDirectory "recipe-chain-guard" $ \root -> do
      binary <- fixture root
      (code, output) <- invoke binary root []
      if code == ExitSuccess then pure () else expectationFailure (T.unpack output)
      before <- readManifest root
      case Aeson.eitherDecode before :: Either String Aeson.Value of
        Right (Aeson.Object fields) -> do
          KM.lookup "version" fields `shouldBe` Just (Aeson.toJSON (15 :: Int))
          T.pack (show fields) `shouldSatisfy` T.isInfixOf "recipeChain"
          T.pack (show fields) `shouldSatisfy` T.isInfixOf "descriptorHash"
        other -> expectationFailure (show other)
      writeRecipe root "base" "0.9" "[\"demo\"]" ""
      (refused, diagnostic) <- invoke binary root []
      refused `shouldBe` ExitFailure 1
      diagnostic `shouldSatisfy` T.isInfixOf "base"
      readManifest root `shouldReturn` before
      readFile (root </> "command-marker") `shouldReturn` "once"
      (allowed, visible) <- invoke binary root ["--allow-downgrade"]
      allowed `shouldBe` ExitSuccess
      visible `shouldSatisfy` T.isInfixOf "allow-downgrade"
      readFile (root </> "command-marker") `shouldReturn` "onceonce"

  it "previews same-version descriptor changes without writing provenance" $
    withSystemTempDirectory "recipe-chain-digest" $ \root -> do
      binary <- fixture root
      (code, _) <- invoke binary root []
      code `shouldBe` ExitSuccess
      before <- readManifest root
      let descriptor = root </> ".seihou/modules/base/recipe.dhall"
      original <- TIO.readFile descriptor
      TIO.writeFile descriptor (T.replace "description=None Text" "description=Some \"New base description\"" original)
      (previewed, output) <- invoke binary root ["--dry-run"]
      previewed `shouldBe` ExitSuccess
      output `shouldSatisfy` T.isInfixOf "Recipe descriptor changed: base"
      readManifest root `shouldReturn` before
      readFile (root </> "command-marker") `shouldReturn` "once"

  it "prepares old unknown history in memory and adopts it only on an accepted run" $
    withSystemTempDirectory "recipe-chain-adoption" $ \root -> do
      binary <- fixture root
      (code, _) <- invoke binary root []
      code `shouldBe` ExitSuccess
      bytes <- readManifest root
      let Right (Aeson.Object fields) = Aeson.eitherDecode bytes
          withoutChain (Aeson.Object app) = Aeson.Object (KM.delete "recipeChain" app)
          withoutChain other = other
          Just (Aeson.Array apps) = KM.lookup "applications" fields
          legacy = Aeson.Object (KM.insert "version" (Aeson.toJSON (12 :: Int)) (KM.insert "applications" (Aeson.Array (fmap withoutChain apps)) fields))
      LBS.writeFile (root </> ".seihou/manifest.json") (Aeson.encode legacy)
      old <- readManifest root
      (previewed, output) <- invoke binary root ["--dry-run"]
      previewed `shouldBe` ExitSuccess
      output `shouldSatisfy` T.isInfixOf "prior chain is unknown"
      readManifest root `shouldReturn` old
      (accepted, _) <- invoke binary root []
      accepted `shouldBe` ExitSuccess
      adopted <- readManifest root
      adopted `shouldSatisfy` (/= old)

  it "retains generated provenance but no command receipt when a run command fails" $
    withSystemTempDirectory "recipe-chain-command-failure" $ \root -> do
      binary <- fixture root
      let descriptor = root </> ".seihou/modules/demo/module.dhall"
      source <- TIO.readFile descriptor
      TIO.writeFile descriptor (T.replace "printf once >> command-marker" "printf once >> command-marker; exit 1" source)
      (code, _) <- invoke binary root []
      code `shouldBe` ExitFailure 1
      D.doesFileExist (root </> "value.txt") `shouldReturn` True
      readFile (root </> "command-marker") `shouldReturn` "once"
      bytes <- readManifest root
      case Aeson.eitherDecode bytes :: Either String Aeson.Value of
        Right (Aeson.Object fields) -> case KM.lookup "applications" fields of
          Just (Aeson.Array apps) -> forM_ apps $ \case
            Aeson.Object app -> do
              KM.lookup "recipeChain" app `shouldSatisfy` (\value -> value /= Nothing && value /= Just Aeson.Null)
              KM.lookup "commandReceipts" app `shouldSatisfy` (\value -> value == Nothing || value == Just (Aeson.object []))
            other -> expectationFailure (show other)
          other -> expectationFailure (show other)
        other -> expectationFailure (show other)

  it "does not create a manifest directory during preview of a cache-only recipe" $
    withSystemTempDirectory "recipe-chain-no-write" $ \root -> do
      binary <- fixture root
      let cache = root </> "config/seihou/installed"
      D.createDirectoryIfMissing True cache
      forM_ ["base", "child", "demo"] $ \name -> D.renameDirectory (root </> ".seihou/modules" </> name) (cache </> name)
      D.removeDirectory (root </> ".seihou/modules")
      D.removeDirectory (root </> ".seihou")
      (code, output) <- invoke binary root ["--dry-run"]
      if code == ExitSuccess then pure () else expectationFailure (T.unpack output)
      D.doesDirectoryExist (root </> ".seihou") `shouldReturn` False

  it "accepts base-only metadata through ordinary update without rerunning commands, then becomes a no-op" $
    withSystemTempDirectory "recipe-chain-update" $ \root -> do
      binary <- fixture root
      (ran, _) <- invoke binary root []
      ran `shouldBe` ExitSuccess
      before <- readManifest root
      writeRecipe root "base" "1.1" "[\"demo\"]" ""
      (previewed, preview) <- invokeCommand binary root ["update", "child", "--dry-run", "--json"]
      previewed `shouldBe` ExitSuccess
      case Aeson.eitherDecode (LBS.fromStrict (TE.encodeUtf8 preview)) :: Either String Aeson.Value of
        Right (Aeson.Object fields) -> do
          KM.lookup "schemaVersion" fields `shouldBe` Just (Aeson.toJSON (1 :: Int))
          KM.lookup "alreadyUpToDate" fields `shouldBe` Just (Aeson.Bool False)
          KM.lookup "recipeChains" fields `shouldSatisfy` (\case Just (Aeson.Array xs) -> length xs == 1; _ -> False)
          KM.lookup "versions" fields `shouldBe` Just (Aeson.toJSON ([] :: [Aeson.Value]))
        other -> expectationFailure (show other)
      readManifest root `shouldReturn` before
      readFile (root </> "command-marker") `shouldReturn` "once"
      (eof, _) <- invokeCommand binary root ["update", "child"]
      eof `shouldBe` ExitSuccess
      readManifest root `shouldReturn` before
      (accepted, output) <- invokeCommand binary root ["update", "child", "--json"]
      if accepted == ExitSuccess then pure () else expectationFailure (T.unpack output)
      readManifest root >>= (`shouldSatisfy` (/= before))
      readFile (root </> "command-marker") `shouldReturn` "once"
      (repeated, unchanged) <- invokeCommand binary root ["update", "child", "--dry-run"]
      repeated `shouldBe` ExitSuccess
      unchanged `shouldSatisfy` T.isInfixOf "Already up to date"

  it "updates a local recipe with read-only definitions and schema payloads without changing the originals" $
    withSystemTempDirectory "recipe-chain-read-only" $ \root -> do
      binary <- fixture root
      let files = [root </> ".seihou/modules/demo/module.dhall", root </> ".seihou/modules/demo/schema/Migration.dhall"]
      forM_ files $ \file -> D.getPermissions file >>= D.setPermissions file . D.setOwnerWritable False
      permissions <- mapM D.getPermissions files
      before <- mapM BS.readFile files
      _ <- successful binary root ["run", "child"]
      writeRecipe root "base" "1.1" "[\"demo\"]" ""
      _ <- successful binary root ["update", "child", "--json"]
      mapM D.getPermissions files `shouldReturn` permissions
      mapM BS.readFile files `shouldReturn` before
      readFile (root </> "command-marker") `shouldReturn` "once"

  it "adopts unknown recipe history through update only on acceptance" $
    withSystemTempDirectory "recipe-chain-update-adopt" $ \root -> do
      binary <- fixture root
      (ran, _) <- invoke binary root []
      ran `shouldBe` ExitSuccess
      bytes <- readManifest root
      let Right (Aeson.Object fields) = Aeson.eitherDecode bytes
          withoutChain (Aeson.Object app) = Aeson.Object (KM.delete "recipeChain" app)
          withoutChain other = other
          Just (Aeson.Array apps) = KM.lookup "applications" fields
          legacy = Aeson.Object (KM.insert "version" (Aeson.toJSON (12 :: Int)) (KM.insert "applications" (Aeson.Array (fmap withoutChain apps)) fields))
      LBS.writeFile (root </> ".seihou/manifest.json") (Aeson.encode legacy)
      old <- readManifest root
      (previewed, output) <- invokeCommand binary root ["update", "child", "--dry-run"]
      previewed `shouldBe` ExitSuccess
      output `shouldSatisfy` T.isInfixOf "prior chain is unknown"
      readManifest root `shouldReturn` old
      (accepted, applied) <- invokeCommand binary root ["update", "child", "--json"]
      if accepted == ExitSuccess then pure () else expectationFailure (T.unpack applied)
      readManifest root >>= (`shouldSatisfy` (/= old))
      readFile (root </> "command-marker") `shouldReturn` "once"

  it "guards a downgraded base during update before commands or publication" $
    withSystemTempDirectory "recipe-chain-update-guard" $ \root -> do
      binary <- fixture root
      (ran, _) <- invoke binary root []
      ran `shouldBe` ExitSuccess
      before <- readManifest root
      writeRecipe root "base" "0.9" "[\"demo\"]" ""
      (refused, output) <- invokeCommand binary root ["update", "child", "--json"]
      refused `shouldBe` ExitFailure 1
      output `shouldSatisfy` T.isInfixOf "base"
      readManifest root `shouldReturn` before
      readFile (root </> "command-marker") `shouldReturn` "once"
      (allowed, preview) <- invokeCommand binary root ["update", "child", "--allow-downgrade", "--dry-run"]
      allowed `shouldBe` ExitSuccess
      preview `shouldSatisfy` T.isInfixOf "allow-downgrade"

  it "rolls recipe-chain evidence and generated files back after a changed command fails" $
    withSystemTempDirectory "recipe-chain-update-failure" $ \root -> do
      binary <- fixture root
      (ran, _) <- invoke binary root []
      ran `shouldBe` ExitSuccess
      before <- readManifest root
      fileBefore <- readFile (root </> "value.txt")
      writeRecipe root "base" "1.1" "[\"demo\"]" ""
      let path = root </> ".seihou/modules/demo/module.dhall"
      body <- TIO.readFile path
      TIO.writeFile path (T.replace "printf once >> command-marker" "exit 7" body)
      (failed, output) <- invokeCommand binary root ["update", "child", "--json"]
      failed `shouldBe` ExitFailure 1
      output `shouldSatisfy` T.isInfixOf "command_failed"
      readManifest root `shouldReturn` before
      readFile (root </> "value.txt") `shouldReturn` fileBefore
      readFile (root </> "command-marker") `shouldReturn` "once"

  it "refreshes an unchanged recipe's base closure once, preserves previews, and replays from an empty cache" $
    withSystemTempDirectory "recipe-chain-remote" $ \root -> do
      binary <- remoteFixture root
      _ <- successful binary root ["install", remoteUrl "child", "--module", "child"]
      _ <- successful binary root ["run", "child"]
      before <- readManifest (root </> "project")
      let installed = root </> "config/seihou/installed"
      oldBase <- BS.readFile (installed </> "base/recipe.dhall")
      writeRemoteRecipe root "base" "1.1" ("[ {module=\"demo\",source=Some \"" <> remoteUrl "demo" <> "\",vars=[] : List {name : Text,value : Text}} ]") ""
      commitRemote root "base"
      preview <- successful binary root ["upgrade", "child", "demo", "--dry-run", "--json"]
      case Aeson.eitherDecode (LBS.fromStrict (TE.encodeUtf8 preview)) :: Either String Aeson.Value of
        Right (Aeson.Array entries) -> length entries `shouldBe` 3
        other -> expectationFailure (show other)
      readManifest (root </> "project") `shouldReturn` before
      BS.readFile (installed </> "base/recipe.dhall") `shouldReturn` oldBase
      allRoots <- successful binary root ["upgrade", "--dry-run", "--json"]
      case Aeson.eitherDecode (LBS.fromStrict (TE.encodeUtf8 allRoots)) :: Either String Aeson.Value of
        Right (Aeson.Array entries) -> length entries `shouldBe` 3
        other -> expectationFailure (show other)
      _ <- successful binary root ["upgrade", "child", "--json"]
      readManifest (root </> "project") `shouldReturn` before
      BS.readFile (installed </> "base/recipe.dhall") >>= (`shouldSatisfy` (/= oldBase))
      updated <- successful binary root ["update", "child", "--json"]
      updated `shouldSatisfy` T.isInfixOf "skippedUnchanged"
      readFile (root </> "project/command-marker") `shouldReturn` "once"
      unchanged <- successful binary root ["update", "child", "--dry-run"]
      unchanged `shouldSatisfy` T.isInfixOf "Already up to date"
      D.removePathForcibly installed
      _ <- successful binary root ["update", "child", "--json"]
      -- Cache reconstruction is published as part of the accepted update.
      D.doesFileExist (installed </> "base/recipe.dhall") `shouldReturn` True
      readFile (root </> "project/command-marker") `shouldReturn` "once"

  it "acquires new external bases and members without fetching a removed base" $
    withSystemTempDirectory "recipe-chain-reparent" $ \root -> do
      binary <- remoteFixture root
      _ <- successful binary root ["install", remoteUrl "child", "--module", "child"]
      _ <- successful binary root ["run", "child"]
      let producers = root </> "producers"
      D.renameDirectory (producers </> "base") (producers </> "unavailable-base")
      D.renameDirectory (producers </> "demo") (producers </> "fresh")
      let path = producers </> "fresh/module.dhall"
      body <- TIO.readFile path
      TIO.writeFile path (T.replace "name=\"demo\"" "name=\"fresh\"" (T.replace "dest=\"value.txt\"" "dest=\"fresh.txt\"" body))
      commitRemote root "fresh"
      writeRemoteRecipe root "next-base" "1" ("[ {module=\"fresh\",source=Some \"" <> remoteUrl "fresh" <> "\",vars=[] : List {name : Text,value : Text}} ]") ""
      initRemote root "next-base"
      writeRemoteRecipe root "child" "1" "[] : List Text" (", extends=Some {recipe=\"next-base\",source=Some \"" <> remoteUrl "next-base" <> "\"}")
      commitRemote root "child"
      preview <- successful binary root ["update", "child", "--dry-run"]
      preview `shouldSatisfy` T.isInfixOf "next-base"
      _ <- successful binary root ["update", "child", "--json"]
      D.doesFileExist (root </> "project/fresh.txt") `shouldReturn` True
      D.doesFileExist (root </> "project/value.txt") `shouldReturn` False
      unchanged <- successful binary root ["update", "child", "--dry-run"]
      unchanged `shouldSatisfy` T.isInfixOf "Already up to date"

  it "refuses an out-of-range base during update and upgrade even with the application downgrade override" $
    withSystemTempDirectory "recipe-chain-range-update" $ \root -> do
      binary <- remoteFixture root
      _ <- successful binary root ["install", remoteUrl "child", "--module", "child"]
      _ <- successful binary root ["run", "child"]
      before <- readManifest (root </> "project")
      let installed = root </> "config/seihou/installed/base/recipe.dhall"
      cached <- BS.readFile installed
      writeRemoteRecipe root "base" "2" ("[ {module=\"demo\",source=Some \"" <> remoteUrl "demo" <> "\",vars=[] : List {name : Text,value : Text}} ]") ""
      commitRemote root "base"
      forM_ [["update", "child", "--allow-downgrade", "--json"], ["upgrade", "child", "--json"]] $ \args -> do
        (code, output) <- invokeCommand binary root args
        code `shouldBe` ExitFailure 1
        output `shouldSatisfy` T.isInfixOf "base"
        readManifest (root </> "project") `shouldReturn` before
        BS.readFile installed `shouldReturn` cached
        readFile (root </> "project/command-marker") `shouldReturn` "once"

  it "keeps a recipe refresh together when skip-unversioned excludes a changed recipe" $
    withSystemTempDirectory "recipe-chain-upgrade-skip" $ \root -> do
      binary <- remoteFixture root
      _ <- successful binary root ["install", remoteUrl "child", "--module", "child"]
      let cached = root </> "config/seihou/installed/child/recipe.dhall"
      before <- BS.readFile cached
      let descriptor = root </> "producers/child/recipe.dhall"
      body <- TIO.readFile descriptor
      TIO.writeFile descriptor (T.replace "version=Some \"1\"" "version=None Text" body)
      commitRemote root "child"
      output <- successful binary root ["upgrade", "child", "--skip-unversioned", "--json"]
      output `shouldSatisfy` T.isInfixOf "skipped"
      BS.readFile cached `shouldReturn` before
      D.doesFileExist (root </> "project/.seihou/manifest.json") `shouldReturn` False

  it "refuses a same-name base substitution before cache or project publication" $
    withSystemTempDirectory "recipe-chain-update-substitution" $ \root -> do
      binary <- remoteFixture root
      _ <- successful binary root ["install", remoteUrl "child", "--module", "child"]
      _ <- successful binary root ["run", "child"]
      before <- readManifest (root </> "project")
      cached <- BS.readFile (root </> "config/seihou/installed/base/recipe.dhall")
      let replacement = root </> "producers/replacement"
      callProcess "git" ["clone", "-q", root </> "producers/base", replacement]
      appendFile (root </> "fixture-gitconfig") ("[url \"file://" <> replacement <> "\"]\n    insteadOf = " <> remoteUrl "replacement" <> "\n")
      writeRemoteRecipe root "child" "1" "[] : List Text" (", extends=Some {recipe=\"base\",source=Some \"" <> remoteUrl "replacement" <> "\"}")
      commitRemote root "child"
      (code, output) <- invokeCommand binary root ["update", "child", "--json"]
      code `shouldBe` ExitFailure 1
      output `shouldSatisfy` T.isInfixOf "different source"
      readManifest (root </> "project") `shouldReturn` before
      BS.readFile (root </> "config/seihou/installed/base/recipe.dhall") `shouldReturn` cached

  it "rejects a base descriptor edited after the update preview without publishing" $
    withSystemTempDirectory "recipe-chain-stale-update" $ \root -> do
      binary <- fixture root
      _ <- successful binary root ["run", "child"]
      before <- readManifest root
      writeRecipe root "base" "1.1" "[\"demo\"]" ""
      let request = U.UpdateRequest (U.NamedUpdateTargets ["child"]) [] False U.ForbidPrompts RunChangedCommands False False False
      let environmentKeys = ["XDG_CONFIG_HOME", "XDG_CACHE_HOME"]
      result <- bracket (mapM lookupEnv environmentKeys) (\previous -> forM_ (zip environmentKeys previous) $ \(key, value) -> maybe (unsetEnv key) (setEnv key) value) $ \_ -> do
        setEnv "XDG_CONFIG_HOME" (root </> "config")
        setEnv "XDG_CACHE_HOME" (root </> "cache")
        D.withCurrentDirectory root $ U.withProjectUpdate request $ \case
          Left err -> pure (Left err)
          Right plan -> do
            let Just base = find ((== "base") . (^. #name)) (plan ^. #candidateArtifacts)
            TIO.appendFile (base ^. #originalDirectory </> "recipe.dhall") "\n-- changed after preview\n"
            U.applyProjectUpdate plan
      result `shouldSatisfy` (\case Left UpdatePlanStale {} -> True; _ -> False)
      readManifest root `shouldReturn` before
      readFile (root </> "command-marker") `shouldReturn` "once"

successful binary root args = do
  (code, output) <- invokeCommand binary root args
  if code == ExitSuccess then pure () else expectationFailure (T.unpack output)
  pure output

remoteUrl name = "https://example.invalid/" <> name <> ".git"

writeRemoteRecipe root name version members extra = do
  writeRecipe root name version members extra
  let target = root </> "producers" </> name
  D.createDirectoryIfMissing True target
  D.renameFile (root </> ".seihou/modules" </> name </> "recipe.dhall") (target </> "recipe.dhall")

commitRemote root name = do
  let repo = root </> "producers" </> name
  callProcess "git" ["-C", repo, "add", "."]
  callProcess "git" ["-C", repo, "-c", "user.name=Seihou Test", "-c", "user.email=test@example.invalid", "commit", "--allow-empty", "-qm", "test: recipe candidate"]

initRemote root name = do
  callProcess "git" ["-C", root </> "producers" </> name, "init", "-q"]
  commitRemote root name

remoteFixture root = do
  binary <- fixture root
  let producers = root </> "producers"
  D.createDirectory producers
  D.createDirectory (root </> "project")
  D.renameDirectory (root </> ".seihou/modules/demo") (producers </> "demo")
  writeRemoteRecipe root "base" "1" ("[ {module=\"demo\",source=Some \"" <> remoteUrl "demo" <> "\",vars=[] : List {name : Text,value : Text}} ]") ""
  writeRemoteRecipe root "child" "1" "[] : List Text" (", extends=Some {recipe=\"base\",source=Some \"" <> remoteUrl "base" <> "\",versionRange=Some {minimum=\"1\",before=\"2\"}}")
  forM_ ["demo", "base", "child"] (initRemote root)
  -- Every URL remains portable in descriptors and manifest; only this test
  -- process's transport routes to committed fixture producers.
  -- Directory names have no .git suffix, so use one explicit rewrite per URL.
  writeFile (root </> "fixture-gitconfig") $ concat ["[url \"file://" <> producers </> name <> "\"]\n    insteadOf = " <> remoteUrl name <> "\n" | name <- ["demo", "base", "child", "fresh", "next-base"]]
  pure binary
