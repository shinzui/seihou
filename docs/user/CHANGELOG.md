# Changelog

User-facing release notes for Seihou. This is a curated summary of
user-visible changes; the [full engineering changelog](../../CHANGELOG.md) at
the repository root records every change, including internal refactors and
packaging.

Versions follow the Haskell [PVP](https://pvp.haskell.org/) (`A.B.C.D`). All
packages in the workspace share a single version.

## Unreleased

### Added

- **Call tracing for agent commands.** Seihou can now record what each model
  call actually did — which provider and model ran, how long it took, how many
  tokens it used, and what it cost:

  ```sh
  seihou config set agent.trace file
  seihou agent assist "add a health check module"
  cat .seihou/trace.jsonl
  ```

  ```text
  {"kind":"call_started","eventId":"a1b2c3","timestamp":"2026-07-27T18:04:11Z","provider":"anthropic","model":"claude-sonnet-4-6","maxTokens":8192,"promptSummary":"add a health check module"}
  {"kind":"call_finished","eventId":"a1b2c3","timestamp":"2026-07-27T18:04:19Z","provider":"anthropic","model":"claude-sonnet-4-6","latencyMs":7913,"inputTokens":4211,"outputTokens":880,"usd":0.0264}
  ```

  The file is JSON Lines, one object per line, so ordinary tools answer the
  questions you actually have — `jq -s 'map(select(.kind == "call_finished") |
  .usd) | add' .seihou/trace.jsonl` totals what a project has cost you.

  `agent.trace` takes `off`, `file`, `stdout`, or `stderr`, and resolves through
  the same precedence chain as `provider`, `model`, and `effort`: a `--trace`
  flag, `SEIHOU_AGENT_TRACE`, then `agent.<command>.trace` and `agent.trace` in
  local then global config. Use `--trace stderr` to watch a single run without
  leaving a file behind; trace lines go to stderr precisely so they never
  corrupt assistant output you are piping. The file destination is
  `.seihou/trace.jsonl`, changeable with `agent.tracePath`.

  **Tracing is off by default and stays out of your way** — with `agent.trace`
  unset, nothing is written, nothing extra is printed, and no file is created.

  Two limits worth knowing. Interactive `claude`/`codex` sessions are not
  traced: they are spawned subprocesses, not requests Seihou can time or price,
  so tracing covers batch runs (`--batch`, or automatically when stdin is not a
  terminal) and the API providers. And the subscription-based CLI providers do
  not report tokens or cost, so their events carry latency only — use
  `anthropic` or `openai` for cost accounting.

  See [Tracing model calls](agent-assistance.md#tracing-model-calls).

- **Blueprint- and prompt-declared agent settings.** A blueprint or agent
  prompt can now declare the agent it was written for, in its own Dhall file:

  ```dhall
  , launch = Some S.Launch::{
    , provider = Some "claude-cli"
    , model = Some "claude-opus-4-8"
    , effort = Some "max"
    }
  ```

  This matters when a prompt only works well with a particular provider, or
  genuinely needs deep reasoning: rather than hoping whoever runs it has the
  right settings configured, the author states them once. Declared values
  **override every config-file tier** — project-local and global, per-command
  keys included — but **lose to anything you state for a single invocation**: a
  `--provider` / `--model` / `--effort` flag, or a `SEIHOU_AGENT_*` environment
  variable. Precedence is per field, so a `--model` flag replaces only the model
  while a declared `effort` still applies.

  Honored by `seihou agent run`, `seihou agent migrate`, and `seihou prompt
  run`. Add `--verbose` to see what resolved and where each value came from
  (`[blueprint: launch.effort]`, `[flag on subcommand]`, and so on). A
  declaration naming an unknown provider or effort is reported by `seihou
  validate-blueprint` / `seihou validate-prompt` and refuses the run instead of
  silently falling back. `seihou agent config` lists the new tier in its
  precedence legend, and freshly scaffolded blueprints show the field as a
  commented example.

  `prompt.dhall` already accepted a `launch` record in earlier releases, but
  nothing read it; it is now honored, and gains an `effort` field. Existing
  blueprints and prompts are unaffected — the field is optional, and artifacts
  authored against an older schema pin still load. See
  [Blueprints](blueprints.md#launch-settings) and
  [Prompts](prompts.md#launch-settings).

- **Configurable reasoning effort.** Each agent command (and `seihou prompt
  run`) can now set the model's reasoning effort — how hard it thinks — with the
  same hierarchy as provider and model. Use `agent.effort` /
  `agent.<command>.effort` (levels `minimal`, `low`, `medium`, `high`, `xhigh`,
  `max`), `SEIHOU_AGENT_EFFORT`, or the `--effort LEVEL` flag. Effort flows to
  the local CLIs (`claude --effort` / `codex -c model_reasoning_effort`) and to
  the API providers, and appears as a new row in `seihou agent config`. Unset by
  default, so the CLI/provider picks its own. Requires Baikai 0.4. See
  [AI Agent Assistance](agent-assistance.md#reasoning-effort).

- **Ordered blueprint migrations.** Blueprint authors can declare versioned,
  agent-driven upgrade steps in `blueprint.dhall`, and users can run the exact
  requested window with `seihou agent migrate BLUEPRINT --from VERSION --to
  VERSION`. Seihou runs the declared edges inside that window in ascending order,
  tolerating undeclared gaps, skipping an edge that overlaps one already selected,
  and deferring an edge whose target overshoots the window; it writes a durable
  receipt after every successful step; resumes interrupted chains by default;
  and supports `--rerun` plus a side-effect-free `--debug` preview. See
  [Blueprint Migrations](blueprint-migrations.md) for the full workflow, plus
  [Blueprints](blueprints.md), [Migrations](migrations.md), and the
  [`agent migrate` reference](../cli/agent.md#agent-migrate).

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
  `bootstrap`, `setup`, `run`, `migrate`, or `prompt-run`) to override the shared
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

### Fixed

- **Reasoning effort now reaches non-interactive agent runs.** Effort was
  applied to interactive Claude Code and Codex sessions but silently dropped
  whenever Seihou took the batch path — `claude -p`, used when stdin is not a
  terminal, such as in CI or through a pipe. Configured, environment-set, and
  blueprint-declared effort now reach the agent in both modes. Requires Baikai
  0.4.1 / baikai-claude 0.4.

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
