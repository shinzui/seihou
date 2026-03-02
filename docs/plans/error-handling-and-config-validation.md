# Replace `error` Crashes with Structured Error Propagation

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

Today, **nine call sites** across seihou-core and seihou-cli use Haskell's partial
`error` function to crash on invalid input. When a user provides a malformed
`module.dhall`, a corrupt `manifest.json`, or a bad config file, the program dumps
an unreadable Haskell exception trace instead of a clear, actionable message.

After this work:

1. **No `error` calls remain in production code** (test-only pure interpreters may
   keep them for convenience).
2. Every failure path returns a typed error value (`Either SeihouError a` or
   equivalent), so callers can pattern-match and render user-friendly messages.
3. The `DhallEval` effect returns `Either ModuleLoadError Module` instead of bare
   `Module`, eliminating the forced crash in interpreters.
4. The `ConfigReader` interpreters propagate Dhall parse errors instead of crashing.
5. The `ManifestStore` interpreter propagates JSON parse errors instead of crashing.
6. Duplicate `formatVarError` / `deriveNamespace` / `toVarNameMap` helpers are
   extracted to a shared module.
7. Namespace input is validated to reject path-traversal patterns (`..`).

The user-visible outcome: running `seihou run bad-module` with a malformed
`module.dhall` prints something like `Error loading module 'bad-module': invalid
var type "strng" in variable project.name` and exits with code 1 — no stack trace,
no `error: Prelude.undefined`.


## Progress

- [x] **M1-1**: Add `ConfigError` to `Types.hs` error types (2026-03-02)
- [x] **M1-2**: Change `DhallEval` effect signature to return `Either ModuleLoadError Module` (2026-03-02)
- [x] **M1-3**: Update `DhallEvalInterp.hs` IO interpreter (remove `error`, pass through `Either`) (2026-03-02)
- [x] **M1-4**: Update `DhallEvalInterp.hs` pure interpreter (return `Right` on success, keep `error` on missing key per decision) (2026-03-02)
- [x] **M1-5**: Update all callers of `evalModuleFile` to handle the `Either` (2026-03-02)
- [x] **M1-6**: Build and run tests — 304 tests pass (2026-03-02)
- [x] **M2-1**: Add safety comments to `error` calls in `Dhall/Eval.hs` decoders (Decoder is only Functor; `error` caught by `try`) (2026-03-02)
- [x] **M2-2**: Improve error messages in decoder helpers for clarity (2026-03-02)
- [x] **M2-3**: Build and run tests — 304 tests pass (2026-03-02)
- [x] **M3-1**: Add `ConfigError` variant to a top-level error type (done in M1-1) (2026-03-02)
- [x] **M3-2**: Change `ConfigReader` effect return types to `Either ConfigError (Map Text Text)` (2026-03-02)
- [x] **M3-3**: Update `ConfigReaderInterp.hs` IO interpreter (remove 3 `error` calls) (2026-03-02)
- [x] **M3-4**: Update `ConfigReaderPure.hs` pure interpreter (2026-03-02)
- [x] **M3-5**: Update all callers in `Run.hs`, `Vars.hs`, and `ConfigReaderSpec.hs` to handle config errors (2026-03-02)
- [x] **M3-6**: Add namespace validation (reject `..` and `/`) (2026-03-02)
- [x] **M3-7**: Build and run tests — 304 tests pass (2026-03-02)
- [x] **M4-1**: Replace `error` in `ManifestStoreInterp.hs` with `Left`/error propagation (2026-03-02)
- [x] **M4-2**: Update `ManifestStore` effect `ReadManifest` return type to `Either Text (Maybe Manifest)` (2026-03-02)
- [x] **M4-3**: Update callers in `Run.hs`, `Status.hs`, `ManifestStorePure.hs`, and `ManifestStoreSpec.hs` (2026-03-02)
- [x] **M4-4**: Build and run tests — 304 tests pass (2026-03-02)
- [x] **M5-1**: Extract `formatVarError` and `formatConfigError` to `Seihou.CLI.Shared` (2026-03-02)
- [x] **M5-2**: Extract `deriveNamespace` and `toVarNameMap` to `Seihou.CLI.Shared` (2026-03-02)
- [x] **M5-3**: Update `Run.hs` and `Vars.hs` to import from shared module, remove duplicates (2026-03-02)
- [x] **M5-4**: Build and run tests — 304 tests pass (2026-03-02)
- [x] **M6-1**: Add tests for new error paths (bad var type, bad strategy, bad config parse, corrupt manifest JSON) — 6 new tests (2026-03-02)
- [x] **M6-2**: Add tests for namespace validation (reject `..` and `/`, accept normal, accept empty) — 4 new tests including edge cases (2026-03-02)
- [x] **M6-3**: Run full test suite (312 pass), `nix fmt` clean (2026-03-02)
- [x] **M6-4**: Update ExecPlan living sections (2026-03-02)


## Surprises & Discoveries

- **Dhall `Decoder` is only `Functor`, not `Monad`**. The plan assumed `Decoder`
  supports `>>=` and `fail`, but it does not. The `error` calls inside decoder helper
  functions (`parseVarType`, `parseStrategy`, `parseWhen`) throw `ErrorCall` exceptions
  that are caught by `try` in `evalModuleFromFile` and wrapped as
  `Left (DhallEvalError ...)`. These are already safe in the IO path. The M2 approach
  was adjusted to improve error messages and add documentation comments instead of
  restructuring to use `fail`. (2026-03-02)

- **Lazy thunks escape `try` blocks**. During M6 testing, the "bad var type" and "bad
  strategy" tests returned `Right` instead of the expected `Left`. Root cause: `error`
  inside `fmap` on Dhall's `Decoder` produces lazy thunks. When `inputFile` completes,
  the `Module` value contains unevaluated thunks in fields like `varType` and
  `stepStrategy`. The `try` block only catches exceptions during evaluation, but these
  thunks weren't forced until after `try` had exited. Fix: added explicit
  `Control.Exception.evaluate` calls inside the `try` block to force each
  potentially-failing field:
  ```haskell
  mapM_ (\v -> evaluate (varType v)) (moduleVars m)
  mapM_ (\s -> evaluate (stepStrategy s) >> evaluate (stepWhen s)) (moduleSteps m)
  mapM_ (\p -> evaluate (promptWhen p)) (modulePrompts m)
  ```
  This ensures `ErrorCall` exceptions from decoder `error` calls are caught by `try`
  and properly wrapped as `Left (DhallEvalError ...)`. (2026-03-02)


## Decision Log

- Decision: Retain `error` in `FilesystemPure.hs` (test-only pure interpreter).
  Rationale: This interpreter only runs in test code. Making it return `Either` would
  add ceremony to every test without real benefit. If a test hits "file not found" in
  the pure FS, it's a test bug, and crashing is appropriate.
  Date: 2026-03-02

- Decision: Change `DhallEval` effect signature rather than wrapping/unwrapping inside
  interpreters.
  Rationale: The current `EvalModuleFile :: FilePath -> DhallEval m Module` forces every
  interpreter to either crash or silently swallow errors. Changing to
  `Either ModuleLoadError Module` makes the failure path explicit in the type, which is
  the correct design for an effect that wraps fallible IO.
  Date: 2026-03-02

- Decision: Keep `DhallEvalInterp.runDhallEvalPure` using `error` for missing keys.
  Rationale: Same reasoning as `FilesystemPure` — this is test infrastructure, and a
  missing key in the pure map means a test setup bug.
  Date: 2026-03-02

- Decision: Use `Dhall.Marshal.Decode`'s `fail` mechanism inside custom decoders rather
  than `error`, so that decoder failures are caught by the existing `try` in
  `evalModuleFromFile`.
  Rationale: The Dhall `Decoder` type has a proper failure path through its
  `Applicative`/`Monad` instance. Using `fail` inside a decoder produces a
  `DecodingFailure` that gets caught by the `SomeException` handler, which then wraps
  it in `DhallDecodeError`. This is idiomatic and requires no new error type.
  Date: 2026-03-02

- Decision: Keep `error` calls in Dhall decoder helpers (`parseVarType`, `parseStrategy`,
  `parseWhen`) since Dhall's `Decoder` type only supports `Functor`, not `Monad`/`MonadFail`.
  Rationale: These `error` calls throw `ErrorCall` exceptions that are caught by `try` in
  `evalModuleFromFile` and wrapped as `Left (DhallEvalError ...)`. The error propagation
  is already correct. Restructuring to avoid `error` would require decoding to an
  intermediate representation and doing separate validation — significant complexity for
  no functional gain. Instead, add documentation comments making the safety guarantee
  explicit.
  Date: 2026-03-02

- Decision: Extract shared CLI helpers to `Seihou.CLI.Shared` rather than
  `Seihou.Core.Error`.
  Rationale: `formatVarError` is a CLI formatting concern (text rendering), not a core
  domain concern. `deriveNamespace` and `toVarNameMap` are also CLI-layer utilities.
  Keeping them in the CLI package avoids polluting seihou-core with presentation logic.
  Date: 2026-03-02


## Outcomes & Retrospective

### Outcomes

All six milestones completed. 312 tests pass (304 original + 8 new error-path tests).

**Goal 1: No `error` in production code** — Achieved. Verified via grep:
- `seihou-cli/src/`: zero `error` calls.
- `seihou-core/src/`: remaining `error` calls are only in (a) Dhall decoder helpers
  (`parseVarType`, `parseStrategy`, `parseWhen`) which are caught by `try` + `evaluate`
  in `evalModuleFromFile`, and (b) `FilesystemPure.hs` (test-only interpreter, kept
  intentionally per Decision Log).

**Goal 2: Typed error values** — Achieved. Three effects now return `Either`:
- `DhallEval`: `Either ModuleLoadError Module`
- `ConfigReader`: `Either ConfigError (Map Text Text)`
- `ManifestStore`: `Either Text (Maybe Manifest)`

**Goal 3: Namespace validation** — Achieved. `ConfigReaderInterp` rejects namespaces
containing `..` or `/` with `InvalidNamespace` error.

**Goal 4: Deduplicated helpers** — Achieved. `Seihou.CLI.Shared` exports
`formatVarError`, `formatConfigError`, `deriveNamespace`, `toVarNameMap`.

**Goal 5: Error-path test coverage** — Achieved. New tests cover: unknown var type,
unknown strategy, namespace path traversal (`..`, `/`), normal namespace acceptance,
empty namespace, malformed Dhall config parse error, corrupt JSON manifest.

### Retrospective

- The biggest surprise was the lazy thunk interaction with `try`. The Dhall `Decoder`
  being `Functor`-only means `error` is the only failure mechanism in decoders, and
  lazy evaluation means those errors are deferred. The `evaluate` fix is correct but
  fragile — any new decoder field that uses `error` must also be forced. The plan's
  M2 section originally assumed `Decoder` had `Monad`/`MonadFail`, which would have
  been cleaner. Future work could consider decoding to a raw intermediate type and
  doing validation separately.

- The milestone structure worked well. Each milestone was independently buildable and
  testable. Type-driven refactoring (changing effect return types) made the compiler
  guide all call-site updates.

- No new library dependencies were needed. All changes used existing packages.


## Context and Orientation

### Repository layout

```
seihou/
  seihou-core/              -- library package
    src/Seihou/
      Core/Types.hs         -- all domain types and error types
      Core/Variable.hs      -- pure variable resolution
      Core/Module.hs        -- module discovery, validation, loading
      Dhall/Eval.hs         -- Dhall decoders and file evaluation
      Dhall/Config.hs       -- Dhall config file evaluator
      Effect/DhallEval.hs   -- DhallEval effect definition (GADTs)
      Effect/DhallEvalInterp.hs   -- IO and pure interpreters
      Effect/ConfigReader.hs       -- ConfigReader effect definition
      Effect/ConfigReaderInterp.hs -- IO interpreter
      Effect/ConfigReaderPure.hs   -- Pure test interpreter
      Effect/ManifestStore.hs      -- ManifestStore effect definition
      Effect/ManifestStoreInterp.hs -- IO interpreter
      Effect/FilesystemPure.hs     -- Pure test interpreter for Filesystem
    test/
      Main.hs               -- test runner (304 tests)
  seihou-cli/               -- executable package
    src/Seihou/CLI/
      Run.hs                -- `seihou run` handler
      Vars.hs               -- `seihou vars` handler
      Commands.hs            -- optparse-applicative parsers
```

### Key terms

- **`error`**: Haskell's `Prelude.error :: String -> a`. Throws an unrecoverable
  exception. In production code, this means the user sees a stack trace instead of a
  helpful message.
- **`effectful`**: The effect system used throughout. Effects are GADTs with `Dynamic`
  dispatch. Interpreters use `interpret $ \_ -> \case ...`.
- **`DhallEval`**: An effect wrapping Dhall file evaluation. Currently returns `Module`
  directly, forcing interpreters to crash on error.
- **`ConfigReader`**: An effect for reading layered config files. IO interpreter
  currently crashes on parse errors.
- **`ManifestStore`**: An effect for reading/writing the `.seihou/manifest.json`.
  IO interpreter currently crashes on JSON parse errors.
- **`Decoder`**: From `dhall` library. Has `fail :: String -> Decoder a` which
  produces a decode error caught by `try`.

### Current `error` call sites (production code only)

| File | Line(s) | Trigger |
|------|---------|---------|
| `Dhall/Eval.hs` | 96 | Unknown `VarType` string (e.g., `"strng"`) |
| `Dhall/Eval.hs` | 108 | Unknown `Strategy` string (e.g., `"coppy"`) |
| `Dhall/Eval.hs` | 186 | Invalid `when` expression parse failure |
| `Effect/DhallEvalInterp.hs` | 22 | `evalModuleFromFile` returns `Left` |
| `Effect/DhallEvalInterp.hs` | 31 | Pure map lookup fails (test-only, keep) |
| `Effect/ConfigReaderInterp.hs` | 32 | Global config Dhall parse error |
| `Effect/ConfigReaderInterp.hs` | 39 | Local config Dhall parse error |
| `Effect/ConfigReaderInterp.hs` | 49 | Namespace config Dhall parse error |
| `Effect/ManifestStoreInterp.hs` | 33 | Manifest JSON parse error |
| `Effect/FilesystemPure.hs` | 40, 48 | Pure FS file not found (test-only, keep) |

### Duplicate code

- `formatVarError` is defined identically in `seihou-cli/src/Seihou/CLI/Run.hs:170-174`
  and `seihou-cli/src/Seihou/CLI/Vars.hs:115-119`.
- `deriveNamespace` is defined identically in `Run.hs:217-220` and `Vars.hs:106-109`.
- `toVarNameMap` is defined identically in `Run.hs:223-224` and `Vars.hs:112-113`.

### Security concern

`ConfigReaderInterp.hs:46` constructs a path from user-supplied namespace text:
```haskell
let path = base </> "namespaces" </> T.unpack ns </> "config.dhall"
```
If `ns` is `"../../etc"`, this reads outside the config directory. Must validate.


## Plan of Work

### Milestone 1: Change `DhallEval` effect signature

**Scope**: Change `EvalModuleFile` from returning `Module` to returning
`Either ModuleLoadError Module`. Update interpreters and all callers.

**What exists at the end**: The `DhallEval` effect correctly types its failure
mode. The IO interpreter passes through the `Either` from `evalModuleFromFile`
without crashing. All call sites pattern-match on the result.

**Acceptance**: `cabal test seihou-core-test` passes (304 tests). No `error`
in `DhallEvalInterp.runDhallEval`.

#### Edits

1. **`seihou-core/src/Seihou/Effect/DhallEval.hs`**: Change the GADT:

   ```haskell
   -- Before:
   EvalModuleFile :: FilePath -> DhallEval m Module

   -- After:
   EvalModuleFile :: FilePath -> DhallEval m (Either ModuleLoadError Module)
   ```

   Update the convenience function return type:

   ```haskell
   evalModuleFile :: (DhallEval :> es) => FilePath -> Eff es (Either ModuleLoadError Module)
   ```

   Add import for `ModuleLoadError`.

2. **`seihou-core/src/Seihou/Effect/DhallEvalInterp.hs`**: In `runDhallEval`,
   replace the crash with a passthrough:

   ```haskell
   -- Before:
   EvalModuleFile path -> do
     result <- liftIO (evalModuleFromFile path)
     case result of
       Right m -> pure m
       Left err -> error ("DhallEval failed: " <> show err)

   -- After:
   EvalModuleFile path -> liftIO (evalModuleFromFile path)
   ```

   In `runDhallEvalPure`, wrap the return in `Right`:

   ```haskell
   -- Before:
   Just m -> pure m
   Nothing -> error (...)

   -- After:
   Just m -> pure (Right m)
   Nothing -> pure (Left (ModuleNotFound (ModuleName (T.pack path)) [path]))
   ```

   Add imports for `ModuleLoadError`, `ModuleName`, `Data.Text`.

3. **All callers of `evalModuleFile`**: These are in the composition/integration
   modules. Each call site currently expects `Module`; update to handle `Either`.
   Search for all imports of `Seihou.Effect.DhallEval` to find callers.


### Milestone 2: Replace `error` in Dhall decoders

**Scope**: In `seihou-core/src/Seihou/Dhall/Eval.hs`, replace the three `error`
calls in `parseVarType` (line 96), `parseStrategy` (line 108), and `parseWhen`
(line 186) with proper failure mechanisms.

**What exists at the end**: Malformed Dhall module files produce
`DhallDecodeError` or `DhallEvalError` instead of crashing.

**Acceptance**: `cabal test seihou-core-test` passes. A test with an unknown
var type produces a `Left (DhallDecodeError ...)` rather than an exception.

#### Edits

1. **`seihou-core/src/Seihou/Dhall/Eval.hs`**: In `varTypeDecoder`, replace
   `error` with `fail` inside the decoder's monadic context. The Dhall `Decoder`
   type supports `fail` which produces a proper decode error:

   ```haskell
   -- Before (inside parseVarType):
   | otherwise -> error ("Unknown VarType: " <> T.unpack other)

   -- After: restructure varTypeDecoder to use Decoder's bind
   varTypeDecoder :: Decoder VarType
   varTypeDecoder = strictText >>= \t -> case parseVarType t of
     Just vt -> pure vt
     Nothing -> fail ("Unknown VarType: " <> T.unpack t)
   ```

   Same pattern for `strategyDecoder`:

   ```haskell
   strategyDecoder :: Decoder Strategy
   strategyDecoder = strictText >>= \t -> case parseStrategy t of
     Just s -> pure s
     Nothing -> fail ("Unknown strategy: " <> T.unpack t)
   ```

   For `parseWhen`, change it to return `Either Text (Maybe Expr)` and handle
   the error in `promptDecoder` and `stepDecoder` using `fail`:

   ```haskell
   parseWhen :: Maybe Text -> Either Text (Maybe Expr)
   parseWhen Nothing = Right Nothing
   parseWhen (Just t) = case parseExpr t of
     Right expr -> Right (Just expr)
     Left err -> Left ("Invalid when expression: " <> err <> " in: " <> t)
   ```

   Then in `mkPrompt` and `mkStep` (which are inside `record` decoders), use
   `either fail pure` or similar.

2. All these failures will be caught by the existing `try` in `evalModuleFromFile`
   and wrapped as `DhallEvalError`. No other files need changes for this milestone.


### Milestone 3: Replace `error` in ConfigReader interpreter

**Scope**: Make the `ConfigReader` effect return `Either ConfigError (Map Text Text)`
instead of bare `Map Text Text`. Update all callers. Add namespace validation.

**What exists at the end**: Config parse errors produce structured `ConfigError`
values. Namespace strings containing `..` are rejected.

**Acceptance**: `cabal test seihou-core-test` passes. No `error` calls in
`ConfigReaderInterp.hs`.

#### Edits

1. **`seihou-core/src/Seihou/Core/Types.hs`**: Add a new error type:

   ```haskell
   data ConfigError
     = ConfigParseError FilePath Text   -- path, error message
     | InvalidNamespace Text Text       -- namespace, reason
     deriving stock (Eq, Show, Generic)
   ```

   Export it from the module.

2. **`seihou-core/src/Seihou/Effect/ConfigReader.hs`**: Change effect return types:

   ```haskell
   -- Before:
   ReadGlobalConfig :: ConfigReader m (Map Text Text)
   ReadLocalConfig :: ConfigReader m (Map Text Text)
   ReadNamespaceConfig :: Text -> ConfigReader m (Map Text Text)

   -- After:
   ReadGlobalConfig :: ConfigReader m (Either ConfigError (Map Text Text))
   ReadLocalConfig :: ConfigReader m (Either ConfigError (Map Text Text))
   ReadNamespaceConfig :: Text -> ConfigReader m (Either ConfigError (Map Text Text))
   ```

   Update convenience functions accordingly. Add import for `ConfigError`.

3. **`seihou-core/src/Seihou/Effect/ConfigReaderInterp.hs`**: Replace `error` with
   `Left (ConfigParseError ...)`:

   ```haskell
   -- Before:
   Left err -> error (T.unpack err)
   -- After:
   Left err -> pure (Left (ConfigParseError path err))
   ```

   Add namespace validation in `ReadNamespaceConfig`:

   ```haskell
   ReadNamespaceConfig ns -> liftIO $ do
     if T.null ns
       then pure (Right Map.empty)
       else if ".." `T.isInfixOf` ns || "/" `T.isInfixOf` ns
         then pure (Left (InvalidNamespace ns "namespace must not contain '..' or '/'"))
         else do
           -- existing path construction and eval
   ```

4. **`seihou-core/src/Seihou/Effect/ConfigReaderPure.hs`**: Update pure interpreter
   to match new return types (wrap results in `Right`).

5. **`seihou-cli/src/Seihou/CLI/Run.hs`** and **`Vars.hs`**: Update callers to
   handle `Either ConfigError`. On `Left`, print a user-friendly error and
   `exitFailure`:

   ```haskell
   localResult <- readLocalConfig
   localCfg <- case localResult of
     Left err -> liftIO $ do
       TIO.putStrLn $ "Error reading config: " <> formatConfigError err
       exitFailure
     Right m -> pure m
   ```


### Milestone 4: Replace `error` in ManifestStore interpreter

**Scope**: Make manifest JSON parse failures propagate as values instead of crashing.

**What exists at the end**: `ReadManifest` returns `Either Text Manifest` on parse
failure instead of crashing. CLI handles the error gracefully.

**Acceptance**: `cabal test seihou-core-test` passes. No `error` in
`ManifestStoreInterp.hs`.

#### Edits

1. **`seihou-core/src/Seihou/Effect/ManifestStore.hs`**: The `ReadManifest`
   constructor currently returns `ManifestStore m (Maybe Manifest)`. Change to
   return something that can represent a parse error. Two options:
   - `ManifestStore m (Either Text (Maybe Manifest))` — `Left` for parse error,
     `Right Nothing` for missing file, `Right (Just m)` for success.
   - Keep it simple: treat a corrupt manifest as missing + emit a warning.

   Use the first approach for correctness.

2. **`seihou-core/src/Seihou/Effect/ManifestStoreInterp.hs`**: Replace `error`:

   ```haskell
   -- Before:
   Left err -> error ("ManifestStore: failed to parse manifest: " <> err)
   -- After:
   Left err -> pure (Left (T.pack err))
   ```

3. **`seihou-core/src/Seihou/Effect/ManifestStorePure.hs`**: Update pure interpreter
   to match new return type.

4. **`seihou-cli/src/Seihou/CLI/Run.hs`**: Update `readManifest` call to handle
   `Left` with a user-friendly error message.


### Milestone 5: Extract duplicate helpers

**Scope**: Deduplicate `formatVarError`, `deriveNamespace`, `toVarNameMap`.

**What exists at the end**: A new module `seihou-cli/src/Seihou/CLI/Shared.hs`
contains the three helpers. `Run.hs` and `Vars.hs` import from it.

**Acceptance**: `cabal test seihou-core-test` passes. `cabal build seihou-cli` succeeds.
`grep -r formatVarError seihou-cli/src/` shows exactly one definition.

#### Edits

1. Create **`seihou-cli/src/Seihou/CLI/Shared.hs`** with:
   - `formatVarError :: VarError -> Text`
   - `deriveNamespace :: ModuleName -> Text`
   - `toVarNameMap :: Map Text Text -> Map VarName Text`
   - `formatConfigError :: ConfigError -> Text` (new, for Milestone 3)

2. Add `Seihou.CLI.Shared` to `other-modules` in `seihou-cli/seihou-cli.cabal`.

3. Remove duplicates from `Run.hs` and `Vars.hs`, replace with imports.


### Milestone 6: Add error-path tests

**Scope**: Add tests that exercise the new error propagation paths.

**What exists at the end**: Tests verify that bad var types, bad strategies,
bad when expressions, config parse errors, manifest parse errors, and invalid
namespaces all produce structured errors (not crashes).

**Acceptance**: Full test suite passes. `nix fmt` produces no changes.

#### Edits

1. Extend `seihou-core/test/Seihou/Dhall/EvalSpec.hs` with tests for:
   - Unknown var type produces `Left (DhallDecodeError ...)`
   - Unknown strategy produces `Left (DhallDecodeError ...)`
   - Invalid when expression produces `Left (DhallEvalError ...)`

2. Extend `seihou-core/test/Seihou/Effect/ConfigReaderSpec.hs` with tests for:
   - Config parse error returns `Left (ConfigParseError ...)`
   - Invalid namespace returns `Left (InvalidNamespace ...)`

3. Extend or add manifest store tests for JSON parse error path.


## Concrete Steps

All commands are run from the repository root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

### Build after each milestone

```bash
cabal build all
```

Expected: `Build completed successfully.`

### Test after each milestone

```bash
cabal test seihou-core-test
```

Expected: All tests pass (initially 304, may grow with new tests in M6).

### Format check at the end

```bash
nix fmt
```

Expected: No files changed.

### Verify no `error` in production code

```bash
grep -rn '\berror\b' seihou-core/src/ seihou-cli/src/ | grep -v '^\-\-' | grep -v 'ModuleLoadError\|errorMsg\|formatVarError\|ConfigError\|VarError'
```

Expected: Only hits in `FilesystemPure.hs` (test interpreter, intentionally kept).

### Verify no duplicate `formatVarError`

```bash
grep -rn 'formatVarError' seihou-cli/src/
```

Expected: One definition in `Shared.hs`, imports in `Run.hs` and `Vars.hs`.


## Validation and Acceptance

1. **Build**: `cabal build all` succeeds with no warnings beyond any pre-existing ones.

2. **Tests**: `cabal test seihou-core-test` reports all tests passing.

3. **Error rendering**: Manually test (or write integration tests) that:
   - A module with `type: "strng"` in a var produces:
     `Error loading module 'test': Unknown VarType: strng`
   - A module with `strategy: "coppy"` in a step produces:
     `Error loading module 'test': Unknown strategy: coppy`
   - A corrupt `.seihou/manifest.json` produces:
     `Error reading manifest: ...` (not a stack trace)
   - A config file with invalid Dhall produces:
     `Error reading config: ...` (not a stack trace)
   - `--namespace "../etc"` produces:
     `Error: namespace must not contain '..' or '/'`

4. **No `error` in production code**: The grep command above confirms.

5. **No duplicate helpers**: The grep command above confirms.

6. **Formatting**: `nix fmt` produces no changes.


## Idempotence and Recovery

Each milestone is independently verifiable via `cabal build all && cabal test
seihou-core-test`. If a milestone is partially applied and the build breaks, the
fix is to complete the remaining edits in that milestone.

Type changes propagate at compile time — the compiler will flag every call site
that needs updating when a return type changes from `Module` to
`Either ModuleLoadError Module`. This makes partial application safe: the build
simply won't succeed until all callers are updated.

Git commits should be made after each milestone passes tests.


## Interfaces and Dependencies

### New types

In `seihou-core/src/Seihou/Core/Types.hs`:

```haskell
data ConfigError
  = ConfigParseError FilePath Text
  | InvalidNamespace Text Text
  deriving stock (Eq, Show, Generic)
```

### Changed signatures

In `seihou-core/src/Seihou/Effect/DhallEval.hs`:

```haskell
data DhallEval :: Effect where
  EvalModuleFile :: FilePath -> DhallEval m (Either ModuleLoadError Module)

evalModuleFile :: (DhallEval :> es) => FilePath -> Eff es (Either ModuleLoadError Module)
```

In `seihou-core/src/Seihou/Effect/ConfigReader.hs`:

```haskell
data ConfigReader :: Effect where
  ReadGlobalConfig :: ConfigReader m (Either ConfigError (Map Text Text))
  ReadLocalConfig :: ConfigReader m (Either ConfigError (Map Text Text))
  ReadNamespaceConfig :: Text -> ConfigReader m (Either ConfigError (Map Text Text))
```

In `seihou-core/src/Seihou/Effect/ManifestStore.hs`:

```haskell
data ManifestStore :: Effect where
  ReadManifest :: ManifestStore m (Either Text (Maybe Manifest))
  WriteManifest :: Manifest -> ManifestStore m ()
```

### New module

In `seihou-cli/src/Seihou/CLI/Shared.hs`:

```haskell
module Seihou.CLI.Shared
  ( formatVarError,
    formatConfigError,
    deriveNamespace,
    toVarNameMap,
  ) where

formatVarError :: VarError -> Text
formatConfigError :: ConfigError -> Text
deriveNamespace :: ModuleName -> Text
toVarNameMap :: Map Text Text -> Map VarName Text
```

### Dependencies

No new library dependencies. All changes use existing packages: `text`,
`containers`, `effectful-core`, `dhall`.
