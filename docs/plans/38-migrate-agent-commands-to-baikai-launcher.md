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

After this change and its 2026-05-24 correction, the existing `seihou agent assist`, `seihou agent bootstrap`, `seihou agent setup`, and `seihou agent run` commands use resolved provider/model configuration for every launch. API providers send their rendered system prompt and initial user prompt through the Baikai completion facade. CLI providers launch interactive local `claude` or `codex` sessions directly.

The user-visible behavior is that `seihou agent --provider claude-cli assist "..."` starts Claude Code, while `seihou agent assist --provider codex-cli "..."` starts Codex. `--debug` continues to print the resolved prompt without contacting a provider.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] 2026-05-23: Threaded resolved `AgentModelConfig` from `Main.hs` command dispatch into all agent handlers.
- [x] 2026-05-23: Replaced `launchAgentWith` calls in assist, bootstrap, setup, and blueprint runner with `runAgentCompletion`.
- [x] 2026-05-23: Preserved debug output, provider error handling, provider failure exits, and successful blueprint bookkeeping semantics.
- [x] 2026-05-23: Added a pure `buildAgentCompletionRequest` helper and test coverage for rendered prompt plus resolved model request construction.
- [x] 2026-05-23: Removed the obsolete `Seihou.CLI.AgentLaunchExec` module from the executable target after confirming no active agent handler references it.
- [x] 2026-05-23: Validated with `cabal build seihou`, `cabal test seihou-cli-test`, and `cabal run seihou -- agent --debug --provider codex-cli assist "show me the prompt"`.
- [x] 2026-05-24: Corrective update restored direct interactive launch for `claude-cli` and `codex-cli`, added subcommand-local provider/model flags, and linked `seihou` with `-threaded`.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- Discovery: `AgentRun` debug mode previously treated prompt printing as a successful launch because `launchAgentWith` returned `ExitSuccess` in debug mode. The migration preserves that by recording blueprint provenance after successful debug prompt printing as well as after successful Baikai completion.
  Evidence: the old `Seihou.CLI.AgentLaunchExec.launchAgentWith` returned `ExitSuccess` in debug mode and `AgentRun` recorded only on `ExitSuccess`.
  Date: 2026-05-23

- Discovery: After deleting `Seihou.CLI.AgentLaunchExec`, the active executable agent modules have no raw Claude launcher references.
  Evidence:

```text
$ rg -n "launchAgentWith|AgentLaunchExec|rawSystem \"claude\"|findExecutable \"claude\"" seihou-cli/src-exe seihou-cli/src/Seihou/CLI/AgentLaunch.hs seihou-cli/src/Seihou/CLI/AgentCompletion.hs
```

  The command exited with status 1 and no matches, which is ripgrep's normal result for no matches.
  Date: 2026-05-23

- Discovery: Baikai's CLI providers are the wrong abstraction for interactive `seihou agent` sessions.
  Evidence: Baikai's local docs and source show `claude-cli` drives `claude -p` and `codex-cli` drives `codex exec`, both as batch providers. A live `seihou agent assist --provider codex-cli` smoke check reached Codex and failed with `stdin is not a terminal` in the non-TTY test harness after the direct-launch fix, proving Seihou now starts the interactive CLI.
  Date: 2026-05-24


## Decision Log

Record every decision made while working on the plan.

- Decision: Migrate all four `seihou agent` subcommands together.
  Rationale: They share `AgentOpts`, prompt rendering helpers, and the same launch path; leaving one command on raw Claude Code would make provider/model configuration misleading.
  Date: 2026-05-23

- Decision: Keep the legacy allowed-tools lists in prompt text or remove them from the Baikai call path rather than trying to pass them as Baikai tools.
  Rationale: Baikai's CLI providers explicitly ignore tool calling. The current `defaultAllowedTools`, `bootstrapAllowedTools`, and `setupAllowedTools` are Claude Code-specific launch flags, not portable Baikai tools.
  Date: 2026-05-23

- Decision: Preserve `agent run --debug` as a successful dry-launch for blueprint bookkeeping.
  Rationale: The previous launcher returned `ExitSuccess` after printing the debug prompt, and `AgentRun` recorded applied-blueprint provenance after `ExitSuccess`. Keeping that behavior avoids a hidden semantic change while still preventing provider calls in debug mode.
  Date: 2026-05-23

- Decision: Directly launch `claude` and `codex` for CLI providers.
  Rationale: Users expect `seihou agent assist --provider codex-cli` to open an interactive Codex session, not produce a one-shot `codex exec` response.
  Date: 2026-05-24


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

Completed on 2026-05-23 and corrected on 2026-05-24. `seihou agent` dispatch now resolves provider/model configuration, threads `AgentModelConfig` into assist, bootstrap, setup, and blueprint run handlers, sends API-provider prompts through the Baikai completion facade, and launches CLI providers interactively through `Seihou.CLI.AgentLaunchExec`. Debug mode still prints the rendered prompt without contacting a provider.

Validation passed:

```text
cabal build seihou
cabal test seihou-cli-test
cabal run seihou -- agent --debug --provider codex-cli assist "show me the prompt"
```

The test suite reported `All 221 tests passed`, and the debug smoke command exited 0 after printing the rendered assist prompt.


## Context and Orientation

This plan depends on [36-add-baikai-dependency-and-agent-completion-facade.md](/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/docs/plans/36-add-baikai-dependency-and-agent-completion-facade.md) and [37-add-configurable-agent-provider-and-model-selection.md](/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/docs/plans/37-add-configurable-agent-provider-and-model-selection.md). Plan 36 creates `runAgentCompletion`; plan 37 adds provider/model fields to `AgentOpts` and a resolver that returns `AgentModelConfig`.

The current handlers are executable-side modules:

`seihou-cli/src-exe/Seihou/CLI/Assist.hs` gathers `AgentContext`, renders `data/assist-prompt.md`, prints the prompt in debug mode, and otherwise calls `runAgentCompletion` with the resolved `AgentModelConfig`.

`seihou-cli/src-exe/Seihou/CLI/Bootstrap.hs` renders `data/bootstrap-prompt.md`, prints the prompt in debug mode, and otherwise calls `runAgentCompletion`.

`seihou-cli/src-exe/Seihou/CLI/Setup.hs` renders `data/setup-prompt.md`, prints the prompt in debug mode, and otherwise calls `runAgentCompletion`.

`seihou-cli/src-exe/Seihou/CLI/AgentRun.hs` resolves an agent-driven blueprint, optionally applies baseline modules, renders `data/blueprint-prompt.md`, calls `runAgentCompletion`, and records the applied blueprint only after successful debug prompt printing or successful provider completion.

`seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs` was the raw process launcher. It has been deleted because no active agent handler references it.


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

This plan consumes `Seihou.CLI.AgentCompletion`, `Seihou.CLI.AgentConfig`, and `Seihou.CLI.AgentLaunchExec`. It edits `seihou-cli/src-exe/Main.hs`, `seihou-cli/src-exe/Seihou/CLI/Assist.hs`, `seihou-cli/src-exe/Seihou/CLI/Bootstrap.hs`, `seihou-cli/src-exe/Seihou/CLI/Setup.hs`, and `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`.

At completion, API providers use the portable completion interface:

```haskell
runAgentCompletion :: AgentCompletionRequest -> IO (Either Text Text)
```

## Revision Note

2026-05-23: Implemented the plan, updated living sections with validation evidence and the debug-mode blueprint bookkeeping decision, and revised context prose to describe the migrated Baikai launch path.

2026-05-24: Corrected this plan after live use showed that Baikai CLI providers were batch subprocess adapters and did not satisfy `seihou agent`'s interactive-session requirement. The implemented behavior now splits API providers through Baikai from interactive local CLI providers through direct process launch.
