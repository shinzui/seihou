# seihou prompt

Run first-class agent-session prompts.

## Usage

```text
seihou prompt COMMAND [OPTIONS]
```

## Subcommands

| Command | Description |
|---------|-------------|
| `run` | Resolve, render, and launch a prompt |

## seihou prompt run

```text
seihou prompt run PROMPT [USER-PROMPT] [OPTIONS]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `PROMPT` | Yes | Name of the prompt to run |
| `USER-PROMPT` | No | Optional one-off instruction appended to the rendered prompt |

## Options

| Option | Description |
|--------|-------------|
| `--var KEY=VALUE` | Variable override; repeatable |
| `--namespace NS` | Override namespace for config lookup |
| `--context CTX`, `-c CTX` | Override context for config lookup |
| `--provider PROVIDER` | Use `claude-cli`, `codex-cli`, `anthropic`, or `openai` for this invocation |
| `--model MODEL` | Use a provider-specific model name or alias for this invocation |
| `--debug` | Print the complete rendered provider prompt, including context and guidance, then exit without contacting a provider |
| `--verbose`, `-v` | Show detailed progress messages |

## Description

`seihou prompt run` discovers the named `prompt.dhall`, resolves typed
variables through the standard Seihou precedence chain, prompts for required
missing values when interactive, runs command-derived variables, renders the
Markdown body, wraps it with current Seihou project context, prompt identity,
reference-file metadata, and selected prompt guidance, then starts the
configured provider.

Debug mode is the safest way to inspect a prompt:

```sh
seihou prompt run review-changes --debug
```

The debug output is the exact provider prompt. It includes the environment
block, prompt identity block, reference-file block, prompt guidance block, the
rendered prompt body, and any one-off `USER-PROMPT`.

Non-debug runs launch the configured provider. CLI providers start interactive
Claude Code or Codex sessions. API providers send one rendered completion
request and print the assistant response.

## Examples

```sh
# Render and inspect without launching a provider
seihou prompt run review-changes --debug

# Supply a typed variable
seihou prompt run review-changes --var project.name=seihou

# Add a one-off instruction
seihou prompt run review-changes "focus on CLI changes"

# Launch through Codex for this invocation
seihou prompt run review-changes --provider codex-cli
```

## See Also

- [First-Class Prompts](../user/prompts.md)
- [AI Agent Assistance](../user/agent-assistance.md)
- [`seihou new-prompt`](new-prompt.md)
- [`seihou validate-prompt`](validate-prompt.md)
