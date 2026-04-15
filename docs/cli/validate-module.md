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
- **Module declares a version** (required — `version` must be `Some "X.Y.Z"` with a non-empty string)
- Variable names are unique
- Prompts reference declared variables
- Step source files exist
- Dependency names are valid
- Step destinations are safe and reference declared variables
- Commands are well-formed and safe
- Exports reference declared variables

A module without a `version` (or with `version = Some ""`) fails validation
with `module must declare a version`. `seihou install` and `seihou upgrade`
rely on versions to compare installed vs. available releases, so every
module is expected to be versioned.

With `--lint`, additional advisory warnings are reported: unused variables,
required variables without prompts, duplicate step destinations, empty
choice lists, and variables missing descriptions.

## Examples

```sh
# Validate the module in the current directory
seihou validate-module

# Validate a specific module
seihou validate-module ./my-module

# Validate with lint warnings
seihou validate-module --lint
```
