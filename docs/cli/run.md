# seihou run

Run modules to generate a project.

## Usage

```
seihou run [MODULE] [OPTIONS]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `MODULE` | No | Primary module to run. If omitted, an fzf picker opens. |

## Options

| Option | Description |
|--------|-------------|
| `-m, --module MODULE` | Additional modules to compose (repeatable) |
| `--var KEY=VALUE` | Variable overrides (repeatable) |
| `--dry-run` | Show plan without executing |
| `--diff` | Show diff against current disk state |
| `--force` | Auto-resolve conflicts (accept new files) |
| `--no-commands` | Skip shell command steps |
| `--namespace NS` | Override namespace for config lookup |
| `-c, --context CTX` | Override context for config lookup |
| `-v, --verbose` | Show detailed progress messages |

## Description

Loads the specified module and its dependencies, resolves all variables, compiles a generation plan, and executes it in the current directory.

Handles multiple module composition with explicit layering. Manages manifest state (`.seihou/manifest.json`) for incrementality, tracking new, modified, unchanged, and conflicting files.

## Examples

```sh
# Run a single module
seihou run haskell-project

# Compose multiple modules
seihou run haskell-project -m github-ci -m nix-flake

# Dry run with variable overrides
seihou run haskell-project --var project-name=my-app --dry-run

# Force overwrite conflicts
seihou run haskell-project --force
```
