# seihou browse

Browse modules, recipes, and blueprints in a git repository without installing.

## Usage

```
seihou browse <GIT-URL> [OPTIONS]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `GIT-URL` | Yes | Git repository URL to browse |

## Options

| Option | Description |
|--------|-------------|
| `--tag TAG` | Filter items by tag |

## Description

Clones the repository and shows available modules, recipes, and blueprints
without installing anything. For registry repos with `seihou-registry.dhall`,
displays all module, recipe, and blueprint entries with descriptions and tags.
Single-recipe repos (containing `recipe.dhall` at the root) and
single-blueprint repos (containing `blueprint.dhall` at the root) are also
detected.

## Examples

```sh
# Browse available items
seihou browse https://github.com/user/seihou-modules.git

# Filter by tag
seihou browse https://github.com/user/seihou-modules.git --tag haskell
```
