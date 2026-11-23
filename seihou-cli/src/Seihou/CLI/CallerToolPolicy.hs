-- | A caller's explicit inputs apply to one invocation only.
module Seihou.CLI.CallerToolPolicy
  ( CallerPolicyOptions (..),
    ResolvedPolicy,
    resolvePolicy,
    policyEvidence,
    effectiveTools,
    settingsPath,
    codexHooksPath,
    withCodexPolicy,
    handleCodexHookReview,
    verifyPolicyFile,
    policyOptionNames,
    emptyPolicy,
    preflightPolicyManifest,
  )
where

import Baikai.Kit.Session qualified as KitSession
import Baikai.Provider.OpenAI.Cli qualified as CodexCli
import Baikai.Provider.OpenAI.ReviewedHooks (CodexHooks, ReviewedCodexThread, parseCodexHooks, reviewCodexHooksInTerminal)
import Control.Exception (IOException, try)
import Control.Monad (unless)
import Data.Aeson qualified as Aeson
import Data.ByteString qualified as BS
import Data.Char (isControl, isSpace)
import Data.Generics.Labels ()
import Data.List (nub)
import Data.Maybe (isJust)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.AgentCompletion (AgentModelConfig, AgentProvider (..), buildBaikaiModel)
import Seihou.CLI.AppliedBlueprint (preflightPolicyReceipt)
import Seihou.CLI.KitConfig (seihouKitConfig)
import Seihou.Core.Types (CallerToolPolicy (..), SHA256)
import Seihou.Manifest.Hash (hashBytes)
import Seihou.Prelude
import System.Directory (getCurrentDirectory, makeAbsolute)
import System.Exit (exitFailure)
import System.IO (stderr)
import System.Posix.Files (getFileStatus, isRegularFile)

data CallerPolicyOptions = CallerPolicyOptions [Text] (Maybe FilePath) (Maybe FilePath)
  deriving stock (Eq, Show, Generic)

data ResolvedPolicy
  = ClaudePolicy [Text] (Maybe (FilePath, SHA256))
  | CodexPolicy FilePath SHA256 CodexHooks

emptyPolicy :: ResolvedPolicy
emptyPolicy = ClaudePolicy [] Nothing

policyOptionNames :: CallerPolicyOptions -> [Text]
policyOptionNames (CallerPolicyOptions rules settings hooks) =
  ["--allowed-tool" | not (null rules)] <> ["--settings" | isJust settings] <> ["--codex-hooks" | isJust hooks]

resolvePolicy :: Bool -> AgentProvider -> CallerPolicyOptions -> IO (Either Text ResolvedPolicy)
resolvePolicy batch provider options@(CallerPolicyOptions rules file codexFile)
  | null flags = pure (Right emptyPolicy)
  | Just path <- codexFile =
      if not (null rules) || isJust file
        then pure (Left "--codex-hooks cannot be combined with --allowed-tool or --settings.")
        else
          if provider /= AgentProviderCodexCli || not batch
            then pure (Left ("--codex-hooks requires --batch --provider codex-cli." <> apiTools))
            else do
              absolute <- makeAbsolute path
              contents <- readPolicyFile "--codex-hooks" absolute
              pure $ do
                bytes <- contents
                hooks <- first ("--codex-hooks: " <>) (parseCodexHooks bytes)
                pure (CodexPolicy absolute (hashBytes bytes) hooks)
  | provider /= AgentProviderClaudeCli || not batch =
      pure
        ( Left
            ( T.intercalate " and " flags
                <> " require --batch --provider claude-cli. Omit the policy to keep this launch mode."
                <> apiTools
                <> if provider == AgentProviderCodexCli then " For Codex, use --codex-hooks FILE." else ""
            )
        )
  | any invalidRule rules = pure (Left "--allowed-tool requires one nonblank Claude tool pattern per flag, for example 'Bash(grep *)'.")
  | otherwise = case file of
      Nothing -> pure (Right (ClaudePolicy (nub rules) Nothing))
      Just path -> do
        absolute <- makeAbsolute path
        contents <- readPolicyFile "--settings" absolute
        pure $ do
          bytes <- contents
          case Aeson.decodeStrict' bytes of
            Just (Aeson.Object _) -> Right (ClaudePolicy (nub rules) (Just (absolute, hashBytes bytes)))
            _ -> Left ("--settings must contain a JSON object: " <> T.pack path)
  where
    flags = policyOptionNames options
    apiTools = if provider `elem` [AgentProviderOpenAI, AgentProviderAnthropic] then " This API provider runs no tools." else ""
    invalidRule rule =
      let (name, suffix) = T.breakOn "(" rule
       in T.null name
            || T.isPrefixOf "-" name
            || T.any isControl rule
            || T.any (\c -> isSpace c || c `elem` (",)" :: String)) name
            || (not (T.null suffix) && not (onePattern 0 (T.unpack suffix)))
    -- Claude also accepts a delimited list. A single flag must never turn
    -- into two grants, while punctuation inside a tool's pattern is literal.
    onePattern :: Int -> String -> Bool
    onePattern depth [] = depth == 0
    onePattern depth ('\\' : _ : rest) = depth > 0 && onePattern depth rest
    onePattern depth ('(' : rest) = onePattern (depth + 1) rest
    onePattern depth (')' : rest) = depth > 0 && (depth /= 1 || null rest) && onePattern (depth - 1) rest
    onePattern depth (_ : rest) = depth > 0 && onePattern depth rest

readPolicyFile :: Text -> FilePath -> IO (Either Text BS.ByteString)
readPolicyFile flag path = do
  result <- try @IOException $ do
    status <- getFileStatus path
    unless (isRegularFile status) $ ioError (userError "expected a regular file")
    BS.readFile path
  pure (first (const (flag <> " requires a readable regular file: " <> T.pack path)) result)

verifyPolicyFile :: ResolvedPolicy -> IO (Either Text ())
verifyPolicyFile = \case
  ClaudePolicy _ Nothing -> pure (Right ())
  ClaudePolicy _ (Just (path, digest)) -> verify "--settings" path digest
  CodexPolicy path digest _ -> verify "--codex-hooks" path digest
  where
    verify flag path digest = do
      current <- readPolicyFile flag path
      pure $
        unless (fmap hashBytes current == Right digest) $
          Left (flag <> " changed or became unreadable: " <> T.pack path <> ". Inspect the working diff and retry with a stable policy file.")

settingsPath :: ResolvedPolicy -> Maybe FilePath
settingsPath (ClaudePolicy _ file) = fst <$> file
settingsPath CodexPolicy {} = Nothing

codexHooksPath :: ResolvedPolicy -> Maybe FilePath
codexHooksPath (CodexPolicy path _ _) = Just path
codexHooksPath ClaudePolicy {} = Nothing

effectiveTools :: ResolvedPolicy -> [String] -> [String]
effectiveTools (ClaudePolicy rules _) tools = nub (tools <> map T.unpack rules)
effectiveTools CodexPolicy {} tools = tools

policyEvidence :: ResolvedPolicy -> Maybe CallerToolPolicy
policyEvidence (ClaudePolicy [] Nothing) = Nothing
policyEvidence (ClaudePolicy rules file) = Just (CallerToolPolicy rules (snd <$> file) Nothing Nothing)
policyEvidence (CodexPolicy _ digest _) = Just (CallerToolPolicy [] Nothing (Just digest) Nothing)

-- | Keep the checked thread live while the caller prepares and runs its turn.
-- Ordinary invocations keep their existing provider path.
withCodexPolicy ::
  ResolvedPolicy ->
  AgentModelConfig ->
  Maybe FilePath ->
  (Maybe ReviewedCodexThread -> IO a) ->
  IO (Either Text a)
withCodexPolicy policy config mounted use = case policy of
  CodexPolicy path _ hooks ->
    verifyPolicyFile policy >>= \case
      Left err -> pure (Left err)
      Right () -> do
        sessionArgs <- KitSession.codexSessionArgs seihouKitConfig
        let cli = CodexCli.defaultCodexCliConfig & #extraArgs .~ sessionArgs
        result <- CodexCli.withReviewedCodexCli cli (buildBaikaiModel config) (maybe [] pure mounted) hooks (use . Just)
        pure (first (describeError path) result)
  ClaudePolicy {} -> Right <$> use Nothing
  where
    describeError path message
      | message == "Codex requires review for the current hooks." =
          message <> " Run seihou agent review-codex-hooks " <> shellPath path <> " and retry."
      | otherwise = message
    shellPath path = "'" <> T.replace "'" "'\\''" (T.pack path) <> "'"

handleCodexHookReview :: Bool -> FilePath -> IO ()
handleCodexHookReview debug path
  | debug = failReview "To review a Codex hooks file, run seihou agent review-codex-hooks FILE in a terminal."
  | otherwise = do
      cwd <- getCurrentDirectory
      reviewCodexHooksInTerminal "codex" cwd path >>= \case
        Left err -> failReview err
        Right False -> failReview "Codex hook review cancelled."
        Right True -> TIO.putStrLn "Codex has reviewed the current hook declarations."
  where
    failReview message = TIO.hPutStrLn stderr message >> exitFailure

preflightPolicyManifest :: FilePath -> ResolvedPolicy -> IO (Either Text ())
preflightPolicyManifest path policy
  | isJust (policyEvidence policy) = preflightPolicyReceipt path
  | otherwise = pure (Right ())
