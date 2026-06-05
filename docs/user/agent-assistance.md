# AI Agent Assistance

`seihou agent` renders Seihou-aware prompts and sends them to a configured AI
provider. Use it to author modules, bootstrap template repositories, guide
project setup, or run agent-driven blueprints.

CLI providers start interactive local tools. API providers send one rendered
prompt as a completion request and print one response.

## Providers

| Provider | Requirement | Behavior |
|----------|-------------|----------|
| `claude-cli` | Local `claude` binary on `PATH` and authenticated | Starts an interactive Claude Code session. |
| `codex-cli` | Local `codex` binary on `PATH` and authenticated | Starts an interactive Codex session with workspace-write sandboxing and on-request approvals. |
| `anthropic` | `ANTHROPIC_API_KEY` or `ANTHROPIC_KEY` | Calls the Anthropic Messages API through Baikai. |
| `openai` | `OPENAI_API_KEY` or `OPENAI_KEY` | Calls the OpenAI Chat Completions API through Baikai. |

The default provider is `claude-cli` with no explicit model.

## Selecting a provider

Provider and model flags may appear on either the parent `agent` command or
the subcommand:

```sh
seihou agent --provider codex-cli --model gpt-5 assist "create a module"
seihou agent assist --provider codex-cli --model gpt-5 "create a module"
```

For persistent defaults:

```sh
seihou config set agent.provider codex-cli --global
seihou config set agent.model gpt-5 --global
```

Resolution order is:

1. Subcommand `--provider` / `--model`
2. Parent `--provider` / `--model`
3. `SEIHOU_AGENT_PROVIDER` / `SEIHOU_AGENT_MODEL`
4. Local `.seihou/config.dhall`
5. Global `~/.config/seihou/config.dhall`
6. Built-in defaults

Agent provider settings are separate from module variable resolution.
Blueprint variables still use the normal variable precedence chain before the
blueprint prompt is rendered.

## Debug mode

`--debug` prints the resolved prompt and exits without contacting a provider:

```sh
seihou agent --debug assist "inspect this module"
seihou agent --debug --provider openai setup "inspect this prompt"
seihou agent --debug run api-service --var project.name=payments
```

Use debug mode to audit what Seihou will send, test provider selection, and
smoke-check prompts in CI without opening an agent session.

## Agent commands

### Assist

```sh
seihou agent assist "add a migration to this module"
```

Use `assist` inside an existing Seihou module or template repository. The
prompt includes the current directory, available modules, manifest state, and
schema guidance for module authoring.

### Bootstrap

```sh
seihou agent bootstrap "create a Haskell service template"
seihou agent bootstrap --repo "create a team template registry"
```

Use `bootstrap` when starting a new module or registry from scratch. `--repo`
targets a multi-item repository with `seihou-registry.dhall`.

### Setup

```sh
seihou agent setup "configure this repo with our Haskell template"
```

Use `setup` in a consumer project. The prompt guides the agent through
selecting modules, configuring variables and context, previewing the run,
verifying output, and committing changes when appropriate.

### Run

```sh
seihou agent run api-service "tailor this for payments"
```

Use `run` for blueprints. The runner resolves blueprint variables, optionally
applies baseline modules, renders the blueprint prompt, and records the
successful run in `.seihou/manifest.json`.

See [Agent-Driven Blueprints](blueprints.md) for blueprint authoring and
publishing details.

## Seihou Kit

`seihou kit` installs curated Claude Code and Codex skills and subagents from
the `seihou-kit` repository:

```sh
seihou kit list
seihou kit install review-pr
seihou kit install code-reviewer --project
seihou kit update
seihou kit status
```

User-scope installs are available across projects. Project-scope installs are
written into the current repository and can be checked in.

Kit installs provider-native copies for both Claude Code and Codex:

| Scope | Claude Code | Codex |
|-------|-------------|-------|
| User | `~/.config/seihou/agents/.claude/...` | `~/.agents/skills/` and `~/.codex/agents/` |
| Project | `.seihou/agents/.claude/...` | `.agents/skills/` and `.codex/agents/` |

When `seihou agent --provider codex-cli ...` launches from a project,
project-scoped Codex skills and custom agents are available through Codex's
native discovery paths.

## See also

- [Configuration and Variable Resolution](config-and-variables.md#agent-provider-defaults)
- [Agent-Driven Blueprints](blueprints.md)
- [`seihou agent`](../cli/agent.md)
- [`seihou kit`](../cli/kit.md)
