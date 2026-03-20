# seihou browse

Browse modules in a git repository without installing.

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
| `--tag TAG` | Filter modules by tag |

## Description

Clones the repository and shows available modules without installing anything. For multi-module repos with `seihou-registry.dhall`, displays all modules with descriptions and tags.

## Examples

```sh
# Browse available modules
seihou browse https://github.com/user/seihou-modules.git

# Filter by tag
seihou browse https://github.com/user/seihou-modules.git --tag haskell
```
