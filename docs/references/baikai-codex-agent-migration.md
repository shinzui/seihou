# Migrating Agent Commands to Baikai and Codex

This reference captures the reusable migration pattern for projects that are moving agent commands to Baikai while also supporting Codex as an interactive local CLI provider. It is written for other projects that have the same broad shape as Seihou: a CLI has agent commands, prompt rendering, optional kit/skill installation, and a desire to support both API-backed completions and local interactive agent sessions.

The key lesson is that "provider abstraction" has two different meanings. Baikai is a good abstraction for batch API completions: render one prompt, send one request, receive one assistant response. It is not a replacement for an interactive local agent CLI. Claude Code and Codex interactive sessions should be launched directly so the user keeps the expected terminal session, authenticated local state, permissions behavior, and working-directory context.


## Target Architecture

Split providers into two categories.

API providers go through Baikai. These include providers such as Anthropic and OpenAI-compatible APIs. The project should expose a small internal facade that converts project prompts into Baikai requests, registers the needed Baikai providers, executes the request, and extracts assistant text from the response. In Seihou this facade is `Seihou.CLI.AgentCompletion`.

Interactive CLI providers are launched directly. These include `claude-cli` and `codex-cli`. The project should still use the same provider/model resolution path, but dispatch to a launcher that shells out to the local CLI instead of calling Baikai. In Seihou this direct launcher is `Seihou.CLI.AgentLaunchExec`.

Keep prompt rendering provider-neutral. The command should build the same high-quality project context regardless of provider. The last step decides whether that rendered prompt goes into a Baikai batch request or an interactive local CLI process.


## Migration Steps

Add a provider/model configuration layer first. Support command flags, environment variables, project config, user config, and defaults in one resolver. Preserve the existing default provider unless the product intentionally changes it.

Introduce a Baikai facade for batch completions. Keep Baikai imports isolated in one module rather than spreading provider package details across command handlers. Test provider text parsing, model config construction, request construction, and response text extraction.

Move existing agent command handlers to consume the resolved provider config and rendered prompt. The handler should not know provider package details. It should choose between the Baikai completion path and the interactive launcher path.

Restore or preserve direct local CLI launch behavior for `claude-cli` and `codex-cli`. For Codex, pass the rendered prompt to `codex` and choose explicit sandbox and approval defaults that match the command's safety model. In Seihou the chosen defaults are workspace-write sandboxing and on-request approvals.

Make parser ergonomics explicit. Users expect provider/model flags to work both before and after the agent subcommand, such as `tool agent --provider codex-cli assist` and `tool agent assist --provider codex-cli`. If both positions are supported, document the precedence.


## Kit and Skill Support

Do not assume a single mounted directory is a portable agent-content layout. Claude Code and Codex discover skills and agents from different filesystem conventions.

Install provider-native copies. For Claude Code, Seihou writes skills and agents below the Seihou agent base:

```text
<agent-base>/.claude/skills/<name>/
<agent-base>/.claude/agents/<name>.md
```

For Codex, Seihou writes skills and custom agents to Codex's native discovery locations:

```text
.agents/skills/<name>/
.codex/agents/<name>.toml
$HOME/.agents/skills/<name>/
$HOME/.codex/agents/<name>.toml
```

If a shared kit contains Markdown agent files for Claude Code, convert those files into Codex custom-agent TOML for Codex. Preserve the kit agent's instructions as `developer_instructions`, and write stable metadata such as `name` and `description`.

Put provider path rules in one testable helper module. Seihou uses `Seihou.CLI.KitPaths` for `skillTargetDir`, `agentTargetFile`, Codex TOML generation, and provider-specific installed scans. The command handler calls those helpers for install, update, uninstall, and status instead of duplicating string literals.

Make lifecycle operations symmetric. Install should write every supported provider layout. Update should repair partial installs when one provider copy exists and another is missing. Status should show provider coverage, for example `claude,codex`. Uninstall should remove all provider copies for the selected item and scope without deleting parent provider directories.


## Validation

Use unit tests for provider-independent logic. Test provider parsing, config precedence, Baikai request construction, response extraction, provider path helpers, Codex TOML generation, and installed-item scanning.

Use command smoke tests for the CLI surface. Verify help output, parser flag positions, debug prompt rendering, kit install/status/uninstall behavior, and build integration.

Treat debug mode carefully. A command such as `tool agent --provider codex-cli --debug assist ...` proves that the project resolved the provider and rendered the prompt. It does not prove that Codex loaded a skill, because debug mode exits before starting Codex. To prove downstream skill loading, run a real non-debug Codex session or a Codex command that enumerates available skills from the target working directory.

Avoid running `cabal build` and `cabal test` concurrently in the same workspace. In Seihou this caused a Cabal `dist-newstyle` package database collision:

```text
ghc-pkg-9.12.2: cannot create: ... package.conf.inplace already exists
```

Run build and tests sequentially when they share the same build directory.


## Common Mistakes

Do not route interactive CLI providers through Baikai just because Baikai has CLI-provider adapters. Those adapters are batch subprocess integrations, not an interactive terminal session with the user's expected workflow.

Do not let a provider/model abstraction hide behavior changes. If a provider opens an interactive session, model it as an interactive launch path. If a provider returns a one-shot response, model it as a completion path.

Do not install Codex skills into `.codex/skills` unless current Codex documentation explicitly says to do so. The documented project skill path used for this migration is `.agents/skills`, while custom agents live in `.codex/agents`.

Do not use debug-mode success as evidence that Codex loaded project skills. Debug mode is a prompt inspection path, not an end-to-end provider-discovery test.


## Seihou Reference Implementation

The Seihou implementation is a concrete example of this pattern:

- `seihou-cli/src/Seihou/CLI/AgentCompletion.hs` isolates Baikai batch completion behavior.
- `seihou-cli/src/Seihou/CLI/AgentConfig.hs` resolves provider and model settings.
- `seihou-cli/src/Seihou/CLI/AgentLaunch.hs` gathers and formats shared prompt context.
- `seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs` launches local interactive Claude Code and Codex sessions.
- `seihou-cli/src-exe/Seihou/CLI/Kit.hs` owns kit command flow.
- `seihou-cli/src/Seihou/CLI/KitPaths.hs` owns provider-native kit layouts.
- `docs/masterplans/4-baikai-backed-configurable-agent-assistance.md` records the initiative history and decision log.
- `docs/plans/40-support-codex-kit-skills-and-agents.md` records the Codex kit follow-up implementation.
