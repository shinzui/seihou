# seihou agent

AI-powered agent commands backed by Baikai providers.

## Usage

```text
seihou agent [--debug] [--provider PROVIDER] [--model MODEL] <SUBCOMMAND> [OPTIONS]
```

## Options

| Option | Description |
|--------|-------------|
| `--debug` | Print the resolved system prompt and exit without contacting a provider |
| `--provider PROVIDER` | Use `claude-cli`, `codex-cli`, `anthropic`, or `openai` for this invocation |
| `--model MODEL` | Use a provider-specific model name or alias for this invocation |

The default provider is `claude-cli` with no explicit model, which lets the local `claude -p` command choose its own default. Parent options must appear before the subcommand:

```sh
seihou agent --provider codex-cli --model gpt-5 assist "create a module"
seihou agent --debug --provider openai setup "show the prompt only"
```

Provider and model values are resolved from CLI flags, environment variables, local config, global config, and defaults. See [Configuration and Variable Resolution](../user/config-and-variables.md#agent-provider-defaults) for the full precedence chain.

## Providers

| Provider | Backing Baikai provider | Requirements | Notes |
|----------|-------------------------|--------------|-------|
| `claude-cli` | `claude -p` | `claude` installed, on `PATH`, and authenticated | Batch text provider; no tool calls or interactive Claude Code handoff |
| `codex-cli` | `codex exec` | `codex` installed, on `PATH`, and authenticated | Batch text provider; no tool calls or interactive Codex handoff |
| `anthropic` | Anthropic Messages API | `ANTHROPIC_API_KEY` or `ANTHROPIC_KEY` | Defaults to `claude-sonnet-4-6` when no model is configured |
| `openai` | OpenAI Chat Completions API | `OPENAI_API_KEY` or `OPENAI_KEY` | Defaults to `gpt-4o-mini` when no model is configured |

## Subcommands

### agent assist

Launch an AI-assisted template authoring session.

```text
seihou agent assist [PROMPT]
```

Renders a Seihou-aware prompt for creating and modifying modules, then sends it to the configured provider as a one-shot completion. The prompt includes context about the current directory, existing modules, manifest state, available modules, and the Seihou module schema.

### agent bootstrap

Bootstrap a new module or multi-module repository.

```text
seihou agent bootstrap [PROMPT] [OPTIONS]
```

| Option | Description |
|--------|-------------|
| `--repo` | Bootstrap a multi-module repository with registry |

Renders a prompt for creating a complete Seihou module from scratch: defining variables, writing templates, setting up prompts, and validating the result. With `--repo`, the prompt targets a multi-module repository with `seihou-registry.dhall`.

### agent setup

Guided project setup: configure, run, and commit.

```text
seihou agent setup [PROMPT]
```

Renders a prompt for using a Seihou module: selecting a module, configuring variables and context, running the module to generate files, verifying output, and committing changes to git.

### agent run

Run an agent-driven blueprint.

```text
seihou agent run BLUEPRINT [PROMPT] [OPTIONS]
```

| Option | Description |
|--------|-------------|
| `--var KEY=VALUE` | Variable override; repeatable |
| `--no-baseline` | Skip applying the blueprint's base modules before rendering the prompt |
| `--namespace NS` | Override namespace for config lookup |
| `--context CTX`, `-c CTX` | Override context for config lookup |
| `--verbose`, `-v` | Show detailed progress messages |

Resolves the named blueprint, prompts for required variables, optionally applies its baseline modules, renders the blueprint prompt, and sends it to the configured provider. A successful non-debug run records applied-blueprint provenance in `.seihou/manifest.json`.

## Requirements

At least one configured provider must be usable for non-debug runs. The CLI providers require their local binaries and login state. API providers require their API keys. Debug runs do not contact providers and are safe to use for prompt inspection:

```sh
seihou agent --debug --provider claude-cli assist "inspect this prompt"
seihou agent --debug --provider codex-cli bootstrap --repo "inspect this prompt"
seihou agent --debug --provider openai setup "inspect this prompt"
```
