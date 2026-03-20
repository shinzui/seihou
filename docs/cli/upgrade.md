# seihou upgrade

Upgrade installed modules to latest versions.

## Usage

```
seihou upgrade [MODULE...] [OPTIONS]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `MODULE` | No | Specific modules to upgrade (repeatable). Defaults to all. |

## Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Show what would be upgraded without making changes |
| `--json` | Output as JSON |

## Description

Upgrades installed modules to the latest version from their source repository. Only modules installed via `seihou install` are eligible. Modules without version info are skipped.

## Examples

```sh
# Upgrade all installed modules
seihou upgrade

# Upgrade specific modules
seihou upgrade haskell-project nix-flake

# Preview upgrades
seihou upgrade --dry-run
```
