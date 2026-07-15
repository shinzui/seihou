# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.4.0.0] - 2026-07-15

### Added

#### First-class prompts
- New first-class **`Prompt`** runnable type: a `prompt.dhall` schema,
  `AgentPrompt` domain types, Dhall decoding, validation, and
  prompt-aware runnable discovery (with blueprint-over-prompt
  precedence) (EP-50, EP-51).
- **Command-derived variables**: `commandVars` resolve shell-command
  output into variables (`FromCommand` provenance), with precedence,
  type coercion, validation, trimming, size limits, conditions, and
  command-failure diagnostics (EP-52).
- **Prompt CLI workflows**: `seihou new-prompt` scaffolds a prompt,
  `seihou prompt run` renders and launches a provider prompt, and
  `seihou validate-prompt` lints prompt definitions (EP-53).
- **Registry integration**: prompts are discovered, installed, browsed,
  and listed alongside modules, recipes, and blueprints, and are covered
  by `seihou registry sync-versions` / `validate` (EP-55).
- **Prompt guidance blocks**: `prompt.dhall` can declare conditional
  Markdown guidance rendered with project context around
  `seihou prompt run` provider prompts. `--debug` prints the complete
  provider prompt, and `validate-prompt` checks guidance titles, bodies,
  and condition references. The agent `bootstrap`/`assist` context prompts
  now teach the full `prompt.dhall` schema (EP-61).
- New `docs/user/prompts.md`, per-command CLI docs, and a
  `seihou help prompts` topic (EP-54).

#### OKF documentation extension
- New **`seihou extension`** host command and an external
  **`seihou-okf-extension`** package that defines the extension contract
  and moves OKF usage out of the CLI core (EP-60).
- OKF **DocModel loader** for Seihou registries: loads modules, recipes,
  blueprints, and prompts with resolved module references (EP-57).
- OKF **rendering** of a `DocModel` to a documentation bundle, with
  concept IDs, frontmatter, module cross-links, and validation (EP-58).
- **`seihou docs`** (via the OKF extension): turn a registry into an OKF
  documentation bundle (EP-59).
- The default Nix package now bundles the OKF extension alongside the CLI
  so `seihou docs` / `seihou extension run okf` work from a single
  install.

#### Validation and variables
- `seihou validate-module --lint` now flags two authoring mistakes: a
  `when` clause or `{{#if}}` conditional that references an undeclared
  variable, and an `Eq <var> <literal>` comparison whose literal type
  cannot match the variable's declared type (EP-49).
- **Defaulted variables coerce to their declared type**: a `bool`
  variable with `default = Some "true"` now resolves to `VBool True`
  (not `VText "true"`), so `Eq` comparisons match from the default
  source. A malformed default (e.g. `Some "treu"` on a bool) now fails
  module load with a clear error (EP-49).

### Changed

- The CLI kit is now built on the shared **`baikai-kit`** package;
  `Seihou.CLI.KitPaths` was removed and `Seihou.CLI.Kit` slimmed
  accordingly.
- Agent dependencies (`baikai`, `baikai-claude`, `baikai-openai`,
  `baikai-kit`) and `okf-core` now resolve from published **Hackage**
  releases; adapted to baikai interactive API changes (`modelId`,
  `AssistantPayload.timestamp :: Maybe UTCTime`).

### Fixed

- The blueprint runner now mounts an existing blueprint `files/` directory for
  interactive Claude Code and Codex sessions and points the agent at its
  absolute path; providers without local directory access receive explicit
  fallback guidance.
- Blueprint `allowedTools` entries are now unioned with the base runner tool
  set, de-duplicated, and passed to the interactive launcher so Claude Code can
  pre-approve the effective set.

### Packaging

- New third package **`seihou-okf-extension`** (BSD-3-Clause, with
  `LICENSE` and Hackage metadata).
- All three packages share version `0.4.0.0`, and intra-repo components
  pin `seihou-core ^>=0.4.0.0`.

## [0.3.0.0] - 2026-06-12

### Added

#### Blueprints (agent-driven scaffolding)
- New first-class **`Blueprint`** runnable type: a `blueprint.dhall`
  schema, Dhall decoder, validator, and run-refusal semantics for
  agent-driven scaffolding that complements modules and recipes
  (EP-29).
- Blueprint authoring and inspection commands: `seihou new-blueprint`
  scaffolds a blueprint and `seihou validate-blueprint` lints it
  (EP-30).
- `seihou agent run BLUEPRINT` parses and executes a blueprint through
  the configured agent provider (EP-31).
- **Applied-blueprint provenance**: a new `AppliedBlueprint` record is
  written to the manifest after an agent run (manifest schema bumped to
  **v3**), and `seihou status` surfaces which blueprint was applied
  (EP-32).
- **Registry support for blueprints**: the `Registry` type and the
  `SingleBlueprint` repository shape gained blueprints; `seihou install`
  and `seihou browse` handle blueprints alongside modules and recipes,
  and `seihou registry sync-versions` / `validate` understand blueprint
  entries (EP-33).
- New `seihou help blueprints` topic and user-guide coverage of
  agent-driven blueprints (EP-34).

#### Agent provider integration (Baikai)
- Agent commands are now routed through a configurable **provider**
  backed by [Baikai](https://hackage.haskell.org/package/baikai): a
  completion facade, configurable provider selection, and interactive
  CLI provider launches. New `baikai`, `baikai-claude`, and
  `baikai-openai` dependencies.
- `seihou kit` installs Codex-compatible kit content, with reduced CLI
  approval prompts for the Codex provider.
- New `seihou help agent` topic and a Baikai-backed agent-configuration
  guide.

#### CLI flags and UX
- `seihou list` gained `--modules`, `--recipes`, and `--blueprints`
  filters to narrow output by kind, and its summary count is now
  kind-aware.

### Changed

- **Migration planner rewritten** as a gap-tolerant window walker:
  migration chains with version gaps are walked more robustly, and the
  walker contract is documented in `docs/cli/migrate.md` and
  `docs/user/migrations.md` (EP-35).
- Agent dependencies now resolve from the published **Hackage** `baikai`
  packages, and the git `streamly` pin tracks the official
  `composewell/streamly` repository.

### Removed

- **Breaking:** removed the `seihou migrate --bump-only` and
  `seihou run --bump-blocked` recovery flags. The rewritten gap-tolerant
  migration planner advances recorded versions through benign
  empty-migration gaps and exhausted partial-chain tails automatically,
  so the manual escape hatches are no longer needed (EP-35).

### Fixed

- `seihou migrate` no longer crashes with
  `getDirectoryContents:openDirStream: does not exist` when a migration
  chain mixes a `MoveFile` op with a `RunCommand` step (e.g.
  `rm -rf <src-dir>`) that removes the source's parent directory before
  `cleanupEmptyDirs` runs. The IO interpreter of
  `Filesystem.RemoveDirectoryIfEmpty` now treats a missing path as a
  no-op, matching the pure interpreter's semantics. On the affected
  chain the manifest had already been rolled back even though the disk
  moves had completed, so a second `seihou migrate` invocation
  succeeded — the fix removes the need for that retry dance.
- Manifests are now written **atomically** (write-to-temp-then-rename),
  avoiding corruption if the process is interrupted mid-write.
- Recipe expansion is now **total** — malformed or cyclic recipes
  surface as structured errors instead of throwing.
- Generation, migration, and removal paths are validated and constrained
  to stay within the project tree, rejecting paths that escape it.
- The `seihou` executable now packages its **embedded source assets**
  (`data/` prompts and `help/` topics) via `extra-source-files`, so the
  Hackage tarball and installed binary carry them.

### Packaging

- Added Hackage metadata (`license`, `license-file`, `author`,
  `maintainer`, `homepage`, `bug-reports`, `category`, `description`)
  and a `LICENSE` (BSD-3-Clause) file to both packages.
- `seihou-cli` now pins `seihou-core ^>=0.3.0.0`.
- Both packages share version `0.3.0.0`.

## [0.2.0.0] - 2026-04-29

### Added

#### Module migrations
- **Module migrations**: a new `migrations` field on `module.dhall` lets
  authors declare file-system operations (`MoveFile`, `MoveDir`,
  `DeleteFile`, `DeleteDir`, `RunCommand`) that move a project's
  working tree from one module version to another. New `seihou migrate
  <module>` command applies the chain to the current project, rewrites
  the manifest's `files` map to reflect new paths, and bumps the
  applied module's recorded version. Supports `--dry-run`, `--force`
  (mirroring `seihou remove` conflict semantics), `--to VERSION`, and
  `--json`. New `seihou help migrations` topic embeds the full
  reference in the binary; new `docs/user/migrations.md` and
  `docs/cli/migrate.md` cover authoring and CLI usage. Schema-upgrade
  detects and adds the `migrations` field on legacy modules.
- `seihou migrate` is self-contained: it fetches the latest module
  before planning so users no longer need a manual `seihou upgrade`
  first. `--no-fetch` opts out for offline/pinned workflows.
- `seihou migrate --commit` / `--commit-message`: stage and commit the
  migration result with an autogenerated or user-supplied message.
- `seihou upgrade --with-migrations` runs migrations against the
  current project for each successfully-upgraded module. Without the
  flag, `seihou upgrade` prints a one-line advisory pointing at
  `seihou migrate <module>` when migrations are pending.
- `seihou run` is migration-aware: refuses to apply when modules have
  partial chains or are blocked, and prints actionable remediation hints.
- `seihou status` renders pending-migration, partial-chain, and blocked
  rows; reports `Pending migrations: N migration(s) pending: a → b`
  under any applied module whose installed copy has advanced past the
  manifest's recorded version.
- **Recovery escape hatches** for migration edge cases:
  - `seihou migrate --bump-only`: refresh the manifest's recorded
    version without applying any operations, for benign empty-migrations
    version gaps.
  - `seihou run --bump-blocked`: bump-through blocked modules in a
    single command when the chain is provably benign.
  - Benign empty-migrations upgrades (versions that declare no
    file-system ops) now proceed silently in `seihou run` and render
    without blocked-language in `seihou status`.
  - Bump-through for exhausted partial-chain tails: when the reachable
    prefix terminates with no further declared edges, `seihou migrate`
    advances the recorded version through the unreachable tail rather
    than leaving the manifest stuck mid-chain.
  - `seihou migrate` falls back to local migrations when an upstream
    fetch drops applicable edges, preventing partial-chain skips.

#### Recipes (module composition presets)
- New `Recipe` type and `recipe.dhall` schema — named, ordered
  compositions of modules with optional pre-bound parameters.
- Recipe discovery, expansion, and validation across local and registry
  sources, with provenance recorded in the manifest and surfaced in
  `seihou status`.
- Recipes integrated into `seihou run`, `seihou list`, `seihou install`,
  and `seihou browse`; new `seihou new-recipe` scaffolds a recipe.
- FZF selector covers recipes alongside modules.

#### Registry tooling
- `seihou registry` authoring command group with `sync-versions` and
  `validate` subcommands. `sync-versions` reads each entry's
  `module.dhall` / `recipe.dhall`, compares against the registry, and
  rewrites `seihou-registry.dhall` with current versions; `--dry-run`
  and `--check` (CI-friendly, exits 1 on drift) supported.
- `seihou registry validate`: structural + strict `version` equality
  check across registry entries, exiting non-zero on any failure, so it
  works as a single CI pre-merge gate. See `docs/cli/registry.md`.
- `seihou browse` and `seihou install` emit per-entry warnings to
  stderr when a multi-module registry has versions out of sync with the
  underlying modules — without blocking the operation.
- Documented `version` field on registry entries in
  `docs/user/registries-and-multi-module-repos.md` and the bootstrap
  prompt.

#### Templating
- Inline `{{#if cond}} … {{/if}}` conditional blocks in the Template
  strategy with unbounded nesting, routed through the standard
  `renderTemplateText` renderer.
- Standalone-block whitespace trim: lines that contain only
  `{{#if}}`/`{{/if}}` tags collapse cleanly without leaving stray
  blank lines.
- Decommissioned the legacy `Seihou.Engine.TemplatePrototype` and
  promoted the production renderer to handle all template paths.
- New consolidated templating reference: `docs/user/templating.md` and
  in-binary `seihou help templating`. Getting-started doc gains a
  `{{#if}}` teaser and a populated run-flags table.
- Written evaluation of Dhall-as-templating with three prototypes
  (split-flake reproduction, dhall-text single-source flake, typed
  dhall-text renderer, inline-conditional template) and a comparison
  doc with recommendation.

#### Composition
- **Parameterized-dep multi-instantiation**: parents can instantiate
  the same dependency multiple times with different parameter sets.
  Threaded `ModuleInstance` through the loader, resolver, and planner;
  introduced `ParentVars` and a manifest v2 schema; `Execute` now
  attributes each `FileRecord` via an ownership map and `seihou status`
  shows parent bindings. Diamond fixtures cover the new behaviour.

#### CLI flags and UX
- `seihou run --confirm-defaults`: walk through each variable resolved
  from a default or from a parent module's export and accept or
  override it interactively. Overridden values are tagged as prompted
  input so they flow into the "save prompted values?" offer.
- `seihou status --check-updates`: surface available registry updates
  alongside the existing status output.
- Schema upgrade detects and injects the new `migrations` field on
  legacy modules.

#### Infrastructure
- Library-first CLI module placement: `seihou-cli` now exposes a
  private `seihou-cli-internal` library (`src/`) with the `seihou`
  executable reduced to `src-exe/` (`Main.hs`, command dispatchers, and
  modules trapped by `optparse-applicative`, `file-embed`, `githash`,
  or `Paths_seihou_cli`). New `nix/check-cli-module-placement.sh`
  enforces the convention via `nix flake check` and the pre-commit
  hook.
- Master-plan seihou module shipped (`agents/skills/master-plan`),
  with skill and spec.

### Fixed

- `seihou migrate` no longer skips partial chains when an upstream
  fetch drops applicable edges (EP-27).
- `seihou outdated` version detection corrected via the new
  library-exposed `VersionCompare` module.
- Use-after-free in `checkSource`: temp-dir lifetime extended past
  consumer reads.
- Nix CLI test sandbox now provides `git` so `seihou-cli` tests run
  under `nix flake check`.

### Changed

- Pinned `seihou-schema` URL bumped to the published Migration commit;
  `mori-schema` upgraded to `9b1d6ee`.
- Both packages share version `0.2.0.0`.

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

[Unreleased]: https://github.com/shinzui/seihou/compare/v0.4.0.0...HEAD
[0.4.0.0]: https://github.com/shinzui/seihou/compare/v0.3.0.0...v0.4.0.0
[0.3.0.0]: https://github.com/shinzui/seihou/compare/v0.2.0.0...v0.3.0.0
[0.2.0.0]: https://github.com/shinzui/seihou/compare/v0.1.0.0...v0.2.0.0
[0.1.0.0]: https://github.com/shinzui/seihou/releases/tag/v0.1.0.0
