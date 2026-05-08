# Architecture Overview

| Field | Value |
|---|---|
| **Status** | Implemented |
| **Updated** | 2026-04-16 |
| **Created** | 2026-03-01 |
| **Subsystem** | Core |

## Overview

Seihou (製法) is a composable, type-safe project scaffolding system. It treats project generation as **configuration resolution + filesystem operations** rather than text templating. Modules authored in Dhall define typed inputs, generation strategies, and filesystem operations that compose deterministically.

This document describes the end-to-end system architecture: the execution pipeline, effect stack, project structure, and technology choices.

## Execution Pipeline

```text
CLI input
  │
  ▼
┌─────────────────────┐
│  Config Resolution   │  Merge: CLI → env → local → namespace → context → global → defaults
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  Module Loading      │  Evaluate Dhall → typed Module values
└─────────┬───────────┘  Resolve dependencies (topological sort)
          │
          ▼
┌─────────────────────┐
│  Variable Resolution │  Resolve all vars per precedence
└─────────┬───────────┘  Validate types, required fields, patterns
          │
          ▼
┌─────────────────────┐
│  Plan Compilation    │  For each module step:
└─────────┬───────────┘    Strategy dispatch → [Operation]
          │
          ▼
┌─────────────────────┐
│  Three-State Diff    │  Compare plan against manifest + disk
└─────────┬───────────┘  Detect conflicts, classify changes
          │
          ▼
┌─────────────────────┐
│  User Approval       │  Show plan/diff, prompt per-conflict
└─────────┬───────────┘  (--dry-run stops here)
          │
          ▼
┌─────────────────────┐
│  Execution           │  Write files, create dirs, run commands
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  Manifest Update     │  Record applied modules, file hashes,
└─────────────────────┘  variable values, timestamps
```

### Pipeline Stages in Detail

**Config Resolution** merges configuration from seven sources (CLI flags, environment variables, local project config, namespace config, context config, global config, module defaults) into a single resolved configuration map. Each value retains provenance metadata for the `--explain` feature. The active context is resolved from `--context` flag, `SEIHOU_CONTEXT` env var, `.seihou/context` file, or `~/.config/seihou/default-context`.

**Module Loading** evaluates Dhall module definitions into typed Haskell values. When multiple modules are composed, their dependency graph is resolved via topological sort to determine execution order. If the name resolves to a recipe (`recipe.dhall`), it is expanded into its constituent modules before entering the composition pipeline. If the name resolves to a blueprint (`blueprint.dhall`), the loader hands control to `seihou agent run` rather than the deterministic pipeline; the blueprint is not plan-compiled (see [Blueprints](../design/proposed/blueprints.md)).

**Variable Resolution** walks each module's variable declarations and resolves values from the merged config. Type checking and validation (required, pattern, range) happen here. Cross-module variable references are resolved through explicit exports.

**Plan Compilation** dispatches each module step to its generation strategy (Copy, Template, DhallText, Structured) and produces a list of filesystem operations. Composition patches (append-section, append-line-if-absent, record merge, etc.) are applied during this phase.

**Three-State Diff** compares the compiled plan against both the manifest (what was last generated) and disk (what currently exists). This produces a classified diff: new files, modified files, conflicting files (user edited a generated file), and deleted files.

**User Approval** presents the plan to the user. In interactive mode, conflicts are shown per-file with diffs for the user to accept, reject, or merge. `--dry-run` prints operations and stops. `--diff` shows the filesystem diff.

**Execution** performs the approved filesystem operations: writing files, creating directories, running shell commands.

**Manifest Update** records the final state: which modules were applied, what variable values were used, file content hashes, and generation timestamps. This enables future incremental runs.

## Effect Stack

Seihou uses the `effectful` library for its effect system, following the patterns established in mori. The effect stack isolates side effects and enables pure testing of business logic.

```haskell
type AppEffects =
  '[ Filesystem       -- File reads, writes, directory operations
   , Console          -- User prompts, output, progress display
   , DhallEval        -- Dhall expression evaluation
   , ConfigReader     -- Configuration resolution across layers
   , ManifestStore    -- Manifest read/write operations
   , Process          -- Shell command execution (for RunCommand steps)
   , Logger           -- Structured logging
   , IOE              -- Base IO (effectful requirement)
   ]
```

### Effect Descriptions

| Effect | Responsibility | Test Strategy |
|---|---|---|
| `Filesystem` | File I/O, directory operations, path resolution, file/directory removal | In-memory filesystem |
| `Console` | Interactive prompts, terminal output, progress bars | Scripted input/captured output |
| `DhallEval` | Evaluate Dhall expressions to Haskell values | Pre-evaluated fixtures |
| `ConfigReader` | Resolve config from all layers with provenance | Pure config maps |
| `ManifestStore` | Read/write `.seihou/manifest.json` | In-memory store |
| `Process` | Execute shell commands (git init, etc.) | Command recording |
| `Logger` | Structured log output | Log capture |

## Project Structure

Seihou is organized as a multi-package Cabal workspace:

```text
seihou/
├── cabal.project                  # Workspace definition
├── flake.nix                      # Nix flake for dev environment + CI
├── flake.lock
├── seihou-core/                   # Library: domain types, engine, effects
│   ├── seihou-core.cabal
│   └── src/
│       └── Seihou/
│           ├── Core/
│           │   ├── Types.hs       # Module, Recipe, VarDecl, Step, Operation, Removal, etc.
│           │   ├── Variable.hs    # Resolution, validation, coercion
│           │   ├── Module.hs      # Loading, validation, discovery (discoverRunnable)
│           │   ├── Recipe.hs      # Recipe validation (validateRecipe)
│           │   ├── Blueprint.hs   # Blueprint validation, discovery (validateBlueprint, discoverBlueprint)
│           │   ├── Expr.hs        # Expression language AST and evaluator
│           │   ├── Registry.hs    # Multi-module repository support (modules + recipes + blueprints)
│           │   ├── Version.hs     # Semantic version parsing and comparison
│           │   ├── Install.hs     # Module name parsing from URLs
│           │   ├── Status.hs      # Tracked file status computation
│           │   └── Context.hs     # Execution context
│           ├── Engine/
│           │   ├── Plan.hs        # Single-module plan compilation
│           │   ├── Template.hs    # Placeholder engine + {{#if}} conditional blocks
│           │   ├── Execute.hs     # Plan execution
│           │   ├── Diff.hs        # Three-state diff engine
│           │   ├── Conflict.hs    # Conflict resolution
│           │   ├── Preview.hs     # Diff visualization
│           │   ├── Section.hs     # Text patching (append/prepend/line-dedup)
│           │   ├── Remove.hs      # Module removal engine
│           │   ├── Validate.hs    # Post-generation validation
│           │   └── DhallJSON.hs   # Dhall-to-JSON bridge
│           ├── Composition/
│           │   ├── Graph.hs       # Dependency graph, topological sort
│           │   ├── Resolve.hs     # Module loading, variable resolution
│           │   ├── Plan.hs        # Multi-module plan merging
│           │   └── Recipe.hs      # Recipe expansion (expandRecipe)
│           ├── Manifest/
│           │   ├── Types.hs       # Manifest, FileRecord, JSON serialization
│           │   └── Hash.hs        # SHA256 content hashing
│           ├── Interaction/
│           │   └── Prompt.hs      # Interactive variable prompts
│           ├── Dhall/
│           │   ├── Eval.hs        # Dhall evaluation bridge
│           │   └── Config.hs      # Config file parsing
│           └── Effect/            # 8 effects, each with IO + Pure interpreters
│               ├── Filesystem.hs
│               ├── Console.hs
│               ├── DhallEval.hs
│               ├── ConfigReader.hs
│               ├── ConfigWriter.hs
│               ├── ManifestStore.hs
│               ├── Process.hs
│               └── Logger.hs
├── seihou-cli/                    # CLI: library-first; executable holds only the trapped IO shell
│   ├── seihou-cli.cabal
│   ├── src/                       # seihou-cli-internal library (test-importable)
│   │   └── Seihou/
│   │       ├── CLI/
│   │       │   ├── AgentLaunch.hs    # Shared Claude Code launcher (pure formatters + IO helpers)
│   │       │   ├── AppliedBlueprint.hs # Manifest writer for AppliedBlueprint provenance
│   │       │   ├── BrowseFormat.hs   # Module/recipe/blueprint browsing output formatter
│   │       │   ├── CommitMessage.hs  # AI-generated commit messages (claude CLI)
│   │       │   ├── Completions/      # Bash/Fish/Zsh completion emitters
│   │       │   ├── Diff.hs           # seihou diff helpers
│   │       │   ├── Git.hs            # Git porcelain helpers for --commit
│   │       │   ├── Init.hs           # seihou init helpers
│   │       │   ├── InstallHistory.hs # Install URL history (XDG config)
│   │       │   ├── InstallShared.hs  # Shared install helpers (cloneRepo, installModuleDir)
│   │       │   ├── List.hs           # seihou list formatter
│   │       │   ├── Migrate.hs        # Migration planning helpers
│   │       │   ├── PendingMigrations.hs  # Pending-migrations probe
│   │       │   ├── Registry.hs       # seihou registry shared helpers
│   │       │   ├── Registry/
│   │       │   │   ├── Sync.hs       # seihou registry sync-versions
│   │       │   │   └── Validate.hs   # seihou registry validate
│   │       │   ├── RemoteVersion.hs  # Remote module version probing
│   │       │   ├── SavePrompted.hs   # Persist prompted values to local config
│   │       │   ├── SchemaVersion.hs  # Pinned seihou-schema URL/hash
│   │       │   ├── Shared.hs         # Common CLI utilities (formatBlueprintRefusal, etc.)
│   │       │   ├── StatusRender.hs   # seihou status renderer (modules + blueprint section)
│   │       │   ├── Style.hs          # Color/formatting
│   │       │   └── VersionCompare.hs # Version comparison helpers
│   │       ├── Effect/
│   │       │   └── Fzf.hs            # Fzf effect + interpreter
│   │       └── Fzf.hs                # Interactive module selection via fzf
│   ├── src-exe/                   # Executable target: Main.hs + trapped command handlers
│   │   ├── Main.hs                # Entry point + command dispatcher
│   │   └── Seihou/
│   │       └── CLI/
│   │           ├── AgentLaunchExec.hs  # claude shell-out (returns ExitCode)
│   │           ├── AgentRun.hs       # seihou agent run BLUEPRINT handler
│   │           ├── Assist.hs         # seihou agent assist handler (embedded prompt)
│   │           ├── Bootstrap.hs      # seihou agent bootstrap handler (embedded prompt)
│   │           ├── Browse.hs         # seihou browse handler
│   │           ├── Commands.hs       # Command ADT + optparse-applicative
│   │           ├── Completions.hs    # seihou completions handler
│   │           ├── Config.hs         # seihou config handler
│   │           ├── Context.hs        # seihou context handler
│   │           ├── Help.hs           # seihou help handler
│   │           ├── Install.hs        # seihou install handler
│   │           ├── Kit.hs            # seihou kit handler (skills/subagents)
│   │           ├── NewBlueprint.hs   # seihou new-blueprint handler
│   │           ├── NewModule.hs      # seihou new-module handler
│   │           ├── NewRecipe.hs      # seihou new-recipe handler
│   │           ├── Outdated.hs       # seihou outdated handler
│   │           ├── Remove.hs         # seihou remove handler
│   │           ├── Run.hs            # seihou run handler (with blueprint refusal)
│   │           ├── SchemaUpgrade.hs  # seihou schema-upgrade handler
│   │           ├── Setup.hs          # seihou agent setup handler (embedded prompt)
│   │           ├── Status.hs         # seihou status handler
│   │           ├── Upgrade.hs        # seihou upgrade handler
│   │           ├── Validate.hs       # seihou validate-module handler
│   │           ├── ValidateBlueprint.hs # seihou validate-blueprint handler
│   │           ├── Vars.hs           # seihou vars handler
│   │           └── Version.hs        # --version (GitHash + Paths_seihou_cli)
│   └── data/                      # Embedded prompt templates (Data.FileEmbed)
│       ├── assist-prompt.md
│       ├── bootstrap-prompt.md
│       ├── setup-prompt.md
│       └── blueprint-prompt.md
├── schema/                        # Dhall schema (mirrored into seihou-schema)
│   ├── package.dhall
│   ├── Module.dhall
│   ├── Recipe.dhall
│   └── Blueprint.dhall
└── docs/                          # Documentation (this directory)
```

## CLI Module Placement Convention

Code under `seihou-cli/src/Seihou/` defaults to the `seihou-cli-internal`
library. The `seihou` executable target is reserved for the IO shell:
`Main.hs`, command dispatchers, and the small set of modules that genuinely
cannot live in the library.

A module belongs in the executable target only if it imports one of these
four Haskell-package dependencies:

- `Options.Applicative` (the optparse-applicative CLI parser).
- `Data.FileEmbed` (compile-time `embedFile` for prompt and help text).
- `GitHash` (compile-time git hash exposed by `--version`).
- `Paths_seihou_cli` (Cabal's generated module exposing the package version).

A fifth, transitive criterion also keeps a module in the executable: it
imports another seihou module that is itself executable-only. The most
common case today is `Seihou.CLI.Commands` (trapped by
`Options.Applicative`); every command-handler module that imports
`Commands` for its `Opts` type is transitively trapped.

Any other module — pure helpers, formatters, IO-bearing primitives that
other commands or tests might call — belongs in the library. The library
already exposes IO-bearing helpers (for example, `cloneRepo` and
`installModuleDir` in `Seihou.CLI.InstallShared`); needing IO is not a
reason to stay in the executable.

The executable target lives in `seihou-cli/src-exe/`. The library
lives in `seihou-cli/src/`. The split source directories make GHC
resolve library imports through the package binary instead of finding
the source files locally — which means a module added to `src/` is
automatically library-visible, and a module added to `src-exe/` cannot
be reached by the test suite. The convention is enforced at the GHC
level by this directory layout.

`seihou-cli/seihou-cli.cabal`'s `executable seihou` block carries a
single header comment above its `other-modules` list pointing readers
at the "Trapped-modules inventory" subsection below. Per-line cabal
comments are not used because the project's formatter (`cabal-gild`)
sorts module entries alphabetically and floats `--` comments to the
top of the section, which would silently desynchronise per-module
annotations from the modules they describe.

To add a new executable-only module, demonstrate the trapping
dependency in the module's import list, add the file under
`seihou-cli/src-exe/Seihou/CLI/...`, list it in the executable's
`other-modules`, and add a row to the "Trapped-modules inventory"
subsection below. To add an exemption (a module that legitimately
stays in the executable despite not importing one of the four
dependencies), add it to the `EXEMPT_MODULES` list in the enforcement
script (see the path declared in
`docs/plans/21-enforce-cli-library-first-convention.md`) with an
inline comment naming the reason.

### Trapped-modules inventory

The table below names every module in `executable seihou`'s
`other-modules` and the trapping reason that keeps it out of the
library. Update this table when an entry is added to or removed from
the cabal file's `other-modules`.

| Module | Trapping reason |
|---|---|
| `Paths_seihou_cli` | Generated by Cabal; lives in the executable |
| `Seihou.CLI.AgentLaunch` | Mixed pure surface + `launchAgent` (process invocation); split deferred to `docs/plans/20-extract-trapped-cli-helpers.md` |
| `Seihou.CLI.AgentLaunchExec` | Exempt — process launcher (`rawSystem`/`exitWith`) consumed only by trapped agent-prompt wrappers; kept executable-side by design (see `EXEMPT_MODULES` in `nix/check-cli-module-placement.sh`) |
| `Seihou.CLI.AgentRun` | `Data.FileEmbed` for the embedded `blueprint-prompt.md` template |
| `Seihou.CLI.Assist` | `Data.FileEmbed` for the embedded prompt template |
| `Seihou.CLI.Bootstrap` | `Data.FileEmbed` for the embedded prompt template |
| `Seihou.CLI.Browse` | Imports `Seihou.CLI.Commands` (transitively trapped) |
| `Seihou.CLI.Commands` | `Options.Applicative` |
| `Seihou.CLI.Completions` | Imports `Seihou.CLI.Commands` (transitively trapped) |
| `Seihou.CLI.Completions.Bash` | Imports `Seihou.CLI.Commands` (transitively trapped) |
| `Seihou.CLI.Completions.Fish` | Imports `Seihou.CLI.Commands` (transitively trapped) |
| `Seihou.CLI.Completions.Zsh` | Imports `Seihou.CLI.Commands` (transitively trapped) |
| `Seihou.CLI.Config` | Imports `Seihou.CLI.Commands` (transitively trapped) |
| `Seihou.CLI.Context` | Imports `Seihou.CLI.Commands` (transitively trapped) |
| `Seihou.CLI.Help` | `Data.FileEmbed` for embedded help-topic content |
| `Seihou.CLI.Install` | Imports `Seihou.CLI.Commands` (transitively trapped) |
| `Seihou.CLI.Kit` | `Options.Applicative` |
| `Seihou.CLI.NewBlueprint` | Imports `Seihou.CLI.Commands` (transitively trapped) |
| `Seihou.CLI.NewModule` | Imports `Seihou.CLI.Commands` (transitively trapped) |
| `Seihou.CLI.NewRecipe` | Imports `Seihou.CLI.Commands` (transitively trapped) |
| `Seihou.CLI.Outdated` | Imports `Seihou.CLI.Commands` (transitively trapped) |
| `Seihou.CLI.Remove` | Imports `Seihou.CLI.Commands` (transitively trapped) |
| `Seihou.CLI.Run` | Imports `Seihou.CLI.Commands` (transitively trapped) |
| `Seihou.CLI.SchemaUpgrade` | Imports `Seihou.CLI.Commands` (transitively trapped) |
| `Seihou.CLI.Setup` | `Data.FileEmbed` for the embedded prompt template |
| `Seihou.CLI.Status` | Imports `Seihou.CLI.Commands` (transitively trapped) |
| `Seihou.CLI.Upgrade` | Imports `Seihou.CLI.Commands` (transitively trapped) |
| `Seihou.CLI.Validate` | Imports `Seihou.CLI.Commands` (transitively trapped) |
| `Seihou.CLI.ValidateBlueprint` | Imports `Seihou.CLI.Commands` (transitively trapped) |
| `Seihou.CLI.Vars` | Imports `Seihou.CLI.Commands` (transitively trapped) |
| `Seihou.CLI.Version` | `GitHash` and `Paths_seihou_cli` |

Why this convention exists: the masterplan
`docs/masterplans/1-migrations-dx.md` retrospective records that helpers
repeatedly had to be hoisted from executable-only modules into library
siblings during EP-1, EP-2, and EP-4, costing about three hours of
unscheduled refactor work, because tests cannot import from the executable
target. Defaulting to the library prevents the discovery from happening
mid-implementation.

## Technology Stack

| Component | Choice | Rationale |
|---|---|---|
| Language | Haskell (GHC 9.12.2, GHC2024) | Type safety, Dhall ecosystem, personal preference |
| Build | Cabal (multi-package workspace) | Native Haskell build, workspace support |
| Effect system | effectful | Performant, ergonomic, actively maintained |
| Module authoring | Dhall | Type-safe configuration, deterministic evaluation |
| CLI parsing | optparse-applicative | Standard Haskell CLI library, composable parsers |
| Dev environment | Nix flakes | Reproducible builds, CI integration |
| Serialization | aeson (JSON), yaml | Manifest storage, structured file generation |
| File hashing | cryptonite (SHA256) | Manifest integrity, change detection |
| Testing | tasty + hspec | Property and unit testing |

## Key Architectural Decisions

### Templates Stay Mostly Dumb; Dhall Computes

Templates perform placeholder substitution (`{{var.name}}`) and a single
kind of branching construct: inline `{{#if <expr>}}…{{/if}}` blocks
(optionally with `{{#else}}`) that gate body text on the same expression
grammar used by a step's `when` clause. The block form exists so that a
module author can keep a single `.tpl` file instead of shipping two
near-duplicate templates with mutually exclusive `when` guards; it is
deliberately limited to the Template strategy's body path — destination
paths and shell commands stay placeholder-only.

For anything richer than boolean gating — loops, arithmetic, string
assembly, structured records — a Dhall function computes the final text
and the engine passes it through without further logic. This preserves
P1 (templates do not grow a full expression sub-language) while keeping
the "same file for two configurations" ergonomics cheap. See
[Generation Strategies: Conditional blocks](../design/proposed/generation-strategies.md#conditional-blocks-template-only)
and [ExecPlan 9](../../plans/9-inline-conditionals-in-template-strategy.md)
for the full design.

### Explicit Composition via Declared Dependencies

Modules declare their dependencies explicitly. Composition order is determined by topological sort of the dependency graph, not by implicit stacking order. Patch semantics are strategy-dependent: Dhall record merge for structured files, declarative operations (append-section, replace-section) for text files.

### Stateful Manifest for Incrementality

A manifest (`.seihou/manifest.json`) tracks what was generated, enabling:
- Incremental re-generation (only changed files)
- "Which module generated this file?" queries
- Conflict detection when users edit generated files
- Undo/rollback capability (future)

### Three-State Diff Model

The diff engine compares three sources: the manifest (last known generated state), the plan (what would be generated now), and disk (current filesystem state). This enables precise conflict classification without requiring version control.

## Cross-References

- [Module System](../design/proposed/module-system.md) — Module structure, loading, variables, exports
- [Composition and Layering](../design/proposed/composition-and-layering.md) — Dependency graph, patch model
- [Blueprints](../design/proposed/blueprints.md) — Agent-driven runnable type, runner workflow, manifest behaviour
- [Variable Resolution](../design/proposed/variable-resolution.md) — Resolution precedence, expression language
- [Generation Strategies](../design/proposed/generation-strategies.md) — Per-strategy specs, placeholder engine
- [Manifest and Incrementality](../design/proposed/manifest-and-incrementality.md) — Manifest format, three-state model
- [CLI Commands](../design/proposed/cli-commands.md) — Command specifications
- [V1 Milestones](../roadmap/v1-milestones.md) — Implementation plan
