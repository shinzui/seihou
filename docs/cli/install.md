# seihou install

Install modules, recipes, blueprints, and prompts from a git repository.

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
| `--module MODULE` | Install a specific module, recipe, blueprint, or prompt from the registry (repeatable) |
| `--all` | Install all modules, recipes, blueprints, and prompts from the registry |

## Description

Clones the git repository and installs modules, recipes, blueprints, and prompts to
`~/.config/seihou/installed/<name>/`.

Handles these repository types:

- **Single-module** repos (containing `module.dhall` at the root)
- **Single-recipe** repos (containing `recipe.dhall` at the root)
- **Single-blueprint** repos (containing `blueprint.dhall` at the root)
- **Single-prompt** repos (containing `prompt.dhall` at the root)
- **Multi-item registries** (containing `seihou-registry.dhall`)

For registries, module, recipe, blueprint, and prompt entries are presented for selection.
If neither `--module` nor `--all` is specified, an interactive picker is shown.
The `--all` flag installs all registry entries. The `--module` flag name is kept
for compatibility, but it can select any registry entry kind.

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

# Install specific items from a registry
seihou install https://github.com/user/seihou-modules.git --module haskell --module api-service

# Install all items from a registry
seihou install https://github.com/user/seihou-modules.git --all

# Install a prompt entry from a registry
seihou install https://github.com/user/team-prompts.git --module review-changes

# Reinstall from history (opens fzf picker)
seihou install
```
