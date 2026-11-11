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
| `--full` | Show complete descriptions, word-wrapped, instead of one truncated line |

## Description

Scans all module search paths and lists every available module, recipe,
blueprint, and prompt. Entries are grouped under one heading per kind
(`Modules`, `Recipes`, `Blueprints`, `Prompts`), each with a count, and
sorted by name within it. A kind with nothing to show has no section.

Each entry takes two lines: its name and source location (`project`, `user`,
or `installed`) on the first, and its description indented on the second.
Installed items show their origin repository and version when that
information is recorded in `.seihou-origin.json`:

```text
Recipes (2)

  haskell-library   installed: my-templates v1.0.0
    Haskell library with Nix + Cabal
  service-starter   installed: my-templates v0.3.0
    Bootstrap a service repository with CI, container images, and a deploy…

Blueprints (1)

  api-service       installed: my-templates v0.1.0
    Agent-guided API service starter

3 items found (3 sources searched)
```

By default each description is collapsed to one line and cut at 72
characters with a trailing `…`, so no line is wider than 76 columns and the
list stays readable in an 80-column terminal however long a description is.
Pass `--full` to see every description in full, word-wrapped at the same
width under the same indentation, with a blank line between entries.

Items that fail to load are shown with an error indicator in place of their
description.

### Filters

`--repo`, `--tag`, and kind flags read the `.seihou-origin.json` metadata written by
`seihou install` (which records the registry `repoName`, item `version`,
kind, and `tags` from `seihou-registry.dhall`). Filters combine with AND:
supplying both `--repo` and `--tag` returns only items matching both.
Project and user-scope items have no origin metadata and are therefore
excluded by an active `--repo` or `--tag` filter. Kind flags only change
which sections appear.

When a filter is active, the summary line includes a
`[filtered: repo=…, tag=…, kind=…]` suffix so it is clear the list is a subset.

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

# Read every blueprint's whole description
seihou list --full --blueprints
```
