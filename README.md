# Seihou (製法)

Composable, type-safe project scaffolding and agent workflow authoring. Define reusable modules in Dhall, compose them with dependency resolution, and generate projects with incremental updates. Four authorable artifact kinds are supported: deterministic *modules*, named compositions called *recipes*, agent-driven *blueprints* for open-ended scaffolding, and reusable *prompts* for agent-session workflows.

## Quick Start

```sh
# Initialize Seihou configuration
seihou init

# Generate a project from a module
seihou run haskell-base --var project.name=my-app

# Check what was generated
seihou status
```

## Commands

### `seihou init`

```
seihou init
```

Creates the Seihou configuration directory at `~/.config/seihou/` with subdirectories for user modules and installed modules. Safe to run multiple times.

### `seihou run`

```
seihou run MODULE [-m MODULE...] [--var KEY=VALUE...] [--dry-run] [--diff] [--force] [--no-commands]
```

Loads the specified module and its dependencies, resolves variables, compiles a generation plan, and executes it in the current directory.

| Flag | Description |
|------|-------------|
| `-m, --module MODULE` | Additional module to compose (repeatable) |
| `--var KEY=VALUE` | Variable override (repeatable) |
| `--dry-run` | Show plan without executing |
| `--diff` | Show diff against current disk state |
| `--force` | Auto-resolve conflicts |
| `--no-commands` | Skip shell command steps |

```sh
# Compose two modules together
seihou run haskell-base -m nix-flake --var project.name=my-app

# Preview what would happen
seihou run haskell-base --dry-run
```

### `seihou vars`

```
seihou vars MODULE [--explain] [--var KEY=VALUE...]
```

Lists variable declarations for a module. With `--explain`, shows resolved values and their provenance (default, CLI override, environment, or dependency export).

```sh
seihou vars haskell-base --explain --var project.name=my-app
```

### `seihou install`

```
seihou install GIT-URL [--name NAME] [--module NAME...] [--all]
```

Clones a git repository and installs a module, recipe, blueprint, prompt, or selected entries from a registry to `~/.config/seihou/installed/<name>/`. The name defaults to the repository name for single-artifact repositories.

### `seihou status`

```
seihou status
```

Reads `.seihou/manifest.json` in the current directory and displays applied modules, tracked files, and resolved variable values.

### `seihou new-module`

```
seihou new-module NAME [--path DIR]
```

Scaffolds a new module directory with a boilerplate `module.dhall` and an example template. Module names must match `[a-z][a-z0-9-]*`. The output directory defaults to `./<name>/`.

### `seihou validate-module`

```
seihou validate-module [PATH]
```

Validates that a module directory is well-formed: `module.dhall` evaluates, variable names are unique, prompts reference declared variables, step source files exist, and exports reference declared variables. PATH defaults to the current directory.

### `seihou diff`

```
seihou diff
```

Shows files that have changed since the last generation by comparing current content against the manifest.

### `seihou list`

```
seihou list
```

Lists available modules, recipes, blueprints, and prompts across the three search paths (project-local, user, installed). Use `--modules`, `--recipes`, `--blueprints`, or `--prompts` to restrict by kind.

### `seihou prompt`

```
seihou prompt run PROMPT [USER-PROMPT] [--var KEY=VALUE...] [--debug]
```

Resolves a reusable prompt artifact, runs command-derived variables, renders the prompt body, and launches the configured Claude Code, Codex, Anthropic, or OpenAI provider. `--debug` prints the rendered prompt without contacting a provider.

### `seihou config`

```
seihou config COMMAND [-g|--global] [-n|--namespace NS]
```

Manage configuration values. Subcommands: `set KEY VALUE`, `get KEY`, `unset KEY`, `list`. Default scope is local (`.seihou/config.dhall`). Use `--global` or `--namespace NS` for other scopes.

## Documentation

- [Getting Started Guide](docs/user/getting-started.md) — End-to-end walkthrough from initialization to project generation
- [Module Authoring Reference](docs/user/module-authoring.md) — Complete module format, strategies, variables, composition
- [Blueprints Guide](docs/user/blueprints.md) — Agent-driven scaffolding for open-ended project shapes
- [Prompts Guide](docs/user/prompts.md) — Reusable agent-session templates with variables and command-derived context
- [Agent Assistance Guide](docs/user/agent-assistance.md) — Configuring and running Claude Code, Codex, Anthropic, and OpenAI providers

## Module Authoring

A Seihou module is a directory containing a `module.dhall` file and a `files/` directory with templates. Modules declare variables, define generation steps (copy, template, dhall-text, structured), and can depend on other modules.

```sh
# Create a new module
seihou new-module my-template

# Validate it
seihou validate-module ./my-template

# Test it
seihou run my-template --dry-run --var project.name=test
```

See the [Module Authoring Reference](docs/user/module-authoring.md) for the complete specification.

- **Blueprints** (`seihou agent run BLUEPRINT`) — agent-driven scaffolding for open-ended project shapes. See the [Blueprints Guide](docs/user/blueprints.md), [`seihou new-blueprint`](docs/cli/new-blueprint.md), [`seihou validate-blueprint`](docs/cli/validate-blueprint.md), and [`seihou agent`](docs/cli/agent.md).
- **Prompts** (`seihou prompt run PROMPT`) — reusable agent-session templates for workflows such as code review, release preparation, and planning. See the [Prompts Guide](docs/user/prompts.md), [`seihou new-prompt`](docs/cli/new-prompt.md), [`seihou validate-prompt`](docs/cli/validate-prompt.md), and [`seihou prompt`](docs/cli/prompt.md).

## Building from Source

Seihou uses Nix flakes for its development environment and Cabal for building.

```sh
# Enter the dev shell
nix develop

# Build everything
cabal build all

# Run the CLI
cabal run seihou -- --help

# Run tests
cabal test all
```

## Project Structure

```
seihou/
├── seihou-core/       # Library: module loading, Dhall evaluation, template
│                      # rendering, variable resolution, composition, execution
├── seihou-cli/        # Executable: CLI commands and handlers
├── docs/
│   ├── user/          # User guides and release-facing changelog
│   ├── cli/           # Command reference
│   ├── dev/           # Architecture, design notes, roadmap
│   └── plans/         # Execution plans (living implementation documents)
├── cabal.project      # Multi-package workspace
└── flake.nix          # Nix development environment
```

## License

Seihou is licensed under the BSD-3-Clause license. See `LICENSE` for details.
