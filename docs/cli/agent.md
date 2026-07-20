# seihou agent

AI-powered agent commands backed by configurable providers. First-class prompt
artifacts use the same provider configuration through `seihou prompt run`.

## Usage

```text
seihou agent [--debug] [--provider PROVIDER] [--model MODEL] <SUBCOMMAND> [OPTIONS]
```

## Options

| Option | Description |
|--------|-------------|
| `--debug` | Print the resolved system prompt and exit without contacting a provider |
| `--provider PROVIDER` | Use `claude-cli`, `codex-cli`, `anthropic`, or `openai` for this invocation |
| `--model MODEL` | Use a provider-specific model name or alias for this invocation; run `seihou agent models` to list known choices |
| `--effort LEVEL` | Reasoning effort for this invocation: `minimal`, `low`, `medium`, `high`, `xhigh`, or `max` |

The default provider is `claude-cli`. When no model is configured, Seihou pins a deterministic per-provider default (`claude-cli` → `claude-opus-4-8`, `codex-cli` → `gpt-5.6-terra`) and always passes it explicitly, so a CLI session never inherits whatever model another `claude`/`codex` session left active. Provider and model options may appear on the parent command or on the subcommand:

```sh
seihou agent --provider codex-cli --model gpt-5 assist "create a module"
seihou agent assist --provider codex-cli --model gpt-5 "create a module"
seihou agent --debug --provider openai setup "show the prompt only"
```

Provider and model values are resolved from CLI flags, environment variables, per-command and shared config keys (local then global), and defaults. Each command can be configured independently with `agent.<command>.provider` / `agent.<command>.model`, falling back to the shared `agent.provider` / `agent.model` defaults; a local project value always overrides a global one. See [Configuration and Variable Resolution](../user/config-and-variables.md#agent-provider-defaults) for the full precedence chain, and run `seihou agent config` (below) to inspect what resolves for each command.

## Providers

| Provider | Backing implementation | Requirements | Notes |
|----------|-------------------------|--------------|-------|
| `claude-cli` | interactive `claude` | `claude` installed, on `PATH`, and authenticated | Starts a Claude Code session with the rendered Seihou prompt and allowed tool flags. Defaults to `claude-opus-4-8` when no model is configured; the model is always passed explicitly so the session is deterministic |
| `codex-cli` | interactive `codex` | `codex` installed, on `PATH`, and authenticated | Starts a Codex session with the rendered Seihou prompt, workspace-write sandboxing, and on-request approvals. Defaults to `gpt-5.6-terra` when no model is configured; the model is always passed explicitly so the session is deterministic |
| `anthropic` | Anthropic Messages API | `ANTHROPIC_API_KEY` or `ANTHROPIC_KEY` | Defaults to `claude-sonnet-4-6` when no model is configured |
| `openai` | OpenAI Chat Completions API | `OPENAI_API_KEY` or `OPENAI_KEY` | Defaults to `gpt-4o-mini` when no model is configured |

## Subcommands

### agent models

List the models in Seihou's compiled Baikai catalog.

```text
seihou agent models [--provider PROVIDER]
```

The provider filter may appear on the parent command or after the subcommand:

```sh
seihou agent --provider claude-cli models
seihou agent models --provider openai
```

Anthropic catalog rows are compatible with both `anthropic` and `claude-cli`;
OpenAI rows are compatible with both `openai` and `codex-cli`. The unfiltered
table prints each model once with both compatible providers. Listing uses only
compiled data, so it does not read agent configuration, inspect API keys, or
contact a provider.

The catalog is a discovery aid rather than a validation list. Provider-native
aliases and custom model IDs remain accepted by `--model` even when they do not
appear in the table. Passing a parent `--model` to `agent models` is rejected
because a model selection is irrelevant to a listing command.

### agent config

Show the resolved provider and model for every agent command.

```text
seihou agent config
```

Prints one entry per command (`assist`, `bootstrap`, `setup`, `run`, `migrate`, and
`prompt run`) with its resolved provider, model, and reasoning effort, each
labelled by the source that supplied the value — a config scope and key (for
example `[local: agent.run.model]` or `[global: agent.effort]`), an environment
variable, or `[built-in default]` — followed by the precedence legend. An
`effort` of `(default)` means none is configured. The command is read-only: it
reflects the current environment and config but never changes them. Set values
with `seihou config set agent.<command>.{provider,model,effort} ...`.

### agent assist

Launch an AI-assisted template authoring session.

```text
seihou agent assist [PROMPT]
```

Renders a Seihou-aware prompt for creating and modifying modules, then starts the configured provider. CLI providers open interactive local agent sessions. API providers receive a one-shot completion request and print the assistant response. The prompt includes context about the current directory, existing modules, manifest state, available modules, and the Seihou module schema.

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

Resolves the named blueprint, prompts for required variables, optionally applies its baseline modules, renders the blueprint prompt, and starts the configured provider. A successful non-debug run records applied-blueprint provenance in `.seihou/manifest.json`.

### agent migrate

Run ordered library-upgrade prompts declared by a blueprint.

```text
seihou agent migrate BLUEPRINT --from VERSION --to VERSION [PROMPT] [OPTIONS]
```

| Option | Description |
|--------|-------------|
| `--from VERSION` | Current library version; required dotted numeric value |
| `--to VERSION` | Target library version; required dotted numeric value |
| `--var KEY=VALUE` | Variable override; repeatable |
| `--namespace NS` | Override namespace for config lookup |
| `--context CTX`, `-c CTX` | Override context for config lookup |
| `--verbose`, `-v` | Show detailed progress messages |
| `--rerun` | Ignore matching exact-edge receipts and run the selected steps again |

The command plans matching blueprint edges in ascending version order, permitting
undeclared gaps, and starts one provider interaction per edge. It writes a
receipt after each successful interaction, so an interrupted invocation resumes
at its first unrecorded edge. Migration mode does not apply blueprint baselines
and has no `--force` option.

```sh
seihou agent migrate my-library --from 1.0.0 --to 3.0.0
seihou agent --debug migrate my-library --from 1.0.0 --to 3.0.0
```

For this subcommand, parent `--debug` is a true dry run: it prints every pending
prompt in order, never contacts a provider, and never writes a migration receipt.
Receipts report provider completion rather than package-manager verification.
See [Agent-Driven Blueprints](../user/blueprints.md#library-upgrade-migrations).

## Requirements

At least one configured provider must be usable for non-debug runs. The CLI providers require their local binaries and login state. API providers require their API keys. Debug runs do not contact providers and are safe to use for prompt inspection:

```sh
seihou agent --debug --provider claude-cli assist "inspect this prompt"
seihou agent --debug --provider codex-cli bootstrap --repo "inspect this prompt"
seihou agent --debug --provider openai setup "inspect this prompt"
```

## First-Class Prompts

Use `seihou prompt run PROMPT` for reusable agent-session templates that do not
apply blueprint baselines or record applied-blueprint provenance:

```sh
seihou prompt run review-changes --debug
seihou prompt run review-changes --provider codex-cli
```

See [`seihou prompt`](prompt.md) and [First-Class Prompts](../user/prompts.md).
