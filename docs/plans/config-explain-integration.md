# Thread Namespace Name Through Variable Resolution

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

When a user runs `seihou vars haskell-base --explain`, the provenance column should show exactly where each value came from, including the namespace name when a value comes from a namespace config file. Currently, the output for a namespace-sourced value reads `from namespace  config` (with a double space and no namespace name) because the `resolveVariables` function hardcodes an empty string for the namespace. After this change, it will correctly read `from namespace haskell config`, making the provenance output fully informative.

The user can verify the fix by setting a value with `seihou config set haskell.ghc 9.12.2 --namespace haskell`, then running `seihou vars haskell-base --explain` and seeing `haskell.ghc = "9.12.2"  (from namespace haskell config)` in the output.


## Progress

- [x] M1-1: Add `namespace` parameter to `resolveVariables` in `Variable.hs` (2026-03-03)
- [x] M1-2: Update `resolveComposedVariables` in `Resolve.hs` to accept and thread the namespace (2026-03-03)
- [x] M1-3: Update `resolveWithPrompts` in `Resolve.hs` to accept and thread the namespace (2026-03-03)
- [x] M1-4: Update CLI call site in `Vars.hs` to pass the namespace (2026-03-03)
- [x] M1-5: Update CLI call site in `Run.hs` to pass the namespace (2026-03-03)
- [x] M1-6: Update all test call sites in `VariableSpec.hs` (2026-03-03)
- [x] M1-7: Update all test call sites in `ResolveSpec.hs` (2026-03-03)
- [x] M1-8: Update all test call sites in `CompositionSpec.hs` (2026-03-03)
- [x] M1-9: Update all test call sites in `PromptSpec.hs` (2026-03-03)
- [x] M1-10: Update all test call sites in `ExecutionSpec.hs` and `GenerationSpec.hs` (2026-03-03)
- [x] M1-11: Updated `FromNamespaceConfig ""` assertions to `FromNamespaceConfig "haskell"` in namespace-specific tests (2026-03-03)
- [x] M1-12: Build and test — all 458 tests pass (2026-03-03)
- [x] M1-13: Manual verification — `seihou vars haskell-base --explain` shows `from namespace haskell config` (2026-03-03)


## Surprises & Discoveries

- The change was entirely mechanical — adding one `Text` parameter and threading it through. No surprises encountered.


## Decision Log

- Decision: Add a `Text` parameter (the namespace name) to `resolveVariables` rather than changing the config map keys or introducing a wrapper type.
  Rationale: The simplest change that fixes the bug. `resolveVariables` already receives the three config maps as separate arguments; it just lacks the namespace name to populate `FromNamespaceConfig`. Adding one `Text` parameter is minimal, non-breaking in spirit (all call sites must be updated, but the change is mechanical), and keeps the function pure. The alternative — embedding the namespace in the config map keys or creating a `ConfigContext` record — would add complexity with no benefit.
  Date: 2026-03-03

- Decision: Pass empty text `""` as the namespace parameter in tests that don't use namespace config.
  Rationale: Most existing tests pass `Map.empty` for the namespace config map and don't test namespace provenance. Passing `""` for the namespace name in those tests is consistent with the current behavior (they never match a namespace config key, so the namespace string is never used). This avoids inflating the diff by inventing fake namespace names in tests that don't exercise that path.
  Date: 2026-03-03

- Decision: Implement as a single milestone since all changes are interdependent.
  Rationale: The signature change to `resolveVariables` cascades to every call site immediately — partial changes won't compile. A single milestone with a single commit keeps the codebase in a working state at every point.
  Date: 2026-03-03


## Outcomes & Retrospective

All 13 items completed. The namespace name now flows correctly through the entire resolution pipeline. Manual verification confirmed `from namespace haskell config` appears in `--explain` output. All 458 tests pass unchanged (with updated assertions). The fix was minimal: one new parameter threaded through 4 source files and 6 test files.


## Context and Orientation

Variable resolution in Seihou follows a six-layer precedence chain: CLI overrides > environment variables > local config > namespace config > global config > module defaults. Each resolved variable carries a `VarSource` tag that records where its value came from. The `--explain` flag on `seihou vars` displays these tags in a human-readable provenance report.

The relevant source files are:

`seihou-core/src/Seihou/Core/Variable.hs` defines `resolveVariables`, a pure function that takes six arguments (variable declarations, CLI overrides, environment variables, and three config maps) and returns resolved variables tagged with `VarSource`. On line 147, the namespace lookup hardcodes `FromNamespaceConfig ""` because the function receives the namespace config as an opaque `Map VarName Text` with no knowledge of which namespace it came from.

`seihou-core/src/Seihou/Core/Types.hs` defines `VarSource` with the constructor `FromNamespaceConfig Text`, where the `Text` field is meant to hold the namespace name (e.g., `"haskell"`). The `formatExplain` function in `Variable.hs` renders this as `"from namespace <ns> config"`.

`seihou-core/src/Seihou/Composition/Resolve.hs` defines `resolveComposedVariables` and `resolveWithPrompts`, which wrap `resolveVariables` for multi-module composition with export visibility and interactive prompts. Both call `resolveVariables` and must thread the namespace parameter through.

`seihou-cli/src/Seihou/CLI/Vars.hs` is the CLI handler for `seihou vars`. Its `explainMode` function reads config files via the `ConfigReader` effect, derives the namespace from the module name (e.g., `"haskell-base"` → `"haskell"`), and calls `resolveVariables`. It already has the namespace string available in a local `namespace` binding — it just does not pass it to `resolveVariables`.

`seihou-cli/src/Seihou/CLI/Run.hs` follows the same pattern, deriving the namespace and calling `resolveWithPrompts` with the three config maps.

Test files that call `resolveVariables` or its wrappers: `VariableSpec.hs` (~20 calls), `ResolveSpec.hs` (~11 calls), `CompositionSpec.hs` (~5 calls), `PromptSpec.hs` (~4 calls), `ExecutionSpec.hs` (1 call), `GenerationSpec.hs` (5 calls). Most pass `Map.empty` for the namespace config and don't test namespace provenance.


## Plan of Work

### Milestone 1: Thread namespace name through resolution

This milestone adds a `Text` parameter (the namespace name) to `resolveVariables`, threads it through `resolveComposedVariables` and `resolveWithPrompts`, updates the two CLI call sites, and updates all test call sites. At the end, `seihou vars <module> --explain` correctly shows the namespace name in provenance output when a variable comes from namespace config. All 458 existing tests still pass.

In `seihou-core/src/Seihou/Core/Variable.hs`, add a `Text` parameter named `namespace` between the environment variables and the local config in `resolveVariables`'s signature. On line 147, change `FromNamespaceConfig ""` to `FromNamespaceConfig namespace`. The new signature becomes:

    resolveVariables ::
      [VarDecl] ->
      Map VarName Text ->   -- CLI overrides
      Map Text Text ->       -- Environment variables
      Text ->                -- Namespace name (used in provenance tagging)
      Map VarName Text ->    -- Local config
      Map VarName Text ->    -- Namespace config
      Map VarName Text ->    -- Global config
      Either [VarError] (Map VarName ResolvedVar)

In `seihou-core/src/Seihou/Composition/Resolve.hs`, add the same `Text` parameter to `resolveComposedVariables` and `resolveWithPrompts`, inserting it after `envVars` and before `localConfig`. Thread it through to the inner `resolveVariables` calls (three sites: line 89, line 135, and line 172).

In `seihou-cli/src/Seihou/CLI/Vars.hs`, in `explainMode`, the `namespace` binding already exists. Insert it into the `resolveVariables` call at line 97, between `envVars` and `localMap`.

In `seihou-cli/src/Seihou/CLI/Run.hs`, in `handleRun`, the `namespace` binding already exists at line 76. Insert it into the `resolveWithPrompts` call at line 84, between `envVars` and `localMap`.

In every test file, insert `""` as the namespace parameter in each `resolveVariables`, `resolveComposedVariables`, and `resolveWithPrompts` call — except for the namespace-specific tests in `VariableSpec.hs` which should pass `"haskell"` (or whatever namespace the test is exercising). Update the three existing `FromNamespaceConfig ""` assertions in `VariableSpec.hs` (lines 368, 403, 470) to `FromNamespaceConfig "haskell"` since those tests now pass a namespace name.


## Concrete Steps

**Working directory**: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

**Step 1**: Edit `seihou-core/src/Seihou/Core/Variable.hs`. Add `Text` parameter to `resolveVariables` signature (after `envVars`, before `localConfig`). Change `FromNamespaceConfig ""` on line 147 to `FromNamespaceConfig namespace`.

**Step 2**: Edit `seihou-core/src/Seihou/Composition/Resolve.hs`. Add `Text` parameter to `resolveComposedVariables` and `resolveWithPrompts` signatures (after `envVars`, before `localConfig`). Thread it into the three inner `resolveVariables` calls.

**Step 3**: Edit `seihou-cli/src/Seihou/CLI/Vars.hs`. In `explainMode`, insert `namespace` argument into the `resolveVariables` call.

**Step 4**: Edit `seihou-cli/src/Seihou/CLI/Run.hs`. In `handleRun`, insert `namespace` argument into the `resolveWithPrompts` call.

**Step 5**: Edit `seihou-core/test/Seihou/Core/VariableSpec.hs`. Insert `""` in all `resolveVariables` calls that don't test namespace provenance. Insert `"haskell"` in the namespace-specific tests. Update the three `FromNamespaceConfig ""` assertions to `FromNamespaceConfig "haskell"`.

**Step 6**: Edit `seihou-core/test/Seihou/Composition/ResolveSpec.hs`. Insert `""` in all `resolveComposedVariables` calls.

**Step 7**: Edit `seihou-core/test/Seihou/Integration/CompositionSpec.hs`. Insert `""` in all `resolveComposedVariables` calls.

**Step 8**: Edit `seihou-core/test/Seihou/Interaction/PromptSpec.hs`. Insert `""` in all `resolveWithPrompts` calls.

**Step 9**: Edit `seihou-core/test/Seihou/Integration/ExecutionSpec.hs` and `seihou-core/test/Seihou/Integration/GenerationSpec.hs`. Insert `""` in all `resolveVariables` calls.

**Step 10**: Build and test:

    cabal build all
    cabal test all

Expected: all 458 tests pass.

**Step 11**: Manual verification using the built binary:

    seihou config set haskell.ghc 9.12.2 --namespace haskell
    seihou vars haskell-base --explain --var project.name=my-app --var project.version=0.1.0

Expected output includes:

    haskell.ghc = "9.12.2"  (from namespace haskell config)


## Validation and Acceptance

### Automated

    cabal test all

All 458 existing tests pass. No new tests are needed because the existing `VariableSpec.hs` six-layer precedence tests already exercise namespace config resolution — they will now assert `FromNamespaceConfig "haskell"` instead of `FromNamespaceConfig ""`, which is a stronger assertion.

### Manual acceptance criteria

1. **Namespace provenance visible**: Run `seihou config set haskell.ghc 9.12.2 --namespace haskell`, then `seihou vars haskell-base --explain --var project.name=my-app --var project.version=0.1.0`. The output line for `haskell.ghc` reads `from namespace haskell config`.

2. **Other sources unaffected**: In the same explain output, variables from CLI show `from --set flag`, variables from defaults show `from module default`. No double spaces or empty labels appear.

3. **All tests pass**: `cabal test all` reports 458 tests passed.


## Idempotence and Recovery

All edits are safe to repeat. The signature change is a compile-time contract: if any call site is missed, the build fails with a clear type error. Rolling back is a simple `git checkout` of the affected files. No persistent state, files, or config is modified.


## Interfaces and Dependencies

No new dependencies. The change modifies existing function signatures only.

In `seihou-core/src/Seihou/Core/Variable.hs`:

    resolveVariables ::
      [VarDecl] ->
      Map VarName Text ->   -- CLI overrides
      Map Text Text ->       -- Environment variables
      Text ->                -- Namespace name
      Map VarName Text ->    -- Local config
      Map VarName Text ->    -- Namespace config
      Map VarName Text ->    -- Global config
      Either [VarError] (Map VarName ResolvedVar)

In `seihou-core/src/Seihou/Composition/Resolve.hs`:

    resolveComposedVariables ::
      [(Module, FilePath)] ->
      Map VarName Text ->
      Map Text Text ->
      Text ->                -- Namespace name (new)
      Map VarName Text ->
      Map VarName Text ->
      Map VarName Text ->
      Either [VarError] (Map ModuleName (Map VarName ResolvedVar))

    resolveWithPrompts ::
      (Console :> es) =>
      [(Module, FilePath)] ->
      Map VarName Text ->
      Map Text Text ->
      Text ->                -- Namespace name (new)
      Map VarName Text ->
      Map VarName Text ->
      Map VarName Text ->
      Eff es (Either [VarError] (Map ModuleName (Map VarName ResolvedVar)))
