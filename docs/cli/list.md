# seihou list

List available modules, recipes, blueprints, and prompts.

## Usage

```
seihou list [OPTIONS]
```

## Options

| Option | Description |
|--------|-------------|
| `--repo REPO` | Only show items installed from the given registry repository |
| `--tag TAG` | Only show items whose origin metadata contains this tag |
| `--modules` | Only show modules |
| `--recipes` | Only show recipes |
| `--blueprints` | Only show blueprints |
| `--prompts` | Only show prompts |

## Description

Scans all module search paths and lists every available module, recipe, blueprint, and prompt with:

- Name
- Description
- Source location (project, user, or installed)

Recipes, blueprints, and prompts are shown with `[recipe]`, `[blueprint]`, and
`[prompt]` suffixes on their source labels to distinguish them from modules.

Installed items show their origin repository, version, and kind when that
information is recorded in `.seihou-origin.json`, e.g.
`(installed: seihou-haskell v1.2.0 [recipe])`,
`(installed: seihou-services v0.1.0 [blueprint])`, or
`(installed: team-prompts v0.1.0 [prompt])`.

Items that fail to load are shown with an error indicator.

### Filters

`--repo`, `--tag`, and kind flags read the `.seihou-origin.json` metadata written by
`seihou install` (which records the registry `repoName`, item `version`,
kind, and `tags` from `seihou-registry.dhall`). Filters combine with AND:
supplying both `--repo` and `--tag` returns only items matching both.
Project and user-scope items have no origin metadata and are therefore
excluded by any active filter.

When a filter is active, the output header and summary include a
`[filtered: repo=…, tag=…]` suffix so it is clear the list is a subset.

## Examples

```sh
# List everything
seihou list

# Only items installed from the seihou-haskell registry
seihou list --repo seihou-haskell

# Only items tagged "haskell"
seihou list --tag haskell

# Combine filters
seihou list --repo seihou-templates --tag nix

# Only prompts
seihou list --prompts
```
