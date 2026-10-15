module Seihou.Engine.CheckoutSpec (tests) where

import Control.Monad (forM_, when)
import Data.ByteString.Lazy qualified as LBS
import Data.Either (isLeft)
import Data.Generics.Labels ()
import Data.IORef
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Data.Time (UTCTime (..), fromGregorian)
import Seihou.Core.Checkout
import Seihou.Core.Module (checkFileExistence, validateModule)
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalModuleFromFile)
import Seihou.Effect.Filesystem
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.Process
import Seihou.Effect.ProcessInterp (runProcessIO)
import Seihou.Engine.Checkout
import Seihou.Engine.Plan (compilePlan)
import Seihou.Engine.Remove (CheckoutRemovalSelection (..), selectCheckoutRemoval)
import Seihou.Manifest.Types
import Seihou.Prelude
import System.Directory qualified as D
import System.Exit (ExitCode (..))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

fixtureManifest :: Manifest
fixtureManifest = emptyManifest now & #applications .~ [app] & #checkoutOutputs .~ Map.fromList [(dest, record source) | (dest, source) <- [(".local/config", "config/editor"), (".tool/assets", "assets/shared")]]
  where
    now = UTCTime (fromGregorian 2026 10 15) 0
    app = AppliedComposition (ApplicationId "a") (AppliedModuleTarget "demo") (LocalOrigin "demo") (Just "1") [] Nothing Nothing [AppliedInstanceState "demo" emptyParentVars (LocalOrigin "demo") (Just "1") Map.empty] Map.empty now
    record source = CheckoutOutputRecord (DirectorySymlink source) (Map.singleton (ApplicationId "a") (Set.singleton "demo"))

withFixture :: (FilePath -> IO a) -> IO a
withFixture action = withSystemTempDirectory "checkout-contract" $ \temp -> do
  root <- D.canonicalizePath temp
  (code, _, _) <- readProcessWithExitCode "git" ["-C", root, "init", "-q"] ""
  code `shouldBe` ExitSuccess
  forM_ ["config/editor", "assets/shared"] (D.createDirectoryIfMissing True . (root </>))
  TIO.writeFile (root </> ".gitignore") ".local/\n.tool/\n"
  TIO.writeFile (root </> "config/editor/settings") "sentinel"
  action root

prepare root intent old new = runEff $ runFilesystem $ runProcessIO $ prepareCheckoutPlan intent SyncIgnoredOnly root old new []

apply root plan = runEff $ runFilesystem $ runProcessIO $ applyCheckoutPlan SyncIgnoredOnly root plan

tests :: IO TestTree
tests = testSpec "checkout filesystem contract" $ do
  it "requires application selection for ambiguous owners and preserves unselected claims" $ do
    let [app] = fixtureManifest ^. #applications
        second = app & #applicationId .~ ApplicationId "b"
        shared = fixtureManifest & #applications .~ [app, second] & #checkoutOutputs %~ Map.map (#owners %~ Map.insert (ApplicationId "b") (Set.singleton "demo"))
    selectCheckoutRemoval shared "demo" Nothing `shouldSatisfy` isLeft
    Right (Just selected) <- pure (selectCheckoutRemoval shared "demo" (Just (ApplicationId "a")))
    let retained = selected ^. #candidateManifest
    map (^. #applicationId) (retained ^. #applications) `shouldBe` [ApplicationId "b"]
    map (Map.keys . (^. #owners)) (Map.elems (retained ^. #checkoutOutputs)) `shouldBe` [[ApplicationId "b"], [ApplicationId "b"]]
  it "rejects native spelling aliases when the temporary volume is case-insensitive" $ withFixture $ \root -> do
    insensitive <- D.doesDirectoryExist (root </> ".GIT")
    when insensitive $ do
      let aliased = fixtureManifest & #checkoutOutputs %~ Map.adjust (#spec .~ DirectorySymlink "config/Editor") ".local/config"
      Right plan <- prepare root Rebuild aliased aliased
      checkoutApplicable plan `shouldBe` False
      concatMap (map (^. #code) . (^. #errors)) (plan ^. #entries) `shouldContain` ["checkout_native_alias"]
  it "compiles project sources without an installed files source and validates rendered paths" $ withFixture $ \root -> do
    let modul = Module "demo" (Just "1.0.0") Nothing [VarDecl "source" VTText Nothing Nothing True Nothing] [] [] [Step Symlink "{{source}}" ".local/config" Nothing Nothing Checkout] [] [] Nothing []
    checkFileExistence root modul `shouldReturn` []
    compiled <- compilePlan root modul (Map.singleton "source" (VText "config/editor"))
    compiled `shouldBe` Right [CheckoutOutputOp ".local/config" (DirectorySymlink "config/editor") "demo"]
    escaped <- compilePlan root modul (Map.singleton "source" (VText "../outside"))
    escaped `shouldSatisfy` isLeft
    invalid <- validateModule root (modul & #steps %~ map (#lifecycle .~ Managed))
    invalid `shouldSatisfy` isLeft
    skipped <- compilePlan root (modul & #steps %~ map (#condition ?~ ExprLit False)) Map.empty
    skipped `shouldBe` Right []
  it "traces only declared link writes and parent creation, with fixed read-only Git calls" $ withFixture $ \root -> do
    Right plan <- prepare root Rebuild fixtureManifest fixtureManifest
    writes <- newIORef []
    processes <- newIORef []
    applied <- runEff $ tracedFilesystem writes $ tracedProcess processes $ applyCheckoutPlan SyncIgnoredOnly root plan
    applied ^. #failure `shouldBe` Nothing
    actualWrites <- readIORef writes
    Set.fromList actualWrites `shouldBe` Set.fromList [("mkdir", root </> ".local"), ("mkdir", root </> ".tool"), ("link", root </> ".local/config"), ("link", root </> ".tool/assets")]
    actualProcesses <- readIORef processes
    actualProcesses
      `shouldSatisfy` all
        ( \(cmd, args) ->
            cmd == "git" && case args of
              ["rev-parse", "--show-toplevel"] -> True
              ["ls-files", "--cached", "-z"] -> True
              ["check-ignore", "-q", "--", path] -> "./" `T.isPrefixOf` path
              _ -> False
        )
  it "creates portable links and converges without following their contents" $ withFixture $ \root -> do
    Right plan <- prepare root Rebuild fixtureManifest fixtureManifest
    map (^. #action) (plan ^. #entries) `shouldBe` [CreateLink, CreateLink]
    result <- apply root plan
    result ^. #failure `shouldBe` Nothing
    D.getSymbolicLinkTarget (root </> ".local/config") `shouldReturn` "../config/editor"
    TIO.readFile (root </> "config/editor/settings") `shouldReturn` "sentinel"
    Right repeated <- prepare root Rebuild fixtureManifest fixtureManifest
    map (^. #action) (repeated ^. #entries) `shouldBe` [UnchangedLink, UnchangedLink]
  it "repairs dangling wrong links and leaves sentinel target bytes alone" $ withFixture $ \root -> do
    D.createDirectoryIfMissing True (root </> ".local")
    D.createDirectoryLink "../missing" (root </> ".local/config")
    Right plan <- prepare root Rebuild fixtureManifest fixtureManifest
    map (^. #action) (plan ^. #entries) `shouldBe` [ReplaceLink, CreateLink]
    result <- apply root plan
    result ^. #failure `shouldBe` Nothing
  it "refuses every mutation when any destination is a real object" $ withFixture $ \root -> do
    D.createDirectoryIfMissing True (root </> ".local/config")
    TIO.writeFile (root </> ".local/config/sentinel") "keep"
    Right plan <- prepare root Rebuild fixtureManifest fixtureManifest
    checkoutApplicable plan `shouldBe` False
    result <- apply root plan
    result ^. #failure `shouldSatisfy` isJust
    D.doesPathExist (root </> ".tool") `shouldReturn` False
    TIO.readFile (root </> ".local/config/sentinel") `shouldReturn` "keep"
  it "refuses symlink ancestors and missing sources" $ withFixture $ \root -> do
    D.createDirectoryLink "assets" (root </> ".local")
    Right plan <- prepare root Rebuild fixtureManifest fixtureManifest
    checkoutApplicable plan `shouldBe` False
    D.removeDirectoryLink (root </> ".local")
    D.removeDirectory (root </> "assets/shared")
    Right missing <- prepare root Rebuild fixtureManifest fixtureManifest
    checkoutApplicable missing `shouldBe` False
  it "protects ignored tracked paths even when absent on disk" $ withFixture $ \root -> do
    D.createDirectoryIfMissing True (root </> ".local")
    TIO.writeFile (root </> ".local/config") "tracked"
    (code, _, _) <- readProcessWithExitCode "git" ["-C", root, "add", "-f", "--", ".local/config"] ""
    code `shouldBe` ExitSuccess
    D.removeFile (root </> ".local/config")
    Right plan <- prepare root Rebuild fixtureManifest fixtureManifest
    checkoutApplicable plan `shouldBe` False
    concatMap (map (^. #code) . (^. #errors)) (plan ^. #entries) `shouldContain` ["checkout_path_tracked"]
  it "reports unsupported symlink creation without copying source data" $ withFixture $ \root -> do
    Right plan <- prepare root Rebuild fixtureManifest fixtureManifest
    result <- runEff $ unsupportedLinks $ runProcessIO $ applyCheckoutPlan SyncIgnoredOnly root plan
    result ^. #failure `shouldSatisfy` isJust
    case result ^. #failure of
      Just err -> err ^. #message `shouldSatisfy` T.isInfixOf "symlink permissions"
      Nothing -> expectationFailure "expected a creation error"
    D.doesPathExist (root </> ".local") `shouldReturn` False
    TIO.readFile (root </> "config/editor/settings") `shouldReturn` "sentinel"
  it "rolls back an ordinary mid-apply failure and supports retry" $ withFixture $ \root -> do
    Right plan <- prepare root Rebuild fixtureManifest fixtureManifest
    result <- runEff $ runFilesystem $ runProcessIO $ applyCheckoutPlanWithHook (\n -> when (n == 1) (liftIO (ioError (userError "injected")))) SyncIgnoredOnly root plan
    result ^. #failure `shouldSatisfy` isJust
    D.doesPathExist (root </> ".local") `shouldReturn` False
    retried <- apply root plan
    retried ^. #failure `shouldBe` Nothing
  it "retires a dangling last-owner link without checking its source" $ withFixture $ \root -> do
    Right first <- prepare root Rebuild fixtureManifest fixtureManifest
    _ <- apply root first
    D.removeFile (root </> "config/editor/settings")
    D.removeDirectory (root </> "config/editor")
    let candidate = fixtureManifest & #checkoutOutputs %~ Map.delete ".local/config"
    Right retired <- prepare root Reconcile fixtureManifest candidate
    map (^. #action) (retired ^. #entries) `shouldBe` [RetireLink, UnchangedLink]
    result <- apply root retired
    result ^. #failure `shouldBe` Nothing
    D.pathIsSymbolicLink (root </> ".tool/assets") `shouldReturn` True
  it "rejects unknown specs and bad owners at the byte decoding boundary" $ do
    let bytes = manifestToJSON fixtureManifest
    manifestFromJSON bytes `shouldBe` Right fixtureManifest
    manifestFromJSON (replace "directory-symlink" "invented-kind" bytes) `shouldSatisfy` isLeft
    manifestFromJSON (manifestToJSON (fixtureManifest & #applications .~ [])) `shouldSatisfy` isLeft
  where
    replace a b = LBS.fromStrict . TE.encodeUtf8 . T.replace a b . TE.decodeUtf8 . LBS.toStrict

-- These first-order effects can be reissued in an isolated real interpreter.
-- The trace fails on any text read/write, copy, rename or recursive removal.
tracedFilesystem :: (IOE :> es) => IORef [(Text, FilePath)] -> Eff (Filesystem : es) a -> Eff es a
tracedFilesystem trace = interpret $ \_ operation -> do
  case operation of
    CreateDirectoryIfMissing _ path -> liftIO (modifyIORef' trace (("mkdir", path) :))
    CreateDirectoryLink _ path -> liftIO (modifyIORef' trace (("link", path) :))
    RemoveLink path -> liftIO (modifyIORef' trace (("unlink", path) :))
    InspectPath _ -> pure ()
    ListDirectory _ -> pure ()
    NormalizePath _ -> pure ()
    _ -> liftIO (ioError (userError "checkout attempted an unexpected filesystem effect"))
  liftIO $ runEff $ runFilesystem $ reissue operation

reissue :: Filesystem m a -> Eff '[Filesystem, IOE] a
reissue (CreateDirectoryIfMissing parents path) = createDirectoryIfMissing parents path
reissue (CreateDirectoryLink target path) = createLink target path
reissue (RemoveLink path) = removeLink path
reissue (InspectPath path) = inspectPath path
reissue (ListDirectory path) = listDirectory path
reissue (NormalizePath path) = normalizePath path
reissue (RemoveDirectoryIfEmpty path) = removeDirectoryIfEmpty path
reissue _ = liftIO (ioError (userError "unexpected filesystem effect"))

tracedProcess :: (IOE :> es) => IORef [(Text, [Text])] -> Eff (Process : es) a -> Eff es a
tracedProcess trace = interpret $ \_ (RunProcess cmd args root) -> do
  liftIO (modifyIORef' trace ((cmd, args) :))
  liftIO $ runEff $ runProcessIO $ runProcess cmd args root

unsupportedLinks :: (IOE :> es) => Eff (Filesystem : es) a -> Eff es a
unsupportedLinks = interpret $ \_ operation -> case operation of
  CreateDirectoryLink _ _ -> liftIO (ioError (userError "symlink creation unsupported"))
  _ -> liftIO $ runEff $ runFilesystem $ reissue operation
