# seihou list

List available modules, recipes, and blueprints.

## Usage

```
seihou list [OPTIONS]
```

## Options

| Option | Description |
|--------|-------------|
| `--repo REPO` | Only show modules installed from the given registry repository |
| `--tag TAG` | Only show modules whose origin metadata contains this tag |

## Description

Scans all module search paths and lists every available module, recipe, and blueprint with:

- Name
- Description
- Source location (project, user, or installed)

Recipes and blueprints are shown with `[recipe]` and `[blueprint]` suffixes on
their source labels to distinguish them from modules.

Installed items show their origin repository, version, and kind when that
information is recorded in `.seihou-origin.json`, e.g.
`(installed: seihou-haskell v1.2.0 [recipe])` or
`(installed: seihou-services v0.1.0 [blueprint])`.

Items that fail to load are shown with an error indicator.

### Filters

`--repo` and `--tag` read the `.seihou-origin.json` metadata written by
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
```
