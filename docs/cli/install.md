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
| `--force` | Replace an installation that came from a different source, or one with no recorded provenance |

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

### When the name is already taken

`~/.config/seihou/installed/` is keyed by the artifact's bare name across every
repository you have ever installed from, and it is shared by every project on
the machine. Two repositories can publish an artifact with the same name, so
installing over an existing entry is either the most routine thing seihou does
or one of the most destructive, and only the provenance recorded in
`.seihou-origin.json` beside the installed copy tells them apart.

Reinstalling from the same URL — the ordinary way to pick up a new version —
replaces the entry without comment. Installing from a *different* URL stops:

```text
✗ Refusing to install 'shared-thing': a different artifact
  is already installed under that name.

  Installed on this machine:  https://github.com/acme/one
  Incoming:                   https://github.com/acme/two

  These are different artifacts that happen to share a name. Installing
  would replace the first for every project on this machine.

  To replace it anyway, re-run with --force.
```

Nothing is removed before that decision, so a refused install leaves the
existing entry byte-identical. The command exits non-zero.

An entry that carries no `.seihou-origin.json` at all — one you created by hand,
or one left by a much older seihou — is refused for the same reason with a
message saying provenance is missing. Seihou cannot tell whether it is the same
artifact, and guessing would affect every project on the machine.

Two spellings of one git URL are one source: `https://host/repo`,
`https://host/repo.git`, and `https://host/repo/` all match each other, so
typing a different spelling than last time is not a collision.

`--force` replaces the entry anyway and prints what it overrode. It is the only
override for a registry entry, because `--name` applies to single-artifact
repositories only and a registry entry has no rename escape hatch. When
installing a whole registry, every entry is attempted and each refusal is
printed; the command reports the totals and then exits non-zero.

If `--force` feels too blunt — you want the old entry gone rather than
overwritten, and you want to see what disappears — remove it by hand first:

```sh
rm -rf ~/.config/seihou/installed/shared-thing
```

The install then finds nothing under that name and proceeds silently. Do this
knowing it affects every project on the machine that resolved that name; a
project whose `.seihou/manifest.json` records the removed artifact will report
it as missing on the next `seihou status`.

`seihou upgrade`, `seihou update`, and `seihou migrate` also write to the cache,
but always from the URL the artifact itself already records, so they never hit
this refusal in normal operation and have no `--force` for it. If one of them
does report a source mismatch, the cache disagrees with its own provenance file
— see [`seihou upgrade`](upgrade.md) and [`seihou migrate`](migrate.md).

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

# Replace an artifact installed from a different repository
seihou install https://github.com/acme/two.git --module shared-thing --force
```
