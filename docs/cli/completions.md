# seihou completions

Generate shell completion scripts.

## Usage

```
seihou completions <SHELL>
```

## Subcommands

| Shell | Description |
|-------|-------------|
| `bash` | Generate Bash completion script |
| `zsh` | Generate Zsh completion script |
| `fish` | Generate Fish completion script |

## Description

Outputs a completion script for the specified shell. Source it in your shell profile to enable Tab completion for all seihou commands, subcommands, and flags.

## Examples

```sh
# Zsh (add to ~/.zshrc)
eval "$(seihou completions zsh)"

# Bash (add to ~/.bashrc)
eval "$(seihou completions bash)"

# Fish (add to ~/.config/fish/config.fish)
seihou completions fish | source
```
