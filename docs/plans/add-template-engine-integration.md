# Integrate Template Engine with Execution Pipeline and Add Structured Strategy

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

The template engine (placeholder substitution in `Seihou.Engine.Template`) works correctly in isolation, and the plan compilation layer dispatches to Copy, Template, and DhallText strategies. However, two integration gaps exist between these layers and the execution/manifest pipeline:

First, the `Operation` type does not carry strategy metadata. When the execution layer writes a file to disk, it records a `FileRecord` in the manifest but hardcodes `fileStrategy = Template` for every `WriteFileOp` — even files produced by Copy or DhallText. This means the manifest cannot accurately track which strategy generated each file, breaking audit trails and future smart regeneration.

Second, the Structured strategy (Dhall record evaluated to JSON or YAML) is declared in the type system but returns an error at compile time: `"Structured strategy not yet implemented"`. This is the last of the four generation strategies from the design specification.

After this work:

1. The `WriteFileOp` operation carries the `Strategy` that produced it. The execution layer records the correct strategy in the manifest's `FileRecord` for every file — Copy files say `Copy`, Template files say `Template`, DhallText files say `DhallText`, and Structured files say `Structured`.

2. The Structured strategy is fully implemented. A module step with `strategy = "structured"` and a `.gen` source file is evaluated through placeholder substitution, then Dhall evaluation, then serialized to JSON or YAML based on the destination file extension. For example, a step with source `package.json.gen` and destination `package.json` produces valid JSON.

3. Comprehensive tests verify that strategy metadata flows correctly through the pipeline from plan compilation to manifest storage, and that the Structured strategy produces correct JSON and YAML output.

The user can verify this by running `cabal test seihou-core-test` and seeing all tests pass, including new tests that assert strategy values in FileRecords and test Structured generation with fixture modules.


## Progress

- [x] **M1-1**: Add `opStrategy :: Strategy` field to `WriteFileOp` in `Types.hs` (2026-03-02)
- [x] **M1-2**: Update `compileCopyStep` in `Plan.hs` to pass `Copy` strategy (2026-03-02)
- [x] **M1-3**: Update `compileTemplateStep` in `Plan.hs` to pass `Template` strategy (2026-03-02)
- [x] **M1-4**: Update `compileDhallTextStep` in `Plan.hs` to pass `DhallText` strategy (2026-03-02)
- [x] **M1-5**: Update `executeOp` in `Execute.hs` to use `opStrategy` from operation (2026-03-02)
- [x] **M1-6**: Update all test files that construct `WriteFileOp` to include strategy field (2026-03-02)
- [x] **M1-7**: Update `dryRunPlan`, `mergeOperations`, `destOfOp`, `Diff.hs planToFileMap`, and all other code matching on `WriteFileOp` (2026-03-02)
- [x] **M1-8**: Build and run tests — all 312 pass (2026-03-02)
- [x] **M2-1**: `dhall-json` incompatible with GHC 9.12.2 (bytestring <0.12 constraint); wrote fallback `Seihou.Engine.DhallJSON` module instead (2026-03-02)
- [x] **M2-2**: Add `yaml`, `aeson-pretty` dependencies to `seihou-core.cabal` (2026-03-02)
- [x] **M2-3**: Implement `compileStructuredStep` in `Plan.hs` with `evaluateDhallExpr` and `serializeByExtension` helpers (2026-03-02)
- [x] **M2-4**: Implement output format detection: `.json` → pretty JSON, `.yaml`/`.yml` → YAML, other → error (2026-03-02)
- [x] **M2-5**: Create test fixture `structured-basic/` with `data.json.gen` and `config.yaml.gen` (2026-03-02)
- [x] **M2-6**: Add 4 unit tests: JSON output, YAML output, unconvertible Dhall error, unsupported format error (2026-03-02)
- [x] **M2-7**: Build and run tests — all 316 pass (2026-03-02)
- [x] **M3-1**: Add test in `ExecuteSpec.hs` verifying `fileStrategy = Template` for template-generated files (2026-03-02)
- [x] **M3-2**: Add test in `ExecuteSpec.hs` verifying `fileStrategy = Copy` for copy-generated files (2026-03-02)
- [x] **M3-3**: Add test in `ExecuteSpec.hs` verifying `fileStrategy = DhallText` for DhallText-generated files (2026-03-02)
- [x] **M3-3b**: Add test in `ExecuteSpec.hs` verifying `fileStrategy = Structured` for structured-generated files (2026-03-02)
- [x] **M3-4**: Add integration test in `ExecutionSpec.hs` verifying strategy tracking through full haskell-base pipeline (README→Template, Lib.hs→Template, LICENSE→Copy, cabal→Template, cabal.project→DhallText) (2026-03-02)
- [x] **M3-5**: Run full suite (321 tests pass), `nix fmt` clean (2026-03-02)


## Surprises & Discoveries

- `Diff.hs` also had a `WriteFileOp` pattern match in `planToFileMap` that was not listed in the original plan. The compiler caught it immediately since Haskell's exhaustiveness checking flags incomplete pattern matches after adding a field. This validates the plan's Idempotence section claim that "the compiler will flag every location."
- `dhall-json` 1.7.x has a hard constraint `bytestring <0.12`, which conflicts with GHC 9.12.2's bundled `bytestring 0.12.2`. Implemented the fallback path: a custom `Seihou.Engine.DhallJSON` module (~45 lines) that converts Dhall `Expr` to aeson `Value` by pattern matching on constructors.
- A Dhall `Natural` (e.g., `42`) is a valid JSON value, so the "non-record error" test needed a truly unconvertible expression (a lambda) rather than a simple numeric literal.


## Decision Log

- Decision: Add `opStrategy` field to `WriteFileOp` rather than creating separate operation constructors per strategy.
  Rationale: Adding a field is minimally invasive. The alternative — separate constructors like `TemplateWriteOp`, `DhallTextWriteOp`, `StructuredWriteOp` — would require extensive pattern-match updates throughout composition, execution, diff, and CLI code for no functional benefit. A single `WriteFileOp` with a strategy tag is simpler and aligns with how `CopyFileOp` already carries implicit strategy semantics (though CopyFileOp is currently unused by plan compilation — all copies go through `WriteFileOp` after reading the content).
  Date: 2026-03-02

- Decision: Use `dhall-json` and `yaml` libraries for the Structured strategy rather than writing a custom Dhall-to-JSON converter.
  Rationale: `dhall-json` provides `Dhall.JSON.dhallToJSON` which handles the full Dhall expression type system correctly, including records, lists, optionals, and unions. Writing a custom converter would be error-prone and incomplete. The `yaml` library (via `Data.Yaml`) provides YAML serialization from aeson `Value`. Both are well-maintained and compatible with the existing `dhall` and `aeson` dependency versions. If GHC 9.12.2 compatibility is an issue, this will be discovered in Milestone 2 and an alternative (manual conversion) can be considered.
  Date: 2026-03-02

- Decision: Keep `CopyFileOp` in the `Operation` type even though plan compilation currently does not produce it (all copy steps read the file and produce `WriteFileOp`).
  Rationale: The constructor exists for a reason (lazy copy without reading into memory). Removing it is out of scope and could break future optimizations. Plan compilation might use it later.
  Date: 2026-03-02

- Decision: Implement custom `Seihou.Engine.DhallJSON` module instead of using `dhall-json` library.
  Rationale: `dhall-json` 1.7.x has `bytestring <0.12` constraint, incompatible with GHC 9.12.2's bundled `bytestring 0.12.2`. The custom module is ~45 lines, handles all Dhall value constructors needed for Structured output (records, text, numbers, bools, lists, optionals), and avoids a dependency incompatibility.
  Date: 2026-03-02

- Decision: The Structured strategy accepts any Dhall value (not just records) for JSON/YAML serialization.
  Rationale: A Natural, Bool, or List is valid JSON/YAML. Restricting to records-only would add unnecessary complexity with no user benefit. The error case is truly unconvertible expressions like lambdas or type-level terms.
  Date: 2026-03-02


## Outcomes & Retrospective

All three milestones completed. The implementation achieves the purpose stated in the plan:

1. **Strategy propagation (M1)**: `WriteFileOp` now carries `opStrategy :: Strategy`. The execution layer reads it instead of hardcoding `Template`. The manifest accurately records which strategy generated each file. 14 source and test files updated; the Haskell compiler caught every pattern-match site including one (`Diff.hs`) not listed in the original plan.

2. **Structured strategy (M2)**: Fully implemented. A module step with `strategy = "structured"` evaluates a Dhall source file (after placeholder substitution) and serializes the result to JSON or YAML based on the destination file extension. The `dhall-json` library was incompatible with GHC 9.12.2, so a custom `Seihou.Engine.DhallJSON` module was written as a fallback — this is simpler and avoids the dependency issue.

3. **Strategy-tracking tests (M3)**: 5 new tests verify that `fileStrategy` in `FileRecord` matches the actual strategy used, both in unit tests (all 4 strategies) and in integration (haskell-base fixture pipeline).

Final test count: 321 (up from 312). All pass. `nix fmt` clean.

New files: `seihou-core/src/Seihou/Engine/DhallJSON.hs`, `seihou-core/test/fixtures/structured-basic/`.
New dependencies: `aeson-pretty`, `yaml`.

Gap: No fixture-based integration test for Structured strategy through the full load→resolve→compile pipeline (only unit tests via `withFixture`). This could be added in a future plan if needed.


## Context and Orientation

This section describes the current state of the codebase relevant to this plan. Key terms are defined inline.

### Repository layout (relevant files only)

    seihou/
      seihou-core/
        seihou-core.cabal                   -- Library package; lists dependencies and modules
        src/Seihou/
          Core/Types.hs                     -- All domain types including Operation, Strategy, FileRecord
          Engine/Template.hs                -- Placeholder engine: renderTemplate, renderDestPath
          Engine/Plan.hs                    -- Plan compilation: dispatches steps to strategies
          Engine/Execute.hs                 -- Plan execution: writes files, records FileRecords
          Engine/Diff.hs                    -- Three-state diff (manifest vs plan vs disk)
          Composition/Plan.hs              -- Multi-module plan merging
        test/
          Seihou/Engine/TemplateSpec.hs     -- Template engine unit tests
          Seihou/Engine/PlanSpec.hs         -- Plan compilation tests
          Seihou/Engine/ExecuteSpec.hs      -- Execution tests
          Seihou/Engine/DiffSpec.hs         -- Diff engine tests
          Seihou/Integration/GenerationSpec.hs  -- Load→resolve→compile integration tests
          Seihou/Integration/ExecutionSpec.hs   -- Full pipeline integration tests
          Seihou/Integration/CompositionSpec.hs -- Multi-module composition tests
          fixtures/haskell-base/            -- Reference fixture with all 3 strategies
      seihou-cli/
        src/Seihou/CLI/Run.hs              -- `seihou run` command handler

### Key types

**Operation** (defined in `seihou-core/src/Seihou/Core/Types.hs`): Represents a filesystem operation produced by the plan compiler. The key constructors are:

    data Operation
      = WriteFileOp { opDest :: FilePath, opContent :: Text }  -- missing strategy!
      | CreateDirOp { opPath :: FilePath }
      | CopyFileOp  { opSrc :: FilePath, opDest :: FilePath }
      | RunCommandOp { opCommand :: Text, opWorkDir :: Maybe FilePath }

**Strategy** (same file): One of `Copy`, `Template`, `DhallText`, or `Structured`. Declared in module step definitions and recorded in the manifest's `FileRecord`.

**FileRecord** (same file): Stored in the manifest per generated file. Contains `fileHash`, `fileModule`, `fileStrategy`, and `fileGeneratedAt`. Currently, `executeOp` in `Execute.hs` hardcodes `fileStrategy = Template` for `WriteFileOp`, which is incorrect for Copy and DhallText steps.

**The bug**: In `seihou-core/src/Seihou/Engine/Execute.hs` at the `WriteFileOp` handler (around line 40), the code creates a `FileRecord` with `fileStrategy = Template` regardless of which strategy actually produced the operation. This happens because `WriteFileOp` does not carry a `Strategy` field, so the execution layer has no way to know the true strategy.

### How strategies flow through the pipeline

    Module step (has `stepStrategy :: Strategy`)
           │
           ▼ [compilePlan in Plan.hs]
    Operation (currently loses strategy info for WriteFileOp)
           │
           ▼ [executePlan in Execute.hs]
    FileRecord (needs correct `fileStrategy`)
           │
           ▼ [written to .seihou/manifest.json]
    Manifest

### Structured strategy (not yet implemented)

The Structured strategy converts a Dhall source file (with `.gen` extension) into JSON or YAML output:

1. Read the `.gen` source file from the module's `files/` directory
2. Substitute `{{placeholder}}` patterns with resolved variable values (same as Template and DhallText)
3. Evaluate the resulting text as a Dhall expression — it must produce a Dhall record
4. Serialize the record to JSON or YAML depending on the destination file extension (`.json` → JSON, `.yaml` or `.yml` → YAML)
5. Write the serialized text to the destination

The output format is determined by the destination file extension. For example, a step with `dest = "package.json"` produces JSON; a step with `dest = "config.yaml"` produces YAML.

### Current test count

The test suite currently has 312 tests, all passing.


## Plan of Work

### Milestone 1: Propagate strategy through the Operation type

This milestone fixes the architectural gap where strategy information is lost between plan compilation and execution. At the end, `WriteFileOp` carries an `opStrategy` field, plan compilation populates it correctly, and the execution layer uses it to record accurate `FileRecord` entries in the manifest.

The change touches `Types.hs` (add field), `Plan.hs` (pass strategy when constructing WriteFileOp), `Execute.hs` (read strategy from operation), and every test file and module that constructs or pattern-matches on `WriteFileOp`.

Acceptance: `cabal build all && cabal test seihou-core-test` passes. Inspection of `Execute.hs` confirms it reads `opStrategy` from the operation rather than using a hardcoded value.

#### Edits

In `seihou-core/src/Seihou/Core/Types.hs`, add the `opStrategy` field to `WriteFileOp`:

    -- Before:
    WriteFileOp { opDest :: FilePath, opContent :: Text }

    -- After:
    WriteFileOp { opDest :: FilePath, opContent :: Text, opStrategy :: Strategy }

In `seihou-core/src/Seihou/Engine/Plan.hs`, update each step compiler to pass the correct strategy:

- `compileCopyStep`: change `WriteFileOp destStr content` to `WriteFileOp destStr content Copy`
- `compileTemplateStep`: change `WriteFileOp destStr rendered` to `WriteFileOp destStr rendered Template`
- `compileDhallTextStep`: change `WriteFileOp destStr evaluated` to `WriteFileOp destStr evaluated DhallText`

In `seihou-core/src/Seihou/Engine/Execute.hs`, update `executeOp` for the `WriteFileOp` case to use the strategy from the operation:

    -- Before:
    fileStrategy = Template,

    -- After:
    fileStrategy = opStrategy op,

where `op` is the matched `WriteFileOp`.

In `seihou-core/src/Seihou/Engine/Execute.hs`, update `dryRunPlan`'s `formatOp` for `WriteFileOp` — the pattern match now has three fields.

In `seihou-core/src/Seihou/Composition/Plan.hs`, update `destOfOp` — the pattern match for `WriteFileOp` now has three fields.

In `seihou-cli/src/Seihou/CLI/Run.hs`, update the list comprehension that extracts planned files: `[... | WriteFileOp dest content <- ops]` becomes `[... | WriteFileOp dest content _ <- ops]` (wildcard the strategy field).

Update all test files that construct `WriteFileOp` values:
- `seihou-core/test/Seihou/Engine/PlanSpec.hs`: Every `shouldBe [WriteFileOp ...]` assertion needs the strategy field. Copy steps get `Copy`, Template steps get `Template`, DhallText steps get `DhallText`.
- `seihou-core/test/Seihou/Engine/ExecuteSpec.hs`: Every `WriteFileOp` construction needs a strategy. Use `Template` for the existing tests (they're testing execution mechanics, not strategy dispatch).
- `seihou-core/test/Seihou/Engine/DiffSpec.hs`: If any WriteFileOp is constructed here, add the field.
- `seihou-core/test/Seihou/Integration/ExecutionSpec.hs`: Pattern matches on `WriteFileOp` in extractPlanned need the wildcard.
- `seihou-core/test/Seihou/Integration/GenerationSpec.hs`: Pattern matches need the wildcard.
- `seihou-core/test/Seihou/Integration/CompositionSpec.hs`: Same update.


### Milestone 2: Implement the Structured strategy

This milestone adds the last generation strategy. At the end, a module step with `strategy = "structured"` and a Dhall `.gen` source file is evaluated to a JSON or YAML output file. A test fixture and unit tests verify the behavior.

This requires two new library dependencies: `dhall-json` (converts Dhall expressions to aeson Values) and `yaml` (serializes aeson Values to YAML). Both are available on Hackage. If `dhall-json` does not build with GHC 9.12.2, a fallback plan is described in Idempotence and Recovery.

Acceptance: A test with a `.gen` fixture that produces JSON passes. A test with a `.gen` fixture that produces YAML passes. An error test for a non-record Dhall expression passes. `cabal build all && cabal test seihou-core-test` succeeds.

#### Edits

In `seihou-core/seihou-core.cabal`, add dependencies to the `library` section:

    dhall-json >=1.7 && <2,
    yaml >=0.11 && <1,

Also add `yaml` to the `test-suite` build-depends (needed for test assertions).

In `seihou-core/src/Seihou/Engine/Plan.hs`:

Add a new function `compileStructuredStep` that follows the same pattern as `compileDhallTextStep` but with an additional serialization phase. The implementation:

1. Read the source file with `tryReadFile`.
2. Substitute placeholders with `renderTemplate`.
3. Evaluate the substituted text as a Dhall expression using `Dhall.inputExpr` from the `dhall` library. This returns a `Dhall.Expr Src Void`.
4. Convert the Dhall expression to an aeson `Value` using `Dhall.JSON.dhallToJSON` from the `dhall-json` library. If the conversion fails, return an error.
5. Determine the output format from the destination file extension. If the extension is `.json`, serialize with `Data.Aeson.encode`. If `.yaml` or `.yml`, serialize with `Data.Yaml.encode`. If neither, return an error.
6. Render the destination path with `renderDestPath`.
7. Return `WriteFileOp` with `Structured` strategy, directory operations, and the serialized content.

Replace the `Structured -> pure (Left ...)` line in `compileStep` with `Structured -> compileStructuredStep baseDir vars step`.

Add necessary imports: `Dhall.JSON` (from dhall-json), `Data.Yaml` (from yaml), `Data.Aeson` (already available via aeson), `Data.Aeson.Encode.Pretty` or `Data.Aeson.encode`, `Dhall.Core` (for `inputExpr`), plus `Data.Text.Lazy` and `Data.Text.Lazy.Encoding` for ByteString-to-Text conversion.

Create a test fixture directory `seihou-core/test/fixtures/structured-basic/` with:

- `module.dhall`: A minimal module definition declaring one step with `strategy = "structured"`, src `"data.json.gen"`, dest `"data.json"`, and one variable `project.name`.
- `files/data.json.gen`: A Dhall expression that evaluates to a record: `{ name = "{{project.name}}", version = "1.0.0" }`.

Create a second fixture file for YAML testing: either a second step in the same module or a separate fixture. A second step in the same module with src `"config.yaml.gen"` and dest `"config.yaml"` is simplest.

In `seihou-core/test/Seihou/Engine/PlanSpec.hs`, add tests:

- "compiles a Structured step to JSON": Create a temp fixture with a `.gen` file containing a Dhall record, compile with Structured strategy and destination `output.json`, assert the result is valid JSON containing the expected keys and values.
- "compiles a Structured step to YAML": Same but with destination `output.yaml`, assert the result is valid YAML.
- "reports error for Structured step with non-record Dhall": A `.gen` file containing `42` (a Natural, not a record) should return `Left` with an error message.
- "reports error for unknown output format in Structured step": Destination `output.txt` (not `.json` or `.yaml`) should return `Left`.


### Milestone 3: Strategy-tracking integration tests

This milestone adds tests that verify strategy information flows correctly from plan compilation through execution to manifest FileRecords. These tests catch regressions like the original hardcoded-strategy bug.

Acceptance: New tests in `ExecuteSpec.hs` assert `fileStrategy` values on FileRecords produced by execution. `nix fmt` produces no changes. Full suite passes.

#### Edits

In `seihou-core/test/Seihou/Engine/ExecuteSpec.hs`, add three tests:

- "records Template strategy in FileRecord for WriteFileOp with Template": Construct a `WriteFileOp "test.txt" "content" Template`, execute it, assert `fileStrategy record == Template`.
- "records Copy strategy in FileRecord for WriteFileOp with Copy": Same pattern but with `Copy` strategy.
- "records DhallText strategy in FileRecord for WriteFileOp with DhallText": Same pattern but with `DhallText`.

In `seihou-core/test/Seihou/Integration/GenerationSpec.hs` or `ExecutionSpec.hs`, add a test that compiles the `haskell-base` fixture, executes the plan, and verifies that the resulting FileRecords have the correct strategy for each file:

- `README.md` → `Template`
- `src/Lib.hs` → `Template`
- `LICENSE` → `Copy`
- `my-app.cabal` → `Template`
- `cabal.project` → `DhallText`

Run `nix fmt` and verify no changes.


## Concrete Steps

All commands run from the repository root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

### Build after each milestone

    cabal build all

Expected: `Build completed successfully.`

### Test after each milestone

    cabal test seihou-core-test

Expected: All tests pass. Count will grow from 312 as new tests are added.

### Check dependency resolution for Milestone 2

Before implementing Milestone 2, verify that `dhall-json` and `yaml` resolve:

    cabal build all --dry-run

Expected: The solver should find compatible versions of `dhall-json` and `yaml` for GHC 9.12.2. If it cannot, the plan must be revised to use a manual Dhall-to-JSON converter (see Idempotence and Recovery).

### Format check at the end

    nix fmt

Expected: No files changed.

### Verify strategy tracking correctness

After Milestone 1, inspect the Execute.hs diff to confirm the hardcoded `Template` is replaced:

    grep -n 'fileStrategy' seihou-core/src/Seihou/Engine/Execute.hs

Expected: `fileStrategy = opStrategy op` (or equivalent), not `fileStrategy = Template`.


## Validation and Acceptance

1. **Build**: `cabal build all` succeeds.

2. **Tests**: `cabal test seihou-core-test` passes all tests (312 original + new tests).

3. **Strategy tracking**: After Milestone 1, the ExecuteSpec tests verify that `fileStrategy` in FileRecords matches the actual strategy used:
   - `WriteFileOp "x" "y" Template` produces `fileStrategy = Template`
   - `WriteFileOp "x" "y" Copy` produces `fileStrategy = Copy`
   - `WriteFileOp "x" "y" DhallText` produces `fileStrategy = DhallText`

4. **Structured strategy**: After Milestone 2, a fixture module with a `.gen` source file produces valid JSON output when the destination ends in `.json` and valid YAML when it ends in `.yaml`.

5. **Integration**: After Milestone 3, the `haskell-base` fixture's execution produces FileRecords with the correct strategy for each of its five generated files.

6. **Formatting**: `nix fmt` produces no changes.


## Idempotence and Recovery

Each milestone is independently verifiable via `cabal build all && cabal test seihou-core-test`. If a milestone is partially applied and the build breaks, the fix is to complete the remaining edits in that milestone.

Milestone 1 is a type change. The Haskell compiler will flag every location where `WriteFileOp` is constructed or pattern-matched with the wrong number of fields, making it impossible to forget a call site.

Milestone 2 depends on `dhall-json` and `yaml` building with GHC 9.12.2. If the cabal solver cannot find compatible versions:

- **Fallback for `dhall-json`**: Write a minimal `dhallExprToJSON :: Expr Src Void -> Either Text Value` function (approximately 40 lines) that handles records, text, naturals, integers, bools, lists, and optionals. This covers the use cases needed for Structured generation. Place it in a new module `Seihou.Engine.DhallJSON`.
- **Fallback for `yaml`**: Use `HsYAML` or `HsYAML-aeson` (both pure Haskell, no C dependency). Alternatively, support only JSON output in v1 and defer YAML to a later plan.

Git commits should be made after each milestone passes tests.


## Interfaces and Dependencies

### Changed types

In `seihou-core/src/Seihou/Core/Types.hs`:

    data Operation
      = WriteFileOp
          { opDest :: FilePath,
            opContent :: Text,
            opStrategy :: Strategy     -- NEW: which strategy produced this
          }
      | CreateDirOp { opPath :: FilePath }
      | CopyFileOp { opSrc :: FilePath, opDest :: FilePath }
      | RunCommandOp { opCommand :: Text, opWorkDir :: Maybe FilePath }

### New function

In `seihou-core/src/Seihou/Engine/Plan.hs`:

    compileStructuredStep
      :: FilePath                       -- Module base directory
      -> Map VarName VarValue           -- Resolved variables
      -> Step                           -- The step to compile
      -> IO (Either [Text] [Operation])

### New dependencies (Milestone 2)

- `dhall-json >=1.7 && <2`: Provides `Dhall.JSON.dhallToJSON` for converting Dhall expressions to aeson Values.
- `yaml >=0.11 && <1`: Provides `Data.Yaml.encode` for serializing aeson Values to YAML.

### Existing dependencies used

- `dhall >=1.42 && <2`: Already a dependency. Provides `Dhall.inputExpr` for evaluating Dhall text to an expression.
- `aeson >=2.1 && <3`: Already a dependency. Provides `Data.Aeson.encode` for JSON serialization.
- `text >=2.0 && <3`: Already a dependency.
- `containers >=0.6 && <1`: Already a dependency.
