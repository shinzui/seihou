module Seihou.CLI.AgentConfig
  ( -- * Inputs
    AgentConfigInputs (..),
    baseAgentConfigInputs,
    AgentSettingFlags (..),
    noAgentSettingFlags,

    -- * Command identity
    AgentCommandName (..),
    agentCommandSegment,
    agentCommandLabel,
    allAgentCommands,

    -- * Config keys and environment variables
    agentProviderConfigKey,
    agentModelConfigKey,
    agentEffortConfigKey,
    agentTraceConfigKey,
    agentTracePathConfigKey,
    agentCommandProviderConfigKey,
    agentCommandModelConfigKey,
    agentCommandEffortConfigKey,
    agentCommandTraceConfigKey,
    agentProviderEnvVar,
    agentModelEnvVar,
    agentEffortEnvVar,
    agentTraceEnvVar,

    -- * Provenance
    AgentConfigSource (..),
    AgentField (..),
    ResolvedAgentField (..),
    agentConfigSourceLabel,

    -- * Resolution
    resolveAgentModelConfig,
    resolveAgentModelConfigFor,
    resolveTracePath,
    loadAgentModelConfig,
    loadAgentModelConfigFor,

    -- * Artifact-declared launch settings
    AgentLaunchDeclaration (..),
    noAgentLaunchDeclaration,
    agentLaunchDeclaration,
    validateAgentLaunchDeclaration,
    PendingAgentConfig (..),
    loadPendingAgentConfig,
    resolvePendingAgentConfig,
    resolvedAgentModelConfig,
    formatResolvedAgentProvenance,
    resolveDeclaredAgentConfig,

    -- * Whole-configuration inspection
    ResolvedCommandConfig (..),
    loadResolvedAgentConfig,
  )
where

import Baikai.ThinkingLevel (ThinkingLevel)
import Control.Applicative ((<|>))
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Text qualified as T
import Seihou.CLI.AgentCompletion
  ( AgentModelConfig (..),
    AgentProvider (..),
    TraceSetting (..),
    defaultAgentModelConfig,
    defaultModelForProvider,
    effortFromText,
    effortToText,
    providerFromText,
    providerToText,
    traceFromText,
    traceToText,
  )
import Seihou.CLI.Shared (formatConfigError, logIO)
import Seihou.Core.Types (AgentLaunch (..), LogLevel)
import Seihou.Effect.ConfigReader (readGlobalConfig, readLocalConfig)
import Seihou.Effect.ConfigReaderInterp (runConfigReader)
import Seihou.Effect.Logger (logError, logInfo)
import Seihou.Prelude
import System.Environment (lookupEnv)
import System.Exit (exitFailure)

-- | All the raw material provider/model resolution draws on, in one record so
-- the pure resolver can be unit-tested without touching the filesystem or the
-- environment.
--
-- The two @cli*FromSubcommand@ flags record whether the (already combined)
-- winning CLI flag originated from the subcommand's own @--provider@/@--model@
-- (as opposed to the parent @seihou agent@ flag). They only affect the
-- provenance label reported for a CLI-sourced value; they never change which
-- value wins.
data AgentConfigInputs = AgentConfigInputs
  { cliProvider :: !(Maybe Text),
    cliModel :: !(Maybe Text),
    cliEffort :: !(Maybe Text),
    cliTrace :: !(Maybe Text),
    cliProviderFromSubcommand :: !Bool,
    cliModelFromSubcommand :: !Bool,
    cliEffortFromSubcommand :: !Bool,
    cliTraceFromSubcommand :: !Bool,
    envProvider :: !(Maybe Text),
    envModel :: !(Maybe Text),
    envEffort :: !(Maybe Text),
    envTrace :: !(Maybe Text),
    -- | Declared by the blueprint or prompt being run, when the command has
    -- one. Only populated once the artifact has been loaded; see
    -- 'resolvePendingAgentConfig'.
    declaredProvider :: !(Maybe Text),
    declaredModel :: !(Maybe Text),
    declaredEffort :: !(Maybe Text),
    -- | Reserved: no schema field feeds this yet. It exists so all four
    -- settings are structurally identical, making a future @launch.trace@ an
    -- insertion rather than a redesign.
    declaredTrace :: !(Maybe Text),
    localConfig :: !(Map Text Text),
    globalConfig :: !(Map Text Text)
  }
  deriving stock (Eq, Generic, Show)

-- | An 'AgentConfigInputs' with nothing set: no flags, no environment, empty
-- config maps. Handy as a base for tests and for callers that only populate a
-- few fields.
baseAgentConfigInputs :: AgentConfigInputs
baseAgentConfigInputs =
  AgentConfigInputs
    { cliProvider = Nothing,
      cliModel = Nothing,
      cliEffort = Nothing,
      cliTrace = Nothing,
      cliProviderFromSubcommand = False,
      cliModelFromSubcommand = False,
      cliEffortFromSubcommand = False,
      cliTraceFromSubcommand = False,
      envProvider = Nothing,
      envModel = Nothing,
      envEffort = Nothing,
      envTrace = Nothing,
      declaredProvider = Nothing,
      declaredModel = Nothing,
      declaredEffort = Nothing,
      declaredTrace = Nothing,
      localConfig = Map.empty,
      globalConfig = Map.empty
    }

-- | The four agent settings as supplied on one command-line tier — either the
-- parent @seihou agent@ command or the subcommand itself.
--
-- Grouping them keeps the loader signatures honest: four same-typed
-- @Maybe Text@ values in a row, twice over, are trivial to transpose by
-- accident, and the compiler would not notice.
data AgentSettingFlags = AgentSettingFlags
  { provider :: !(Maybe Text),
    model :: !(Maybe Text),
    effort :: !(Maybe Text),
    trace :: !(Maybe Text)
  }
  deriving stock (Eq, Generic, Show)

-- | No flags supplied on this tier.
noAgentSettingFlags :: AgentSettingFlags
noAgentSettingFlags =
  AgentSettingFlags
    { provider = Nothing,
      model = Nothing,
      effort = Nothing,
      trace = Nothing
    }

-- | Fold the parent and subcommand flag tiers into gathered inputs. The
-- subcommand's own flag wins over the parent @seihou agent@ flag; which tier
-- supplied the winner only affects the provenance label, never the value.
applyAgentSettingFlags :: AgentSettingFlags -> AgentSettingFlags -> AgentConfigInputs -> AgentConfigInputs
applyAgentSettingFlags parent command inputs =
  inputs
    { cliProvider = command.provider <|> parent.provider,
      cliModel = command.model <|> parent.model,
      cliEffort = command.effort <|> parent.effort,
      cliTrace = command.trace <|> parent.trace,
      cliProviderFromSubcommand = isJust command.provider,
      cliModelFromSubcommand = isJust command.model,
      cliEffortFromSubcommand = isJust command.effort,
      cliTraceFromSubcommand = isJust command.trace
    }

-- | The agent-driven commands whose provider/model can be configured
-- independently. Each maps to a config-key segment (see 'agentCommandSegment').
data AgentCommandName
  = AgentCmdAssist
  | AgentCmdBootstrap
  | AgentCmdSetup
  | AgentCmdRun
  | AgentCmdMigrate
  | AgentCmdPromptRun
  deriving stock (Eq, Show, Enum, Bounded)

-- | The token used inside per-command config keys, e.g. @"assist"@ in
-- @agent.assist.model@.
agentCommandSegment :: AgentCommandName -> Text
agentCommandSegment AgentCmdAssist = "assist"
agentCommandSegment AgentCmdBootstrap = "bootstrap"
agentCommandSegment AgentCmdSetup = "setup"
agentCommandSegment AgentCmdRun = "run"
agentCommandSegment AgentCmdMigrate = "migrate"
agentCommandSegment AgentCmdPromptRun = "prompt-run"

-- | Human-facing label for display, e.g. @"prompt run"@ for the two-word
-- @seihou prompt run@ command.
agentCommandLabel :: AgentCommandName -> Text
agentCommandLabel AgentCmdPromptRun = "prompt run"
agentCommandLabel c = agentCommandSegment c

-- | Every configurable agent command, in display order.
allAgentCommands :: [AgentCommandName]
allAgentCommands = [minBound .. maxBound]

-- | The cross-command default provider key, @agent.provider@.
agentProviderConfigKey :: Text
agentProviderConfigKey = "agent.provider"

-- | The cross-command default model key, @agent.model@.
agentModelConfigKey :: Text
agentModelConfigKey = "agent.model"

-- | The cross-command default reasoning-effort key, @agent.effort@.
agentEffortConfigKey :: Text
agentEffortConfigKey = "agent.effort"

-- | The cross-command default trace-destination key, @agent.trace@.
agentTraceConfigKey :: Text
agentTraceConfigKey = "agent.trace"

-- | The trace file path key, @agent.tracePath@. Free-form (any path) and
-- deliberately not per-command: one project writes one trace file.
agentTracePathConfigKey :: Text
agentTracePathConfigKey = "agent.tracePath"

-- | The per-command provider key, e.g. @agent.assist.provider@.
agentCommandProviderConfigKey :: AgentCommandName -> Text
agentCommandProviderConfigKey c = "agent." <> agentCommandSegment c <> ".provider"

-- | The per-command model key, e.g. @agent.run.model@.
agentCommandModelConfigKey :: AgentCommandName -> Text
agentCommandModelConfigKey c = "agent." <> agentCommandSegment c <> ".model"

-- | The per-command reasoning-effort key, e.g. @agent.run.effort@.
agentCommandEffortConfigKey :: AgentCommandName -> Text
agentCommandEffortConfigKey c = "agent." <> agentCommandSegment c <> ".effort"

-- | The per-command trace-destination key, e.g. @agent.run.trace@.
agentCommandTraceConfigKey :: AgentCommandName -> Text
agentCommandTraceConfigKey c = "agent." <> agentCommandSegment c <> ".trace"

agentProviderEnvVar :: String
agentProviderEnvVar = "SEIHOU_AGENT_PROVIDER"

agentModelEnvVar :: String
agentModelEnvVar = "SEIHOU_AGENT_MODEL"

agentEffortEnvVar :: String
agentEffortEnvVar = "SEIHOU_AGENT_EFFORT"

agentTraceEnvVar :: String
agentTraceEnvVar = "SEIHOU_AGENT_TRACE"

-- | Which of the resolvable fields a value belongs to. Used only to build
-- provenance labels.
data AgentField = ProviderField | ModelField | EffortField | TraceField
  deriving stock (Eq, Show)

-- | Where a resolved value came from, highest precedence first.
data AgentConfigSource
  = -- | @--provider@/@--model@ on the subcommand.
    SourceCliSubcommand
  | -- | @--provider@/@--model@ on @seihou agent@.
    SourceCliParent
  | -- | @SEIHOU_AGENT_PROVIDER@/@SEIHOU_AGENT_MODEL@.
    SourceEnv
  | -- | The blueprint's or prompt's own @launch.<field>@ declaration.
    SourceArtifactDeclaration
  | -- | Local @agent.<command>.<field>@.
    SourceLocalCommand
  | -- | Local @agent.<field>@.
    SourceLocalDefault
  | -- | Global @agent.<command>.<field>@.
    SourceGlobalCommand
  | -- | Global @agent.<field>@.
    SourceGlobalDefault
  | -- | The hard-coded fallback (provider @claude-cli@, model unset).
    SourceBuiltinDefault
  deriving stock (Eq, Show)

-- | A resolved value paired with the source that supplied it.
data ResolvedAgentField a = ResolvedAgentField
  { value :: !a,
    source :: !AgentConfigSource
  }
  deriving stock (Eq, Generic, Show)

-- | A short human label describing where a value came from, suitable for
-- bracketed display. For config-file sources it names the concrete key that
-- won, e.g. @"local: agent.run.model"@ or @"global: agent.provider"@.
agentConfigSourceLabel :: AgentCommandName -> AgentField -> AgentConfigSource -> Text
agentConfigSourceLabel c field src =
  case src of
    SourceCliSubcommand -> "flag on subcommand"
    SourceCliParent -> "flag on `seihou agent`"
    SourceEnv -> "env: " <> T.pack (envVarName field)
    SourceArtifactDeclaration -> artifactKind c <> ": launch." <> fieldName field
    SourceLocalCommand -> "local: " <> commandKey field c
    SourceLocalDefault -> "local: " <> defaultKey field
    SourceGlobalCommand -> "global: " <> commandKey field c
    SourceGlobalDefault -> "global: " <> defaultKey field
    SourceBuiltinDefault -> "built-in default"

-- | Which kind of artifact declares launch settings for a command, so the
-- provenance label names the thing the user actually ran.
artifactKind :: AgentCommandName -> Text
artifactKind AgentCmdPromptRun = "prompt"
artifactKind _ = "blueprint"

fieldName :: AgentField -> Text
fieldName ProviderField = "provider"
fieldName ModelField = "model"
fieldName EffortField = "effort"
fieldName TraceField = "trace"

envVarName :: AgentField -> String
envVarName ProviderField = agentProviderEnvVar
envVarName ModelField = agentModelEnvVar
envVarName EffortField = agentEffortEnvVar
envVarName TraceField = agentTraceEnvVar

defaultKey :: AgentField -> Text
defaultKey ProviderField = agentProviderConfigKey
defaultKey ModelField = agentModelConfigKey
defaultKey EffortField = agentEffortConfigKey
defaultKey TraceField = agentTraceConfigKey

commandKey :: AgentField -> AgentCommandName -> Text
commandKey ProviderField = agentCommandProviderConfigKey
commandKey ModelField = agentCommandModelConfigKey
commandKey EffortField = agentCommandEffortConfigKey
commandKey TraceField = agentCommandTraceConfigKey

-- | The full result of resolving one command's provider and model, with
-- provenance, used by the @seihou agent config@ inspection command.
data ResolvedCommandConfig = ResolvedCommandConfig
  { command :: !AgentCommandName,
    provider :: !(ResolvedAgentField AgentProvider),
    model :: !(ResolvedAgentField (Maybe Text)),
    effort :: !(ResolvedAgentField (Maybe ThinkingLevel)),
    trace :: !(ResolvedAgentField TraceSetting),
    -- | The configured @agent.tracePath@, if any. Carried without provenance:
    -- it is free-form, has no CLI flag and no per-command variant, so there is
    -- no precedence story worth displaying.
    tracePath :: !(Maybe FilePath)
  }
  deriving stock (Eq, Generic, Show)

-- | Flat resolver, preserved for backward compatibility. It never consults the
-- per-command config keys, so a caller with only @agent.provider@/@agent.model@
-- set (or none) gets exactly the historical behavior.
resolveAgentModelConfig :: AgentConfigInputs -> Either Text AgentModelConfig
resolveAgentModelConfig inputs = do
  provider <-
    resolveProvider
      [ candidate inputs.cliProvider SourceCliSubcommand,
        candidate inputs.envProvider SourceEnv,
        candidate (Map.lookup agentProviderConfigKey inputs.localConfig) SourceLocalDefault,
        candidate (Map.lookup agentProviderConfigKey inputs.globalConfig) SourceGlobalDefault
      ]
  let modelField =
        applyProviderDefaultModel provider.value $
          resolveModel
            [ candidate inputs.cliModel SourceCliSubcommand,
              candidate inputs.envModel SourceEnv,
              candidate (Map.lookup agentModelConfigKey inputs.localConfig) SourceLocalDefault,
              candidate (Map.lookup agentModelConfigKey inputs.globalConfig) SourceGlobalDefault
            ]
  pure
    AgentModelConfig
      { provider = provider.value,
        model = modelField.value,
        effort = Nothing,
        trace = TraceOff,
        tracePath = Nothing
      }

-- | Resolve the provider, model, and reasoning effort for a specific command,
-- honoring the full precedence chain including the per-command config tiers, and
-- reporting the source of each value.
--
-- Precedence, highest first: subcommand flag, parent @agent@ flag, environment
-- variable, the artifact's own @launch.<field>@ declaration, local
-- @agent.<command>.<field>@, local @agent.<field>@, global
-- @agent.<command>.<field>@, global @agent.<field>@, built-in default.
--
-- The declaration tier is only populated for commands that load an artifact
-- first; see 'resolvePendingAgentConfig'. For every other caller the
-- @declared*@ inputs are 'Nothing' and this behaves exactly as it did before
-- the tier existed.
resolveAgentModelConfigFor ::
  AgentCommandName ->
  AgentConfigInputs ->
  Either
    Text
    ( ResolvedAgentField AgentProvider,
      ResolvedAgentField (Maybe Text),
      ResolvedAgentField (Maybe ThinkingLevel),
      ResolvedAgentField TraceSetting
    )
resolveAgentModelConfigFor c inputs = do
  provider <-
    (\p -> ResolvedAgentField p.value p.source)
      <$> resolveProvider (providerCandidates c inputs)
  let model = applyProviderDefaultModel provider.value (resolveModel (modelCandidates c inputs))
  effort <- resolveEffort (effortCandidates c inputs)
  trace <- resolveTrace (traceCandidates c inputs)
  pure (provider, model, effort, trace)

-- | Resolve the trace file path: local @agent.tracePath@ beats global, and a
-- blank value counts as absent. There is no CLI flag and no per-command
-- variant — 'agentTracePathConfigKey' is free-form, so it stays outside the
-- validated four-value 'TraceSetting' vocabulary.
resolveTracePath :: AgentConfigInputs -> Maybe FilePath
resolveTracePath inputs =
  T.unpack . fst
    <$> firstNonBlankWithSource
      [ candidate (Map.lookup agentTracePathConfigKey inputs.localConfig) SourceLocalDefault,
        candidate (Map.lookup agentTracePathConfigKey inputs.globalConfig) SourceGlobalDefault
      ]

-- | When no model was configured (source is the built-in default), substitute
-- the provider's deterministic default so the two local CLI providers always
-- resolve to a concrete model instead of 'Nothing'. The source stays
-- 'SourceBuiltinDefault' — the value is a built-in, just a non-empty one.
applyProviderDefaultModel :: AgentProvider -> ResolvedAgentField (Maybe Text) -> ResolvedAgentField (Maybe Text)
applyProviderDefaultModel prov field =
  case field.value of
    Just _ -> field
    Nothing -> case defaultModelForProvider prov of
      Just m -> field {value = Just m}
      Nothing -> field

providerCandidates :: AgentCommandName -> AgentConfigInputs -> [(Maybe Text, AgentConfigSource)]
providerCandidates c inputs =
  [ candidate inputs.cliProvider (cliSource inputs.cliProviderFromSubcommand),
    candidate inputs.envProvider SourceEnv,
    candidate inputs.declaredProvider SourceArtifactDeclaration,
    candidate (Map.lookup (agentCommandProviderConfigKey c) inputs.localConfig) SourceLocalCommand,
    candidate (Map.lookup agentProviderConfigKey inputs.localConfig) SourceLocalDefault,
    candidate (Map.lookup (agentCommandProviderConfigKey c) inputs.globalConfig) SourceGlobalCommand,
    candidate (Map.lookup agentProviderConfigKey inputs.globalConfig) SourceGlobalDefault
  ]

modelCandidates :: AgentCommandName -> AgentConfigInputs -> [(Maybe Text, AgentConfigSource)]
modelCandidates c inputs =
  [ candidate inputs.cliModel (cliSource inputs.cliModelFromSubcommand),
    candidate inputs.envModel SourceEnv,
    candidate inputs.declaredModel SourceArtifactDeclaration,
    candidate (Map.lookup (agentCommandModelConfigKey c) inputs.localConfig) SourceLocalCommand,
    candidate (Map.lookup agentModelConfigKey inputs.localConfig) SourceLocalDefault,
    candidate (Map.lookup (agentCommandModelConfigKey c) inputs.globalConfig) SourceGlobalCommand,
    candidate (Map.lookup agentModelConfigKey inputs.globalConfig) SourceGlobalDefault
  ]

effortCandidates :: AgentCommandName -> AgentConfigInputs -> [(Maybe Text, AgentConfigSource)]
effortCandidates c inputs =
  [ candidate inputs.cliEffort (cliSource inputs.cliEffortFromSubcommand),
    candidate inputs.envEffort SourceEnv,
    candidate inputs.declaredEffort SourceArtifactDeclaration,
    candidate (Map.lookup (agentCommandEffortConfigKey c) inputs.localConfig) SourceLocalCommand,
    candidate (Map.lookup agentEffortConfigKey inputs.localConfig) SourceLocalDefault,
    candidate (Map.lookup (agentCommandEffortConfigKey c) inputs.globalConfig) SourceGlobalCommand,
    candidate (Map.lookup agentEffortConfigKey inputs.globalConfig) SourceGlobalDefault
  ]

traceCandidates :: AgentCommandName -> AgentConfigInputs -> [(Maybe Text, AgentConfigSource)]
traceCandidates c inputs =
  [ candidate inputs.cliTrace (cliSource inputs.cliTraceFromSubcommand),
    candidate inputs.envTrace SourceEnv,
    candidate inputs.declaredTrace SourceArtifactDeclaration,
    candidate (Map.lookup (agentCommandTraceConfigKey c) inputs.localConfig) SourceLocalCommand,
    candidate (Map.lookup agentTraceConfigKey inputs.localConfig) SourceLocalDefault,
    candidate (Map.lookup (agentCommandTraceConfigKey c) inputs.globalConfig) SourceGlobalCommand,
    candidate (Map.lookup agentTraceConfigKey inputs.globalConfig) SourceGlobalDefault
  ]

cliSource :: Bool -> AgentConfigSource
cliSource True = SourceCliSubcommand
cliSource False = SourceCliParent

-- | Resolve a provider from an ordered candidate list, parsing the winning text
-- and falling back to the built-in default provider when nothing is set.
resolveProvider :: [(Maybe Text, AgentConfigSource)] -> Either Text (ResolvedAgentField AgentProvider)
resolveProvider candidates =
  case firstNonBlankWithSource candidates of
    Just (txt, src) -> (\p -> ResolvedAgentField p src) <$> providerFromText txt
    Nothing -> Right (ResolvedAgentField defaultAgentModelConfig.provider SourceBuiltinDefault)

-- | Resolve a model from an ordered candidate list. An unset model resolves to
-- 'Nothing' with source 'SourceBuiltinDefault', letting the provider pick.
resolveModel :: [(Maybe Text, AgentConfigSource)] -> ResolvedAgentField (Maybe Text)
resolveModel candidates =
  case firstNonBlankWithSource candidates of
    Just (txt, src) -> ResolvedAgentField (Just txt) src
    Nothing -> ResolvedAgentField Nothing SourceBuiltinDefault

-- | Resolve a reasoning effort from an ordered candidate list. The winning text
-- is parsed with 'effortFromText'; a parse failure returns 'Left'. An unset
-- effort resolves to 'Nothing' with source 'SourceBuiltinDefault', which leaves
-- the provider/CLI default untouched.
resolveEffort :: [(Maybe Text, AgentConfigSource)] -> Either Text (ResolvedAgentField (Maybe ThinkingLevel))
resolveEffort candidates =
  case firstNonBlankWithSource candidates of
    Just (txt, src) -> (\lvl -> ResolvedAgentField (Just lvl) src) <$> effortFromText txt
    Nothing -> Right (ResolvedAgentField Nothing SourceBuiltinDefault)

-- | Resolve a trace destination from an ordered candidate list. Unlike the
-- model and effort resolvers there is no \"unset\" state: an unconfigured trace
-- resolves to 'TraceOff' with source 'SourceBuiltinDefault', which emits
-- nothing.
resolveTrace :: [(Maybe Text, AgentConfigSource)] -> Either Text (ResolvedAgentField TraceSetting)
resolveTrace candidates =
  case firstNonBlankWithSource candidates of
    Just (txt, src) -> (\t -> ResolvedAgentField t src) <$> traceFromText txt
    Nothing -> Right (ResolvedAgentField TraceOff SourceBuiltinDefault)

candidate :: Maybe Text -> AgentConfigSource -> (Maybe Text, AgentConfigSource)
candidate value src = (value, src)

-- | The leftmost candidate whose value is present and non-blank (whitespace is
-- stripped, and @""@ counts as absent), together with its source.
firstNonBlankWithSource :: [(Maybe Text, AgentConfigSource)] -> Maybe (Text, AgentConfigSource)
firstNonBlankWithSource =
  foldr step Nothing
  where
    step (value, src) acc =
      case T.strip <$> value of
        Just "" -> acc
        Just stripped -> Just (stripped, src)
        Nothing -> acc

-- | Read the two environment variables and the local + global config, then run
-- the flat resolver. Preserved for backward compatibility.
loadAgentModelConfig :: Maybe Text -> Maybe Text -> IO (Either Text AgentModelConfig)
loadAgentModelConfig cliProvider cliModel = do
  inputsOrErr <-
    gatherAgentConfigInputs
      noAgentSettingFlags
      noAgentSettingFlags {provider = cliProvider, model = cliModel}
  pure (inputsOrErr >>= resolveAgentModelConfig)

-- | Read the environment and config, then resolve provider/model/effort for a
-- specific command, projecting away the provenance the command handler does not
-- need.
loadAgentModelConfigFor ::
  AgentCommandName ->
  -- | flags on the parent @seihou agent@ command
  AgentSettingFlags ->
  -- | flags on the subcommand itself
  AgentSettingFlags ->
  IO (Either Text AgentModelConfig)
loadAgentModelConfigFor c parentFlags commandFlags = do
  inputsOrErr <- gatherAgentConfigInputs parentFlags commandFlags
  pure $ do
    inputs <- inputsOrErr
    (provider, model, effort, trace) <- resolveAgentModelConfigFor c inputs
    pure
      AgentModelConfig
        { provider = provider.value,
          model = model.value,
          effort = effort.value,
          trace = trace.value,
          tracePath = resolveTracePath inputs
        }

-- | Resolve every configurable command from the real environment and config,
-- with no CLI flags, for the @seihou agent config@ inspection view.
loadResolvedAgentConfig :: IO (Either Text [ResolvedCommandConfig])
loadResolvedAgentConfig = do
  inputsOrErr <- gatherAgentConfigInputs noAgentSettingFlags noAgentSettingFlags
  pure $ do
    inputs <- inputsOrErr
    traverse (resolveOne inputs) allAgentCommands
  where
    resolveOne inputs c = do
      (provider, model, effort, trace) <- resolveAgentModelConfigFor c inputs
      pure
        ResolvedCommandConfig
          { command = c,
            provider = provider,
            model = model,
            effort = effort,
            trace = trace,
            tracePath = resolveTracePath inputs
          }

-- | Shared IO: read @SEIHOU_AGENT_*@ and the local + global config maps into an
-- 'AgentConfigInputs'. Any config read error surfaces as 'Left'.
gatherAgentConfigInputs ::
  -- | flags on the parent @seihou agent@ command
  AgentSettingFlags ->
  -- | flags on the subcommand itself
  AgentSettingFlags ->
  IO (Either Text AgentConfigInputs)
gatherAgentConfigInputs parentFlags commandFlags = do
  envProvider <- fmap T.pack <$> lookupEnv agentProviderEnvVar
  envModel <- fmap T.pack <$> lookupEnv agentModelEnvVar
  envEffort <- fmap T.pack <$> lookupEnv agentEffortEnvVar
  envTrace <- fmap T.pack <$> lookupEnv agentTraceEnvVar
  (localResult, globalResult) <- runEff $ runConfigReader $ do
    local <- readLocalConfig
    global <- readGlobalConfig
    pure (local, global)
  pure $ do
    local <- first formatConfigError localResult
    global <- first formatConfigError globalResult
    pure $
      applyAgentSettingFlags
        parentFlags
        commandFlags
        baseAgentConfigInputs
          { envProvider = envProvider,
            envModel = envModel,
            envEffort = envEffort,
            envTrace = envTrace,
            localConfig = local,
            globalConfig = global
          }

-- | The three launch fields the resolver understands, projected out of an
-- artifact's @launch@ record. @mode@ is deliberately absent: it is reserved
-- and no part of the resolution path.
data AgentLaunchDeclaration = AgentLaunchDeclaration
  { provider :: !(Maybe Text),
    model :: !(Maybe Text),
    effort :: !(Maybe Text)
  }
  deriving stock (Eq, Generic, Show)

-- | A declaration that states nothing, leaving every field to the user's
-- flags, environment, and config.
noAgentLaunchDeclaration :: AgentLaunchDeclaration
noAgentLaunchDeclaration =
  AgentLaunchDeclaration
    { provider = Nothing,
      model = Nothing,
      effort = Nothing
    }

-- | Project a decoded artifact's launch record into the resolver's declaration
-- tier. An artifact with no @launch@ record declares nothing.
agentLaunchDeclaration :: Maybe AgentLaunch -> AgentLaunchDeclaration
agentLaunchDeclaration Nothing = noAgentLaunchDeclaration
agentLaunchDeclaration (Just l) =
  AgentLaunchDeclaration
    { provider = l.provider,
      model = l.model,
      effort = l.effort
    }

-- | Parse-check a declared launch record, returning one message per invalid
-- value. An empty list means the declaration is usable.
--
-- The model is not checked: it is free-form by design, since providers accept
-- aliases and custom model IDs.
validateAgentLaunchDeclaration :: AgentLaunchDeclaration -> [Text]
validateAgentLaunchDeclaration decl =
  check "launch.provider" providerFromText decl.provider
    <> check "launch.effort" effortFromText decl.effort
  where
    check :: Text -> (Text -> Either Text a) -> Maybe Text -> [Text]
    check key parse value =
      [ key <> ": " <> err
      | Just raw <- [value],
        not (T.null (T.strip raw)),
        Left err <- [parse (T.strip raw)]
      ]

-- | Everything needed to finish resolution later: the command identity plus
-- the flags, environment, and config already gathered. A handler holds one of
-- these while it discovers and decodes its artifact, then finishes with
-- 'resolvePendingAgentConfig'.
--
-- This two-phase shape exists because the artifact's declaration is only known
-- after the handler loads it, but resolution must still be a single pass over
-- one ordered precedence list.
data PendingAgentConfig = PendingAgentConfig
  { command :: !AgentCommandName,
    inputs :: !AgentConfigInputs
  }
  deriving stock (Eq, Generic, Show)

-- | Read the environment and config for a command whose artifact may declare
-- its own launch settings, stopping short of resolution.
loadPendingAgentConfig ::
  AgentCommandName ->
  -- | flags on the parent @seihou agent@ command
  AgentSettingFlags ->
  -- | flags on the subcommand itself
  AgentSettingFlags ->
  IO (Either Text PendingAgentConfig)
loadPendingAgentConfig c parentFlags commandFlags = do
  inputsOrErr <- gatherAgentConfigInputs parentFlags commandFlags
  pure (PendingAgentConfig c <$> inputsOrErr)

-- | Finish resolution by folding the artifact's declaration into the gathered
-- inputs and running the ordinary precedence chain.
resolvePendingAgentConfig ::
  PendingAgentConfig ->
  AgentLaunchDeclaration ->
  Either Text ResolvedCommandConfig
resolvePendingAgentConfig pending decl = do
  let inputs =
        pending.inputs
          { declaredProvider = decl.provider,
            declaredModel = decl.model,
            declaredEffort = decl.effort
          }
  (provider, model, effort, trace) <- resolveAgentModelConfigFor pending.command inputs
  pure
    ResolvedCommandConfig
      { command = pending.command,
        provider = provider,
        model = model,
        effort = effort,
        trace = trace,
        tracePath = resolveTracePath inputs
      }

-- | Project a resolved command config down to what the launch layer needs,
-- discarding provenance.
resolvedAgentModelConfig :: ResolvedCommandConfig -> AgentModelConfig
resolvedAgentModelConfig rcc =
  AgentModelConfig
    { provider = rcc.provider.value,
      model = rcc.model.value,
      effort = rcc.effort.value,
      trace = rcc.trace.value,
      tracePath = rcc.tracePath
    }

-- | A one-line provenance summary for a verbose log line, e.g.
--
-- > provider claude-cli [built-in default], model claude-sonnet-5 [blueprint: launch.model], effort max [blueprint: launch.effort]
formatResolvedAgentProvenance :: ResolvedCommandConfig -> Text
formatResolvedAgentProvenance rcc =
  T.intercalate
    ", "
    [ part "provider" (providerToText rcc.provider.value) ProviderField rcc.provider.source,
      part "model" (fromMaybe "<provider default>" rcc.model.value) ModelField rcc.model.source,
      part "effort" (maybe "<unset>" effortToText rcc.effort.value) EffortField rcc.effort.source,
      part "trace" (traceToText rcc.trace.value) TraceField rcc.trace.source
    ]
  where
    part label value field src =
      label <> " " <> value <> " [" <> agentConfigSourceLabel rcc.command field src <> "]"

-- | Finish resolution with the artifact's declaration, logging the resolved
-- provenance at verbose level and exiting with an actionable message when the
-- artifact declares an unusable value.
--
-- The label names the artifact in the error message, e.g.
-- @"blueprint 'payments-service'"@.
resolveDeclaredAgentConfig ::
  LogLevel ->
  Text ->
  PendingAgentConfig ->
  AgentLaunchDeclaration ->
  IO AgentModelConfig
resolveDeclaredAgentConfig level label pending decl =
  case resolvePendingAgentConfig pending decl of
    Left err -> do
      logIO level (logError $ "Invalid agent settings for " <> label <> ": " <> err)
      exitFailure
    Right resolved -> do
      logIO level (logInfo $ "Agent: " <> formatResolvedAgentProvenance resolved)
      pure (resolvedAgentModelConfig resolved)
