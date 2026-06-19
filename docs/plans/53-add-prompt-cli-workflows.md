---
id: 53
slug: add-prompt-cli-workflows
title: "Add prompt CLI workflows"
kind: exec-plan
created_at: 2026-06-19T16:22:12Z
intention: "intention_01kvgax2mfezgsw4rrzsk012qc"
master_plan: "docs/masterplans/6-first-class-prompt-support.md"
---

# Add prompt CLI workflows

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, users can create, validate, render, and run first-class prompt artifacts from the CLI. The main workflow is `seihou prompt run NAME [PROMPT]`, which resolves typed variables from CLI/env/project/global config, fills command-derived variables, renders the prompt body, and starts an interactive Claude Code or Codex session through the existing Baikai launcher.

Users can also scaffold a prompt directory with `seihou new-prompt NAME` and validate one with `seihou validate-prompt PATH`.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] Add command parser types and help for `new-prompt`, `validate-prompt`, and `prompt run`.
- [ ] Add scaffold generation for a prompt directory.
- [ ] Add validate-prompt handler and renderer.
- [ ] Add prompt runner that resolves variables, runs command vars, renders prompt text, and launches Baikai interactive providers.
- [ ] Add CLI tests and debug-mode smoke coverage.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Use `seihou prompt run NAME` instead of `seihou agent prompt run NAME`.
  Rationale: Prompts are becoming a first-class user-facing artifact, not only a sub-mode of the existing agent-assistance commands. The runner still uses Baikai and agent config internally.
  Date: 2026-06-19

- Decision: `seihou prompt run --debug` should print the fully rendered prompt and skip provider launch.
  Rationale: Existing `seihou agent --debug` behavior is valuable for authoring, testing command-derived variables, and avoiding accidental live agent sessions.
  Date: 2026-06-19


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

CLI command parsing lives in `seihou-cli/src-exe/Seihou/CLI/Commands.hs`. `Main.hs` dispatches parsed commands to handlers in `seihou-cli/src-exe/Seihou/CLI/*`. Existing prompt-like command behavior is in `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`, which discovers a blueprint, resolves its variables by wrapping them in a placeholder `Module`, optionally applies baseline modules, renders a prompt, and launches the provider.

Baikai interactive launch is already wrapped by `seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs`. Agent provider/model configuration is resolved by `seihou-cli/src/Seihou/CLI/AgentConfig.hs` and `seihou-cli/src/Seihou/CLI/AgentCompletion.hs`. Prompt CLI code should reuse those modules rather than adding new provider flags with different semantics.

Scaffolding helpers live in `seihou-core/src/Seihou/Core/Scaffold.hs`; `seihou-cli/src-exe/Seihou/CLI/NewBlueprint.hs` is the closest pattern for creating a directory with a Dhall file, `prompt.md`, and `files/`.


## Plan of Work

Milestone 1 adds command grammar. Extend `Command` and parser definitions in `Seihou.CLI.Commands` with `NewPrompt`, `ValidatePrompt`, and a parent `Prompt` command containing a `PromptRun` subcommand. Prompt run options should include `NAME`, optional initial user prompt, repeated `--var KEY=VALUE`, optional `--namespace`, optional `--context`, `--provider`, `--model`, `--debug`, and `--verbose`. Keep provider/model override behavior consistent with `seihou agent` subcommands.

Milestone 2 adds scaffolding and validation handlers. Add `Seihou.CLI.NewPrompt` using new `promptDhall` and example prompt helpers from `Seihou.Core.Scaffold`. Add `Seihou.CLI.ValidatePrompt` mirroring `ValidateBlueprint` but using `Seihou.Core.AgentPrompt` checks. Wire both handlers in `Main.hs` and cabal modules.

Milestone 3 adds the prompt runner. Add `Seihou.CLI.PromptRun` or similar. It should discover `RunnableAgentPrompt`, reject modules/recipes/blueprints with actionable messages, resolve declared variables using the same config precedence as blueprint runner, call EP-52's command-var resolver, substitute `{{var}}` placeholders into the prompt body, wrap it in a small system prompt if needed, and launch the configured provider. Unlike `AgentRun`, it must not apply `baseModules` and must not record applied-blueprint provenance.

Milestone 4 tests and smoke checks. Add pure tests for option parsing where this project already has CLI parser tests. Add handler-level tests around render helpers where possible. Add a debug smoke fixture so `seihou prompt --debug run review-changes` or the final chosen syntax prints the rendered prompt without requiring `claude` or `codex` on `PATH`.


## Concrete Steps

Run these commands from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`:

```bash
rg -n "AgentRun|NewBlueprint|ValidateBlueprint|agentParser|resolveAgentModelConfig|launchConfiguredAgent" seihou-cli/src seihou-cli/src-exe seihou-cli/test
cabal build seihou
cabal test seihou-cli-test --test-options '--pattern Prompt'
```

If the focused pattern is unsupported, run:

```bash
cabal test seihou-cli-test
```

Manual smoke after implementation:

```bash
cabal run seihou -- new-prompt review-changes --path /tmp/review-changes
cabal run seihou -- validate-prompt /tmp/review-changes
cabal run seihou -- prompt --debug run review-changes --var project.name=demo
```

Adjust the exact debug syntax if the parser lands on `seihou prompt run --debug`; the implemented help and tests must agree.


## Validation and Acceptance

Acceptance is met when a user can scaffold a prompt, validate it, and render it in debug mode without contacting a provider. The debug output must include substituted config/CLI variables and command-derived variables. A non-debug run with `--provider codex-cli` or `--provider claude-cli` should attempt the existing Baikai interactive launch path. API providers may either be rejected for interactive prompt sessions or supported as one-shot completions, but the behavior must be explicit in help and tests.


## Idempotence and Recovery

`new-prompt` must refuse to overwrite an existing directory, matching `new-blueprint`. Debug runs are safe and should not write `.seihou/manifest.json`. Live provider runs may edit the working tree because Claude Code or Codex is interactive; make that clear in help text.


## Interfaces and Dependencies

This plan depends hard on EP-51 and EP-52. It uses existing Baikai wrappers through:

```haskell
Seihou.CLI.AgentConfig.loadAgentModelConfig
Seihou.CLI.AgentLaunchExec.launchConfiguredAgent
Seihou.CLI.AgentCompletion.AgentModelConfig
```

New handler interfaces should be similar to:

```haskell
handleNewPrompt :: NewPromptOpts -> IO ()
handleValidatePrompt :: ValidatePromptOpts -> IO ()
handlePromptRun :: Bool -> AgentModelConfig -> PromptRunOpts -> IO ()
```
