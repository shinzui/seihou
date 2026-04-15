# seihou list

List available modules.

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

Scans all module search paths and lists every available module with:

- Module name
- Description
- Source location (project, user, or installed)

Installed modules show their origin repository and version when that
information is recorded in `.seihou-origin.json`, e.g.
`(installed: seihou-haskell v1.2.0)`.

Modules that fail to load are shown with an error indicator.

### Filters

`--repo` and `--tag` read the `.seihou-origin.json` metadata written by
`seihou install` (which records the registry `repoName`, module `version`,
and `tags` from `seihou-registry.dhall`). Filters combine with AND:
supplying both `--repo` and `--tag` returns only modules matching both.
Project and user-scope modules have no origin metadata and are therefore
excluded by any active filter.

When a filter is active, the output header and summary include a
`[filtered: repo=…, tag=…]` suffix so it is clear the list is a subset.

## Examples

```sh
# List everything
seihou list

# Only modules installed from the seihou-haskell registry
seihou list --repo seihou-haskell

# Only modules tagged "haskell"
seihou list --tag haskell

# Combine filters
seihou list --repo seihou-templates --tag nix
```
