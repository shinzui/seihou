# seihou install

Install modules from a git repository.

## Usage

```
seihou install [GIT-URL] [OPTIONS]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `GIT-URL` | No | Git repository URL to clone. If omitted, an interactive picker selects from install history. |

## Options

| Option | Description |
|--------|-------------|
| `--name NAME` | Override installed module name (single-module repos only) |
| `--module MODULE` | Install a specific module from the registry (repeatable) |
| `--all` | Install all modules from the registry |

## Description

Clones the git repository and installs modules to
`~/.config/seihou/installed/<name>/`.

Handles both single-module repos (containing `module.dhall`) and multi-module
registries (containing `seihou-registry.dhall`). If neither `--module` nor
`--all` is specified for a registry, an interactive picker is shown.

### Install history

Every successful install appends the source URL to
`~/.config/seihou/install-history.json`, which retains the 50 most recent
entries (deduplicated, most-recent first).

When you run `seihou install` without a `GIT-URL`, Seihou resolves the
source from that history:

- If `fzf` is available, it opens an fzf picker prompting "Select a
  previously used source". Cancelling the picker aborts the install.
- Otherwise, it prints a numbered list and prompts for a selection.
- If the history is empty, the command prints a usage hint and exits
  non-zero.

This makes reinstalling from frequently-used repositories a single keystroke
away without needing to remember or retype long URLs.

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

# Reinstall from history (opens fzf picker)
seihou install
```
