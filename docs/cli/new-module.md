# seihou new-module

Scaffold a new module.

## Usage

```
seihou new-module <NAME> [OPTIONS]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `NAME` | Yes | Module name to create |

## Options

| Option | Description |
|--------|-------------|
| `--path DIR` | Output directory (default: `./<name>/`) |

## Description

Creates a new module directory with boilerplate files:

```
<name>/
├── module.dhall
└── files/
    └── README.md.tpl
```

Module names must match `[a-z][a-z0-9-]*` — lowercase letters and hyphens, starting with a letter.

## Examples

```sh
# Create a module in the current directory
seihou new-module my-template

# Create a module at a specific path
seihou new-module my-template --path ~/seihou-modules/my-template
```
