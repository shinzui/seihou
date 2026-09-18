{-# LANGUAGE TemplateHaskell #-}

-- | @seihou agent upgrade MODULE [PROMPT]@: diagnose a project for a module
-- upgrade, write an upgrade brief outside the project, and start an agent
-- session that repairs the manifest state and performs the upgrade.
--
-- The command never fails because of project, machine, network, or
-- configuration state. Diagnosis turns every such problem into a finding
-- ("Seihou.CLI.UpgradeDiagnosis"), the brief is always written somewhere and
-- its path printed, and a session that cannot start falls back to telling
-- the user how to use the brief. The only non-zero exit is the interactive
-- session's own exit code, passed through as the other agent commands do.
-- See docs/adr/0016-agent-assisted-upgrade-diagnoses-read-only-and-never-fails.md.
module Seihou.CLI.AgentUpgrade
  ( handleAgentUpgrade,
    upgradeModelConfig,
  )
where

import Control.Exception (SomeException, displayException, try)
import Data.FileEmbed (embedFile)
import Data.Generics.Labels ()
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Seihou.CLI.AgentCompletion
  ( AgentModelConfig (..),
    AgentProvider (..),
    buildAgentCompletionRequestWith,
    defaultAgentModelConfig,
    providerToText,
    runAgentCompletion,
  )
import Seihou.CLI.AgentLaunch (substitute, upgradeAllowedTools)
import Seihou.CLI.AgentLaunchExec (launchConfiguredAgent)
import Seihou.CLI.AgentTrace (traceSinkForConfig)
import Seihou.CLI.Commands (AgentUpgradeOpts (..))
import Seihou.CLI.UpgradeDiagnosis
  ( BriefLocation (..),
    UpgradeDiagnosis,
    briefSections,
    createBriefDirectory,
    diagnoseUpgrade,
    diagnosisEnvFor,
    emptyDiagnosis,
    readiness,
    renderReadinessReport,
    writeBrief,
  )
import Seihou.Core.Types (LogLevel (..))
import Seihou.Prelude
import System.Directory (findExecutable, getCurrentDirectory)
import System.Exit (ExitCode (..), exitWith)
import System.IO (stderr)

-- | The fixed part of the brief, embedded at compile time from
-- data/upgrade-prompt.md.
promptTemplate :: Text
promptTemplate = TE.decodeUtf8 $(embedFile "data/upgrade-prompt.md")

-- | Resolve the agent configuration without ever exiting. A configuration
-- error becomes a finding for the brief, and the command carries on with
-- the built-in default provider.
upgradeModelConfig :: IO (Either Text AgentModelConfig) -> IO (AgentModelConfig, Maybe Text)
upgradeModelConfig load = do
  result <- try @SomeException load
  pure $ case result of
    Right (Right config) -> (config, Nothing)
    Right (Left err) -> (defaultAgentModelConfig, Just (fallbackFinding err))
    Left err -> (defaultAgentModelConfig, Just (fallbackFinding (T.pack (displayException err))))
  where
    fallbackFinding err =
      "agent configuration could not be resolved ("
        <> err
        <> "); fell back to the built-in default provider, "
        <> providerToText (defaultAgentModelConfig ^. #provider)

-- | Arguments: @--debug@, the seihou version text, the resolved agent
-- configuration, the configuration-fallback finding if any, and the options.
handleAgentUpgrade :: Bool -> Text -> AgentModelConfig -> Maybe Text -> AgentUpgradeOpts -> IO ()
handleAgentUpgrade debug version modelConfig configProblem opts = do
  let target = opts ^. #target
  (diagnosis, escaped) <- diagnose target
  if opts ^. #check
    then TIO.putStr (renderReadinessReport target (readiness diagnosis))
    else do
      directory <- createBriefDirectory target
      let findings = maybe [] pure configProblem <> escaped
          backupDir = either (\reason -> "a directory outside the project (" <> reason <> ")") T.pack directory
          brief = renderBrief version diagnosis findings backupDir (opts ^. #prompt)
      location <- writeBrief directory brief
      TIO.hPutStrLn stderr $ case location of
        BriefSaved path -> "Upgrade brief: " <> T.pack path
        BriefNotSaved reason -> "Upgrade brief not saved: " <> reason
      if debug
        then TIO.putStr brief
        else launch target modelConfig brief location (opts ^. #prompt)

-- | Run the diagnosis. It never throws, but if something escapes anyway the
-- brief says so and the command carries on with an empty diagnosis.
diagnose :: Text -> IO (UpgradeDiagnosis, [Text])
diagnose target = do
  rootResult <- try @SomeException getCurrentDirectory
  let root = either (const ".") id rootResult
  result <- try @SomeException (diagnosisEnvFor root >>= \env -> diagnoseUpgrade env target)
  pure $ case result of
    Right diagnosis -> (diagnosis, [])
    Left err ->
      let reason = "the diagnosis stopped unexpectedly: " <> T.pack (displayException err)
       in (emptyDiagnosis root target reason, [reason])

renderBrief :: Text -> UpgradeDiagnosis -> [Text] -> Text -> Maybe Text -> Text
renderBrief version diagnosis findings backupDir userPrompt =
  substitute
    ( briefSections diagnosis findings
        <> [ ("seihou_version", version),
             ("backup_dir", backupDir),
             ("user_request", fromMaybe "(none given)" userPrompt)
           ]
    )
    promptTemplate

launch :: Text -> AgentModelConfig -> Text -> BriefLocation -> Maybe Text -> IO ()
launch target modelConfig brief location userPrompt =
  case modelConfig ^. #provider of
    AgentProviderClaudeCli -> interactive "claude"
    AgentProviderCodexCli -> interactive "codex"
    _ -> completion
  where
    -- Without a request of the user's own, the session opens by asking the
    -- agent to start, so it does not sit waiting for input.
    initialPrompt =
      Just (fromMaybe ("Upgrade " <> target <> " by following the upgrade brief in your system prompt.") userPrompt)

    interactive binary = do
      found <- findExecutable binary
      case found of
        Nothing -> fallback location (T.pack binary <> " is not on PATH")
        Just _ -> do
          result <- try @SomeException (launchConfiguredAgent modelConfig upgradeAllowedTools False brief initialPrompt)
          case result of
            Left err -> fallback location ("the session could not start: " <> T.pack (displayException err))
            Right code -> do
              (after, _) <- diagnose target
              TIO.putStr ("\nAfter the session:\n" <> renderReadinessReport target (readiness after))
              exitWith code

    completion = do
      result <- try @SomeException $ do
        sink <- traceSinkForConfig LogNormal modelConfig
        runAgentCompletion (buildAgentCompletionRequestWith sink modelConfig brief initialPrompt)
      case result of
        Right (Right assistantText) -> TIO.putStrLn assistantText
        Right (Left err) -> fallback location ("the provider returned an error: " <> err)
        Left err -> fallback location ("the provider could not be reached: " <> T.pack (displayException err))

-- | How to use the brief when seihou could not start a session with it.
-- Always exits 0: the brief is the deliverable.
fallback :: BriefLocation -> Text -> IO ()
fallback location reason = do
  TIO.putStrLn ("Could not start the agent: " <> reason <> ".")
  case location of
    BriefSaved path ->
      TIO.putStr $
        T.unlines
          [ "The upgrade brief is saved at " <> T.pack path <> ". To use it, run:",
            "",
            "  claude --append-system-prompt \"$(cat " <> T.pack path <> ")\"",
            "",
            "or open the file in any coding agent."
          ]
    BriefNotSaved why ->
      TIO.putStrLn
        ( "The upgrade brief could not be saved ("
            <> why
            <> "). Re-run with 'seihou agent --debug upgrade' to print it, and give it to any coding agent."
        )
