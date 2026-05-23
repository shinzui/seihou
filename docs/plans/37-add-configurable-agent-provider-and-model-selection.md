---
id: 37
slug: add-configurable-agent-provider-and-model-selection
title: "Add configurable agent provider and model selection"
kind: exec-plan
created_at: 2026-05-23T22:53:01Z
intention: "intention_01ksbgksmgeaesf6sft8prdvyn"
master_plan: "docs/masterplans/4-baikai-backed-configurable-agent-assistance.md"
---

# Add configurable agent provider and model selection

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, users can choose which AI provider and model Seihou agent commands use. They can set defaults in existing Seihou config files, override them with environment variables, or pass command-line flags on `seihou agent`. Existing users who do nothing continue to get a Claude CLI-backed default through Baikai's `claude -p` provider.

The visible outcome is that `seihou agent --provider codex-cli --model gpt-5 setup "..."` and `seihou agent --provider claude-cli --model sonnet assist "..."` parse cleanly, resolve to an `AgentModelConfig`, and feed the same config into all agent subcommands.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] Add provider/model fields to `AgentOpts` and the `seihou agent` parser.
- [ ] Define config key names and precedence for agent provider/model lookup.
- [ ] Implement pure resolution logic that merges CLI flags, environment variables, Seihou config, and defaults.
- [ ] Add parser and resolver tests.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Put `--provider` and `--model` on the parent `seihou agent` command rather than duplicating them on every subcommand.
  Rationale: `seihou agent --debug` is already a parent option in `seihou-cli/src-exe/Seihou/CLI/Commands.hs`; provider and model are cross-cutting launch settings with the same scope.
  Date: 2026-05-23

- Decision: Use config keys `agent.provider` and `agent.model`.
  Rationale: Existing config is a flat Dhall record of text values. These keys are explicit, do not collide with module variables, and can be managed through the existing `seihou config set/get/list` command.
  Date: 2026-05-23


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This plan depends on [36-add-baikai-dependency-and-agent-completion-facade.md](/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/docs/plans/36-add-baikai-dependency-and-agent-completion-facade.md). That plan creates `Seihou.CLI.AgentCompletion.AgentModelConfig` and provider parsing helpers.

The command-line parser is in `seihou-cli/src-exe/Seihou/CLI/Commands.hs`. It defines:

```haskell
data AgentOpts = AgentOpts
  { agentDebug :: Bool,
    agentCommand :: AgentCommand
  }
```

`agentParser` currently parses only `--debug` before `agentCommandParser`. The child subcommands are `assist`, `bootstrap`, `setup`, and `run`.

Seihou config files are flat Dhall records read through `seihou-core/src/Seihou/Effect/ConfigReader.hs` and `seihou-core/src/Seihou/Effect/ConfigReaderInterp.hs`. The existing config command in `seihou-cli/src-exe/Seihou/CLI/Config.hs` can write any key/value pair, so this plan does not need a new config subcommand. `docs/user/config-and-variables.md` documents precedence for module variables, but agent provider/model resolution should be narrower and explicit: CLI flag, environment variable, local config, global config, built-in default. Namespace and context config can be added later if there is a concrete use case.


## Plan of Work

Milestone 1 extends the CLI parser. In `seihou-cli/src-exe/Seihou/CLI/Commands.hs`, add `agentProvider :: Maybe Text` and `agentModel :: Maybe Text` to `AgentOpts`. Add `--provider PROVIDER` and `--model MODEL` options in `agentParser`. Help text must list the accepted provider values from plan 36: `claude-cli`, `codex-cli`, `anthropic`, and `openai`. Keep `--debug` behavior unchanged.

Milestone 2 adds config resolution in the library. Create `seihou-cli/src/Seihou/CLI/AgentConfig.hs` and expose it from `seihou-cli/seihou-cli.cabal`. Define:

```haskell
data AgentConfigInputs = AgentConfigInputs
  { cliProvider :: Maybe Text,
    cliModel :: Maybe Text,
    envProvider :: Maybe Text,
    envModel :: Maybe Text,
    localConfig :: Map Text Text,
    globalConfig :: Map Text Text
  }

resolveAgentModelConfig :: AgentConfigInputs -> Either Text AgentModelConfig
```

Use keys `agent.provider` and `agent.model` in config maps and environment variables `SEIHOU_AGENT_PROVIDER` and `SEIHOU_AGENT_MODEL`. The built-in default is `provider = claude-cli` and `model = Nothing`, which lets `claude -p` select its default model.

Milestone 3 adds an IO helper, probably `loadAgentModelConfig :: Maybe Text -> Maybe Text -> IO (Either Text AgentModelConfig)`, that reads local and global config with `runConfigReader`, reads the two environment variables, and calls the pure resolver. Keep this helper in `AgentConfig.hs` so the command handlers can share it.

Milestone 4 adds tests in `seihou-cli/test/Seihou/CLI/AgentConfigSpec.hs`. Cover CLI-over-env, env-over-local, local-over-global, default fallback, invalid provider diagnostics, and model-only override. Add the test module to `seihou-cli/seihou-cli.cabal` and `seihou-cli/test/Main.hs`.


## Concrete Steps

Run these commands from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`:

```bash
cabal test seihou-cli-test --test-options '--pattern AgentConfig'
cabal run seihou -- agent --help
cabal run seihou -- agent --provider codex-cli --model gpt-5 --debug assist "say hello"
```

The final command may not produce the final Baikai call until plan 38 is complete, but after this plan the parser must accept the flags and no longer report an unknown option.


## Validation and Acceptance

The parser is accepted when `cabal run seihou -- agent --help` documents `--provider` and `--model`, and `cabal run seihou -- agent --provider codex-cli --model gpt-5 --debug assist "say hello"` reaches the command handler instead of failing option parsing.

The resolver is accepted when the focused `AgentConfig` tests pass and demonstrate this precedence:

```text
CLI flags > SEIHOU_AGENT_* env vars > local .seihou/config.dhall > global ~/.config/seihou/config.dhall > claude-cli default
```


## Idempotence and Recovery

Parser and resolver edits are repeatable. If the test command mutates user config by accident, that is a bug in this plan: automated tests must use pure maps or temporary directories, not the real `~/.config/seihou/config.dhall`.


## Interfaces and Dependencies

This plan consumes `Seihou.CLI.AgentCompletion.AgentModelConfig` from plan 36. It touches `seihou-cli/src-exe/Seihou/CLI/Commands.hs`, creates `seihou-cli/src/Seihou/CLI/AgentConfig.hs`, and adds `seihou-cli/test/Seihou/CLI/AgentConfigSpec.hs`.

At the end of this plan, later handlers can call:

```haskell
loadAgentModelConfig :: Maybe Text -> Maybe Text -> IO (Either Text AgentModelConfig)
resolveAgentModelConfig :: AgentConfigInputs -> Either Text AgentModelConfig
```
