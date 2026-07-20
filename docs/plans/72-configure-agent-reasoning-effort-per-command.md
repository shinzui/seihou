---
id: 72
slug: configure-agent-reasoning-effort-per-command
title: "Configure agent reasoning effort per command"
kind: exec-plan
created_at: 2026-07-20T17:33:16Z
intention: "intention_01ky09cttvemeatvvtqxnt1gdm"
---

# Configure agent reasoning effort per command

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

Seihou's `seihou agent` commands (`assist`, `bootstrap`, `setup`, `run`, `migrate`) and the
`seihou prompt run` command launch an AI agent — for the local CLI providers (`claude-cli`,
`codex-cli`) an interactive terminal session, for the API providers (`anthropic`, `openai`)
a one-shot completion. Today a user can configure the **provider** and **model** per command
(see `docs/plans/70-support-per-command-hierarchical-agent-model-and-provider-configuration.md`),
but not the **reasoning effort**: how hard the model thinks before acting.

Baikai 0.4.0.0 added that capability (see the baikai plan
`docs/plans/44-add-reasoning-effort-control-to-interactive-cli-launches.md` in the baikai
repository). Its interactive launch request now carries an `effort :: Maybe ThinkingLevel`
field, and `ThinkingLevel` has six levels: `ThinkingMinimal`, `ThinkingLow`,
`ThinkingMedium`, `ThinkingHigh`, `ThinkingXHigh`, `ThinkingMax`. For the local CLI providers
Baikai translates this to `claude --effort <level>` / `codex -c model_reasoning_effort=<level>`;
for the API providers it maps to the provider's native reasoning-effort primitive through
Baikai's request `Options.thinking` field.

After this change, a user can set the reasoning effort with the same hierarchy already used
for provider and model:

1. A shared default key `agent.effort`, e.g. `seihou config set agent.effort high --global`.
2. Per-command overrides `agent.<command>.effort`, e.g.
   `seihou config set agent.run.effort max` (project-local) so blueprint runs think hard
   while `assist` stays cheaper.
3. An environment variable `SEIHOU_AGENT_EFFORT`.
4. A CLI flag `--effort <level>` on the parent `seihou agent` command, on each agent
   subcommand, and on `seihou prompt run`.

Resolution is hierarchical and provenance-tracked exactly like provider/model: local
overrides global, per-command overrides the shared default, and `seihou agent config` shows
the resolved effort for every command with the source of each value labelled.

**Reasoning effort** is a coarse dial (six named buckets from `minimal` to `max`) telling a
reasoning-capable model how much internal deliberation to spend before answering. Higher
effort generally means better answers but more latency and token cost.

**The observable outcome**, verifiable end-to-end:

```text
$ seihou config set agent.effort high --global
$ seihou config set agent.run.effort max          # local (project) scope
$ seihou agent config
...
  run          provider  claude-cli       [built-in default]
               model     claude-opus-4-8  [built-in default]
               effort    max              [local: agent.run.effort]
  assist       provider  claude-cli       [built-in default]
               model     claude-opus-4-8  [built-in default]
               effort    high             [global: agent.effort]
...
```

and, proving it reaches the CLI, `seihou agent --provider claude-cli --effort max run …`
launches `claude` with `--effort max` on its argv (Baikai builds that argv), while
`seihou prompt run <name> --effort low` launches with `--effort low`.

**"Also don't forget `seihou prompt run`."** `seihou prompt run` is a separate top-level
command (under `seihou prompt`, not `seihou agent`), so it has its own parser options and its
own dispatch arm in `seihou-cli/src-exe/Main.hs`. It already resolves per-command provider
and model config (as `AgentCmdPromptRun`), but because its wiring is separate from the agent
subcommands, this plan explicitly threads the new effort through the prompt-run parser,
dispatch arm, and handler too, and covers it in tests.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] Milestone 1: Upgrade the Baikai dependency bounds in `seihou-cli/seihou-cli.cabal` to
  admit `baikai 0.4`, `baikai-claude`/`baikai-openai` at their current release; rebuild.
- [x] Milestone 2: Add reasoning-effort to the config vocabulary and resolver in the library
  (`seihou-cli/src/Seihou/CLI/AgentConfig.hs` and `Seihou.CLI.AgentCompletion`): an
  `agentEffort` field on `AgentModelConfig`, `effortFromText`/`effortToText`,
  `agent.effort` / `agent.<command>.effort` keys, `SEIHOU_AGENT_EFFORT`, provenance-aware
  resolution (the resolver now returns a provider/model/effort triple); unit tests.
  Completed 2026-07-20 (landed together with Milestone 3 — see note).
- [x] Milestone 3: Add the `--effort` CLI flag (parent `agent`, every agent subcommand, and
  `prompt run`), thread it through the `Main.hs` dispatch **including the prompt-run arm**,
  and into both launch paths — the interactive request's `effort` field and the API path's
  `Options.thinking`. Completed 2026-07-20. Verified with a scratch `HOME`: `--effort` is
  listed on the parent, every subcommand, and `prompt run`; an invalid value is rejected with
  a diagnostic; a valid value parses and resolves. **Note:** M2 changed the arity/return type
  of `loadAgentModelConfigFor`/`resolveAgentModelConfigFor`, which the executable dispatch
  consumes, so M2 and M3 were committed together to keep every commit's build green.
- [x] Milestone 4: Show the resolved effort in `seihou agent config` (a third row per
  command); update `docs/user/agent-assistance.md`, `docs/user/config-and-variables.md`,
  `docs/cli/agent.md`, and `docs/user/CHANGELOG.md`; run the full suite. Completed
  2026-07-20. Live `seihou agent config` shows the effort row (e.g. `run` → `max [local:
  agent.run.effort]`, others → `high [global: agent.effort]`, unset → `(default) [built-in
  default]`). Full suite green: 347 CLI + core + extension tests pass.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Mirror the existing provider/model configuration machinery exactly for effort —
  same key shape (`agent.effort`, `agent.<command>.effort`), same precedence chain, same
  `SEIHOU_AGENT_*` environment variable style, same `--effort` flag placement (parent +
  subcommand + prompt run), same provenance display in `seihou agent config`.
  Rationale: The per-command hierarchical resolver from plan 70 is already the right shape;
  reusing it keeps one mental model for users and one code path for maintainers.
  Date: 2026-07-20

- Decision: The built-in default effort is **unset** (`Nothing`), unlike the model defaults
  which are pinned per provider. When effort is unset, Seihou passes no effort flag and the
  CLI/provider uses its own default.
  Rationale: The user asked to *configure* the thinking level, not to pin a default. Effort
  is a cost/latency dial the user should opt into; forcing a default could surprise users
  with higher token spend. Users who want determinism can set `agent.effort` explicitly.
  Date: 2026-07-20

- Decision: Effort applies to **all four providers**. For the CLI providers it flows through
  the interactive request's `effort` field (Baikai renders `--effort` / `model_reasoning_effort`).
  For the API providers it flows through Baikai's request `Options.thinking`.
  Rationale: Reasoning effort is meaningful for both interactive and one-shot use, and Baikai
  supports both paths; wiring only one would be a surprising half-feature.
  Date: 2026-07-20

- Decision: Accept effort text case-insensitively as one of
  `minimal | low | medium | high | xhigh | max`, mapping to the six `Baikai.ThinkingLevel`
  constructors. Reject anything else with a diagnostic listing the valid values (matching how
  `providerFromText` behaves for providers).
  Rationale: These are the canonical Baikai level names; a clear error beats silently
  ignoring a typo.
  Date: 2026-07-20

- Decision: `seihou prompt run` is threaded explicitly. Its options record, its parser, its
  dispatch arm, and `handlePromptRun` all gain effort, and a test asserts it resolves.
  Rationale: It is a separate command tree from `seihou agent`; the earlier provider/model
  work had to wire it separately, so effort must too, and the user explicitly flagged it.
  Date: 2026-07-20


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

Delivered exactly the Purpose. Reasoning effort is now configurable per agent command with
the same hierarchy and provenance as provider/model: `agent.effort` /
`agent.<command>.effort`, `SEIHOU_AGENT_EFFORT`, and a `--effort LEVEL` flag on the parent
`agent`, every subcommand, and `seihou prompt run`. The `seihou prompt run` gap was closed
explicitly — its separate parser option, dispatch arm, and handler all thread effort, and
`seihou prompt run --help` lists `--effort`. Effort reaches both launch paths (interactive
`effort` field for the CLIs, `Options.thinking` for the API providers), and `seihou agent
config` shows a labelled effort row per command. The built-in default is unset, so any
project that does not configure effort behaves exactly as before.

Validation: 29 `AgentConfig` + 9 `AgentConfigShow` unit cases pass (16 new across effort
resolution and display); a scratch-`HOME` run confirmed the flag, the precedence, the
diagnostic on an invalid value, and the `agent config` effort rows; the full suite (347 CLI +
core + extension) is green.

Lessons: (1) Adding a field to the exported `AgentModelConfig` record made every
missing-field literal in the test suite a runtime bottom that only surfaced under an `Eq`
comparison (`shouldBe`) — `AgentCompletionSpec` had four such literals; a `cfg` smart
constructor in `AgentConfigSpec` avoided the same trap there. (2) Baikai's `Options.thinking`
field name collides with `ThinkingContent.thinking`, so the record update had to be qualified
via `Baikai.Options`. (3) Because M2 changed `loadAgentModelConfigFor`'s arity/return type
(now a provider/model/effort triple), M2 and M3 had to land in one commit to keep the build
green.

Gaps / future work: effort remains unpinned by default (a deliberate cost/latency choice —
users opt in). The baikai coordinated release (0.4.0.0) was done by the user before this
work; seihou's bound was widened to `^>=0.4.0.0`. `seihou agent models` still ignores a
parent `--effort` silently (as it does `--model` filtering nuances); not worth a rejection
path.


## Context and Orientation

This section assumes the reader knows only the working tree. Read it fully before editing.

Seihou is a Haskell project scaffolding CLI. The relevant package is `seihou-cli`, split into
an internal library at `seihou-cli/src/` (`Seihou.CLI.*`) and an executable target at
`seihou-cli/src-exe/` (`Main.hs`, the option parser `Seihou.CLI.Commands`, and command
handlers). A repository convention (root `CLAUDE.md`, enforced by
`nix/check-cli-module-placement.sh`) keeps pure/reusable code in `src/` and only modules that
must import `Options.Applicative` (the parser) or another executable-only module in
`src-exe/`.

### The agent configuration machinery (plan 70)

`seihou-cli/src/Seihou/CLI/AgentCompletion.hs` defines the resolved config the handlers act
on:

```haskell
data AgentProvider = AgentProviderClaudeCli | AgentProviderCodexCli
                   | AgentProviderAnthropic | AgentProviderOpenAI

data AgentModelConfig = AgentModelConfig
  { agentProvider :: AgentProvider
  , agentModel :: Maybe Text
  }
```

`seihou-cli/src/Seihou/CLI/AgentConfig.hs` resolves that config with provenance. Its shape,
which this plan extends:

- `data AgentCommandName = AgentCmdAssist | AgentCmdBootstrap | AgentCmdSetup | AgentCmdRun
  | AgentCmdMigrate | AgentCmdPromptRun`, with `agentCommandSegment` giving the config-key
  token (`"assist"`, …, `"prompt-run"`), `agentCommandLabel` the display label, and
  `allAgentCommands = [minBound .. maxBound]`.
- Key builders `agentProviderConfigKey = "agent.provider"`, `agentModelConfigKey = "agent.model"`,
  `agentCommandProviderConfigKey c = "agent." <> segment <> ".provider"`, and the `.model`
  analogue.
- `data AgentConfigInputs { cliProvider, cliModel, cliProviderFromSubcommand,
  cliModelFromSubcommand, envProvider, envModel, localConfig, globalConfig }` and a smart
  constructor `baseAgentConfigInputs`.
- Provenance types `data AgentConfigSource = SourceCliSubcommand | SourceCliParent | SourceEnv
  | SourceLocalCommand | SourceLocalDefault | SourceGlobalCommand | SourceGlobalDefault
  | SourceBuiltinDefault`; `data AgentField = ProviderField | ModelField`;
  `data ResolvedAgentField a = ResolvedAgentField { resolvedValue :: a, resolvedSource :: AgentConfigSource }`;
  `agentConfigSourceLabel :: AgentCommandName -> AgentField -> AgentConfigSource -> Text`.
- Core resolvers: `resolveAgentModelConfigFor :: AgentCommandName -> AgentConfigInputs ->
  Either Text (ResolvedAgentField AgentProvider, ResolvedAgentField (Maybe Text))`; a flat
  `resolveAgentModelConfig`; IO loaders `loadAgentModelConfigFor` and (for the inspection
  command) `loadResolvedAgentConfig :: IO (Either Text [ResolvedCommandConfig])` where
  `data ResolvedCommandConfig { rccCommand, rccProvider, rccModel }`.

The precedence chain, highest first: subcommand flag → parent `agent` flag → `SEIHOU_AGENT_*`
env → local `agent.<command>.<field>` → local `agent.<field>` → global `agent.<command>.<field>`
→ global `agent.<field>` → built-in default.

`seihou-cli/src/Seihou/CLI/AgentConfigShow.hs` renders `seihou agent config`:
`formatResolvedAgentConfig :: [ResolvedCommandConfig] -> Text` and `handleAgentConfigShow :: IO ()`.
It prints each command with a `provider` row (carrying the command label) and a `model` row
(blank label), each `[source]`-labelled, plus a precedence legend.

The parser is `seihou-cli/src-exe/Seihou/CLI/Commands.hs`. The parent `agent` carries
`agentProvider`/`agentModel` (`--provider`/`--model` via helpers `providerOption`,
`modelOption`); every agent subcommand's option record and `PromptRunOpts` carry their own
`--provider`/`--model`. `Main.hs` dispatch resolves per command via a private
`resolveAgentModelConfigFor :: AgentCommandName -> Maybe Text -> Maybe Text -> Maybe Text ->
Maybe Text -> IO AgentModelConfig` (parent flags, then subcommand flags) that calls the
library `loadAgentModelConfigFor`.

### The launch paths that must receive effort

- Interactive (CLI providers): `seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs`.
  `launchConfiguredAgentWith` dispatches on `modelConfig.agentProvider` to `launchClaude` /
  `launchCodex`, each of which builds a Baikai `interactiveLaunchRequest {...}` record. Today
  it sets `systemPrompt`, `modelId`, `workingDir`, `extraDirs`, `safety`. Baikai's request
  type also has an `effort :: Maybe ThinkingLevel` field (from `Baikai.Interactive`), which
  we will set. The Baikai module is imported as `Baikai.Interactive (…, modelId, …)`; add
  `effort` to that import list.
- API (Anthropic/OpenAI providers): `seihou-cli/src/Seihou/CLI/AgentCompletion.hs`,
  `runAgentCompletion`. It calls `Baikai.completeRequest model ctx Baikai.emptyOptions`.
  `Baikai.Options` has a `thinking :: Maybe ThinkingLevel` field; we will set it from the
  resolved effort. Note: today the agent handlers route CLI providers to
  `launchConfiguredAgent` and only API providers to `runAgentCompletion` (they branch on
  `agentProvider`), so each launch path sees the same `AgentModelConfig`.

### Baikai 0.4 interface (already released)

`Baikai.ThinkingLevel` exports `ThinkingLevel (..)` with the six constructors above,
`renderThinkingLevel :: ThinkingLevel -> Text` (canonical names `minimal`…`max`), and it is
re-exported from the umbrella `Baikai` module. `Baikai.Interactive.InteractiveLaunchRequest`
has `effort :: Maybe ThinkingLevel` defaulting to `Nothing` in `interactiveLaunchRequest`.
`Baikai.Options` (`emptyOptions`) has `thinking :: Maybe ThinkingLevel`. The seihou-cli cabal
currently pins `baikai ^>=0.3.1.0` (which excludes 0.4), so Milestone 1 must widen it.


## Plan of Work

Four milestones. Each is independently verifiable and leaves the build green.

### Milestone 1 — Upgrade the Baikai dependency

Scope: admit Baikai 0.4 so the new `effort`/`thinking` fields are in scope. Nothing else
changes yet.

Edit `seihou-cli/seihou-cli.cabal`. The file references `baikai`, `baikai-claude`, and
`baikai-openai` across three stanzas (the internal library, the executable, and the test
suite). Widen each caret bound to admit the released versions — `baikai` to admit `0.4.0.0`,
and `baikai-claude`/`baikai-openai` to admit their current release. Confirm the exact current
versions by reading their `.cabal` files in the baikai checkout (located via `mori registry
show baikai --full`, e.g. `/Users/shinzui/Keikaku/bokuno/baikai/*/*.cabal`) before choosing
bounds; at time of writing they are `baikai 0.4.0.0`, `baikai-claude 0.3.0.2`,
`baikai-openai 0.3.0.2`.

Acceptance: `cabal build seihou-cli-internal` and `cabal build seihou` succeed against the
new Baikai. No behavior change.

### Milestone 2 — Reasoning-effort in the config vocabulary and resolver

Scope: teach the library to resolve an effort value with the same hierarchy and provenance as
provider/model. Pure and unit-tested; no CLI or launch changes yet.

1. In `seihou-cli/src/Seihou/CLI/AgentCompletion.hs`:
   - Add `agentEffort :: Maybe ThinkingLevel` to `AgentModelConfig` (import
     `Baikai.ThinkingLevel (ThinkingLevel (..))` or use `Baikai` qualified). Update
     `defaultAgentModelConfig` to `agentEffort = Nothing`.
   - Add `effortFromText :: Text -> Either Text ThinkingLevel` (case-insensitive; maps
     `minimal|low|medium|high|xhigh|max`; error lists the valid set) and
     `effortToText :: ThinkingLevel -> Text` (reuse `Baikai.renderThinkingLevel`). Export both.

2. In `seihou-cli/src/Seihou/CLI/AgentConfig.hs`:
   - Add `agentEffortConfigKey = "agent.effort"`, `agentCommandEffortConfigKey c =
     "agent." <> agentCommandSegment c <> ".effort"`, and `agentEffortEnvVar = "SEIHOU_AGENT_EFFORT"`.
   - Extend `AgentField` with `EffortField` and `agentConfigSourceLabel` accordingly (so
     labels read `local: agent.run.effort` etc.).
   - Add `cliEffort :: Maybe Text` and `cliEffortFromSubcommand :: Bool` to
     `AgentConfigInputs` (and `baseAgentConfigInputs`).
   - Add an `effort` candidate list mirroring `providerCandidates`/`modelCandidates` and have
     `resolveAgentModelConfigFor` also resolve an effort field. Its return type becomes a
     triple `(ResolvedAgentField AgentProvider, ResolvedAgentField (Maybe Text),
     ResolvedAgentField (Maybe ThinkingLevel))`. A resolved effort text is parsed with
     `effortFromText`; a parse failure returns `Left`. Unset → `Nothing` with
     `SourceBuiltinDefault`. Keep the flat `resolveAgentModelConfig` unchanged in behavior
     (effort stays `Nothing` there — it is the legacy adapter).
   - Update `loadAgentModelConfigFor` to read `SEIHOU_AGENT_EFFORT`, accept the CLI effort +
     its from-subcommand flag, and project the resolved effort into `AgentModelConfig.agentEffort`.
   - Update `ResolvedCommandConfig` with `rccEffort :: ResolvedAgentField (Maybe ThinkingLevel)`
     and `loadResolvedAgentConfig` to populate it.

3. Tests in `seihou-cli/test/Seihou/CLI/AgentConfigSpec.hs`: add cases proving effort follows
   the same precedence (per-command over default, local over global, env over config, CLI over
   env, built-in default = unset), invalid-effort diagnostics, and case-insensitive parsing.
   Because `resolveAgentModelConfigFor` now returns a triple, update existing helper
   accessors (`providerOf`, `modelOf`) and add `effortOf`.

Acceptance: `cabal test seihou-cli-test --test-options '--pattern AgentConfig'` passes,
including the new effort cases.

### Milestone 3 — `--effort` flag, dispatch (incl. prompt run), and launch wiring

Scope: expose effort on the CLI and make it actually reach the agent. At the end, a real
`seihou agent … --effort …` and `seihou prompt run … --effort …` pass the effort to Baikai.

1. Parser (`seihou-cli/src-exe/Seihou/CLI/Commands.hs`): add an `effortOption :: Parser (Maybe Text)`
   helper (metavar `LEVEL`, help listing the six levels) next to `providerOption`/`modelOption`.
   Add `agentEffort :: Maybe Text` to `AgentOpts` and wire `effortOption` into `agentParser`. Add a
   `*Effort :: Maybe Text` field to each agent subcommand's option record and to
   `PromptRunOpts`, wiring `effortOption` into each subcommand parser and `promptRunParser`.

2. Dispatch (`seihou-cli/src-exe/Main.hs`): extend the private `resolveAgentModelConfigFor`
   helper to take parent and subcommand effort flags too, computing
   `effort = subEffort <|> parentEffort` and `effortFromSub = isJust subEffort`, passing them
   to the library `loadAgentModelConfigFor`. Update every agent dispatch arm to pass its
   subcommand effort **and the prompt-run arm** (`AgentCmdPromptRun`, parent effort `Nothing`,
   subcommand `promptRunOpts.runPromptEffort`).

3. Launch (`seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs`): add `effort` to the
   `Baikai.Interactive` import list; thread `modelConfig.agentEffort` into `launchClaude`/
   `launchCodex` and set `effort = <resolved>` on the `interactiveLaunchRequest {...}` records.

4. API path (`seihou-cli/src/Seihou/CLI/AgentCompletion.hs`): in `runAgentCompletion`, replace
   `Baikai.emptyOptions` with `Baikai.emptyOptions { Baikai.thinking = req.completionModelConfig.agentEffort }`.

Acceptance (behavioral, no live model needed): with a scratch `HOME`,
`seihou agent --debug --provider claude-cli --effort max assist "hi"` still prints the prompt
(debug short-circuits before launch, so this just proves the flag parses and resolves), and
`seihou agent config` (Milestone 4) shows the effort. Additionally confirm
`seihou prompt run --help` lists `--effort`.

### Milestone 4 — Display, docs, validation

Scope: surface effort in the inspection command, document it, and validate the whole suite.

1. `seihou-cli/src/Seihou/CLI/AgentConfigShow.hs`: render a third `effort` row per command
   (blank label column, like the model row), value = `effortToText` or `(default)` when unset,
   `[source]`-labelled via `agentConfigSourceLabel cmd EffortField …`. Extend the format tests
   in `seihou-cli/test/Seihou/CLI/AgentConfigShowSpec.hs`.

2. Docs: update `docs/user/agent-assistance.md` (a "reasoning effort" subsection with the six
   levels, the `agent.effort` / `agent.<command>.effort` keys, and that it applies to
   `prompt run` too), `docs/user/config-and-variables.md` (the agent-provider-defaults section
   → add the effort keys and precedence), `docs/cli/agent.md` (the `--effort` option and the
   `agent config` effort row), and `docs/user/CHANGELOG.md`.

3. Validation: run the full test suite and, if the interactive binaries are available, a
   `--debug` smoke of `agent --effort`.

Acceptance: `cabal test all` green (staging the `seihou` binary at the build-tool path if the
`UpdateE2ESpec`/completion E2E tests demand it — see plan 70's note); `seihou agent config`
shows an effort row; docs updated.


## Concrete Steps

Run from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` unless noted.

Milestone 1:

```bash
cabal build seihou 2>&1 | tail -3
```

Milestone 2:

```bash
cabal test seihou-cli-test --test-options '--pattern AgentConfig'
```

Milestone 3–4 (scratch HOME so real config is untouched):

```bash
BIN=$(cabal list-bin seihou)
export HOME="$(mktemp -d)"
"$BIN" config set agent.effort high --global
"$BIN" config set agent.run.effort max
"$BIN" agent config
"$BIN" prompt run --help | grep -- --effort
```

Expected `agent config` (excerpt): the `run` command shows `effort max [local: agent.run.effort]`
and the others show `effort high [global: agent.effort]`; commands with nothing set show
`effort (default) [built-in default]` before any config is written.

Full validation:

```bash
cabal test all
```


## Validation and Acceptance

Accepted when:

1. Effort resolves with the same hierarchy and provenance as provider/model: unit tests in
   `AgentConfigSpec` prove per-command-over-default, local-over-global, env-over-config,
   CLI-over-env, invalid-value diagnostics, and unset → built-in default.
2. `seihou agent config` prints an `effort` row per command (all six commands including
   `prompt run`), labelled with its source; format tests pass.
3. Effort reaches the agent: the resolved `AgentModelConfig.agentEffort` is set from
   `--effort`/env/config, the interactive launch sets Baikai's `effort` field, and the API
   path sets `Options.thinking`. `seihou prompt run --effort <level>` is wired end-to-end
   (parser → dispatch → handler).
4. Unset effort changes nothing: with no effort configured, argv and API options are
   identical to before this plan (no `--effort`, `thinking = Nothing`).
5. `cabal test all` is green; docs and CHANGELOG describe the feature.


## Idempotence and Recovery

All edits are additive and repeatable. Manual checks use a scratch `HOME`; automated tests
use pure maps or temporary directories — never the real `~/.config/seihou/config.dhall`.
Milestones are independently committable and each leaves the build green: Milestone 1 only
widens bounds; Milestone 2 adds an unused-by-default field (`agentEffort = Nothing`) and pure
resolution; Milestones 3–4 consume it. To roll back, revert a milestone's commit; earlier
milestones stay valid because later ones only read what earlier ones added.


## Interfaces and Dependencies

Depends on Baikai 0.4.0.0 (released): `Baikai.ThinkingLevel.ThinkingLevel (..)`,
`renderThinkingLevel`; `Baikai.Interactive`'s `effort` field; `Baikai.Options`'s `thinking`
field. No other new dependencies.

Interfaces at completion:

```haskell
-- Seihou.CLI.AgentCompletion
data AgentModelConfig = AgentModelConfig
  { agentProvider :: AgentProvider, agentModel :: Maybe Text
  , agentEffort :: Maybe Baikai.ThinkingLevel }
effortFromText :: Text -> Either Text Baikai.ThinkingLevel
effortToText   :: Baikai.ThinkingLevel -> Text

-- Seihou.CLI.AgentConfig
agentEffortConfigKey        :: Text
agentCommandEffortConfigKey :: AgentCommandName -> Text
agentEffortEnvVar           :: String
data AgentField = ProviderField | ModelField | EffortField
resolveAgentModelConfigFor  :: AgentCommandName -> AgentConfigInputs
  -> Either Text ( ResolvedAgentField AgentProvider
                 , ResolvedAgentField (Maybe Text)
                 , ResolvedAgentField (Maybe Baikai.ThinkingLevel) )
loadAgentModelConfigFor     :: AgentCommandName -> Maybe Text -> Maybe Text -> Maybe Text
                            -> Bool -> Bool -> Bool -> IO (Either Text AgentModelConfig)
data ResolvedCommandConfig = ResolvedCommandConfig
  { rccCommand :: AgentCommandName
  , rccProvider :: ResolvedAgentField AgentProvider
  , rccModel :: ResolvedAgentField (Maybe Text)
  , rccEffort :: ResolvedAgentField (Maybe Baikai.ThinkingLevel) }
```

Executable changes: `AgentOpts`, each agent subcommand opts record, and `PromptRunOpts` gain
an effort field; `Main.hs`'s private `resolveAgentModelConfigFor` gains effort parameters and
every dispatch arm (including prompt run) passes them; `AgentLaunchExec` sets Baikai's
interactive `effort` field. Cabal: widen `baikai*` bounds to admit 0.4.

Downstream/coordination: this consumes the baikai plan 44 work
(`docs/plans/44-add-reasoning-effort-control-to-interactive-cli-launches.md` in the baikai
repository) and complements seihou plan 70's provider/model configuration
(`docs/plans/70-support-per-command-hierarchical-agent-model-and-provider-configuration.md`).
