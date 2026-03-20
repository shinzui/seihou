# seihou agent

AI-powered agent commands.

## Usage

```
seihou agent <SUBCOMMAND> [OPTIONS]
```

## Options

| Option | Description |
|--------|-------------|
| `--debug` | Print the resolved system prompt and exit |

## Subcommands

### agent assist

Launch an AI-assisted template authoring session.

```
seihou agent assist [PROMPT]
```

Launches an interactive Claude Code session for creating and modifying Seihou modules. The agent gathers context about the current directory (existing modules, manifest state, available modules) and can run `new-module`, `validate-module`, `run --dry-run`, `vars`, `list`, git commands, and read/write files.

### agent bootstrap

Bootstrap a new module or multi-module repository.

```
seihou agent bootstrap [PROMPT] [OPTIONS]
```

| Option | Description |
|--------|-------------|
| `--repo` | Bootstrap a multi-module repository with registry |

Guides you through creating a complete Seihou module from scratch — defining variables, writing templates, setting up prompts, and validating the result. With `--repo`, creates a multi-module repository with `seihou-registry.dhall`.

### agent setup

Guided project setup: configure, run, and commit.

```
seihou agent setup [PROMPT]
```

Guides you through using a Seihou module: selecting a module, configuring variables and context, running the module to generate files, verifying output, and committing changes to git.

## Requirements

Requires the `claude` CLI to be installed. Each subcommand launches an interactive Claude session pre-configured with context about the current directory.
