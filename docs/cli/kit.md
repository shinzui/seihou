# seihou kit

Manage Claude Code and Codex skills and subagents from the `seihou-kit` repository.

## Usage

```
seihou kit [SUBCOMMAND] [OPTIONS]
```

Running `seihou kit` with no subcommand is equivalent to `seihou kit list`.

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `list` | List available skills and subagents (default) |
| `install NAME [--project]` | Install a skill or subagent |
| `update [NAME]` | Pull latest and reinstall (all by default) |
| `uninstall NAME [--project]` | Remove an installed skill or subagent |
| `status` | Show installed items with their scope and provider coverage |

## Options

| Option | Description |
|--------|-------------|
| `--project` | Target project scope instead of user scope (available on `install` and `uninstall`) |

## Description

Seihou Kit installs curated skills and subagents from a remote repository
(`https://github.com/shinzui/seihou-kit`). Install writes provider-native
copies for both Claude Code and Codex. Claude Code content is exposed to
interactive sessions through Seihou's agent directories and `--add-dir`.
Codex content is written to Codex's documented discovery locations, so
`seihou agent --provider codex-cli ...` sessions launched from the same
project can discover project-scoped skills and custom agents.

The kit repository is shallow-cloned to `~/.cache/seihou/kit/` on first use
and refreshed with `git pull --ff-only` on subsequent invocations. A
`kit.json` manifest at the repo root enumerates the skills and agents that
can be installed. If the network is unavailable but a cached clone exists,
commands continue with cached data.

### Scopes

| Scope | Provider | Skills directory | Agents file |
|-------|----------|------------------|-------------|
| **User** (default) | Claude Code | `~/.config/seihou/agents/.claude/skills/<name>/` | `~/.config/seihou/agents/.claude/agents/<name>.md` |
| **User** (default) | Codex | `~/.agents/skills/<name>/` | `~/.codex/agents/<name>.toml` |
| **Project** (`--project`) | Claude Code | `.seihou/agents/.claude/skills/<name>/` | `.seihou/agents/.claude/agents/<name>.md` |
| **Project** (`--project`) | Codex | `.agents/skills/<name>/` | `.codex/agents/<name>.toml` |

User-scope items are available across every project. Project-scope items are
checked in with the project and only activated when running `seihou` from
that project directory.

`seihou kit status` groups installed rows by name, type, and scope, then shows
a `PROVIDERS` column such as `claude,codex`. If one provider copy is missing,
`seihou kit update NAME` repairs the missing copy for any scope where the item
is otherwise installed.

## Examples

```sh
# List everything available in the kit
seihou kit list

# Install a skill to the user scope
seihou kit install review-pr

# Install an agent to the current project
seihou kit install code-reviewer --project

# Refresh the cache and reinstall everything you already have
seihou kit update

# Refresh and reinstall a single item
seihou kit update review-pr

# Show what is currently installed
seihou kit status

# Remove a skill from the user scope
seihou kit uninstall review-pr
```
