---
slug: filesystem-execution-and-manifest-tracking
title: "Filesystem Execution and Manifest Tracking"
kind: exec-plan
created_at: 2026-03-02T04:19:33Z
---


# Filesystem Execution and Manifest Tracking

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this work, `seihou run` will be able to execute a generation plan against a real
filesystem, track what was generated in a manifest file (`.seihou/manifest.json`), and
on subsequent runs, detect which files changed, which the user modified, and which are
orphaned. The `--dry-run` flag will print the plan without writing anything. The user
can run `seihou status` to see the current state of generated files.

This bridges the gap between the plan compiler (M2, already built) and a working CLI
(M3). Today, `compilePlan` produces `[Operation]` in IO but nothing executes those
operations or records state. After this plan, the full pipeline works:
load → resolve → compile → diff → execute → record manifest.


## Progress

- [x] M1: Expand Manifest types and add JSON serialization (2026-03-01)
  - [x] Replace stub `Manifest` in `Types.hs` with full record type
  - [x] Add `AppliedModule`, `FileRecord`, `SHA256` types
  - [x] Add `DiffResult` and classification types
  - [x] Add `ConflictResolution` type
  - [x] Add `aeson`, `cryptohash-sha256`, `time`, `bytestring`, `base16-bytestring` dependencies
  - [x] Create `Seihou.Manifest.Types` with JSON instances
  - [x] Create `Seihou.Manifest.Hash` with SHA256 content hashing
  - [x] Write `ManifestTypesSpec` tests (14 new tests, 178 total)
  - [x] Fix existing `TypesSpec` test that used old stub `Manifest` constructor
- [x] M2: Filesystem effect interpreter (2026-03-01)
  - [x] Create `Seihou.Effect.FilesystemInterp` (real IO interpreter)
  - [x] Create `Seihou.Effect.FilesystemPure` (in-memory `PureFS` with `reinterpret`/`State`)
  - [x] Write `FilesystemSpec` tests (9 pure + 5 real = 14 new tests, 192 total)
- [x] M3: ManifestStore effect interpreter (2026-03-01)
  - [x] Create `Seihou.Effect.ManifestStoreInterp` (JSON via Filesystem effect)
  - [x] Create `Seihou.Effect.ManifestStorePure` (in-memory with `reinterpret`/`State`)
  - [x] Write `ManifestStoreSpec` tests (4 pure + 3 real-via-pure = 7 new tests, 199 total)
- [x] M4: Execution engine (2026-03-01)
  - [x] Create `Seihou.Engine.Execute` — `executePlan` via `Filesystem` effect
  - [x] Build `FileRecord` entries with SHA256 hashes from executed operations
  - [x] `dryRunPlan` returns human-readable text without executing
  - [x] Write `ExecuteSpec` tests (8 executePlan + 6 dryRunPlan = 14 new tests, 213 total)
- [x] M5: Three-state diff engine (2026-03-01)
  - [x] Create `Seihou.Engine.Diff` — classify files across manifest/plan/disk
  - [x] Implement all classification cases from the design doc
  - [x] Write `DiffSpec` tests for each classification case (10 new tests, 223 total)
- [x] M6: Integration — full pipeline and CLI wiring (2026-03-01)
  - [x] Wire `run` command handler: load → resolve → compile → diff → execute → save manifest
  - [x] Wire `status` command handler: load manifest → classify → display
  - [x] Wire `--dry-run`, `--diff`, and `--force` flags
  - [x] Write integration tests for full pipeline (5 new tests, 228 total)
  - [x] All tests pass, `nix fmt`, `nix flake check`


## Surprises & Discoveries

- The existing `TypesSpec.hs` had a test `Manifest \`shouldBe\` Manifest` which
  relied on the old nullary `Manifest` constructor. Replacing the stub with a record
  type broke this test because hspec's `shouldBe` requires `Serial` instances for
  SmallCheck, which don't exist for `Map FilePath FileRecord`. Fixed by replacing
  the test with a simpler `SHA256` field accessor test.

- The `when` function from `Control.Monad` is not in the GHC2024 default Prelude.
  Required explicit `import Control.Monad (when)` in `Seihou.CLI.Run`.

- `loadModule` from `Seihou.Core.Module` does not expose the discovered module
  directory. The CLI handler needs both the directory (for `compilePlan`) and the
  validated module. Solved by calling `discoverModule` separately and then loading
  via `evalModuleFromFile` + `validateModule` from the discovered dir. This avoids
  modifying the existing public API.


## Decision Log

- Decision: Scope this plan to cover execution + manifest + diff but NOT interactive
  conflict resolution UX (prompting the user to choose per-file). Conflicts are
  detected and reported, and `--force` resolves them, but interactive resolution
  is deferred to the M3 (CLI Core) plan.
  Rationale: Interactive prompting requires the `Console` effect interpreter, which
  is not yet implemented. Keeping this plan focused on the engine layer avoids
  coupling to TTY concerns. The `--force` flag covers the non-interactive case.
  Date: 2026-03-01

- Decision: Use `cryptohash-sha256` for SHA256 hashing rather than `cryptonite`.
  Rationale: `cryptohash-sha256` is a minimal, well-maintained package with no
  native dependencies. `cryptonite` is heavier and has had maintenance concerns.
  The `hashable` family of packages also depends on `cryptohash-sha256`, so it is
  widely trusted. If it turns out to be unavailable in the Nix package set, fall
  back to `cryptonite`.
  Date: 2026-03-01

- Decision: The `Filesystem` real interpreter uses `System.Directory` and
  `Data.Text.IO` directly. No `UnliftIO` or bracket-based resource management
  is needed for v1 since all operations are short-lived.
  Rationale: Keep it simple. File writes are small text files; no streaming needed.
  Date: 2026-03-01

- Decision: `time` package for `UTCTime` in manifest types.
  Rationale: Already a boot package (ships with GHC). No extra dependency cost.
  Date: 2026-03-01

- Decision: Keep `Plan.hs` as-is (raw IO) for now; execution uses the effect
  stack. The plan compiler reads source files directly; execution writes output
  files via the `Filesystem` effect. Refactoring plan compilation to use effects
  is deferred.
  Rationale: The plan compiler is working and tested. Refactoring it now would be
  churn without user-visible benefit.
  Date: 2026-03-01


## Outcomes & Retrospective

All 6 milestones completed. 228 tests pass (64 new tests added). `nix fmt` and
`nix flake check` pass.

**What was built:**
- Full manifest type system with JSON serialization and SHA256 hashing
- Real and pure interpreters for both `Filesystem` and `ManifestStore` effects
- Execution engine that converts `[Operation]` to filesystem writes + `FileRecord` entries
- Three-state diff engine classifying files across manifest/plan/disk
- CLI `run` handler: full pipeline from module loading through manifest persistence
- CLI `status` handler: manifest introspection
- Integration tests exercising the complete pipeline with the `haskell-base` fixture

**Architecture outcomes:**
- The `effectful` `reinterpret (runState initial) handler` pattern proved clean
  for building pure test interpreters. All engine code is testable without touching
  the real filesystem.
- Layering `ManifestStore` on top of `Filesystem` effect composition worked well —
  the real manifest store is just JSON serialization atop filesystem reads/writes.
- The three-state diff model (manifest vs plan vs disk) correctly identifies all
  classification cases: New, Modified, Unchanged, Conflict, and Orphaned.

**Known limitations:**
- `executePlan` always sets `fileStrategy = Template` for `WriteFileOp` operations,
  regardless of the actual strategy used by the plan compiler. This is cosmetic
  since the strategy field is informational.
- Interactive conflict resolution is deferred (only `--force` auto-resolution).
- `compilePlan` uses raw IO; refactoring it to use the `Filesystem` effect is deferred.


## Context and Orientation

### Project Structure

Seihou is a multi-package Haskell workspace:

```
seihou/
├── cabal.project              # Workspace root listing both packages
├── seihou-core/               # Library: types, effects, engines
│   ├── seihou-core.cabal
│   ├── src/
│   │   ├── Seihou/Core/       # Types.hs, Module.hs, Expr.hs, Variable.hs
│   │   ├── Seihou/Dhall/      # Eval.hs
│   │   ├── Seihou/Effect/     # Filesystem.hs, ManifestStore.hs, Console.hs,
│   │   │                      # Logger.hs, DhallEval.hs, DhallEvalInterp.hs,
│   │   │                      # ConfigReader.hs, Process.hs
│   │   └── Seihou/Engine/     # Plan.hs, Template.hs
│   └── test/
│       ├── Main.hs            # Tasty test runner (9 modules wired up)
│       ├── Seihou/Core/       # ExprSpec, ModuleSpec, TypesSpec, VariableSpec
│       ├── Seihou/Dhall/      # EvalSpec
│       ├── Seihou/Engine/     # PlanSpec, TemplateSpec
│       ├── Seihou/Integration/ # GenerationSpec, ModuleLoadSpec
│       └── fixtures/          # haskell-base/ (module.dhall + files/), invalid-module/
├── seihou-cli/                # Executable: CLI entry point
│   ├── seihou-cli.cabal
│   └── src/
│       ├── Main.hs            # Parses command, runs handler
│       └── Seihou/CLI/Commands.hs  # optparse-applicative parser
└── flake.nix                  # GHC 9.12.2, treefmt, pre-commit hooks
```

### Key Types Already Defined

In `seihou-core/src/Seihou/Core/Types.hs`:

- **`Operation`**: The plan compiler's output. Four constructors: `WriteFileOp dest content`,
  `CreateDirOp path`, `CopyFileOp src dest`, `RunCommandOp command workDir`.
- **`Manifest`**: Currently a stub (`data Manifest = Manifest`). This plan replaces it.
- **`Module`**, **`Step`**, **`Strategy`**: Module structure and generation steps.
- **`VarName`**, **`VarValue`**: Variable identifiers and values.

### Effect Interfaces Already Defined (No Interpreters)

In `seihou-core/src/Seihou/Effect/`:

- **`Filesystem`**: `ReadFileText`, `WriteFileText`, `CopyFile`, `ListDirectory`,
  `CreateDirectoryIfMissing`, `DoesFileExist`, `DoesDirectoryExist`, `GetCurrentDirectory`.
  Uses `Effectful.Dispatch.Dynamic`.
- **`ManifestStore`**: `ReadManifest`, `WriteManifest`. Uses `Effectful.Dispatch.Dynamic`.
  Currently parameterized on the stub `Manifest` type.
- **`Console`**: `PutText`, `PutError`, `GetLine`, `Confirm`, `IsInteractive`.
- **`Logger`**: `LogDebug`, `LogInfo`, `LogWarn`, `LogError`.

Only `DhallEvalInterp` has a real interpreter today. All others are interface-only.

### What Already Works

- Module loading from Dhall (`Seihou.Core.Module.loadModule`)
- Variable resolution with 3-layer precedence (`Seihou.Core.Variable.resolveVariables`)
- Template placeholder rendering (`Seihou.Engine.Template.renderTemplate`)
- Plan compilation: Copy, Template, DhallText strategies (`Seihou.Engine.Plan.compilePlan`)
- 164 passing tests across 9 test modules

### What This Plan Adds

1. Full `Manifest` type with `AppliedModule`, `FileRecord`, `SHA256`, JSON serialization
2. Three-state diff types: `DiffResult`, `PlannedFile`, `ModifiedFile`, `ConflictFile`, `OrphanedFile`
3. `Filesystem` effect interpreters: real IO + in-memory for testing
4. `ManifestStore` effect interpreters: JSON file + in-memory for testing
5. SHA256 content hashing
6. Execution engine: `[Operation]` → filesystem writes → manifest entries
7. Three-state diff engine: manifest vs plan vs disk classification
8. CLI handler wiring for `run` and `status`

### Design Reference

The manifest schema, three-state diff model, file classification logic, and conflict
resolution design are fully specified in
`docs/dev/design/proposed/manifest-and-incrementality.md`. This plan implements that
design.

### Build and Test Commands

All commands run from the workspace root (`seihou/`):

```bash
cabal build all          # Build both packages
cabal test all           # Run all tests
nix fmt                  # Format with treefmt (fourmolu + cabal-gild)
nix flake check          # Full CI: build + test + formatting
```

### Terminology

- **Plan**: The list of `[Operation]` produced by `compilePlan`. Describes what would
  be generated, without side effects.
- **Manifest**: JSON file at `.seihou/manifest.json` recording what was generated,
  including content hashes and module provenance.
- **Three-state diff**: Comparison of manifest (last generated), plan (what would be
  generated now), and disk (current filesystem state).
- **Classification**: Categorizing each file as New, Modified, Unchanged, Conflict,
  Orphaned, or Untracked based on the three-state comparison.
- **Effect**: An `effectful` dynamic dispatch effect — a GADT describing operations
  that are interpreted by a handler at runtime.
- **Interpreter**: The `effectful` handler that gives meaning to an effect (e.g.,
  real IO vs in-memory for testing).


## Plan of Work

### Milestone 1: Manifest Types and JSON Serialization

Replace the stub `Manifest` type with the full record structure from the design doc.
Add `AppliedModule`, `FileRecord`, `SHA256` newtypes. Add three-state diff result
types. Add `ConflictResolution`. Implement JSON serialization via `aeson` with
`deriving (FromJSON, ToJSON)` via generics. Implement SHA256 content hashing using
`cryptohash-sha256`. Write tests for roundtrip serialization and hashing.

At the end of this milestone: all new types compile, JSON roundtrip tests pass,
hashing produces expected digests.

**Files to create:**
- `seihou-core/src/Seihou/Manifest/Types.hs` — JSON instances, smart constructors
- `seihou-core/src/Seihou/Manifest/Hash.hs` — SHA256 hashing of `Text` content
- `seihou-core/test/Seihou/Manifest/TypesSpec.hs` — Roundtrip and hash tests

**Files to modify:**
- `seihou-core/src/Seihou/Core/Types.hs` — Replace `Manifest` stub, add new types
- `seihou-core/seihou-core.cabal` — Add `aeson`, `cryptohash-sha256`, `time`,
  `bytestring`, `base16-bytestring` dependencies; add new modules to `exposed-modules`
  and `other-modules`
- `seihou-core/src/Seihou/Effect/ManifestStore.hs` — Import updated `Manifest` type
  (no code changes needed since it already imports from `Types`)
- `seihou-core/test/Main.hs` — Wire new test module

**Acceptance:**
```bash
cabal build seihou-core
cabal test seihou-core
# New tests pass: Manifest JSON roundtrip, SHA256 hashing
```

### Milestone 2: Filesystem Effect Interpreters

Create the real IO interpreter for the `Filesystem` effect using `System.Directory`
and `Data.Text.IO`. Create the in-memory pure interpreter using an `IORef (Map FilePath Text)`
(or `effectful`'s `State` effect) for testing. Write tests that exercise both
interpreters.

At the end of this milestone: the `Filesystem` effect can be used in both production
and test contexts. Tests verify that `writeFileText` followed by `readFileText` returns
the content, directories are created, etc.

**Files to create:**
- `seihou-core/src/Seihou/Effect/FilesystemInterp.hs` — `runFilesystem` (real IO)
- `seihou-core/src/Seihou/Effect/FilesystemPure.hs` — `runFilesystemPure` (in-memory)
- `seihou-core/test/Seihou/Effect/FilesystemSpec.hs` — Tests for both interpreters

**Files to modify:**
- `seihou-core/seihou-core.cabal` — Add new modules
- `seihou-core/test/Main.hs` — Wire new test module

**Acceptance:**
```bash
cabal test seihou-core
# FilesystemSpec tests pass: read/write roundtrip, directory creation, file existence
```

### Milestone 3: ManifestStore Effect Interpreters

Create the real interpreter that reads/writes `.seihou/manifest.json` using the
`Filesystem` effect (layered composition). Atomic writes: write to temp file, then
rename. Create the in-memory interpreter for testing.

At the end of this milestone: manifests can be persisted to disk and loaded back.

**Files to create:**
- `seihou-core/src/Seihou/Effect/ManifestStoreInterp.hs` — `runManifestStore` (real)
- `seihou-core/src/Seihou/Effect/ManifestStorePure.hs` — `runManifestStorePure` (in-memory)
- `seihou-core/test/Seihou/Effect/ManifestStoreSpec.hs` — Tests

**Files to modify:**
- `seihou-core/seihou-core.cabal` — Add new modules
- `seihou-core/test/Main.hs` — Wire new test module

**Acceptance:**
```bash
cabal test seihou-core
# ManifestStoreSpec tests pass: write → read roundtrip, missing manifest returns Nothing
```

### Milestone 4: Execution Engine

Create `Seihou.Engine.Execute` that takes `[Operation]` and executes them via the
`Filesystem` effect. For each operation, record a `FileRecord` in a map that will
become part of the manifest. Support `--dry-run` by providing an alternative code
path that formats the plan as human-readable text without executing.

At the end of this milestone: given a list of operations and the in-memory filesystem,
the execution engine writes all files and produces a map of `FileRecord` entries.

**Files to create:**
- `seihou-core/src/Seihou/Engine/Execute.hs` — `executePlan`, `dryRunPlan`
- `seihou-core/test/Seihou/Engine/ExecuteSpec.hs` — Tests using pure filesystem

**Files to modify:**
- `seihou-core/seihou-core.cabal` — Add new modules
- `seihou-core/test/Main.hs` — Wire new test module

**Key function signatures:**

```haskell
-- In Seihou.Engine.Execute:
executePlan
  :: (Filesystem :> es, Logger :> es)
  => FilePath           -- Target directory
  -> [Operation]        -- Plan operations
  -> ModuleName         -- Module that produced these operations
  -> Eff es (Map FilePath FileRecord)

dryRunPlan :: [Operation] -> Text  -- Human-readable plan description
```

**Acceptance:**
```bash
cabal test seihou-core
# ExecuteSpec: operations produce correct filesystem state, FileRecords have correct hashes
```

### Milestone 5: Three-State Diff Engine

Create `Seihou.Engine.Diff` that compares the manifest, plan (list of operations),
and disk state (via `Filesystem` effect) to produce a `DiffResult`. Implement the
full classification table from the design doc.

At the end of this milestone: given a manifest, a list of planned operations, and an
in-memory filesystem representing disk state, the diff engine correctly classifies
every file.

**Files to create:**
- `seihou-core/src/Seihou/Engine/Diff.hs` — `computeDiff`
- `seihou-core/test/Seihou/Engine/DiffSpec.hs` — Tests for all classification cases

**Key function signature:**

```haskell
-- In Seihou.Engine.Diff:
computeDiff
  :: (Filesystem :> es)
  => Manifest           -- Last recorded state (or empty manifest for first run)
  -> [(FilePath, Text)] -- Plan: (destination, content) pairs extracted from operations
  -> Eff es DiffResult
```

**Acceptance:**
```bash
cabal test seihou-core
# DiffSpec: all 7 classification cases pass (New, Conflict-exists, Modified, Conflict-user,
#           Unchanged, Orphaned-present, Orphaned-deleted)
```

### Milestone 6: Integration — Full Pipeline and CLI Wiring

Wire the full pipeline in the CLI `run` handler: load module → resolve variables →
compile plan → compute diff → execute (or dry-run) → save manifest. Wire the `status`
handler to load the manifest and display file states. Write integration tests that
exercise the full pipeline with the fixture module.

At the end of this milestone: `cabal run seihou -- run haskell-base --var project.name=my-app`
generates files in the current directory. `cabal run seihou -- run haskell-base --dry-run --var project.name=my-app`
prints the plan. `cabal run seihou -- status` prints the manifest state.

**Files to create:**
- `seihou-cli/src/Seihou/CLI/Run.hs` — `run` command handler
- `seihou-cli/src/Seihou/CLI/Status.hs` — `status` command handler
- `seihou-core/test/Seihou/Integration/ExecutionSpec.hs` — Full pipeline integration tests

**Files to modify:**
- `seihou-cli/src/Main.hs` — Dispatch to new handlers
- `seihou-cli/seihou-cli.cabal` — Add new modules, add dependencies (effectful-core,
  containers, directory, filepath, seihou-core)
- `seihou-core/seihou-core.cabal` — Add integration test module
- `seihou-core/test/Main.hs` — Wire new integration test

**Acceptance:**
```bash
cabal build all
cabal test all
nix fmt
nix flake check
# All pass. Integration tests exercise: first run creates manifest, re-run detects
# unchanged files, variable change triggers re-generation, --dry-run shows plan
# without writing, --force overwrites conflicts.
```


## Concrete Steps

Commands are run from the workspace root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/`.

### Milestone 1

```bash
# After editing Types.hs, creating Manifest/Types.hs, Manifest/Hash.hs, and test:
cabal build seihou-core
# Expected: compiles cleanly
cabal test seihou-core
# Expected: all existing 164 tests pass + new ManifestTypesSpec tests pass
```

### Milestone 2

```bash
cabal build seihou-core
cabal test seihou-core
# Expected: all tests pass + FilesystemSpec tests pass
```

### Milestone 3

```bash
cabal build seihou-core
cabal test seihou-core
# Expected: all tests pass + ManifestStoreSpec tests pass
```

### Milestone 4

```bash
cabal build seihou-core
cabal test seihou-core
# Expected: all tests pass + ExecuteSpec tests pass
```

### Milestone 5

```bash
cabal build seihou-core
cabal test seihou-core
# Expected: all tests pass + DiffSpec tests pass
```

### Milestone 6

```bash
cabal build all
cabal test all
nix fmt
nix flake check
# Expected: all pass, formatting clean
```


## Validation and Acceptance

### Unit Tests

1. **ManifestTypesSpec**: Manifest JSON roundtrip (encode → decode = identity).
   SHA256 hashing of known content matches expected hex digest. Empty manifest
   serializes correctly. FileRecord with all fields roundtrips.

2. **FilesystemSpec**: Write then read returns same content. `doesFileExist` returns
   `True` after write, `False` before. `createDirectoryIfMissing` is idempotent.
   `copyFile` produces identical content at destination. Both real and pure
   interpreters behave identically.

3. **ManifestStoreSpec**: Write manifest then read returns `Just manifest`. Read
   without prior write returns `Nothing`. Written JSON file is valid and parseable.
   Atomic write: partial write leaves no corrupt file.

4. **ExecuteSpec**: `WriteFileOp` creates file with correct content.
   `CreateDirOp` creates directory. `CopyFileOp` copies content. Execution
   returns `FileRecord` entries with correct SHA256 hashes.
   `dryRunPlan` returns text listing all operations without side effects.

5. **DiffSpec**: Each classification case from the table:
   - File in plan only → New
   - File in plan + on disk (not in manifest) → Conflict
   - File in manifest + plan + disk, disk=manifest → Modified or Unchanged
   - File in manifest + plan + disk, disk≠manifest → Conflict
   - File in manifest only (present on disk) → Orphaned
   - File in manifest only (absent from disk) → Orphaned (deleted)
   - File on disk only → Untracked

### Integration Tests

6. **Full pipeline**: Load `haskell-base` fixture, resolve variables, compile plan,
   execute into a temp directory, verify files exist with correct content, verify
   manifest was created with correct structure.

7. **Re-run unchanged**: Execute once, then re-run with same inputs. Verify diff
   shows all files as Unchanged. No files are rewritten.

8. **Re-run with change**: Execute once, change a variable value, re-compile plan.
   Verify diff shows affected files as Modified.

9. **Dry-run**: Execute with dry-run flag. Verify no files are written. Verify
   plan text output lists all operations.

10. **Force mode**: Execute once, manually modify a generated file (in-memory),
    re-run with `--force`. Verify the file is overwritten and manifest updated.

### End-to-End (Manual)

After all code is written and tests pass:

```bash
cd /tmp && mkdir test-project && cd test-project
cabal run seihou -- run haskell-base --var project.name=my-app --dry-run
# Expected: prints plan listing all files that would be generated

cabal run seihou -- run haskell-base --var project.name=my-app
# Expected: generates files, creates .seihou/manifest.json

cabal run seihou -- status
# Expected: lists applied modules, tracked files, variables

cabal run seihou -- run haskell-base --var project.name=my-app
# Expected: shows all files as Unchanged, no writes
```


## Idempotence and Recovery

- **Manifest writes are atomic**: Write to `.seihou/manifest.json.tmp`, then rename
  to `.seihou/manifest.json`. If the process is killed during write, the old manifest
  is still intact.
- **All milestones are safe to re-run**: Each milestone adds new modules without
  modifying the behavior of existing ones (except the `Manifest` stub replacement
  in M1, which is a one-time change).
- **If a milestone fails mid-way**: The previously passing tests still pass. Fix the
  issue and continue.
- **`nix fmt` is idempotent**: Running it multiple times produces the same output.
- **Reverting M1's type change**: If the `Manifest` type change causes unexpected
  breakage, the old stub can be restored. But since it is only used in `ManifestStore`
  (which has no interpreter yet), the blast radius is minimal.


## Interfaces and Dependencies

### New Package Dependencies (seihou-core)

| Package | Version | Purpose |
|---|---|---|
| `aeson` | `>=2.1 && <3` | JSON serialization for manifest |
| `cryptohash-sha256` | `>=0.11 && <1` | SHA256 content hashing |
| `bytestring` | `>=0.11 && <1` | Binary data for hashing |
| `base16-bytestring` | `>=1.0 && <2` | Hex encoding of SHA256 digests |
| `time` | `>=1.12 && <2` | `UTCTime` for manifest timestamps |

Note: `time` is a boot library (ships with GHC), so it adds no real dependency weight.

### New Package Dependencies (seihou-cli)

| Package | Version | Purpose |
|---|---|---|
| `effectful-core` | `>=2.4 && <3` | Effect dispatch in CLI handlers |
| `containers` | `>=0.6 && <1` | `Map` for variable overrides |
| `directory` | `>=1.3 && <2` | Filesystem operations in handlers |
| `filepath` | `>=1.4 && <2` | Path manipulation |

### New Modules and Their Signatures

**`seihou-core/src/Seihou/Manifest/Types.hs`**

```haskell
module Seihou.Manifest.Types
  ( emptyManifest,
    currentManifestVersion,
    manifestToJSON,
    manifestFromJSON,
  ) where

emptyManifest :: UTCTime -> Manifest
currentManifestVersion :: Int   -- Always 1 for now
manifestToJSON :: Manifest -> ByteString
manifestFromJSON :: ByteString -> Either String Manifest
```

**`seihou-core/src/Seihou/Manifest/Hash.hs`**

```haskell
module Seihou.Manifest.Hash
  ( hashContent,
  ) where

hashContent :: Text -> SHA256   -- SHA256 hex digest of UTF-8 encoded text
```

**`seihou-core/src/Seihou/Effect/FilesystemInterp.hs`**

```haskell
module Seihou.Effect.FilesystemInterp
  ( runFilesystem,
  ) where

runFilesystem :: (IOE :> es) => Eff (Filesystem : es) a -> Eff es a
```

**`seihou-core/src/Seihou/Effect/FilesystemPure.hs`**

```haskell
module Seihou.Effect.FilesystemPure
  ( runFilesystemPure,
    PureFS,
    emptyFS,
  ) where

type PureFS = Map FilePath Text   -- Virtual filesystem

runFilesystemPure :: PureFS -> Eff (Filesystem : es) a -> Eff es (a, PureFS)
emptyFS :: PureFS
```

**`seihou-core/src/Seihou/Effect/ManifestStoreInterp.hs`**

```haskell
module Seihou.Effect.ManifestStoreInterp
  ( runManifestStore,
  ) where

runManifestStore
  :: (Filesystem :> es)
  => FilePath                    -- Path to .seihou/manifest.json
  -> Eff (ManifestStore : es) a
  -> Eff es a
```

**`seihou-core/src/Seihou/Effect/ManifestStorePure.hs`**

```haskell
module Seihou.Effect.ManifestStorePure
  ( runManifestStorePure,
  ) where

runManifestStorePure
  :: Maybe Manifest              -- Initial manifest (or Nothing)
  -> Eff (ManifestStore : es) a
  -> Eff es (a, Maybe Manifest)
```

**`seihou-core/src/Seihou/Engine/Execute.hs`**

```haskell
module Seihou.Engine.Execute
  ( executePlan,
    dryRunPlan,
  ) where

executePlan
  :: (Filesystem :> es, Logger :> es)
  => FilePath                    -- Target directory (project root)
  -> [Operation]                 -- Operations from plan compiler
  -> ModuleName                  -- Module provenance
  -> Eff es (Map FilePath FileRecord)

dryRunPlan :: [Operation] -> Text
```

**`seihou-core/src/Seihou/Engine/Diff.hs`**

```haskell
module Seihou.Engine.Diff
  ( computeDiff,
  ) where

computeDiff
  :: (Filesystem :> es)
  => Manifest                    -- Previous state (or emptyManifest for first run)
  -> [(FilePath, Text)]          -- Planned file outputs
  -> Eff es DiffResult
```

**`seihou-cli/src/Seihou/CLI/Run.hs`**

```haskell
module Seihou.CLI.Run
  ( handleRun,
  ) where

handleRun :: RunOpts -> IO ()
```

**`seihou-cli/src/Seihou/CLI/Status.hs`**

```haskell
module Seihou.CLI.Status
  ( handleStatus,
  ) where

handleStatus :: IO ()
```

### Type Changes in `seihou-core/src/Seihou/Core/Types.hs`

The `Manifest` stub is replaced with:

```haskell
data Manifest = Manifest
  { manifestVersion :: Int
  , manifestGenAt :: UTCTime
  , manifestModules :: [AppliedModule]
  , manifestVars :: Map VarName Text
  , manifestFiles :: Map FilePath FileRecord
  }

data AppliedModule = AppliedModule
  { appliedName :: ModuleName
  , appliedSource :: FilePath
  , appliedAt :: UTCTime
  }

data FileRecord = FileRecord
  { fileHash :: SHA256
  , fileModule :: ModuleName
  , fileStrategy :: Strategy
  , fileGeneratedAt :: UTCTime
  }

newtype SHA256 = SHA256 { unSHA256 :: Text }

data DiffResult = DiffResult
  { diffNew :: [PlannedFile]
  , diffModified :: [ModifiedFile]
  , diffUnchanged :: [FilePath]
  , diffConflict :: [ConflictFile]
  , diffOrphaned :: [OrphanedFile]
  }

data PlannedFile = PlannedFile
  { plannedPath :: FilePath
  , plannedModule :: ModuleName
  , plannedContent :: Text
  }

data ModifiedFile = ModifiedFile
  { modifiedPath :: FilePath
  , modifiedModule :: ModuleName
  , modifiedOldHash :: SHA256
  , modifiedNewContent :: Text
  }

data ConflictFile = ConflictFile
  { conflictPath :: FilePath
  , conflictModule :: ModuleName
  , conflictManifest :: SHA256
  , conflictDisk :: SHA256
  , conflictPlan :: Text
  }

data OrphanedFile = OrphanedFile
  { orphanedPath :: FilePath
  , orphanedModule :: ModuleName
  }

data ConflictResolution
  = AcceptNew
  | KeepCurrent
  | Skip
  | Abort
```

Note: The design doc uses `ByteString` for content fields in diff types, but we use
`Text` since all our content is text. This avoids unnecessary encoding/decoding.
