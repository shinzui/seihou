---
id: 4
slug: baikai-backed-configurable-agent-assistance
title: "Baikai-backed configurable agent assistance"
kind: master-plan
created_at: 2026-05-23T22:52:51Z
intention: "intention_01ksbgksmgeaesf6sft8prdvyn"
---

# Baikai-backed configurable agent assistance

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Vision & Scope

After this initiative, Seihou's `seihou agent` commands use the Baikai provider abstraction for AI completions instead of hard-coding a direct Claude process launch. Users can choose a provider and model with parent command flags, environment variables, or existing Seihou config files. The supported provider set includes Baikai's API providers for Anthropic and OpenAI-compatible hosts plus Baikai's CLI providers for `claude -p` and the Codex equivalent, `codex exec`.

The included commands are `seihou agent assist`, `seihou agent bootstrap`, `seihou agent setup`, and `seihou agent run`. The initiative includes build dependency integration, provider/model resolution, command migration, documentation, and validation. It explicitly excludes implementing tool-calling parity for Baikai CLI providers because the Baikai docs state those providers are batch text providers and do not expose tool calls.


## Decomposition Strategy

The work is decomposed by functional concern. First, Seihou needs a stable internal facade over Baikai so the rest of the codebase does not import provider packages directly. Second, users need a configuration surface for provider and model selection. Third, the existing agent subcommands need to consume those two pieces and stop calling the raw Claude launcher. Fourth, docs and full validation need to make the changed semantics explicit.

This avoids one large plan that touches dependencies, parsing, launch behavior, blueprint bookkeeping, docs, and tests at once. The first two plans can be verified mostly with pure tests and compilation. The migration plan depends on both because it needs both a completion facade and a resolved model config. The documentation plan comes last so it documents the actual implemented behavior.

An alternative was to keep the existing interactive Claude Code launch path and add Baikai only for Codex or API providers. That was rejected for the main path because the user asked for the agent assist commands to use Baikai. The plans still call out the behavior change: Baikai's `claude-cli` provider is `claude -p`, not the prior interactive Claude Code session with `--allowedTools`.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| EP-1 | Add Baikai dependency and agent completion facade | docs/plans/36-add-baikai-dependency-and-agent-completion-facade.md | None | None | Complete |
| EP-2 | Add configurable agent provider and model selection | docs/plans/37-add-configurable-agent-provider-and-model-selection.md | EP-1 | None | Complete |
| EP-3 | Migrate agent commands to Baikai launcher | docs/plans/38-migrate-agent-commands-to-baikai-launcher.md | EP-1, EP-2 | None | Complete |
| EP-4 | Document and validate configurable Baikai agents | docs/plans/39-document-and-validate-configurable-baikai-agents.md | EP-3 | None | Complete |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-1, EP-3).


## Dependency Graph

EP-1 must run first because it creates the shared `Seihou.CLI.AgentCompletion` facade and integrates the Baikai packages into the Cabal build. EP-2 depends on EP-1 because it resolves provider text into the `AgentProvider` and `AgentModelConfig` types defined by that facade.

EP-3 depends on EP-1 and EP-2. The command handlers cannot migrate until there is a completion function to call and a resolved model configuration to pass into it. EP-4 depends on EP-3 because user documentation and architecture notes need to describe the final command behavior, including the fact that non-debug commands produce a batch assistant response instead of opening an interactive Claude Code session.

No plans are intentionally parallel at the start. After EP-1 is complete, EP-2 is the next hard dependency. Documentation drafting for EP-4 can begin informally during EP-3, but it should not be committed as complete until the migrated command behavior is verified.


## Integration Points

`Seihou.CLI.AgentCompletion` is shared by EP-1, EP-2, and EP-3. EP-1 defines the module, provider enum, model config record, provider parsing helpers, Baikai model construction, provider registration, and one-shot completion function. EP-2 consumes the provider enum and model config record from its resolver. EP-3 consumes `runAgentCompletion`.

`Seihou.CLI.AgentConfig` is shared by EP-2 and EP-3. EP-2 defines config keys, environment variables, precedence, and IO loading. EP-3 calls it from command dispatch before invoking each handler.

`seihou-cli/src-exe/Seihou/CLI/Commands.hs` is shared by EP-2 and EP-3. EP-2 adds parent `seihou agent` flags and fields to `AgentOpts`; EP-3 reads those fields during dispatch and threads the resolved config into handlers.

The agent prompt rendering modules are shared by EP-1, EP-3, and EP-4. `seihou-cli/src/Seihou/CLI/AgentLaunch.hs` remains the home of context gathering and pure prompt formatting. EP-3 removes raw launching from the command path but should not remove the prompt helpers. EP-4 updates architecture docs to explain this split.

Documentation files `docs/cli/agent.md`, `docs/user/config-and-variables.md`, `docs/dev/architecture/overview.md`, and `docs/user/CHANGELOG.md` are owned by EP-4 after code behavior is final.


## Progress

- [x] EP-1: Add Baikai packages to the local build inputs.
- [x] EP-1: Create `Seihou.CLI.AgentCompletion` with provider registration, model construction, request execution, and response text extraction.
- [x] EP-1: Add focused tests for pure completion facade helpers.
- [x] EP-2: Add parent `seihou agent --provider` and `--model` parser fields.
- [x] EP-2: Implement provider/model resolution from CLI flags, environment variables, local config, global config, and defaults.
- [x] EP-2: Add parser smoke validation and resolver tests.
- [x] EP-3: Thread resolved `AgentModelConfig` through agent command dispatch and handlers.
- [x] EP-3: Replace raw Claude launcher calls in assist, bootstrap, setup, and blueprint runner.
- [x] EP-3: Preserve debug behavior and successful blueprint bookkeeping semantics.
- [x] EP-4: Update user command and configuration documentation.
- [x] EP-4: Update architecture docs, changelog, parser help text, and embedded agent prompt templates.
- [x] EP-4: Run full build, tests, and debug-mode command smoke checks.


## Surprises & Discoveries

Baikai's CLI providers are not drop-in replacements for the current interactive Claude Code launch. Evidence from `/Users/shinzui/Keikaku/bokuno/baikai/docs/user/cli-providers.md`: `claude-cli` drives `claude -p`, `codex-cli` drives `codex exec`, streaming is synthetic, usage is zeroed, and tool calling is not supported. EP-3 and EP-4 must make this batch behavior explicit.

The MasterPlan child init step was initially run in parallel and produced duplicate `36-` plan prefixes because the init script scans the directory without locking. The newly created files were renumbered immediately to `36` through `39`; future plan creation in this repository should run init scripts sequentially.

EP-1 uses local Baikai package paths in `cabal.project`: `../../baikai/baikai`, `../../baikai/baikai-claude`, and `../../baikai/baikai-openai`. The relative path is from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`; the initially assumed `../baikai/...` path does not exist.

Baikai re-exports duplicate record selectors named `api` and `provider` from both `Model` and `Response`. Later plans that inspect Baikai records directly should import narrower modules such as `Baikai.Model` or avoid direct Baikai selectors from command code.

`Seihou.CLI.Commands` still belongs to the executable target, not the `seihou-cli-internal` library that `seihou-cli-test` imports. EP-2 therefore validated parent parser behavior with `cabal run seihou -- agent --help` and `cabal run seihou -- agent --provider codex-cli --model gpt-5 --debug assist "say hello"` rather than adding a direct parser unit test.

EP-3 removed `Seihou.CLI.AgentLaunchExec` from the executable target after migration. A handler-scoped ripgrep check found no `launchAgentWith`, `AgentLaunchExec`, `rawSystem "claude"`, or `findExecutable "claude"` references in the active agent launch modules. `Seihou.CLI.CommitMessage` still has its own Claude-based commit-message helper and is outside the `seihou agent` command migration.

EP-3 preserves `agent run --debug` as a successful dry launch for applied-blueprint bookkeeping. The old launcher returned `ExitSuccess` after printing a debug prompt, so the migrated runner records provenance after successful debug prompt printing as well as after successful Baikai provider completion.

EP-4 found that the embedded prompt templates were part of the user-visible debug surface and still told providers they could use repository tools or launch Claude Code. Those templates were updated to describe batch Baikai responses and local commands for the user to run. This affects future prompt work: prompt text must be validated against provider capabilities, not only Markdown docs.

EP-4 also found that `seihou agent run` discovers blueprints from `.seihou/modules`, user modules, and installed modules, not from the current directory itself. The blueprint debug smoke check therefore used a temporary project with the sample blueprint copied under `.seihou/modules/sample-blueprint`.


## Decision Log

- Decision: Use four child plans: facade, configuration, command migration, and documentation/validation.
  Rationale: These are separate functional concerns with clear hard dependencies and independently verifiable outcomes.
  Date: 2026-05-23

- Decision: Default to Baikai's Claude CLI provider with no explicit model when users do not configure anything.
  Rationale: This preserves the closest available Claude-backed behavior while routing through Baikai. Leaving the model empty lets `claude -p` choose its own default, matching the existing command's lack of a model flag.
  Date: 2026-05-23

- Decision: Model the CLI providers as batch completion providers, not interactive agents.
  Rationale: The Baikai source and docs show the Claude CLI provider shells out to `claude -p --output-format json --no-session-persistence` and the OpenAI CLI provider shells out to `codex exec --json`; neither path supports Claude Code `--allowedTools` semantics.
  Date: 2026-05-23

- Decision: Put provider/model flags on the parent `seihou agent` parser.
  Rationale: Provider and model apply to all agent subcommands in the same way, just like the existing parent `--debug` flag.
  Date: 2026-05-23

- Decision: EP-1 exposes `AgentModelConfig` fields as `agentProvider` and `agentModel`.
  Rationale: These names avoid colliding with Baikai's own `provider` and `model` selectors while still carrying the provider/model concepts required by EP-2 and EP-3.
  Date: 2026-05-23

- Decision: Treat blank EP-2 provider/model inputs as absent when resolving agent configuration.
  Rationale: Blank CLI, environment, or config values should not mask useful lower-precedence values or produce an empty provider diagnostic.
  Date: 2026-05-23


## Outcomes & Retrospective

The Baikai-backed configurable agent assistance initiative is complete. Seihou now has a Baikai completion facade, provider/model resolution from flags, environment, local config, global config, and defaults, migrated agent command handlers, updated user/developer documentation, updated parser help text, and prompt templates aligned with batch provider semantics.

Validation completed on 2026-05-23 with `cabal build all`, `cabal test all`, `seihou agent --help`, debug smoke checks for `assist`, `bootstrap`, and `setup`, and a temporary-project debug smoke check for `agent run sample-blueprint`. Live non-debug provider calls were not run as part of EP-4; the documented acceptance treats missing local binaries or credentials as an environment limitation.
