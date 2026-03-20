# seihou install

Install modules from a git repository.

## Usage

```
seihou install <GIT-URL> [OPTIONS]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `GIT-URL` | Yes | Git repository URL to clone |

## Options

| Option | Description |
|--------|-------------|
| `--name NAME` | Override installed module name (single-module repos only) |
| `--module MODULE` | Install a specific module from the registry (repeatable) |
| `--all` | Install all modules from the registry |

## Description

Clones the git repository and installs modules to `~/.config/seihou/installed/<name>/`.

Handles both single-module repos (containing `module.dhall`) and multi-module registries (containing `seihou-registry.dhall`). If neither `--module` nor `--all` is specified for a registry, an interactive picker is shown.

## Examples

```sh
# Install a single-module repo
seihou install https://github.com/user/seihou-haskell.git

# Install with a custom name
seihou install https://github.com/user/seihou-haskell.git --name my-haskell

# Install specific modules from a registry
seihou install https://github.com/user/seihou-modules.git --module haskell --module nix

# Install all modules from a registry
seihou install https://github.com/user/seihou-modules.git --all
```
