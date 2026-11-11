-- | The deterministic secret scanner, Gitleaks, run on exactly the captured
-- bytes.
--
-- The captured post-change content is written to a private temporary tree
-- (removed on every exit path) and scanned with @gitleaks dir@. The scan uses
-- a Seihou-owned configuration that extends only Gitleaks' built-in rules,
-- ignores @gitleaks:allow@ comments, points the ignore-file lookup at an
-- empty directory and clears @GITLEAKS_*@ environment overrides, so nothing in
-- the repository or environment can weaken the baseline. Only the rule ID,
-- path and line are read from the report; the matched text never leaves this
-- module.
--
-- The scanner serves two roles that callers keep distinct: a transmission
-- safeguard ('flaggedPaths', 'flaggedTexts') and a deterministic check whose
-- findings are reported only for definitions that declare it.
module Seihou.CLI.Judgement.Scanner
  ( ScanResult (..),
    findScanner,
    scanCaptured,
    flaggedPaths,
  )
where

import Control.Exception (IOException, try)
import Control.Monad (forM_)
import Data.Aeson ((.:), (.:?))
import Data.Aeson qualified as Aeson
import Data.Aeson.Types qualified as Aeson
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Generics.Labels ()
import Data.List (isPrefixOf, nub)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Seihou.CLI.Judgement.Evidence (EvidenceFile)
import Seihou.Core.Judgement
import Seihou.Prelude
import System.Directory (createDirectoryIfMissing, findExecutable)
import System.Environment (getEnvironment, lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath (makeRelative, splitDirectories, takeDirectory)
import System.IO.Temp (withSystemTempDirectory)
import System.Process qualified as P

data ScanResult = ScanResult
  { -- | Hits in captured file content, as deterministic findings.
    findings :: ![DeterministicFinding],
    -- | Names of outgoing instruction texts the scanner flagged.
    flaggedTexts :: ![Text]
  }
  deriving stock (Eq, Show, Generic)

-- | Locate the scanner: @SEIHOU_GITLEAKS@ when set, otherwise @gitleaks@ on
-- PATH.
findScanner :: IO (Maybe FilePath)
findScanner = do
  override <- lookupEnv "SEIHOU_GITLEAKS"
  case override of
    Just p | not (null p) -> pure (Just p)
    _ -> findExecutable "gitleaks"

trustedConfig :: Text
trustedConfig =
  T.unlines
    [ "# Seihou-owned Gitleaks configuration: the built-in rules only.",
      "title = \"seihou judgement baseline\"",
      "[extend]",
      "useDefault = true"
    ]

-- | Scan captured content and named outgoing texts.
scanCaptured :: FilePath -> [EvidenceFile] -> [(Text, Text)] -> IO (Either Text ScanResult)
scanCaptured exe files texts = withSystemTempDirectory "seihou-scan" $ \tmp -> do
  let contentRoot = tmp </> "content"
      textRoot = tmp </> "texts"
      ignoreDir = tmp </> "ignore"
      configPath = tmp </> "gitleaks.toml"
      reportPath = tmp </> "report.json"
  forM_ [contentRoot, textRoot, ignoreDir] (createDirectoryIfMissing True)
  BS.writeFile configPath (TE.encodeUtf8 trustedConfig)
  forM_ files $ \f -> forM_ (f ^. #content) $ \bytes -> do
    let dest = contentRoot </> (f ^. #path)
    createDirectoryIfMissing True (takeDirectory dest)
    BS.writeFile dest bytes
  forM_ (zip [0 :: Int ..] texts) $ \(i, (_, body)) ->
    BS.writeFile (textRoot </> ("text-" <> show i <> ".txt")) (TE.encodeUtf8 body)
  env <- getEnvironment
  let cleanEnv = [(k, v) | (k, v) <- env, not ("GITLEAKS_" `isPrefixOf` k)]
      args =
        [ "dir",
          tmp,
          "--no-banner",
          "--no-color",
          "--log-level",
          "error",
          "--redact",
          "--ignore-gitleaks-allow",
          "--gitleaks-ignore-path",
          ignoreDir,
          "--config",
          configPath,
          "--report-format",
          "json",
          "--report-path",
          reportPath,
          "--exit-code",
          "0"
        ]
  attempted <- try (P.readCreateProcessWithExitCode ((P.proc exe args) {P.env = Just cleanEnv, P.cwd = Just tmp}) "")
  case attempted of
    Left (e :: IOException) -> pure (Left ("could not run the secret scanner (" <> T.pack exe <> "): " <> T.pack (show e)))
    Right (ExitFailure n, _, _) -> pure (Left ("the secret scanner exited " <> T.pack (show n) <> "; no scan result is available"))
    Right (ExitSuccess, _, _) -> do
      report <- try (BL.readFile reportPath)
      pure $ case report of
        Left (_ :: IOException) -> Left "the secret scanner wrote no report"
        Right bytes -> case Aeson.eitherDecode bytes >>= Aeson.parseEither (mapM parseHit) of
          Left _ -> Left "the secret scanner's report did not have the expected structure"
          Right hits -> Right (classify tmp hits)
  where
    parseHit = Aeson.withObject "finding" $ \o -> do
      rule <- o .: "RuleID"
      file <- o .: "File"
      line <- o .:? "StartLine"
      pure (rule :: Text, file :: FilePath, line :: Maybe Int)
    classify tmp hits =
      let rel f = makeRelative tmp f
          contentHits =
            [ DeterministicFinding SecretScan rule (Location p line)
            | (rule, file, line) <- hits,
              ("content" : rest) <- [splitDirectories (rel file)],
              let p = joinPosix rest
            ]
          textHits =
            nub
              [ name
              | (_, file, _) <- hits,
                ["texts", leaf] <- [splitDirectories (rel file)],
                (i, (name, _)) <- zip [0 :: Int ..] texts,
                leaf == "text-" <> show i <> ".txt"
              ]
       in ScanResult contentHits textHits
    joinPosix = T.unpack . T.intercalate "/" . map T.pack

-- | Paths whose captured content the scanner flagged.
flaggedPaths :: ScanResult -> [FilePath]
flaggedPaths r = nub [f ^. #location . #path | f <- r ^. #findings]
