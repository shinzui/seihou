# Configuration and Variable Resolution

This guide explains how Seihou resolves variable values from multiple sources, how to set up configuration files so variables are automatically resolved, and how to inspect and debug the resolution process.

For an introduction to modules and variables, see the [Getting Started Guide](getting-started.md). For the full variable declaration format, see the [Module Authoring Reference](module-authoring.md).


## The resolution hierarchy

When a module declares a variable (e.g., `project.name`), Seihou looks for a value in nine sources, in order. The first source that provides a value wins:

| Priority | Source | How to set it |
|----------|--------|---------------|
| 1 (highest) | CLI flags | `--var project.name=my-app` |
| 2 | Environment variables | `SEIHOU_VAR_PROJECT_NAME=my-app` |
| 3 | Local project config | `.seihou/config.dhall` in the current directory |
| 4 | Namespace config | `~/.config/seihou/namespaces/<ns>/config.dhall` |
| 5 | Context config | `~/.config/seihou/contexts/<ctx>/config.dhall` |
| 6 | Global config | `~/.config/seihou/config.dhall` |
| 7 | Parent bindings | Parameterized dependency `depVars` from parent module |
| 8 | Module defaults | `default = Some "value"` in `module.dhall` |
| 9 (lowest) | Interactive prompt | User enters value when prompted |

If no source provides a value:

- **Required variables** (`required = True`) cause an error in non-interactive mode, or trigger an interactive prompt if a TTY is available.
- **Optional variables** (`required = False`) are silently omitted. Steps can test for their presence using `IsSet` in `when` conditions.

### Reviewing defaults interactively

Pass `--confirm-defaults` to `seihou run` to step through every variable whose value would otherwise come from a module default (priority 8) or a parent binding (priority 7). Each variable is displayed with its default in brackets; press Enter to accept, or type a new value to override. Overridden values are tagged as prompted input, so they flow into the "save prompted values?" offer at the end of the run.

The flag is a no-op in non-interactive mode (no TTY on stdin).


## Setting up configuration files

Configuration files are Dhall records mapping variable names to string values. You manage them with the `seihou config` command.

### Global config

Global config values apply to every project. Use this for personal defaults like your name, preferred license, or common tool versions:

```sh
seihou config set author.name "Jane Doe" --global
seihou config set license MIT --global
seihou config set haskell.ghc 9.12.2 --global
```

These are stored in `~/.config/seihou/config.dhall`. Any module that declares an `author.name`, `license`, or `haskell.ghc` variable will automatically pick up these values.

### Local config

Local config values are specific to a project. They live in `.seihou/config.dhall` in the project directory and override global values for the same key:

```sh
seihou config set project.name my-app
seihou config set license Apache-2.0
```

Use local config for project-specific values that you don't want to pass via `--var` every time you re-run generation.

### Namespace config

Namespace config sits between local and global. It groups values by domain — for example, all Haskell-related defaults:

```sh
seihou config set haskell.ghc 9.12.2 --namespace haskell
seihou config set haskell.cabal-version 3.0 --namespace haskell
```

These are stored in `~/.config/seihou/namespaces/haskell/config.dhall`. When you run a module, Seihou derives the namespace from the module name (the part before the first hyphen). For a module named `haskell-base`, the namespace is `haskell`. You can override this with `--namespace`:

```sh
seihou run my-module --namespace haskell
```

### Context config

Context config lets you maintain separate identities or settings for different environments — for example, "work" vs "personal". Context values sit between namespace and global in the resolution hierarchy.

```sh
seihou config set author.name "Jane Doe" --context personal
seihou config set author.name "Jane Smith" --context work
seihou config set author.email "jane@work.com" --context work
```

These are stored in `~/.config/seihou/contexts/<name>/config.dhall`. Seihou resolves the active context from four sources (first match wins):

1. `--context` CLI flag on `run`, `vars`, or `config`
2. `SEIHOU_CONTEXT` environment variable
3. `.seihou/context` file in the current project directory
4. `~/.config/seihou/default-context` file (global default)

Manage contexts with the `seihou context` command:

```sh
seihou context show                  # show active context and its source
seihou context set work              # set project-level context (.seihou/context)
seihou context default personal      # set global default context
seihou context clear                 # remove project-level context
seihou context clear-default         # remove global default context
```

Or pass `--context` to any command that resolves variables:

```sh
seihou run my-module --var project.name=app --context work
seihou vars my-module --explain --context work
```


## Environment variables

Any declared variable can be set via an environment variable. The mapping is:

1. Prefix with `SEIHOU_VAR_`
2. Uppercase the name
3. Replace `.` with `_`

Examples:

| Variable | Environment variable |
|----------|---------------------|
| `project.name` | `SEIHOU_VAR_PROJECT_NAME` |
| `license` | `SEIHOU_VAR_LICENSE` |
| `haskell.ghc` | `SEIHOU_VAR_HASKELL_GHC` |

Environment variables override all config layers but are overridden by `--var` CLI flags. This is useful for CI/CD pipelines:

```sh
export SEIHOU_VAR_PROJECT_NAME=my-app
seihou run haskell-base
```

## Agent provider defaults

`seihou agent` resolves its AI provider separately from module variables. These keys configure the default provider and model used by `seihou agent assist`, `seihou agent bootstrap`, `seihou agent setup`, and `seihou agent run`:

| Setting | Environment variable | Accepted values |
|---------|----------------------|-----------------|
| `agent.provider` | `SEIHOU_AGENT_PROVIDER` | `claude-cli`, `codex-cli`, `anthropic`, `openai` |
| `agent.model` | `SEIHOU_AGENT_MODEL` | Any provider-specific model name or alias |

Agent provider resolution uses this order, with the first non-blank value winning:

1. Subcommand CLI flag: `seihou agent assist --provider ... --model ...`
2. Parent CLI flag: `seihou agent --provider ... --model ... assist`
3. Environment variables: `SEIHOU_AGENT_PROVIDER`, `SEIHOU_AGENT_MODEL`
4. Local project config: `.seihou/config.dhall`
5. Global config: `~/.config/seihou/config.dhall`
6. Built-in defaults: provider `claude-cli`, no explicit model

Namespace config, context config, parent bindings, module defaults, and interactive variable prompts are not part of agent provider resolution. They still apply to blueprint variables and module variables that `seihou agent run` resolves before rendering its prompt.

Use global config for personal provider defaults:

```sh
seihou config set agent.provider codex-cli --global
seihou config set agent.model gpt-5 --global
seihou agent assist "create a module"
```

Use parent CLI flags for a one-off override:

```sh
seihou agent --provider claude-cli --model sonnet setup "add nix"
```

Use environment variables for temporary shell sessions or CI:

```sh
export SEIHOU_AGENT_PROVIDER=openai
export SEIHOU_AGENT_MODEL=gpt-4o-mini
seihou agent --debug assist "inspect the prompt"
```

The `claude-cli` provider starts an interactive local Claude Code session and the `codex-cli` provider starts an interactive local Codex session. Seihou launches Codex with workspace-write sandboxing and on-request approvals so routine project commands do not require confirmation for every step. The `anthropic` and `openai` providers call API endpoints through Baikai and read API keys from the standard provider environment variables.


## Inspecting resolved variables

### View declarations

To see what variables a module declares (without resolving them):

```sh
seihou vars my-module
```

Output:

```
Variables for my-module:

  project.name     = (required, no default)
  project.version  = "0.1.0.0"
  license          = "MIT"
  author.name      = (optional, no default)
```

### View resolved values with provenance

To see how variables resolve from the config hierarchy, use `--explain`:

```sh
seihou vars my-module --explain --var project.name=my-app
```

Output:

```
Variables for my-module:

  project.name     = "my-app"        [--var]
  project.version  = "0.1.0.0"       [default]
  license          = "MIT"            [global config]
  author.name      = "Jane Doe"      [global config]
```

Each variable shows where its value came from in brackets. The `--explain` command resolves the full module composition (including dependencies), so exported variables from dependencies are visible too.

### View the effective config

To see the merged config across all scopes:

```sh
seihou config list --effective
```

Output:

```
Effective config:
  author.name  = Jane Doe    [global]
  author.email = jane@work.com [context: work]
  license      = MIT          [global]
  project.name = my-app       [local]
```

Add `--namespace` or `--context` to include those scopes in the merge:

```sh
seihou config list --effective --namespace haskell
seihou config list --effective --context work
```

### Managing config values

```sh
# Set a value
seihou config set license MIT --global

# Get a value
seihou config get license --global

# Remove a value
seihou config unset license --global

# List values in a scope
seihou config list --global
seihou config list --namespace haskell
seihou config list --context work
seihou config list              # shows local + global
```


## Diagnostics

Seihou provides two diagnostic hints to help you catch mistakes:

### Unused config keys

If a config file contains a key that doesn't match any declared variable in the composition, Seihou warns you. This catches typos — for example, setting `auther.name` instead of `author.name`:

```
Warning: Config keys not matching any declared variable: auther.name
```

This warning appears during `seihou run`. It does not block execution.

### Unresolved optional variables

When using `seihou vars --explain`, optional variables that have no value from any source are listed at the end:

```
Unresolved optional variables:
  author.email
  ci.provider
```

This tells you which optional variables you might want to configure. Set them in your global or local config to make them available.


## Precedence examples

### Example 1: Global defaults, local overrides

```sh
# Set global defaults
seihou config set license MIT --global
seihou config set author.name "Jane Doe" --global

# Override license for this project
seihou config set license Apache-2.0

# Result: license=Apache-2.0 (local), author.name="Jane Doe" (global)
seihou vars my-module --explain --var project.name=test
```

### Example 2: CLI overrides everything

```sh
seihou config set license MIT --global

# CLI flag wins over global config
seihou run my-module --var project.name=app --var license=BSD-3-Clause
# license resolves to BSD-3-Clause from CLI, not MIT from global
```

### Example 3: Environment for CI

```sh
# In a CI pipeline, set variables via environment
export SEIHOU_VAR_PROJECT_NAME=my-app
export SEIHOU_VAR_LICENSE=MIT

# No --var flags needed
seihou run haskell-base --force
```

### Example 4: Namespace config for language defaults

```sh
# Set Haskell-specific defaults
seihou config set haskell.ghc 9.12.2 --namespace haskell
seihou config set haskell.cabal-version 3.0 --namespace haskell

# These apply automatically to haskell-* modules
seihou run haskell-base --var project.name=my-app
# haskell.ghc resolves to 9.12.2 from namespace config
```

### Example 5: Context config for work/personal

```sh
# Set up work and personal contexts
seihou config set author.name "Jane Smith" --context work
seihou config set author.email "jane@company.com" --context work
seihou config set author.name "Jane Doe" --context personal
seihou config set author.email "jane@home.dev" --context personal

# Set a global default context
seihou context default personal

# Now author.name resolves to "Jane Doe" from the personal context
seihou run my-module --var project.name=side-project

# Override for a work project
seihou run my-module --var project.name=work-app --context work
# author.name resolves to "Jane Smith" from the work context
```


## Cross-module variable sharing

When modules declare dependencies, variables can flow between them via **exports**. A module can export variables it declares, making them visible to dependent modules:

```dhall
-- In haskell-base/module.dhall:
, exports = [ { var = "project.name", alias = None Text } ]
```

When another module depends on `haskell-base` and declares its own `project.name` variable, the exported value acts as a default — lower priority than CLI/env/config, but higher than the module's own default.

Variables exported from a dependency are also visible in `seihou vars --explain` for the dependent module, since explain mode resolves the full composition.

For the complete export mechanism, including aliasing and visibility rules, see the [Module Authoring Reference](module-authoring.md).


## Saving prompted values

When you run a module interactively and answer prompts for variable values, Seihou offers to save those answers to the local project config (`.seihou/config.dhall`) so you don't have to re-enter them on subsequent runs.

After a successful run, if any variables were resolved via interactive prompts, you'll see:

```
Save prompted values to .seihou/config.dhall?

  project.name = "my-app"
  license      = "MIT"

Save? [Y/n]
```

If you confirm, the values are written to `.seihou/config.dhall`. On the next run, they'll be picked up automatically at priority 3 (local config) and the prompts won't appear.

Values already present in local config with the same value are not shown — only new or changed values are offered for saving. If a prompted value would overwrite an existing config value, the display shows what it would replace:

```
  project.name = "new-app"  (overwrites current: "old-app")
```

### Controlling save behavior with flags

You can control this behavior with CLI flags:

- `--save-prompted` — Save prompted values automatically without asking. Useful for scripted workflows.
- `--no-save-prompted` — Suppress the save offer entirely. The run proceeds normally but prompted values are not persisted.

```sh
# Auto-save without confirmation
seihou run my-module --save-prompted

# Never offer to save
seihou run my-module --no-save-prompted
```

When neither flag is given, Seihou asks interactively (the default). In non-interactive mode (no TTY), the save offer is silently skipped.

### Inspecting and removing saved values

Saved values are regular local config entries. You can manage them with the `seihou config` command:

```sh
# View what's saved
seihou config list

# Remove a saved value (next run will prompt again)
seihou config unset project.name

# Verify provenance
seihou vars my-module --explain
# Shows [local config] for saved values instead of [prompt]
```
