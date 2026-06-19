# seihou new-blueprint

Scaffold a new agent-driven blueprint.

## Usage

```
seihou new-blueprint <NAME> [OPTIONS]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `NAME` | Yes | Blueprint name to create |

## Options

| Option | Description |
|--------|-------------|
| `--path DIR` | Output directory (default: `./<name>/`) |

## Description

A *blueprint* is one of Seihou's runnable artifact kinds, alongside modules,
recipes, and prompts. Where modules deterministically generate files, a
blueprint hands a base prompt and reference materials to an AI coding
agent which then iterates with the user on the actual project files. A
blueprint cannot be run with `seihou run`; the implemented agent
runner (`seihou agent run`) consumes it.

This command creates a new blueprint directory with boilerplate files:

```
<name>/
├── blueprint.dhall
├── prompt.md
└── files/
```

- `blueprint.dhall` — the blueprint record. Imports the schema from
  `seihou-schema` via URL and uses record completion (`::`).
- `prompt.md` — the Markdown body the agent runner consumes. Imported
  by `blueprint.dhall` as `./prompt.md as Text`. Edit this freely; it
  is plain Markdown, not Dhall.
- `files/` — empty reference directory. Snippets, partial templates,
  or example configurations placed here are mounted read-only into
  the agent's filesystem at run time.

Blueprint names must match `[a-z][a-z0-9-]*` — lowercase letters,
digits, and hyphens, starting with a letter. Blueprints share the same
namespace as modules and recipes; a single `seihou` lookup resolves
all three by name.

## Examples

```sh
# Create a blueprint in the current directory
seihou new-blueprint payments-service

# Create a blueprint at a specific path
seihou new-blueprint payments-service --path ~/seihou-blueprints/payments
```
