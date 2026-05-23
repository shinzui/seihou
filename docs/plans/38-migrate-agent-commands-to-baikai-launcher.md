---
id: 38
slug: migrate-agent-commands-to-baikai-launcher
title: "Migrate agent commands to Baikai launcher"
kind: exec-plan
created_at: 2026-05-23T22:53:01Z
intention: "intention_01ksbgksmgeaesf6sft8prdvyn"
master_plan: "docs/masterplans/4-baikai-backed-configurable-agent-assistance.md"
---

# Migrate agent commands to Baikai launcher

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, the existing `seihou agent assist`, `seihou agent bootstrap`, `seihou agent setup`, and `seihou agent run` commands send their rendered system prompt and initial user prompt through the Baikai completion facade instead of directly shelling out to the interactive Claude Code launcher. The same command can target `claude -p`, `codex exec`, Anthropic API, or OpenAI API depending on the resolved provider and model.

The user-visible behavior is that `seihou agent --provider claude-cli assist "..."` still uses a Claude CLI backend, while `seihou agent --provider codex-cli assist "..."` uses Codex's non-interactive CLI backend through Baikai. `--debug` continues to print the resolved prompt without contacting a provider.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] Thread resolved `AgentModelConfig` from `Main.hs`/command dispatch into all agent handlers.
- [ ] Replace `launchAgentWith` calls in assist/bootstrap/setup/blueprint runner with `runAgentCompletion`.
- [ ] Preserve debug output and non-zero error behavior.
- [ ] Add tests for prompt rendering and handler-level launch request construction where possible.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Migrate all four `seihou agent` subcommands together.
  Rationale: They share `AgentOpts`, prompt rendering helpers, and the same launch path; leaving one command on raw Claude Code would make provider/model configuration misleading.
  Date: 2026-05-23

- Decision: Keep the legacy allowed-tools lists in prompt text or remove them from the Baikai call path rather than trying to pass them as Baikai tools.
  Rationale: Baikai's CLI providers explicitly ignore tool calling. The current `defaultAllowedTools`, `bootstrapAllowedTools`, and `setupAllowedTools` are Claude Code-specific launch flags, not portable Baikai tools.
  Date: 2026-05-23


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This plan depends on [36-add-baikai-dependency-and-agent-completion-facade.md](/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/docs/plans/36-add-baikai-dependency-and-agent-completion-facade.md) and [37-add-configurable-agent-provider-and-model-selection.md](/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/docs/plans/37-add-configurable-agent-provider-and-model-selection.md). Plan 36 creates `runAgentCompletion`; plan 37 adds provider/model fields to `AgentOpts` and a resolver that returns `AgentModelConfig`.

The current handlers are executable-side modules:

`seihou-cli/src-exe/Seihou/CLI/Assist.hs` gathers `AgentContext`, renders `data/assist-prompt.md`, calls `agentDirsForSession`, and invokes `launchAgentWith addDirs defaultAllowedTools debug systemPrompt assistOpts.assistPrompt`.

`seihou-cli/src-exe/Seihou/CLI/Bootstrap.hs` renders `data/bootstrap-prompt.md` and uses `bootstrapAllowedTools`.

`seihou-cli/src-exe/Seihou/CLI/Setup.hs` renders `data/setup-prompt.md` and uses `setupAllowedTools`.

`seihou-cli/src-exe/Seihou/CLI/AgentRun.hs` resolves an agent-driven blueprint, optionally applies baseline modules, renders `data/blueprint-prompt.md`, calls `launchAgentWith`, and records the applied blueprint only after a clean agent exit.

`seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs` is the raw process launcher. After this plan it should either be deleted if no longer referenced, or left unused only if another checked-in plan still needs it.


## Plan of Work

Milestone 1 updates command dispatch. In `seihou-cli/src-exe/Main.hs`, when handling `Agent AgentOpts`, call `loadAgentModelConfig agentProvider agentModel` from plan 37 before dispatching to the selected subcommand. On `Left err`, print `Error: ` plus the message and exit failure. On success, pass `AgentModelConfig` into the handler. This requires changing handler signatures to include the config:

```haskell
handleAssist :: Bool -> AgentModelConfig -> AssistOpts -> IO ()
handleBootstrap :: Bool -> AgentModelConfig -> BootstrapOpts -> IO ()
handleSetup :: Bool -> AgentModelConfig -> SetupOpts -> IO ()
handleAgentRun :: Bool -> AgentModelConfig -> BlueprintRunOpts -> IO ()
```

Milestone 2 migrates `Assist`, `Bootstrap`, and `Setup`. In each handler, keep prompt rendering unchanged. If `debug` is true, print the rendered system prompt and return success without calling Baikai, matching current behavior. Otherwise call `runAgentCompletion AgentCompletionRequest { systemPrompt, initialPrompt, modelConfig }`. On success, print the assistant text to stdout. On failure, print the error and exit failure.

Milestone 3 migrates `AgentRun`. Keep blueprint discovery, variable resolution, baseline application, and prompt rendering unchanged. Replace the `launchAgentWith` call with the same `runAgentCompletion` path. Preserve the existing manifest behavior: record the `AppliedBlueprint` entry only after a successful Baikai completion. Treat `Right _` as success and `Left _` as failure.

Milestone 4 cleans up obsolete raw-launch code. Remove imports of `Seihou.CLI.AgentLaunchExec` from handlers. If `Seihou.CLI.AgentLaunchExec` has no references, remove it from `seihou-cli/seihou-cli.cabal` and delete the file. Keep `Seihou.CLI.AgentLaunch` because its context gathering and prompt formatters are still used.

Milestone 5 updates tests where feasible. Existing `AgentLaunchSpec` tests remain valid for pure prompt helpers. Add pure tests around any new helper that converts rendered prompts plus initial prompt into an `AgentCompletionRequest`. Avoid live Baikai calls in automated tests.


## Concrete Steps

Run these commands from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`:

```bash
rg -n "launchAgentWith|AgentLaunchExec|rawSystem \"claude\"|findExecutable \"claude\"" seihou-cli
cabal build seihou
cabal test seihou-cli-test
cabal run seihou -- agent --debug --provider codex-cli assist "show me the prompt"
```

After migration, the `rg` command should have no references from active agent handlers to `launchAgentWith` or `AgentLaunchExec`. The debug command should print the resolved prompt and should not require `codex` on `PATH`.


## Validation and Acceptance

Acceptance is met when `cabal build seihou` and `cabal test seihou-cli-test` succeed, `seihou agent --debug --provider claude-cli assist "x"` prints the system prompt without invoking any provider, and a non-debug call uses the configured provider through `runAgentCompletion`.

Manual live validation is optional for implementation but useful when credentials are present:

```bash
seihou agent --provider claude-cli --model sonnet assist "Reply with one sentence about Seihou."
seihou agent --provider codex-cli assist "Reply with one sentence about Seihou."
```

The expected output is a plain assistant response on stdout. These commands are not expected to open an interactive tool-using Claude Code session after this migration.


## Idempotence and Recovery

The migration is repeatable because prompt rendering remains pure and Baikai calls happen only after all context gathering completes. For `agent run`, if baseline application succeeds but Baikai completion fails, preserve the existing behavior for non-zero agent exits: do not record a successful applied-blueprint entry.


## Interfaces and Dependencies

This plan consumes `Seihou.CLI.AgentCompletion` and `Seihou.CLI.AgentConfig`. It edits `seihou-cli/src-exe/Main.hs`, `seihou-cli/src-exe/Seihou/CLI/Assist.hs`, `seihou-cli/src-exe/Seihou/CLI/Bootstrap.hs`, `seihou-cli/src-exe/Seihou/CLI/Setup.hs`, and `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`.

At completion, no handler should depend on `Seihou.CLI.AgentLaunchExec`. The portable launch interface is:

```haskell
runAgentCompletion :: AgentCompletionRequest -> IO (Either Text Text)
```
