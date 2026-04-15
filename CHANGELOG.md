# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.1.0.0] - 2026-04-15

Initial public release of seihou — a composable, type-safe project scaffolding
system driven by Dhall modules, with stateful manifests and incremental
regeneration.

### Added

#### Core pipeline
- **Dhall module loading**: module discovery, validation, decoders, and
  expression evaluation with graceful schema evolution.
- **Variable resolution**: six-layer resolution (defaults, module, repo config,
  user config, context, CLI) with context-aware selection (work/personal),
  composition-aware `--explain`, and variable exports for cross-module scoping.
- **Generation strategies**: `Copy`, `Template`, `DhallText`, and `Structured`
  strategies, plus text patching with `Section` and `PatchOp` (including
  `AppendLineIfAbsent` for idempotent line-level patching).
- **Composition and layering**: module composition with declared dependencies,
  topological ordering, parameterized dependencies for parent-to-child variable
  passing, and intelligent composition merge for text and structured files.
- **Plan compilation and execution**: filesystem execution with shell command
  hooks, `{{var}}` interpolation in commands, and structured error propagation.
- **Manifest tracking**: stateful `.seihou/manifest.json` for incrementality,
  three-state diff engine (manifest / plan / disk), and scoped orphan detection
  that preserves files and variables across independent module runs.
- **Interactive conflict resolution**: per-file conflict prompts during
  `seihou run` with TTY input handling.
- **First-class module removal**: reversible `seihou remove` backed by declared
  removal steps and a step-based removal engine.

#### Module system
- **Module versions**: required version field at validation time, version
  comparison via a dedicated `Version` type, `seihou outdated`, and
  `seihou upgrade` with support for upgrading unversioned modules.
- **Schema evolution**: `seihou-schema` git submodule, `SchemaVersion` module,
  schema-import-based modules, `seihou schema-upgrade` command, and
  `MissingSchemaImport` detection and injection.

#### CLI commands
- `seihou init` — initialize a new project
- `seihou run` — apply modules, with `--commit` for AI-generated commit
  messages, colored dry-run preview, and interactive conflict resolution
- `seihou vars` — show resolved variables with composition-aware `--explain`
- `seihou install` — install modules, with URL history and FZF selection
- `seihou browse` — inspect remote registries
- `seihou list` — list installed modules with `--repo` and `--tag` filtering
- `seihou status` — show file state classification and module versions
- `seihou diff` — compare manifest vs. disk
- `seihou validate-module` — structured diagnostics and lint checks
- `seihou new-module` — scaffold a new module
- `seihou config` — `set`, `get`, `list` (with `--effective`), `unset`
- `seihou context` — manage active context
- `seihou remove` — reversible module removal
- `seihou upgrade` / `seihou outdated` — module version management
- `seihou schema-upgrade` — upgrade modules to the latest schema
- `seihou agent bootstrap` / `agent assist` / `agent setup` — agent workflows
- `seihou help topics` — embedded help topics

#### Registries
- Multi-module registry support with discovery and validation.
- Registry metadata types, Dhall decoders, and registry origin in `seihou list`.

#### Configuration and prompts
- Config file layering and dedicated `ConfigWriter` effect with IO and pure
  interpreters.
- Interactive prompts with default values, optional variable handling, and
  `save-prompted` to persist answers to local config.

#### DX
- Shell completion for Bash, Zsh, and Fish.
- FZF integration for module, registry, and context selection.
- `Logger` effect with `--verbose` flag wired through all CLI handlers.
- Version with git SHA in CLI output.
- Help topics subcommand and grouped `--help` output.

### Infrastructure
- Multi-package cabal workspace: `seihou-core` (library) and `seihou-cli`
  (executable and test suite).
- Nix flakes build with `haskell-nix` for GHC 9.12 tool patches, and schema
  submodule support.
- Integration and golden tests for scaffold, composition merge, text patching,
  structured merge, removal engine, and CLI output formats.

[Unreleased]: https://github.com/shinzui/seihou/compare/v0.1.0.0...HEAD
[0.1.0.0]: https://github.com/shinzui/seihou/releases/tag/v0.1.0.0
