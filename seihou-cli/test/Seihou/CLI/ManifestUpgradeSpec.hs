module Seihou.CLI.ManifestUpgradeSpec (tests) where

import Control.Lens ((^.))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Vector qualified as V
import Seihou.CLI.ManifestUpgrade
  ( InferenceOutcome (..),
    LegacyManifest (..),
    LegacyRef (..),
    UpgradeReportEntry (..),
    UpgradeResult (..),
    applyUpgrade,
    formatUpgradeReport,
    inferOriginFromLegacyPath,
    readLegacyManifest,
  )
import Seihou.Core.Types (ArtifactOrigin (..), Manifest (..))
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)
import Text.Read (readMaybe)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.ManifestUpgrade" spec

fixturePath :: FilePath
fixturePath = "test/fixtures/legacy-manifest-v5.json"

-- | Every legacy reference the fixture contains, as
-- @(pointer, name, path, version, definition file)@.
expectedRefs :: [([String], String, FilePath, Maybe String, FilePath)]
expectedRefs =
  [ ( ["modules", "0", "source"],
      "haskell-base",
      "/Users/someone-else/.config/seihou/installed/haskell-base",
      Just "1.4.0",
      "module.dhall"
    ),
    ( ["modules", "1", "source"],
      "project-lint",
      "/Users/someone-else/work/myproject/.seihou/modules/project-lint",
      Just "0.2.0",
      "module.dhall"
    ),
    ( ["applications", "0", "targetSource"],
      "haskell-base",
      "/Users/someone-else/.config/seihou/installed/haskell-base",
      Just "1.4.0",
      "module.dhall"
    ),
    ( ["applications", "0", "instances", "0", "source"],
      "haskell-base",
      "/Users/someone-else/.config/seihou/installed/haskell-base",
      Just "1.4.0",
      "module.dhall"
    ),
    ( ["applications", "1", "targetSource"],
      "haskell-service",
      "/Users/someone-else/.config/seihou/installed/haskell-service",
      Just "3.1.0",
      "recipe.dhall"
    ),
    ( ["applications", "1", "instances", "0", "source"],
      "project-lint",
      "/Users/someone-else/work/myproject/.seihou/modules/project-lint",
      Just "0.2.0",
      "module.dhall"
    ),
    ( ["applications", "1", "instances", "1", "source"],
      "scratch-helper",
      "/Users/someone-else/.config/seihou/modules/scratch-helper",
      Nothing,
      "module.dhall"
    )
  ]

describeRef :: LegacyRef -> ([String], String, FilePath, Maybe String, FilePath)
describeRef ref =
  ( map T.unpack (ref ^. #jsonPointer),
    T.unpack (ref ^. #artifactName),
    ref ^. #legacyPath,
    fmap T.unpack (ref ^. #recordedVersion),
    ref ^. #definitionFile
  )

spec :: Spec
spec = do
  describe "readLegacyManifest" $ do
    it "finds every legacy reference in a schema-5 manifest, in document order" $ do
      bytes <- LBS.readFile fixturePath
      case readLegacyManifest bytes of
        Left err -> expectationFailure ("expected a legacy manifest, got: " <> err)
        Right Nothing -> expectationFailure "expected a legacy manifest, got 'nothing to do'"
        Right (Just legacy) -> do
          (legacy ^. #schemaVersion) `shouldBe` 5
          map describeRef (legacy ^. #refs) `shouldBe` expectedRefs

    it "reports nothing to do for a manifest already at the current schema version" $
      readLegacyManifest "{\"version\":6,\"modules\":[]}" `shouldBe` Right Nothing

    it "reports nothing to do for a manifest from a newer seihou" $
      readLegacyManifest "{\"version\":7,\"modules\":[]}" `shouldBe` Right Nothing

    it "rejects a document with no version field" $
      readLegacyManifest "{\"modules\":[]}"
        `shouldBe` Left "manifest has no 'version' field"

  describe "schema versions 1 through 5" $
    -- Version 6's guard made these documents undecodable by the ordinary
    -- manifest decoder, so this is where their positive coverage now lives.
    -- Every field a later schema version added is optional with an empty
    -- default and none of them holds a path, so all five convert identically.
    it "converts every pre-portable-origin schema version the same way" $
      mapM_ convertsCleanly [1 .. 5]

  describe "inferOriginFromLegacyPath" $ do
    it "converts a foreign project path by its .seihou/modules suffix" $ do
      outcome <-
        inferOriginFromLegacyPath
          "/nowhere/this-project"
          []
          (legacyRef "demo" "/Users/someone-else/work/theirproject/.seihou/modules/demo")
      outcome `shouldBe` InferredFromProjectPath (ProjectOrigin ".seihou/modules/demo")

    it "recovers the upstream URL from a locally installed copy" $
      withInstall (Just originJson) $ \projectRoot installRoot -> do
        outcome <-
          inferOriginFromLegacyPath
            projectRoot
            [installRoot]
            (legacyRef "demo" "/Users/someone-else/.config/seihou/installed/demo")
        outcome
          `shouldBe` InferredFromLocalInstall
            (RemoteOrigin "https://example.com/demo-modules.git" "demo" (Just "demo-modules"))

    it "falls back to an unverifiable local origin when nothing is installed here" $
      withSystemTempDirectory "seihou-upgrade" $ \root -> do
        let projectRoot = root </> "project"
            installRoot = root </> "home" </> "seihou" </> "installed"
        createDirectoryIfMissing True projectRoot
        createDirectoryIfMissing True installRoot
        outcome <-
          inferOriginFromLegacyPath
            projectRoot
            [installRoot]
            (legacyRef "demo" "/Users/someone-else/.config/seihou/installed/demo")
        outcome `shouldBe` InferredAsUnverifiable (LocalOrigin "demo")

    it "reports an installed copy with no recorded provenance as unverifiable" $
      withInstall Nothing $ \projectRoot installRoot -> do
        outcome <-
          inferOriginFromLegacyPath
            projectRoot
            [installRoot]
            (legacyRef "demo" "/Users/someone-else/.config/seihou/modules/demo")
        outcome `shouldBe` InferredAsUnverifiable (LocalOrigin "demo")

  describe "applyUpgrade" $ do
    it "replaces every recorded path with its origin and bumps the schema version" $ do
      result <- upgradedFixture
      let document = result ^. #upgradedDocument
      (result ^. #fromVersion) `shouldBe` 5
      documentKeys document `shouldNotContain` ["source"]
      documentKeys document `shouldNotContain` ["targetSource"]
      documentKeys document `shouldContain` ["origin"]
      documentKeys document `shouldContain` ["targetOrigin"]
      lookupPath ["version"] document `shouldBe` Just (Aeson.Number 6)
      lookupPath ["modules", "0", "origin"] document
        `shouldBe` Just (Aeson.toJSON (RemoteOrigin haskellBaseUrl "haskell-base" (Just "seihou-modules")))
      lookupPath ["applications", "1", "instances", "0", "origin"] document
        `shouldBe` Just (Aeson.toJSON (ProjectOrigin ".seihou/modules/project-lint"))

    it "leaves no machine-specific path anywhere in the document" $ do
      result <- upgradedFixture
      -- The invariant of docs/adr/0001: nothing whose meaning depends on the
      -- machine that wrote it. A variable whose *value* happens to name the
      -- other developer is data, not a path, and must survive.
      filter absoluteLooking (documentStrings (result ^. #upgradedDocument))
        `shouldBe` []

    it "preserves every field it does not convert" $ do
      result <- upgradedFixture
      let document = result ^. #upgradedDocument
      lookupPath ["variables", "project.author"] document
        `shouldBe` Just (Aeson.String "someone-else")
      lookupPath ["modules", "0", "parentVars", "project.name"] document
        `shouldBe` Just (Aeson.String "demo")
      lookupPath ["files", "flake.nix", "baseline"] document
        `shouldBe` Just (Aeson.String (T.replicate 64 "2"))
      lookupPath ["blueprintMigrations", "0", "agentSessionId"] document
        `shouldBe` Just (Aeson.String "session-abc")
      lookupPath ["blueprint", "userPrompt"] document
        `shouldBe` Just (Aeson.String "build a service")
      lookupPath
        ["applications", "0", "commandReceipts", T.replicate 64 "4", "command"]
        document
        `shouldBe` Just (Aeson.String "cabal build")

    it "produces a document the ordinary manifest decoder accepts" $ do
      result <- upgradedFixture
      case Aeson.fromJSON (result ^. #upgradedDocument) :: Aeson.Result Manifest of
        Aeson.Error err -> expectationFailure ("upgraded manifest does not decode: " <> err)
        Aeson.Success manifest -> length (manifest ^. #modules) `shouldBe` 2

    it "reports each artifact once even though it appears in three records" $ do
      result <- upgradedFixture
      map (^. #artifactName) (result ^. #entries)
        `shouldBe` ["haskell-base", "project-lint", "haskell-service", "scratch-helper"]

  describe "formatUpgradeReport" $
    it "renders one aligned block per conversion" $
      formatUpgradeReport exampleResult `shouldBe` exampleReport

haskellBaseUrl :: Text
haskellBaseUrl = "https://github.com/shinzui/seihou-modules.git"

-- | A manifest at one of the historical schema versions, carrying only the
-- keys that version is guaranteed to have.
schemaVersionDocument :: Int -> LBS.ByteString
schemaVersionDocument version =
  LBS.fromStrict . TE.encodeUtf8 . T.concat $
    [ "{\"version\":",
      T.pack (show version),
      ",\"generatedAt\":\"2026-07-01T12:00:00Z\"",
      ",\"modules\":[{\"name\":\"demo\"",
      ",\"source\":\"/Users/someone-else/.config/seihou/installed/demo\"",
      ",\"version\":\"1.0.0\",\"appliedAt\":\"2026-07-01T12:00:00Z\"}]",
      ",\"variables\":{},\"files\":{}}"
    ]

-- | One historical schema version reads, converts, and lands on version 6
-- with a portable origin in place of the recorded path.
convertsCleanly :: Int -> Expectation
convertsCleanly version =
  case readLegacyManifest (schemaVersionDocument version) of
    Left err -> expectationFailure ("schema version " <> show version <> " did not read: " <> err)
    Right Nothing -> expectationFailure ("schema version " <> show version <> " reported nothing to do")
    Right (Just legacy) -> do
      (legacy ^. #schemaVersion) `shouldBe` version
      let converted =
            applyUpgrade
              legacy
              [(ref, InferredAsUnverifiable (LocalOrigin "demo")) | ref <- legacy ^. #refs]
          document = converted ^. #upgradedDocument
      lookupPath ["version"] document `shouldBe` Just (Aeson.Number 6)
      lookupPath ["modules", "0", "origin"] document
        `shouldBe` Just (Aeson.toJSON (LocalOrigin "demo"))
      lookupPath ["modules", "0", "version"] document `shouldBe` Just (Aeson.String "1.0.0")
      filter absoluteLooking (documentStrings document) `shouldBe` []

-- | The fixture, converted with a fixed inference for each artifact so the
-- assertions are about the rewrite rather than about this machine.
upgradedFixture :: IO UpgradeResult
upgradedFixture = do
  bytes <- LBS.readFile fixturePath
  case readLegacyManifest bytes of
    Right (Just legacy) ->
      pure (applyUpgrade legacy [(ref, inferenceFor ref) | ref <- legacy ^. #refs])
    other -> fail ("fixture did not read as a legacy manifest: " <> show (fmap (fmap (^. #schemaVersion)) other))
  where
    inferenceFor ref = case ref ^. #artifactName of
      "project-lint" -> InferredFromProjectPath (ProjectOrigin ".seihou/modules/project-lint")
      "scratch-helper" -> InferredAsUnverifiable (LocalOrigin "scratch-helper")
      name -> InferredFromLocalInstall (RemoteOrigin haskellBaseUrl name (Just "seihou-modules"))

exampleResult :: UpgradeResult
exampleResult =
  UpgradeResult
    { fromVersion = 5,
      entries =
        [ UpgradeReportEntry
            { artifactName = "haskell-base",
              legacyPath = "/Users/shinzui/.config/seihou/installed/haskell-base",
              outcome =
                InferredFromLocalInstall (RemoteOrigin haskellBaseUrl "haskell-base" (Just "seihou-modules"))
            },
          UpgradeReportEntry
            { artifactName = "project-lint",
              legacyPath = "/Users/shinzui/work/myproject/.seihou/modules/project-lint",
              outcome = InferredFromProjectPath (ProjectOrigin ".seihou/modules/project-lint")
            },
          UpgradeReportEntry
            { artifactName = "scratch-helper",
              legacyPath = "/Users/other/.config/seihou/modules/scratch-helper",
              outcome = InferredAsUnverifiable (LocalOrigin "scratch-helper")
            }
        ],
      upgradedDocument = Aeson.Null
    }

exampleReport :: Text
exampleReport =
  T.unlines
    [ "Reading .seihou/manifest.json (schema version 5)",
      "",
      "  haskell-base       /Users/shinzui/.config/seihou/installed/haskell-base",
      "                  →  remote https://github.com/shinzui/seihou-modules.git",
      "",
      "  project-lint       /Users/shinzui/work/myproject/.seihou/modules/project-lint",
      "                  →  project .seihou/modules/project-lint",
      "",
      "  scratch-helper     /Users/other/.config/seihou/modules/scratch-helper",
      "                  →  local scratch-helper  (no upstream recorded)",
      ""
    ]

-- | Every object key appearing anywhere in a document.
documentKeys :: Aeson.Value -> [Text]
documentKeys (Aeson.Object fields) =
  map Key.toText (KeyMap.keys fields) <> concatMap documentKeys (KeyMap.elems fields)
documentKeys (Aeson.Array elements) = concatMap documentKeys elements
documentKeys _ = []

-- | Whether a string looks like a path that only means something on the
-- machine that wrote it.
absoluteLooking :: Text -> Bool
absoluteLooking value =
  T.isPrefixOf "/" value
    || T.isPrefixOf "~" value
    || T.isPrefixOf "\\\\" value
    || (T.length value >= 3 && T.index value 1 == ':' && T.index value 2 == '\\')

-- | Every string value appearing anywhere in a document.
documentStrings :: Aeson.Value -> [Text]
documentStrings (Aeson.String text) = [text]
documentStrings (Aeson.Object fields) = concatMap documentStrings (KeyMap.elems fields)
documentStrings (Aeson.Array elements) = concatMap documentStrings elements
documentStrings _ = []

-- | Follow a pointer of object keys and array indices.
lookupPath :: [Text] -> Aeson.Value -> Maybe Aeson.Value
lookupPath [] value = Just value
lookupPath (step : rest) (Aeson.Object fields) =
  KeyMap.lookup (Key.fromText step) fields >>= lookupPath rest
lookupPath (step : rest) (Aeson.Array elements) = do
  index <- readMaybe (T.unpack step)
  element <- elements V.!? index
  lookupPath rest element
lookupPath _ _ = Nothing

-- | A reference to a module, which is all the inference tests need.
legacyRef :: Text -> FilePath -> LegacyRef
legacyRef name path =
  LegacyRef
    { jsonPointer = ["modules", "0", "source"],
      artifactName = name,
      legacyPath = path,
      recordedVersion = Just "1.0.0",
      definitionFile = "module.dhall"
    }

originJson :: String
originJson =
  "{\"sourceUrl\":\"https://example.com/demo-modules.git\"\
  \,\"repoName\":\"demo-modules\"\
  \,\"installedAt\":\"2026-07-01T00:00:00Z\"\
  \,\"version\":\"1.0.0\",\"tags\":[]}"

-- | A project root plus a search path holding an installed @demo@, with or
-- without the @.seihou-origin.json@ that records where it came from.
withInstall :: Maybe String -> (FilePath -> FilePath -> IO a) -> IO a
withInstall mOriginJson action =
  withSystemTempDirectory "seihou-upgrade" $ \root -> do
    let projectRoot = root </> "project"
        installRoot = root </> "home" </> "seihou" </> "installed"
        artifactDir = installRoot </> "demo"
    createDirectoryIfMissing True projectRoot
    createDirectoryIfMissing True artifactDir
    writeFile (artifactDir </> "module.dhall") "{ name = \"demo\" }"
    case mOriginJson of
      Nothing -> pure ()
      Just contents -> writeFile (artifactDir </> ".seihou-origin.json") contents
    action projectRoot installRoot
