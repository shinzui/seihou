---
id: 36
slug: add-baikai-dependency-and-agent-completion-facade
title: "Add Baikai dependency and agent completion facade"
kind: exec-plan
created_at: 2026-05-23T22:53:01Z
intention: "intention_01ksbgksmgeaesf6sft8prdvyn"
master_plan: "docs/masterplans/4-baikai-backed-configurable-agent-assistance.md"
---

# Add Baikai dependency and agent completion facade

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, Seihou has a small internal facade for asking an AI provider for one text completion through the `baikai` library. The facade is the only place in Seihou that knows how to register Baikai providers, construct a Baikai `Model`, convert Seihou's rendered agent prompt into a Baikai `Context`, call `completeRequest`, and return assistant text or a fallback diagnostic.

This plan does not change the user-facing `seihou agent` commands by itself. It creates the build dependency and internal API that later plans use so those commands can run against Anthropic API, OpenAI-compatible API, `claude -p`, or `codex exec` through one abstraction.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] 2026-05-23: Add Baikai packages to the local build inputs.
- [x] 2026-05-23: Create `Seihou.CLI.AgentCompletion` with provider registration, model construction, request execution, and response text extraction.
- [x] 2026-05-23: Add focused tests for model construction and response extraction helpers that do not call a live provider.
- [x] 2026-05-23: Build `seihou-cli` enough to prove the new imports and dependencies compile.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- Surprise: The Baikai source path from the Seihou repository root is `../../baikai`, not `../baikai`.
  Evidence: the first `cabal build seihou-cli-internal` failed with `The package location '../baikai/baikai' does not exist`; changing `cabal.project` to `../../baikai/baikai`, `../../baikai/baikai-claude`, and `../../baikai/baikai-openai` let Cabal resolve and build the packages.

- Surprise: Baikai re-exports duplicate record selectors named `api` and `provider` from both `Model` and `Response`.
  Evidence: the first test compile failed with `Ambiguous occurrence 'Baikai.api'`; the tests now import `Baikai.Model` qualified for model selectors and `Baikai.Response` qualified for response construction.


## Decision Log

Record every decision made while working on the plan.

- Decision: Put the Seihou-facing facade in `seihou-cli/src/Seihou/CLI/AgentCompletion.hs`, not in each executable handler.
  Rationale: `Assist`, `Bootstrap`, `Setup`, and `AgentRun` currently share launch helpers through `Seihou.CLI.AgentLaunch`; the Baikai call path should follow the same library-first pattern so it can be unit-tested without `Options.Applicative`, `Data.FileEmbed`, or process-launch trapping.
  Date: 2026-05-23

- Decision: Treat Baikai CLI providers as batch completion providers, not interactive Claude Code sessions.
  Rationale: `mori registry show shinzui/baikai --full` and `/Users/shinzui/Keikaku/bokuno/baikai/docs/user/cli-providers.md` show that `Baikai.Provider.Claude.Cli` drives `claude -p` and `Baikai.Provider.OpenAI.Cli` drives `codex exec`; both return one assistant message and explicitly do not support tool calling.
  Date: 2026-05-23

- Decision: Use local Baikai package paths in `cabal.project` instead of a GitHub `source-repository-package` stanza for Baikai itself.
  Rationale: Mori identifies `/Users/shinzui/Keikaku/bokuno/baikai` as the source of truth on this machine, and local package paths keep Seihou building against the inspected source. The Streamly pin remains a `source-repository-package` because Baikai's own `cabal.project` uses that unreleased package pair.
  Date: 2026-05-23

- Decision: Name Seihou's model config record fields `agentProvider` and `agentModel`.
  Rationale: Baikai exports record fields named `provider` and `model`; using Seihou-specific field names avoids ambiguous selector imports for downstream command code while keeping the public facade small.
  Date: 2026-05-23


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

Completed on 2026-05-23. Seihou now has a `Seihou.CLI.AgentCompletion` facade that owns provider parsing, default model configuration, Baikai `Model` construction, provider registration, request dispatch, and assistant text extraction. The facade compiles without live API keys or installed AI CLIs, and its pure helpers are covered by focused tests. Later plans can consume `AgentProvider`, `AgentModelConfig`, `defaultAgentModelConfig`, `providerFromText`, `providerToText`, `buildBaikaiModel`, and `runAgentCompletion` without importing Baikai directly.


## Context and Orientation

The repository root is `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`. `mori show --full` identifies this project as `shinzui/seihou`, a Haskell application with packages `seihou-core`, `seihou-cli`, and two test suites. The current `cabal.project` lists only local packages:

```cabal
packages:
  seihou-core
  seihou-cli
```

`mori registry show shinzui/baikai --full` locates the Baikai source at `/Users/shinzui/Keikaku/bokuno/baikai`. The package set there contains `baikai`, `baikai-claude`, and `baikai-openai`. The core package exports `Baikai`, `Baikai.Model`, `Baikai.Context`, `Baikai.Options`, `Baikai.Response`, and the provider registry. `baikai-claude` exports `Baikai.Provider.Claude.Api` and `Baikai.Provider.Claude.Cli`; `baikai-openai` exports `Baikai.Provider.OpenAI.Api` and `Baikai.Provider.OpenAI.Cli`.

The Baikai docs at `/Users/shinzui/Keikaku/bokuno/baikai/docs/user/cli-providers.md` say the CLI providers use `AnthropicMessagesCli` for `claude -p` and `OpenAICompletionsCli` for `codex exec`. A hand-built CLI model sets `modelId` to the model name to pass via `--model`; an empty `modelId` lets the CLI choose its default.

The existing Seihou agent launcher is split between `seihou-cli/src/Seihou/CLI/AgentLaunch.hs` and `seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs`. `AgentLaunch.hs` gathers context, formats prompt sections, and defines allowed Claude Code tools. `AgentLaunchExec.hs` currently shells out to the interactive `claude` CLI with `rawSystem`, `--system-prompt`, `--add-dir`, and `--allowedTools`.


## Plan of Work

Milestone 1 adds the dependency. Edit `cabal.project` to add a `source-repository-package` stanza for Baikai using the local repository's Git remote and current commit, with `subdir: baikai baikai-claude baikai-openai`, or use the local source path mechanism already accepted by this repository if the implementation session confirms one is preferred. Edit `seihou-cli/seihou-cli.cabal` so both the `seihou-cli-internal` library and `seihou` executable can see `baikai`, `baikai-claude`, `baikai-openai`, `generic-lens`, `lens`, and `vector` if the new code imports them directly. Prefer putting Baikai-consuming code in the library and keeping executable imports minimal.

Milestone 2 creates `seihou-cli/src/Seihou/CLI/AgentCompletion.hs` and exposes it from `seihou-cli/seihou-cli.cabal`. Define small Seihou-owned types instead of leaking Baikai everywhere:

```haskell
data AgentProvider
  = AgentProviderClaudeCli
  | AgentProviderCodexCli
  | AgentProviderAnthropic
  | AgentProviderOpenAI
  deriving stock (Eq, Show, Generic)

data AgentModelConfig = AgentModelConfig
  { provider :: AgentProvider,
    model :: Maybe Text
  }

data AgentCompletionRequest = AgentCompletionRequest
  { systemPrompt :: Text,
    initialPrompt :: Maybe Text,
    modelConfig :: AgentModelConfig
  }
```

The exact record fields can be adjusted during implementation, but the facade must expose helpers that later plans can call without importing Baikai directly: `defaultAgentModelConfig`, `providerFromText`, `providerToText`, `buildBaikaiModel`, and `runAgentCompletion`.

Milestone 3 makes the facade register providers before dispatch. Call `Baikai.Provider.Claude.Cli.register`, `Baikai.Provider.OpenAI.Cli.register`, `Baikai.Provider.Claude.Api.register`, and `Baikai.Provider.OpenAI.Api.register` once inside `runAgentCompletion` or a helper it calls. Registration is idempotent according to `/Users/shinzui/Keikaku/bokuno/baikai/docs/user/getting-started.md`, so a simple call-per-command is acceptable.

Milestone 4 adds pure tests in `seihou-cli/test/Seihou/CLI/AgentCompletionSpec.hs`. Test text parsing, default provider/model behavior, and that `buildBaikaiModel AgentProviderClaudeCli (Just "sonnet")` creates a model with `api = AnthropicMessagesCli`, `provider = "anthropic"`, and `modelId = "sonnet"`. Add the test module to `seihou-cli/seihou-cli.cabal` and `seihou-cli/test/Main.hs`.


## Concrete Steps

Run these commands from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`:

```bash
mori registry show shinzui/baikai --full
mori registry docs shinzui/baikai
cabal build seihou-cli-internal
cabal test seihou-cli-test --test-options '--pattern AgentCompletion'
```

The first two commands confirm the local Baikai source path and docs. The build should compile `Seihou.CLI.AgentCompletion`. The focused test command should run only the new spec when the test runner supports pattern filtering; if the runner ignores the pattern, the full CLI suite may run instead.

Validation completed on 2026-05-23:

```text
$ cabal build seihou-cli-internal
...
[31 of 31] Compiling Seihou.Fzf.Selector
```

```text
$ cabal test seihou-cli-test --test-options '--pattern AgentCompletion'
All 7 tests passed (0.01s)
Test suite seihou-cli-test: PASS
```


## Validation and Acceptance

Acceptance for this plan is internal but observable. `cabal build seihou-cli-internal` succeeds with the Baikai imports. `cabal test seihou-cli-test --test-options '--pattern AgentCompletion'` passes. In GHCi or a tiny test, `providerFromText "claude-cli"` returns `Right AgentProviderClaudeCli`, `providerFromText "codex-cli"` returns `Right AgentProviderCodexCli`, and unknown provider text returns a useful error containing the accepted provider names.

Do not require live `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `claude`, or `codex` for this plan's automated tests. Live calls belong in later manual validation because they depend on developer-machine credentials and installed CLI binaries.


## Idempotence and Recovery

The dependency and new module edits are repeatable. If dependency resolution fails because Baikai's `base >=4.20` bound conflicts with Seihou's compiler, stop and record the exact Cabal error in this plan's Surprises & Discoveries before changing package bounds. Do not vendor Baikai code into Seihou.


## Interfaces and Dependencies

Use the local dependency discovered by Mori: `mori://shinzui/baikai/packages/baikai`, `mori://shinzui/baikai/packages/baikai-claude`, and `mori://shinzui/baikai/packages/baikai-openai`. The Seihou-facing module at `seihou-cli/src/Seihou/CLI/AgentCompletion.hs` owns provider parsing, model construction, provider registration, and one-shot completion.

Later plans depend on these exported functions:

```haskell
defaultAgentModelConfig :: AgentModelConfig
providerFromText :: Text -> Either Text AgentProvider
providerToText :: AgentProvider -> Text
buildBaikaiModel :: AgentModelConfig -> Baikai.Model
runAgentCompletion :: AgentCompletionRequest -> IO (Either Text Text)
```

Returning `Either Text Text` from `runAgentCompletion` keeps executable handlers in control of user-facing error output and exit behavior. If implementation prefers exceptions for Baikai errors, wrap them inside this facade so callers still receive `Either`.

Revision note 2026-05-23: Implemented the Baikai dependency and `Seihou.CLI.AgentCompletion` facade, added focused tests, recorded dependency path and selector-ambiguity discoveries, and captured validation output.
