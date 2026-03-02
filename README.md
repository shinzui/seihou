# Seihou (製法)

Composable, type-safe project scaffolding. Define reusable modules in Dhall, compose them with dependency resolution, and generate projects with incremental updates.

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
seihou install GIT-URL [--name NAME]
```

Clones a git repository, validates its `module.dhall`, and installs it to `~/.config/seihou/installed/<name>/`. The module name defaults to the repository name.

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

## Module Authoring

A Seihou module is a directory containing a `module.dhall` file and a `files/` directory with templates. Modules declare variables, define generation steps (copy, template, dhall-text), and can depend on other modules.

```sh
# Create a new module
seihou new-module my-template

# Validate it
seihou validate-module ./my-template

# Test it
seihou run my-template --dry-run --var project.name=test
```

See `docs/dev/design/proposed/module-system.md` for the full module specification.

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
│   ├── dev/           # Architecture, design specs, roadmap
│   └── plans/         # Execution plans (living implementation documents)
├── cabal.project      # Multi-package workspace
└── flake.nix          # Nix development environment
```

## License

See LICENSE file.
