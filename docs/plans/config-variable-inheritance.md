# Automatic Variable Resolution via Config Hierarchy

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, a user who sets common variable values in their config files never has to pass `--var` flags for those values again. For example, a user who runs `seihou config set author.name "Jane Doe" --global` and `seihou config set license MIT --global` will have those values automatically resolve for every module that declares `author.name` or `license` variables. A user can verify this by running `seihou vars haskell-base --explain` and seeing each variable's resolved value annotated with its source layer (global config, local config, namespace config, CLI, env, or module default).

The config hierarchy already exists in Seihou. The six-layer precedence chain (CLI, env, local config, namespace config, global config, module default) is implemented in `seihou-core/src/Seihou/Core/Variable.hs` and wired through `seihou run` and `seihou vars --explain`. However, several gaps prevent this from being a fully seamless experience:

1. Optional variables without defaults are treated as errors instead of being silently omitted, making the system fragile when configs don't cover every declared variable.
2. The `seihou vars` command resolves a single module in isolation, ignoring dependency exports, so its output diverges from what `seihou run` actually resolves.
3. The `seihou config list` command does not show namespace configs or a merged effective view, making it hard to understand what values are in play.
4. There is no way to see which config values are unused (set in config but not declared by any module) or which declared variables remain unresolved after config lookup.
5. Non-required variables that lack both a default and a config value crash with `MissingRequiredVar` even though they are explicitly marked non-required — this is a bug.

This plan addresses all five gaps so that declared variables are automatically resolved from the config hierarchy with clear diagnostics when something is missing or unused.


## Progress

- [x] Milestone 1: Fix the non-required variable resolution bug (2026-03-06)
  - [x] Changed `resolveOne` return type to `Either VarError (Maybe (VarName, ResolvedVar))`
  - [x] Non-required variables with no value now return `Right Nothing` (omitted from map)
  - [x] Updated `formatDeclarations` to show `(optional, no default)` for non-required vars
  - [x] Added 4 new tests: omit optional, error on required, resolve optional with value, mixed scenario
  - [x] All 513 tests pass (493 core + 20 CLI)
- [x] Milestone 2: Make `seihou vars --explain` composition-aware (2026-03-06)
  - [x] Rewrote `explainMode` to use `loadComposition` and `resolveWithPrompts`
  - [x] `declarationMode` remains single-module (no change needed)
  - [x] Added `Console` effect via `runConsole` for interactive prompt support
  - [x] Target module's resolved vars (including inherited exports) shown with provenance
  - [x] Composition info logged when multiple modules involved
  - [x] All 513 tests pass
- [x] Milestone 3: Add `seihou config list --effective` merged view (2026-03-06)
  - [x] Added `configEffective :: Bool` to `ConfigOpts` in Commands.hs
  - [x] Added `--effective` / `-e` flag to config parser
  - [x] Implemented `handleListEffective` with source-annotated merged output
  - [x] Merge order: local > namespace > global (matching resolution precedence)
  - [x] All 513 tests pass
- [x] Milestone 4: Add diagnostics for unused config values and unresolved variables (2026-03-06)
  - [x] Added `diagnoseResolution` function to Variable.hs
  - [x] Wired into Run.hs: warns about unused config keys at LogNormal level
  - [x] Wired into Vars.hs: shows unused config keys and unresolved optional vars after provenance
  - [x] Added 4 tests for diagnoseResolution: unused keys, unresolved optional, clean match, multi-layer
  - [x] All 517 tests pass (497 core + 20 CLI)
- [ ] Milestone 5: End-to-end validation of the automatic resolution flow


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Fix the non-required variable bug before other work.
  Rationale: The bug at `Variable.hs:155-157` makes both branches (required and non-required) return `MissingRequiredVar`, which causes false failures when a non-required variable has no value from any source. This must be fixed first because it blocks the "automatic resolution" story — a module with optional variables that aren't in any config should not fail.
  Date: 2026-03-06

- Decision: Make `seihou vars --explain` use the full composition pipeline rather than single-module resolution.
  Rationale: The `seihou run` command resolves variables through `resolveWithPrompts` which handles dependency exports, but `seihou vars --explain` calls `resolveVariables` on a single module. This means a user inspecting variables sees different results than what `seihou run` actually uses. Aligning the two builds trust in the config hierarchy.
  Date: 2026-03-06

- Decision: Add `--effective` flag to `seihou config list` rather than changing the default behavior.
  Rationale: The current `seihou config list` shows per-scope values, which is useful for understanding what is set where. The merged view is a different question ("what value wins?") and deserves its own flag. This avoids breaking existing behavior.
  Date: 2026-03-06

- Decision: Scope this plan to the existing six-layer precedence chain; do not add new layers or Dhall-native typed configs.
  Rationale: The precedence chain (CLI, env, local, namespace, global, default) is well-tested and covers the user's stated need. Typed Dhall configs (where a config file produces `Map Text VarValue` instead of `Map Text Text`) would be a nice enhancement but adds complexity without solving the immediate gaps. It can be a follow-up plan.
  Date: 2026-03-06


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Seihou is a composable, type-safe project scaffolding system. Modules are defined in Dhall (`module.dhall` files) and declare typed variables that control file generation. Variables are resolved through a six-layer precedence chain before being passed to the template engine.

The term "config hierarchy" refers to the three Dhall config files that sit between environment variables and module defaults in the precedence chain:

    1. CLI flags            (highest)    --var project.name=my-app
    2. Environment          (high)       SEIHOU_VAR_PROJECT_NAME=my-app
    3. Local config         (medium)     .seihou/config.dhall
    4. Namespace config     (medium-low) ~/.config/seihou/namespaces/<ns>/config.dhall
    5. Global config        (low)        ~/.config/seihou/config.dhall
    6. Module defaults      (lowest)     default = Some "my-value" in module.dhall

A "declared variable" is a `VarDecl` record in a module's `module.dhall`. It has a name, type, optional default, required flag, and optional validation. "Automatic resolution" means that if any layer in the hierarchy provides a value for a declared variable, the variable resolves without the user needing to pass `--var`.

Key files and their roles:

- `seihou-core/src/Seihou/Core/Types.hs` — All core types: `VarDecl`, `VarValue`, `VarSource`, `ResolvedVar`, `VarError`, `ConfigScope`, `ConfigError`.
- `seihou-core/src/Seihou/Core/Variable.hs` — The `resolveVariables` function implements the six-layer lookup. Also contains `coerceValue` (string-to-typed conversion), `validateVarValue`, `formatExplain`, and `formatDeclarations`.
- `seihou-core/src/Seihou/Composition/Resolve.hs` — `resolveComposedVariables` and `resolveWithPrompts` resolve variables for multi-module compositions, handling dependency exports.
- `seihou-core/src/Seihou/Effect/ConfigReader.hs` — The `ConfigReader` effect with operations `ReadGlobalConfig`, `ReadLocalConfig`, `ReadNamespaceConfig`.
- `seihou-core/src/Seihou/Effect/ConfigReaderInterp.hs` — IO interpreter that reads Dhall config files from standard locations (`~/.config/seihou/config.dhall`, `.seihou/config.dhall`, `~/.config/seihou/namespaces/<ns>/config.dhall`).
- `seihou-core/src/Seihou/Effect/ConfigReaderPure.hs` — Pure interpreter for testing.
- `seihou-cli/src/Seihou/CLI/Run.hs` — The `handleRun` function wires config reading into the execution pipeline.
- `seihou-cli/src/Seihou/CLI/Vars.hs` — The `handleVars` function implements `seihou vars` and `seihou vars --explain`.
- `seihou-cli/src/Seihou/CLI/Config.hs` — The `handleConfig` function implements `seihou config set/get/unset/list`.
- `seihou-cli/src/Seihou/CLI/Commands.hs` — CLI parser definitions for all commands.
- `seihou-cli/src/Seihou/CLI/Shared.hs` — Shared helpers: `deriveNamespace`, `toVarNameMap`, `formatVarError`, `unwrapConfig`.
- `seihou-core/test/Seihou/Core/VariableSpec.hs` — Unit tests for variable resolution, including six-layer precedence.
- `seihou-core/test/Seihou/Effect/ConfigReaderSpec.hs` — Tests for the ConfigReader effect.


## Plan of Work

The work is divided into five milestones. Each milestone is independently verifiable and leaves the codebase in a working state.


### Milestone 1: Fix the non-required variable resolution bug

Currently, `resolveVariables` in `seihou-core/src/Seihou/Core/Variable.hs` at lines 155-157 has:

    Nothing
      | varRequired decl -> Left (MissingRequiredVar name)
      | otherwise -> Left (MissingRequiredVar name)

Both branches return the same error. A non-required variable with no value from any source should be silently omitted from the resolved map rather than producing an error. This is the root cause of false failures when modules declare optional variables that the user hasn't configured.

Edit `resolveVariables` in `seihou-core/src/Seihou/Core/Variable.hs` so that the `otherwise` branch (non-required, no value) returns `Right Nothing` instead of `Left`. This requires changing `resolveOne` to return `Either VarError (Maybe (VarName, ResolvedVar))` and adjusting the collection logic to filter out `Nothing` values.

Add tests to `seihou-core/test/Seihou/Core/VariableSpec.hs`:
- A non-required variable with no default and no config value should not appear in the resolved map and should not produce an error.
- A required variable with no value should still produce `MissingRequiredVar`.
- A non-required variable with a value from any source should still resolve normally.

At the end of this milestone, `resolveVariables` correctly distinguishes required from optional variables. Running the full test suite confirms no regressions.

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    nix develop -c cabal test all


### Milestone 2: Make `seihou vars --explain` composition-aware

Currently, `handleVars` in `seihou-cli/src/Seihou/CLI/Vars.hs` loads a single module via `loadModule` and calls `resolveVariables` directly. This means:
- Dependency exports are invisible (a variable inherited from a dependency shows as missing).
- The resolution result diverges from what `seihou run` would compute for the same module.

Change `explainMode` in `seihou-cli/src/Seihou/CLI/Vars.hs` to use `loadComposition` and `resolveComposedVariables` (from `Seihou.Composition.Resolve`) instead of `loadModule` and `resolveVariables`. The composition should include the target module and all its transitive dependencies. Display the resolved variables for the target module only (not dependencies), but with exports properly injected.

The `declarationMode` (no `--explain`) can remain single-module since it only shows declarations, not resolved values.

Add the `Console` effect to the `explainMode` effect stack to support `resolveWithPrompts`. In non-interactive contexts (piped output), prompts are skipped and missing variables appear as errors, matching `seihou run` behavior.

At the end of this milestone, running `seihou vars haskell-with-nix --explain --var project.name=my-app` shows variables inherited from `haskell-base` (like `project.name`) with their correct provenance, matching what `seihou run` would resolve.

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    nix develop -c cabal build all
    # Manual verification with a test module that has dependencies


### Milestone 3: Add `seihou config list --effective` merged view

Currently, `seihou config list` shows per-scope values. When a user has values in multiple scopes, they cannot easily see which value wins for a given key.

Add an `--effective` flag to the config command parser in `seihou-cli/src/Seihou/CLI/Commands.hs`. When present, `handleList` in `seihou-cli/src/Seihou/CLI/Config.hs` reads all three config scopes and merges them according to the precedence chain (local overrides namespace overrides global). Display each key-value pair annotated with its winning scope.

The merge logic: start with the global map, overlay the namespace map (if a namespace is provided via `--namespace`), then overlay the local map. For display, track which scope contributed each key.

Expected output format:

    Effective config:
      author.name  = "Jane Doe"       [global]
      license      = "MIT"             [local]
      haskell.ghc  = "9.12.2"         [namespace: haskell]

The `--effective` flag should be combinable with `--namespace NS` to include namespace values in the merge. Without `--namespace`, only local and global are merged.

Add a new `ConfigAction` variant `ConfigListEffective` and handle it in `handleConfig`. The effective view does not require module context — it shows the raw merged config independent of any module's declarations.

At the end of this milestone, users can run `seihou config list --effective --namespace haskell` and see the merged view of all config layers.

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    nix develop -c cabal build seihou-cli
    # Set values in global and local, then verify merged output


### Milestone 4: Add diagnostics for unused config values and unresolved variables

When `seihou run` or `seihou vars --explain` resolves variables, two kinds of mismatches can occur silently:
- A config file sets a key that no module in the composition declares (unused config value, likely a typo).
- A module declares a non-required variable that no config layer provides (unresolved optional variable).

Add a diagnostic pass after variable resolution in `seihou-core/src/Seihou/Composition/Resolve.hs` or as a new function in `seihou-core/src/Seihou/Core/Variable.hs`. This function takes the resolved variables map, the list of all declarations across modules, and the merged config maps. It returns two lists:
- Unused config keys: keys present in any config layer that do not match any declared variable name across the composition.
- Unresolved optional variables: declared variables that are not required and have no resolved value (after Milestone 1 makes this possible).

In `seihou-cli/src/Seihou/CLI/Run.hs`, emit warnings for unused config keys at `LogNormal` level. In `seihou-cli/src/Seihou/CLI/Vars.hs` (explain mode), append an "Unresolved optional variables" section after the provenance report.

Add tests to verify:
- A config key that matches no declaration is reported as unused.
- A non-required variable with no value is reported as unresolved.
- A required variable with no value remains a hard error (not a diagnostic).

At the end of this milestone, running `seihou run haskell-base --var project.name=my-app` with `auther.name` (typo) set in global config shows a warning: `Warning: config key 'auther.name' does not match any declared variable`.

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    nix develop -c cabal test all


### Milestone 5: End-to-end validation of the automatic resolution flow

This milestone validates the full user journey without writing new library code. Create or update a test fixture that exercises the complete config-to-variable flow:

1. Set global config values: `author.name`, `license`.
2. Set namespace config values: `haskell.ghc`.
3. Set local config values: `project.name`.
4. Run `seihou vars haskell-base --explain` and verify all four variables resolve from their respective config layers.
5. Run `seihou vars haskell-base --explain --var license=Apache` and verify CLI overrides the global config value.
6. Set `SEIHOU_VAR_LICENSE=BSD3` and verify env overrides global config but CLI still wins when both are present.
7. Run `seihou run haskell-base --dry-run` and verify the plan uses config-resolved values.

Document the expected output for each step. If integration tests exist in the test suite, add a new test module. Otherwise, document the manual verification steps with expected transcripts.

At the end of this milestone, the full automatic resolution story is validated end-to-end and documented.


## Concrete Steps

All commands assume the working directory is the repository root:

    /Users/shinzui/Keikaku/bokuno/seihou-project/seihou

Build and test after each milestone:

    nix develop -c cabal test all

Expected output (test count will increase as tests are added):

    All N tests passed.

For manual CLI verification:

    nix develop -c cabal run seihou -- vars haskell-base --explain --var project.name=test
    nix develop -c cabal run seihou -- config list --effective


## Validation and Acceptance

Milestone 1 acceptance: A test in `VariableSpec.hs` demonstrates that a non-required variable with no default and no config value does not appear in the resolved map and does not produce an error. The existing 6-layer precedence tests still pass.

Milestone 2 acceptance: Running `seihou vars haskell-with-nix --explain --var project.name=my-app` shows `project.name` resolved with provenance, including values inherited from `haskell-base` via exports. The output matches what `seihou run` would resolve.

Milestone 3 acceptance: Running `seihou config list --effective` after setting values in global and local scopes shows the merged view with scope annotations. Local values override global values for the same key.

Milestone 4 acceptance: Setting a misspelled config key (e.g., `auther.name` instead of `author.name`) and running `seihou run` produces a warning about the unused config key. The warning does not block execution.

Milestone 5 acceptance: The full user journey (set configs, run vars --explain, verify provenance, override with CLI/env) works end-to-end with correct precedence at every layer.


## Idempotence and Recovery

All milestones are additive. The Milestone 1 bug fix changes behavior for non-required variables only; required variables are unaffected. Milestones 2-4 add new functionality without modifying existing behavior. Each milestone can be reverted by reverting its commit(s).

The `seihou config set/unset` commands are idempotent — setting the same key twice overwrites, unsetting a missing key is a no-op. Config files are Dhall records and are always valid after a write operation.


## Interfaces and Dependencies

No new external dependencies are introduced. All work uses the existing `effectful`, `dhall`, `optparse-applicative`, and `containers` libraries.

In `seihou-core/src/Seihou/Core/Variable.hs`, the `resolveVariables` signature does not change. The internal `resolveOne` helper changes its return type from `Either VarError (VarName, ResolvedVar)` to `Either VarError (Maybe (VarName, ResolvedVar))`.

In `seihou-core/src/Seihou/Core/Variable.hs`, define a new function:

    diagnoseResolution ::
      Map VarName ResolvedVar ->
      [VarDecl] ->
      Map VarName Text ->
      Map VarName Text ->
      Map VarName Text ->
      ([VarName], [VarName])  -- (unusedConfigKeys, unresolvedOptionalVars)

In `seihou-cli/src/Seihou/CLI/Commands.hs`, add to `ConfigOpts`:

    configEffective :: Bool

In `seihou-cli/src/Seihou/CLI/Config.hs`, add:

    handleListEffective :: Maybe Text -> IO ()

In `seihou-cli/src/Seihou/CLI/Vars.hs`, change `explainMode` to use `loadComposition` and `resolveComposedVariables` instead of `loadModule` and `resolveVariables`.
