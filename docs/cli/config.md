# seihou config

Read and write configuration values.

## Usage

```
seihou config <SUBCOMMAND> [OPTIONS]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `set KEY VALUE` | Set a config value |
| `get KEY` | Get a config value |
| `unset KEY` | Remove a config value |
| `list` | List config values |

## Options

| Option | Description |
|--------|-------------|
| `-g, --global` | Use global scope (`~/.config/seihou/config.dhall`) |
| `-n, --namespace NS` | Use namespace scope |
| `-c, --context CTX` | Use context scope |
| `-e, --effective` | Show merged config across all scopes (with `list`) |

## Description

Manage config values across multiple scopes:

- **Local** (default): `.seihou/config.dhall` in the current project
- **Global**: `~/.config/seihou/config.dhall`
- **Namespace**: scoped by namespace
- **Context**: scoped by context (e.g., work, personal)

## Examples

```sh
# Set a local config value
seihou config set user.name "Alice"

# Set a global config value
seihou config set user.email "alice@example.com" --global

# Get a value
seihou config get user.name

# List all effective config
seihou config list --effective

# Set a context-scoped value
seihou config set user.email "alice@work.com" --context work
```
