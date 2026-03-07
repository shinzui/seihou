# Add Context-Aware Variable Resolution

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

Users often work across multiple environments — a "work" context and a "personal" context — where
the same variable (e.g., `user.email`, `git.author`, `license`) should resolve to different values
depending on which context is active. Today, the only scoping mechanism is **namespaces**, which are
derived from module names and scope config by module family (e.g., `haskell-base` → namespace
`haskell`). Namespaces don't capture the cross-cutting concern of "who am I right now."

After this change, a user can:

1. Define named **contexts** (e.g., `work`, `personal`) in the global config directory, each with
   its own variable values.
2. Set a **default context** globally so it applies without any flags.
3. Set a **project-level context** in `.seihou/context` so the project always uses the right one.
4. Override the context per-invocation with `--context <name>` (or `-c <name>`) on `run`, `vars`,
   and `config` commands.
5. See the active context and its source in `vars --explain` provenance output.
6. Manage context configs with `seihou config set/get/list --context <name>`.

Context config slots into the variable resolution precedence chain between namespace config and
global config, giving it higher priority than global defaults but lower than namespace-specific
or local project overrides.

**New 8-level precedence chain:**

1. CLI flags (`--var key=value`)
2. Environment variables (`SEIHOU_VAR_*`)
3. Local project config (`.seihou/config.dhall`)
4. Namespace config (`~/.config/seihou/namespaces/<ns>/config.dhall`)
5. **Context config** (`~/.config/seihou/contexts/<ctx>/config.dhall`) ← NEW
6. Global config (`~/.config/seihou/config.dhall`)
7. Module defaults
8. Interactive prompts


## Progress

### Milestone 1: Core types and context config reading
- [x] Add `FromContextConfig Text` constructor to `VarSource` in `Seihou.Core.Types` (2026-03-07)
- [x] Add `ScopeContext Text` constructor to `ConfigScope` in `Seihou.Core.Types` (2026-03-07)
- [x] Add `ReadContextConfig` operation to `ConfigReader` effect (2026-03-07)
- [x] Implement `ReadContextConfig` in `ConfigReaderInterp` (IO interpreter) (2026-03-07)
- [x] Implement `ReadContextConfig` in `ConfigReaderPure` (pure/test interpreter) (2026-03-07)
- [x] Add `ScopeContext` case to `ConfigWriterInterp.resolvePath` (2026-03-07)
- [x] Add context config tests in `ConfigReaderSpec` (2026-03-07)

### Milestone 2: Variable resolution with context layer
- [x] Add `contextConfig` parameter to `resolveVariables` in `Seihou.Core.Variable` (2026-03-07)
- [x] Insert context config lookup between namespace and global in the precedence chain (2026-03-07)
- [x] Update `formatExplain` to display `[context: <name>]` source (2026-03-07)
- [x] Update `diagnoseResolution` to accept and include context config keys (2026-03-07)
- [x] Add context resolution tests in `VariableSpec` (4 tests: resolve, lower than namespace, higher than global, formatExplain) (2026-03-07)
- [x] Update all existing test call sites (VariableSpec, ResolveSpec, CompositionSpec, GenerationSpec, ExecutionSpec, PromptSpec, ConfigReaderSpec) (2026-03-07)

### Milestone 5: Composition pipeline update (combined with M2)
- [x] Update `resolveComposedVariables` signature to accept context config (2026-03-07)
- [x] Update `resolveWithPrompts` signature to accept context config (2026-03-07)
- [x] Update all call sites in CLI handlers (temporarily wired with empty context) (2026-03-07)

### Milestone 3: Context resolution logic
- [x] Create `Seihou.Core.Context` module with `resolveContext` and `validateContextName` (2026-03-07)
- [x] Implement context resolution order: CLI flag → env var (`SEIHOU_CONTEXT`) → project file (`.seihou/context`) → global default (`~/.config/seihou/default-context`) (2026-03-07)
- [x] Add context name validation (same rules as namespace: no `..`, no `/`) (2026-03-07)
- [x] Add tests for context resolution (12 tests in ContextSpec) (2026-03-07)

### Milestone 4: CLI integration
- [x] Add `--context` / `-c` flag to `RunOpts` in `Commands.hs` (2026-03-07)
- [x] Add `--context` / `-c` flag to `VarsOpts` in `Commands.hs` (2026-03-07)
- [x] Add `--context` / `-c` flag to `ConfigOpts` in `Commands.hs` (2026-03-07)
- [x] Wire context into `handleRun` — resolve context, read context config, pass to resolution (2026-03-07)
- [x] Wire context into `handleVars` — same pattern as run (2026-03-07)
- [x] Wire context into `handleConfig` — allow `--context <name>` as a scope for set/get/list (2026-03-07)
- [x] Update `handleListEffective` to include context layer (2026-03-07)
- [x] Update `seihou init` to create `contexts/` directory (2026-03-07)

### Milestone 6: Integration tests and documentation
- [x] Add integration test: context overrides global config in composed resolution (2026-03-07)
- [x] Add integration test: context flows through multi-module composition (2026-03-07)
- [x] Update help text for `run`, `vars`, and `config` commands (included with M4 parser changes) (2026-03-07)
- [x] Verify `config list --effective` includes context layer (2026-03-07)


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Context config sits between namespace config and global config in precedence.
  Rationale: Context is a cross-cutting identity concern ("who am I") while namespace is a
  module-family concern ("what kind of project"). Local and namespace should still win over
  context since they are more specific. Context should win over global since global is the
  broadest scope.
  Date: 2026-03-07

- Decision: Context is resolved from four sources in order: `--context` CLI flag, `SEIHOU_CONTEXT`
  env var, `.seihou/context` file (plain text, single line), `~/.config/seihou/default-context`
  file (plain text, single line). No context is the default (empty string → skip context layer).
  Rationale: Mirrors the existing pattern where CLI overrides env overrides config. The project
  file `.seihou/context` allows teams to pin a context per repo. The global default-context file
  allows users to set a persistent default without modifying any Dhall files.
  Date: 2026-03-07

- Decision: Context configs live at `~/.config/seihou/contexts/<name>/config.dhall`, parallel
  to the existing `namespaces/<name>/config.dhall` pattern.
  Rationale: Consistent with the existing filesystem layout. Same Dhall format, same
  read/write mechanics.
  Date: 2026-03-07

- Decision: Use `-c` as the short flag for `--context` (not taken by any existing command).
  Rationale: Natural abbreviation, not conflicting with existing flags.
  Date: 2026-03-07

- Decision: Context config uses the same format as all other config scopes — a Dhall record of
  `Text` key-value pairs. No new schema or format.
  Rationale: Minimizes implementation surface. Users already know this format.
  Date: 2026-03-07

- Decision: Combined Milestones 2 and 5 into a single implementation step.
  Rationale: Updating `resolveVariables` signature (M2) breaks `resolveComposedVariables` and
  `resolveWithPrompts` (M5), which break CLI handlers. These must be updated atomically for
  the build to succeed.
  Date: 2026-03-07


## Outcomes & Retrospective

All 6 milestones complete. The implementation adds context-aware variable resolution with:

- New `FromContextConfig Text` / `ScopeContext Text` constructors in core types
- `ReadContextConfig` operation in the ConfigReader effect (IO + pure interpreters)
- Context config inserted between namespace and global in the 8-level precedence chain
- `Seihou.Core.Context` module with `resolveContext` (CLI flag → env → project file → global default)
- `--context` / `-c` flags on `run`, `vars`, and `config` commands
- `seihou init` creates `contexts/` directory
- `config list --effective` includes context layer
- 18 new tests across ContextSpec, VariableSpec, ResolveSpec, and ConfigReaderSpec

Milestones 2 and 5 were combined since updating `resolveVariables` required simultaneously updating `resolveComposedVariables`, `resolveWithPrompts`, and all call sites.


## Context and Orientation

### Current variable resolution system

The variable resolution pipeline is implemented in `seihou-core/src/Seihou/Core/Variable.hs`.
The function `resolveVariables` takes seven parameters:

```haskell
resolveVariables ::
  [VarDecl] ->
  Map VarName Text ->   -- CLI overrides
  Map Text Text ->       -- Environment variables
  Text ->                -- Namespace name
  Map VarName Text ->   -- Local config
  Map VarName Text ->   -- Namespace config
  Map VarName Text ->   -- Global config
  Either [VarError] (Map VarName ResolvedVar)
```

It walks each `VarDecl` through a 6-level precedence chain: CLI → env → local → namespace →
global → default. If nothing matches and the variable is required, it returns
`MissingRequiredVar`. Each resolved value is tagged with a `VarSource` for provenance tracking.

### Provenance types (in `seihou-core/src/Seihou/Core/Types.hs`)

```haskell
data VarSource
  = FromCLI
  | FromEnv Text
  | FromLocalConfig
  | FromNamespaceConfig Text
  | FromGlobalConfig
  | FromDefault
  | FromPrompt
```

### Config scopes (in `seihou-core/src/Seihou/Core/Types.hs`)

```haskell
data ConfigScope
  = ScopeLocal
  | ScopeNamespace Text
  | ScopeGlobal
```

### ConfigReader effect (`seihou-core/src/Seihou/Effect/ConfigReader.hs`)

Three operations: `ReadGlobalConfig`, `ReadLocalConfig`, `ReadNamespaceConfig Text`. Each
returns `Either ConfigError (Map Text Text)`.

**IO interpreter** (`seihou-core/src/Seihou/Effect/ConfigReaderInterp.hs`): Resolves paths
using XDG config directory. Missing files → empty map. Invalid Dhall → `ConfigParseError`.
Namespace names are validated to reject `..` and `/`.

**Pure interpreter** (`seihou-core/src/Seihou/Effect/ConfigReaderPure.hs`): Takes three scripted
maps (local, namespaces as `Map Text (Map Text Text)`, global). Used in tests.

### ConfigWriter effect (`seihou-core/src/Seihou/Effect/ConfigWriter.hs`)

Three operations: `WriteConfigValue scope key val`, `DeleteConfigValue scope key`,
`ListConfigValues scope`. The IO interpreter resolves paths identically to ConfigReader and
performs read-modify-write using `serializeConfig`.

### CLI commands (`seihou-cli/src/Seihou/CLI/Commands.hs`)

Relevant option types:
- `RunOpts`: has `runNamespace :: Maybe Text` — controls namespace override
- `VarsOpts`: has `varsNamespace :: Maybe Text`
- `ConfigOpts`: has `configGlobal :: Bool`, `configNamespace :: Maybe Text`

### Composition pipeline (`seihou-core/src/Seihou/Composition/Resolve.hs`)

`resolveComposedVariables` and `resolveWithPrompts` both accept the same config maps and
call `resolveVariables` per-module in topological order.

### CLI handlers

- `seihou-cli/src/Seihou/CLI/Run.hs` (`handleRun`): Reads all three config layers, calls
  `resolveWithPrompts`, then compiles and executes the plan.
- `seihou-cli/src/Seihou/CLI/Vars.hs` (`handleVars`): Same config reading pattern in
  `explainMode`.
- `seihou-cli/src/Seihou/CLI/Config.hs` (`handleConfig`): Maps `--global`/`--namespace` to
  `ConfigScope`, delegates to `writeConfigValue`/`deleteConfigValue`/`listConfigValues`.
- `seihou-cli/src/Seihou/CLI/Init.hs` (`handleInit`): Creates `~/.config/seihou/` with
  subdirectories `modules/`, `installed/`, `namespaces/`. Need to add `contexts/`.

### Key filesystem paths

| What | Path |
|---|---|
| Global config | `~/.config/seihou/config.dhall` |
| Namespace config | `~/.config/seihou/namespaces/<ns>/config.dhall` |
| **Context config** (new) | `~/.config/seihou/contexts/<ctx>/config.dhall` |
| **Default context** (new) | `~/.config/seihou/default-context` |
| **Project context** (new) | `.seihou/context` |
| Local project config | `.seihou/config.dhall` |

### Test infrastructure

- `seihou-core/test/Seihou/Core/VariableSpec.hs` — Unit tests for `resolveVariables`
- `seihou-core/test/Seihou/Effect/ConfigReaderSpec.hs` — Tests for pure and IO config reading
- `seihou-core/test/Seihou/Integration/ExecutionSpec.hs` — End-to-end generation tests
- Test framework: `tasty` + `tasty-hspec`, `hspec`


## Plan of Work

### Milestone 1: Core types and context config reading

Add the `FromContextConfig Text` constructor to `VarSource` in
`seihou-core/src/Seihou/Core/Types.hs` (after `FromNamespaceConfig Text`). Add the
`ScopeContext Text` constructor to `ConfigScope` (after `ScopeNamespace Text`).

Add a `ReadContextConfig :: Text -> ConfigReader m (Either ConfigError (Map Text Text))`
operation to the `ConfigReader` effect in `seihou-core/src/Seihou/Effect/ConfigReader.hs`,
along with its convenience function `readContextConfig`.

In the IO interpreter (`seihou-core/src/Seihou/Effect/ConfigReaderInterp.hs`), handle
`ReadContextConfig ctx` by resolving to `~/.config/seihou/contexts/<ctx>/config.dhall`,
applying the same validation as namespaces (reject `..` and `/`), and treating missing
files as empty maps.

In the pure interpreter (`seihou-core/src/Seihou/Effect/ConfigReaderPure.hs`), extend
`runConfigReaderPure` to accept a fourth parameter `Map Text (Map Text Text)` for context
configs (same shape as namespace configs). Handle `ReadContextConfig ctx` by looking up
the context name in this map.

In `seihou-core/src/Seihou/Effect/ConfigWriterInterp.hs`, add a case for
`ScopeContext ctx` in `resolvePath` that resolves to
`~/.config/seihou/contexts/<ctx>/config.dhall`.

Add tests in `seihou-core/test/Seihou/Effect/ConfigReaderSpec.hs` for the pure interpreter
returning context config, and for the IO interpreter validating context names.

**Acceptance:** `cabal build all` succeeds. New tests pass.

### Milestone 2: Variable resolution with context layer

In `seihou-core/src/Seihou/Core/Variable.hs`, add a `Map VarName Text` parameter for
context config and a `Text` parameter for context name to `resolveVariables`. Insert a new
lookup step between the namespace config and global config lookups in `resolveOne`, using
`lookupConfig name ty ctxConfig (FromContextConfig contextName)`.

Update `formatExplain` in the same file to render `FromContextConfig ctx` as
`[context: <ctx>]`.

Update `diagnoseResolution` to accept the context config map as a parameter and include its
keys in the `allConfigKeys` set.

Update all existing call sites of `resolveVariables` (in `Seihou.Composition.Resolve`).

Add tests in `seihou-core/test/Seihou/Core/VariableSpec.hs` verifying:
- Context config resolves when namespace and local don't have the variable
- Context config is lower priority than namespace config
- Context config is higher priority than global config
- `formatExplain` shows `[context: work]`

**Acceptance:** `cabal build all` succeeds. All existing + new tests pass.

### Milestone 3: Context resolution logic

Create `seihou-core/src/Seihou/Core/Context.hs` exporting:

```haskell
resolveContext ::
  Maybe Text ->    -- CLI flag (--context)
  Map Text Text -> -- Environment variables (look for SEIHOU_CONTEXT)
  IO (Maybe Text)  -- Resolved context name, Nothing = no context active
```

Resolution order:
1. If CLI flag is `Just ctx`, return `Just ctx`
2. If `SEIHOU_CONTEXT` is set in env vars, return `Just` its value
3. If `.seihou/context` exists and is non-empty, return `Just` its contents (trimmed)
4. If `~/.config/seihou/default-context` exists and is non-empty, return `Just` its contents
5. Otherwise return `Nothing`

Validate context names: reject empty, reject containing `..` or `/`.

Add this module to `seihou-core.cabal`'s `exposed-modules`.

Add tests for each resolution source and precedence.

**Acceptance:** `cabal build all` succeeds. New tests pass.

### Milestone 4: CLI integration

In `seihou-cli/src/Seihou/CLI/Commands.hs`:
- Add `runContext :: Maybe Text` field to `RunOpts`
- Add `varsContext :: Maybe Text` field to `VarsOpts`
- Add `configContext :: Maybe Text` field to `ConfigOpts`
- Add `--context` / `-c` parser to `runParser`, `varsParser`, `configParser`

In `seihou-cli/src/Seihou/CLI/Run.hs` (`handleRun`):
- Call `resolveContext` with `runOpts.runContext` and `envVars`
- Read context config via `readContextConfig` (if context is active)
- Pass context config to `resolveWithPrompts`

In `seihou-cli/src/Seihou/CLI/Vars.hs` (`handleVars`):
- Same pattern: resolve context, read context config, pass to resolution

In `seihou-cli/src/Seihou/CLI/Config.hs`:
- Update `resolveScope` to handle `configContext` → `ScopeContext ctx`
- Update `scopeLabel` with `ScopeContext ctx -> "context " <> ctx`
- Update `handleListEffective` to include the context layer

In `seihou-cli/src/Seihou/CLI/Init.hs` (`handleInit`):
- Add `createDirectoryIfMissing True (base </> "contexts")` alongside `namespaces/`

**Acceptance:** `cabal build all` succeeds. CLI `--help` shows `--context` flag. Manual test:
`seihou config set user.email work@example.com --context work` creates the context config file.

### Milestone 5: Composition pipeline update

In `seihou-core/src/Seihou/Composition/Resolve.hs`:
- Add context config parameter (`Map VarName Text`) and context name (`Text`) to
  `resolveComposedVariables`
- Add same parameters to `resolveWithPrompts`
- Pass through to `resolveVariables` calls

Update all call sites in `handleRun` and `handleVars` (already partially done in M4).

**Acceptance:** `cabal build all` succeeds. All tests pass.

### Milestone 6: Integration tests and documentation

Add integration tests that exercise the full pipeline with context:
- A test where context config provides `user.email` and global config has a different one,
  verifying context wins
- A test with `.seihou/context` file
- A test verifying `--context` flag overrides project file

Update CLI help text in `Commands.hs` footer docs to mention contexts.

Verify `seihou config list --effective --context work` shows the context layer.

**Acceptance:** All tests pass. `cabal test all` clean.


## Concrete Steps

All commands run from the repository root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

### Build and test (run after each milestone)

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
cabal build all
cabal test all
```

Expected output includes `All N tests passed` (test count increases as new tests are added).

### Manual verification (after Milestone 4)

```bash
# Initialize (creates contexts/ directory)
seihou init

# Set a context config value
seihou config set user.email work@example.com --context work
seihou config set user.email personal@example.com --context personal

# Verify
seihou config list --context work
# Expected: work config:
#   user.email = work@example.com

# Set project context
echo "work" > .seihou/context

# Check effective config
seihou config list --effective
# Expected: shows user.email = work@example.com [context: work]

# Override with flag
seihou vars some-module --explain --context personal
# Expected: user.email resolved from [context: personal]
```


## Validation and Acceptance

1. **Type-level:** `cabal build all` compiles without errors or warnings
2. **Unit tests:** New tests in `VariableSpec`, `ConfigReaderSpec`, and a new `ContextSpec` all pass
3. **Integration:** `cabal test all` passes with no regressions
4. **Manual smoke test:** The commands in the "Concrete Steps" section produce the expected output
5. **Provenance:** `seihou vars <module> --explain --context work` shows `[context: work]` for variables resolved from context config
6. **Precedence:** Setting the same variable in context and global config, context wins. Setting it in namespace and context, namespace wins.
7. **No context:** When no context is active (no flag, no env, no project file, no default), behavior is identical to before this change — full backward compatibility.


## Idempotence and Recovery

- All file edits are additive (new constructors, new parameters, new function). No existing
  behavior is removed.
- `seihou init` is already idempotent — adding `contexts/` follows the same pattern.
- Context config files are created on first `config set --context <name>` — no manual setup
  required.
- If a milestone partially fails, the codebase may not compile but `git stash` or `git checkout`
  recovers cleanly.
- The pure test interpreters make it safe to iterate on logic without filesystem side effects.


## Interfaces and Dependencies

### New module

In `seihou-core/src/Seihou/Core/Context.hs`, define:

```haskell
resolveContext :: Maybe Text -> Map Text Text -> IO (Maybe Text)
validateContextName :: Text -> Either Text Text
```

### Modified types in `seihou-core/src/Seihou/Core/Types.hs`

```haskell
data VarSource
  = FromCLI
  | FromEnv Text
  | FromLocalConfig
  | FromNamespaceConfig Text
  | FromContextConfig Text       -- NEW
  | FromGlobalConfig
  | FromDefault
  | FromPrompt

data ConfigScope
  = ScopeLocal
  | ScopeNamespace Text
  | ScopeContext Text            -- NEW
  | ScopeGlobal
```

### Modified effect in `seihou-core/src/Seihou/Effect/ConfigReader.hs`

```haskell
data ConfigReader :: Effect where
  ReadGlobalConfig :: ConfigReader m (Either ConfigError (Map Text Text))
  ReadLocalConfig :: ConfigReader m (Either ConfigError (Map Text Text))
  ReadNamespaceConfig :: Text -> ConfigReader m (Either ConfigError (Map Text Text))
  ReadContextConfig :: Text -> ConfigReader m (Either ConfigError (Map Text Text))  -- NEW
```

### Modified function in `seihou-core/src/Seihou/Core/Variable.hs`

```haskell
resolveVariables ::
  [VarDecl] ->
  Map VarName Text ->   -- CLI overrides
  Map Text Text ->       -- Environment variables
  Text ->                -- Namespace name
  Text ->                -- Context name (new)
  Map VarName Text ->   -- Local config
  Map VarName Text ->   -- Namespace config
  Map VarName Text ->   -- Context config (new)
  Map VarName Text ->   -- Global config
  Either [VarError] (Map VarName ResolvedVar)
```

### Modified functions in `seihou-core/src/Seihou/Composition/Resolve.hs`

```haskell
resolveComposedVariables ::
  [(Module, FilePath)] ->
  Map VarName Text ->        -- CLI overrides
  Map Text Text ->           -- Environment variables
  Text ->                    -- Namespace
  Text ->                    -- Context name (new)
  Map VarName Text ->        -- Local config
  Map VarName Text ->        -- Namespace config
  Map VarName Text ->        -- Context config (new)
  Map VarName Text ->        -- Global config
  Either [VarError] (Map ModuleName (Map VarName ResolvedVar))

resolveWithPrompts ::
  (Console :> es) =>
  [(Module, FilePath)] ->
  Map VarName Text ->
  Map Text Text ->
  Text ->                    -- Namespace
  Text ->                    -- Context name (new)
  Map VarName Text ->
  Map VarName Text ->
  Map VarName Text ->        -- Context config (new)
  Map VarName Text ->
  Eff es (Either [VarError] (Map ModuleName (Map VarName ResolvedVar)))
```

### Dependencies

No new external dependencies. Uses only existing libraries:
- `effectful` (effect system)
- `optparse-applicative` (CLI parsing)
- `containers` (Map)
- `text`
- `directory` (XDG paths, file existence checks)
- `dhall` (config file evaluation, via existing `Seihou.Dhall.Config`)
