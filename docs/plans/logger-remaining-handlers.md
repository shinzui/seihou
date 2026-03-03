# Wire Logger into Remaining CLI Handlers

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

The prior plan (`docs/plans/logger-effect-interpreters.md`) created the Logger effect interpreters and wired them into `handleRun`. The remaining six CLI handlers — `init`, `install`, `vars`, `status`, `new-module`, `validate-module` — still print error messages directly to stdout via `TIO.putStrLn`. This is inconsistent and violates the Unix convention where diagnostic output belongs on stderr.

After this change, every error message across all CLI handlers will flow through the Logger effect and appear on stderr with a `[error]` prefix. This makes it possible to cleanly redirect program output (`seihou status > manifest-info.txt`) without error messages leaking into the file. User-facing output (command results, listings, reports, success confirmations) stays on stdout via `TIO.putStrLn`. The `logIO` helper and a shared `unwrapConfig` function will be extracted into the shared utilities module so all handlers use the same pattern established in `handleRun`.

The user can verify the change by running any command with an error condition (e.g., `seihou vars nonexistent-module 2>/dev/null`) and observing that no output appears on stdout — the error went to stderr.


## Progress

- [x] M1-1: Move `logIO` from `Run.hs` to `Shared.hs` and update `Run.hs` imports (2026-03-03)
- [x] M1-2: Move `unwrapConfig` from `Run.hs` to `Shared.hs` (Logger-ified version) (2026-03-03)
- [x] M1-3: Build and test — all 439 tests pass (2026-03-03)
- [x] M2-1: Wire Logger into `Install.hs` (6 error call sites) (2026-03-03)
- [x] M2-2: Wire Logger into `Vars.hs` (5 error call sites + shared `unwrapConfig`) (2026-03-03)
- [x] M2-3: Wire Logger into `NewModule.hs` (3 error call sites) (2026-03-03)
- [x] M2-4: Wire Logger into `Validate.hs` (1 error call site) (2026-03-03)
- [x] M2-5: Wire Logger into `Status.hs` (1 error call site) (2026-03-03)
- [x] M2-6: Build and test all — all 439 tests pass (2026-03-03)
- [x] M2-7: Manual verification — errors go to stderr, user output goes to stdout (2026-03-03)


## Surprises & Discoveries

- Validate.hs had both `import Seihou.Core.Types` (unqualified, bringing everything into scope) and a separate `import Seihou.Core.Types (LogLevel (..))`. The treefmt pre-commit hook sorted them alphabetically, revealing the redundancy. Removed the duplicate. Other handlers (NewModule.hs) needed `import Seihou.Core.Types (LogLevel (..))` separately since they don't have the unqualified import.


## Decision Log

- Decision: Do not wire Logger into `Init.hs`.
  Rationale: `handleInit` has zero error paths — it never calls `exitFailure` and every `TIO.putStrLn` call in it is user-facing success output ("Created modules/", "Created config.dhall", "Already exists: config.dhall"). There is nothing to route through Logger. Adding Logger imports with no call sites would be dead code.
  Date: 2026-03-03

- Decision: Hardcode `LogNormal` in all remaining handlers instead of adding a `--verbose` flag to each command.
  Rationale: These handlers are simple and have almost no informational or debug output — they have only error messages and user-facing results. Adding `--verbose` flags to six commands would add CLI surface area with no practical benefit until those commands gain meaningful diagnostic output (e.g., "Resolving dependencies..." progress messages). The `LogNormal` level ensures `logError` messages always appear (since errors require only `LogQuiet`, and `LogNormal >= LogQuiet`). When a handler later grows verbose-worthy output, adding `--verbose` is a one-field, one-line parser change.
  Date: 2026-03-03

- Decision: Extract `logIO` and `unwrapConfig` into `Shared.hs` rather than creating a new module.
  Rationale: `Shared.hs` already serves as the home for cross-handler utility functions (`formatVarError`, `formatConfigError`, `deriveNamespace`, `toVarNameMap`). Adding two more small functions keeps the module cohesive. The `logIO` function is three lines and `unwrapConfig` is five. Creating a new module for eight lines would be over-engineering.
  Date: 2026-03-03

- Decision: Keep progress messages (e.g., "Cloning X ..." in `install`) as `TIO.putStrLn` rather than converting to `logInfo`.
  Rationale: Without a `--verbose` flag on these commands, `logInfo` at `LogNormal` would suppress these messages (Info requires `LogVerbose`). These messages are useful feedback the user expects — suppressing them changes visible behavior with no way to opt back in. If `--verbose` is added to `install` later, these can be migrated to `logInfo` then.
  Date: 2026-03-03

- Decision: Remove the duplicate `unwrapConfig` from `Vars.hs`.
  Rationale: `Vars.hs` has its own copy of `unwrapConfig` that uses `TIO.putStrLn` directly. After extracting the Logger-ified version to `Shared.hs`, the duplicate must be removed. Both `Run.hs` and `Vars.hs` will import the shared version.
  Date: 2026-03-03


## Outcomes & Retrospective

All 10 items completed in a single session. Both milestones landed in one commit (`0ecb190`).

**Results**: Every error message across all CLI handlers now flows through the Logger effect and appears on stderr with `[error]` prefix. User-facing output (listings, reports, success confirmations) remains on stdout via `TIO.putStrLn`. The `logIO` and `unwrapConfig` helpers in `Shared.hs` provide a single shared pattern. The duplicate `unwrapConfig` in `Vars.hs` was removed. All 439 tests pass.

**Verification**: `seihou vars nonexistent-module 2>/dev/null` produces no output (error suppressed). `seihou init 2>/dev/null` shows success messages on stdout unchanged. `seihou new-module INVALID 2>/dev/null` and `seihou validate-module /nonexistent 2>/dev/null` produce no stdout output.

**Lessons**: The treefmt pre-commit hook catches import ordering and duplicate imports, which is helpful for maintaining consistent style. Planning to add `LogLevel (..)` to a module that already has an unqualified import of the same module creates a silent duplicate that the formatter surfaces.


## Context and Orientation

### Logger infrastructure (already built)

The prior plan `docs/plans/logger-effect-interpreters.md` created the Logger effect interpreters. The relevant pieces are:

The Logger effect (`seihou-core/src/Seihou/Effect/Logger.hs`) defines four operations: `LogDebug`, `LogInfo`, `LogWarn`, `LogError`. Each takes a `Text` message. Helper functions `logDebug`, `logInfo`, `logWarn`, `logError` wrap each operation in a `send` call.

The IO interpreter (`seihou-core/src/Seihou/Effect/LoggerInterp.hs`) exports `runLoggerIO :: (IOE :> es) => LogLevel -> Eff (Logger : es) a -> Eff es a`. It writes messages to stderr with level-based filtering. At `LogNormal`, only `logWarn` and `logError` messages appear. At `LogVerbose`, all four levels appear.

The `LogLevel` type is defined in `seihou-core/src/Seihou/Core/Types.hs`: `data LogLevel = LogQuiet | LogNormal | LogVerbose` with derived `Eq`, `Ord`, `Show`, `Generic`. The ordering `LogQuiet < LogNormal < LogVerbose` is used by `shouldLog` for filtering.

In `seihou-cli/src/Seihou/CLI/Run.hs`, the Logger is used via a `logIO` helper:

    logIO :: LogLevel -> Eff '[Logger, IOE] () -> IO ()
    logIO level action = runEff $ runLoggerIO level action

This runs a one-shot Logger action in plain `IO`. Usage: `logIO level (logError "something went wrong")`. The level is computed from `runVerbose runOpts`.

`Run.hs` also has a Logger-ified `unwrapConfig`:

    unwrapConfig :: (IOE :> es) => LogLevel -> Either ConfigError a -> Eff es a

This is called inside effectful blocks to handle config loading errors. `Vars.hs` has its own copy of this function that still uses `TIO.putStrLn`.

### The six remaining handlers

The CLI dispatches commands through `seihou-cli/src/Main.hs`, which pattern-matches on the `Command` type and calls the corresponding handler function. Each handler is in its own module under `seihou-cli/src/Seihou/CLI/`. The dispatch does not pass any shared state — each handler is a standalone `IO` action.

**`Init.hs`** (`handleInit :: IO ()`) — Creates `~/.config/seihou/` with subdirectories and a default `config.dhall`. All output is success confirmations ("Created ...", "Already exists: ..."). No error paths exist (no `exitFailure`). Nothing to wire.

**`Install.hs`** (`handleInstall :: InstallOpts -> IO ()`) — Clones a git repo, validates the module, and copies it to the install directory. Has six error call sites that print to stdout before `exitFailure`: already-installed (lines 40-41), git clone failure (lines 52-53), Dhall eval error (lines 62-63), validation errors (lines 70-71), generic error (line 74), and one success message ("Installed module...") plus a progress message ("Cloning..."). The error messages should route through Logger; success and progress messages stay as `TIO.putStrLn`.

**`Vars.hs`** (`handleVars :: VarsOpts -> IO ()`) — Loads a module and either lists variable declarations or shows resolve provenance. Has five error call sites: module not found (lines 31-33), generic error (line 36), resolve errors (lines 98-99), and `unwrapConfig` errors (lines 110-112, a duplicate of Run.hs). All variable listing output is user-facing.

**`Status.hs`** (`handleStatus :: IO ()`) — Reads `.seihou/manifest.json` and displays its contents. Has one error call site: manifest read error (line 25). All other output is the manifest display.

**`NewModule.hs`** (`handleNewModule :: NewModuleOpts -> IO ()`) — Scaffolds a new module directory. Has three error call sites: invalid name (lines 21-22), directory exists (line 35). All creation confirmations are user output.

**`Validate.hs`** (`handleValidateModule :: ValidateOpts -> IO ()`) — Validates a module directory. Has one error call site: `module.dhall` not found (line 30). The validation report output is user-facing (goes to stdout via `TIO.putStr`).

### Shared utilities module

`seihou-cli/src/Seihou/CLI/Shared.hs` exports `formatVarError`, `formatConfigError`, `deriveNamespace`, and `toVarNameMap`. It currently does not import any effectful modules. After this plan, it will also export `logIO` and `unwrapConfig`.


## Plan of Work

### Milestone 1: Extract shared Logger helpers

This milestone moves the `logIO` helper and `unwrapConfig` from `Run.hs` into `Shared.hs` so all handlers can use them. At the end, `handleRun` still works exactly as before, but its Logger utilities come from `Shared.hs` instead of being locally defined. All 439 tests pass.

In `seihou-cli/src/Seihou/CLI/Shared.hs`, add imports for `Effectful`, `Seihou.Effect.Logger (Logger)`, `Seihou.Effect.LoggerInterp (runLoggerIO)`, and `Seihou.Core.Types (LogLevel (..), ConfigError)`. Add `logIO` and `unwrapConfig` to the export list. Define:

    logIO :: LogLevel -> Eff '[Logger, IOE] () -> IO ()
    logIO level action = runEff $ runLoggerIO level action

    unwrapConfig :: (IOE :> es) => LogLevel -> Either ConfigError a -> Eff es a
    unwrapConfig _ (Right a) = pure a
    unwrapConfig level (Left err) = liftIO $ do
      logIO level (logError $ "Error reading config: " <> formatConfigError err)
      exitFailure

In `seihou-cli/src/Seihou/CLI/Run.hs`, remove the local `logIO` definition (lines 309-311) and the local `unwrapConfig` definition (lines 277-283). Update the import of `Seihou.CLI.Shared` to also import `logIO` and `unwrapConfig`. Remove the now-unused direct imports of `Seihou.Effect.Logger (Logger)` and `Seihou.Effect.LoggerInterp (runLoggerIO)` — wait, `Run.hs` still uses `logDebug`, `logInfo`, `logWarn`, `logError` directly in its body, so it still needs the Logger helpers. But it no longer needs to import `Logger` (the type) or `runLoggerIO` since `logIO` comes from Shared. Check that the remaining imports in Run.hs are actually used: `Seihou.Effect.Logger` is needed for `logDebug`, `logInfo`, `logWarn`, `logError`; `Seihou.Effect.LoggerInterp` is no longer needed.


### Milestone 2: Wire Logger into remaining handlers

This milestone modifies five handler files (all except `Init.hs`) to route error messages through Logger. At the end, every error message in the CLI appears on stderr with a `[error]` prefix, while user-facing output remains on stdout. All tests pass and `seihou <command> 2>/dev/null` suppresses errors while preserving output.

For each handler, the pattern is the same: add `import Seihou.CLI.Shared (logIO)`, add `import Seihou.Effect.Logger (logError)`, add `import Seihou.Core.Types (LogLevel (..))`, and replace `TIO.putStrLn "Error: ..."` with `logIO LogNormal (logError "Error: ...")`. Then remove any now-unused `Data.Text.IO` import if `TIO` is no longer referenced.

The specific edits per handler are detailed below.

**Install.hs** — Six error call sites. Replace each `TIO.putStrLn` + `exitFailure` pair with `logIO LogNormal` + `exitFailure`. Multi-line error blocks (e.g., lines 40-42 where two messages print before `exitFailure`) become a single `logIO LogNormal $ do logError ...; logError ...` block followed by `exitFailure`. The "Cloning ..." message (line 48) and "Installed module..." message (line 81) stay as `TIO.putStrLn`.

**Vars.hs** — Five error call sites plus the duplicate `unwrapConfig`. Remove the local `unwrapConfig` entirely. Import `unwrapConfig` from `Shared`. Replace error `TIO.putStrLn` calls with `logError`. The declaration mode output and explain mode output remain as `TIO.putStrLn`.

**NewModule.hs** — Three error call sites. Replace error `TIO.putStrLn` before `exitFailure` with `logIO LogNormal (logError ...)`.

**Validate.hs** — One error call site (line 30, "module.dhall not found"). Replace with `logIO LogNormal (logError ...)`. The report output stays as `TIO.putStr`.

**Status.hs** — One error call site (line 25, "Error reading manifest"). Replace with `logIO LogNormal (logError ...)`. All manifest display output stays as `TIO.putStrLn`.


## Concrete Steps

### Milestone 1

**Working directory**: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

**Step 1**: Edit `seihou-cli/src/Seihou/CLI/Shared.hs`. Add the new imports and exports. Add `logIO` and `unwrapConfig` definitions.

**Step 2**: Edit `seihou-cli/src/Seihou/CLI/Run.hs`. Remove local `logIO` and `unwrapConfig`. Update imports: add `logIO` and `unwrapConfig` to the `Seihou.CLI.Shared` import, remove the `Seihou.Effect.LoggerInterp` import, remove `Logger` from the `Seihou.Effect.Logger` import (keep `logDebug`, `logInfo`, `logWarn`, `logError`).

**Step 3**: Build and test:

    cabal build all
    cabal test all

Expected: all 439 tests pass, clean build.

### Milestone 2

**Step 4**: Edit `seihou-cli/src/Seihou/CLI/Install.hs`. Add Logger imports. Replace six error call sites. Keep progress and success messages.

**Step 5**: Edit `seihou-cli/src/Seihou/CLI/Vars.hs`. Add Logger imports. Remove local `unwrapConfig`. Import `unwrapConfig` and `logIO` from Shared. Replace five error call sites.

**Step 6**: Edit `seihou-cli/src/Seihou/CLI/NewModule.hs`. Add Logger imports. Replace three error call sites.

**Step 7**: Edit `seihou-cli/src/Seihou/CLI/Validate.hs`. Add Logger imports. Replace one error call site.

**Step 8**: Edit `seihou-cli/src/Seihou/CLI/Status.hs`. Add Logger imports. Replace one error call site.

**Step 9**: Build and test:

    cabal build all
    cabal test all

Expected: all 439 tests pass.

**Step 10**: Manual verification:

    seihou vars nonexistent-module 2>/dev/null

Expected: no output on stdout (error went to stderr).

    seihou vars nonexistent-module 2>&1 >/dev/null

Expected: `[error]` prefixed messages on stderr.

    seihou install fake-url 2>/dev/null

Expected: no error output on stdout.

    seihou new-module INVALID 2>/dev/null

Expected: no error output on stdout.

    seihou validate-module /nonexistent/path 2>/dev/null

Expected: no error output on stdout.

    seihou status 2>/dev/null

Expected: either manifest output (stdout) or no output if manifest doesn't exist and error went to stderr. Actually, `status` with no manifest prints "No manifest found..." which is user output (stays on stdout). The error case only triggers on corrupt manifest JSON.


## Validation and Acceptance

### Automated

    cabal test all

All 439 tests pass. No new tests are needed because this change is purely a routing change — the same messages appear, just on stderr instead of stdout. The existing Logger tests in `LoggerSpec.hs` already cover the interpreter and filtering logic.

### Manual acceptance criteria

1. **Error messages go to stderr**: Run `seihou vars nonexistent-module` and redirect stderr to /dev/null: `seihou vars nonexistent-module 2>/dev/null`. No output should appear (the error was suppressed). Run again without redirect: the `[error]` prefixed messages appear.

2. **User output stays on stdout**: Run `seihou status` in a directory with a manifest. The manifest display appears on stdout. Run `seihou status 2>/dev/null` — the same output appears (stderr redirect has no effect on user output).

3. **No behavior change for Init**: Run `seihou init`. Output is unchanged — success messages on stdout, no Logger prefixes.

4. **Install error on stderr**: Run `seihou install https://invalid-url.example.com/fake.git 2>/dev/null`. No error output appears on stdout.

5. **All tests pass**: `cabal test all` shows 439 tests passing.


## Idempotence and Recovery

All changes are mechanical substitutions of `TIO.putStrLn` with `logIO LogNormal (logError ...)`. If a handler is partially migrated, it still compiles and works — unmigrated calls print to stdout as before. Building and testing can be repeated freely. If Milestone 2 fails partway, the Milestone 1 commit (shared helpers) is independently valid and useful.


## Interfaces and Dependencies

### Modified modules

In `seihou-cli/src/Seihou/CLI/Shared.hs`, add:

    logIO :: LogLevel -> Eff '[Logger, IOE] () -> IO ()
    unwrapConfig :: (IOE :> es) => LogLevel -> Either ConfigError a -> Eff es a

In `seihou-cli/src/Seihou/CLI/Run.hs`, remove local `logIO` and `unwrapConfig` definitions. Import them from `Shared`.

In `seihou-cli/src/Seihou/CLI/Install.hs`, `Vars.hs`, `NewModule.hs`, `Validate.hs`, `Status.hs`, add imports for `logIO` from `Shared` and `logError` from `Seihou.Effect.Logger`. Replace error `TIO.putStrLn` calls with `logIO LogNormal (logError ...)`.

### Dependencies

No new library dependencies. Uses existing:
- `effectful-core` (already a dependency of seihou-cli via seihou-core) — for `Eff`, `IOE`, `runEff`, `liftIO`
- `Seihou.Effect.Logger` — for `Logger`, `logError`
- `Seihou.Effect.LoggerInterp` — for `runLoggerIO`
- `Seihou.Core.Types` — for `LogLevel`
