# seihou new-recipe

Scaffold a new recipe.

## Usage

```
seihou new-recipe <NAME> [OPTIONS]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `NAME` | Yes | Recipe name to create |

## Options

| Option | Description |
|--------|-------------|
| `-m, --module MODULE` | Module to include in the recipe (repeatable) |
| `--path DIR` | Output directory (default: `./<name>/`) |

## Description

Creates a new recipe directory with a boilerplate `recipe.dhall`:

```
<name>/
└── recipe.dhall
```

Recipe names must match `[a-z][a-z0-9-]*` — lowercase letters and hyphens, starting with a letter.

A recipe is a named, reusable composition of modules. Instead of typing `seihou run mod-a -m mod-b -m mod-c` every time, you define a recipe that lists the modules and run `seihou run my-recipe`.

The generated `recipe.dhall` includes fields for `name`, `version`, `description`, `modules`, `vars`, and `prompts`. If `--module` flags are provided, the modules list is pre-populated.

## Examples

```sh
# Create a recipe with modules pre-populated
seihou new-recipe haskell-library --module nix-flake --module cabal-ghc

# Create an empty recipe to fill in manually
seihou new-recipe my-stack

# Create at a specific path
seihou new-recipe haskell-library --path ~/recipes/haskell-library
```
