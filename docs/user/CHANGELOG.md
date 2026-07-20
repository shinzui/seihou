# Changelog

User-facing release notes for Seihou. This is a curated summary of
user-visible changes; the [full engineering changelog](../../CHANGELOG.md) at
the repository root records every change, including internal refactors and
packaging.

Versions follow the Haskell [PVP](https://pvp.haskell.org/) (`A.B.C.D`). All
packages in the workspace share a single version.

## Unreleased

### Added

- **Deterministic CLI provider defaults.** When no model is configured, the
  local CLI providers now pin a specific model instead of deferring to the
  ambient `claude` / `codex` session: `claude-cli` defaults to `claude-opus-4-8`
  and `codex-cli` defaults to `gpt-5.6-terra`. Seihou always passes the model
  explicitly, so an agent run never accidentally inherits a different model
  another session selected. Override with `--model` or an `agent.model` /
  `agent.<command>.model` config key.

- **Per-command agent provider and model.** Each agent command can now use a
  different provider and model through configuration. Set
  `agent.<command>.provider` / `agent.<command>.model` (for `assist`,
  `bootstrap`, `setup`, `run`, or `prompt-run`) to override the shared
  `agent.provider` / `agent.model` defaults for that command only. Resolution
  is hierarchical: a project's local config overrides the user's global config,
  and within a scope a per-command key overrides the shared default. The new
  read-only `seihou agent config` command prints the resolved provider and model
  for every command, labelling the source of each value. See
  [AI Agent Assistance](agent-assistance.md) and the
  [agent reference](../cli/agent.md).

- **Project-aware updates.** `seihou update` now stages candidate sources,
  reuses saved per-instance inputs, applies migrations, three-way merges user
  edits from content-addressed generated baselines, skips unchanged commands,
  and publishes cache/manifest state only after success. Human and JSON output,
  interactive conflict/orphan choices, dry-run, force policies, and optional
  Git commits are included. See [the update reference](../cli/update.md).

### Changed

- `seihou status` recommends one update per recorded application; `run` is
  described as initial application/reconfiguration, while `upgrade` is
  explicitly shared-cache-only maintenance.

## [0.3.0.0] - 2026-06-12

### Added

- **Blueprints — agent-driven scaffolding.** A new runnable artifact kind for
  open-ended project shapes: Seihou applies a deterministic baseline, then hands
  the project to a configured AI provider. Author with `seihou new-blueprint`,
  check with `seihou validate-blueprint`, and run with `seihou agent run
  BLUEPRINT`. Blueprints are installable from registries, and `seihou status`
  records which blueprint was applied. See
  [Blueprints](blueprints.md).
- **AI provider integration.** Agent commands (`seihou agent`,
  `seihou prompt run`) now route through a configurable provider —
  `claude-cli`, `codex-cli`, `anthropic`, or `openai`. See
  [AI Agent Assistance](agent-assistance.md).
- **`seihou kit`** installs Claude Code and Codex skills and subagents.
- **`seihou list` kind filters:** `--modules`, `--recipes`, and
  `--blueprints` narrow output by artifact kind, and the summary count is
  kind-aware.

### Changed

- **More robust migrations.** The migration planner is now a gap-tolerant
  window walker, so migration chains with version gaps apply reliably. See
  [Migrations](migrations.md).

### Removed

- **Breaking:** the `seihou migrate --bump-only` and `seihou run
  --bump-blocked` recovery flags were removed — the rewritten migration planner
  advances through benign version gaps automatically, so the manual escape
  hatches are no longer needed.

### Fixed

- `seihou migrate` no longer crashes when a chain mixes a file move with a
  `RunCommand` step that removes the source's parent directory.
- Manifests are written atomically (write-to-temp-then-rename), avoiding
  corruption if the process is interrupted mid-write.
- Malformed or cyclic recipes now surface as structured errors instead of
  crashing.
- Generation, migration, and removal paths are constrained to stay within the
  project tree.

### Packaging

- First public [Hackage](https://hackage.haskell.org/) release preparation:
  BSD-3-Clause licensing and complete package metadata, with the CLI's embedded
  help topics and agent prompt templates packaged into source distributions.

## [0.2.0.0] - 2026-04-29

### Added

- **Module migrations.** Modules can declare file-system operations
  (`MoveFile`, `MoveDir`, `DeleteFile`, `DeleteDir`, `RunCommand`) that move a
  project across module versions. `seihou migrate` applies the chain, rewrites
  the manifest, and bumps the recorded version; `seihou run` and `seihou
  status` are migration-aware. See [Migrations](migrations.md).
- **Recipes.** Named, ordered compositions of modules with optional pre-bound
  parameters. Author with `seihou new-recipe`; recipes are first-class in
  `run`, `list`, `install`, and `browse`.
- **Registry tooling.** The `seihou registry` command group (`sync-versions`,
  `validate`) keeps a multi-module repository's `seihou-registry.dhall` in sync
  with its artifacts, with CI-friendly `--check` and non-zero exit on drift.
- **Inline template conditionals.** `{{#if cond}} … {{/if}}` blocks in the
  Template strategy, with unbounded nesting. See
  [Templating](templating.md).
- **`seihou run --confirm-defaults`** steps through each defaulted or
  export-derived variable so you can accept or override it interactively.
- **`seihou status --check-updates`** surfaces available registry updates
  alongside status output.
- **Parameterized-dependency multi-instantiation:** a parent can instantiate
  the same dependency several times with different parameter sets.

### Changed

- `seihou migrate` fetches the latest module before planning, so no manual
  `seihou upgrade` is needed first (`--no-fetch` opts out).

## [0.1.0.0] - 2026-04-15

Initial public release of Seihou — a composable, type-safe project scaffolding
system driven by Dhall modules, with stateful manifests and incremental
regeneration.

### Added

- **Core pipeline:** Dhall module loading and validation, layered variable
  resolution with `--explain`, four generation strategies (`Copy`, `Template`,
  `DhallText`, `Structured`) plus text patching, composition with declared
  dependencies and topological ordering, and plan compilation with shell-command
  hooks.
- **Manifest tracking:** a stateful `.seihou/manifest.json`, a three-state diff
  engine (manifest / plan / disk), interactive conflict resolution, and
  reversible module removal.
- **Module system:** required module versions, `seihou outdated` / `seihou
  upgrade`, schema evolution, and `seihou schema-upgrade`.
- **CLI:** `init`, `run`, `vars`, `install`, `browse`, `list`, `status`,
  `diff`, `validate-module`, `new-module`, `config`, `context`, `remove`,
  agent workflows, and embedded help topics.
- **Registries:** multi-module registry support with discovery and validation.
- **Developer experience:** Bash/Zsh/Fish completions, FZF selection, and a
  `--verbose` flag wired throughout.

---

[0.3.0.0]: https://github.com/shinzui/seihou/compare/v0.2.0.0...v0.3.0.0
[0.2.0.0]: https://github.com/shinzui/seihou/compare/v0.1.0.0...v0.2.0.0
[0.1.0.0]: https://github.com/shinzui/seihou/releases/tag/v0.1.0.0
