---
slug: config-file-layering-and-precedence-chain
title: "Implement Config File Layering and Precedence Chain"
kind: exec-plan
created_at: 2026-03-02T15:52:18Z
---


# Implement Config File Layering and Precedence Chain

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, Seihou resolves variables from three Dhall configuration files in addition to CLI flags, environment variables, and module defaults. A user who runs `seihou init` gets a global config file at `~/.config/seihou/config.dhall` (this already happens). They can then set commonly-used variable defaults there — for example, `{ license = "MIT", haskell.ghc = "9.12.2" }` — and those values automatically apply to every module they run, without needing `--var` flags each time. If a project has a `.seihou/config.dhall` in its working directory, those local values take precedence over global ones. Namespace configs (per-language or per-domain groupings like `haskell`, `nix`, etc., stored at `~/.config/seihou/namespaces/<ns>/config.dhall`) sit between local and global in priority.

The full six-layer precedence chain, as specified in the design doc at `docs/dev/design/proposed/variable-resolution.md`, becomes fully operational:

    1. CLI flags            (highest)    --var project.name=my-app
    2. Environment          (high)       SEIHOU_VAR_PROJECT_NAME=my-app
    3. Local config         (medium)     .seihou/config.dhall
    4. Namespace config     (medium-low) ~/.config/seihou/namespaces/<ns>/config.dhall
    5. Global config        (low)        ~/.config/seihou/config.dhall
    6. Module defaults      (lowest)     default = Some "my-value" in module.dhall

Users can verify this by running `seihou vars <module> --explain`, which now shows the actual config file source for each value (e.g., "from local config", "from namespace haskell config", "from global config").


## Progress

- [x] Milestone 1: ConfigReader effect interpreters (real IO + pure for testing) (2026-03-02)
  - [x] Created `seihou-core/src/Seihou/Dhall/Config.hs` with `evalConfigFile` and `evalConfigFileIfExists`
  - [x] Created `seihou-core/src/Seihou/Effect/ConfigReaderInterp.hs` with `runConfigReader`
  - [x] Created `seihou-core/src/Seihou/Effect/ConfigReaderPure.hs` with `runConfigReaderPure`
  - [x] Added all 3 new modules to `seihou-core.cabal` exposed-modules
  - [x] Build passed cleanly
- [x] Milestone 2: Extend resolveVariables with config layer lookups (2026-03-02)
  - [x] Modified `resolveVariables` signature to accept 3 new `Map VarName Text` params (local, namespace, global)
  - [x] Added `lookupConfig` helper for config layer lookups in precedence chain
  - [x] Updated `resolveComposedVariables` and `resolveWithPrompts` signatures to thread config maps
  - [x] Updated all callers: 13 in VariableSpec, 8 in ResolveSpec, 5 in PromptSpec, 3 in CompositionSpec, 5 in GenerationSpec, 1 in ExecutionSpec, 1 in Vars.hs, 1 in Run.hs
  - [x] All 276 tests pass
- [x] Milestone 3: Wire config reading into the run and vars commands (2026-03-02)
  - [x] Added `runNamespace :: Maybe Text` field to `RunOpts` and `varsNamespace :: Maybe Text` to `VarsOpts`
  - [x] Added `--namespace` flag parser to both `runParser` and `varsParser` in `Commands.hs`
  - [x] Updated `handleRun` to read configs via `ConfigReader` effect, derive namespace from module name
  - [x] Updated `explainMode` in `handleVars` to read configs via `ConfigReader` effect
  - [x] Added `deriveNamespace` and `toVarNameMap` helpers to both `Run.hs` and `Vars.hs`
  - [x] All 276 tests pass
- [x] Milestone 4: Tests for the full six-layer precedence chain (2026-03-02)
  - [x] Created `seihou-core/test/Seihou/Dhall/ConfigSpec.hs` (3 tests: valid config, empty record, missing/invalid file)
  - [x] Created `seihou-core/test/Seihou/Effect/ConfigReaderSpec.hs` (5 tests: pure interpreter for all 3 operations)
  - [x] Extended `VariableSpec.hs` with 14 new tests for six-layer precedence and config source provenance
  - [x] Extended `ResolveSpec.hs` with 4 new tests for config layers in composed resolution
  - [x] Wired new test modules into `Main.hs` and `seihou-core.cabal`
  - [x] Fixed `evalConfigFile` to handle empty `{=}` records (Dhall `toMap` needs type annotation for empty records)
  - [x] `nix fmt` produces no changes
  - [x] All 304 tests pass (276 existing + 28 new)


## Surprises & Discoveries

- Dhall's `toMap` operator cannot be applied to an empty record `{=}` without a type annotation (`toMap ({=})` fails with "An empty toMap requires a type annotation"). Since the default config created by `seihou init` is `{=}`, `evalConfigFile` must special-case this. Fixed by detecting `{=}` or `{ = }` and returning `Map.empty` directly rather than going through Dhall evaluation.

- The `ConfigReader` effect interface (`ConfigReader.hs`) and its three operations already existed from a previous milestone, making Milestone 1 purely about creating the interpreters and config evaluator. No type changes were needed.

- The `VarSource` constructors `FromLocalConfig`, `FromNamespaceConfig Text`, and `FromGlobalConfig` were already defined and handled in `formatExplain`'s `showSource`. No changes to the types module were needed.


## Decision Log

- Decision: Config files use Dhall and evaluate to a flat `Map Text Text` of variable-name to text-value pairs, using the same coercion rules as CLI/env sources.
  Rationale: The design doc says "Dhall config files provide native-typed values (no coercion needed)", but the current variable resolution pipeline (`resolveVariables`) works with `Map VarName Text` for CLI and `Map Text Text` for env, then coerces per-variable. Making config files produce `Map Text Text` (raw text key-value pairs) keeps the resolution function uniform and avoids a parallel typed-value pipeline. The Dhall file `{ license = "MIT", project.name = "my-app" }` naturally evaluates to text pairs. In v1, config files hold text values only. Typed config values can be added later if needed.
  Date: 2026-03-02

- Decision: Namespace is determined by a dotted prefix convention in variable names (e.g., `haskell.ghc` belongs to namespace `haskell`). The first dotted segment of the primary module's name (before the first `-`) is used as the namespace hint. If `~/.config/seihou/namespaces/<ns>/config.dhall` exists, it is loaded; otherwise the namespace layer is empty. There is no explicit `--namespace` flag for v1.
  Rationale: The design docs reference namespaces but do not define a mechanism for determining them. Using the module name's prefix is simple, convention-based, and requires no additional flags. A module named `haskell-base` maps to namespace `haskell`; `nix-flake` maps to `nix`. Modules without a hyphen (e.g., `base`) have no namespace. This can be refined later with explicit module metadata or CLI flags.
  Date: 2026-03-02

- Decision: Config file loading is best-effort — missing files are silently treated as empty maps, not errors.
  Rationale: Users should not be forced to create config files. The global config is created by `seihou init`, but local and namespace configs are entirely optional. A missing file simply means that config layer contributes no values. Only Dhall parse errors are treated as fatal.
  Date: 2026-03-02

- Decision: The `ConfigReader` effect interface already exists at `seihou-core/src/Seihou/Effect/ConfigReader.hs` with three operations. We will implement two interpreters (real IO and pure) following the pattern used for `Console` and `Filesystem`.
  Rationale: Reuse the existing effect interface rather than creating a new one.
  Date: 2026-03-02

- Decision: The `resolveVariables` pure function gains three new `Map VarName Text` parameters for local, namespace, and global config layers, rather than reading configs from within an effect.
  Rationale: The template-rendering ExecPlan's Decision Log explicitly states: "Variable resolution is a pure function taking explicit inputs, not an effect. When config file layers are added in M3, the calling code will read configs via effects and pass the results into the same pure resolution function." This keeps `resolveVariables` testable without effects.
  Date: 2026-03-02


## Outcomes & Retrospective

All 4 milestones completed successfully. The full six-layer variable resolution precedence chain is now operational:

1. CLI flags (highest) - `--var project.name=my-app`
2. Environment variables - `SEIHOU_VAR_PROJECT_NAME=my-app`
3. Local config - `.seihou/config.dhall`
4. Namespace config - `~/.config/seihou/namespaces/<ns>/config.dhall`
5. Global config - `~/.config/seihou/config.dhall`
6. Module defaults (lowest) - `default = Some "value"` in module.dhall

**Files created:** 5 new source files + 2 new test files
- `seihou-core/src/Seihou/Dhall/Config.hs` — Dhall config file evaluator
- `seihou-core/src/Seihou/Effect/ConfigReaderInterp.hs` — Real IO interpreter
- `seihou-core/src/Seihou/Effect/ConfigReaderPure.hs` — Pure test interpreter
- `seihou-core/test/Seihou/Dhall/ConfigSpec.hs` — Config evaluator tests
- `seihou-core/test/Seihou/Effect/ConfigReaderSpec.hs` — Pure interpreter tests

**Files modified:** 11 files (source + test + cabal)
- `Variable.hs`, `Resolve.hs`, `Commands.hs`, `Run.hs`, `Vars.hs` (source)
- `VariableSpec.hs`, `ResolveSpec.hs`, `PromptSpec.hs`, `CompositionSpec.hs`, `GenerationSpec.hs`, `ExecutionSpec.hs` (tests)
- `seihou-core.cabal`, `Main.hs` (infrastructure)

**Test results:** 304 tests pass (276 existing + 28 new). No existing tests broken.

**Lessons learned:**
- The design of keeping `resolveVariables` pure (accepting explicit maps) paid off — adding 3 new parameters was straightforward and all callers were mechanical updates.
- Pre-existing VarSource constructors and ConfigReader effect interface meant the type-level changes were already in place; this plan was purely about implementation and wiring.
- The `toMap` trick for config files works well but requires special-casing empty records. A future improvement could use a type-annotated `toMap` expression instead.


## Context and Orientation

Seihou is a composable project scaffolding system. It is a Haskell project built as a Cabal multi-package workspace with two packages: `seihou-core` (library, at `seihou-core/`) and `seihou-cli` (executable, at `seihou-cli/`). It uses GHC 9.12.2 with GHC2024, the `effectful` library for effects, Dhall for module definitions and config files, and `optparse-applicative` for the CLI.

A "variable" is a typed, named value (like `project.name` or `license`) that modules declare and templates consume. Variable resolution is the process of determining each variable's concrete value by searching through a prioritized chain of sources. The current implementation resolves from three sources: CLI flags (`--var`), environment variables (`SEIHOU_VAR_*`), and module defaults. Three config-file layers are specified in the design but not yet implemented.

The key files involved in this plan:

`seihou-core/src/Seihou/Core/Variable.hs` contains `resolveVariables`, the pure function that resolves a list of variable declarations against the precedence chain. It currently accepts two maps (`Map VarName Text` for CLI overrides and `Map Text Text` for environment variables) and falls through to module defaults. A comment on line 121 reads: "Layers 3-5 (local config, namespace config, global config) will be added in M3."

`seihou-core/src/Seihou/Core/Types.hs` defines `VarSource` with seven constructors. Three of them — `FromLocalConfig`, `FromNamespaceConfig Text`, and `FromGlobalConfig` — exist as placeholders that are rendered in `formatExplain` output but never assigned by any resolution code path.

`seihou-core/src/Seihou/Effect/ConfigReader.hs` defines the `ConfigReader` effect interface with three operations: `ReadGlobalConfig`, `ReadLocalConfig`, and `ReadNamespaceConfig Text`. Each returns `Map Text Text`. The effect exists but has no interpreter — no `ConfigReaderInterp.hs` or `ConfigReaderPure.hs` files exist.

`seihou-core/src/Seihou/Composition/Resolve.hs` contains `resolveComposedVariables` (pure, for multi-module resolution) and `resolveWithPrompts` (effectful, with interactive prompt support). Both pass `cliOverrides` and `envVars` through to `resolveVariables` per module. Config layers would need to be threaded through these functions as well.

`seihou-cli/src/Seihou/CLI/Run.hs` is the `handleRun` function that drives `seihou run`. It constructs `cliOverrides` from `--var` flags and `envVars` from the process environment, then calls `resolveWithPrompts`. Config reading would be added here.

`seihou-cli/src/Seihou/CLI/Vars.hs` is the `handleVars` function that drives `seihou vars --explain`. It constructs the same two maps and calls `resolveVariables` directly. Config reading would also be added here.

`seihou-cli/src/Seihou/CLI/Init.hs` already creates `~/.config/seihou/config.dhall` with a default empty record `{=}` and creates the `namespaces/` directory.

The Dhall library (`dhall >= 1.42`) is already a dependency in `seihou-core.cabal`. The `Seihou.Dhall.Eval` module contains `evalModuleFromFile` which reads and decodes Dhall files. Config files are simpler — they evaluate to a Dhall record of text key-value pairs.


## Plan of Work

The work is divided into four milestones.


### Milestone 1: ConfigReader effect interpreters

This milestone creates two interpreters for the existing `ConfigReader` effect: a real IO interpreter that reads Dhall files from disk, and a pure interpreter that returns scripted responses for testing.

Create a new file `seihou-core/src/Seihou/Effect/ConfigReaderInterp.hs` with a function `runConfigReader :: (IOE :> es) => Eff (ConfigReader : es) a -> Eff es a`. The interpreter resolves file paths using `System.Directory.getXdgDirectory XdgConfig "seihou"` for the global config base and `System.Directory.getCurrentDirectory` for the local config root. For `ReadGlobalConfig`, it reads `~/.config/seihou/config.dhall`. For `ReadLocalConfig`, it reads `.seihou/config.dhall` relative to the current directory. For `ReadNamespaceConfig ns`, it reads `~/.config/seihou/namespaces/<ns>/config.dhall`. Each operation attempts to read and evaluate the Dhall file; if the file does not exist, it returns `Map.empty`. If the file exists but contains invalid Dhall, the interpreter raises an IO error (which the caller handles).

To evaluate a Dhall config file into a `Map Text Text`, create a helper function `evalConfigFile :: FilePath -> IO (Map Text Text)` in a new module `seihou-core/src/Seihou/Dhall/Config.hs`. This function uses the `dhall` library's `inputFile` with a decoder for `Map Text Text`. The Dhall type of a config file is `{ key1 = "value1", key2 = "value2" }` which evaluates to a record. The decoder uses `Dhall.map strictText strictText` to interpret this as a `Map Text Text`. If the Dhall record has non-text values, evaluation fails with an error. A helper `evalConfigFileIfExists :: FilePath -> IO (Map Text Text)` wraps this: if the file exists, evaluate it; otherwise return `Map.empty`.

Create a pure interpreter `seihou-core/src/Seihou/Effect/ConfigReaderPure.hs` with a function `runConfigReaderPure :: Map Text Text -> Map Text (Map Text Text) -> Map Text Text -> Eff (ConfigReader : es) a -> Eff es a`. The three arguments are the local config map, a map from namespace names to their config maps, and the global config map. This allows tests to script exact config values without touching the filesystem.

Add `Seihou.Dhall.Config`, `Seihou.Effect.ConfigReaderInterp`, and `Seihou.Effect.ConfigReaderPure` to the `exposed-modules` list in `seihou-core/seihou-core.cabal`.

At the end of this milestone, `cabal build all` succeeds.


### Milestone 2: Extend resolveVariables with config layer lookups

This milestone modifies the pure `resolveVariables` function to accept three additional maps for config layers and look them up in the correct precedence position.

In `seihou-core/src/Seihou/Core/Variable.hs`, change the signature of `resolveVariables` from:

    resolveVariables ::
      [VarDecl] ->
      Map VarName Text ->  -- CLI overrides
      Map Text Text ->     -- Environment variables
      Either [VarError] (Map VarName ResolvedVar)

to:

    resolveVariables ::
      [VarDecl] ->
      Map VarName Text ->  -- CLI overrides
      Map Text Text ->     -- Environment variables
      Map VarName Text ->  -- Local config
      Map VarName Text ->  -- Namespace config
      Map VarName Text ->  -- Global config
      Either [VarError] (Map VarName ResolvedVar)

Inside `resolveOne`, the lookup chain becomes: `lookupCLI` → `lookupEnv` → `lookupLocalConfig` → `lookupNamespaceConfig` → `lookupGlobalConfig` → `varDefault`. The three new lookup functions follow the same pattern as `lookupCLI`: take the variable name and type, look up in the corresponding map, coerce the text value to the declared type, and tag with the appropriate `VarSource` (`FromLocalConfig`, `FromNamespaceConfig`, or `FromGlobalConfig`). The namespace config lookup additionally needs to know the namespace name for the `FromNamespaceConfig Text` constructor — this is passed as an additional parameter or determined from context.

Update the comment at line 121 to reflect that layers 3-5 are now implemented.

All callers of `resolveVariables` must be updated to pass the three new maps. In this milestone, pass `Map.empty` for all three in the existing callers so that existing behavior is preserved:

In `seihou-core/src/Seihou/Composition/Resolve.hs`, update `resolveComposedVariables` and `resolveWithPrompts` to accept and thread through the three new config maps. Both functions gain the three additional `Map VarName Text` parameters in their signatures. Every internal call to `resolveVariables` passes these maps along.

In `seihou-core/src/Seihou/Core/Variable.hs`, update `formatExplain`'s `showSource` (already handles all constructors — no change needed there).

At the end of this milestone, `cabal build all` and `cabal test all` succeed with all 276 existing tests passing. No behavior changes — all config maps are empty.


### Milestone 3: Wire config reading into the run and vars commands

This milestone modifies `handleRun` and `handleVars` (the CLI entry points) to actually read config files and pass the resulting maps into the resolution chain.

In `seihou-cli/src/Seihou/CLI/Run.hs`, after constructing `cliOverrides` and `envVars`, add config reading. Use the `ConfigReader` effect via `runConfigReader`:

    runEff $ runConfigReader $ runConsole $ do
      localCfg <- readLocalConfig
      namespaceCfg <- readNamespaceConfig namespace
      globalCfg <- readGlobalConfig
      let localMap = toVarNameMap localCfg
          nsMap = toVarNameMap namespaceCfg
          globalMap = toVarNameMap globalCfg
      resolveWithPrompts modulesInOrder cliOverrides envVars localMap nsMap globalMap

The `toVarNameMap` helper converts `Map Text Text` (with text keys like `"project.name"`) to `Map VarName Text` (with `VarName` keys). The namespace is derived from the primary module name: for `ModuleName "haskell-base"`, take the portion before the first hyphen to get `"haskell"`. If the module name has no hyphen, namespace config is skipped (empty map).

Similarly update `seihou-cli/src/Seihou/CLI/Vars.hs` in `explainMode` to read configs via `ConfigReader` and pass them to `resolveVariables`.

Also add `--namespace` as an optional flag to `RunOpts` and `VarsOpts` in `seihou-cli/src/Seihou/CLI/Commands.hs`, so users can explicitly override the auto-detected namespace. When provided, it takes precedence over the module-name-derived namespace.

At the end of this milestone, the full six-layer precedence chain is operational. A user can:
1. Place `{ license = "MIT" }` in `~/.config/seihou/config.dhall`
2. Run `seihou vars haskell-base --explain` and see `license = "MIT" (from global config)`
3. Place `{ license = "BSD-3-Clause" }` in `.seihou/config.dhall`
4. Run `seihou vars haskell-base --explain` and see `license = "BSD-3-Clause" (from local config)` (local overrides global)


### Milestone 4: Tests for the full six-layer precedence chain

This milestone adds comprehensive tests for config file loading and the extended resolution chain.

Create `seihou-core/test/Seihou/Dhall/ConfigSpec.hs` with tests for:
- Evaluating a valid Dhall config file to a `Map Text Text`.
- Handling a missing file (returns empty map).
- Handling an invalid Dhall file (produces an error).

Create `seihou-core/test/Seihou/Effect/ConfigReaderSpec.hs` with tests using the pure interpreter:
- `ReadGlobalConfig` returns the scripted global map.
- `ReadLocalConfig` returns the scripted local map.
- `ReadNamespaceConfig "haskell"` returns the scripted namespace map.

Extend `seihou-core/test/Seihou/Core/VariableSpec.hs` with new tests for the six-layer precedence:
- Local config overrides global config.
- Namespace config overrides global config.
- Local config overrides namespace config.
- Environment variables override local config.
- CLI flags override everything.
- Config source provenance appears correctly in `formatExplain` output.

Extend `seihou-core/test/Seihou/Composition/ResolveSpec.hs` to verify that config maps flow correctly through multi-module resolution.

Wire new test modules into `seihou-core/test/Main.hs` and `seihou-core/seihou-core.cabal`.

Run `nix fmt` and `cabal test all`. All existing and new tests must pass.


## Concrete Steps

All commands are run from the repository root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

After each milestone, rebuild and test:

    cabal build all
    cabal test all

After all milestones, format and verify:

    nix fmt
    cabal test all

To verify config layering manually after Milestone 3:

Create a global config:

    mkdir -p ~/.config/seihou
    echo '{ license = "MIT", `haskell.ghc` = "9.12.2" }' > ~/.config/seihou/config.dhall

Create a local config:

    mkdir -p .seihou
    echo '{ `project.name` = "my-local-app" }' > .seihou/config.dhall

Check explain output:

    cabal run seihou -- vars haskell-base --explain

Expected output includes:

    project.name = "my-local-app"  (from local config)
    license = "MIT"  (from global config)

Override with CLI:

    cabal run seihou -- vars haskell-base --explain --var project.name=cli-app

Expected output includes:

    project.name = "cli-app"  (from --set flag)
    license = "MIT"  (from global config)


## Validation and Acceptance

After implementation, the following must hold:

1. `cabal test all` passes with all existing tests plus new config-layer tests.

2. The `resolveVariables` function accepts six sources and resolves in the correct precedence order: CLI > env > local config > namespace config > global config > module default.

3. Running `seihou vars <module> --explain` with a global config file shows values sourced from "from global config". With a local config file, values show "from local config" and override matching global values.

4. Missing config files are silently ignored — `seihou run <module>` works identically to before when no config files exist.

5. Invalid Dhall in a config file produces a clear error message rather than silently proceeding.

6. `nix fmt` produces no changes.


## Idempotence and Recovery

All changes are additive: new modules (`Dhall.Config`, `ConfigReaderInterp`, `ConfigReaderPure`), new tests, and modifications to existing functions (`resolveVariables`, `resolveComposedVariables`, `resolveWithPrompts`, `handleRun`, `handleVars`). The existing `resolveComposedVariables` signature changes, but all callers are updated simultaneously. Any edit can be reverted with `git checkout -- <file>`. The config file reading is best-effort (missing files return empty maps), so running the tool without config files behaves identically to the current behavior.


## Interfaces and Dependencies

No new external dependencies. Config file evaluation uses the existing `dhall` library (already in `seihou-core.cabal`). File path resolution uses `directory`'s `getXdgDirectory` (already a dependency). The `effectful-core` library is already used throughout.

New modules and their key exports:

In `seihou-core/src/Seihou/Dhall/Config.hs`:

    evalConfigFile :: FilePath -> IO (Map Text Text)
    evalConfigFileIfExists :: FilePath -> IO (Map Text Text)

In `seihou-core/src/Seihou/Effect/ConfigReaderInterp.hs`:

    runConfigReader :: (IOE :> es) => Eff (ConfigReader : es) a -> Eff es a

In `seihou-core/src/Seihou/Effect/ConfigReaderPure.hs`:

    runConfigReaderPure ::
      Map Text Text ->             -- local config
      Map Text (Map Text Text) ->  -- namespace configs (keyed by namespace name)
      Map Text Text ->             -- global config
      Eff (ConfigReader : es) a ->
      Eff es a

Modified signatures:

In `seihou-core/src/Seihou/Core/Variable.hs`:

    resolveVariables ::
      [VarDecl] ->
      Map VarName Text ->  -- CLI overrides
      Map Text Text ->     -- Environment variables
      Map VarName Text ->  -- Local config
      Map VarName Text ->  -- Namespace config
      Map VarName Text ->  -- Global config
      Either [VarError] (Map VarName ResolvedVar)

In `seihou-core/src/Seihou/Composition/Resolve.hs`:

    resolveComposedVariables ::
      [(Module, FilePath)] ->
      Map VarName Text ->  -- CLI overrides
      Map Text Text ->     -- Environment variables
      Map VarName Text ->  -- Local config
      Map VarName Text ->  -- Namespace config
      Map VarName Text ->  -- Global config
      Either [VarError] (Map ModuleName (Map VarName ResolvedVar))

    resolveWithPrompts ::
      (Console :> es) =>
      [(Module, FilePath)] ->
      Map VarName Text ->  -- CLI overrides
      Map Text Text ->     -- Environment variables
      Map VarName Text ->  -- Local config
      Map VarName Text ->  -- Namespace config
      Map VarName Text ->  -- Global config
      Eff es (Either [VarError] (Map ModuleName (Map VarName ResolvedVar)))

In `seihou-cli/src/Seihou/CLI/Commands.hs`:

    data RunOpts = RunOpts
      { ...existing fields...
      , runNamespace :: Maybe Text   -- optional --namespace flag
      }

    data VarsOpts = VarsOpts
      { ...existing fields...
      , varsNamespace :: Maybe Text  -- optional --namespace flag
      }
