---
id: 70
slug: support-per-command-hierarchical-agent-model-and-provider-configuration
title: "Support per-command hierarchical agent model and provider configuration"
kind: exec-plan
created_at: 2026-07-20T13:26:38Z
intention: "intention_01kxzv9xdyeyctpadtzw239k3x"
master_plan: "docs/masterplans/4-baikai-backed-configurable-agent-assistance.md"
---

# Support per-command hierarchical agent model and provider configuration

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

Seihou ships a family of AI-assisted commands under `seihou agent` — `assist`,
`bootstrap`, `setup`, and `run` — plus `seihou prompt run`. Each of these renders a
Seihou-aware prompt and hands it to an AI **provider** (an integration that talks to a
model, either by launching a local CLI tool such as Claude Code or Codex, or by calling
an HTTP API such as Anthropic's or OpenAI's) with a chosen **model** (a specific named
LLM, e.g. `gpt-5` or `claude-opus-4-8`).

Today every agent command shares one provider and one model. A user can set
`agent.provider` and `agent.model` in a Seihou config file, but that single pair applies
uniformly to all commands. There is no way to say "use a fast cheap model for `assist`
but a strong model for `run`" through configuration — only through per-invocation
command-line flags that vanish when the command exits. There is also no single place to
*see* what provider and model each command will actually use, or *why*.

After this change, a user can:

1. Set a different provider and model **per agent command** in configuration, for
   example `agent.assist.model = gpt-5-mini` and `agent.run.model = claude-opus-4-8`,
   while `agent.model` and `agent.provider` remain the shared default for any command
   that has no specific override.

2. Rely on **hierarchical** resolution where a project's local config
   (`.seihou/config.dhall`) overrides the user's global config
   (`~/.config/seihou/config.dhall`), and within a scope a per-command key overrides the
   shared default key.

3. Run a new command, `seihou agent config`, that prints a clear table of the resolved
   provider and model for **every** agent command and labels the **source** of each value
   (which config scope and key, an environment variable, or the built-in default), so the
   effective configuration is auditable at a glance.

The visible outcome, verifiable end-to-end, is this session:

```text
$ seihou config set agent.model claude-sonnet-5 --global
$ seihou config set agent.assist.provider codex-cli --global
$ seihou config set agent.assist.model gpt-5-mini --global
$ cd my-project
$ seihou config set agent.run.model claude-opus-4-8    # local (project) scope
$ seihou agent config

Resolved agent provider and model per command
(highest-precedence source wins; see precedence list below)

  assist       provider codex-cli   [global: agent.assist.provider]
               model    gpt-5-mini  [global: agent.assist.model]
  bootstrap    provider claude-cli  [built-in default]
               model    claude-sonnet-5  [global: agent.model]
  setup        provider claude-cli  [built-in default]
               model    claude-sonnet-5  [global: agent.model]
  run          provider claude-cli  [built-in default]
               model    claude-opus-4-8  [local: agent.run.model]
  prompt-run   provider claude-cli  [built-in default]
               model    claude-sonnet-5  [global: agent.model]

Precedence, highest first:
  1. --provider / --model flag on the subcommand
  2. --provider / --model flag on `seihou agent`
  3. SEIHOU_AGENT_PROVIDER / SEIHOU_AGENT_MODEL environment variables
  4. local  .seihou/config.dhall        agent.<command>.{provider,model}
  5. local  .seihou/config.dhall        agent.{provider,model}
  6. global ~/.config/seihou/config.dhall agent.<command>.{provider,model}
  7. global ~/.config/seihou/config.dhall agent.{provider,model}
  8. built-in default: provider claude-cli, model unset
```

Existing users who set only `agent.provider`/`agent.model`, or who pass only CLI flags,
see no behavior change: those paths continue to resolve exactly as before. This plan is
purely additive.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Milestone 1: Introduce the per-command, provenance-aware resolver in the library
  (`seihou-cli/src/Seihou/CLI/AgentConfig.hs`): `AgentCommandName`, per-command config
  keys, `ResolvedAgentField`/`AgentConfigSource`, `resolveAgentModelConfigFor`, and a
  backward-compatible reimplementation of `resolveAgentModelConfig`. Pure unit tests in
  `seihou-cli/test/Seihou/CLI/AgentConfigSpec.hs`. Completed 2026-07-20; all 13
  `AgentConfig` cases pass (7 pre-existing + 6 new).
- [x] Milestone 2: Thread the command name into resolution so each handler picks up its
  per-command keys. Add `loadAgentModelConfigFor` to the library; update the dispatch in
  `seihou-cli/src-exe/Main.hs`. Completed 2026-07-20; verified with a scratch `HOME` that
  `seihou agent assist` reads `agent.assist.provider` (errors on an invalid value) while
  `seihou agent setup` falls through to the default and renders normally.
- [x] Milestone 3: Add the `seihou agent config` inspection command. Library-side
  `loadResolvedAgentConfig` + `formatResolvedAgentConfig` and handler
  `handleAgentConfigShow` in the new library module
  `seihou-cli/src/Seihou/CLI/AgentConfigShow.hs`; `AgentConfigShow` constructor + parser
  (`command "config"`) in `seihou-cli/src-exe/Seihou/CLI/Commands.hs`; dispatch in
  `Main.hs`. Five format unit cases in `seihou-cli/test/Seihou/CLI/AgentConfigShowSpec.hs`.
  Completed 2026-07-20; the live `seihou agent config` output matches the Purpose
  transcript exactly (all 18 AgentConfig* tests pass).
- [x] Milestone 4: Documentation and full validation. Updated
  `docs/user/agent-assistance.md` (per-command config + inspection subsections, 8-tier
  precedence), `docs/user/config-and-variables.md` (per-command keys + project-over-global
  example), `docs/cli/agent.md` (`agent config` subcommand), and `docs/user/CHANGELOG.md`.
  Full suite green: 315 CLI + 1007 core + 16 extension tests pass. Completed 2026-07-20.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- Milestone 3: The handler `handleAgentConfigShow` imports no executable-only dependency,
  so per the placement convention it lives in the library
  (`seihou-cli/src/Seihou/CLI/AgentConfigShow.hs`), not `src-exe/` as the plan's prose
  first sketched; only the `AgentCommand` constructor and its `command "config"` parser sit
  in the executable. The rendered table prints the command label on the provider row only
  and blanks the label column on the model row (matching the Purpose transcript), so the
  format tests assert model rows by their unique value + source rather than by command name.
- Milestone 1: Rather than the `agentConfigSourceLabel :: AgentConfigSource -> Text -> Text`
  signature sketched in the plan, the implemented label function is
  `agentConfigSourceLabel :: AgentCommandName -> AgentField -> AgentConfigSource -> Text`
  with a new `AgentField = ProviderField | ModelField` type. This lets the function compute
  the exact winning key itself (e.g. `local: agent.run.model`) instead of relying on the
  caller to pass the right key string, which removes a class of caller mistakes. Also added
  a `baseAgentConfigInputs` smart constructor so the two new `cli*FromSubcommand` fields did
  not force every `AgentConfigInputs` literal in tests to be rewritten.


## Decision Log

Record every decision made while working on the plan.

- Decision: Precedence orders **scope over specificity across scopes**, and
  **specificity over default within a scope**. Concretely, from highest to lowest among
  config values: local per-command key, then local default key, then global per-command
  key, then global default key.
  Rationale: The user's explicit requirement is that "projects can override global ones."
  Making any local value beat any global value honors that directly. Within a single
  scope, the more specific per-command key is the more intentional statement, so it wins
  over the shared default in that same file. This is the least surprising reading of
  "hierarchical, project overrides global."
  Date: 2026-07-20

- Decision: Keep the existing overall precedence chain intact and insert the two new
  per-command config tiers between the environment variables and the existing default
  config keys. Full chain: subcommand flag > parent `agent` flag > env var > local
  per-command key > local default key > global per-command key > global default key >
  built-in default.
  Rationale: This is strictly additive. Every currently-passing `AgentConfigSpec` case
  keeps its result because per-command keys are absent in those inputs, so they collapse
  to the old chain. No existing user configuration changes meaning.
  Date: 2026-07-20

- Decision: Config keys use the shape `agent.<command>.provider` and
  `agent.<command>.model`, where `<command>` is one of `assist`, `bootstrap`, `setup`,
  `run`, `prompt-run`.
  Rationale: The flat dotted-key convention already exists (`agent.provider`) and is
  writable through `seihou config set`. Nesting the command segment between `agent` and
  the field keeps keys self-describing and collision-free. `prompt-run` uses a hyphen so
  the two-word `seihou prompt run` command maps to a single key segment.
  Date: 2026-07-20

- Decision: Environment variables (`SEIHOU_AGENT_PROVIDER`/`SEIHOU_AGENT_MODEL`) stay
  cross-command; there is no per-command environment variable.
  Rationale: The existing environment variables are already a coarse global override, and
  adding ten per-command variables would bloat the surface with little benefit. Users who
  want per-command control use config keys.
  Date: 2026-07-20

- Decision: Expose the inspection surface as `seihou agent config` (a subcommand of
  `agent`) rather than folding it into the existing top-level `seihou config`.
  Rationale: The top-level `seihou config` command is a generic key/value editor with
  `set`/`get`/`unset`/`list` actions over raw scopes; it has no concept of agent
  resolution or provenance. `seihou agent config` is a read-only, agent-specific
  *resolution* view, discoverable alongside the commands it describes. It does not accept
  `set`; users still write values with `seihou config set`.
  Date: 2026-07-20

- Decision: Put the pure resolution and formatting logic in the library
  (`seihou-cli/src/Seihou/CLI/AgentConfig.hs`) and keep only the parser wiring and a thin
  IO handler in the executable target (`seihou-cli/src-exe/`).
  Rationale: The repository enforces a library-first convention (see project `CLAUDE.md`
  and `docs/dev/architecture/overview.md`, "CLI Module Placement Convention"). Pure logic
  in the library is unit-testable by `seihou-cli-test`; only modules that must import
  `Options.Applicative` (the parser) or `Seihou.CLI.Commands` belong in `src-exe/`.
  Date: 2026-07-20


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

The plan delivered exactly the three user-visible capabilities from Purpose. Agent
commands now read per-command config keys `agent.<command>.{provider,model}` for `assist`,
`bootstrap`, `setup`, `run`, and `prompt-run`, falling back to the shared
`agent.{provider,model}` defaults. Resolution is hierarchical and additive: the eight-tier
precedence chain inserts local then global per-command tiers around the pre-existing default
tiers, so any project-local value overrides any global value, and within a scope the
per-command key beats the shared default. The new read-only `seihou agent config` command
prints the resolved provider and model for every command with the winning source labelled;
its live output matches the Purpose transcript, including `run` resolving to a local
`agent.run.model` while other commands fall back to a global `agent.model`.

Backward compatibility held: the flat `resolveAgentModelConfig`/`loadAgentModelConfig`
retain their exact behavior, every pre-existing `AgentConfig` test passes unchanged, and a
user who set only `agent.provider`/`agent.model` sees no difference.

Validation: 18 `AgentConfig`/`AgentConfigShow` unit cases pass; a scratch-`HOME`
behavioral check confirmed `agent assist` reads `agent.assist.provider` while `agent setup`
does not; and the full suite (315 CLI + 1007 core + 16 extension) is green.

Lessons: (1) `NoFieldSelectors` is enabled repo-wide, so record fields cannot be used as
bare functions — use `\r -> r.field` in point-free positions. (2) The `UpdateE2ESpec` and
completion E2E tests spawn the built `seihou` binary via `build-tool-depends`, which is not
staged under a bare `cabal test all` outside the nix sandbox; they fail with
`posix_spawnp: does not exist` for reasons unrelated to source changes and pass once the
binary is staged (or under `nix flake check`). This is expected given the preceding
`fix(nix): provide test tools in build sandbox` commit.

Gaps / future work: environment variables remain cross-command by design; if a concrete
need arises, per-command environment variables (e.g. `SEIHOU_AGENT_RUN_MODEL`) could be
added as a new tier. Namespace/context scopes are still out of scope for agent resolution.


## Context and Orientation

This section assumes no prior knowledge of the repository. Read it fully before editing.

Seihou is a Haskell project scaffolding tool. It is a multi-package Cabal workspace built
with Nix. The two packages relevant here are:

- `seihou-core` — the pure/effectful core library at `seihou-core/src/`.
- `seihou-cli` — the command-line tool. It is split into an **internal library** at
  `seihou-cli/src/` (Haskell modules under the `Seihou.CLI.*` namespace) and an
  **executable target** at `seihou-cli/src-exe/` (`Main.hs`, the option parser, and
  command handlers). The build definition is `seihou-cli/seihou-cli.cabal`.

There is a firm convention, described in the project's root `CLAUDE.md` and in
`docs/dev/architecture/overview.md` under "CLI Module Placement Convention": new code goes
in the internal library (`seihou-cli/src/`) by default. A module belongs in the executable
target (`seihou-cli/src-exe/`) only if it must import one of `Options.Applicative`,
`Data.FileEmbed`, `GitHash`, or `Paths_seihou_cli`, or if it imports another
executable-only module (most commonly `Seihou.CLI.Commands`, which is trapped because it
uses `Options.Applicative`). A script, `nix/check-cli-module-placement.sh`, mechanically
enforces this and runs in both `nix flake check` and the pre-commit hook. Practically:
put pure resolution and formatting in `seihou-cli/src/`; put the option parser and the
handler that references parser option records in `seihou-cli/src-exe/`.

### Configuration model

Seihou configuration lives in flat Dhall records — files whose content is a record mapping
text keys to text values. There are several **scopes** (locations a config file can live):

- **local** — `.seihou/config.dhall` in the current project directory.
- **namespace** — a named group (rarely used for agent settings; ignore for this plan).
- **context** — another named group (also ignore for this plan).
- **global** — `~/.config/seihou/config.dhall` in the user's home.

The effect that reads these is `seihou-core/src/Seihou/Effect/ConfigReader.hs`. It exposes
`readLocalConfig`, `readGlobalConfig`, `readNamespaceConfig`, and `readContextConfig`, each
returning `Either ConfigError (Map Text Text)`. The IO interpreter is
`seihou-core/src/Seihou/Effect/ConfigReaderInterp.hs` (`runConfigReader`). Writing config
is done through `Seihou.Effect.ConfigWriter` and the `seihou config` command implemented in
`seihou-cli/src-exe/Seihou/CLI/Config.hs`. That command already supports
`seihou config set/get/unset/list` and `seihou config list --effective` (which merges
scopes and tags each value with its winning scope). No changes to the writer or the generic
`seihou config` command are required by this plan; users set the new keys with the existing
`seihou config set agent.assist.model gpt-5-mini`.

### Agent provider/model resolution as it exists today

The relevant library modules are:

- `seihou-cli/src/Seihou/CLI/AgentCompletion.hs` defines the domain types:

  ```haskell
  data AgentProvider
    = AgentProviderClaudeCli
    | AgentProviderCodexCli
    | AgentProviderAnthropic
    | AgentProviderOpenAI

  data AgentModelConfig = AgentModelConfig
    { agentProvider :: AgentProvider
    , agentModel :: Maybe Text   -- Nothing = let the provider pick its default
    }

  defaultAgentModelConfig :: AgentModelConfig   -- claude-cli, model unset
  providerFromText :: Text -> Either Text AgentProvider   -- parses "codex-cli" etc.
  providerToText   :: AgentProvider -> Text
  ```

- `seihou-cli/src/Seihou/CLI/AgentConfig.hs` currently defines the flat resolver:

  ```haskell
  data AgentConfigInputs = AgentConfigInputs
    { cliProvider :: Maybe Text
    , cliModel :: Maybe Text
    , envProvider :: Maybe Text
    , envModel :: Maybe Text
    , localConfig :: Map Text Text
    , globalConfig :: Map Text Text
    }

  agentProviderConfigKey :: Text  -- "agent.provider"
  agentModelConfigKey :: Text     -- "agent.model"
  agentProviderEnvVar :: String   -- "SEIHOU_AGENT_PROVIDER"
  agentModelEnvVar :: String      -- "SEIHOU_AGENT_MODEL"

  resolveAgentModelConfig :: AgentConfigInputs -> Either Text AgentModelConfig
  loadAgentModelConfig :: Maybe Text -> Maybe Text -> IO (Either Text AgentModelConfig)
  ```

  `resolveAgentModelConfig` picks, for the provider, the first non-blank of
  `[cliProvider, envProvider, local "agent.provider", global "agent.provider"]`, defaulting
  to `claude-cli`; and similarly for the model with `"agent.model"`. "Non-blank" means it
  strips whitespace and treats `""` as absent (helper `firstNonBlank`). `loadAgentModelConfig`
  reads the two environment variables and the local + global config maps, then calls the
  pure resolver.

- The command-line parser is `seihou-cli/src-exe/Seihou/CLI/Commands.hs`. The parent
  `agent` command carries `agentProvider :: Maybe Text` and `agentModel :: Maybe Text`
  (from `--provider`/`--model`), and every subcommand's option record *also* carries its
  own `--provider`/`--model` (e.g. `assistProvider`, `assistModel`, `setupProvider`, …),
  parsed by the shared helpers `providerOption` and `modelOption`. The `AgentCommand`
  sum type currently has constructors `AgentAssist`, `AgentBootstrap`, `AgentSetup`,
  `AgentRun`, `AgentModels`.

- Dispatch is in `seihou-cli/src-exe/Main.hs`. Its private helper resolves the config by
  combining the subcommand flag with the parent flag (subcommand wins) and hands the
  result to the handler:

  ```haskell
  resolveAgentModelConfig :: Maybe Text -> Maybe Text -> Maybe Text -> Maybe Text
                          -> IO AgentCompletion.AgentModelConfig
  resolveAgentModelConfig parentProvider parentModel commandProvider commandModel = do
    configResult <- loadAgentModelConfig (commandProvider <|> parentProvider)
                                         (commandModel   <|> parentModel)
    case configResult of
      Left err -> TIO.putStrLn ("Error: " <> err) >> exitFailure
      Right config -> pure config
  ```

  Each agent subcommand calls this and passes the resolved `AgentModelConfig` to its
  handler (`handleAssist`, `handleBootstrap`, `handleSetup`, `handleAgentRun`,
  `handlePromptRun`). The handler ultimately calls `buildBaikaiModel` (in
  `AgentCompletion.hs`) or `launchConfiguredAgent*` (in
  `seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs`).

The single fact to internalize: **the command name is currently discarded before config is
read**, so config cannot vary by command. This plan makes the command name a resolution
input.

### The behavior gap this plan closes

1. There is no per-command config key. `agent.model` is the only model key.
2. There is no way to view the resolved provider/model for each command with its source.
3. Hierarchy across scopes (local over global) exists for the flat keys but has never been
   extended to per-command keys, because those keys do not exist yet.

### Existing tests to follow as patterns

`seihou-cli/test/Seihou/CLI/AgentConfigSpec.hs` unit-tests `resolveAgentModelConfig` with a
`baseInputs` record and small helpers. `seihou-cli/test/Seihou/CLI/AgentModelsSpec.hs` tests
formatting output. Both are registered in `seihou-cli/seihou-cli.cabal` (under the
`seihou-cli-test` test suite's `other-modules`) and aggregated in
`seihou-cli/test/Main.hs`. New library test modules follow the same two registration steps.


## Plan of Work

The work is four milestones. Milestones 1 and 3 add pure, unit-tested library logic and are
verifiable in isolation. Milestone 2 wires the new resolver into real command dispatch.
Milestone 4 documents and validates the whole feature end-to-end.

### Milestone 1 — Per-command, provenance-aware resolver in the library

Scope: extend `seihou-cli/src/Seihou/CLI/AgentConfig.hs` so resolution is parameterized by
a command name and reports where each resolved value came from. At the end of this
milestone the library compiles, exposes the new API, and a focused unit-test suite proves
the precedence chain, including the new per-command tiers and the project-over-global rule.
Nothing about command dispatch changes yet, so the CLI behaves exactly as before.

Add the following to `AgentConfig.hs`:

1. A command-name enumeration and its config-key segment:

   ```haskell
   data AgentCommandName
     = AgentCmdAssist
     | AgentCmdBootstrap
     | AgentCmdSetup
     | AgentCmdRun
     | AgentCmdPromptRun
     deriving stock (Eq, Show, Enum, Bounded)

   -- | The token used inside config keys, e.g. "assist" in "agent.assist.model".
   agentCommandSegment :: AgentCommandName -> Text
   agentCommandSegment AgentCmdAssist    = "assist"
   agentCommandSegment AgentCmdBootstrap = "bootstrap"
   agentCommandSegment AgentCmdSetup     = "setup"
   agentCommandSegment AgentCmdRun       = "run"
   agentCommandSegment AgentCmdPromptRun = "prompt-run"

   -- | Human label for display, e.g. "prompt run".
   agentCommandLabel :: AgentCommandName -> Text
   agentCommandLabel AgentCmdPromptRun = "prompt run"
   agentCommandLabel c = agentCommandSegment c

   allAgentCommands :: [AgentCommandName]
   allAgentCommands = [minBound .. maxBound]
   ```

2. Per-command config-key builders:

   ```haskell
   agentCommandProviderConfigKey :: AgentCommandName -> Text
   agentCommandProviderConfigKey c = "agent." <> agentCommandSegment c <> ".provider"

   agentCommandModelConfigKey :: AgentCommandName -> Text
   agentCommandModelConfigKey c = "agent." <> agentCommandSegment c <> ".model"
   ```

3. A provenance model describing where a resolved value originated:

   ```haskell
   data AgentConfigSource
     = SourceCliSubcommand      -- --provider/--model on the subcommand
     | SourceCliParent          -- --provider/--model on `seihou agent`
     | SourceEnv                -- SEIHOU_AGENT_* environment variable
     | SourceLocalCommand       -- local  agent.<cmd>.<field>
     | SourceLocalDefault       -- local  agent.<field>
     | SourceGlobalCommand      -- global agent.<cmd>.<field>
     | SourceGlobalDefault      -- global agent.<field>
     | SourceBuiltinDefault     -- hard-coded fallback
     deriving stock (Eq, Show)

   data ResolvedAgentField a = ResolvedAgentField
     { resolvedValue  :: a
     , resolvedSource :: AgentConfigSource
     }
     deriving stock (Eq, Show)
   ```

4. A per-command resolver that keeps the existing `AgentConfigInputs` fields but takes the
   command name and returns the resolved provider and model **with** their sources. The CLI
   fields (`cliProvider`/`cliModel`) already represent the winning CLI flag (subcommand
   `<|>` parent) as computed by `Main.hs` today. To label CLI-sourced values precisely
   (subcommand vs. parent), add two optional fields carrying the *pre-combined* flags; when
   absent, resolution falls back to labelling any CLI value as `SourceCliSubcommand`. Keep
   this backward compatible by giving the new fields defaults via a smart constructor rather
   than breaking existing `AgentConfigInputs` literals in tests.

   Concretely, extend `AgentConfigInputs` with:

   ```haskell
   data AgentConfigInputs = AgentConfigInputs
     { cliProvider :: Maybe Text        -- combined winning provider flag (unchanged)
     , cliModel :: Maybe Text           -- combined winning model flag (unchanged)
     , cliProviderFromSubcommand :: Bool  -- NEW: True if the combined provider came from the subcommand flag
     , cliModelFromSubcommand :: Bool     -- NEW
     , envProvider :: Maybe Text
     , envModel :: Maybe Text
     , localConfig :: Map Text Text
     , globalConfig :: Map Text Text
     }
   ```

   Because existing `AgentConfigSpec` literals construct `AgentConfigInputs` with all
   fields, adding fields to the record would force edits to those literals. To avoid
   touching every literal and to keep old callers working, introduce a smart default and
   have the test's `baseInputs` include the two new `False` fields. (The spec is updated in
   this same milestone, so this is fine; document the two new fields there.)

   The resolver:

   ```haskell
   resolveAgentModelConfigFor
     :: AgentCommandName
     -> AgentConfigInputs
     -> Either Text (ResolvedAgentField AgentProvider, ResolvedAgentField (Maybe Text))
   ```

   Implementation walks an ordered candidate list for each field. Each candidate is a
   `(Maybe Text, AgentConfigSource)` pair; the first non-blank text wins. For the provider
   of command `c`:

   ```text
   (cliProvider,                        SourceCliSubcommand or SourceCliParent)
   (envProvider,                        SourceEnv)
   (local  agent.<c>.provider,          SourceLocalCommand)
   (local  agent.provider,              SourceLocalDefault)
   (global agent.<c>.provider,          SourceGlobalCommand)
   (global agent.provider,              SourceGlobalDefault)
   (Just "claude-cli" via default,      SourceBuiltinDefault)
   ```

   The first CLI entry's source is `SourceCliSubcommand` when
   `cliProviderFromSubcommand` is `True`, else `SourceCliParent`. Reuse the existing
   `firstNonBlank`/blank-stripping semantics so `"  "` counts as absent. The chosen
   provider text is parsed with `providerFromText`; a parse failure returns `Left err`
   exactly as today. The model resolution is identical but there is no built-in text
   default — if nothing matches, the resolved model is `Nothing` with source
   `SourceBuiltinDefault`.

5. Rewrite `resolveAgentModelConfig` (the existing flat function) as a thin adapter so no
   caller outside this module breaks:

   ```haskell
   resolveAgentModelConfig :: AgentConfigInputs -> Either Text AgentModelConfig
   resolveAgentModelConfig inputs =
     -- Resolve as if for a command with no per-command keys present, so behavior
     -- is identical to the historical flat resolver.
     buildFlat <$> resolveAgentModelConfigFor sentinelNoCommand inputs
   ```

   The cleanest way to preserve exact old behavior is to resolve against a command whose
   per-command keys are guaranteed absent. Rather than inventing a sentinel command, note
   that per-command keys only participate when present in the maps; for the flat function
   we simply *skip* the per-command tiers. Implement `resolveAgentModelConfig` by calling a
   shared internal helper `resolveWith :: [Candidate] -> ...` with the flat candidate list
   (CLI, env, local default, global default, built-in) — i.e. reuse the same core walker,
   omitting the per-command tiers. This guarantees the existing tests pass unchanged in
   result while sharing one implementation. Prefer this over the sentinel approach; the
   sentinel text above is illustrative only.

6. Add a human-readable label for sources, for later display and for tests:

   ```haskell
   agentConfigSourceLabel :: AgentCommandName -> AgentConfigSource -> Text
   -- e.g. SourceLocalCommand -> "local: agent.assist.provider"
   --      SourceGlobalDefault -> "global: agent.model"
   --      SourceBuiltinDefault -> "built-in default"
   ```

   Because the label distinguishes provider vs. model keys, either pass the field name or
   provide two label functions (`...ProviderSourceLabel`, `...ModelSourceLabel`). Choose
   whichever keeps call sites clear; a single function taking the concrete key text is
   simplest:

   ```haskell
   agentConfigSourceLabel :: AgentConfigSource -> Text -> Text
   -- second argument is the concrete config key for the command/field, e.g.
   -- "agent.assist.provider", used only for the local/global command/default cases.
   ```

Export every new name from the module's export list.

Tests (in `seihou-cli/test/Seihou/CLI/AgentConfigSpec.hs`): keep all existing cases (they
must still pass, proving backward compatibility) and add:

- A per-command model key beats the default key in the same scope:
  local `{agent.model=A, agent.run.model=B}` resolves command `run` to model `B` with
  source `SourceLocalCommand`, and command `assist` to `A` with source `SourceLocalDefault`.
- Project overrides global across specificity: local `agent.model=A` beats global
  `agent.run.model=B` for command `run` (local default wins over global command), resolved
  value `A`, source `SourceLocalDefault`. This is the crucial "projects override global"
  case and follows directly from the Decision Log.
- Global per-command beats global default: global `{agent.provider=anthropic,
  agent.assist.provider=openai}` resolves `assist` provider to `openai`
  (`SourceGlobalCommand`) and `setup` provider to `anthropic` (`SourceGlobalDefault`).
- CLI subcommand flag still beats everything and is labelled `SourceCliSubcommand` when
  `cliProviderFromSubcommand = True`, `SourceCliParent` otherwise.
- Built-in default when nothing is set: provider `claude-cli` with `SourceBuiltinDefault`,
  model `Nothing` with `SourceBuiltinDefault`.

Acceptance: `cabal test seihou-cli-test --test-options '--pattern AgentConfig'` passes and
prints the new case names.

### Milestone 2 — Thread the command name through dispatch

Scope: make each real agent command resolve against its own per-command keys. At the end,
`seihou agent run` and `seihou agent assist` (etc.) read `agent.run.*` and `agent.assist.*`
respectively, still honoring flags, env, and defaults. Verifiable by setting a config key
and observing `--debug` or actual model selection differ per command.

Add an IO loader to the library alongside `loadAgentModelConfig`:

```haskell
loadAgentModelConfigFor
  :: AgentCommandName
  -> Maybe Text        -- winning provider flag (subcommand <|> parent), unchanged shape
  -> Maybe Text        -- winning model flag
  -> Bool              -- provider flag came from the subcommand?
  -> Bool              -- model flag came from the subcommand?
  -> IO (Either Text AgentModelConfig)
```

It mirrors the existing `loadAgentModelConfig`: read `SEIHOU_AGENT_*`, read local+global
config via `runConfigReader`, then call `resolveAgentModelConfigFor` and project the
`ResolvedAgentField`s down to a plain `AgentModelConfig` (dropping the sources, which only
the inspection command needs). Keep the old `loadAgentModelConfig` as a thin wrapper that
calls the flat resolver for exact backward compatibility, or reimplement it in terms of the
new function with the flat behavior — but only if that preserves results identically; when
in doubt, leave `loadAgentModelConfig` untouched.

Update `seihou-cli/src-exe/Main.hs`:

- Change the private `resolveAgentModelConfig` helper (the one in `Main.hs`, not the
  library one) to take an `AgentCommandName` and the raw subcommand/parent flags separately
  so it can report which flag won. Signature becomes:

  ```haskell
  resolveAgentModelConfigFor
    :: AgentCommandName
    -> Maybe Text -> Maybe Text   -- parent provider, parent model
    -> Maybe Text -> Maybe Text   -- subcommand provider, subcommand model
    -> IO AgentCompletion.AgentModelConfig
  ```

  Internally compute `provider = subProvider <|> parentProvider`, `providerFromSub =
  isJust subProvider`, likewise for model, then call the library
  `loadAgentModelConfigFor`. On `Left`, print `Error:` and `exitFailure` exactly as today.

- At each dispatch arm pass the matching command name:
  `AgentAssist` → `AgentCmdAssist`, `AgentBootstrap` → `AgentCmdBootstrap`, `AgentSetup` →
  `AgentCmdSetup`, `AgentRun` → `AgentCmdRun`. For the top-level `seihou prompt run` arm,
  pass `AgentCmdPromptRun` (its parent provider/model are `Nothing`, unchanged).

- `AgentModels` needs no model config and is unchanged.

Acceptance: with `seihou config set agent.run.model X --global` and a different
`agent.assist.model Y`, running `seihou agent --debug run ...` versus `seihou agent --debug
assist ...` shows the respective models are picked up (visible in Milestone 3's inspection
command; for this milestone, verify via a targeted test of `loadAgentModelConfigFor` using
a temporary `HOME`/cwd, or via `seihou agent config` once Milestone 3 lands — note the
dependency and, if implementing strictly in order, defer the end-to-end check to M3).

### Milestone 3 — `seihou agent config` inspection command

Scope: add a read-only command that prints the resolved provider and model for every agent
command, each labelled with its source, plus the precedence legend. At the end, a user can
run `seihou agent config` and audit the effective configuration exactly as shown in
Purpose.

Library additions in `AgentConfig.hs`:

```haskell
data ResolvedCommandConfig = ResolvedCommandConfig
  { rccCommand  :: AgentCommandName
  , rccProvider :: ResolvedAgentField AgentProvider
  , rccModel    :: ResolvedAgentField (Maybe Text)
  }

-- Resolve every command from real local+global config and env, with no CLI flags
-- (the inspection command is not tied to a running subcommand).
loadResolvedAgentConfig :: IO (Either Text [ResolvedCommandConfig])

-- Pure formatter, unit-testable: given the resolutions, produce the display block.
formatResolvedAgentConfig :: [ResolvedCommandConfig] -> Text
```

`loadResolvedAgentConfig` reads env + local + global once, then folds
`resolveAgentModelConfigFor` over `allAgentCommands` with empty CLI flags. Any config read
error surfaces as `Left`. `formatResolvedAgentConfig` renders the table (command label,
provider value + source label, model value or `(default)` + source label) followed by the
fixed precedence legend from Purpose. Provider values use `providerToText`; an unset model
prints `(default)`.

Executable additions:

- In `seihou-cli/src-exe/Seihou/CLI/Commands.hs`: add constructor `AgentConfigShow` to
  `AgentCommand` (no options needed, or a unit-option record for symmetry). Add a
  `command "config" agentConfigInfo` entry to the `agent` subcommand group with a
  `progDesc` like `"Show the resolved provider and model for each agent command"`. Provide
  `agentConfigInfo :: ParserInfo AgentCommand` and a parser `pure AgentConfigShow`.
- Create `seihou-cli/src-exe/Seihou/CLI/AgentConfigShow.hs` with
  `handleAgentConfigShow :: IO ()` that calls `loadResolvedAgentConfig`, and on `Right`
  prints `formatResolvedAgentConfig`, on `Left` prints `Error: <err>` and `exitFailure`.
  This module imports library functions only; it does **not** need `Options.Applicative`.
  However, to keep dispatch simple it may be called directly from `Main.hs`, so it can live
  in the library too. **Decision for placement:** put `handleAgentConfigShow` in the
  library at `seihou-cli/src/Seihou/CLI/AgentConfigShow.hs` since it imports no
  executable-only dependency; register it in the library stanza of the cabal file. Only the
  `AgentCommand` constructor and parser live in `src-exe` (inside `Commands.hs`).
- In `seihou-cli/src-exe/Main.hs`: add the dispatch arm
  `AgentConfigShow -> handleAgentConfigShow`.

Register the new library module `Seihou.CLI.AgentConfigShow` under the
`seihou-cli-internal` library's `exposed-modules` in `seihou-cli/seihou-cli.cabal`.

Tests: add `formatResolvedAgentConfig` cases to `AgentConfigSpec` (or a small dedicated
`AgentConfigShowSpec`) asserting that a known set of resolutions renders the expected
labels — e.g. a command whose model comes from `SourceLocalCommand` shows
`[local: agent.run.model]`, and an unset model shows `(default)` with
`[built-in default]`. These are pure string assertions.

Acceptance: `cabal run seihou -- agent config` prints the table; `cabal run seihou -- agent
--help` lists the new `config` subcommand; the format tests pass.

### Milestone 4 — Documentation and full validation

Scope: document the new keys, precedence, and command, then run the whole suite. At the end
the user docs describe per-command configuration and the inspection command, and all tests
pass.

Edit `docs/user/agent-assistance.md`: in the provider/model configuration section
(currently around the "Selecting a provider" and precedence list near lines 21–46), add the
per-command keys and update the precedence list to the eight-tier chain from Purpose. Add a
short "Inspecting resolved configuration" subsection showing `seihou agent config` output.

Edit `docs/user/config-and-variables.md`: at the `#agent-provider-defaults` anchor
referenced by `agent-assistance.md`, document `agent.<command>.{provider,model}` and the
project-over-global rule with a worked example.

Edit `docs/cli/agent.md`: add the `config` subcommand to the agent command reference.

Edit `docs/user/CHANGELOG.md`: add an entry describing per-command agent provider/model
configuration and `seihou agent config`. (If a `seihou-update-docs` skill workflow is
preferred, follow it; otherwise edit directly.)

Acceptance: `cabal test` (full suite) passes; the manual transcript in Validation matches.


## Concrete Steps

Run all commands from the repository root
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` unless stated otherwise.

Build and run the focused resolver tests during Milestone 1:

```bash
cabal build seihou-cli
cabal test seihou-cli-test --test-options '--pattern AgentConfig'
```

Expected: the suite reports the new case names (per-command override, project-over-global,
global command over global default, CLI provenance, built-in default) all passing, and the
pre-existing cases still pass.

Exercise dispatch during Milestone 2 (uses your real global config — prefer a scratch
`HOME` to avoid mutating personal config):

```bash
export HOME="$(mktemp -d)"
cabal run seihou -- config init
cabal run seihou -- config set agent.model claude-sonnet-5 --global
cabal run seihou -- config set agent.assist.model gpt-5-mini --global
cabal run seihou -- config set agent.assist.provider codex-cli --global
cabal run seihou -- agent --debug assist "say hello" | head -1
cabal run seihou -- agent --debug run "say hello" | head -1
```

`--debug` prints the resolved system prompt and exits without contacting a provider, so
these confirm the commands parse and reach the handler with their per-command config. Full
model verification is done through the inspection command below.

Inspect resolved config during Milestone 3 (continuing the scratch `HOME` session, and
inside a project directory to demonstrate local override):

```bash
mkdir -p "$HOME/proj" && cd "$HOME/proj"
cabal run --project-dir=/Users/shinzui/Keikaku/bokuno/seihou-project/seihou seihou -- \
  init >/dev/null 2>&1 || true
cabal run --project-dir=/Users/shinzui/Keikaku/bokuno/seihou-project/seihou seihou -- \
  config set agent.run.model claude-opus-4-8
cabal run --project-dir=/Users/shinzui/Keikaku/bokuno/seihou-project/seihou seihou -- \
  agent config
```

Expected output matches the transcript in Purpose: `run` shows model `claude-opus-4-8`
labelled `[local: agent.run.model]`; `assist` shows `gpt-5-mini` labelled
`[global: agent.assist.model]` and provider `codex-cli`; other commands fall back to
`claude-sonnet-5` `[global: agent.model]`.

Full validation during Milestone 4:

```bash
cabal test
```

Expected: all suites pass. Record the summary line count in Outcomes.


## Validation and Acceptance

The feature is accepted when all of the following hold:

1. **Per-command config unit tests pass.**
   `cabal test seihou-cli-test --test-options '--pattern AgentConfig'` demonstrates: a
   per-command key overrides the default key in the same scope; a local default key
   overrides a global per-command key (project overrides global); a global per-command key
   overrides a global default key; CLI subcommand flags win and are labelled correctly; and
   the built-in default (`claude-cli`, model unset) applies when nothing is set.

2. **Backward compatibility.** Every pre-existing case in
   `seihou-cli/test/Seihou/CLI/AgentConfigSpec.hs` still passes unchanged in expected value.
   A user who set only `agent.provider`/`agent.model` sees identical resolution.

3. **Dispatch honors per-command keys.** With a scratch `HOME`, after
   `seihou config set agent.assist.model gpt-5-mini --global` and
   `seihou config set agent.run.model claude-opus-4-8` (local), `seihou agent config` prints
   `gpt-5-mini` for `assist` and `claude-opus-4-8` for `run`, each with the correct source
   label, while unconfigured commands show `claude-sonnet-5 [global: agent.model]` (given
   `agent.model` set globally) or `[built-in default]` when no default is set.

4. **Inspection command is discoverable and correct.**
   `seihou agent --help` lists `config`; `seihou agent config` prints the per-command table
   plus the eight-tier precedence legend; the pure format tests pass.

5. **Documentation reflects reality.** `docs/user/agent-assistance.md`,
   `docs/user/config-and-variables.md`, and `docs/cli/agent.md` describe the per-command
   keys, the project-over-global rule, and `seihou agent config`; `docs/user/CHANGELOG.md`
   has an entry.

6. **Full suite green.** `cabal test` passes.


## Idempotence and Recovery

All edits are additive and repeatable. Re-running the resolver or the tests has no side
effects. The manual verification uses a scratch `HOME` created with `mktemp -d`; nothing
touches the developer's real `~/.config/seihou/config.dhall`. If a step accidentally reads
or writes real config, that is a defect to fix — tests must use pure `Map`s and manual
verification must use a temporary `HOME` and project directory.

If Milestone 2's dispatch change is committed before Milestone 3's inspection command, the
new per-command keys are silently honored but not yet viewable; this is safe and
observable via `--debug` and targeted tests. Milestones may be committed independently;
each leaves the build green because new code paths are additive and the flat resolver
remains intact.

To roll back a milestone, revert its commit(s); because `resolveAgentModelConfig` and
`loadAgentModelConfig` retain their original behavior throughout, reverting later
milestones never breaks earlier ones.


## Interfaces and Dependencies

No new external libraries are introduced. The change builds on existing modules:

- `seihou-cli/src/Seihou/CLI/AgentCompletion.hs` — reuse `AgentProvider`,
  `AgentModelConfig`, `defaultAgentModelConfig`, `providerFromText`, `providerToText`.
- `seihou-core/src/Seihou/Effect/ConfigReader.hs` and
  `seihou-core/src/Seihou/Effect/ConfigReaderInterp.hs` — reuse `readLocalConfig`,
  `readGlobalConfig`, `runConfigReader`.
- `seihou-cli/src/Seihou/CLI/Shared.hs` — reuse `formatConfigError`.

New/changed library interfaces at completion of the plan, all in
`seihou-cli/src/Seihou/CLI/AgentConfig.hs` unless noted:

```haskell
data AgentCommandName = AgentCmdAssist | AgentCmdBootstrap | AgentCmdSetup
                      | AgentCmdRun | AgentCmdPromptRun
agentCommandSegment :: AgentCommandName -> Text
agentCommandLabel   :: AgentCommandName -> Text
allAgentCommands    :: [AgentCommandName]

agentCommandProviderConfigKey :: AgentCommandName -> Text
agentCommandModelConfigKey    :: AgentCommandName -> Text

data AgentConfigSource = SourceCliSubcommand | SourceCliParent | SourceEnv
                       | SourceLocalCommand | SourceLocalDefault
                       | SourceGlobalCommand | SourceGlobalDefault
                       | SourceBuiltinDefault
data ResolvedAgentField a = ResolvedAgentField { resolvedValue :: a, resolvedSource :: AgentConfigSource }

resolveAgentModelConfigFor
  :: AgentCommandName -> AgentConfigInputs
  -> Either Text (ResolvedAgentField AgentProvider, ResolvedAgentField (Maybe Text))

loadAgentModelConfigFor
  :: AgentCommandName -> Maybe Text -> Maybe Text -> Bool -> Bool
  -> IO (Either Text AgentModelConfig)

data ResolvedCommandConfig = ResolvedCommandConfig
  { rccCommand :: AgentCommandName
  , rccProvider :: ResolvedAgentField AgentProvider
  , rccModel :: ResolvedAgentField (Maybe Text)
  }
loadResolvedAgentConfig   :: IO (Either Text [ResolvedCommandConfig])
formatResolvedAgentConfig :: [ResolvedCommandConfig] -> Text
agentConfigSourceLabel    :: AgentConfigSource -> Text -> Text

-- Unchanged, retained for backward compatibility:
resolveAgentModelConfig :: AgentConfigInputs -> Either Text AgentModelConfig
loadAgentModelConfig    :: Maybe Text -> Maybe Text -> IO (Either Text AgentModelConfig)
```

New library module `seihou-cli/src/Seihou/CLI/AgentConfigShow.hs`:

```haskell
handleAgentConfigShow :: IO ()
```

Executable changes:

- `seihou-cli/src-exe/Seihou/CLI/Commands.hs`: `AgentCommand` gains `AgentConfigShow`;
  `agentConfigInfo :: ParserInfo AgentCommand` and its `command "config"` registration.
- `seihou-cli/src-exe/Main.hs`: private `resolveAgentModelConfigFor` helper taking the
  command name; dispatch arms pass the matching `AgentCommandName`; `AgentConfigShow` arm
  calls `handleAgentConfigShow`.

Cabal registration in `seihou-cli/seihou-cli.cabal`:

- `Seihou.CLI.AgentConfigShow` added to the `seihou-cli-internal` library `exposed-modules`.
- Any new test module (if a dedicated `AgentConfigShowSpec` is used) added to the
  `seihou-cli-test` `other-modules` and aggregated in `seihou-cli/test/Main.hs`.

The CLI module placement check `nix/check-cli-module-placement.sh` must still pass:
`Seihou.CLI.AgentConfigShow` is library-eligible (no `Options.Applicative`,
`Data.FileEmbed`, `GitHash`, or `Paths_seihou_cli` import, and it does not import
`Seihou.CLI.Commands`), so it belongs in the library, not the executable.
