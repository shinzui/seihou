# seihou schema-upgrade

Upgrade module.dhall files to the current schema.

## Usage

```
seihou schema-upgrade [PATH] [OPTIONS]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `PATH` | No | Module directory to upgrade. Defaults to current directory. |

## Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Show what would change without modifying files |
| `--all` | Upgrade all discovered modules across all search paths |

## Description

Detects missing or outdated fields in `module.dhall` files and rewrites them to match the current schema. This command is useful when upgrading modules written for an older version of Seihou that may be missing fields like `version`, `patch`, or `commands`.

The command handles:

- **Missing `version` field** — Adds `version = None Text` after the `name` field.
- **Missing `patch` on steps** — Adds `patch = None Text` to step records that lack it.
- **Missing `commands` field** — Adds an empty `commands` list before `dependencies`.
- **Bare string dependencies** — Converts `["module-name"]` to the record form `[{ module = "module-name", vars = [] : List { name : Text, value : Text } }]`.
- **`List Text` dependency annotation** — Converts `[] : List Text` to the record type annotation.
- **Missing schema import** — Injects `let S = <url> <hash> in S.Module::{...}` wrapping the module record, importing the schema from the pinned GitHub URL.

The command is idempotent — running it on an already-current module reports "up to date" and makes no changes.

## Examples

```sh
# Upgrade module.dhall in the current directory
seihou schema-upgrade

# Upgrade a specific module
seihou schema-upgrade ./my-module

# Preview what would change
seihou schema-upgrade --dry-run

# Upgrade all discovered modules
seihou schema-upgrade --all
```
