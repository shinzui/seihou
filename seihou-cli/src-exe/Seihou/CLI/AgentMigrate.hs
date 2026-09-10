{-# LANGUAGE TemplateHaskell #-}

module Seihou.CLI.AgentMigrate
  ( handleAgentMigrate,
  )
where

import Baikai.Trace.Sink (TraceSink)
import Control.Applicative ((<|>))
import Control.Monad (unless, when)
import Data.FileEmbed (embedFile)
import Data.Generics.Labels ()
import Data.List (nub)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, listToMaybe, maybeToList)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Data.Time.Clock (getCurrentTime)
import Seihou.CLI.AgentCompletion
  ( AgentModelConfig (..),
    AgentProvider (..),
    buildAgentCompletionRequestWith,
    runAgentCompletion,
  )
import Seihou.CLI.AgentConfig
  ( PendingAgentConfig,
    agentLaunchDeclaration,
    resolveDeclaredAgentConfig,
  )
import Seihou.CLI.AgentGuard (enforceAgentArtifactGuard)
import Seihou.CLI.AgentLaunch (gatherAgentContext)
import Seihou.CLI.AgentLaunchExec (launchConfiguredAgentAddingDirs)
import Seihou.CLI.AgentTrace (traceSinkForConfig)
import Seihou.CLI.AppliedBlueprintMigration (recordAppliedBlueprintMigration)
import Seihou.CLI.BlueprintExecution
  ( BlueprintExecutionRequest (..),
    PreparedBlueprintExecution (..),
    prepareBlueprintExecution,
  )
import Seihou.CLI.BlueprintMigration
  ( BlueprintMigrationLaunchFailure (..),
    BlueprintMigrationLaunchResult (..),
    BlueprintMigrationRunResult (..),
    ResolvedWindow (..),
    VersionProbeResult (..),
    formatBlueprintMigrationDebugOutput,
    formatMigrationStepLabel,
    formatProbeFailure,
    formatResolvedWindow,
    formatWindowResolutionError,
    highestMigratedVersion,
    parseNotApplicableSignal,
    pendingBlueprintMigrations,
    renderBlueprintMigrationSystemPrompt,
    resolveMigrationWindow,
    runBlueprintMigrationsWith,
    runVersionProbe,
    unstatedNotApplicableReason,
  )
import Seihou.CLI.Commands (BlueprintMigrationOpts (..))
import Seihou.CLI.MigrationCohort
  ( CohortBlueprint (..),
    CohortResolutionError (..),
    resolveCohortBlueprint,
    resolveMigrationCohort,
  )
import Seihou.CLI.Shared (formatVarError, logIO)
import Seihou.Core.Migration
  ( BlueprintMigration (..),
    BlueprintMigrationPlan (..),
    BlueprintMigrationStep (..),
    EntailedEdge (..),
    EntailmentError (..),
    EntailmentSite (..),
    MigrationPlanError (..),
    expandEntailedEdges,
    planBlueprintMigrationChain,
  )
import Seihou.Core.Module (defaultSearchPaths, discoverRunnable)
import Seihou.Core.Types
import Seihou.Core.Version (Version, parseVersion, renderVersion)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.Logger (logError, logWarn)
import Seihou.Effect.ManifestStore (readManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Effect.ProcessInterp (runProcessIO)
import Seihou.Prelude
import System.Directory
  ( createDirectoryIfMissing,
    doesFileExist,
    getCurrentDirectory,
    removeFile,
  )
import System.Exit (ExitCode (..), exitFailure, exitWith)
import System.FilePath (takeDirectory)
import System.Timeout (timeout)

migrationPromptTemplate :: Text
migrationPromptTemplate = TE.decodeUtf8 $(embedFile "data/blueprint-migration-prompt.md")

handleAgentMigrate :: Bool -> PendingAgentConfig -> BlueprintMigrationOpts -> IO ()
handleAgentMigrate debug pendingConfig opts = do
  let level = if opts ^. #verbose then LogVerbose else LogNormal
      manifestPath = ".seihou" </> "manifest.json"

  -- Two --mark-applied combinations cannot mean anything, and both are
  -- refused here rather than resolved by precedence. This is the first thing
  -- the command does: the refusal must land before the blueprint is
  -- discovered, before the version probe runs, and above all before a receipt
  -- is written, so an invalid invocation leaves the filesystem untouched.
  rejectConflictingMarkApplied debug opts

  -- The blueprint's discovery directory is classified into a portable origin
  -- as it is loaded. Receipts are keyed by that origin, not by the name the
  -- user typed, so a blueprint of the same name from another repository has
  -- its own receipts.
  projectRoot <- getCurrentDirectory
  searchPaths <- defaultSearchPaths
  invoked <- discoverMigrationBlueprint level projectRoot searchPaths (opts ^. #name)
  let blueprint = invoked ^. #blueprint

  -- Pre-flight downgrade and origin guard, before a single edge is planned.
  -- Placing it before planning is the point rather than an implementation
  -- detail: a substituted blueprint's edges do not match this project's
  -- receipts, so without the check the command would report that every edge in
  -- the window already has a receipt and exit successfully, having silently
  -- skipped work that never ran. The refusal happens before any receipt is
  -- written, so the manifest is left byte-identical.
  --
  -- No baseline modules are in scope: migration mode applies no baseModules
  -- (see docs/user/blueprint-migrations.md), and refusing for artifacts this
  -- command will not touch would violate the scoping rule in
  -- docs/adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md.
  --
  -- --debug performs no check at all: it contacts no provider and writes
  -- nothing, so a prompt can still be inspected on any machine.
  --
  -- Only the invoked blueprint is in scope here. Blueprints reached by
  -- entailment are not known until the window has been planned, and they are
  -- checked separately once they are; the guard is not moved later to
  -- accommodate them, because the invoked blueprint being substituted is
  -- exactly the case that would make the planned window meaningless.
  unless debug $
    enforceAgentArtifactGuard
      (opts ^. #allowDowngrade)
      manifestPath
      [blueprint ^. #name]
      mempty

  -- Finish provider/model/effort resolution now that the blueprint is loaded:
  -- `agent migrate` reads the same Blueprint record as `agent run`, so it
  -- honors the same launch declaration.
  modelConfig <-
    resolveDeclaredAgentConfig
      level
      ("blueprint '" <> blueprint ^. #name . #unModuleName <> "'")
      pendingConfig
      (agentLaunchDeclaration (blueprint ^. #launch))

  -- The receipts are read before the window is planned, not after, because
  -- the window itself now depends on them: an omitted --from is the highest
  -- version this project has already migrated this blueprint to. The same
  -- list is reused for per-step filtering further down, so the manifest is
  -- read once.
  receipts <- readMigrationReceipts level manifestPath

  window <- resolveWindow level projectRoot invoked receipts opts
  let current = window ^. #fromVersion
      target = window ^. #toVersion
      windowReport = formatResolvedWindow (opts ^. #verbose) window
  unless (null windowReport) $ mapM_ TIO.putStrLn (windowReport <> [""])

  planned <-
    case planBlueprintMigrationChain (blueprint ^. #name . #unModuleName) (blueprint ^. #migrations) current target of
      Left err -> exitErr level (renderPlanError err)
      Right Nothing -> do
        TIO.putStrLn "No blueprint migration needed: --from and --to resolve to the same version."
        pure Nothing
      Right (Just migrationPlan) -> pure (Just migrationPlan)

  case planned of
    Nothing -> pure ()
    Just migrationPlan -> do
      -- Load every blueprint this window reaches by entailment, then flatten
      -- the window into an ordered list of steps, each labelled with the
      -- blueprint that declares it. Both happen before receipts are consulted,
      -- because an entailed step is filtered against its own owner's receipts
      -- rather than the invoked blueprint's.
      let invokedName = blueprint ^. #name . #unModuleName
      cohortResult <-
        resolveMigrationCohort
          projectRoot
          searchPaths
          (Map.singleton invokedName invoked)
          (migrationPlan ^. #steps)
      cohort <- case cohortResult of
        Left err -> exitErr level (renderCohortError err)
        Right resolved -> pure resolved

      -- Every entailed blueprint is an artifact this command is about to
      -- generate from, so ADR 0003's scoping rule reaches it too. The invoked
      -- blueprint was already checked before planning; this covers the rest,
      -- and still lands before any launch.
      let entailedNames =
            [ModuleName name | name <- Map.keys cohort, name /= invokedName]
      unless (debug || null entailedNames) $
        enforceAgentArtifactGuard
          (opts ^. #allowDowngrade)
          manifestPath
          entailedNames
          mempty

      expandedPlan <- case expandEntailedEdges (lookupCohortMigrations cohort) (migrationPlan ^. #steps) of
        Left err -> exitErr level (renderEntailmentError cohort err)
        Right expandedSteps -> pure (migrationPlan & #steps .~ expandedSteps)

      let pending =
            pendingBlueprintMigrations
              (opts ^. #rerun)
              (lookupCohortIdentity cohort)
              receipts
              expandedPlan
      if null pending
        then reportNoPending expandedPlan
        else do
          -- One execution context per blueprint that owns a pending step, so
          -- each step gets its own reference files, allowed tools, and
          -- variables. All of them are resolved now rather than lazily per
          -- step: a user should answer every prompt up front rather than
          -- being interrupted between agent sessions.
          preparedByOwner <- prepareCohort level modelConfig opts cohort pending
          traceSink <- traceSinkForConfig level modelConfig
          context <- gatherAgentContext
          let signalPath = notApplicableSignalPath projectRoot
              renderStep position total step =
                case Map.lookup (step ^. #owner) preparedByOwner of
                  Nothing -> missingOwnerMessage step
                  Just prepared ->
                    renderBlueprintMigrationSystemPrompt
                      migrationPromptTemplate
                      signalPath
                      context
                      prepared
                      position
                      total
                      step
              renderDebugStep position total step =
                renderStep position total step
                  <> maybe
                    ""
                    ("\n\n===== Initial user instruction =====\n" <>)
                    (opts ^. #prompt)

          if debug
            then
              TIO.putStrLn $
                "Blueprint migrations for "
                  <> invokedName
                  <> ": "
                  <> renderVersion (expandedPlan ^. #from)
                  <> " -> "
                  <> renderVersion (expandedPlan ^. #to)
                  <> "\n"
                  <> formatBlueprintMigrationDebugOutput renderDebugStep pending
            else do
              -- The agent needs somewhere to put the signal file, and the
              -- directory is created by the first receipt anyway.
              createDirectoryIfMissing True (takeDirectory signalPath)
              result <-
                runBlueprintMigrationsWith
                  (launchMigration traceSink modelConfig opts preparedByOwner signalPath renderStep)
                  (recordMigration manifestPath cohort)
                  pending
              handleRunResult level (blueprint ^. #name) result

-- | Refuse the two @--mark-applied@ combinations that contradict themselves.
--
-- Neither has a defensible winner, so neither gets one. @--rerun@ means "run
-- these edges again even though receipts exist" and @--mark-applied@ means
-- "run nothing"; @--debug@ is a true dry run that writes nothing and
-- @--mark-applied@ exists to write receipts. Letting either silently win
-- would leave a user believing something happened that did not.
--
-- The refusal block follows the shape 'Seihou.CLI.ManifestGuard' established
-- for this command's other refusal — a @✗@ line naming what was refused, then
-- an indented paragraph explaining the conflict and what to do instead.
rejectConflictingMarkApplied :: Bool -> BlueprintMigrationOpts -> IO ()
rejectConflictingMarkApplied debug opts
  | not (opts ^. #markApplied) = pure ()
  | opts ^. #rerun =
      refuse
        [ "✗ --mark-applied and --rerun cannot be combined.",
          "",
          "  --rerun runs edges that already have receipts; --mark-applied records",
          "  receipts without running anything. Pick one."
        ]
  | debug =
      refuse
        [ "✗ --mark-applied cannot be combined with --debug.",
          "",
          "  --debug renders prompts without changing anything; --mark-applied writes",
          "  migration receipts. Run it without --debug when you are ready to record."
        ]
  | otherwise = pure ()
  where
    refuse ls = do
      TIO.putStrLn (T.intercalate "\n" ls)
      exitFailure

-- | What a step's owning blueprint declares, for the pure expander. A name
-- absent from the cohort was not installed, which the expander reports against
-- the edge that named it.
lookupCohortMigrations :: Map Text CohortBlueprint -> Text -> Maybe [BlueprintMigration]
lookupCohortMigrations cohort name =
  (^. #blueprint . #migrations) <$> Map.lookup name cohort

-- | A step's owning blueprint's recorded identity, for receipt matching. This
-- is the whole cross-entry-point property in one function: a step owned by
-- @kiroku-upgrade@ is filtered against kiroku's receipts no matter which
-- blueprint the user named.
lookupCohortIdentity :: Map Text CohortBlueprint -> Text -> Maybe (ModuleName, ArtifactOrigin)
lookupCohortIdentity cohort name = do
  resolved <- Map.lookup name cohort
  pure (resolved ^. #blueprint . #name, resolved ^. #origin)

-- | Prepare one execution context per blueprint that owns a pending step.
--
-- Blueprints in the cohort that own no pending step are deliberately skipped:
-- preparing one resolves its variables, which can prompt, and asking a user to
-- answer questions for a blueprint whose every edge already has a receipt is
-- pure friction.
prepareCohort ::
  LogLevel ->
  AgentModelConfig ->
  BlueprintMigrationOpts ->
  Map Text CohortBlueprint ->
  [BlueprintMigrationStep] ->
  IO (Map Text PreparedBlueprintExecution)
prepareCohort level modelConfig opts cohort pending =
  Map.fromList <$> traverse prepareOne owners
  where
    owners = nub [step ^. #owner | step <- pending]

    prepareOne name = case Map.lookup name cohort of
      -- Unreachable: every owner came out of a plan the cohort resolved.
      Nothing -> exitErr level ("Internal error: no blueprint loaded for migration step owner '" <> name <> "'.")
      Just resolved -> do
        prepared <-
          prepare level modelConfig opts (resolved ^. #blueprint) (resolved ^. #blueprintDir)
        pure (name, prepared)

-- | Unreachable in production — 'prepareCohort' covers every pending step's
-- owner — but a rendered message beats a partial-function crash if the two
-- ever drift apart.
missingOwnerMessage :: BlueprintMigrationStep -> Text
missingOwnerMessage step =
  "Internal error: no execution context prepared for '" <> step ^. #owner <> "'."

discoverMigrationBlueprint :: LogLevel -> FilePath -> [FilePath] -> ModuleName -> IO CohortBlueprint
discoverMigrationBlueprint level projectRoot searchPaths requestedName = do
  result <- resolveCohortBlueprint projectRoot searchPaths requestedName
  case result of
    Right resolved -> pure resolved
    Left err -> exitErr level (renderCohortError err)

renderCohortError :: CohortResolutionError -> Text
renderCohortError = \case
  CohortArtifactWrongKind name kind ->
    "'" <> name ^. #unModuleName <> "' is a " <> kind <> ", not a blueprint."
  CohortArtifactMissing name searched ->
    renderModuleLoadError (ModuleNotFound name searched)
  CohortArtifactUnusable err -> renderModuleLoadError err

-- | Turn an expansion failure into the message a blueprint author has to act
-- on. These are the only feedback an author gets about an @entails@ list, so
-- each says which blueprint is at fault and what to do next.
renderEntailmentError :: Map Text CohortBlueprint -> EntailmentError -> Text
renderEntailmentError cohort = \case
  EntailedBlueprintNotFound site name ->
    renderSite site
      <> " entails blueprint '"
      <> name
      <> "', which is not installed on this machine.\n\n"
      <> "  Install it, then re-run:\n"
      <> "    seihou install <url> --module "
      <> name
  EntailedEdgeNotDeclared site name fromVersion toVersion ->
    renderSite site
      <> " entails edge "
      <> fromVersion
      <> " -> "
      <> toVersion
      <> " of '"
      <> name
      <> "', which declares no such edge.\n\n"
      <> "  This is an authoring error in '"
      <> site ^. #blueprint
      <> "'. Report it upstream.\n"
      <> "  Declared edges of '"
      <> name
      <> "': "
      <> declaredEdges name
  EntailmentCycle chain ->
    "blueprint migration entailment forms a cycle:\n"
      <> T.intercalate "\n" ["    " <> link | link <- chain]
      <> "\n\n  Each of these edges declares that the next must run first, so"
      <> " there is no order that satisfies them all.\n"
      <> "  This is an authoring error in the blueprints listed. Report it upstream."
  where
    renderSite site =
      "'" <> site ^. #blueprint <> "' edge " <> site ^. #from <> " -> " <> site ^. #to

    -- The likeliest cause of a missing edge is an off-by-one in a version
    -- string, so showing the real list usually makes the mistake obvious.
    declaredEdges name = case Map.lookup name cohort of
      Nothing -> "(none: the blueprint could not be read)"
      Just resolved ->
        case [edge ^. #from <> " -> " <> edge ^. #to | edge <- resolved ^. #blueprint . #migrations] of
          [] -> "(it declares no migrations at all)"
          rendered -> T.intercalate ", " rendered

-- | Decide both ends of the version window, running the blueprint's declared
-- probe only if it is needed.
--
-- The probe is skipped entirely when @--to@ was supplied: an explicit
-- invocation must never execute a subprocess whose answer it would discard.
-- It /is/ run under @--debug@, though nothing else there is: it is a
-- read-only command the blueprint supplies, and refusing to run it would make
-- debug output diverge from a real run in exactly the way that matters — the
-- window, and therefore which edges are shown.
--
-- Receipts are matched against the invoked blueprint's own identity. That is
-- the same "by owner" rule the per-step filtering uses: the window is
-- expressed in the invoked library's version space, so the receipts that
-- bound it are the ones the invoked blueprint owns.
resolveWindow ::
  LogLevel ->
  FilePath ->
  CohortBlueprint ->
  [AppliedBlueprintMigration] ->
  BlueprintMigrationOpts ->
  IO ResolvedWindow
resolveWindow level projectRoot invoked receipts opts = do
  fromFlag <- traverse (parseRequestedVersion level "--from") (opts ^. #from)
  toFlag <- traverse (parseRequestedVersion level "--to") (opts ^. #to)
  probed <- case (toFlag, invoked ^. #blueprint . #versionProbe) of
    (Just _, _) -> pure Nothing
    (Nothing, Nothing) -> pure Nothing
    (Nothing, Just command) -> do
      result <- executeVersionProbe level projectRoot command
      pure $ case result of
        ProbeVersion version -> Just (version, command)
        _ -> Nothing
  let recorded =
        highestMigratedVersion
          (invoked ^. #origin)
          (invoked ^. #blueprint . #name)
          receipts
  case resolveMigrationWindow fromFlag toFlag probed recorded of
    Right window -> pure window
    Left err ->
      exitErr level (formatWindowResolutionError (invoked ^. #blueprint . #name) err)

-- | Run one version probe under a wall-clock bound, reporting anything that
-- is not a version and returning it for the caller to discard.
--
-- Every failure here is a warning rather than an error. The user did not
-- write the probe, and still has @--to@; turning an author's broken command
-- into a hard failure would take a working escape hatch away from the person
-- who cannot fix it.
executeVersionProbe :: LogLevel -> FilePath -> Text -> IO VersionProbeResult
executeVersionProbe level projectRoot command = do
  bounded <- timeout probeTimeoutMicroseconds run
  let result = fromMaybe (ProbeExitedNonZero 124 timedOut) bounded
  mapM_ (logIO level . logWarn) (formatProbeFailure command result)
  pure result
  where
    run = runEff $ runProcessIO $ runVersionProbe command projectRoot

    -- 124 is what `timeout(1)` reports, which is the closest thing to a
    -- convention for "the command did not finish".
    timedOut =
      "timed out after "
        <> T.pack (show (probeTimeoutMicroseconds `div` 1_000_000))
        <> " seconds"

-- | How long a version probe may take before the command stops waiting for
-- it. Generous enough for a cold @nix eval@, short enough that a probe that
-- hangs forever does not hang @seihou agent migrate@ forever with it.
probeTimeoutMicroseconds :: Int
probeTimeoutMicroseconds = 60 * 1_000_000

parseRequestedVersion :: LogLevel -> Text -> Text -> IO Version
parseRequestedVersion level flag raw =
  case parseVersion raw of
    Just version -> pure version
    Nothing -> exitErr level (flag <> " value '" <> raw <> "' is not a valid dotted numeric version.")

readMigrationReceipts :: LogLevel -> FilePath -> IO [AppliedBlueprintMigration]
readMigrationReceipts level manifestPath = do
  result <- runEff $ runFilesystem $ runManifestStore manifestPath readManifest
  case result of
    Left err -> exitErr level ("Error reading migration receipts: " <> err)
    Right Nothing -> pure []
    Right (Just manifest) -> pure (manifest ^. #blueprintMigrations)

prepare ::
  LogLevel ->
  AgentModelConfig ->
  BlueprintMigrationOpts ->
  Blueprint ->
  FilePath ->
  IO PreparedBlueprintExecution
prepare level modelConfig opts blueprint blueprintDir = do
  let providerCanMountFiles =
        modelConfig ^. #provider == AgentProviderClaudeCli
          || modelConfig ^. #provider == AgentProviderCodexCli
  result <-
    prepareBlueprintExecution
      BlueprintExecutionRequest
        { blueprint = blueprint,
          blueprintDir = blueprintDir,
          variableOverrides = opts ^. #vars,
          namespaceOverride = opts ^. #namespace,
          contextOverride = opts ^. #context,
          canMountFiles = providerCanMountFiles,
          logLevel = level
        }
  case result of
    Left errs -> do
      logIO level $ logError "Error resolving blueprint migration variables:"
      mapM_ (logIO level . logError . ("  " <>) . formatVarError) errs
      exitFailure
    Right prepared -> pure prepared

-- | Where an edge reports that it does not apply.
--
-- It lives under @.seihou\/@ rather than in the working tree so a signal a
-- crashed run left behind never shows up in @git status@, and the leading dot
-- keeps it out of the way of @.seihou@'s own contents.
notApplicableSignalPath :: FilePath -> FilePath
notApplicableSignalPath projectRoot = projectRoot </> ".seihou" </> ".migrate-signal"

-- | Delete a signal left behind by an earlier edge or a crashed run, so it
-- cannot be misread as this edge's answer.
clearNotApplicableSignal :: FilePath -> IO ()
clearNotApplicableSignal signalPath = do
  exists <- doesFileExist signalPath
  when exists (removeFile signalPath)

-- | Read and consume the signal an edge may have written.
--
-- The file's existence is the signal: an agent creates it deliberately, with
-- its own tools, at a path only this command names. An empty one therefore
-- still means "not applicable", it just fails to say why.
readNotApplicableSignal :: FilePath -> IO (Maybe Text)
readNotApplicableSignal signalPath = do
  exists <- doesFileExist signalPath
  if not exists
    then pure Nothing
    else do
      contents <- TIO.readFile signalPath
      removeFile signalPath
      let firstLine = listToMaybe (filter (not . T.null) (map T.strip (T.lines contents)))
      pure (Just (fromMaybe unstatedNotApplicableReason firstLine))

launchMigration ::
  -- | built once per command, so every migration edge appends to one destination
  TraceSink ->
  AgentModelConfig ->
  BlueprintMigrationOpts ->
  -- | one execution context per owning blueprint, keyed by name
  Map Text PreparedBlueprintExecution ->
  -- | where this edge reports that it does not apply
  FilePath ->
  (Int -> Int -> BlueprintMigrationStep -> Text) ->
  Int ->
  Int ->
  BlueprintMigrationStep ->
  IO (Either BlueprintMigrationLaunchFailure BlueprintMigrationLaunchResult)
launchMigration traceSink modelConfig opts preparedByOwner signalPath renderStep position total step = do
  TIO.putStrLn $
    "Running blueprint migration "
      <> stepLabel
      <> ": "
      <> formatMigrationStepLabel step
  clearNotApplicableSignal signalPath
  let systemPrompt = renderStep position total step
  case Map.lookup (step ^. #owner) preparedByOwner of
    Nothing -> pure (Left (BlueprintMigrationProviderFailure (missingOwnerMessage step)))
    Just prepared -> case modelConfig ^. #provider of
      AgentProviderClaudeCli -> launchInteractive prepared systemPrompt
      AgentProviderCodexCli -> launchInteractive prepared systemPrompt
      AgentProviderAnthropic -> launchCompletion systemPrompt
      AgentProviderOpenAI -> launchCompletion systemPrompt
  where
    stepLabel = T.pack (show position) <> "/" <> T.pack (show total)

    -- An interactive session communicates only through its exit code, so the
    -- signal file is the one channel an agent has to report inapplicability.
    -- Only the owning blueprint's files/ directory is mounted: handing this
    -- step another cohort member's reference material invites the agent to
    -- pre-apply work the framing prompt tells it to leave for a later step.
    launchInteractive prepared systemPrompt = do
      exitCode <-
        launchConfiguredAgentAddingDirs
          (maybeToList (prepared ^. #mountedFilesDir))
          modelConfig
          (prepared ^. #allowedTools)
          False
          systemPrompt
          (opts ^. #prompt)
      case exitCode of
        ExitSuccess -> Right <$> sessionResultFromSignal Nothing
        failure -> do
          -- A failed session's signal is not this edge's answer.
          clearNotApplicableSignal signalPath
          pure (Left (BlueprintMigrationProcessFailure failure))

    -- An API provider hands us its reply directly, so the marker line works.
    -- The signal file is still checked, because a provider given tool access
    -- may take the prompt's first instruction rather than its fallback.
    launchCompletion systemPrompt = do
      result <-
        runAgentCompletion
          (buildAgentCompletionRequestWith traceSink modelConfig systemPrompt (opts ^. #prompt))
      case result of
        Left err -> do
          clearNotApplicableSignal signalPath
          pure (Left (BlueprintMigrationProviderFailure err))
        Right assistantText -> do
          TIO.putStrLn assistantText
          Right <$> sessionResultFromSignal (parseNotApplicableSignal assistantText)

    sessionResultFromSignal parsedReason = do
      fileReason <- readNotApplicableSignal signalPath
      case fileReason <|> parsedReason of
        Nothing -> pure BlueprintMigrationSessionReturned
        Just reason -> do
          TIO.putStrLn $
            "Blueprint migration "
              <> stepLabel
              <> ": "
              <> formatMigrationStepLabel step
              <> " — not applicable: "
              <> reason
          pure (BlueprintMigrationSessionNotApplicable reason)

-- | Write one edge's receipt under the identity of the blueprint that /owns/
-- the edge, not the one the user named on the command line.
--
-- This looks like a mistake to a reader who does not know the design, and it
-- is the single line that makes fan-out correct. A project that crossed
-- kiroku's edge by running @keiro-upgrade@ has a receipt saying so under
-- @kiroku-upgrade@'s name and origin, so running @kiroku-upgrade@ directly
-- afterwards finds it and crosses nothing twice. Recording under the invoking
-- blueprint would make the same work look like two different edges.
recordMigration ::
  FilePath ->
  -- | every blueprint this run loaded, keyed by name
  Map Text CohortBlueprint ->
  BlueprintMigrationStep ->
  MigrationOutcome ->
  IO (Either Text ())
recordMigration manifestPath cohort step migrationOutcome =
  case Map.lookup (step ^. #owner) cohort of
    -- Unreachable: the step came out of a plan this cohort resolved.
    Nothing -> pure (Left (missingOwnerMessage step))
    Just owner -> do
      now <- getCurrentTime
      recordAppliedBlueprintMigration
        manifestPath
        AppliedBlueprintMigration
          { name = owner ^. #blueprint . #name,
            origin = owner ^. #origin,
            blueprintVersion = owner ^. #blueprint . #version,
            fromVersion = step ^. #edge . #from,
            toVersion = step ^. #edge . #to,
            outcome = migrationOutcome,
            appliedAt = now,
            agentSessionId = Nothing
          }

handleRunResult :: LogLevel -> ModuleName -> BlueprintMigrationRunResult -> IO ()
handleRunResult level blueprintName = \case
  BlueprintMigrationNoWork ->
    TIO.putStrLn "No pending blueprint migrations."
  BlueprintMigrationComplete completed -> do
    let notApplicable = length [() | (_, MigrationNotApplicable _) <- completed]
    TIO.putStrLn $
      "Completed "
        <> T.pack (show (length completed))
        <> " blueprint migration(s) for '"
        <> blueprintName ^. #unModuleName
        <> "'"
        <> ( if notApplicable > 0
               then " (" <> T.pack (show notApplicable) <> " not applicable)"
               else ""
           )
        <> "."
  BlueprintMigrationLaunchFailed step failure -> do
    let prefix =
          "Blueprint migration "
            <> formatMigrationStepLabel step
            <> " failed; completed earlier edges remain recorded. "
        retry = "Fix the provider error, then rerun the same command to resume."
    case failure of
      BlueprintMigrationProcessFailure exitCode -> do
        logIO level $ logError $ prefix <> "Provider exited with " <> T.pack (show exitCode) <> ". " <> retry
        exitWith exitCode
      BlueprintMigrationProviderFailure err -> do
        logIO level $ logError $ prefix <> err <> " " <> retry
        exitFailure
  BlueprintMigrationRecordFailed step err -> do
    logIO level $
      logError $
        "Agent completed blueprint migration "
          <> formatMigrationStepLabel step
          <> ", but its receipt could not be recorded: "
          <> err
          <> ". The next edge was not started; repair manifest access, then rerun the same command."
    exitFailure

reportNoPending :: BlueprintMigrationPlan -> IO ()
reportNoPending migrationPlan
  | null (migrationPlan ^. #steps) =
      TIO.putStrLn "No blueprint migrations are declared inside the requested version window."
  | otherwise =
      TIO.putStrLn "All blueprint migrations in the requested version window already have receipts."

renderPlanError :: MigrationPlanError -> Text
renderPlanError (MigrationVersionUnparseable raw) =
  "the blueprint declares an unparseable migration version: '" <> raw <> "'."
renderPlanError (MigrationDowngradeNotSupported current target) =
  "blueprint migration downgrades are not supported: --from "
    <> renderVersion current
    <> ", --to "
    <> renderVersion target
    <> "."
renderPlanError (MigrationDuplicateEdge fromVersion _) =
  "the blueprint declares more than one migration starting at "
    <> renderVersion fromVersion
    <> "; the author must merge or remove the duplicate."

renderModuleLoadError :: ModuleLoadError -> Text
renderModuleLoadError = \case
  ModuleNotFound name searched ->
    "Blueprint '"
      <> name ^. #unModuleName
      <> "' not found. Searched in:\n"
      <> T.intercalate "\n" (map (("  " <>) . T.pack) searched)
  DhallEvalError name msg ->
    "Failed to evaluate '" <> name ^. #unModuleName <> "': " <> msg
  DhallDecodeError name msg ->
    "Failed to decode '" <> name ^. #unModuleName <> "': " <> msg
  ValidationError name msgs ->
    "Validation failed for '"
      <> name ^. #unModuleName
      <> "':\n"
      <> T.intercalate "\n" (map ("  " <>) msgs)
  CircularDependency names ->
    "Circular dependency detected: " <> T.intercalate " -> " (map (^. #unModuleName) names)
  MissingSourceFile name path ->
    "Missing source file in '" <> name ^. #unModuleName <> "': " <> T.pack path
  RegistryEvalError path msg ->
    "Failed to evaluate registry at '" <> path <> "': " <> msg

exitErr :: LogLevel -> Text -> IO a
exitErr level msg = do
  logIO level (logError msg)
  exitFailure
