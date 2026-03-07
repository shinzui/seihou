# V1 Milestones

| Field | Value |
|---|---|
| **Status** | In Progress |
| **Created** | 2026-03-01 |
| **Updated** | 2026-03-06 |

## Overview

V1 of Seihou delivers a complete, usable project scaffolding system: module loading, generation, composition, incrementality, and a CLI for the core workflow. The milestones are ordered by dependency — each builds on the prior.

## Milestone Summary

| Milestone | Name | Status | Delivers |
|---|---|---|---|
| M0 | Project Bootstrap | Done | Nix flake, cabal workspace, CI, core types |
| M1 | Module Loading | Done | Dhall module parsing, validation, variable declarations |
| M2 | Generation Engine | Done | Plan compilation, placeholder engine, file writing |
| M3 | CLI Core | Done | init, run (single module, one-shot), vars |
| M4 | Composition | Done | Module dependencies, layering, patch operations |
| M5 | Incrementality | Done | Manifest tracking, three-state diff, status |
| M6 | Module Authoring | Done | new-module, validate-module, install |
| M7 | Config & Diagnostics | Done | config commands, --effective, unused key warnings |
| M8 | Discovery & Registry | Done | list, browse, registries, multi-module repos |
| M9 | Interactive Prompts | Done | Optional variable prompting, default display |

## M0 — Project Bootstrap

**Goal**: Repository structure, build system, and foundational types.

**Status**: Done

### Deliverables

- [x] Nix flake with GHC 9.12.2, development shell, CI check
- [x] Cabal workspace with `seihou-core` and `seihou-cli` packages
- [x] Core domain types in `Seihou.Core.Types`:
  - `Module`, `ModuleName`, `VarDecl`, `VarName`, `VarType`, `VarValue`
  - `Prompt`, `Step`, `Strategy`, `Expr`
  - `Operation` (filesystem operations)
- [x] Effect definitions (interfaces only, no implementations):
  - `Filesystem`, `Console`, `DhallEval`, `ConfigReader`, `ManifestStore`, `Process`, `Logger`
- [x] Test infrastructure: tasty + hspec, test helpers
- [x] CI: `nix flake check` runs build + tests

---

## M1 — Module Loading

**Goal**: Parse Dhall module definitions into typed Haskell values and validate them.

**Status**: Done

### Deliverables

- [x] Dhall schema for module definitions (`schema/Module.dhall`)
- [x] Dhall evaluation bridge (`Seihou.Dhall.Eval`):
  - Evaluate `module.dhall` → `Module` value
  - Error handling for Dhall type errors and evaluation failures
- [x] Module discovery (`Seihou.Core.Module`):
  - Search path: local → user → installed
  - Explicit path resolution
- [x] Module validation (`Seihou.Core.Module`):
  - Name format, unique variables, prompt references, file existence, export references
- [x] Variable declaration types with validation rules
- [x] Expression language parser and evaluator (`Seihou.Core.Expr`)
- [x] `DhallEval` effect implementation (real + test)
- [x] Test the haskell-template example module loads correctly

---

## M2 — Generation Engine

**Goal**: Compile loaded modules into a generation plan and execute it.

**Status**: Done

### Deliverables

- [x] Plan compilation (`Seihou.Engine.Plan`)
- [x] Generation strategies: Copy, Template, DhallText, Structured
- [x] Placeholder engine: `{{var.name}}` syntax, escape handling, type coercion
- [x] Variable resolution (`Seihou.Core.Variable`):
  - Multi-layer precedence: CLI → env → local → namespace → context → global → default
  - Provenance tracking per variable
  - Type checking and validation
- [x] Plan execution (`Seihou.Engine.Execute`)
- [x] Config resolution: Global, namespace, local Dhall config loading

---

## M3 — CLI Core

**Goal**: Working CLI with init, run (single module), and vars commands.

**Status**: Done

### Deliverables

- [x] optparse-applicative command parser (`Seihou.CLI.Commands`)
- [x] `seihou init` handler
- [x] `seihou run <module>` handler (single module, one-shot):
  - Module loading → variable resolution → plan compilation → execution
  - Interactive prompts for missing required variables
  - `--dry-run`, `--diff`, `--force`, `--no-commands` flags
- [x] `seihou vars <module>` handler with `--explain` flag
- [x] Error output formatting (stderr, exit codes)
- [x] `Logger` effect implementation

---

## M4 — Composition

**Goal**: Multiple modules compose via dependencies and layering.

**Status**: Done

### Deliverables

- [x] Dependency graph construction (`Seihou.Composition.Graph`)
- [x] Topological sort for execution order, cycle detection
- [x] Layering engine: structured file merge, text file patch operations
- [x] Conflict detection
- [x] Variable export/import with cross-module resolution
- [x] `seihou run` updated with `--module` flag for multi-module composition

---

## M5 — Incrementality

**Goal**: State tracking via manifest, incremental re-generation, conflict detection.

**Status**: Done

### Deliverables

- [x] Manifest types and serialization (`Seihou.Manifest.Types`)
- [x] Three-state diff engine (`Seihou.Engine.Diff`)
- [x] Conflict resolution UX (interactive per-file, `--force` auto-resolution)
- [x] `ManifestStore` effect implementation
- [x] `seihou run` updated for incremental re-runs
- [x] `seihou status` command
- [x] `seihou diff` command
- [x] Content hashing (SHA256) for change detection

---

## M6 — Module Authoring

**Goal**: Tools for creating and validating modules, plus git-based installation.

**Status**: Done

### Deliverables

- [x] `seihou new-module <name>` handler
- [x] `seihou validate-module [<path>]` handler with `--lint` flag
- [x] `seihou install <git-url>` handler with `--name`, `--module`, `--all` flags
- [x] `Process` effect implementation (for git operations)
- [x] Documentation: module authoring guide (user-facing)

---

## M7 — Config & Diagnostics

**Goal**: Configuration management commands and diagnostic warnings.

**Status**: Done

### Deliverables

- [x] `seihou config` subcommands: set, get, unset, list
- [x] Config scope targeting: `--global`, `--namespace`
- [x] `seihou config list --effective` for merged config view across all scopes
- [x] `seihou vars --explain` composition-aware: resolves full module composition
- [x] Diagnostics: unused config key warnings
- [x] Diagnostics: unresolved optional variable reporting in `--explain`
- [x] End-to-end tests for config hierarchy auto-resolution
- [x] User documentation: config-and-variables.md

---

## M8 — Discovery & Registry

**Goal**: Module discovery, browsing, and multi-module repository support.

**Status**: Done

### Deliverables

- [x] `seihou list` command: shows available modules from all discovery paths
- [x] `seihou browse <source>` command: preview modules before installing
- [x] Registry format: `seihou-registry.dhall` with module entries (name, path, description, tags)
- [x] Tag-based filtering in `seihou browse --tag`
- [x] `seihou install` updated for registries: `--module` for selective, `--all` for bulk install
- [x] Origin tracking (`.seihou-origin.json`) for installed modules
- [x] BrowseFormat pure formatting module with golden tests
- [x] User documentation: registries-and-multi-module-repos.md

---

## M9 — Interactive Prompts

**Goal**: Enhanced interactive prompting for both required and optional variables.

**Status**: Done

### Deliverables

- [x] Default value display in prompt text (bracket notation)
- [x] Accept Enter to use default values for required variables
- [x] Optional variable prompting after required resolution
- [x] "Optional configuration:" separator in console output
- [x] Skip optional prompts on empty input (variable stays unresolved)
- [x] Prompt `when` conditions respected for optional prompts
- [x] `resolveWithPrompts` updated in both success and error-recovery paths
- [x] Test fixture: `seihou-core/test/fixtures/prompted-optional/`
- [x] 10 new pure tests (4 default display + 6 optional prompt flow)
- [x] User documentation: module-authoring.md updated with optional prompts section

---

## Definition of Done (V1)

V1 is complete when:

1. All milestones M0–M9 exit criteria are met
2. The haskell-template example from the product spec works end-to-end:
   - `seihou run haskell-base --var project.name=my-app` generates the expected project
   - `seihou status` shows correct state
   - Re-running with a changed variable incrementally updates
3. A multi-module example works (e.g., haskell-base + nix-flake)
4. Module authoring workflow works (new-module → edit → validate → run)
5. Config management works (set → list --effective → vars --explain)
6. Registry workflow works (browse → install --module → run)
7. Interactive prompts work for both required and optional variables
8. All tests pass, CI is green
9. No "TBD" items remain in design docs

## Cross-References

- [Architecture Overview](../architecture/overview.md) — System design
- [Module System](../design/proposed/module-system.md) — M1 details
- [Generation Strategies](../design/proposed/generation-strategies.md) — M2 details
- [CLI Commands](../design/proposed/cli-commands.md) — M3+ details
- [Composition and Layering](../design/proposed/composition-and-layering.md) — M4 details
- [Manifest and Incrementality](../design/proposed/manifest-and-incrementality.md) — M5 details
- [Variable Resolution](../design/proposed/variable-resolution.md) — M7, M9 details
