---
slug: config-writing
title: "Add Config Writing Command"
kind: exec-plan
created_at: 2026-03-04T00:17:46Z
---


# Add Config Writing Command

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

Currently, Seihou can read variable defaults from config files (local, namespace, and global) but there is no way to write those files from the CLI. Users must manually create and edit Dhall config files, which requires knowledge of Dhall syntax and the correct file paths. After this change, users will be able to set, list, and remove config values directly from the command line:

    seihou config set project.name my-app
    seihou config set license MIT --global
    seihou config set haskell.ghc 9.12.2 --namespace haskell
    seihou config list
    seihou config unset license --global

This eliminates the need to hand-edit Dhall files and makes the config layer a first-class part of the CLI workflow. The user can verify the change by running `seihou config set project.name my-app` followed by `seihou config list` and seeing the value appear, or by running `seihou vars <module> --explain` and seeing the value sourced "from local config".


## Progress

- [x] M1-1: Add `serializeConfig` to `Seihou.Dhall.Config` (2026-03-03)
- [x] M1-2: Add serialization tests to `ConfigSpec` (2026-03-03)
- [x] M1-3: Build and test — 448 tests pass (2026-03-03)
- [x] M2-1: Create `ConfigWriter` effect definition (2026-03-03)
- [x] M2-2: Create `ConfigWriterInterp` (IO interpreter) (2026-03-03)
- [x] M2-3: Create `ConfigWriterPure` (pure interpreter) (2026-03-03)
- [x] M2-4: Register new modules in `seihou-core.cabal` (2026-03-03)
- [x] M2-5: Add `ConfigWriterSpec` tests — 11 tests (2026-03-03)
- [x] M2-6: Register test module in test `Main.hs` (2026-03-03)
- [x] M2-7: Build and test — 458 tests pass (2026-03-03)
- [x] M3-1: Add `ConfigScope` type to `Core/Types.hs` — already done in M2 (2026-03-03)
- [x] M3-2: Add `Config ConfigOpts` to `Command` type and parser in `Commands.hs` (2026-03-03)
- [x] M3-3: Create `seihou-cli/src/Seihou/CLI/Config.hs` handler (2026-03-03)
- [x] M3-4: Register CLI module in `seihou-cli.cabal` (2026-03-03)
- [x] M3-5: Wire command dispatch in `Main.hs` (2026-03-03)
- [x] M3-6: Build and test — 458 tests pass (2026-03-03)
- [x] M3-7: Manual verification — set, list, get, unset all work across local/global/namespace scopes (2026-03-03)


## Surprises & Discoveries

- The `ConfigWriterPure` `reinterpret` handler requires the `EffectHandler` type alias pattern (with a fresh type variable `es'` and `State ConfigWriterState :> es'` constraint), not a concrete handler signature. The same pattern is used in `LoggerPure` and `ManifestStorePure`. (2026-03-03)
- The `ConfigWriter` type must be explicitly imported in the spec file for use in the `Eff '[ConfigWriter]` type annotation. The convenience helpers (`writeConfigValue`, etc.) alone are not sufficient. (2026-03-03)
- The default global config written by `seihou init` includes comments above `{=}`. `evalConfigFile` was only stripping the expression itself with `T.strip`, so comments caused `toMap` to fail on the empty record. Fixed by adding `stripDhallComments` to remove `--` comment lines before the empty-record check. (2026-03-03)


## Decision Log

- Decision: Use a simple hand-written Dhall serializer rather than the Dhall library's pretty-printer.
  Rationale: Config files are flat records of text values (`Map Text Text`). The Dhall library's AST construction would require building `RecordLit` nodes with `makeRecordField` and then pretty-printing, which pulls in a complex dependency chain. A hand-written serializer for the simple case of `{ key = "value", ... }` is under 20 lines, easily testable, and produces human-readable output that matches the format already shown in the default config.dhall comments.
  Date: 2026-03-03

- Decision: Config file format uses one key-value pair per line with trailing-comma style for readability.
  Rationale: The output should be easy for humans to read and edit. A format like `{ \`project.name\` = "my-app"\n, license = "MIT"\n}` (Dhall's trailing-comma convention) is idiomatic and produces clean diffs when values are added or removed. The empty config case serializes as `{=}`.
  Date: 2026-03-03

- Decision: The `config` command uses sub-subcommands (`set`, `list`, `get`, `unset`) rather than flags.
  Rationale: Each action has different argument shapes: `set` takes KEY VALUE, `get` takes KEY, `list` takes no positional args, `unset` takes KEY. Sub-subcommands (`seihou config set KEY VALUE`) model this naturally with optparse-applicative and match the UX convention of tools like `git config`.
  Date: 2026-03-03

- Decision: Default scope is `local` (`.seihou/config.dhall`).
  Rationale: Most config values are project-specific. Setting the default to local means `seihou config set project.name my-app` does the right thing without extra flags. Users opt into broader scopes with `--global` or `--namespace NS`. This matches the mental model of git config, where `--local` is the default.
  Date: 2026-03-03

- Decision: The `ConfigWriter` effect uses a read-modify-write pattern internally rather than exposing separate read/write operations.
  Rationale: Writing a config value requires reading the current file, merging the new value, and writing the result. Exposing this as a single `WriteConfigValue` operation keeps the effect interface simple and prevents callers from accidentally writing incomplete maps. The interpreter handles the read-modify-write atomically.
  Date: 2026-03-03

- Decision: The `config list` subcommand shows all three scopes merged with provenance annotations rather than a single scope.
  Rationale: The primary question users ask is "what values will be used and where do they come from?" — which is exactly what merged-with-provenance answers. Single-scope listing is available via `--global` or `--namespace NS` flags for when the user wants to see or edit one scope specifically.
  Date: 2026-03-03

- Decision: Backtick-escape all keys in serialized Dhall.
  Rationale: Variable names in Seihou typically contain dots (e.g., `project.name`, `haskell.ghc`). Dots are not valid in unquoted Dhall labels. Rather than implementing a complex "escape only when needed" rule, always backtick-escaping is safe, consistent, and produces valid Dhall. The Dhall evaluator handles backtick-escaped labels correctly (the existing config.dhall comment examples already show this style).
  Date: 2026-03-03


## Outcomes & Retrospective

All three milestones completed successfully:

- **M1**: Dhall serialization (`serializeConfig`, `escapeDhallText`) with 9 round-trip tests. Commit `e79b8e7`.
- **M2**: ConfigWriter effect with IO and pure interpreters, ConfigScope type, 11 unit tests. Commit `814e1b0`.
- **M3**: CLI `seihou config` command with `set`, `get`, `list`, `unset` subcommands and scope flags. Also fixed a pre-existing bug where the global config file's comments prevented parsing empty records.

Total test count: 458 (up from 439 before this plan). All manual acceptance criteria verified: set/get/list/unset work across local, global, and namespace scopes.

Lesson learned: The `evalConfigFile` empty-record detection needed to strip Dhall comments before comparing, since `seihou init` writes comments into the default global config.


## Context and Orientation

### Config file system

Seihou uses three layers of Dhall config files to provide variable defaults. Each file is a Dhall record that evaluates to a flat map of text key-value pairs. The three layers, in resolution priority order (highest first among configs, but below CLI and env vars):

1. **Local config** at `.seihou/config.dhall` relative to the current working directory. Contains project-specific defaults.
2. **Namespace config** at `~/.config/seihou/namespaces/<ns>/config.dhall`. Contains defaults for a family of related modules (e.g., all "haskell-*" modules share the "haskell" namespace).
3. **Global config** at `~/.config/seihou/config.dhall`. Contains system-wide defaults.

The `seihou init` command creates the global config with an empty record `{=}` and the namespaces directory. Local configs and namespace configs do not exist until the user creates them. Missing files are silently treated as empty maps by the ConfigReader.

### Dhall config format

Config files are plain Dhall records of text values:

    { `project.name` = "my-app", license = "MIT" }

Keys containing dots or special characters must be backtick-escaped. The Dhall `toMap` operator converts this to a list of `{mapKey, mapValue}` entries, which is how `seihou-core/src/Seihou/Dhall/Config.hs` decodes them via `evalConfigFile`. An empty config is the literal `{=}`.

There is currently no serialization function — `Seihou.Dhall.Config` only reads configs.

### Variable resolution chain

When `seihou run` or `seihou vars --explain` executes, variables are resolved by `resolveVariables` in `seihou-core/src/Seihou/Core/Variable.hs` using a six-layer priority chain: CLI overrides > environment variables > local config > namespace config > global config > module defaults. Each resolved value records its source as a `VarSource` variant (e.g., `FromLocalConfig`, `FromGlobalConfig`, `FromNamespaceConfig "haskell"`), which is displayed by the `--explain` flag.

### Effect system pattern

Each effectful capability follows a three-file pattern:

- **Effect definition** (`seihou-core/src/Seihou/Effect/<Name>.hs`): declares the effect type using `effectful`'s Dynamic dispatch and exports convenience helpers that wrap `send`.
- **IO interpreter** (`seihou-core/src/Seihou/Effect/<Name>Interp.hs`): provides the real implementation using `interpret` from `Effectful.Dispatch.Dynamic`.
- **Pure interpreter** (`seihou-core/src/Seihou/Effect/<Name>Pure.hs`): provides a test-friendly implementation using `reinterpret` with `State` or `interpret` with scripted data.

All three are registered as `exposed-modules` in `seihou-core/seihou-core.cabal`.

### CLI command structure

Commands are defined in `seihou-cli/src/Seihou/CLI/Commands.hs` as a `Command` sum type. Each variant carries an options record (e.g., `Run RunOpts`). The parser uses `subparser` with optparse-applicative. The main dispatcher in `seihou-cli/src/Main.hs` pattern-matches on the command and calls the corresponding handler from its dedicated module (e.g., `Seihou.CLI.Run`, `Seihou.CLI.Init`).

New CLI modules are registered in `seihou-cli/seihou-cli.cabal` under `other-modules`.


## Plan of Work

### Milestone 1: Dhall config serialization

This milestone adds a `serializeConfig` function to `seihou-core/src/Seihou/Dhall/Config.hs` that converts a `Map Text Text` back to valid Dhall source text. At the end of this milestone, the serializer exists with tests proving round-trip correctness (serialize then evaluate returns the original map). No effect or CLI changes yet.

In `seihou-core/src/Seihou/Dhall/Config.hs`, add a new exported function `serializeConfig :: Map Text Text -> Text`. The function handles two cases: if the map is empty, return `"{=}\n"`; otherwise, produce a multi-line Dhall record with one entry per line. Each key is backtick-escaped and each value is a Dhall text literal (with backslashes and double-quotes escaped). The format is:

    { `key1` = "value1"
    , `key2` = "value2"
    }

This uses Dhall's trailing-comma style, which produces clean diffs when entries are added or removed.

Also add a helper `escapeDhallText :: Text -> Text` that escapes backslashes and double-quotes inside a Dhall text literal.

In `seihou-core/test/Seihou/Dhall/ConfigSpec.hs`, add tests for `serializeConfig`: empty map produces `{=}`, single entry produces valid Dhall, multiple entries produce valid Dhall, round-trip (serialize then evalConfigFile returns original map), and keys with dots are properly backtick-escaped.


### Milestone 2: ConfigWriter effect and interpreters

This milestone creates the `ConfigWriter` effect with IO and pure interpreters, following the existing three-file pattern. At the end, the effect exists with tests covering write, delete, and error cases. The IO interpreter performs read-modify-write on Dhall config files. The pure interpreter uses in-memory state for testing.

Create three new files:

`seihou-core/src/Seihou/Effect/ConfigWriter.hs` defines the effect with three operations: `WriteConfigValue` takes a scope, key, and value and writes it to the appropriate config file. `DeleteConfigValue` takes a scope and key and removes it. `ListConfigValues` takes a scope and returns the current values. The scope is represented by the `ConfigScope` type (added in M3 but defined here for the effect to reference — actually, define it in `Core/Types.hs` as part of this milestone since the effect needs it).

`seihou-core/src/Seihou/Effect/ConfigWriterInterp.hs` provides the IO interpreter. For write: resolve the file path from the scope, read the existing config (or empty map if file missing), insert the key-value pair, serialize with `serializeConfig`, create parent directories if needed, and write the file. For delete: same read-modify-write but with `Map.delete`. For list: read and return the config map. Path resolution reuses the same logic as `ConfigReaderInterp` (XDG config directory for global, cwd for local, namespaces subdirectory for namespace).

`seihou-core/src/Seihou/Effect/ConfigWriterPure.hs` provides a pure interpreter using `State` on a record of three maps (local, namespaces map-of-maps, global) — mirroring the `ConfigReaderPure` pattern but mutable.

Register all three in `seihou-core.cabal` under `exposed-modules`.

Create `seihou-core/test/Seihou/Effect/ConfigWriterSpec.hs` with tests: write a value then list sees it, write overwrites existing value, delete removes a value, delete nonexistent key is no-op, write to namespace scope works, operations across scopes are independent. Register in `seihou-core.cabal` test `other-modules` and wire into `test/Main.hs`.


### Milestone 3: CLI config command

This milestone adds the `seihou config` command with `set`, `list`, `get`, and `unset` subcommands. At the end, the full CLI workflow is available: set a value, list all values, get a specific value, unset a value, and verify that set values appear in `seihou vars --explain` output.

Add `ConfigScope` to `seihou-core/src/Seihou/Core/Types.hs` if not already added in M2. The type has three constructors: `ScopeLocal`, `ScopeNamespace Text`, and `ScopeGlobal`.

In `seihou-cli/src/Seihou/CLI/Commands.hs`, add `Config ConfigOpts` to the `Command` type. Define `ConfigOpts` with a `ConfigAction` field. `ConfigAction` is a sum type: `ConfigSet Text Text` (key and value), `ConfigGet Text` (key), `ConfigUnset Text` (key), and `ConfigList`. Add scope flags shared across all actions: `--global` (flag), `--namespace NS` (optional text). When neither is given, default to local scope. Add the `config` subcommand to the `commandParser` with sub-subcommands for `set`, `list`, `get`, and `unset`.

Create `seihou-cli/src/Seihou/CLI/Config.hs` with `handleConfig :: ConfigOpts -> IO ()`. The handler dispatches on the action:

- `ConfigSet key value`: Run `ConfigWriter` effect to write the value at the resolved scope. Print confirmation.
- `ConfigGet key`: Run `ConfigReader` to read the appropriate scope's config. Look up the key and print the value, or print "not set" if absent.
- `ConfigList`: When a specific scope is given (`--global` or `--namespace`), read that scope and print its entries. When no scope flag is given, read all three scopes and print a merged view with provenance annotations showing which scope each value comes from.
- `ConfigUnset key`: Run `ConfigWriter` to delete the key. Print confirmation or "not found" if the key wasn't set.

Register `Seihou.CLI.Config` in `seihou-cli/seihou-cli.cabal`. Wire the dispatch in `seihou-cli/src/Main.hs`.

The handler uses `logIO LogNormal (logError ...)` for errors (following the pattern established in the Logger plans) and `TIO.putStrLn` for user-facing output.


## Concrete Steps

### Milestone 1

**Working directory**: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

**Step 1**: Edit `seihou-core/src/Seihou/Dhall/Config.hs`. Add `serializeConfig` and `escapeDhallText` to the export list. Add the function definitions.

**Step 2**: Edit `seihou-core/test/Seihou/Dhall/ConfigSpec.hs`. Add tests for `serializeConfig`: empty map, single entry, multiple entries, round-trip, dotted keys.

**Step 3**: Build and test:

    cabal build all
    cabal test all

Expected: all tests pass (439 existing + new serialization tests).

### Milestone 2

**Step 4**: Edit `seihou-core/src/Seihou/Core/Types.hs`. Add `ConfigScope` type and export.

**Step 5**: Create `seihou-core/src/Seihou/Effect/ConfigWriter.hs`. Define the effect and helpers.

**Step 6**: Create `seihou-core/src/Seihou/Effect/ConfigWriterInterp.hs`. Implement the IO interpreter.

**Step 7**: Create `seihou-core/src/Seihou/Effect/ConfigWriterPure.hs`. Implement the pure interpreter.

**Step 8**: Edit `seihou-core/seihou-core.cabal`. Add the three new modules to `exposed-modules`.

**Step 9**: Create `seihou-core/test/Seihou/Effect/ConfigWriterSpec.hs`. Add tests.

**Step 10**: Edit `seihou-core/seihou-core.cabal` test section. Add `Seihou.Effect.ConfigWriterSpec` to `other-modules`.

**Step 11**: Edit `seihou-core/test/Main.hs`. Import `ConfigWriterSpec`, bind tests, add to `testGroup`.

**Step 12**: Build and test:

    cabal build all
    cabal test all

Expected: all tests pass.

### Milestone 3

**Step 13**: Edit `seihou-cli/src/Seihou/CLI/Commands.hs`. Add `Config ConfigOpts` to `Command`, define `ConfigOpts` and `ConfigAction` types, add parser.

**Step 14**: Create `seihou-cli/src/Seihou/CLI/Config.hs`. Implement `handleConfig`.

**Step 15**: Edit `seihou-cli/seihou-cli.cabal`. Add `Seihou.CLI.Config` to `other-modules`.

**Step 16**: Edit `seihou-cli/src/Main.hs`. Add import and dispatch case.

**Step 17**: Build and test:

    cabal build all
    cabal test all

**Step 18**: Manual verification:

    seihou config set project.name my-app
    # Expected: "Set project.name = my-app in local config"

    seihou config list
    # Expected:
    # Local (.seihou/config.dhall):
    #   project.name = my-app

    seihou config get project.name
    # Expected: my-app

    seihou config set license MIT --global
    # Expected: "Set license = MIT in global config"

    seihou config list
    # Expected: shows both local and global entries with scope labels

    seihou config unset project.name
    # Expected: "Removed project.name from local config"

    seihou config list
    # Expected: only global license entry remains


## Validation and Acceptance

### Automated

    cabal test all

All existing tests plus new tests pass. New tests cover:

- `serializeConfig` round-trip: serialize a map, write to temp file, evaluate with `evalConfigFile`, compare to original.
- `serializeConfig` empty map: produces `{=}`.
- `serializeConfig` escaping: values with double-quotes and backslashes are properly escaped.
- `ConfigWriter` pure: write/list/delete operations on all three scopes.
- `ConfigWriter` pure: write overwrites existing value.
- `ConfigWriter` pure: delete on nonexistent key is no-op.

### Manual acceptance criteria

1. **Set and retrieve**: Run `seihou config set project.name my-app` then `seihou config get project.name`. Output is `my-app`.

2. **Global scope**: Run `seihou config set license MIT --global` then `seihou config list --global`. Output includes `license = MIT`.

3. **Namespace scope**: Run `seihou config set haskell.ghc 9.12.2 --namespace haskell` then `seihou config list --namespace haskell`. Output includes `haskell.ghc = 9.12.2`.

4. **Unset**: Run `seihou config set foo bar` then `seihou config unset foo` then `seihou config get foo`. Output is "not set".

5. **Integration with vars**: Run `seihou config set project.name my-app --global`, then `seihou vars <some-module> --explain --var project.name=override`. The explain output shows `project.name` sourced "from --set flag" (CLI overrides config). Remove the `--var` override and re-run: now it should show "from global config".

6. **All tests pass**: `cabal test all` shows all tests passing.


## Idempotence and Recovery

All steps are safe to repeat. Writing a config value overwrites the previous value for that key, leaving other keys unchanged. The serializer produces deterministic output (keys sorted alphabetically), so writing the same value twice produces identical files. Deleting a nonexistent key is a no-op. If a config file does not exist, writing creates it along with any necessary parent directories. If a milestone fails partway through, the prior milestones' commits are independently valid.


## Interfaces and Dependencies

### New types

In `seihou-core/src/Seihou/Core/Types.hs`:

    data ConfigScope
      = ScopeLocal
      | ScopeNamespace Text
      | ScopeGlobal
      deriving stock (Eq, Show, Generic)

### New functions in existing modules

In `seihou-core/src/Seihou/Dhall/Config.hs`:

    serializeConfig :: Map Text Text -> Text
    escapeDhallText :: Text -> Text

### New effect modules

In `seihou-core/src/Seihou/Effect/ConfigWriter.hs`:

    data ConfigWriter :: Effect where
      WriteConfigValue :: ConfigScope -> Text -> Text -> ConfigWriter m ()
      DeleteConfigValue :: ConfigScope -> Text -> ConfigWriter m ()
      ListConfigValues :: ConfigScope -> ConfigWriter m (Either ConfigError (Map Text Text))

    type instance DispatchOf ConfigWriter = Dynamic

    writeConfigValue :: (ConfigWriter :> es) => ConfigScope -> Text -> Text -> Eff es ()
    deleteConfigValue :: (ConfigWriter :> es) => ConfigScope -> Text -> Eff es ()
    listConfigValues :: (ConfigWriter :> es) => ConfigScope -> Eff es (Either ConfigError (Map Text Text))

In `seihou-core/src/Seihou/Effect/ConfigWriterInterp.hs`:

    runConfigWriter :: (IOE :> es) => Eff (ConfigWriter : es) a -> Eff es a

In `seihou-core/src/Seihou/Effect/ConfigWriterPure.hs`:

    data ConfigWriterState = ConfigWriterState
      { cwLocal :: Map Text Text
      , cwNamespaces :: Map Text (Map Text Text)
      , cwGlobal :: Map Text Text
      }

    emptyConfigWriterState :: ConfigWriterState

    runConfigWriterPure :: ConfigWriterState -> Eff (ConfigWriter : es) a -> Eff es (a, ConfigWriterState)

### New CLI modules

In `seihou-cli/src/Seihou/CLI/Commands.hs`:

    data ConfigAction
      = ConfigSet Text Text
      | ConfigGet Text
      | ConfigUnset Text
      | ConfigList
      deriving stock (Eq, Show, Generic)

    data ConfigOpts = ConfigOpts
      { configAction :: ConfigAction
      , configGlobal :: Bool
      , configNamespace :: Maybe Text
      }
      deriving stock (Eq, Show, Generic)

In `seihou-cli/src/Seihou/CLI/Config.hs`:

    handleConfig :: ConfigOpts -> IO ()

### Dependencies

No new library dependencies. Uses existing: `effectful-core`, `containers`, `text`, `directory`, `filepath`, `dhall` (for round-trip testing only), `optparse-applicative`.
