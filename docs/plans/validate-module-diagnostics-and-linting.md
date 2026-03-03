# Enhance validate-module with Rich Diagnostics and Lint Checks

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

Running `seihou validate-module` today reports a flat list of error messages with no context,
no per-check pass/fail indicators, and no advisory warnings for common authoring mistakes. A
module author looking at the output cannot tell which checks passed, gets no structured
guidance on how to fix failures, and receives no hints about best-practice issues that are not
strictly errors but often lead to user confusion later.

After this change, `seihou validate-module` produces a structured diagnostic report that walks
through each validation check with a pass/fail indicator (check mark or cross), displays a
summary of the module's structure (name, variables, steps, dependencies), and includes advisory
lint warnings for common pitfalls like unused variables, required variables without prompts,
duplicate step destinations, and empty choice lists. A new `--lint` flag enables the advisory
warnings (off by default so the basic command remains fast and focused). Color output is used
on terminals and automatically suppressed when piped.

The user can verify the change by running:

    cd seihou
    cabal run seihou -- validate-module seihou-core/test/fixtures/haskell-base

and observing a colored, check-by-check report on a terminal.


## Progress

- [x] M1-1: Export check functions from `Seihou.Core.Module`, define `DiagSeverity`, `DiagCheck`, `ValidateReport` in new `Seihou.Engine.Validate` (2026-03-02)
- [x] M1-2: Implement `buildReport :: Bool -> FilePath -> Module -> IO ValidateReport` with all 8 core checks (2026-03-02)
- [x] M1-3: Implement `renderReportPlain :: ValidateReport -> Text` with check-mark format (2026-03-02)
- [x] M1-4: Register `Seihou.Engine.Validate` in `seihou-core.cabal` exposed-modules (2026-03-02)
- [x] M1-5: Add 27 unit tests in `ValidateSpec.hs`, register in cabal and test Main.hs (2026-03-02)
- [x] M1-6: Build and run all tests — 404 pass (2026-03-02)
- [x] M2-1: Add 5 lint checks: unused variables, required without prompt, duplicate destinations, empty choice list, missing descriptions (2026-03-02)
- [x] M2-2: Add `--lint` flag to `ValidateOpts` in `Commands.hs` (2026-03-02)
- [x] M2-3: Add unit tests for each lint check — included in M1-5 (built alongside core checks) (2026-03-02)
- [x] M2-4: Build and run all tests — 404 pass (2026-03-02)
- [x] M3-1: Rewrite `handleValidateModule` to use `buildReport` + `renderReportColor` (2026-03-02)
- [x] M3-2: Add `renderReportColor :: Bool -> ValidateReport -> Text` to `Seihou.CLI.Style` (2026-03-02)
- [x] M3-3: Build and run all tests — 404 pass, `nix fmt` clean (2026-03-02)
- [x] M3-4: Manual verification — valid module shows all ✓, invalid shows 6 ✗ with details, `--lint` shows ⚠ warnings (2026-03-02)


## Surprises & Discoveries

- The lint checks and core validation were implemented together in M1 since `buildReport` already takes a `Bool` lint flag. The test suite covers both core checks and lint checks in a single spec file. This was more efficient than splitting across milestones.
- The `Style.hs` import of `Seihou.Core.Types` needed to be expanded from `(ModuleName (..))` to `(Module (..), ModuleName (..))` to access record fields like `moduleName`, `moduleVars`, etc. in the color rendering function.
- The `haskell-base` fixture has two lint warnings: `project.version` and `license` are declared variables but never referenced in prompts, exports, or step destinations. This is by design (they are used via template placeholders `{{project.version}}` in template content, not step destinations). This is a known limitation of the unused variable lint — it only checks destination placeholders, not template body content.


## Decision Log

- Decision: Diagnostic types live in seihou-core as `Seihou.Engine.Validate`, not in seihou-cli.
  Rationale: The report-building logic is pure (aside from file existence checks via IO). Keeping it in seihou-core allows tests to assert on the structured report without depending on the CLI package. Only the color rendering lives in seihou-cli's `Style` module, following the same pattern used for `PreviewLine`/`renderPreviewColor`.
  Date: 2026-03-02

- Decision: Lint checks are gated behind a `--lint` flag rather than always running.
  Rationale: Lint warnings are advisory and can be noisy. Module authors validating a work-in-progress module should not be distracted by warnings about missing descriptions. The `--lint` flag makes them opt-in. The flag is passed through `ValidateOpts` and forwarded to `buildReport` which conditionally includes lint-level diagnostics.
  Date: 2026-03-02

- Decision: Use `DiagSeverity` (Error vs Warning) rather than separate error and warning lists.
  Rationale: A single `[DiagCheck]` list with a severity tag per check is simpler to render, filter, and test than maintaining parallel lists. The exit code is determined by whether any check has `Error` severity, regardless of warnings.
  Date: 2026-03-02

- Decision: Reuse the existing eight validation functions in `Seihou.Core.Module` rather than reimplementing them.
  Rationale: The check functions (`checkNameFormat`, `checkUniqueVars`, etc.) are well-tested and correct. The new `buildReport` calls each one individually and wraps the result in a `DiagCheck` with a descriptive label. This avoids duplication and ensures the validation logic stays in one place.
  Date: 2026-03-02


## Outcomes & Retrospective

All three milestones completed. The `seihou validate-module` command now produces structured, colored diagnostic output.

Key outcomes:
- `Seihou.Engine.Validate` (seihou-core): Pure diagnostic types (`DiagSeverity`, `DiagCheck`, `ValidateReport`), `buildReport` function calling all 8 existing check functions individually, 5 lint checks, `renderReportPlain` for plain text, `reportHasErrors` for exit code logic. 27 unit tests.
- `Seihou.Core.Module`: Exported 10 previously-internal functions for use by `buildReport`.
- `Seihou.CLI.Style`: Added `renderReportColor` with green ✓, red ✗, yellow ⚠, cyan module name, dim error details.
- `Seihou.CLI.Validate`: Rewritten from 59-line flat handler to structured report pipeline (37 lines for Dhall failure path + report path).
- `Seihou.CLI.Commands`: Added `validateLint :: Bool` field and `--lint` switch.
- All 404 tests pass. Exit codes preserved (0 = valid, 1 = invalid).

The unused-variables lint has a known limitation: it only checks step destination placeholders, not template file content. Variables used inside templates (like `{{project.version}}`) are not detected as "used" by this lint. This is acceptable because scanning template content would require reading and parsing all template files, which is a larger scope than this plan.


## Context and Orientation

### Repository Structure

The project is a Haskell workspace with two packages:

    seihou/
    ├── seihou-core/          # Pure library (types, engine, effects)
    │   ├── seihou-core.cabal
    │   └── src/Seihou/
    │       ├── Core/Types.hs        # All domain types (Module, Step, VarDecl, etc.)
    │       ├── Core/Module.hs       # validateModule, loadModule, 8 check functions
    │       └── Engine/Preview.hs    # Precedent: pure report type + plain renderer
    └── seihou-cli/           # CLI executable
        ├── seihou-cli.cabal
        └── src/Seihou/CLI/
            ├── Commands.hs          # ValidateOpts, commandParser
            ├── Validate.hs          # handleValidateModule (current: 59 lines)
            └── Style.hs             # Color helpers, renderPreviewColor

### Current validate-module Behavior

The `validate-module` subcommand is defined in `seihou-cli/src/Seihou/CLI/Commands.hs` (line 62) as:

    data ValidateOpts = ValidateOpts
      { validatePath :: Maybe FilePath
      }

The handler in `seihou-cli/src/Seihou/CLI/Validate.hs` does three things: (1) checks that `module.dhall` exists, (2) evaluates the Dhall file via `evalModuleFromFile`, and (3) calls `validateModule` from `Seihou.Core.Module`. On success it prints `"Module 'name' is valid."`. On failure it prints `"N error(s) found. Module is invalid."` followed by a flat bullet list of error strings.

There is no per-check pass/fail output, no color, no lint warnings, and no module summary.

### Core Validation Logic

The `validateModule` function in `seihou-core/src/Seihou/Core/Module.hs` (line 51) runs eight check functions, each returning `[Text]` (empty means pass). The checks are: `checkNameFormat`, `checkUniqueVars`, `checkPromptRefs`, `checkFileExistence`, `checkExportRefs`, `checkDependencyNames`, `checkSafeDestinations`, `checkDestVarRefs`. All error strings are concatenated and wrapped in `ValidationError ModuleName [Text]` if non-empty.

These check functions are not exported individually — they are internal to the `Module` module. The new `buildReport` function will either need them exported, or will call `validateModule` and then run its own parallel check logic. This plan chooses to export the check functions so `buildReport` can call each one separately and wrap the result.

### Design Doc Specification

The design doc at `docs/dev/design/proposed/cli-commands.md` (lines 403–428) specifies the desired output format:

    Validating module at ./haskell-base/...

      ✓ module.dhall evaluates successfully
      ✓ Module name: haskell-base
      ✓ 3 variables declared
      ✓ 1 prompt defined
      ✓ 4 steps defined
      ✓ All source files exist
      ✓ All exports reference declared variables

    Module is valid.

For invalid modules, failed checks show ✗ with the error detail. The exit code is 0 for valid, 1 for invalid.

### Color Infrastructure

The `Seihou.CLI.Style` module (created in the dry-run preview plan at `docs/plans/cli-dry-run-preview-with-color.md`) already provides `green`, `red`, `yellow`, `dim`, `bold`, `useColor`, and the pattern of a `render*Color :: Bool -> SomeType -> Text` function. The validate report will follow this exact pattern.

### Test Infrastructure

Tests use Tasty + Hspec. Each spec module exports `tests :: IO TestTree`. The test main at `seihou-core/test/Main.hs` imports each spec, runs it in `IO` to get a `TestTree`, and passes them all to `defaultMain`. Module validation tests in `seihou-core/test/Seihou/Core/ModuleSpec.hs` use `withSystemTempDirectory` to create temporary module directories with `files/` subdirectories for source file existence checks.


## Plan of Work

### Milestone 1: Structured Diagnostic Report

This milestone creates a pure `Seihou.Engine.Validate` module in seihou-core that builds a structured validation report from a module. The report contains one entry per check, each with a label, severity, and optional error details. A `renderReportPlain` function produces plain text output matching the design doc format.

The first step is to export the individual check functions from `Seihou.Core.Module`. Currently `checkNameFormat`, `checkUniqueVars`, `checkPromptRefs`, `checkFileExistence`, `checkExportRefs`, `checkDependencyNames`, `checkSafeDestinations`, and `checkDestVarRefs` are internal. Add them to the module's export list. Also export `isValidModuleName` which is used by `checkNameFormat` and will be useful for lint checks.

Then create `seihou-core/src/Seihou/Engine/Validate.hs` with these types:

    data DiagSeverity = DiagError | DiagWarning

    data DiagCheck = DiagCheck
      { diagLabel    :: Text        -- e.g. "Module name format"
      , diagSeverity :: DiagSeverity
      , diagDetails  :: [Text]      -- Empty means pass
      }

    data ValidateReport = ValidateReport
      { reportModule  :: Module
      , reportPath    :: FilePath
      , reportDhallOk :: Bool       -- Did Dhall evaluation succeed?
      , reportChecks  :: [DiagCheck]
      }

The `buildReport` function takes a `FilePath` (module directory) and a `Module` (already decoded from Dhall) and returns a `ValidateReport`. It calls each of the eight check functions individually, wrapping each result as a `DiagCheck` with severity `DiagError` and an appropriate label. The `reportDhallOk` field is always `True` when called from `buildReport` (Dhall errors are handled separately in the CLI before reaching this function).

The `renderReportPlain` function formats the report as:

    Validating module at <path>...

      ✓ module.dhall evaluates successfully
      ✓ Module name: <name>
      ✓ <N> variables declared
      ✓ <N> prompts defined
      ✓ <N> steps defined
      ✓ All source files exist
      ...

    Module is valid.

Each check line shows ✓ if `diagDetails` is empty, ✗ if not. Failed checks show each detail on an indented line below. The final line says "Module is valid." or "N error(s) found. Module is invalid."

Unit tests in `seihou-core/test/Seihou/Engine/ValidateSpec.hs` verify: a valid module produces all-pass checks, an invalid module produces specific failures, the plain renderer matches expected format, and the Dhall-error case renders correctly.

Acceptance: `cabal test all` passes with new tests.

### Milestone 2: Lint Checks

This milestone adds advisory lint checks to `buildReport`. Each lint check produces a `DiagCheck` with severity `DiagWarning`. Lint checks are only included when a `Bool` parameter (representing the `--lint` flag) is `True`.

The `buildReport` signature changes to:

    buildReport :: Bool -> FilePath -> Module -> IO ValidateReport

The `Bool` controls whether lint checks are appended after the core validation checks.

Five lint checks will be implemented:

1. **Unused variables**: A variable is declared in `moduleVars` but never referenced in any step destination placeholder (`{{var.name}}`), any export, or any prompt. This often indicates a leftover from a refactor.

2. **Required variable without prompt**: A variable has `varRequired = True` but no corresponding prompt in `modulePrompts`. This means the variable can only be supplied via `--var` or config files, which may surprise users running the module interactively.

3. **Duplicate step destinations**: Two or more steps write to the same destination path (after placeholder extraction). Unless one uses `stepPatch`, this means last-writer-wins within the same module, which is almost always unintentional.

4. **Empty choice list**: A variable has type `VTChoice []` (choice type with no options). This is a schema error that would cause the prompt to offer no selections.

5. **Missing variable descriptions**: A variable has `varDescription = Nothing`. Descriptions appear in `seihou vars` output and interactive prompts; omitting them makes the module harder to use.

The `--lint` flag is added to `ValidateOpts` in `Commands.hs`:

    data ValidateOpts = ValidateOpts
      { validatePath :: Maybe FilePath,
        validateLint :: Bool
      }

The flag is defined as `switch (long "lint" <> help "Include advisory lint warnings")`.

Unit tests cover each lint check: one test per lint rule verifying that it fires on a crafted module and does not fire on a clean module.

Acceptance: `cabal test all` passes with new tests.

### Milestone 3: Color Rendering and CLI Integration

This milestone rewrites `handleValidateModule` to use `buildReport` and adds color rendering. The flow becomes:

1. Check `module.dhall` exists (unchanged).
2. Evaluate Dhall. On failure, construct a `ValidateReport` with `reportDhallOk = False` and no checks, render it, and exit.
3. On success, call `buildReport (validateLint vopts) moduleDir modul` to get the full report.
4. Detect color support with `useColor`.
5. Render with `renderReportColor colorEnabled report` (or `renderReportPlain` when color is off).
6. Exit with code 0 if no errors, 1 if any errors.

A new `renderReportColor :: Bool -> ValidateReport -> Text` function is added to `Seihou.CLI.Style`. It follows the same pattern as `renderPreviewColor`: when the `Bool` is `False`, it delegates to `renderReportPlain`. When `True`, it colors ✓ in green, ✗ in red, warning labels in yellow, the module name in cyan, and error details in dim.

Acceptance: `cabal test all` passes. Manual verification with `haskell-base` (valid) and `invalid-module` (invalid) fixtures shows colored check-by-check output.


## Concrete Steps

All commands run from `seihou/` (the workspace root).

### Build command

    cabal build all 2>&1

Expected: no errors.

### Test command

    cabal test all 2>&1

Expected: `All N tests passed.`

### Format command

    nix fmt 2>&1

Expected: no output (already formatted).

### Manual verification (valid module)

    cabal run seihou -- validate-module seihou-core/test/fixtures/haskell-base

Expected output (with ANSI colors on a terminal):

    Validating module at seihou-core/test/fixtures/haskell-base...

      ✓ module.dhall evaluates successfully
      ✓ Module name: haskell-base
      ✓ 3 variables declared
      ✓ 1 prompt defined
      ✓ 5 steps defined
      ✓ All source files exist
      ✓ All exports reference declared variables
      ✓ All prompts reference declared variables
      ✓ All dependency names are well-formed
      ✓ All step destinations are safe
      ✓ All destination placeholders reference declared variables

    Module 'haskell-base' is valid.

### Manual verification (invalid module)

    cabal run seihou -- validate-module seihou-core/test/fixtures/invalid-module

Expected output:

    Validating module at seihou-core/test/fixtures/invalid-module...

      ✓ module.dhall evaluates successfully
      ✗ Module name format
          module name must match [a-z][a-z0-9-]*, got: Invalid_Module
      ✗ Unique variable names
          duplicate variable name: x
      ✗ Export references
          export references undeclared variable: nonexistent
      ✗ Prompt references
          prompt references undeclared variable: undeclared
      ✗ Source file existence
          step source file not found: missing.tpl
      ✗ Safe step destinations
          step destination must be relative: /absolute/path

    6 error(s) found. Module is invalid.

### Manual verification (lint warnings)

    cabal run seihou -- validate-module --lint seihou-core/test/fixtures/haskell-base

Expected: same as valid output above, plus any applicable warnings (e.g., variables without descriptions would show as yellow ⚠ lines after the check marks).


## Validation and Acceptance

### Unit Tests

New tests in `seihou-core/test/Seihou/Engine/ValidateSpec.hs` verify:

1. `buildReport` with a valid module produces all-pass `DiagCheck` entries (empty `diagDetails`).
2. `buildReport` with `invalid-module` fixture produces specific failures for name, duplicates, exports, prompts, files, and destinations.
3. Each lint check fires on a crafted module: unused variable, required without prompt, duplicate destinations, empty choice, missing description.
4. Each lint check does NOT fire on a clean module.
5. Lint checks only appear when the `Bool` lint flag is `True`.
6. `renderReportPlain` produces the expected check-mark format for a valid report.
7. `renderReportPlain` produces the expected cross-mark format for an invalid report.
8. The report correctly reflects `reportDhallOk = False`.

### Existing Tests

All existing tests continue to pass. The `validateModule` function is unchanged — `buildReport` calls the same check functions. The `ModuleSpec` tests remain valid.

### Manual Test

Running `seihou validate-module` on the `haskell-base` fixture shows colored check-by-check output. Running on `invalid-module` shows specific failures with ✗ markers. Adding `--lint` shows additional advisory warnings in yellow. Piping to `cat` produces plain text.


## Idempotence and Recovery

All milestones are additive. The new `Seihou.Engine.Validate` module is a new file. The changes to `Seihou.Core.Module` only add exports (no behavior changes). The `handleValidateModule` rewrite replaces the existing 59-line handler with the new report-based flow but preserves the same exit code semantics. Each milestone can be re-run safely.

The `--lint` flag defaults to `False`, so existing scripts calling `seihou validate-module` see no behavior change beyond the improved output formatting.


## Interfaces and Dependencies

### No New External Dependencies

All required libraries are already in the dependency tree. `ansi-terminal` is in `seihou-cli.cabal`. No new packages needed.

### Modified Module in seihou-core

In `seihou-core/src/Seihou/Core/Module.hs`, add to exports:

    checkNameFormat :: Module -> [Text]
    checkUniqueVars :: Module -> [Text]
    checkPromptRefs :: Module -> [Text]
    checkFileExistence :: FilePath -> Module -> IO [Text]
    checkExportRefs :: Module -> [Text]
    checkDependencyNames :: Module -> [Text]
    checkSafeDestinations :: Module -> [Text]
    checkDestVarRefs :: Module -> [Text]
    isValidModuleName :: Text -> Bool
    extractPlaceholders :: Text -> [Text]

### New Module in seihou-core

In `seihou-core/src/Seihou/Engine/Validate.hs`, define:

    data DiagSeverity = DiagError | DiagWarning
    data DiagCheck = DiagCheck
      { diagLabel :: Text, diagSeverity :: DiagSeverity, diagDetails :: [Text] }
    data ValidateReport = ValidateReport
      { reportModule :: Module, reportPath :: FilePath,
        reportDhallOk :: Bool, reportChecks :: [DiagCheck] }

    buildReport :: Bool -> FilePath -> Module -> IO ValidateReport
    renderReportPlain :: ValidateReport -> Text
    reportHasErrors :: ValidateReport -> Bool

### Modified Module in seihou-cli

In `seihou-cli/src/Seihou/CLI/Style.hs`, add:

    renderReportColor :: Bool -> ValidateReport -> Text

In `seihou-cli/src/Seihou/CLI/Commands.hs`, modify:

    data ValidateOpts = ValidateOpts
      { validatePath :: Maybe FilePath,
        validateLint :: Bool
      }

In `seihou-cli/src/Seihou/CLI/Validate.hs`, rewrite:

    handleValidateModule :: ValidateOpts -> IO ()
    -- Uses buildReport + renderReportColor, exits 0 or 1
