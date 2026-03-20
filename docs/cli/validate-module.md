# seihou validate-module

Validate a module for correctness.

## Usage

```
seihou validate-module [PATH] [OPTIONS]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `PATH` | No | Module directory path (defaults to current directory) |

## Options

| Option | Description |
|--------|-------------|
| `--lint` | Include advisory lint warnings |

## Description

Checks module well-formedness:

- `module.dhall` exists and evaluates successfully
- Module name is valid
- Variable names are unique
- Prompts reference declared variables
- Step source files exist
- Exports reference declared variables

With `--lint`, additional advisory warnings are reported.

## Examples

```sh
# Validate the module in the current directory
seihou validate-module

# Validate a specific module
seihou validate-module ./my-module

# Validate with lint warnings
seihou validate-module --lint
```
