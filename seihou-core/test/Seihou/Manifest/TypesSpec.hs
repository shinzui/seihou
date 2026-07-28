module Seihou.Manifest.TypesSpec (tests) where

import Control.Lens ((%~), (&), (.~), (^.))
import Control.Monad (forM_)
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy.Char8 qualified as LBS8
import Data.Foldable (toList)
import Data.Generics.Labels ()
import Data.List (isInfixOf)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Seihou.Core.Types
import Seihou.Manifest.Hash (hashContent)
import Seihou.Manifest.Types
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Manifest.Types" spec

-- Helper to create a fixed timestamp for testing.
fixedTime :: UTCTime
fixedTime = parseTimeOrError True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" "2026-03-01T10:30:00Z"

fixedTime2 :: UTCTime
fixedTime2 = parseTimeOrError True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" "2026-03-01T11:00:00Z"

mkBlueprintMigrationReceipt :: T.Text -> T.Text -> T.Text -> UTCTime -> AppliedBlueprintMigration
mkBlueprintMigrationReceipt blueprintName fromVersion toVersion appliedAt =
  AppliedBlueprintMigration
    { name = ModuleName blueprintName,
      blueprintVersion = Just "0.4.0",
      fromVersion = fromVersion,
      toVersion = toVersion,
      appliedAt = appliedAt,
      agentSessionId = Nothing
    }

-- | Helper to set modules on a Manifest without ambiguous record update.
withManifestModules :: [AppliedModule] -> Manifest -> Manifest
withManifestModules mods m =
  Manifest (m ^. #version) (m ^. #genAt) mods (m ^. #vars) (m ^. #files) (m ^. #applications) (m ^. #recipe) (m ^. #blueprint) (m ^. #blueprintMigrations)

-- | Every string that appears anywhere inside a value keyed @origin@ or
-- @targetOrigin@, at any depth.
originStrings :: Aeson.Value -> [T.Text]
originStrings = go False
  where
    go inOrigin value = case value of
      Aeson.Object object ->
        concat
          [ go (inOrigin || Key.toText key `elem` (["origin", "targetOrigin"] :: [T.Text])) child
          | (key, child) <- KeyMap.toList object
          ]
      Aeson.Array items -> concatMap (go inOrigin) (toList items)
      Aeson.String text -> [text | inOrigin]
      _ -> []

-- | A manifest exercising every serialized origin position at once.
manifestWithEveryOriginPosition :: Manifest
manifestWithEveryOriginPosition =
  (emptyManifest fixedTime)
    & #modules
      .~ [ AppliedModule
             { name = ModuleName "haskell-base",
               parentVars = emptyParentVars,
               origin = RemoteOrigin "https://github.com/shinzui/seihou-modules.git" "haskell-base" (Just "seihou-modules"),
               moduleVersion = Just "1.4.0",
               appliedAt = fixedTime,
               removal = Nothing
             }
         ]
    & #applications
      .~ [ AppliedComposition
             { applicationId = ApplicationId "app",
               target = AppliedModuleTarget (ModuleName "haskell-base"),
               targetOrigin = RemoteOrigin "https://github.com/shinzui/seihou-modules.git" "haskell-base" (Just "seihou-modules"),
               targetVersion = Just "1.4.0",
               additionalModules = [],
               namespace = Nothing,
               context = Nothing,
               instances =
                 [ AppliedInstanceState
                     { name = ModuleName "docs",
                       parentVars = emptyParentVars,
                       origin = ProjectOrigin ".seihou/modules/docs",
                       moduleVersion = Just "0.1.0",
                       resolvedVars = Map.empty
                     },
                   AppliedInstanceState
                     { name = ModuleName "scratch",
                       parentVars = emptyParentVars,
                       origin = LocalOrigin "scratch",
                       moduleVersion = Nothing,
                       resolvedVars = Map.empty
                     }
                 ],
               commandReceipts = Map.empty,
               appliedAt = fixedTime
             }
         ]

-- | A manifest populated in every serialized position that can hold a string,
-- so the machine-independence sweep has something to sweep.
--
-- Deliberately broader than 'manifestWithEveryOriginPosition': that one proves
-- the origin fields are portable, this one proves nothing /else/ smuggles a
-- path in — a file record and its baseline, a command receipt with a working
-- directory, a removal spec, an applied recipe, an applied blueprint, and a
-- blueprint migration receipt.
manifestWithEveryStringPosition :: Manifest
manifestWithEveryStringPosition =
  manifestWithEveryOriginPosition
    & #modules
      .~ [ AppliedModule
             { name = ModuleName "haskell-base",
               parentVars = ParentVars (Map.singleton (VarName "project.name") "demo"),
               origin = RemoteOrigin "https://github.com/shinzui/seihou-modules.git" "haskell-base" (Just "seihou-modules"),
               moduleVersion = Just "1.4.0",
               appliedAt = fixedTime,
               removal =
                 Just
                   ( Removal
                       [RemovalStep RemoveFileAction "flake.nix" (Just "files/flake.nix")]
                       [Command "cabal clean" (Just "backend") Nothing]
                   )
             }
         ]
    & #vars .~ Map.singleton (VarName "project.name") "demo"
    & #files
      .~ Map.singleton
        "backend/flake.nix"
        ( FileRecord
            (hashContent "flake")
            (ModuleName "haskell-base")
            DhallText
            fixedTime
            (Just (BaselineRef (hashContent "flake")))
            (Set.singleton (ApplicationId "app"))
        )
    & #applications
      %~ map (withCommandReceipts (Map.singleton receiptFingerprint receipt))
    & #recipe .~ Just (AppliedRecipe (RecipeName "haskell-service") (Just "3.1.0") fixedTime)
    & #blueprint
      .~ Just
        ( AppliedBlueprint
            { name = ModuleName "service-blueprint",
              blueprintVersion = Just "2.0.0",
              appliedAt = fixedTime,
              baselineModules = [ModuleName "haskell-base"],
              noBaseline = False,
              userPrompt = Just "build a service",
              agentSessionId = Just "session-abc"
            }
        )
    & #blueprintMigrations .~ [mkBlueprintMigrationReceipt "service-blueprint" "1.0.0" "2.0.0" fixedTime2]
  where
    receiptFingerprint = CommandFingerprint (hashContent "cabal build")
    receipt = CommandReceipt receiptFingerprint (ModuleName "haskell-base") "cabal build" (Just "backend") fixedTime

-- | Set an application's command receipts without record update syntax.
withCommandReceipts :: Map.Map CommandFingerprint CommandReceipt -> AppliedComposition -> AppliedComposition
withCommandReceipts receipts composition =
  AppliedComposition
    { applicationId = composition ^. #applicationId,
      target = composition ^. #target,
      targetOrigin = composition ^. #targetOrigin,
      targetVersion = composition ^. #targetVersion,
      additionalModules = composition ^. #additionalModules,
      namespace = composition ^. #namespace,
      context = composition ^. #context,
      instances = composition ^. #instances,
      commandReceipts = receipts,
      appliedAt = composition ^. #appliedAt
    }

-- | Every string in a document, each paired with the JSON path that reaches
-- it, so a failure can say /where/ the offending value was.
--
-- Object keys are reported too: the @files@ map is keyed by destination path,
-- which is exactly the sort of place an absolute path could reappear.
documentStrings :: Aeson.Value -> [(String, T.Text)]
documentStrings = go "$"
  where
    go path value = case value of
      Aeson.Object object ->
        concat
          [ (path <> "." <> T.unpack (Key.toText key), Key.toText key)
              : go (path <> "." <> T.unpack (Key.toText key)) child
          | (key, child) <- KeyMap.toList object
          ]
      Aeson.Array items ->
        concat [go (path <> "[" <> show index <> "]") item | (index, item) <- zip [(0 :: Int) ..] (toList items)]
      Aeson.String text -> [(path, text)]
      _ -> []

-- | Whether a string only means something on the machine that wrote it: a
-- POSIX absolute path, a home-relative path, a UNC share, or a Windows drive
-- prefix.
machineSpecific :: T.Text -> Bool
machineSpecific text =
  T.isPrefixOf "/" text
    || T.isPrefixOf "~" text
    || T.isPrefixOf "\\\\" text
    || (T.length text >= 3 && T.index text 1 == ':' && T.index text 2 == '\\')

spec :: Spec
spec = do
  -- The manifest is checked into version control and read on other machines,
  -- so no origin it records may name a location that only exists on the
  -- machine that wrote it. See
  -- docs/adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md.
  describe "machine independence" $ do
    -- The two specs below constrain the origin fields. This one constrains
    -- every future field as well: a new manifest field that records a location
    -- has to express it relative to the project root or through an
    -- ArtifactOrigin, and this fails if one does neither.
    it "records no machine-specific value anywhere in the document" $ do
      let encoded = Aeson.toJSON manifestWithEveryStringPosition
          scanned = documentStrings encoded
          offenders =
            [ path <> " = " <> T.unpack text
            | (path, text) <- scanned,
              machineSpecific text
            ]
      length scanned `shouldSatisfy` (> 20)
      offenders `shouldBe` []

    it "records no absolute path in any origin position" $ do
      let encoded = Aeson.toJSON manifestWithEveryOriginPosition
          strings = originStrings encoded
      strings `shouldSatisfy` not . null
      forM_ strings $ \text -> do
        T.isPrefixOf "/" text `shouldBe` False
        T.isPrefixOf "~" text `shouldBe` False
        (T.length text >= 2 && T.index text 1 == ':') `shouldBe` False

    it "does not serialize the in-memory source path at all" $ do
      let encoded = LBS8.unpack (manifestToJSON manifestWithEveryOriginPosition)
      encoded `shouldSatisfy` not . isInfixOf "/Users/someone"
      encoded `shouldSatisfy` not . isInfixOf "\"source\""
      encoded `shouldSatisfy` not . isInfixOf "\"targetSource\""

  describe "emptyManifest" $ do
    it "creates a manifest with the current version" $ do
      let m = emptyManifest fixedTime
      (m ^. #version) `shouldBe` currentManifestVersion
      (m ^. #version) `shouldBe` 6

    it "creates a manifest with no modules, vars, or files" $ do
      let m = emptyManifest fixedTime
      (m ^. #modules) `shouldBe` []
      (m ^. #vars) `shouldBe` Map.empty
      (m ^. #files) `shouldBe` Map.empty
      (m ^. #blueprintMigrations) `shouldBe` []

  describe "ArtifactOrigin" $ do
    it "roundtrips a remote origin carrying a repository name" $ do
      let origin = RemoteOrigin "https://github.com/shinzui/seihou-modules.git" "haskell-base" (Just "seihou-modules")
      Aeson.decode (Aeson.encode origin) `shouldBe` Just origin

    it "roundtrips a remote origin with no repository name" $ do
      let origin = RemoteOrigin "https://github.com/shinzui/seihou-modules.git" "haskell-base" Nothing
      Aeson.decode (Aeson.encode origin) `shouldBe` Just origin

    it "omits the repo key entirely when there is no repository name" $ do
      let origin = RemoteOrigin "https://example.com/mods.git" "haskell-base" Nothing
      Aeson.toJSON origin
        `shouldBe` Aeson.object
          [ "kind" Aeson..= ("remote" :: T.Text),
            "url" Aeson..= ("https://example.com/mods.git" :: T.Text),
            "artifact" Aeson..= ("haskell-base" :: T.Text)
          ]

    it "roundtrips a project origin" $ do
      let origin = ProjectOrigin ".seihou/modules/demo"
      Aeson.decode (Aeson.encode origin) `shouldBe` Just origin

    it "roundtrips a local origin" $ do
      let origin = LocalOrigin "scratch-module"
      Aeson.decode (Aeson.encode origin) `shouldBe` Just origin

    it "rejects an unknown origin kind" $ do
      (Aeson.decode "{\"kind\":\"martian\"}" :: Maybe ArtifactOrigin) `shouldBe` Nothing

    it "names the artifact each origin refers to" $ do
      artifactOriginName (RemoteOrigin "https://example.com/mods.git" "haskell-base" Nothing) `shouldBe` "haskell-base"
      artifactOriginName (LocalOrigin "scratch-module") `shouldBe` "scratch-module"
      artifactOriginName (ProjectOrigin ".seihou/modules/demo") `shouldBe` "demo"

  describe "JSON roundtrip" $ do
    it "roundtrips an empty manifest" $ do
      let m = emptyManifest fixedTime
      manifestFromJSON (manifestToJSON m) `shouldBe` Right m

    it "roundtrips a manifest with modules" $ do
      let m =
            withManifestModules
              [ AppliedModule
                  { name = ModuleName "haskell-base",
                    parentVars = emptyParentVars,
                    origin = RemoteOrigin "https://github.com/shinzui/seihou-modules.git" "haskell-base" (Just "seihou-modules"),
                    moduleVersion = Nothing,
                    appliedAt = fixedTime,
                    removal = Nothing
                  }
              ]
              (emptyManifest fixedTime)
      manifestFromJSON (manifestToJSON m) `shouldBe` Right m

    it "roundtrips a manifest with variables" $ do
      let base = emptyManifest fixedTime
          m =
            Manifest
              { version = base ^. #version,
                genAt = base ^. #genAt,
                modules = base ^. #modules,
                vars =
                  Map.fromList
                    [ (VarName "project.name", "my-app"),
                      (VarName "license", "MIT")
                    ],
                files = base ^. #files,
                applications = base ^. #applications,
                recipe = Nothing,
                blueprint = Nothing,
                blueprintMigrations = []
              }
      manifestFromJSON (manifestToJSON m) `shouldBe` Right m

    it "roundtrips a manifest with file records" $ do
      let m :: Manifest
          m =
            ( (emptyManifest fixedTime)
                & #files .~ Map.fromList [("README.md", FileRecord {hash = SHA256 "abc123", moduleName = ModuleName "haskell-base", strategy = Template, generatedAt = fixedTime, baseline = Nothing, applicationIds = mempty}), ("my-app.cabal", FileRecord {hash = SHA256 "def456", moduleName = ModuleName "haskell-base", strategy = DhallText, generatedAt = fixedTime, baseline = Nothing, applicationIds = mempty})]
            )
      manifestFromJSON (manifestToJSON m) `shouldBe` Right m

    it "roundtrips a full manifest" $ do
      let m =
            Manifest
              { version = currentManifestVersion,
                genAt = fixedTime,
                modules =
                  [ AppliedModule (ModuleName "haskell-base") emptyParentVars (LocalOrigin "haskell-base") Nothing fixedTime Nothing,
                    AppliedModule (ModuleName "nix-flake") emptyParentVars (LocalOrigin "nix-flake") Nothing fixedTime2 Nothing
                  ],
                vars =
                  Map.fromList
                    [ (VarName "project.name", "my-app"),
                      (VarName "project.version", "0.1.0.0")
                    ],
                files =
                  Map.fromList
                    [ ( "README.md",
                        FileRecord (SHA256 "aaa") (ModuleName "haskell-base") Template fixedTime Nothing mempty
                      ),
                      ( "LICENSE",
                        FileRecord (SHA256 "bbb") (ModuleName "haskell-base") Copy fixedTime Nothing mempty
                      )
                    ],
                applications = [],
                recipe = Nothing,
                blueprint = Nothing,
                blueprintMigrations = []
              }
      manifestFromJSON (manifestToJSON m) `shouldBe` Right m

    it "roundtrips all strategy types" $ do
      let strategies = [Copy, Template, DhallText, Structured]
          makeRecord s =
            FileRecord (SHA256 "hash") (ModuleName "mod") s fixedTime Nothing mempty
          m :: Manifest
          m =
            ( (emptyManifest fixedTime)
                & #files .~ Map.fromList (zipWith (\i s -> ("file" <> show i, makeRecord s)) [(1 :: Int) ..] strategies)
            )
      manifestFromJSON (manifestToJSON m) `shouldBe` Right m

    it "roundtrips a manifest with versioned modules" $ do
      let m =
            withManifestModules
              [ AppliedModule
                  { name = ModuleName "haskell-base",
                    parentVars = emptyParentVars,
                    origin = LocalOrigin "haskell-base",
                    moduleVersion = Just "1.0.0",
                    appliedAt = fixedTime,
                    removal = Nothing
                  }
              ]
              (emptyManifest fixedTime)
      manifestFromJSON (manifestToJSON m) `shouldBe` Right m

    it "roundtrips a manifest with unversioned modules" $ do
      let m =
            withManifestModules
              [ AppliedModule
                  { name = ModuleName "simple-mod",
                    parentVars = emptyParentVars,
                    origin = LocalOrigin "simple-mod",
                    moduleVersion = Nothing,
                    appliedAt = fixedTime,
                    removal = Nothing
                  }
              ]
              (emptyManifest fixedTime)
      manifestFromJSON (manifestToJSON m) `shouldBe` Right m

    it "roundtrips a manifest with two instances of the same module" $ do
      let pv1 = ParentVars (Map.singleton (VarName "skill.name") "exec-plan")
          pv2 = ParentVars (Map.singleton (VarName "skill.name") "master-plan")
          m =
            withManifestModules
              [ AppliedModule
                  { name = ModuleName "claude-skill-link",
                    parentVars = pv1,
                    origin = ProjectOrigin ".seihou/modules/claude-skill-link",
                    moduleVersion = Nothing,
                    appliedAt = fixedTime,
                    removal = Nothing
                  },
                AppliedModule
                  { name = ModuleName "claude-skill-link",
                    parentVars = pv2,
                    origin = ProjectOrigin ".seihou/modules/claude-skill-link",
                    moduleVersion = Nothing,
                    appliedAt = fixedTime,
                    removal = Nothing
                  }
              ]
              (emptyManifest fixedTime)
      manifestFromJSON (manifestToJSON m) `shouldBe` Right m

    it "roundtrips all version-4 application and update state" $ do
      let appId1 = ApplicationId "application-one"
          appId2 = ApplicationId "application-two"
          fingerprint = CommandFingerprint (SHA256 "command-hash")
          receipt =
            CommandReceipt
              { fingerprint = fingerprint,
                moduleName = ModuleName "master-plan",
                command = "cabal test all",
                workDir = Just "cli",
                completedAt = fixedTime2
              }
          pv1 = ParentVars (Map.singleton (VarName "skill.name") "exec-plan")
          pv2 = ParentVars (Map.singleton (VarName "skill.name") "master-plan")
          application1 =
            AppliedComposition
              { applicationId = appId1,
                target = AppliedModuleTarget (ModuleName "master-plan"),
                targetOrigin = ProjectOrigin ".seihou/modules/master-plan",
                targetVersion = Just "0.7.0",
                additionalModules = [ModuleName "docs"],
                namespace = Just "planning",
                context = Just "work",
                instances =
                  [ AppliedInstanceState (ModuleName "link-skill") pv1 (LocalOrigin "link-skill") (Just "1") (Map.singleton (VarName "skill.name") "exec-plan"),
                    AppliedInstanceState (ModuleName "link-skill") pv2 (LocalOrigin "link-skill") (Just "1") (Map.singleton (VarName "skill.name") "master-plan")
                  ],
                commandReceipts = Map.singleton fingerprint receipt,
                appliedAt = fixedTime
              }
          application2 =
            AppliedComposition
              { applicationId = appId2,
                target = AppliedRecipeTarget (RecipeName "service"),
                targetOrigin = LocalOrigin "service",
                targetVersion = Nothing,
                additionalModules = [],
                namespace = Nothing,
                context = Nothing,
                instances = [],
                commandReceipts = Map.empty,
                appliedAt = fixedTime2
              }
          fileRecord =
            FileRecord
              { hash = SHA256 "applied-hash",
                moduleName = ModuleName "master-plan",
                strategy = Template,
                generatedAt = fixedTime,
                baseline = Just (BaselineRef (hashContent "generated baseline")),
                applicationIds = Set.fromList [appId1, appId2]
              }
          manifest =
            ( (emptyManifest fixedTime)
                & #applications .~ [application1, application2]
                & #files .~ Map.singleton "README.md" fileRecord
            )
      manifestFromJSON (manifestToJSON manifest) `shouldBe` Right manifest

    it "rejects malformed baseline references" $ do
      let json =
            "{\"version\":4,\"generatedAt\":\"2026-03-01T10:30:00Z\",\"modules\":[],\"variables\":{},"
              <> "\"files\":{\"README.md\":{\"hash\":\"abc\",\"module\":\"legacy\",\"strategy\":\"template\","
              <> "\"generatedAt\":\"2026-03-01T10:30:00Z\",\"baseline\":\"../manifest.json\"}}}"
      manifestFromJSON json `shouldSatisfy` either (const True) (const False)

  describe "AppliedBlueprint" $ do
    it "round-trips a fully populated entry through JSON" $ do
      let ab =
            AppliedBlueprint
              { name = ModuleName "payments-service",
                blueprintVersion = Just "0.3.1",
                appliedAt = fixedTime,
                baselineModules = [ModuleName "nix-flake", ModuleName "haskell-base"],
                noBaseline = False,
                userPrompt = Just "set this up for a payments microservice",
                agentSessionId = Nothing
              }
      Aeson.eitherDecode (Aeson.encode ab) `shouldBe` Right ab

    it "round-trips a --no-baseline entry through JSON" $ do
      let ab =
            AppliedBlueprint
              { name = ModuleName "lone-blueprint",
                blueprintVersion = Nothing,
                appliedAt = fixedTime,
                baselineModules = [],
                noBaseline = True,
                userPrompt = Nothing,
                agentSessionId = Nothing
              }
      Aeson.eitherDecode (Aeson.encode ab) `shouldBe` Right ab

    it "writeAppliedBlueprint replaces any prior entry" $ do
      let m0 = emptyManifest fixedTime
          ab1 =
            AppliedBlueprint
              (ModuleName "first")
              Nothing
              fixedTime
              []
              False
              Nothing
              Nothing
          ab2 =
            AppliedBlueprint
              (ModuleName "second")
              (Just "1.0.0")
              fixedTime2
              [ModuleName "x"]
              False
              (Just "do the thing")
              Nothing
          m1 = writeAppliedBlueprint ab1 m0
          m2 = writeAppliedBlueprint ab2 m1
      (m1 ^. #blueprint) `shouldBe` Just ab1
      (m2 ^. #blueprint) `shouldBe` Just ab2

  describe "AppliedBlueprintMigration" $ do
    it "round-trips a fully populated receipt through JSON" $ do
      let receipt =
            AppliedBlueprintMigration
              (ModuleName "payments")
              (Just "0.4.0")
              "1.0.0"
              "2.0.0"
              fixedTime
              (Just "session-123")
      Aeson.eitherDecode (Aeson.encode receipt) `shouldBe` Right receipt

    it "round-trips a version-5 manifest containing a receipt" $ do
      let receipt = mkBlueprintMigrationReceipt "payments" "1.0.0" "2.0.0" fixedTime
          manifest = ((emptyManifest fixedTime) & #blueprintMigrations .~ [receipt])
      manifestFromJSON (manifestToJSON manifest) `shouldBe` Right manifest

    it "replaces the same exact edge in place and appends a different edge" $ do
      let first = mkBlueprintMigrationReceipt "payments" "1.0.0" "2.0.0" fixedTime
          unrelated = mkBlueprintMigrationReceipt "payments" "2.5.0" "3.0.0" fixedTime
          replacement =
            AppliedBlueprintMigration
              (ModuleName "payments")
              (Just "0.5.0")
              "1.0.0"
              "2.0.0"
              fixedTime2
              (Just "rerun")
          manifest1 = writeAppliedBlueprintMigration unrelated (writeAppliedBlueprintMigration first (emptyManifest fixedTime))
          manifest2 = writeAppliedBlueprintMigration replacement manifest1
      (manifest2 ^. #blueprintMigrations) `shouldBe` [replacement, unrelated]
      hasAppliedBlueprintMigration "payments" "1.0.0" "2.0.0" manifest2 `shouldBe` True
      hasAppliedBlueprintMigration "payments" "2.0.0" "3.0.0" manifest2 `shouldBe` False

    it "preserves modules, applications, files, recipe, and normal blueprint provenance" $ do
      let appliedModule = AppliedModule "base" emptyParentVars (LocalOrigin "base") (Just "1.0.0") fixedTime Nothing
          application =
            AppliedComposition
              { applicationId = ApplicationId "app-base",
                target = AppliedModuleTarget "base",
                targetOrigin = LocalOrigin "base",
                targetVersion = Just "1.0.0",
                additionalModules = [],
                namespace = Nothing,
                context = Nothing,
                instances = [],
                commandReceipts = Map.empty,
                appliedAt = fixedTime
              }
          fileRecord = FileRecord (SHA256 "hash") "base" Template fixedTime Nothing mempty
          recipe = AppliedRecipe "recipe" (Just "1.0.0") fixedTime
          normalBlueprint = AppliedBlueprint "payments" (Just "0.4.0") fixedTime [] False Nothing Nothing
          seed =
            ( (emptyManifest fixedTime)
                & #modules .~ [appliedModule]
                & #applications .~ [application]
                & #files .~ Map.singleton "README.md" fileRecord
                & #recipe .~ Just recipe
                & #blueprint .~ Just normalBlueprint
            )
          updated = writeAppliedBlueprintMigration (mkBlueprintMigrationReceipt "payments" "1.0.0" "2.0.0" fixedTime) seed
      (updated ^. #modules) `shouldBe` (seed ^. #modules)
      (updated ^. #applications) `shouldBe` (seed ^. #applications)
      (updated ^. #files) `shouldBe` (seed ^. #files)
      (updated ^. #recipe) `shouldBe` (seed ^. #recipe)
      (updated ^. #blueprint) `shouldBe` (seed ^. #blueprint)

  -- Schema versions 1 through 5 recorded a machine-specific absolute
  -- @source@ path in place of the portable @origin@ introduced in version 6.
  -- Rather than misread them, the decoder refuses them and names the remedy.
  -- Restoring lossless decoding of those versions is owned by
  -- docs/plans/79-upgrade-legacy-absolute-path-manifests-in-place.md, which
  -- also delivers the 'seihou manifest upgrade' command the message names.
  describe "schema back-compat" $ do
    it "refuses every pre-portable-origin schema version and names the remedy" $ do
      let legacy v =
            "{\"version\":"
              <> LBS8.pack (show (v :: Int))
              <> ",\"generatedAt\":\"2026-03-01T10:30:00Z\",\"modules\":[],\"variables\":{},\"files\":{},\"applications\":[]}"
      forM_ [1 .. 5] $ \v ->
        case manifestFromJSON (legacy v) of
          Right _ -> expectationFailure ("schema version " <> show v <> " should not decode directly")
          Left err -> do
            err `shouldSatisfy` isInfixOf "seihou manifest upgrade"
            err `shouldSatisfy` isInfixOf ("schema version " <> show v)

    it "refuses a version-1 manifest that records an absolute module source" $ do
      let json = "{\"version\":1,\"generatedAt\":\"2026-03-01T10:30:00Z\",\"modules\":[{\"name\":\"haskell-base\",\"source\":\"/path\",\"appliedAt\":\"2026-03-01T10:30:00Z\"}],\"variables\":{},\"files\":{}}"
      case manifestFromJSON json of
        Right _ -> expectationFailure "a version-1 manifest should not decode directly"
        Left err -> err `shouldSatisfy` isInfixOf "seihou manifest upgrade"

  describe "version checking" $ do
    it "rejects manifests with version higher than current" $ do
      let base = emptyManifest fixedTime
          m = Manifest {version = 99, genAt = base ^. #genAt, modules = base ^. #modules, vars = base ^. #vars, files = base ^. #files, applications = base ^. #applications, recipe = Nothing, blueprint = Nothing, blueprintMigrations = []}
          result = manifestFromJSON (manifestToJSON m)
      case result of
        Left err -> err `shouldContain` "newer version"
        Right _ -> expectationFailure "should have rejected future version"

  describe "hashContent" $ do
    it "produces a hex-encoded SHA256 digest" $ do
      let h = hashContent "hello world"
      -- SHA256 of "hello world" is a well-known value
      (h ^. #unSHA256) `shouldBe` "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"

    it "produces different hashes for different content" $ do
      let h1 = hashContent "hello"
          h2 = hashContent "world"
      h1 `shouldNotBe` h2

    it "produces consistent hashes for the same content" $ do
      let h1 = hashContent "test content"
          h2 = hashContent "test content"
      h1 `shouldBe` h2

    it "produces a 64-character hex string" $ do
      let SHA256 hex = hashContent "anything"
      T.length hex `shouldBe` 64

    it "handles empty content" $ do
      let h = hashContent ""
      -- SHA256 of empty string is a well-known value
      (h ^. #unSHA256) `shouldBe` "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
