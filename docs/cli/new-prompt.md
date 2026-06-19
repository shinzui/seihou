# seihou new-prompt

Scaffold a new agent-session prompt.

## Usage

```text
seihou new-prompt <NAME> [OPTIONS]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `NAME` | Yes | Prompt name to create |

## Options

| Option | Description |
|--------|-------------|
| `--path DIR` | Output directory (default: `./<name>/`) |

## Description

A prompt is a reusable agent-session template. It renders a Markdown prompt
from typed variables, command-derived variables, and optional reference files,
then launches the configured provider through `seihou prompt run`.

This command creates:

```text
<name>/
├── prompt.dhall
├── prompt.md
└── files/
```

- `prompt.dhall` is the prompt record.
- `prompt.md` is the Markdown body rendered before launch.
- `files/` is an optional reference-file directory.

Prompt names must match `[a-z][a-z0-9-]*`. Prompts share the runnable lookup
namespace with modules, recipes, and blueprints.

## Examples

```sh
# Create a prompt in the current directory
seihou new-prompt review-changes

# Create a prompt at a specific path
seihou new-prompt release-prep --path ~/seihou-prompts/release-prep
```

## See Also

- [First-Class Prompts](../user/prompts.md)
- [`seihou validate-prompt`](validate-prompt.md)
- [`seihou prompt`](prompt.md)
