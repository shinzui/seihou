-- | A caller's explicit inputs apply to one invocation only.
module Seihou.CLI.CallerToolPolicy
  ( CallerPolicyOptions (..),
    ResolvedPolicy,
    resolvePolicy,
    policyEvidence,
    effectiveTools,
    settingsPath,
    verifyPolicyFile,
    policyOptionNames,
    emptyPolicy,
    preflightPolicyManifest,
  )
where

import Control.Exception (IOException, try)
import Control.Monad (unless)
import Data.Aeson qualified as Aeson
import Data.ByteString qualified as BS
import Data.Char (isControl, isSpace)
import Data.Generics.Labels ()
import Data.List (nub)
import Data.Maybe (isJust)
import Data.Text qualified as T
import Seihou.CLI.AgentCompletion (AgentProvider (..))
import Seihou.CLI.AppliedBlueprint (preflightPolicyReceipt)
import Seihou.Core.Types (CallerToolPolicy (..), SHA256)
import Seihou.Manifest.Hash (hashBytes)
import Seihou.Prelude
import System.Directory (makeAbsolute)
import System.Posix.Files (getFileStatus, isRegularFile)

data CallerPolicyOptions = CallerPolicyOptions [Text] (Maybe FilePath)
  deriving stock (Eq, Show, Generic)

data ResolvedPolicy = ResolvedPolicy [Text] (Maybe (FilePath, SHA256))

emptyPolicy :: ResolvedPolicy
emptyPolicy = ResolvedPolicy [] Nothing

policyOptionNames :: CallerPolicyOptions -> [Text]
policyOptionNames (CallerPolicyOptions rules file) =
  ["--allowed-tool" | not (null rules)] <> ["--settings" | isJust file]

resolvePolicy :: Bool -> AgentProvider -> CallerPolicyOptions -> IO (Either Text ResolvedPolicy)
resolvePolicy batch provider options@(CallerPolicyOptions rules file)
  | null flags = pure (Right emptyPolicy)
  | provider /= AgentProviderClaudeCli || not batch =
      pure
        ( Left
            ( T.intercalate " and " flags
                <> " require --batch --provider claude-cli. Omit the policy to keep this launch mode."
                <> if provider `elem` [AgentProviderOpenAI, AgentProviderAnthropic] then " This API provider runs no tools." else ""
            )
        )
  | any invalidRule rules = pure (Left "--allowed-tool requires one nonblank Claude tool pattern per flag, for example 'Bash(grep *)'.")
  | otherwise = case file of
      Nothing -> pure (Right (ResolvedPolicy (nub rules) Nothing))
      Just path -> do
        absolute <- makeAbsolute path
        contents <- readSettings absolute
        pure $ do
          bytes <- contents
          case Aeson.decodeStrict' bytes of
            Just (Aeson.Object _) -> Right (ResolvedPolicy (nub rules) (Just (absolute, hashBytes bytes)))
            _ -> Left ("--settings must contain a JSON object: " <> T.pack path)
  where
    flags = policyOptionNames options
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

readSettings :: FilePath -> IO (Either Text BS.ByteString)
readSettings path = do
  result <- try @IOException $ do
    status <- getFileStatus path
    unless (isRegularFile status) $ ioError (userError "expected a regular file")
    BS.readFile path
  pure (first (const ("--settings requires a readable regular file: " <> T.pack path)) result)

verifyPolicyFile :: ResolvedPolicy -> IO (Either Text ())
verifyPolicyFile (ResolvedPolicy _ Nothing) = pure (Right ())
verifyPolicyFile (ResolvedPolicy _ (Just (path, digest))) = do
  current <- readSettings path
  pure $
    unless (fmap hashBytes current == Right digest) $
      Left ("--settings changed or became unreadable: " <> T.pack path <> ". Inspect the working diff and retry with a stable settings file.")

settingsPath :: ResolvedPolicy -> Maybe FilePath
settingsPath (ResolvedPolicy _ file) = fst <$> file

effectiveTools :: ResolvedPolicy -> [String] -> [String]
effectiveTools (ResolvedPolicy rules _) tools = nub (tools <> map T.unpack rules)

policyEvidence :: ResolvedPolicy -> Maybe CallerToolPolicy
policyEvidence (ResolvedPolicy [] Nothing) = Nothing
policyEvidence (ResolvedPolicy rules file) = Just (CallerToolPolicy rules (snd <$> file) Nothing Nothing)

preflightPolicyManifest :: FilePath -> ResolvedPolicy -> IO (Either Text ())
preflightPolicyManifest path policy
  | isJust (policyEvidence policy) = preflightPolicyReceipt path
  | otherwise = pure (Right ())
