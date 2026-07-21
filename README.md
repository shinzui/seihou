# Seihou (製法)

**Composable, type-safe project scaffolding and agent workflow authoring.**

Seihou lets you define reusable scaffolding in [Dhall](https://dhall-lang.org/),
compose it with automatic dependency resolution, and generate projects that stay
up to date through an incremental, manifest-tracked workflow. Templates stay
dumb; Dhall does the computing; a stateful manifest makes regeneration safe.

```sh
seihou run haskell-base --var project.name=my-app
```

It supports four authorable artifact kinds:

| Kind | What it is | Run with |
|------|-----------|----------|
| **Module** | A deterministic unit of scaffolding — variables, file-generation steps, dependencies. | `seihou run MODULE` |
| **Recipe** | A named, ordered composition of modules with optional pre-bound parameters. | `seihou run RECIPE` |
| **Blueprint** | Agent-driven scaffolding for open-ended project shapes — a deterministic baseline handed to an AI provider. | `seihou agent run BLUEPRINT` |
| **Prompt** | A reusable agent-session template (code review, release prep, planning) with typed variables and command-derived context. | `seihou prompt run PROMPT` |


## Why Seihou

- **Type-safe by construction.** Modules are Dhall values validated before a
  single file is written — misspelled variables, missing sources, and malformed
  compositions are caught up front.
- **Composable with real dependency resolution.** Modules declare dependencies
  and exports; Seihou topologically orders them and passes variables across the
  boundary.
- **Incremental and safe to re-run.** A `.seihou/manifest.json` records what was
  generated. Re-running performs a three-state diff (manifest / plan / disk),
  detects files you've hand-edited, and never clobbers them without asking.
- **Reversible and upgradable.** Modules can declare `removal` steps and
  versioned `migrations`, so you can cleanly undo a module or move a project
  across module versions.
- **Agent-native.** Blueprints and prompts bring configurable AI providers
  (Claude Code, Codex, Anthropic API, OpenAI API) into the same authoring model.


## Installation

### From Hackage

```sh
cabal install seihou-cli
```

This builds and installs the `seihou` executable. Requires GHC 9.12+ and a
recent `cabal`.

### From source (Nix)

```sh
git clone https://github.com/shinzui/seihou.git
cd seihou
nix develop            # dev shell with the pinned toolchain
cabal build all
cabal run seihou -- --help
```

Optional: enable shell completion so `Tab` completes commands, subcommands, and
flags:

```sh
seihou completions zsh  > ~/.zfunc/_seihou          # zsh
seihou completions bash > ~/.local/share/bash-completion/completions/seihou
seihou completions fish > ~/.config/fish/completions/seihou.fish
```


## Quick Start

```sh
# 1. Initialize Seihou's config directory (~/.config/seihou/). Safe to re-run.
seihou init

# 2. Generate a project from a module (prompts for anything you don't pass).
seihou run haskell-base --var project.name=my-app

# 3. See what was generated and its state.
seihou status
```

New to Seihou? The [Getting Started guide](docs/user/getting-started.md) walks
you from an empty directory through authoring your own module, generating a
project, and detecting changes.


## Concepts at a glance

- **Modules** are directories with a `module.dhall` and a `files/` tree. They
  declare **variables**, **steps** (four generation strategies: `copy`,
  `template`, `dhall-text`, `structured`), **dependencies**, **exports**, and
  optional **prompts**, **commands**, **removal**, and **migrations**. See the
  [Module Authoring Reference](docs/user/module-authoring.md).
- **Variables** resolve from a layered hierarchy — CLI flags, environment,
  local / namespace / context / global config, dependency exports, and module
  defaults — with `seihou vars --explain` to trace provenance. See
  [Configuration & Variables](docs/user/config-and-variables.md).
- **Templates** use `{{var}}` interpolation and inline `{{#if cond}}…{{/if}}`
  conditionals. See the [Templating Reference](docs/user/templating.md).
- **Registries** let one git repository publish many modules, recipes,
  blueprints, and prompts. See
  [Registries & Multi-Module Repositories](docs/user/registries-and-multi-module-repos.md).
- **Blueprints** and **prompts** bring AI providers into scaffolding. See the
  [Blueprints](docs/user/blueprints.md), [Prompts](docs/user/prompts.md), and
  [AI Agent Assistance](docs/user/agent-assistance.md) guides.
- **Blueprint migrations** let a library ship ordered, agent-guided upgrade steps
  that consumers run across an explicit version window, with per-edge receipts
  for resume. See [Blueprint Migrations](docs/user/blueprint-migrations.md).


## Commands

Every command has a full reference under [`docs/cli/`](docs/cli/) and built-in
`seihou COMMAND --help`. Overview:

**Core workflow**

| Command | Description |
|---------|-------------|
| [`init`](docs/cli/init.md) | Create the Seihou config directory (`~/.config/seihou/`). |
| [`run`](docs/cli/run.md) | Apply a module or recipe initially, or deliberately reconfigure it. |
| [`update`](docs/cli/update.md) | Reconcile recorded applications with newer sources while preserving user edits. |
| [`remove`](docs/cli/remove.md) | Reverse an applied module via its declared `removal` steps. |
| [`status`](docs/cli/status.md) | Show applied modules, tracked-file state, and resolved variables. |
| [`diff`](docs/cli/diff.md) | Show files changed on disk since the last generation. |

**Discovery & lifecycle**

| Command | Description |
|---------|-------------|
| [`list`](docs/cli/list.md) | List available modules, recipes, blueprints, and prompts (with `--modules`/`--recipes`/`--blueprints`/`--prompts`/`--repo`/`--tag` filters). |
| [`install`](docs/cli/install.md) | Install artifacts from a git repository or registry. |
| [`browse`](docs/cli/browse.md) | Preview a repository's artifacts without installing. |
| [`outdated`](docs/cli/outdated.md) | Check installed modules for newer versions. |
| [`upgrade`](docs/cli/upgrade.md) | Refresh shared installed-cache sources without reconciling a project. |
| [`migrate`](docs/cli/migrate.md) | Apply a module's declared migrations to the current project. |

**Authoring**

| Command | Description |
|---------|-------------|
| [`new-module`](docs/cli/new-module.md) · [`new-recipe`](docs/cli/new-recipe.md) · [`new-blueprint`](docs/cli/new-blueprint.md) · [`new-prompt`](docs/cli/new-prompt.md) | Scaffold each artifact kind. |
| [`validate-module`](docs/cli/validate-module.md) · [`validate-blueprint`](docs/cli/validate-blueprint.md) · [`validate-prompt`](docs/cli/validate-prompt.md) | Validate an artifact directory (`--lint` for advisories). |
| [`vars`](docs/cli/vars.md) | Inspect variable declarations and resolved values (`--explain`). |
| [`schema-upgrade`](docs/cli/schema-upgrade.md) | Upgrade `module.dhall` files to the current schema. |
| [`registry`](docs/cli/registry.md) | Author `seihou-registry.dhall` files (`sync-versions`, `validate`). |

**Configuration**

| Command | Description |
|---------|-------------|
| [`config`](docs/cli/config.md) | Read/write config across local, namespace, context, and global scopes (`--effective` for the merged view). |
| [`context`](docs/cli/context.md) | Manage the active context (e.g. `work` vs `personal`). |

**AI agent**

| Command | Description |
|---------|-------------|
| [`agent`](docs/cli/agent.md) | AI-assisted workflows: `assist`, `bootstrap`, `setup`, and `run` (blueprints). |
| [`prompt`](docs/cli/prompt.md) | Run a first-class agent-session prompt. |
| [`kit`](docs/cli/kit.md) | Manage Claude Code and Codex skills and subagents. |

**Help & integration**

| Command | Description |
|---------|-------------|
| [`help`](docs/cli/help.md) | Built-in help topics (`seihou help modules`, `seihou help update`, …). |
| [`completions`](docs/cli/completions.md) | Generate Bash/Zsh/Fish completion scripts. |
| [`extension`](docs/cli/extension.md) | Run external `seihou-<name>-extension` executables. |


## Documentation

**Guides** ([`docs/user/`](docs/user/))

- [Getting Started](docs/user/getting-started.md) — end-to-end walkthrough from init to generation.
- [Module Authoring Reference](docs/user/module-authoring.md) — the complete module format, all four strategies, expression language, composition, recipes, removal, migrations.
- [Templating Reference](docs/user/templating.md) — `{{var}}` interpolation and inline conditionals.
- [Configuration & Variables](docs/user/config-and-variables.md) — the resolution hierarchy, scopes, and contexts.
- [Registries & Multi-Module Repositories](docs/user/registries-and-multi-module-repos.md) — publish many artifacts from one repo.
- [Migrations](docs/user/migrations.md) — move projects across module versions.
- [Blueprints](docs/user/blueprints.md) — agent-driven scaffolding.
- [Blueprint Migrations](docs/user/blueprint-migrations.md) — publish and run agent-guided library upgrades.
- [Prompts](docs/user/prompts.md) — reusable agent-session workflows.
- [AI Agent Assistance](docs/user/agent-assistance.md) — configure and run Claude Code, Codex, Anthropic, and OpenAI providers.
- [Changelog](docs/user/CHANGELOG.md) — user-facing release notes.

**Reference** — per-command pages in [`docs/cli/`](docs/cli/).


## Authoring a module

```sh
seihou new-module my-template            # scaffold module.dhall + files/
seihou validate-module ./my-template     # check it is well-formed
seihou run my-template --dry-run --var project.name=test   # preview the plan
```

A module is a `module.dhall` plus a `files/` directory of templates. It declares
variables, generation steps, and dependencies. See the
[Module Authoring Reference](docs/user/module-authoring.md) for the full
specification, and the fixtures under `seihou-core/test/fixtures/` for working
examples of composition, structured output, shell commands, and recipes.


## Building from source

Seihou is a multi-package Cabal workspace built with Nix flakes.

```sh
nix develop            # enter the dev shell
cabal build all        # build every package
cabal run seihou -- --help
cabal test all         # run the test suites
nix flake check        # formatting, module-placement, and CI checks
```

## Project structure

```
seihou/
├── seihou-core/            # Library: module loading, Dhall evaluation, template
│                           # rendering, variable resolution, composition, execution
├── seihou-cli/             # The `seihou` CLI (library + executable + tests)
├── seihou-okf-extension/   # External extension: OKF documentation bundles
├── docs/
│   ├── user/               # User guides and the user-facing changelog
│   ├── cli/                # Per-command reference
│   ├── dev/                # Architecture, design notes, roadmap
│   ├── plans/              # Execution plans (living implementation documents)
│   └── masterplans/        # Multi-plan coordination documents
├── cabal.project           # Multi-package workspace
└── flake.nix               # Nix development environment
```


## License

Seihou is licensed under the BSD-3-Clause license. See [`LICENSE`](LICENSE) for
details.
