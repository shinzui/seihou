# seihou browse

Browse modules, recipes, blueprints, and prompts in a git repository without installing.

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

Clones the repository and shows available modules, recipes, blueprints, and prompts
without installing anything. For registry repos with `seihou-registry.dhall`,
displays all entries with kind labels, descriptions, and tags.
Single-recipe repos (containing `recipe.dhall` at the root) and
single-blueprint repos (containing `blueprint.dhall` at the root) are also
detected, as are single-prompt repos containing `prompt.dhall`.

## Examples

```sh
# Browse available items
seihou browse https://github.com/user/seihou-modules.git

# Filter by tag
seihou browse https://github.com/user/seihou-modules.git --tag haskell

# Browse a prompt registry
seihou browse https://github.com/user/team-prompts.git --tag review
```
