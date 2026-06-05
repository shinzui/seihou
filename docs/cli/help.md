# seihou help

Show help for commands and topics.

## Usage

```
seihou help [TOPIC]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `TOPIC` | No | Help topic to display. If omitted, lists available topics. |

## Available Topics

| Topic | Description |
|-------|-------------|
| `agent` | Configurable AI assistance commands |
| `modules` | How Seihou modules work |
| `variables` | Variable declaration, resolution, and overrides |
| `contexts` | Using contexts for environment-specific config |
| `config` | Config scopes, reading, and writing values |
| `git-repository` | Sharing and installing items from git |
| `kit` | Manage Claude Code and Codex skills and subagents |
| `migrations` | Migrating a project between module versions |
| `templating` | Placeholder substitution, `{{#if}}` blocks, and patterns |

## Examples

```sh
# List available topics
seihou help

# Read about variables
seihou help variables

# Read about agent providers and commands
seihou help agent
```
