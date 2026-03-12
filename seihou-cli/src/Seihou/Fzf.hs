module Seihou.Fzf
  ( -- * Config
    FzfConfig (..),
    detectFzfConfig,
    isFzfUsable,

    -- * Options
    FzfOpts (..),
    withPrompt,
    withHeader,
    withHeight,
    withAnsi,
    withNoSort,
    withPreview,
    optsToArgs,

    -- * Candidates and Results
    Candidate (..),
    FzfResult (..),

    -- * Running
    runFzf,
  )
where

import Control.Exception (SomeException, try)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import System.Directory (findExecutable)
import System.Exit (ExitCode (..))
import System.IO (IOMode (..), hClose, hIsTerminalDevice, openFile, stdin)
import System.Process
  ( CreateProcess (..),
    StdStream (..),
    createProcess,
    proc,
    waitForProcess,
  )
import Text.Read (readMaybe)

-- | Runtime configuration for fzf, detected once at CLI startup.
data FzfConfig = FzfConfig
  { fzfBinary :: !FilePath,
    fzfAvailable :: !Bool,
    stdinIsTerminal :: !Bool,
    ttyAvailable :: !Bool
  }
  deriving stock (Eq, Show)

-- | Detect fzf availability and terminal state.
detectFzfConfig :: IO FzfConfig
detectFzfConfig = do
  mFzf <- findExecutable "fzf"
  stdinTerm <- hIsTerminalDevice stdin
  ttyOk <- checkTtyAvailable
  pure
    FzfConfig
      { fzfBinary = maybe "fzf" id mFzf,
        fzfAvailable = case mFzf of Nothing -> False; Just _ -> True,
        stdinIsTerminal = stdinTerm,
        ttyAvailable = ttyOk
      }

-- | Check whether /dev/tty can be opened (for fzf in piped contexts).
checkTtyAvailable :: IO Bool
checkTtyAvailable = do
  result <- try @SomeException $ openFile "/dev/tty" ReadMode
  case result of
    Left _ -> pure False
    Right h -> hClose h >> pure True

-- | Whether fzf can be used for interactive selection.
isFzfUsable :: FzfConfig -> Bool
isFzfUsable cfg = cfg.fzfAvailable && (cfg.stdinIsTerminal || cfg.ttyAvailable)

-- | Composable fzf options. Combine with '<>'.
data FzfOpts = FzfOpts
  { fzfPrompt :: !(Maybe Text),
    fzfHeader :: !(Maybe Text),
    fzfPreview :: !(Maybe Text),
    fzfHeight :: !(Maybe Text),
    fzfAnsi :: !Bool,
    fzfNoSort :: !Bool
  }
  deriving stock (Eq, Show)

instance Semigroup FzfOpts where
  a <> b =
    FzfOpts
      { fzfPrompt = b.fzfPrompt <|> a.fzfPrompt,
        fzfHeader = b.fzfHeader <|> a.fzfHeader,
        fzfPreview = b.fzfPreview <|> a.fzfPreview,
        fzfHeight = b.fzfHeight <|> a.fzfHeight,
        fzfAnsi = a.fzfAnsi || b.fzfAnsi,
        fzfNoSort = a.fzfNoSort || b.fzfNoSort
      }
    where
      (<|>) :: Maybe a -> Maybe a -> Maybe a
      (<|>) Nothing y = y
      (<|>) x _ = x

instance Monoid FzfOpts where
  mempty = FzfOpts Nothing Nothing Nothing Nothing False False

withPrompt :: Text -> FzfOpts
withPrompt p = mempty {fzfPrompt = Just p}

withHeader :: Text -> FzfOpts
withHeader h = mempty {fzfHeader = Just h}

withHeight :: Text -> FzfOpts
withHeight h = mempty {fzfHeight = Just h}

withAnsi :: FzfOpts
withAnsi = mempty {fzfAnsi = True}

withNoSort :: FzfOpts
withNoSort = mempty {fzfNoSort = True}

withPreview :: Text -> FzfOpts
withPreview p = mempty {fzfPreview = Just p}

-- | Convert options to fzf CLI arguments.
optsToArgs :: FzfOpts -> [String]
optsToArgs opts =
  concat
    [ maybe [] (\p -> ["--prompt", T.unpack p]) opts.fzfPrompt,
      maybe [] (\h -> ["--header", T.unpack h]) opts.fzfHeader,
      maybe [] (\p -> ["--preview", T.unpack p]) opts.fzfPreview,
      maybe [] (\h -> ["--height", T.unpack h]) opts.fzfHeight,
      ["--ansi" | opts.fzfAnsi],
      ["--no-sort" | opts.fzfNoSort]
    ]

-- | A selectable candidate with display text and an associated value.
data Candidate a = Candidate
  { candidateDisplay :: !Text,
    candidateValue :: !a
  }
  deriving stock (Functor)

-- | Result of an fzf selection.
data FzfResult a
  = FzfSelected !a
  | FzfNoMatch
  | FzfCancelled
  | FzfError !Text
  deriving stock (Functor)

-- | Run fzf as a subprocess with the given candidates.
--
-- Uses index-based selection: each candidate line is prefixed with a hidden
-- integer index. The index is parsed back from fzf's output to look up the
-- original value, avoiding any issues with special characters in display text.
runFzf :: FzfConfig -> FzfOpts -> [Candidate a] -> IO (FzfResult a)
runFzf _ _ [] = pure FzfNoMatch
runFzf cfg opts candidates
  | not (isFzfUsable cfg) = pure (FzfError "fzf is not available")
  | otherwise = do
      let indexed = zip [0 :: Int ..] candidates
          valueMap = Map.fromList [(i, c.candidateValue) | (i, c) <- indexed]
          inputLines = [show i <> "\t" <> T.unpack c.candidateDisplay | (i, c) <- indexed]
          args = ["-1", "--with-nth=2.."] ++ optsToArgs opts

      let processSpec =
            (proc cfg.fzfBinary args)
              { std_in = CreatePipe,
                std_out = CreatePipe,
                std_err = Inherit,
                delegate_ctlc = True
              }

      result <- try @SomeException $ do
        (Just hIn, Just hOut, _, ph) <- createProcess processSpec
        mapM_ (TIO.hPutStrLn hIn . T.pack) inputLines
        hClose hIn
        outputStr <- TIO.hGetContents hOut
        exitCode <- waitForProcess ph
        pure (exitCode, T.strip outputStr)

      case result of
        Left err -> pure (FzfError (T.pack (show err)))
        Right (exitCode, output) -> case exitCode of
          ExitSuccess -> pure (parseSelection valueMap output)
          ExitFailure 1 -> pure FzfNoMatch
          ExitFailure 130 -> pure FzfCancelled
          ExitFailure n -> pure (FzfError ("fzf exited with code " <> T.pack (show n)))

-- | Parse the index from fzf output and look up the value.
parseSelection :: Map.Map Int a -> Text -> FzfResult a
parseSelection valueMap output =
  let indexText = T.takeWhile (/= '\t') output
   in case readMaybe (T.unpack indexText) of
        Just idx -> case Map.lookup idx valueMap of
          Just val -> FzfSelected val
          Nothing -> FzfError ("invalid index in fzf output: " <> indexText)
        Nothing -> FzfError ("could not parse fzf output: " <> output)
