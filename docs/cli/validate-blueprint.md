# seihou validate-blueprint

Validate a blueprint for correctness.

## Usage

```
seihou validate-blueprint [PATH] [OPTIONS]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `PATH` | No | Blueprint directory path (defaults to current directory) |

## Options

| Option | Description |
|--------|-------------|
| `--lint` | Reserved for future advisory lint warnings (currently a no-op) |

## Description

Checks blueprint well-formedness:

- `blueprint.dhall` exists and evaluates successfully (including the
  `./prompt.md as Text` import)
- Blueprint name matches `[a-z][a-z0-9-]*`
- Blueprint version, if specified, is non-empty
- Prompt body is non-empty after trimming
- Variable names are unique
- Every interactive prompt references a declared variable
- Every entry in the `files` list resolves to an actual file under
  `files/` in the blueprint directory
- Every entry in `baseModules` is well-formed and resolves to a
  module or recipe — not another blueprint
- Tags and `allowedTools` entries are non-empty

If `blueprint.dhall` is missing, `validate-blueprint` exits with code
4. If any rule above is violated, it exits with code 1 after printing a
report listing each failed check. A clean blueprint exits 0.

## Examples

```sh
# Validate the blueprint in the current directory
seihou validate-blueprint

# Validate a specific blueprint
seihou validate-blueprint ./payments-service
```

## See also

- `seihou new-blueprint` — scaffold a new blueprint
- `seihou validate-module` — the module equivalent of this command
