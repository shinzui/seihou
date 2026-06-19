# seihou validate-prompt

Validate a prompt for correctness.

## Usage

```text
seihou validate-prompt [PATH] [OPTIONS]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `PATH` | No | Prompt directory path (defaults to current directory) |

## Options

| Option | Description |
|--------|-------------|
| `--lint` | Reserved for future advisory lint warnings (currently a no-op) |

## Description

Checks prompt well-formedness:

- `prompt.dhall` exists and evaluates successfully, including any
  `./prompt.md as Text` import.
- Prompt name matches `[a-z][a-z0-9-]*`.
- Prompt version, if specified, is non-empty.
- Prompt body is non-empty after trimming.
- Typed variable names are unique.
- Interactive prompts reference declared typed variables.
- Command-derived variables are safe and well-formed.
- Guidance titles and bodies are non-empty.
- Guidance `when` expressions reference declared typed or command-derived
  variables.
- Every entry in the `files` list resolves under the prompt's `files/`
  directory.
- Tags and `allowedTools` entries are non-empty.

If `prompt.dhall` is missing, `validate-prompt` exits with code 4. If any rule
above is violated, it exits with code 1 after printing the failed checks. A
clean prompt exits 0.

## Examples

```sh
# Validate the prompt in the current directory
seihou validate-prompt

# Validate a specific prompt
seihou validate-prompt ./review-changes
```

## See Also

- [First-Class Prompts](../user/prompts.md)
- [`seihou new-prompt`](new-prompt.md)
- [`seihou prompt`](prompt.md)
