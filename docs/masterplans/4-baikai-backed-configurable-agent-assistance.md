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

After this initiative, Seihou's `seihou agent` commands support configurable providers instead of hard-coding only Claude. Users can choose a provider and model with parent command flags, subcommand flags, environment variables, or existing Seihou config files. The supported provider set includes interactive local CLI sessions for `claude-cli` and `codex-cli`, plus Baikai API providers for Anthropic and OpenAI-compatible hosts.

The included commands are `seihou agent assist`, `seihou agent bootstrap`, `seihou agent setup`, and `seihou agent run`. The initiative includes build dependency integration, provider/model resolution, command migration, documentation, and validation. Baikai remains the API completion facade; local CLI providers are launched directly because users expect an interactive Claude Code or Codex session.


## Decomposition Strategy

The work is decomposed by functional concern. First, Seihou needs a stable internal facade over Baikai so the rest of the codebase does not import provider packages directly. Second, users need a configuration surface for provider and model selection. Third, the existing agent subcommands need to consume those two pieces and stop calling the raw Claude launcher. Fourth, docs and full validation need to make the changed semantics explicit.

This avoids one large plan that touches dependencies, parsing, launch behavior, blueprint bookkeeping, docs, and tests at once. The first two plans can be verified mostly with pure tests and compilation. The migration plan depends on both because it needs both a completion facade and a resolved model config. The documentation plan comes last so it documents the actual implemented behavior.

The initial implementation attempted to use Baikai CLI providers for `claude-cli` and `codex-cli`, which made those providers batch completions. That was corrected on 2026-05-24 after live usage showed it was not acceptable for `seihou agent assist`: CLI providers must start interactive sessions, while API providers continue to use Baikai.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| EP-1 | Add Baikai dependency and agent completion facade | docs/plans/36-add-baikai-dependency-and-agent-completion-facade.md | None | None | Complete |
| EP-2 | Add configurable agent provider and model selection | docs/plans/37-add-configurable-agent-provider-and-model-selection.md | EP-1 | None | Complete |
| EP-3 | Migrate agent commands to Baikai launcher | docs/plans/38-migrate-agent-commands-to-baikai-launcher.md | EP-1, EP-2 | None | Complete |
| EP-4 | Document and validate configurable Baikai agents | docs/plans/39-document-and-validate-configurable-baikai-agents.md | EP-3 | None | Complete |
| EP-5 | Support Codex kit skills and agents | docs/plans/40-support-codex-kit-skills-and-agents.md | EP-3 | EP-4 | Complete |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-1, EP-3).


## Dependency Graph

EP-1 must run first because it creates the shared `Seihou.CLI.AgentCompletion` facade and integrates the Baikai packages into the Cabal build. EP-2 depends on EP-1 because it resolves provider text into the `AgentProvider` and `AgentModelConfig` types defined by that facade.

EP-3 depends on EP-1 and EP-2. The command handlers cannot migrate until there is a completion function to call and a resolved model configuration to pass into it. EP-4 depends on EP-3 because user documentation and architecture notes need to describe the final command behavior. After the 2026-05-24 correction, CLI providers are interactive local sessions and API providers are batch completions through Baikai.

EP-5 is a follow-up plan after the initial initiative was completed. It depends on EP-3 because it relies on the corrected interactive `codex-cli` launcher and the established interactive provider semantics. It has a soft dependency on EP-4 because its documentation changes align with the completed user and architecture documentation, but it was implemented independently of Baikai API provider behavior.

No plans are intentionally parallel at the start. After EP-1 is complete, EP-2 is the next hard dependency. Documentation drafting for EP-4 can begin informally during EP-3, but it should not be committed as complete until the migrated command behavior is verified.


## Integration Points

`Seihou.CLI.AgentCompletion` is shared by EP-1, EP-2, and EP-3. EP-1 defines the module, provider enum, model config record, provider parsing helpers, Baikai model construction, provider registration, and one-shot completion function. EP-2 consumes the provider enum and model config record from its resolver. EP-3 consumes `runAgentCompletion` for API providers.

`Seihou.CLI.AgentLaunchExec` is owned by the corrective update after EP-4. It launches `claude` and `codex` interactively for CLI providers, passing rendered prompts and model selection without going through Baikai's batch CLI providers.

`Seihou.CLI.Kit` is shared with EP-5. Before EP-5, kit install, update, uninstall, and status were Claude-layout-only: skills were copied below `.claude/skills` and agents below `.claude/agents`. EP-5 extended those lifecycle operations so installed kit content is visible to Codex interactive sessions under Codex-native layouts while preserving the existing Claude layout. The provider-specific layout helpers now live in the internal library module `Seihou.CLI.KitPaths`, which keeps the executable command handler focused on command flow and makes path behavior directly testable.

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
- [x] 2026-05-24 corrective update: Restore interactive `claude-cli` and `codex-cli` launches, allow provider/model flags after agent subcommands, and link the executable with `-threaded`.
- [x] EP-5: Make kit-installed skills and agents load in Codex interactive sessions as well as Claude Code sessions.


## Surprises & Discoveries

Baikai's CLI providers are not drop-in replacements for interactive local agent launches. Evidence from `/Users/shinzui/Keikaku/bokuno/baikai/docs/user/cli-providers.md`: `claude-cli` drives `claude -p`, `codex-cli` drives `codex exec`, streaming is synthetic, usage is zeroed, and tool calling is not supported. The 2026-05-24 correction therefore restored direct `claude` and `codex` launches for CLI providers and kept Baikai for API providers.

The MasterPlan child init step was initially run in parallel and produced duplicate `36-` plan prefixes because the init script scans the directory without locking. The newly created files were renumbered immediately to `36` through `39`; future plan creation in this repository should run init scripts sequentially.

EP-1 uses local Baikai package paths in `cabal.project`: `../../baikai/baikai`, `../../baikai/baikai-claude`, and `../../baikai/baikai-openai`. The relative path is from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`; the initially assumed `../baikai/...` path does not exist.

Baikai re-exports duplicate record selectors named `api` and `provider` from both `Model` and `Response`. Later plans that inspect Baikai records directly should import narrower modules such as `Baikai.Model` or avoid direct Baikai selectors from command code.

`Seihou.CLI.Commands` still belongs to the executable target, not the `seihou-cli-internal` library that `seihou-cli-test` imports. EP-2 therefore validated parent parser behavior with `cabal run seihou -- agent --help` and `cabal run seihou -- agent --provider codex-cli --model gpt-5 --debug assist "say hello"` rather than adding a direct parser unit test.

EP-3 initially removed `Seihou.CLI.AgentLaunchExec` from the executable target after migration. The 2026-05-24 correction reintroduced that module as the direct interactive launcher for `claude-cli` and `codex-cli`. `Seihou.CLI.CommitMessage` still has its own Claude-based commit-message helper and is outside the `seihou agent` command migration.

EP-3 preserves `agent run --debug` as a successful dry launch for applied-blueprint bookkeeping. The old launcher returned `ExitSuccess` after printing a debug prompt, so the migrated runner records provenance after successful debug prompt printing as well as after successful provider completion.

EP-4 found that the embedded prompt templates were part of the user-visible debug surface. They now describe both cases: interactive CLI sessions may use repository tools directly, while one-shot API completions should return guidance and snippets for the user to apply.

EP-4 also found that `seihou agent run` discovers blueprints from `.seihou/modules`, user modules, and installed modules, not from the current directory itself. The blueprint debug smoke check therefore used a temporary project with the sample blueprint copied under `.seihou/modules/sample-blueprint`.

2026-05-24: The completed behavior had two regressions. First, `seihou agent assist --provider codex-cli` was parsed as a subcommand-local provider request by users but the parser only accepted provider flags before the subcommand. Second, the default `claude-cli` path attempted Baikai's Cradle-backed `claude -p` provider from an executable not linked with `-threaded`, producing `Cradle needs the ghc's threaded runtime system to work correctly. Use the ghc option '-threaded'.`

2026-05-24: A follow-up gap remains after `codex-cli` became a supported interactive provider. `Seihou.CLI.AgentLaunchExec` passes Seihou's user and project agent directories to Codex with `--add-dir`, but `Seihou.CLI.Kit` currently writes installed skills and agents only into `.claude/...` subdirectories below those mounts. Codex therefore receives the directory mount but not Codex-native kit content.

2026-05-24: EP-5 corrected an initial Codex layout assumption. Current official Codex documentation says repo/project skills are discovered from `.agents/skills`, user skills from `$HOME/.agents/skills`, project custom agents from `.codex/agents`, and user custom agents from `$HOME/.codex/agents`. EP-5 therefore installs Codex kit content into those Codex-native discovery roots instead of below Seihou's `.seihou/agents` mount.

2026-05-24: Running `cabal build seihou` and `cabal test seihou-cli-test` in parallel can collide in Cabal's shared `dist-newstyle` package database. During EP-5, the parallel test command failed with `ghc-pkg-9.12.2: cannot create: ... package.conf.inplace already exists`; rerunning build and tests sequentially passed.


## Decision Log

- Decision: Use four child plans: facade, configuration, command migration, and documentation/validation.
  Rationale: These are separate functional concerns with clear hard dependencies and independently verifiable outcomes.
  Date: 2026-05-23

- Decision: Default to `claude-cli` with no explicit model when users do not configure anything.
  Rationale: This preserves the closest available Claude-backed behavior. After the 2026-05-24 correction, leaving the model empty lets interactive Claude Code choose its own default, matching the existing command's lack of a model flag.
  Date: 2026-05-23

- Decision: Initially model the CLI providers as batch completion providers, not interactive agents. Superseded on 2026-05-24.
  Rationale: The Baikai source and docs show the Claude CLI provider shells out to `claude -p --output-format json --no-session-persistence` and the OpenAI CLI provider shells out to `codex exec --json`; neither path supports Claude Code `--allowedTools` semantics. Live usage showed this did not meet `seihou agent` expectations, so direct interactive launches replaced the batch CLI-provider path.
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

- Decision: Restore direct interactive launches for `claude-cli` and `codex-cli`; keep Baikai for API providers.
  Rationale: Users invoke `seihou agent assist` to start an agent session, and Baikai's CLI providers are intentionally batch subprocess adapters. Directly launching `claude` and `codex` matches user expectations while preserving configurable provider/model resolution and Baikai API support.
  Date: 2026-05-24

- Decision: Accept `--provider` and `--model` both before and after agent subcommands, with subcommand-local flags taking precedence.
  Rationale: The reported command was `seihou agent assist --provider codex-cli`; treating that as valid is more ergonomic and avoids surprising parser failures.
  Date: 2026-05-24

- Decision: Launch interactive `codex-cli` sessions with `--ask-for-approval on-request --sandbox workspace-write`.
  Rationale: Codex's default interactive approval behavior prompts too often for normal Seihou workflows such as running project commands and git operations. Codex does not expose a Claude-style per-tool allowlist, so Seihou maps its permission intent to Codex's approval policy and sandbox flags.
  Date: 2026-05-24

- Decision: Add EP-5 as a follow-up rather than modifying completed EP-3 or EP-4.
  Rationale: The remaining gap is kit lifecycle support for Codex-native skill and agent files. The provider launcher and docs migration are already complete and should stay historically accurate.
  Date: 2026-05-24

- Decision: Treat EP-5 as complete after provider-native kit lifecycle support and focused path tests landed.
  Rationale: The implementation writes Claude and Codex copies during install, repairs missing provider copies during update, reports provider coverage during status, removes both provider copies during uninstall, updates user and architecture documentation, and passed build, tests, and manual smoke validation.
  Date: 2026-05-24


## Outcomes & Retrospective

The configurable agent assistance initiative completed its original provider/model migration after a corrective update. Seihou now has a Baikai API completion facade, provider/model resolution from subcommand flags, parent flags, environment, local config, global config, and defaults, interactive local launchers for `claude-cli` and `codex-cli`, Codex approval/sandbox defaults for smoother interactive sessions, migrated agent command handlers, updated user/developer documentation, updated parser help text, and prompt templates that work for both interactive CLI sessions and one-shot API completions.

EP-5 completed one adjacent follow-up: kit-installed assistance content now supports Codex interactive sessions as well as Claude Code sessions. `seihou kit install` writes skills to both Claude's `.claude/skills` layout and Codex's `.agents/skills` layout. Kit agents remain Claude Markdown files for Claude Code and are converted into Codex custom-agent TOML files under `.codex/agents` or `~/.codex/agents`. `seihou kit status` reports provider coverage, `kit update` repairs partial provider installs, and `kit uninstall` removes all provider copies for the selected item and scope.

Validation completed on 2026-05-23 with `cabal build all`, `cabal test all`, `seihou agent --help`, debug smoke checks for `assist`, `bootstrap`, and `setup`, and a temporary-project debug smoke check for `agent run sample-blueprint`. The 2026-05-24 corrective update additionally validated `cabal build seihou`, parent-position debug parsing, subcommand-position provider parsing, and a non-TTY `codex-cli` smoke check that reached Codex and failed with `stdin is not a terminal`, proving Seihou starts the interactive CLI instead of printing a batch response.

EP-5 validation completed on 2026-05-24 with `nix fmt`, `cabal build seihou`, `cabal test seihou-cli-test`, a temporary project-scope `seihou kit install/status/uninstall seihou-module-readme --project` smoke check, and `seihou agent --provider codex-cli --debug assist "confirm kit content is mounted"`.

Revision note, 2026-05-24: Updated the MasterPlan after bug reports showed the completed Baikai CLI-provider behavior was not the desired user experience. The plan now records the corrected split: interactive local CLI providers are launched directly, while API providers continue through Baikai. It also records the parser precedence change and the threaded runtime fix.

Revision note, 2026-05-24: Added EP-5, `docs/plans/40-support-codex-kit-skills-and-agents.md`, after discovering that `seihou kit` still installs Claude-only `.claude/...` content even though `codex-cli` is now a supported interactive provider. The registry, dependency graph, integration points, progress, discoveries, decision log, and retrospective now track the Codex kit follow-up.

Revision note, 2026-05-24: Marked EP-5 complete after implementing `docs/plans/40-support-codex-kit-skills-and-agents.md`. Updated the registry, dependency graph, integration points, progress, surprises, decision log, and retrospective to reflect Codex-native kit layouts, provider-aware lifecycle behavior, and validation evidence.
