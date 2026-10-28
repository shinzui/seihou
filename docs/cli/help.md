# seihou help

List conceptual help topics or read one topic. For exact command flags use
`seihou COMMAND --help`; run `seihou --help` for the command tree.

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
| `blueprints` | Agent-driven project blueprints |
| `modules` | How Seihou modules work |
| `variables` | Variable declaration, resolution, and overrides |
| `contexts` | Using contexts for environment-specific config |
| `config` | Config scopes, reading, and writing values |
| `git-repository` | Sharing and installing items from git |
| `kit` | Manage Claude Code and Codex skills and subagents |
| `manifest` | What .seihou/manifest.json records and how to upgrade it |
| `migrations` | Migrating a project between module versions |
| `prompts` | Reusable agent-session prompt artifacts |
| `templating` | Placeholder substitution, `{{#if}}` blocks, and patterns |
| `update` | Safely update recorded project applications |
| `workflow` | Choose commands for generation, updates, and recovery |
| `sync` | Restore ignored directory links in clones and worktrees |
| `recipes` | Compose existing modules into one named application |
| `registry` | Publish and validate multi-artifact repository metadata |
| `extensions` | Run external extensions and find their help |

## Command coverage

Every public top-level command belongs to a topic. This table is checked by
`just audit-cli-docs`; update it when a command or topic is added.

| Topic | Commands |
|-------|----------|
| `workflow` | `init`, `run`, `remove`, `status`, `diff`, `help`, `completions` |
| `modules` | `new-module`, `validate-module`, `schema-upgrade`, `list` |
| `recipes` | `new-recipe`, `validate-recipe` |
| `variables` | `vars` |
| `contexts` | `context` |
| `config` | `config` |
| `git-repository` | `install`, `browse`, `outdated`, `upgrade` |
| `update` | `update` |
| `sync` | `sync` |
| `manifest` | `manifest` |
| `migrations` | `migrate` |
| `blueprints` | `new-blueprint`, `validate-blueprint` |
| `prompts` | `prompt`, `new-prompt`, `validate-prompt` |
| `agent` | `agent` |
| `kit` | `kit` |
| `registry` | `registry` |
| `extensions` | `extension` |

## Examples

```sh
# List available topics
seihou help

# Choose the right workflow
seihou help workflow

# Restore checkout links in a clone or worktree
seihou help sync

# Read about variables
seihou help variables

# Read about agent providers and commands
seihou help agent

# Keep a recorded project current while preserving user edits
seihou help update
```
