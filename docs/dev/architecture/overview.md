# Architecture Overview

| Field | Value |
|---|---|
| **Status** | Proposed |
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
│  Config Resolution   │  Merge: CLI → env → local → namespace → global → defaults
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

**Config Resolution** merges configuration from six sources (CLI flags, environment variables, local project config, namespace config, global config, module defaults) into a single resolved configuration map. Each value retains provenance metadata for the `--explain` feature.

**Module Loading** evaluates Dhall module definitions into typed Haskell values. When multiple modules are composed, their dependency graph is resolved via topological sort to determine execution order.

**Variable Resolution** walks each module's variable declarations and resolves values from the merged config. Type checking and validation (required, pattern, range) happen here. Cross-module variable references are resolved through explicit exports.

**Plan Compilation** dispatches each module step to its generation strategy (Copy, Template, DhallText, Structured) and produces a list of filesystem operations. Composition patches (append-section, record merge, etc.) are applied during this phase.

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
| `Filesystem` | File I/O, directory operations, path resolution | In-memory filesystem |
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
│           │   ├── Types.hs       # Module, VarDecl, Step, Operation, etc.
│           │   ├── Variable.hs    # Resolution, validation, expression eval
│           │   ├── Module.hs      # Loading, validation, dependency resolution
│           │   └── Expr.hs        # Expression language AST and evaluator
│           ├── Engine/
│           │   ├── Plan.hs        # Plan compilation from modules
│           │   ├── Strategy/
│           │   │   ├── Copy.hs
│           │   │   ├── Template.hs
│           │   │   ├── DhallText.hs
│           │   │   └── Structured.hs
│           │   ├── Diff.hs        # Three-state diff engine
│           │   └── Execute.hs     # Plan execution
│           ├── Composition/
│           │   ├── Graph.hs       # Dependency graph, topological sort
│           │   ├── Layering.hs    # Patch operations, merge strategies
│           │   └── Conflict.hs    # Conflict detection and reporting
│           ├── Manifest/
│           │   ├── Types.hs       # Manifest, FileRecord
│           │   ├── Read.hs
│           │   └── Write.hs
│           ├── Config/
│           │   ├── Resolution.hs  # Multi-layer config merging
│           │   └── Types.hs
│           ├── Dhall/
│           │   ├── Eval.hs        # Dhall evaluation bridge
│           │   └── Schema.hs      # Module schema definitions
│           └── Effect/
│               ├── Filesystem.hs
│               ├── Console.hs
│               ├── DhallEval.hs
│               ├── ConfigReader.hs
│               ├── ManifestStore.hs
│               ├── Process.hs
│               └── Logger.hs
├── seihou-cli/                    # Executable: CLI parsing, command dispatch
│   ├── seihou-cli.cabal
│   └── src/
│       └── Seihou/
│           └── CLI/
│               ├── Main.hs        # Entry point
│               ├── Commands.hs    # Command ADT + optparse-applicative
│               ├── Run.hs         # seihou run handler
│               ├── Init.hs        # seihou init handler
│               ├── Vars.hs        # seihou vars handler
│               ├── Install.hs     # seihou install handler
│               ├── Status.hs      # seihou status handler
│               ├── NewModule.hs   # seihou new-module handler
│               └── Validate.hs    # seihou validate-module handler
└── docs/                          # Documentation (this directory)
```

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

### Templates Stay Dumb; Dhall Computes

Templates perform only placeholder substitution (`{{var.name}}`). When conditional logic or loops are needed, a Dhall function assembles the final text before it reaches the placeholder engine. This preserves P1 (no template logic) while providing an escape hatch for complex files via the `DhallText` strategy.

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
- [Variable Resolution](../design/proposed/variable-resolution.md) — Resolution precedence, expression language
- [Generation Strategies](../design/proposed/generation-strategies.md) — Per-strategy specs, placeholder engine
- [Manifest and Incrementality](../design/proposed/manifest-and-incrementality.md) — Manifest format, three-state model
- [CLI Commands](../design/proposed/cli-commands.md) — Command specifications
- [V1 Milestones](../roadmap/v1-milestones.md) — Implementation plan
