# seihou kit

Manage Claude Code skills and subagents from the `seihou-kit` repository.

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
| `status` | Show installed items with their scope |

## Options

| Option | Description |
|--------|-------------|
| `--project` | Target project scope (`.seihou/agents/`) instead of user scope (available on `install` and `uninstall`) |

## Description

Seihou Kit installs curated Claude Code skills and subagents from a remote
repository (`https://github.com/shinzui/seihou-kit`). Installed content is
automatically exposed to the assist and bootstrap agents via `--add-dir`, so
the skills and agents become available in `seihou agent assist`, `seihou
agent bootstrap`, and `seihou agent setup` sessions.

The kit repository is shallow-cloned to `~/.cache/seihou/kit/` on first use
and refreshed with `git pull --ff-only` on subsequent invocations. A
`kit.json` manifest at the repo root enumerates the skills and agents that
can be installed. If the network is unavailable but a cached clone exists,
commands continue with cached data.

### Scopes

| Scope | Skills directory | Agents file |
|-------|------------------|-------------|
| **User** (default) | `~/.config/seihou/agents/.claude/skills/<name>/` | `~/.config/seihou/agents/.claude/agents/<name>.md` |
| **Project** (`--project`) | `.seihou/agents/.claude/skills/<name>/` | `.seihou/agents/.claude/agents/<name>.md` |

User-scope items are available across every project. Project-scope items are
checked in with the project and only activated when running `seihou` from
that project directory.

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
