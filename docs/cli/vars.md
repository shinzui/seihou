# seihou vars

Inspect resolved variables for a module.

## Usage

```
seihou vars [MODULE] [OPTIONS]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `MODULE` | No | Module to inspect. If omitted, an fzf picker opens. |

## Options

| Option | Description |
|--------|-------------|
| `--explain` | Show resolved values with provenance (default/CLI/environment/export) |
| `--var KEY=VALUE` | Provide variable values for resolution (repeatable) |
| `--namespace NS` | Override namespace for config lookup |
| `-c, --context CTX` | Override context for config lookup |

## Description

Lists all variable declarations for a module with their types, defaults, and descriptions.

With `--explain`, resolves variables and shows where each value came from (default value, CLI override, environment variable, or cross-module export).

## Examples

```sh
# List variables for a module
seihou vars haskell-project

# Show resolved values with provenance
seihou vars haskell-project --explain

# Explain with specific overrides
seihou vars haskell-project --explain --var project-name=my-app
```
