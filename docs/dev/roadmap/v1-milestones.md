# V1 Milestones

| Field | Value |
|---|---|
| **Status** | Proposed |
| **Created** | 2026-03-01 |

## Overview

V1 of Seihou delivers a complete, usable project scaffolding system: module loading, generation, composition, incrementality, and a CLI for the core workflow. The milestones are ordered by dependency — each builds on the prior.

## Milestone Summary

| Milestone | Name | Depends On | Delivers |
|---|---|---|---|
| M0 | Project Bootstrap | — | Nix flake, cabal workspace, CI, core types |
| M1 | Module Loading | M0 | Dhall module parsing, validation, variable declarations |
| M2 | Generation Engine | M1 | Plan compilation, placeholder engine, file writing |
| M3 | CLI Core | M2 | init, run (single module, one-shot), vars |
| M4 | Composition | M3 | Module dependencies, layering, patch operations |
| M5 | Incrementality | M4 | Manifest tracking, three-state diff, status |
| M6 | Module Authoring | M5 | new-module, validate-module, install |

## M0 — Project Bootstrap

**Goal**: Repository structure, build system, and foundational types.

### Deliverables

- [ ] Nix flake with GHC 9.12.2, development shell, CI check
- [ ] Cabal workspace with `seihou-core` and `seihou-cli` packages
- [ ] Core domain types in `Seihou.Core.Types`:
  - `Module`, `ModuleName`, `VarDecl`, `VarName`, `VarType`, `VarValue`
  - `Prompt`, `Step`, `Strategy`, `Expr`
  - `Operation` (filesystem operations)
- [ ] Effect definitions (interfaces only, no implementations):
  - `Filesystem`, `Console`, `DhallEval`, `ConfigReader`, `ManifestStore`, `Process`, `Logger`
- [ ] Test infrastructure: tasty + hspec, test helpers
- [ ] CI: `nix flake check` runs build + tests

### Exit Criteria

- `cabal build all` succeeds
- `cabal test all` succeeds (with placeholder tests)
- `nix flake check` passes
- All core types compile and have `Eq`, `Show`, `Generic` instances

---

## M1 — Module Loading

**Goal**: Parse Dhall module definitions into typed Haskell values and validate them.

### Deliverables

- [ ] Dhall schema for module definitions (`schema/Module.dhall`)
- [ ] Dhall evaluation bridge (`Seihou.Dhall.Eval`):
  - Evaluate `module.dhall` → `Module` value
  - Error handling for Dhall type errors and evaluation failures
- [ ] Module discovery (`Seihou.Core.Module`):
  - Search path: local → user → installed
  - Explicit path resolution
- [ ] Module validation (`Seihou.Core.Module`):
  - Name format, unique variables, prompt references, file existence, export references
- [ ] Variable declaration types with validation rules
- [ ] Expression language parser and evaluator (`Seihou.Core.Expr`)
- [ ] `DhallEval` effect implementation (real + test)
- [ ] Test the haskell-template example module loads correctly

### Exit Criteria

- Can load the haskell-template example from the product spec
- Invalid modules produce clear, actionable error messages
- Expression parser handles all grammar cases
- Module validation catches all rules from the spec

---

## M2 — Generation Engine

**Goal**: Compile loaded modules into a generation plan and execute it.

### Deliverables

- [ ] Plan compilation (`Seihou.Engine.Plan`):
  - Module steps → `[Operation]`
  - Strategy dispatch per step
- [ ] Generation strategies:
  - Copy (`Seihou.Engine.Strategy.Copy`)
  - Template with placeholder engine (`Seihou.Engine.Strategy.Template`)
  - DhallText (`Seihou.Engine.Strategy.DhallText`)
  - Structured JSON/YAML (`Seihou.Engine.Strategy.Structured`)
- [ ] Placeholder engine:
  - Parse `{{var.name}}` syntax
  - Escape handling (`\{{`)
  - Type coercion (Bool/Int/List → Text)
  - Error on unresolved placeholders
- [ ] Variable resolution (`Seihou.Core.Variable`):
  - Multi-layer precedence: CLI → env → local → namespace → global → default
  - Provenance tracking per variable
  - Type checking and validation
- [ ] Plan execution (`Seihou.Engine.Execute`):
  - Write files, create directories
  - `Filesystem` effect implementation (real + in-memory test)
- [ ] Config resolution (`Seihou.Config.Resolution`):
  - Global, namespace, local Dhall config loading
  - Environment variable mapping

### Exit Criteria

- haskell-template example generates correct output files
- Placeholder engine handles all syntax edge cases
- Variable resolution respects precedence order
- `--dry-run` shows plan without writing

---

## M3 — CLI Core

**Goal**: Working CLI with init, run (single module), and vars commands.

### Deliverables

- [ ] optparse-applicative command parser (`Seihou.CLI.Commands`)
- [ ] `seihou init` handler:
  - Create config directories
  - Generate default config.dhall
  - Idempotent behavior
- [ ] `seihou run <module>` handler (single module, one-shot):
  - Module loading → variable resolution → plan compilation → execution
  - Interactive prompts for missing required variables
  - `--dry-run`, `--diff`, `--force`, `--no-commands` flags
  - `Console` effect implementation
- [ ] `seihou vars <module>` handler:
  - Display resolved variables
  - `--explain` flag for provenance
- [ ] Error output formatting (stderr, exit codes)
- [ ] `Logger` effect implementation

### Exit Criteria

- `seihou init` creates config directories
- `seihou run haskell-base --var project.name=my-app` generates a project
- `seihou run haskell-base --dry-run` shows plan
- `seihou vars haskell-base --explain` shows provenance
- Correct exit codes for all error conditions
- Non-interactive mode works (all vars via --var, no TTY)

---

## M4 — Composition

**Goal**: Multiple modules compose via dependencies and layering.

### Deliverables

- [ ] Dependency graph construction (`Seihou.Composition.Graph`):
  - Parse `dependencies` from modules
  - Topological sort for execution order
  - Cycle detection with error path
- [ ] Layering engine (`Seihou.Composition.Layering`):
  - Structured file merge (Dhall record merge semantics)
  - Text file patch operations (append-section, replace-section, prepend)
  - Copy file last-writer-wins with warning
- [ ] Conflict detection (`Seihou.Composition.Conflict`):
  - Scalar merge conflicts in structured files
  - Section overlap in text files
  - Copy destination conflicts
- [ ] Variable export/import:
  - Export visibility enforcement
  - Cross-module variable resolution
- [ ] `seihou run` updated to handle `--module` flag for multi-module composition
- [ ] Section markers in generated text files

### Exit Criteria

- `seihou run haskell-with-nix` composes haskell-base + nix-flake correctly
- Diamond dependencies execute each module once
- Circular dependencies produce clear error
- Variable exports flow between dependent modules
- Structured file merging works for nested records
- Text file patching appends/replaces sections correctly

---

## M5 — Incrementality

**Goal**: State tracking via manifest, incremental re-generation, conflict detection.

### Deliverables

- [ ] Manifest types and serialization (`Seihou.Manifest.Types`, `Read`, `Write`):
  - JSON serialization/deserialization
  - Atomic file writes
- [ ] Three-state diff engine (`Seihou.Engine.Diff`):
  - Manifest vs Plan vs Disk comparison
  - File classification: New, Modified, Unchanged, Conflict, Orphaned
- [ ] Conflict resolution UX:
  - Interactive per-file resolution (accept new, keep current, skip, abort)
  - `--force` auto-resolution
- [ ] `ManifestStore` effect implementation
- [ ] `seihou run` updated:
  - Load manifest on re-run
  - Show incremental diff
  - Update manifest after execution
- [ ] `seihou status` command:
  - Display applied modules, tracked files with status, variables
- [ ] Content hashing (SHA256) for change detection

### Exit Criteria

- First `run` creates manifest
- Re-run with changed variable only updates affected files
- User modification of generated file detected as conflict
- Interactive conflict resolution works
- `--force` overrides all conflicts
- `seihou status` correctly classifies all file states
- Manifest survives roundtrip (write → read → compare)

---

## M6 — Module Authoring

**Goal**: Tools for creating and validating modules, plus git-based installation.

### Deliverables

- [ ] `seihou new-module <name>` handler:
  - Scaffold module directory with boilerplate
  - Generated module passes validation
- [ ] `seihou validate-module [<path>]` handler:
  - All validation rules from module system spec
  - Clear error messages with line/field context
  - Check mark output for each validation step
- [ ] `seihou install <git-url>` handler:
  - Git clone to temp directory
  - Validate cloned module
  - Copy to installed modules directory
  - `--name` override
- [ ] `Process` effect implementation (for git operations)
- [ ] Documentation: module authoring guide (user-facing)

### Exit Criteria

- `seihou new-module my-template` creates valid module scaffold
- `seihou validate-module` catches all validation errors
- `seihou install <url>` clones, validates, and installs
- Installed module is discoverable and runnable
- Generated module scaffold passes `validate-module`

## Definition of Done (V1)

V1 is complete when:

1. All milestones M0–M6 exit criteria are met
2. The haskell-template example from the product spec works end-to-end:
   - `seihou run haskell-base --var project.name=my-app` generates the expected project
   - `seihou status` shows correct state
   - Re-running with a changed variable incrementally updates
3. A multi-module example works (e.g., haskell-base + nix-flake)
4. Module authoring workflow works (new-module → edit → validate → run)
5. All tests pass, CI is green
6. No "TBD" items remain in design docs

## Cross-References

- [Architecture Overview](../architecture/overview.md) — System design
- [Module System](../design/proposed/module-system.md) — M1 details
- [Generation Strategies](../design/proposed/generation-strategies.md) — M2 details
- [CLI Commands](../design/proposed/cli-commands.md) — M3 details
- [Composition and Layering](../design/proposed/composition-and-layering.md) — M4 details
- [Manifest and Incrementality](../design/proposed/manifest-and-incrementality.md) — M5 details
