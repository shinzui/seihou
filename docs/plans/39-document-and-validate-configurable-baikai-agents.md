---
id: 39
slug: document-and-validate-configurable-baikai-agents
title: "Document and validate configurable Baikai agents"
kind: exec-plan
created_at: 2026-05-23T22:53:01Z
intention: "intention_01ksbgksmgeaesf6sft8prdvyn"
master_plan: "docs/masterplans/4-baikai-backed-configurable-agent-assistance.md"
---

# Document and validate configurable Baikai agents

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change and its 2026-05-24 correction, the configurable agent behavior is documented and validated at the user and developer levels. Users can discover accepted provider values, understand how `agent.provider` and `agent.model` are resolved, and see that `claude-cli` starts an interactive local Claude Code session while `codex-cli` starts an interactive local Codex session. API providers continue through Baikai.

This plan also updates architecture notes and command reference text so future contributors preserve the intended split: direct local process launches for interactive CLI providers, Baikai completions for API providers.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Update CLI reference docs for `seihou agent`. Completed 2026-05-23 and corrected 2026-05-24: `docs/cli/agent.md` now documents parent and subcommand provider/model flags, accepted providers, interactive CLI-provider behavior, API-provider batch behavior, `agent run`, and debug examples.
- [x] Update user config docs with `agent.provider` and `agent.model`. Completed 2026-05-23 and corrected 2026-05-24: `docs/user/config-and-variables.md` now explains config keys, environment variables, precedence, examples, and the split between interactive `claude-cli`/`codex-cli` and Baikai-backed API providers.
- [x] Update architecture docs and changelog entries. Completed 2026-05-23: `docs/dev/architecture/overview.md` now describes `AgentCompletion`, `AgentConfig`, and prompt formatting split; `docs/user/CHANGELOG.md` has the Baikai-backed agent entry.
- [x] Update embedded agent prompts for batch provider semantics. Completed 2026-05-23: `seihou-cli/data/assist-prompt.md`, `bootstrap-prompt.md`, `setup-prompt.md`, and `blueprint-prompt.md` no longer claim the provider can use repository tools or launch an interactive Claude Code session.
- [x] Run full build and test validation, plus debug-mode command smoke checks. Completed 2026-05-23: `cabal build all`, `cabal test all`, `seihou agent --help`, `agent --debug assist`, `agent --debug bootstrap`, `agent --debug setup`, and a temp-project `agent --debug run sample-blueprint` all succeeded.
- [x] 2026-05-24: Corrected docs, embedded prompts, and help text to describe interactive CLI providers, subcommand-local provider/model flags, and API-provider batch completions.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- 2026-05-23: Debug smoke checks showed that the embedded prompt templates still described interactive tool-using sessions even though Baikai CLI providers are batch text providers. Evidence: the first `seihou agent --debug --provider claude-cli assist debug` run printed "You have access to the seihou CLI, git, and file editing tools." and setup/bootstrap prompts mentioned launching Claude Code. The prompts were updated to describe batch responses and local commands for the user to run.
- 2026-05-23: `seihou agent run` discovery does not load a blueprint from the current directory itself; it searches `.seihou/modules`, user modules, and installed modules. Evidence: running from `seihou-core/test/fixtures/sample-blueprint` failed with "Module 'sample-blueprint' not found" and listed those search paths. The smoke check was rerun by copying the fixture under a temp project's `.seihou/modules/sample-blueprint`.
- 2026-05-24: The 2026-05-23 documentation over-corrected by promising batch CLI-provider behavior. Live usage showed users expected `seihou agent assist --provider codex-cli` to start Codex interactively, so the docs now distinguish interactive CLI providers from Baikai API providers.


## Decision Log

Record every decision made while working on the plan.

- Decision: Initially document the batch nature of Baikai CLI providers directly in `docs/cli/agent.md`. Superseded on 2026-05-24.
  Rationale: Existing docs promised interactive Claude Code sessions with tools. The first migration treated `claude-cli` and `codex-cli` as one-shot completion providers, so the docs were changed to prevent users from expecting the old terminal handoff. The 2026-05-24 correction restored interactive CLI providers and updated the docs again.
  Date: 2026-05-23

- Decision: Update embedded prompt templates as part of this documentation and validation plan.
  Rationale: `--debug` prints those prompts as user-visible behavior, and leaving them with tool/session claims would contradict the documented batch Baikai semantics even if the Markdown docs were correct.
  Date: 2026-05-23

- Decision: Document CLI providers as interactive local sessions and API providers as Baikai batch completions.
  Rationale: This matches the corrected implementation and prevents future contributors from reintroducing the `codex exec`/`claude -p` behavior for interactive agent commands.
  Date: 2026-05-24


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

Completed 2026-05-23 and corrected 2026-05-24. The CLI reference, configuration guide, architecture overview, changelog, parser help text, and embedded prompt templates now describe configurable agent execution. Provider selection is documented consistently across subcommand flags, parent flags, environment variables, local/global config, and defaults. CLI providers are documented as interactive local sessions; API providers are documented as Baikai batch completions. Validation passed with `cabal build all`, `cabal test all`, and debug smoke checks for assist, bootstrap, setup, and blueprint run during the original pass.


## Context and Orientation

This plan depends on [36-add-baikai-dependency-and-agent-completion-facade.md](/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/docs/plans/36-add-baikai-dependency-and-agent-completion-facade.md), [37-add-configurable-agent-provider-and-model-selection.md](/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/docs/plans/37-add-configurable-agent-provider-and-model-selection.md), and [38-migrate-agent-commands-to-baikai-launcher.md](/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/docs/plans/38-migrate-agent-commands-to-baikai-launcher.md).

Current command docs live in `docs/cli/agent.md`. They say each subcommand launches an interactive Claude session and requires the `claude` CLI. That becomes inaccurate once plan 38 is implemented.

Configuration docs live in `docs/user/config-and-variables.md` and `docs/cli/config.md`. They already explain that arbitrary keys can be written with `seihou config set KEY VALUE`; this plan adds agent-specific examples and precedence text.

Architecture notes live in `docs/dev/architecture/overview.md`. That file currently identifies `Seihou.CLI.AgentLaunchExec` as the Claude shell-out module and describes `AgentLaunch.hs` as a shared Claude Code launcher. Update those references to the Baikai facade and provider/model resolver.


## Plan of Work

Milestone 1 updates `docs/cli/agent.md`. Add parent and subcommand options `--provider PROVIDER` and `--model MODEL`, list accepted providers, and show examples for `claude-cli`, `codex-cli`, `anthropic`, and `openai`. The corrected documentation says CLI providers launch interactive local sessions and API providers send one-shot Baikai completions. Mention that `--debug` still prints the resolved system prompt without contacting the provider.

Milestone 2 updates config docs. In `docs/user/config-and-variables.md`, add an "Agent provider defaults" subsection explaining `agent.provider`, `agent.model`, `SEIHOU_AGENT_PROVIDER`, `SEIHOU_AGENT_MODEL`, and precedence. Include examples:

```bash
seihou config set agent.provider codex-cli --global
seihou config set agent.model gpt-5 --global
seihou agent assist "create a module"
seihou agent --provider claude-cli --model sonnet setup "add nix"
```

Milestone 3 updates developer docs and changelog. In `docs/dev/architecture/overview.md`, replace references to `AgentLaunchExec.hs` as the active launcher with `AgentCompletion.hs` and `AgentConfig.hs`. In `docs/user/CHANGELOG.md`, add a dated entry for configurable Baikai-backed agent commands.

Milestone 4 validates the full initiative. Run the full CLI test suite and at least one debug-mode command for every agent subcommand. Debug commands should not require provider binaries or API keys.


## Concrete Steps

Run these commands from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`:

```bash
cabal build all
cabal test all
cabal run seihou -- agent --help
cabal run seihou -- agent --debug --provider claude-cli assist "debug"
cabal run seihou -- agent --debug --provider codex-cli bootstrap --repo "debug"
cabal run seihou -- agent --debug --provider openai setup "debug"
```

The debug commands should print rendered prompts and exit successfully without contacting any AI provider.


## Validation and Acceptance

Acceptance is met when docs and help text agree on provider values, config keys, and precedence; `cabal build all` and `cabal test all` pass; and all listed debug smoke commands print prompt text without requiring `claude`, `codex`, or API keys.

When live provider tools and credentials are available, run one non-debug `claude-cli` and one non-debug `codex-cli` command to prove both Baikai CLI providers are wired. Record failures caused by missing binaries as environment limitations, not implementation failures.


## Idempotence and Recovery

Documentation edits are repeatable. Debug smoke checks are safe because they do not contact providers. Non-debug live checks may consume API quota for `anthropic` or `openai`; prefer `claude-cli` or `codex-cli` for local subscription-backed smoke tests when available.


## Interfaces and Dependencies

This plan edits `docs/cli/agent.md`, `docs/user/config-and-variables.md`, `docs/dev/architecture/overview.md`, and `docs/user/CHANGELOG.md`. It validates the interfaces created by the earlier plans: `Seihou.CLI.AgentCompletion` for API provider execution, `Seihou.CLI.AgentLaunchExec` for interactive local CLI provider execution, and `Seihou.CLI.AgentConfig` for provider/model resolution.

Revision note, 2026-05-23: Implementation expanded the documented file set to include `seihou-cli/data/assist-prompt.md`, `seihou-cli/data/bootstrap-prompt.md`, `seihou-cli/data/setup-prompt.md`, `seihou-cli/data/blueprint-prompt.md`, and parser help text in `seihou-cli/src-exe/Seihou/CLI/Commands.hs`. Debug validation showed those embedded prompts were user-visible and still described interactive tool-using sessions, so they were brought into scope to keep the completed behavior coherent.

Revision note, 2026-05-24: Corrected the documentation after the implementation restored interactive CLI provider launches. The plan now records that `claude-cli` and `codex-cli` are interactive local sessions, while `anthropic` and `openai` remain Baikai API completions.
