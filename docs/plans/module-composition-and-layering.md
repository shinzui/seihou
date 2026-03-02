# Module Composition and Layering

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this work, Seihou supports multi-module composition. Today `seihou run` handles exactly one module. After this plan, running `seihou run haskell-with-nix` automatically loads `haskell-with-nix` and its declared dependencies (`haskell-base`, `nix-flake`, etc.), determines the correct execution order via topological sort, flows exported variables from dependencies to dependents, compiles and merges all their plans (handling file ownership and last-writer-wins for overlapping outputs), and executes the combined result. The user can also compose ad-hoc via `seihou run haskell-base --module nix-flake`, which builds an implicit dependency graph from the command line. Circular dependencies are detected and reported with a clear error message showing the cycle path.

This completes the M4 (Composition) milestone from the project roadmap at `docs/dev/roadmap/v1-milestones.md`.


## Progress

- [x] M1: Dependency graph and topological sort (2026-03-01)
  - [x] Create `Seihou.Composition.Graph` with `buildGraph`, `topoSort`, cycle detection (2026-03-01)
  - [x] Add `Seihou.Composition.Graph` to `seihou-core.cabal` exposed-modules (2026-03-01)
  - [x] Create `Seihou.Composition.GraphSpec` with unit tests (2026-03-01)
  - [x] Add `GraphSpec` to test Main.hs and `seihou-core.cabal` other-modules (2026-03-01)
  - [x] All tests pass (237 total, 9 new graph tests), `cabal build all` clean (2026-03-01)
- [x] M2: Multi-module loading and variable export flow (2026-03-01)
  - [x] Create `Seihou.Composition.Resolve` with `loadComposition`, `resolveComposedVariables`, `exportedVars` (2026-03-01)
  - [x] Add `Seihou.Composition.Resolve` to `seihou-core.cabal` exposed-modules (2026-03-01)
  - [x] Create `Seihou.Composition.ResolveSpec` with 10 unit tests (2026-03-01)
  - [x] Add `ResolveSpec` to test Main.hs and `seihou-core.cabal` other-modules (2026-03-01)
  - [x] All tests pass (247 total, 10 new resolve tests), `cabal build all` clean (2026-03-01)
- [x] M3: Composed plan compilation and merged execution (2026-03-01)
  - [x] Add `CompositionWarning` type to `Seihou.Core.Types` (2026-03-01)
  - [x] Create `Seihou.Composition.Plan` with `compileComposedPlan`, `mergeOperations` (2026-03-01)
  - [x] Add `Seihou.Composition.Plan` to `seihou-core.cabal` exposed-modules (2026-03-01)
  - [x] Create `Seihou.Composition.PlanSpec` with 7 unit tests (2026-03-01)
  - [x] Add `PlanSpec` to test Main.hs and `seihou-core.cabal` other-modules (2026-03-01)
  - [x] All tests pass (254 total, 7 new plan composition tests), `cabal build all` clean (2026-03-01)
- [x] M4: CLI wiring and integration tests (2026-03-01)
  - [x] Create multi-module test fixtures: `nix-base`, `nix-flake`, `haskell-with-nix` (2026-03-01)
  - [x] Create `Seihou.Integration.CompositionSpec` with 9 integration tests (2026-03-01)
  - [x] Add `CompositionSpec` to test Main.hs and `seihou-core.cabal` other-modules (2026-03-01)
  - [x] Update `Seihou.CLI.Run` to use composition pipeline (`loadComposition`, `resolveComposedVariables`, `compileComposedPlan`) (2026-03-01)
  - [x] All tests pass (263 total), `nix fmt` clean, `nix flake check` passes (2026-03-01)


## Surprises & Discoveries

- Initial `topoSort` had in-degree computed in the wrong direction — counting how many times a node appears as a dependency (standard graph in-degree) rather than how many dependencies each node has (reversed graph in-degree for dependency-first ordering). Fixed by computing `length [d | d <- deps, Set.member d allNodes]` for each node. The `decrementDep` logic was already correct for the reversed interpretation.

- `Data.Text qualified as T` does not bring the `Text` type into scope unqualified. Required separate `import Data.Text (Text)` in Resolve.hs. Same pattern used across all existing modules.

- The `haskell-with-nix` fixture creates a diamond dependency (haskell-with-nix depends on both haskell-base and nix-flake, nix-flake depends on nix-base). The integration tests confirm correct topological ordering and variable flow through the diamond.


## Decision Log

- Decision: Defer patch operations (AppendSection, ReplaceSection, PrependFile, etc.) to a future plan. For v1 composition, when two modules target the same file, the later module in execution order wins (last-writer-wins). A warning is emitted.
  Rationale: Patch operations require section markers in generated files, parser logic for detecting marker boundaries, and merge logic for each patch type. This is substantial complexity that blocks the core composition feature — topological sort, multi-module loading, variable export flow, and merged execution — which is more valuable to ship first. Last-writer-wins is the documented behavior for Copy strategy and a reasonable v1 default for all strategies. Patches can be layered on in a follow-up plan.
  Date: 2026-03-01

- Decision: Defer structured file merge (Dhall record merge) to a future plan. Structured strategy already returns "not yet implemented" from `compilePlan`.
  Rationale: The Structured strategy itself is unimplemented. Adding composition merge on top of a missing strategy adds no value. When Structured is implemented, its merge semantics can be added then.
  Date: 2026-03-01

- Decision: The composition pipeline lives in a new `Seihou.Composition.*` module namespace rather than extending existing `Seihou.Core.Module` or `Seihou.Engine.Plan`.
  Rationale: Composition is a distinct concern that orchestrates existing components (module loading, variable resolution, plan compilation). A separate namespace keeps the single-module code untouched and testable independently, while the composition layer coordinates between them.
  Date: 2026-03-01

- Decision: The `--module` flag on `seihou run` creates an implicit composition where the additional modules are treated as if the primary module depends on them. Their transitive dependencies are also resolved.
  Rationale: This matches the CLI design in `docs/dev/design/proposed/cli-commands.md` and the `runAdditional` field already parsed in `RunOpts`. It provides an ad-hoc composition mechanism for users who don't want to create a wrapper module.
  Date: 2026-03-01

- Decision: Variable export aliasing uses the `exportAs` field (Dhall field `alias`). When a module declares `exports = [{ var = "project.name", alias = None Text }]`, the variable is exported under its original name. When `alias = Some "app.name"`, it is exported under the alias.
  Rationale: This matches the existing `VarExport` type and the Dhall decoder already implemented in `Seihou.Dhall.Eval`.
  Date: 2026-03-01

- Decision: Exported values are injected as synthetic defaults in VarDecl (replacing the module's own default) rather than adding a new resolution tier between env and default.
  Rationale: This avoids modifying the existing `resolveVariables` function or adding a new VarSource type. CLI and env overrides still take priority. The tradeoff is that exports and defaults share the same priority tier; a future enhancement could add `FromExport ModuleName` as a distinct VarSource.
  Date: 2026-03-01

- Decision: Non-declared exports (variables a module doesn't declare but inherits from a dependency's exports) are added to the per-module resolved map as synthetic ResolvedVar entries.
  Rationale: This ensures that templates in a dependent module can reference variables exported by dependencies even if the dependent module doesn't explicitly declare them. This is needed for the common case where a composition module (like haskell-with-nix) orchestrates other modules without redeclaring all their variables.
  Date: 2026-03-01


## Outcomes & Retrospective

All four milestones completed successfully.

**Files created:**
- `seihou-core/src/Seihou/Composition/Graph.hs` — CompositionGraph type, buildGraph, topoSort (Kahn's algorithm with cycle detection)
- `seihou-core/src/Seihou/Composition/Resolve.hs` — loadComposition (recursive transitive dependency loading), resolveComposedVariables (per-module resolution with export visibility), exportedVars
- `seihou-core/src/Seihou/Composition/Plan.hs` — compileComposedPlan (compile + merge), mergeOperations (last-writer-wins with warnings)
- `seihou-core/test/Seihou/Composition/GraphSpec.hs` — 9 tests
- `seihou-core/test/Seihou/Composition/ResolveSpec.hs` — 10 tests
- `seihou-core/test/Seihou/Composition/PlanSpec.hs` — 7 tests
- `seihou-core/test/Seihou/Integration/CompositionSpec.hs` — 9 integration tests
- 3 test fixture directories: `nix-base/`, `nix-flake/`, `haskell-with-nix/` (each with module.dhall + template files)

**Files modified:**
- `seihou-core/src/Seihou/Core/Types.hs` — Added `CompositionWarning` type
- `seihou-core/seihou-core.cabal` — Added 3 exposed-modules, 4 test other-modules
- `seihou-core/test/Main.hs` — Wired 4 new test modules
- `seihou-cli/src/Seihou/CLI/Run.hs` — Replaced single-module flow with composition pipeline

**Test count:** 228 (pre-existing) + 35 (new) = 263 total, all passing.

**Known limitations:**
- Patch operations (AppendSection, ReplaceSection, etc.) not supported; last-writer-wins only
- Structured strategy merge not implemented (strategy itself is unimplemented)
- Exported values use `FromDefault` as VarSource rather than a dedicated `FromExport` source
- `compileComposedPlan` does IO via `compilePlan`; no pure interpreter for the full pipeline yet


## Context and Orientation

### Project Structure

Seihou is a multi-package Haskell workspace using GHC 9.12.2 with the GHC2024 language standard:

    seihou/
    ├── cabal.project              # Workspace root listing both packages
    ├── seihou-core/               # Library: types, effects, engines
    │   ├── seihou-core.cabal
    │   ├── src/
    │   │   ├── Seihou/Core/       # Types.hs, Module.hs, Expr.hs, Variable.hs
    │   │   ├── Seihou/Dhall/      # Eval.hs
    │   │   ├── Seihou/Effect/     # Filesystem, ManifestStore, Process (+ Interp + Pure each)
    │   │   ├── Seihou/Engine/     # Plan.hs, Template.hs, Execute.hs, Diff.hs
    │   │   └── Seihou/Manifest/   # Types.hs, Hash.hs
    │   └── test/
    │       ├── Main.hs            # Test runner wiring all spec modules
    │       ├── Seihou/            # Unit and integration test specs
    │       └── fixtures/          # haskell-base/, invalid-module/
    ├── seihou-cli/                # Executable: CLI entry point
    │   ├── seihou-cli.cabal
    │   └── src/
    │       ├── Main.hs            # Command dispatch (all 7 commands wired)
    │       └── Seihou/CLI/        # Commands.hs, Run.hs, Status.hs, Init.hs,
    │                              # Vars.hs, Validate.hs, NewModule.hs, Install.hs
    └── flake.nix                  # GHC 9.12.2, treefmt, pre-commit hooks

### What Already Works

The single-module pipeline is fully implemented (228 tests pass): module loading from Dhall, variable resolution with three-layer precedence (CLI > env > default), template rendering, plan compilation for Copy/Template/DhallText strategies, execution engine, manifest persistence, and three-state diff. All seven CLI commands are functional.

The `Module` type already contains `moduleDependencies :: [ModuleName]` and `moduleExports :: [VarExport]`. The `ModuleLoadError` type already contains a `CircularDependency [ModuleName]` constructor. The `RunOpts` type already parses `runAdditional :: [ModuleName]` from `--module` flags, but the field is currently unused in `handleRun`.

### Key Functions and Types

In `seihou-core/src/Seihou/Core/Types.hs`:

    data Module = Module
      { moduleName :: ModuleName
      , moduleDescription :: Maybe Text
      , moduleVars :: [VarDecl]
      , moduleExports :: [VarExport]
      , modulePrompts :: [Prompt]
      , moduleSteps :: [Step]
      , moduleDependencies :: [ModuleName]
      }

    data VarExport = VarExport
      { exportVar :: VarName
      , exportAs :: Maybe VarName    -- Alias; Dhall field is "alias"
      }

    data ModuleLoadError
      = ModuleNotFound ModuleName [FilePath]
      | DhallEvalError ModuleName Text
      | DhallDecodeError ModuleName Text
      | ValidationError ModuleName [Text]
      | CircularDependency [ModuleName]   -- For cycle detection
      | MissingSourceFile ModuleName FilePath

In `seihou-core/src/Seihou/Core/Module.hs`:

    loadModule :: [FilePath] -> ModuleName -> IO (Either ModuleLoadError Module)
    discoverModule :: [FilePath] -> ModuleName -> IO (Either ModuleLoadError FilePath)
    defaultSearchPaths :: IO [FilePath]

In `seihou-core/src/Seihou/Core/Variable.hs`:

    resolveVariables :: [VarDecl] -> Map VarName Text -> Map Text Text
                     -> Either [VarError] (Map VarName ResolvedVar)

In `seihou-core/src/Seihou/Engine/Plan.hs`:

    compilePlan :: FilePath -> Module -> Map VarName VarValue
                -> IO (Either [Text] [Operation])

In `seihou-cli/src/Seihou/CLI/Commands.hs`:

    data RunOpts = RunOpts
      { runModule :: ModuleName
      , runAdditional :: [ModuleName]   -- Currently unused
      , runVars :: [(Text, Text)]
      , runDryRun :: Bool
      , runDiff :: Bool
      , runForce :: Bool
      , runNoCommands :: Bool
      }

In `seihou-cli/src/Seihou/CLI/Run.hs`, the `handleRun` function currently loads a single module, resolves its variables, compiles its plan, and executes it. The `runAdditional` field from `RunOpts` is ignored.

### Terminology

- **Composition graph**: A directed acyclic graph (DAG) where nodes are modules and edges point from a module to its dependencies. If module A depends on module B, there is an edge A → B.
- **Topological sort**: An ordering of graph nodes such that every node appears after all its dependencies. For a dependency graph, this means dependencies are processed before the modules that depend on them.
- **Execution order**: The topological sort result — a list of `ModuleName` values from leaf dependencies to the top-level module.
- **Variable export**: A module marking one of its variables as visible to modules that depend on it. The `VarExport` type specifies the variable name and an optional alias.
- **Last-writer-wins**: When two modules produce a file at the same destination path, the module that runs later (appears later in execution order) overwrites the earlier one. A warning is emitted.

### Build and Test Commands

All commands run from the workspace root (`seihou/`):

    cabal build all          # Build both packages
    cabal test all           # Run all tests
    nix fmt                  # Format with treefmt (fourmolu + cabal-gild)
    nix flake check          # Full CI: build + test + formatting


## Plan of Work

### Milestone 1: Dependency Graph and Topological Sort

This milestone adds the graph data structure, topological sort algorithm, and cycle detection. At the end, given a set of modules, the system can determine the correct execution order or report a cycle.

Create `seihou-core/src/Seihou/Composition/Graph.hs` with the following:

A `CompositionGraph` type that holds a map of module names to modules and a map of module names to their dependency lists (edges). A `buildGraph` function that takes a list of modules and constructs the graph. A `topoSort` function that takes a `CompositionGraph` and returns either an `ExecutionOrder [ModuleName]` (a valid topological ordering where dependencies come before dependents) or a `CyclicDependency [ModuleName]` error showing the cycle path. The topological sort uses Kahn's algorithm (iteratively removing nodes with no incoming edges) which naturally detects cycles (if nodes remain when no more zero-in-degree nodes exist, a cycle is present).

The `topoSort` function must handle:
- A single module with no dependencies (returns just that module).
- A linear chain (A depends on B depends on C → order is C, B, A).
- A diamond (A depends on B and C, both depend on D → D appears once, before B and C, which appear before A).
- A self-loop (A depends on A → cycle error).
- A cycle (A → B → C → A → cycle error).
- Disconnected components (the graph includes modules with no edges between them; all are included in the order).

Create `seihou-core/test/Seihou/Composition/GraphSpec.hs` with tests for all the above cases. Wire it into `test/Main.hs` and `seihou-core.cabal`.

**Acceptance**: `cabal build all` compiles cleanly. `cabal test all` passes with new graph tests.

### Milestone 2: Multi-Module Loading and Variable Export Flow

This milestone adds the orchestration layer that loads all modules in a composition (the primary module plus all transitive dependencies), resolves the execution order, and performs variable resolution across modules with export visibility.

Create `seihou-core/src/Seihou/Composition/Resolve.hs` with the following:

A `loadComposition` function that takes search paths, a primary module name, and a list of additional module names (from `--module` flags). It loads the primary module, loads each additional module, then recursively loads all transitive dependencies declared by any of these modules. It builds a `CompositionGraph` and calls `topoSort`. If loading any module fails, it returns the first `ModuleLoadError`. If a cycle is detected, it returns `CircularDependency`. On success, it returns a list of `(Module, FilePath)` pairs in execution order (the `FilePath` being the discovered module directory, needed by `compilePlan`).

A `resolveComposedVariables` function that takes the modules in execution order, CLI overrides, and environment variables, and resolves all variables with export visibility. The resolution works as follows: for each module in execution order, collect the variable declarations from that module plus any exported variables from its dependencies. The exported variables are the resolved values from previously-processed modules that appear in the dependency's `moduleExports` list. The function calls the existing `resolveVariables` for each module, threading the exports through. The result is a `Map ModuleName (Map VarName ResolvedVar)` — a per-module map of resolved variables.

A helper function `exportedVars` that takes a module and its resolved variables and returns a `Map VarName VarValue` of the exported variables (using the alias name if provided, otherwise the original name).

Create `seihou-core/test/Seihou/Composition/ResolveSpec.hs` with tests for multi-module loading (mock modules constructed in-memory, using the `loadModule` path with test fixtures), variable export flow (module A exports `project.name`, module B sees it), and export aliasing. Wire into test infrastructure.

**Acceptance**: `cabal build all` compiles cleanly. `cabal test all` passes with new resolve tests.

### Milestone 3: Composed Plan Compilation and Merged Execution

This milestone adds the function that compiles plans for all modules in execution order and merges them into a single operation list, handling file ownership and last-writer-wins.

Create `seihou-core/src/Seihou/Composition/Plan.hs` with the following:

A `compileComposedPlan` function that takes a list of `(Module, FilePath, Map VarName VarValue)` triples (module, its directory, its resolved variable values — all in execution order) and compiles a plan for each module by calling the existing `compilePlan`. It then merges the resulting operation lists. The merge logic handles file conflicts: when two modules produce a `WriteFileOp` to the same destination, the later module's operation replaces the earlier one and a `CompositionWarning` is recorded. The function returns the merged `[Operation]` list plus a list of warnings.

A `CompositionWarning` type in `Seihou.Core.Types`:

    data CompositionWarning
      = FileOverwritten FilePath ModuleName ModuleName
      deriving stock (Eq, Show, Generic)

The `FileOverwritten` constructor records the file path, the module whose output was overwritten, and the module that overwrote it.

A helper `mergeOperations` that takes a list of `(ModuleName, [Operation])` pairs and returns `([Operation], [CompositionWarning])`. It processes operations in order, tracking seen destination paths. When a `WriteFileOp` or `CopyFileOp` targets an already-seen path, it removes the earlier operation and adds a warning. `CreateDirOp` operations are deduplicated silently.

Create `seihou-core/test/Seihou/Composition/PlanSpec.hs` with tests for: two modules with no overlapping files (all operations present), two modules writing to the same file (later wins, warning emitted), directory deduplication across modules. Wire into test infrastructure.

**Acceptance**: `cabal build all` compiles cleanly. `cabal test all` passes with new plan composition tests.

### Milestone 4: CLI Wiring and Integration Tests

This milestone wires the composition pipeline into `handleRun` and adds end-to-end integration tests with multi-module fixtures.

Update `seihou-cli/src/Seihou/CLI/Run.hs` to replace the current single-module flow with the composition pipeline. The new flow is:

1. Call `loadComposition` with search paths, `runModule`, and `runAdditional`.
2. Call `resolveComposedVariables` with the modules in execution order, CLI overrides, and environment.
3. Call `compileComposedPlan` with the modules, directories, and per-module variables.
4. Print any composition warnings.
5. Continue with the existing diff/execute/manifest logic using the merged operation list.

The manifest update should record all modules in the composition in `manifestModules`.

Create test fixtures for a multi-module composition. Under `seihou-core/test/fixtures/`, create:

- `nix-base/` — a minimal module with one variable (`nix.system`, default `x86_64-linux`), one template step producing `shell.nix`, and an export of `nix.system`. No dependencies.
- `nix-flake/` — a module depending on `nix-base`, with one variable (`nix.description`, default `A Nix project`), one template step producing `flake.nix`. Depends on `["nix-base"]`. Exports `nix.system` (re-exported from dependency — it declares the same var with the same name, or receives it via export).
- `haskell-with-nix/` — a module depending on `["haskell-base", "nix-flake"]`. No new variables of its own. One template step producing `Makefile`. This module exists to compose haskell-base and nix-flake together.

Actually, for simplicity in test fixtures, `nix-flake` should declare its own variable `nix.description` and depend on `nix-base`. And `haskell-with-nix` should depend on `haskell-base` and `nix-flake` (creating a diamond through the transitive dependency on `nix-base`). The fixtures should each have a `module.dhall` and a `files/` directory with the template files they reference.

Create `seihou-core/test/Seihou/Integration/CompositionSpec.hs` with integration tests:

- Load `haskell-with-nix` composition: verify all four modules load in correct order (nix-base, haskell-base, nix-flake, haskell-with-nix — though the exact relative order of haskell-base and nix-flake may vary as long as both come after nix-base and before haskell-with-nix).
- Resolve variables: verify `project.name` from haskell-base is visible to haskell-with-nix (via exports), and `nix.system` from nix-base is visible to nix-flake and haskell-with-nix.
- Compile composed plan: verify the merged plan includes operations from all four modules.
- Detect a circular dependency: create in-memory modules with a cycle and verify the error.

Wire the test into `test/Main.hs` and `seihou-core.cabal`.

Run `nix fmt` and `nix flake check` to ensure everything is clean.

**Acceptance**: `cabal build all` compiles cleanly. `cabal test all` passes with all new tests. `nix flake check` passes. The `handleRun` function in `Run.hs` handles `runAdditional` modules. Multi-module fixtures demonstrate composition working end-to-end in tests.


## Concrete Steps

Commands are run from the workspace root: `seihou/`.

### Milestone 1

    # After creating Graph.hs and GraphSpec.hs:
    cabal build all
    # Expected: compiles cleanly

    cabal test all
    # Expected: all tests pass including new graph tests

### Milestone 2

    cabal build all
    # Expected: compiles cleanly

    cabal test all
    # Expected: all tests pass including new resolve tests

### Milestone 3

    cabal build all
    # Expected: compiles cleanly

    cabal test all
    # Expected: all tests pass including new plan composition tests

### Milestone 4

    cabal build all
    cabal test all
    # Expected: compiles and all tests pass

    nix fmt
    nix flake check
    # Expected: formatting clean, checks pass


## Validation and Acceptance

### Graph and Topological Sort

Building a graph from modules with dependencies `A→[B,C], B→[D], C→[D], D→[]` produces execution order where D comes first and A comes last. Building a graph with `A→[B], B→[A]` returns `CircularDependency`. A single module with no dependencies returns a single-element list.

### Variable Export Flow

Given module A (declares `project.name`, exports it) and module B (depends on A, uses `project.name` in a template), resolving variables for the composition makes `project.name` available to B with `FromDefault` or `FromCLI` provenance. Module B cannot access A's non-exported variables.

### Composed Plan

Given modules A and B that both write to `README.md`, the composed plan contains only B's `WriteFileOp` for `README.md` (last-writer-wins) and a `FileOverwritten` warning. Both modules' non-overlapping files are present.

### CLI Integration

Running `seihou run haskell-with-nix --var project.name=my-app --dry-run` (with the test fixtures in a search path) shows operations from all composed modules. The `runAdditional` field is used when `--module` flags are provided.

### Automated Tests

All existing 228 tests continue to pass. New tests are added for graph construction, topological sort, cycle detection, variable export flow, composed plan compilation, and integration composition. The full validation is:

    cabal test all
    nix fmt
    nix flake check


## Idempotence and Recovery

- **All milestones are additive**: Each creates new files without modifying existing module logic (except M4 which modifies `Run.hs`). If a milestone fails mid-way, previously passing tests still pass.
- **Graph operations are pure**: `buildGraph` and `topoSort` are pure functions with no IO. They can be called repeatedly with the same input.
- **Module loading is read-only**: `loadComposition` reads Dhall files but does not modify anything.
- **Variable resolution is pure**: `resolveComposedVariables` is a pure function once modules are loaded.
- **Plan compilation is read-only IO**: `compileComposedPlan` reads template files but does not write anything. Execution only happens in the existing `executePlan` step.


## Interfaces and Dependencies

### New Package Dependencies

None. All required libraries (`containers` for `Map`/`Set`, `text`, `effectful-core`) are already in `seihou-core.cabal`.

### New Modules

**`seihou-core/src/Seihou/Composition/Graph.hs`**

    module Seihou.Composition.Graph
      ( CompositionGraph (..)
      , buildGraph
      , topoSort
      ) where

    data CompositionGraph = CompositionGraph
      { cgModules :: Map ModuleName Module
      , cgEdges :: Map ModuleName [ModuleName]
      }
      deriving stock (Eq, Show, Generic)

    -- | Build a composition graph from a list of modules.
    buildGraph :: [Module] -> CompositionGraph

    -- | Topological sort of the composition graph.
    -- Returns execution order (dependencies first) or a cycle error.
    topoSort :: CompositionGraph -> Either ModuleLoadError [ModuleName]

**`seihou-core/src/Seihou/Composition/Resolve.hs`**

    module Seihou.Composition.Resolve
      ( loadComposition
      , resolveComposedVariables
      , exportedVars
      ) where

    -- | Load all modules in a composition: primary + additional + transitive deps.
    -- Returns modules with their directories in execution order.
    loadComposition
      :: [FilePath]                          -- Search paths
      -> ModuleName                          -- Primary module
      -> [ModuleName]                        -- Additional modules (--module flags)
      -> IO (Either ModuleLoadError [(Module, FilePath)])

    -- | Resolve variables for all modules with export visibility.
    resolveComposedVariables
      :: [(Module, FilePath)]                -- Modules in execution order
      -> Map VarName Text                    -- CLI overrides
      -> Map Text Text                       -- Environment variables
      -> Either [VarError] (Map ModuleName (Map VarName ResolvedVar))

    -- | Extract exported variables from a module's resolved values.
    exportedVars :: Module -> Map VarName ResolvedVar -> Map VarName VarValue

**`seihou-core/src/Seihou/Composition/Plan.hs`**

    module Seihou.Composition.Plan
      ( compileComposedPlan
      , mergeOperations
      ) where

    -- | Compile plans for all modules and merge into a single operation list.
    compileComposedPlan
      :: [(Module, FilePath, Map VarName VarValue)]  -- Modules with dirs and vars
      -> IO (Either [Text] ([Operation], [CompositionWarning]))

    -- | Merge operation lists from multiple modules, handling file conflicts.
    mergeOperations
      :: [(ModuleName, [Operation])]
      -> ([Operation], [CompositionWarning])

### New Types in `seihou-core/src/Seihou/Core/Types.hs`

    data CompositionWarning
      = FileOverwritten FilePath ModuleName ModuleName
      deriving stock (Eq, Show, Generic)

### Modified Files

- `seihou-core/src/Seihou/Core/Types.hs` — Add `CompositionWarning` type to module exports
- `seihou-core/seihou-core.cabal` — Add three new exposed-modules under `Seihou.Composition.*`, add four new test other-modules under `Seihou.Composition.*Spec` and `Seihou.Integration.CompositionSpec`
- `seihou-core/test/Main.hs` — Wire four new test modules
- `seihou-cli/src/Seihou/CLI/Run.hs` — Replace single-module flow with composition pipeline
- `seihou-core/test/fixtures/` — Add `nix-base/`, `nix-flake/`, `haskell-with-nix/` fixture directories
