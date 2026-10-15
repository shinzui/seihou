---
slug: fix-validate-command
title: "Fix Validate Command"
kind: exec-plan
created_at: 2026-03-04T19:58:19Z
---


# Fix Validate Command

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

The `seihou validate-module` command checks that a module directory is well-formed, reporting which validation rules pass or fail. The command works end-to-end, but has two bugs:

1. When `module.dhall` is missing, the command exits with code 1 instead of code 4 as specified in the design doc. Exit code 4 signals a filesystem-level problem (path doesn't exist or `module.dhall` missing) rather than a validation failure (code 1). Scripts that distinguish between "module invalid" (code 1) and "module not found" (code 4) will misclassify missing-module errors.

2. When Dhall evaluation fails (syntax error, type error, malformed `when` expression), the error details are discarded. The user sees "module.dhall failed to evaluate" but not why it failed. The Dhall error text (e.g., "Invalid when expression" or a Dhall type mismatch) is thrown away in the CLI handler.

After this change, a user running `seihou validate-module /nonexistent` will see an error and get exit code 4. A user running `seihou validate-module` on a module with a Dhall syntax error will see the specific error message from the Dhall evaluator.


## Progress

- [x] M1-1: Fix exit code 4 for missing `module.dhall` in CLI handler (2026-03-04)
- [x] M1-2: Add `reportDhallError` field to `ValidateReport` (2026-03-04)
- [x] M1-3: Update `renderReportPlain` to show Dhall error details (2026-03-04)
- [x] M1-4: Update `renderReportColor` to show Dhall error details (2026-03-04)
- [x] M1-5: Pass Dhall error text through in CLI handler (2026-03-04)
- [x] M1-6: Build — `cabal build all` (2026-03-04)
- [x] M2-1: Update existing `ValidateSpec` tests for new `reportDhallError` field (2026-03-04)
- [x] M2-2: Add test for Dhall error text appearing in rendered report (2026-03-04)
- [x] M2-3: Add test for Dhall error absent when `reportDhallError = Nothing` (2026-03-04)
- [x] M2-4: Build and test — `cabal test all` passes — 473 tests (2026-03-04)


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Add a `reportDhallError :: Maybe Text` field to `ValidateReport` rather than encoding the Dhall error as a `DiagCheck`.
  Rationale: The Dhall error is not a validation check in the same sense as the 9 core checks. It is a prerequisite failure that prevents all other checks from running. Encoding it as a separate field keeps the `DiagCheck` list consistent (only populated when Dhall succeeds) and avoids special-casing in rendering logic. The rendering functions already have a `dhallLine` branch that handles the `reportDhallOk` case, so adding the error text under that branch is natural.
  Date: 2026-03-04

- Decision: Use `exitWith (ExitFailure 4)` for missing `module.dhall` to match the design spec, rather than keeping `exitFailure` (code 1).
  Rationale: The design spec at `docs/dev/design/proposed/cli-commands.md` line 435 specifies exit code 4 for "Path doesn't exist or module.dhall missing", and lines 489 specifies code 4 for "Filesystem error" on `validate-module`. Exit code 1 is for "Module is invalid (errors printed to stderr)" which is a different failure mode. Distinguishing these codes allows scripts to take different actions.
  Date: 2026-03-04

- Decision: The "when expressions parse successfully" check from the design spec (check #8) is not added as a separate validation rule because it is already covered implicitly. The `parseWhen` function in `Seihou.Dhall.Eval` (line 247) calls `error` on malformed expressions, which is caught by `try` in `evalModuleFromFile`. A bad `when` expression causes a Dhall decode failure, which is surfaced as a Dhall evaluation error in the report.
  Date: 2026-03-04


## Outcomes & Retrospective

All milestones complete. Changes delivered:

1. **Exit code 4** for missing `module.dhall` — matches the design spec. Previously exited with code 1.
2. **Dhall error details** now displayed in the validation report. When Dhall evaluation fails, the specific error message appears indented under "module.dhall failed to evaluate".
3. **New `reportDhallError` field** on `ValidateReport` — set to `Just errorText` when Dhall fails, `Nothing` when it succeeds or when the error is not available.
4. Test count: 472 → 473 (+1 new test for Dhall error rendering without details).

Files changed:
- `seihou-core/src/Seihou/Engine/Validate.hs` — added `reportDhallError` field, updated `buildReport` and `renderReportPlain`
- `seihou-cli/src/Seihou/CLI/Style.hs` — updated `renderReportColor` for Dhall error display
- `seihou-cli/src/Seihou/CLI/Validate.hs` — exit code 4, Dhall error passthrough
- `seihou-core/test/Seihou/Engine/ValidateSpec.hs` — updated 2 tests, added 1 new test


## Context and Orientation

Seihou is a composable project scaffolding tool written in Haskell (GHC 9.12.2, GHC2024). It uses a multi-package Cabal workspace with two packages: `seihou-core` (library) and `seihou-cli` (executable).

The validate-module command validates that a module directory contains a well-formed `module.dhall` file and passes 9 structural checks (name format, unique variables, prompt references, export references, file existence, dependency names, safe destinations, destination variable references, command safety). An optional `--lint` flag adds 5 advisory warnings (unused variables, required vars without prompts, duplicate destinations, empty choices, missing descriptions).

The command's code lives in three layers:

1. **CLI handler** at `seihou-cli/src/Seihou/CLI/Validate.hs` — the `handleValidateModule` function that orchestrates the validation flow: determine module path, check for `module.dhall`, evaluate Dhall, build report, render, and exit.

2. **Engine validation** at `seihou-core/src/Seihou/Engine/Validate.hs` — the `ValidateReport` type and `buildReport` function that structures the results of each check into a diagnostic report. Also contains `renderReportPlain` for plain-text rendering and `reportHasErrors` for determining the exit code.

3. **CLI style** at `seihou-cli/src/Seihou/CLI/Style.hs` — the `renderReportColor` function that renders the report with ANSI color codes (green for pass, red for error, yellow for warning).

4. **Core validation** at `seihou-core/src/Seihou/Core/Module.hs` — individual check functions (`checkNameFormat`, `checkUniqueVars`, etc.) that return lists of error messages. These are called by `buildReport`.

The `ValidateReport` type is defined in `seihou-core/src/Seihou/Engine/Validate.hs` (lines 44–50):

    data ValidateReport = ValidateReport
      { reportModule :: Module,
        reportPath :: FilePath,
        reportDhallOk :: Bool,
        reportChecks :: [DiagCheck]
      }

The `ValidateOpts` type is defined in `seihou-cli/src/Seihou/CLI/Commands.hs`:

    data ValidateOpts = ValidateOpts
      { validatePath :: Maybe FilePath,
        validateLint :: Bool
      }

The test suite for engine validation is at `seihou-core/test/Seihou/Engine/ValidateSpec.hs` with 30+ tests covering `buildReport`, lint checks, `renderReportPlain`, `reportHasErrors`, and command safety. These tests construct `ValidateReport` values directly and will need updating when the new field is added.

The design specification at `docs/dev/design/proposed/cli-commands.md` (lines 380–436) defines the output format, exit codes, and validation checks.


## Plan of Work

### Milestone 1: Fix exit code and Dhall error reporting

This milestone fixes both bugs. At the end, `seihou validate-module` on a missing path exits with code 4, and Dhall evaluation failures show the specific error message.

In `seihou-core/src/Seihou/Engine/Validate.hs`, add a new field `reportDhallError :: Maybe Text` to the `ValidateReport` record. Update `buildReport` to set this field to `Nothing` (since `buildReport` is only called when Dhall succeeds). Update `renderReportPlain` to display the Dhall error text (indented under the "module.dhall failed to evaluate" line) when present. No changes to `reportHasErrors` — it already checks `reportDhallOk`.

In `seihou-cli/src/Seihou/CLI/Style.hs`, update `renderReportColor` to display the Dhall error text with dim styling under the red cross mark, mirroring the plain-text rendering.

In `seihou-cli/src/Seihou/CLI/Validate.hs`, make two changes. First, replace `exitFailure` on the missing `module.dhall` branch with `exitWith (ExitFailure 4)`, and add the import for `exitWith` and `ExitFailure`. Second, in the `Left err ->` branch of Dhall evaluation, capture the error text and set `reportDhallError = Just (T.pack (show err))` on the dummy report.


### Milestone 2: Tests

This milestone updates existing tests to account for the new field and adds tests for the new behavior. At the end, all tests pass and the new error rendering is verified.

In `seihou-core/test/Seihou/Engine/ValidateSpec.hs`, update the one test that constructs a `ValidateReport` directly (the "renders a Dhall-failure report" test and "returns True when Dhall failed" test) to include the new `reportDhallError` field. Add a new test that constructs a report with `reportDhallError = Just "some error"` and verifies that `renderReportPlain` includes the error text in the output. Add a test verifying that the rendered report for a Dhall error with details shows the error message under the cross mark.


## Concrete Steps

**Working directory**: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

**Step 1** (M1): Edit `seihou-core/src/Seihou/Engine/Validate.hs`:
- Add `reportDhallError :: Maybe Text` to `ValidateReport` record (after `reportDhallOk`)
- In `buildReport`, set `reportDhallError = Nothing` in the returned record
- In `renderReportPlain`, add the Dhall error detail line after "module.dhall failed to evaluate" when `reportDhallError` is `Just errText`

**Step 2** (M1): Edit `seihou-cli/src/Seihou/CLI/Style.hs`:
- In `renderReportColor`, add the Dhall error detail line (dim-styled) after the red cross line when `reportDhallError report` is `Just errText`

**Step 3** (M1): Edit `seihou-cli/src/Seihou/CLI/Validate.hs`:
- Replace `exitFailure` on the `not exists` branch with `exitWith (ExitFailure 4)`
- Add imports: `System.Exit (ExitCode (..), exitFailure, exitWith)`
- In the `Left err ->` branch, set `reportDhallError = Just (T.pack (show err))` on the report

**Step 4** (M1): Build:

    cabal build all

Expected: compiles cleanly.

**Step 5** (M2): Edit `seihou-core/test/Seihou/Engine/ValidateSpec.hs`:
- Update the "renders a Dhall-failure report" test: add `reportDhallError = Just "test error"` to the constructed report, and verify the error text appears in the rendered output.
- Update the "returns True when Dhall failed" test: add `reportDhallError = Just "test error"` to the constructed report.
- Add new test: construct a report with `reportDhallError = Nothing` and `reportDhallOk = True` and verify no error detail appears.

**Step 6** (M2): Build and run tests:

    cabal build all && cabal test all

Expected: all 472 existing tests pass with updated assertions.


## Validation and Acceptance

### Automated

    cabal test all

All 472 existing tests pass. The updated ValidateSpec tests verify:
- A Dhall-failure report with `reportDhallError = Just "test error"` renders the error text in the output.
- A Dhall-failure report with `reportDhallError = Nothing` (legacy) still renders correctly.
- The `reportHasErrors` function still returns `True` when Dhall failed.

### Manual acceptance

Validate a module with a missing `module.dhall`:

    seihou validate-module /tmp/nonexistent; echo "exit: $?"

Expected: error message about missing `module.dhall`, exit code 4.

Validate a well-formed module:

    seihou validate-module /path/to/valid/module; echo "exit: $?"

Expected: all checks pass, exit code 0.


## Idempotence and Recovery

All steps are safe to repeat. The changes are additive (new record field, additional rendering logic). If a step fails partway, `git checkout` on the affected files reverts to the previous working state.


## Interfaces and Dependencies

No new external dependencies.

In `seihou-core/src/Seihou/Engine/Validate.hs`, the updated type:

    data ValidateReport = ValidateReport
      { reportModule :: Module,
        reportPath :: FilePath,
        reportDhallOk :: Bool,
        reportDhallError :: Maybe Text,
        reportChecks :: [DiagCheck]
      }

In `seihou-cli/src/Seihou/CLI/Validate.hs`, the handler signature does not change:

    handleValidateModule :: ValidateOpts -> IO ()
