# Fix Vars Command Output Format

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

The `seihou vars <module>` command shows variable declarations for a module, and with `--explain` it resolves variables and shows where each value came from (CLI, env, config, default). The command works end-to-end but its output format does not match the design specification. After this change:

1. Default mode output matches the design spec: `  project.name     = (required, no default)` with column alignment and `=` sign format, instead of the current `  project.name (text, required)` parenthesized format.

2. Explain mode output uses bracket notation for sources (`[--var]`, `[default]`, `[env SEIHOU_VAR_X]`) instead of the current parenthesized format (`(from --set flag)`), and adds column alignment and 2-space indentation.

3. The `FromCLI` source label says `--var` instead of `--set flag` (the actual CLI flag is `--var`, not `--set`).

4. Headers say `Variables for <name>:` matching the design spec, instead of `Variables for module '<name>':` or `Variable provenance for module '<name>':`.

A user running `seihou vars haskell-base` will see aligned variable declarations with `=` signs, and `seihou vars haskell-base --explain --var project.name=hello` will show resolved values with bracket-style source tags.


## Progress

- [x] M1-1: Update `declarationMode` and `printVarDecl` in `Vars.hs` for design-spec output format (2026-03-04)
- [x] M1-2: Update `formatExplain` in `Variable.hs` for bracket notation and alignment (2026-03-04)
- [x] M1-3: Update `explainMode` header in `Vars.hs` (2026-03-04)
- [x] M1-4: Build — `cabal build all` (2026-03-04)
- [x] M2-1: Update `formatExplain` tests in `VariableSpec.hs` and add `formatDeclarations` tests (2026-03-04)
- [x] M2-2: Build and test — `cabal test all` passes — 479 tests (2026-03-04)


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Use simplified source labels instead of the full detail shown in the design spec.
  Rationale: The design spec shows `[CLI: --var project.name=my-app]` and `[default: module.dhall]` but the current `VarSource` type does not store the raw CLI flag text or the file path where the default is defined. Changing the type to carry this information would require changes throughout the resolution pipeline. Instead, use practical labels: `[--var]`, `[env SEIHOU_VAR_X]`, `[local config]`, `[namespace: <ns>]`, `[global config]`, `[default]`, `[prompt]`. These are clear enough for provenance tracking.
  Date: 2026-03-04

- Decision: Drop the type annotation from default mode output.
  Rationale: The design spec shows `project.name     = (required, no default)` and `project.version  = "0.1.0.0"` — no type information in default mode. The current implementation shows `project.name (text, required)` which includes the type. Matching the design spec produces cleaner output; the type can be inferred from the value or obtained from `module.dhall` directly.
  Date: 2026-03-04

- Decision: Extract a `formatDeclarations` function from `declarationMode` to `Seihou.Core.Variable` for testability.
  Rationale: `declarationMode` lives in `seihou-cli` (an executable) and cannot be imported by `seihou-core` tests. Extracting the pure formatting logic follows the same pattern used for `parseModuleName` (extracted to `Seihou.Core.Install`) and `formatExplain` (already in `Seihou.Core.Variable`).
  Date: 2026-03-04


## Outcomes & Retrospective

All milestones complete. Changes delivered:

1. **Default mode** now uses `formatDeclarations` from core — aligned output with `=` signs, `(required, no default)` for required vars without defaults.
2. **Explain mode** now uses bracket notation (`[--var]`, `[default]`, `[env ...]`, etc.) with 2-space indentation and column alignment.
3. **Headers** say `Variables for <name>:` — no quotes, no "module" prefix, no "provenance" prefix.
4. **Removed** unused `printVarDecl`, `formatType`, `formatValue` from `Vars.hs`.
5. Test count: 473 → 479 (+6 new tests: 1 indentation test for `formatExplain`, 5 tests for `formatDeclarations`).

Files changed:
- `seihou-core/src/Seihou/Core/Variable.hs` — added `formatDeclarations`, updated `formatExplain` with bracket notation/alignment/indentation, updated `showSource`
- `seihou-cli/src/Seihou/CLI/Vars.hs` — use `formatDeclarations`, fix headers, remove unused functions
- `seihou-core/test/Seihou/Core/VariableSpec.hs` — updated 5 `formatExplain` tests, added 6 new tests


## Context and Orientation

Seihou is a composable project scaffolding tool written in Haskell (GHC 9.12.2, GHC2024). It uses a multi-package Cabal workspace: `seihou-core` (library) and `seihou-cli` (executable).

The `vars` command has two modes. Default mode lists the variable declarations from a module (name, type, default). Explain mode resolves all variables against the six-layer config hierarchy (CLI overrides, environment variables, local config, namespace config, global config, module defaults) and shows where each value came from.

The CLI handler is at `seihou-cli/src/Seihou/CLI/Vars.hs`. It contains `handleVars` (dispatches to `declarationMode` or `explainMode`), `declarationMode` (prints declarations), `printVarDecl` (formats one declaration), `explainMode` (resolves variables and calls `formatExplain`), and helper functions `formatType` and `formatValue`.

The pure formatting for explain mode is at `seihou-core/src/Seihou/Core/Variable.hs` in the `formatExplain` function (lines 209–231). This function takes a `Map VarName ResolvedVar` and produces formatted text with provenance. The current format uses `(from ...)` parenthesized notation.

The `VarSource` type at `seihou-core/src/Seihou/Core/Types.hs` (lines 207–215) has seven constructors: `FromCLI`, `FromEnv Text`, `FromLocalConfig`, `FromNamespaceConfig Text`, `FromGlobalConfig`, `FromDefault`, `FromPrompt`.

The test suite at `seihou-core/test/Seihou/Core/VariableSpec.hs` has 5 tests for `formatExplain` that check for specific source label strings like `"from --set flag"` and `"from module default"`. These will need updating.

The design specification at `docs/dev/design/proposed/cli-commands.md` (lines 183–223) defines the output format for both modes.

The `VarsOpts` type in `seihou-cli/src/Seihou/CLI/Commands.hs` has four fields: `varsModule :: ModuleName`, `varsExplain :: Bool`, `varsVars :: [(Text, Text)]`, `varsNamespace :: Maybe Text`.


## Plan of Work

### Milestone 1: Fix output formats

This milestone updates the output of both modes to match the design spec. At the end, `seihou vars` produces aligned output with `=` signs in default mode, and bracket-style source tags in explain mode.

In `seihou-core/src/Seihou/Core/Variable.hs`, add a new function `formatDeclarations :: [VarDecl] -> Text` that produces the design-spec format for default mode. Each variable is shown as `  <name>  = <value_or_status>` with column alignment. For required variables without defaults: `(required, no default)`. For variables with defaults: the formatted value. Then update `formatExplain` to use bracket notation for sources, add 2-space indentation, and column-align the output. Update the `showSource` helper to produce `[--var]`, `[env <name>]`, `[local config]`, `[namespace: <ns>]`, `[global config]`, `[default]`, `[prompt]`.

In `seihou-core/src/Seihou/Core/Variable.hs`, export `formatDeclarations` from the module header.

In `seihou-cli/src/Seihou/CLI/Vars.hs`, update `declarationMode` to call `formatDeclarations` instead of using `printVarDecl`. Update the header text to `"Variables for <name>:"` (no quotes, no "module" prefix). Update `explainMode` header to `"Variables for <name>:"` instead of `"Variable provenance for module '<name>':"`  Remove the now-unused `printVarDecl`, `formatType`, and `formatValue` functions.


### Milestone 2: Tests

This milestone updates the 5 existing `formatExplain` tests in `VariableSpec.hs` to match the new bracket notation, and adds tests for `formatDeclarations`. At the end, all tests pass.


## Concrete Steps

**Working directory**: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

**Step 1** (M1): Edit `seihou-core/src/Seihou/Core/Variable.hs`:
- Add `formatDeclarations` to the export list
- Add `formatDeclarations :: [VarDecl] -> Text` function that produces aligned output
- Update `formatExplain` to use bracket notation, 2-space indentation, and column alignment
- Update `showSource` labels: `FromCLI` → `[--var]`, `FromDefault` → `[default]`, etc.

**Step 2** (M1): Edit `seihou-cli/src/Seihou/CLI/Vars.hs`:
- Update `declarationMode` to use `formatDeclarations`
- Update both headers to `"Variables for <name>:"`
- Remove unused `printVarDecl`, `formatType`, `formatValue`

**Step 3** (M1): Build:

    cabal build all

Expected: compiles cleanly.

**Step 4** (M2): Edit `seihou-core/test/Seihou/Core/VariableSpec.hs`:
- Update the 5 `formatExplain` tests to check for bracket notation instead of parenthesized notation
- Add tests for `formatDeclarations`

**Step 5** (M2): Build and run tests:

    cabal build all && cabal test all

Expected: all tests pass.


## Validation and Acceptance

### Automated

    cabal test all

All existing tests pass with updated assertions. The `formatExplain` tests verify bracket notation output. New `formatDeclarations` tests verify aligned output with `=` signs.

### Manual acceptance

List variables for a module:

    seihou vars <module>

Expected: aligned output matching design spec format:

    Variables for <name>:

      project.name     = (required, no default)
      project.version  = "0.1.0.0"

Show explain mode:

    seihou vars <module> --explain --var project.name=hello

Expected: resolved values with bracket-style source tags:

    Variables for <name>:

      project.name     = "hello"          [--var]
      project.version  = "0.1.0.0"       [default]


## Idempotence and Recovery

All steps are safe to repeat. The changes modify existing formatting functions. If a step fails partway, `git checkout` on the affected files reverts to the previous working state.


## Interfaces and Dependencies

No new external dependencies.

In `seihou-core/src/Seihou/Core/Variable.hs`, add:

    formatDeclarations :: [VarDecl] -> Text

The existing `formatExplain` signature does not change:

    formatExplain :: Map VarName ResolvedVar -> Text

In `seihou-cli/src/Seihou/CLI/Vars.hs`, the handler signature does not change:

    handleVars :: VarsOpts -> IO ()
