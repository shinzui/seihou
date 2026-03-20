# seihou context

Manage the active context (work, personal, etc.).

## Usage

```
seihou context <SUBCOMMAND>
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `show` | Show the active context and its source |
| `set [NAME]` | Set the project context (`.seihou/context`). Omit NAME for fzf picker. |
| `default NAME` | Set the global default context (`~/.config/seihou/default-context`) |
| `clear` | Remove the project context file |
| `clear-default` | Remove the global default context |

## Description

Contexts allow variables like `user.email` to resolve differently depending on the active context (e.g., "work" vs "personal").

Context config files live at `~/.config/seihou/contexts/<name>/config.dhall`.

The active context is determined by (in priority order):

1. `SEIHOU_CONTEXT` environment variable
2. Project file `.seihou/context`
3. Global default `~/.config/seihou/default-context`

## Examples

```sh
# Show current context
seihou context show

# Set project context
seihou context set work

# Set global default
seihou context default personal

# Clear project context
seihou context clear
```
