---
slug: logger-effect-interpreters
title: "Wire the Logger Effect into the CLI"
kind: exec-plan
created_at: 2026-03-03T16:05:46Z
---


# Wire the Logger Effect into the CLI

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

The seihou CLI currently prints all its output — module composition progress, warnings,
errors, command execution, and result summaries — directly to stdout via `TIO.putStrLn`.
There is no way to control the verbosity of this output. A `Logger` algebraic effect is
already defined in the codebase (`seihou-core/src/Seihou/Effect/Logger.hs`) with four
log levels (Debug, Info, Warn, Error), but it has no interpreters and is not used
anywhere.

After this change, the Logger effect will have two interpreters — an IO interpreter that
writes to stderr with configurable verbosity, and a pure interpreter that collects log
messages for testing. The primary CLI handler (`seihou run`) will use Logger for
informational and diagnostic output, and a new `--verbose` flag will control what gets
printed. The default verbosity shows warnings and errors. With `--verbose`, informational
messages (like module composition details) also appear. Debug-level messages (like shell
command invocations) only appear with `--verbose`.

The user can observe the change by running `seihou run <module> --verbose` and seeing
composition details and command execution lines that were previously always printed or
never printed, now controllable. Without `--verbose`, the CLI is quieter — it prints only
the final summary, user-facing reports (dry-run preview, diff), and errors/warnings.


## Progress

- [x] M1-1: Create `LoggerInterp.hs` — IO interpreter with verbosity filtering (2026-03-03)
- [x] M1-2: Create `LoggerPure.hs` — pure interpreter collecting messages in state (2026-03-03)
- [x] M1-3: Register both modules in `seihou-core/seihou-core.cabal` + add `LogLevel` to Types.hs (2026-03-03)
- [x] M1-4: Write tests in `LoggerSpec.hs`, register in test `Main.hs` (2026-03-03)
- [x] M1-5: Build and test seihou-core — 439 tests pass (2026-03-03)
- [x] M2-1: Add `LogLevel` type to `Seihou.Core.Types` (done in M1-3) (2026-03-03)
- [x] M2-2: Add `--verbose` flag to `RunOpts` in `Commands.hs` and its parser (2026-03-03)
- [x] M2-3: Replace informational `TIO.putStrLn` calls in `Run.hs` with Logger calls (2026-03-03)
- [x] M2-4: Thread Logger via `logIO` helper — no effect stack changes needed (2026-03-03)
- [x] M2-5: Build and test all — 439 tests pass, clean build (2026-03-03)
- [x] M2-6: Manual verification — errors appear at default level, --help shows -v/--verbose (2026-03-03)


## Surprises & Discoveries

- GHC2024 does not bring `Control.Monad.when` into scope by default. Had to add
  an explicit `import Control.Monad (when)` in LoggerInterp.hs. Other effect
  interpreters in the codebase avoid `when` entirely.

- The `logIO` helper pattern turned out simpler than initially planned. No need
  to modify existing effect stacks or use `raise` — each `logIO` call runs its
  own ephemeral `runEff $ runLoggerIO level` block. This is slightly more
  allocation than threading a single Logger through the entire function, but
  avoids restructuring `handleRun`'s multiple independent `runEff` blocks.

- The `executeCommand` helper previously used `stdout`/`stderr` as variable names
  shadowing `System.IO` imports. Renamed to `cmdOut`/`cmdErr` to avoid confusion
  now that the module imports `System.IO.stderr` indirectly via Logger.


## Decision Log

- Decision: The IO interpreter writes to stderr, not stdout.
  Rationale: stdout is reserved for structured program output (dry-run preview, diff
  report, summary line). Diagnostic messages (composition info, warnings, command
  execution traces) belong on stderr so they do not pollute piped output. This follows
  the Unix convention where `program 2>/dev/null` suppresses diagnostics while
  preserving data.
  Date: 2026-03-03

- Decision: Introduce a `LogLevel` type in `Seihou.Core.Types` rather than using a
  `Bool` for verbosity.
  Rationale: A dedicated type (`LogQuiet`, `LogNormal`, `LogVerbose`) is more expressive
  than a boolean and extensible if a `--quiet` flag is added later. The IO interpreter
  receives this level and filters messages accordingly.
  Date: 2026-03-03

- Decision: Only wire Logger into `handleRun` in this plan. Other CLI handlers (init,
  install, vars, status, new-module, validate-module) are left for a follow-up.
  Rationale: `handleRun` is by far the most complex handler and benefits the most from
  structured logging. Wiring all seven handlers at once would bloat the plan without
  adding proportional value. The interpreters and patterns established here make future
  wiring mechanical.
  Date: 2026-03-03

- Decision: Default verbosity is `LogNormal`, which shows Warn and Error. Info messages
  require `--verbose`. Debug messages also require `--verbose`.
  Rationale: The current CLI already prints composition details and command traces
  unconditionally, which is noisy for experienced users. Making the default quieter
  improves the common case while `--verbose` preserves full output for debugging.
  Date: 2026-03-03

- Decision: Keep user-facing structured output (dry-run preview, diff report, summary
  line, conflict prompts) as direct `TIO.putStrLn` calls. Only replace diagnostic and
  progress messages with Logger.
  Rationale: These are not "log messages" — they are the primary program output the user
  requested. Routing them through Logger would make them subject to verbosity filtering,
  which would be wrong (e.g., `--dry-run` output should always appear).
  Date: 2026-03-03

- Decision: Use ephemeral `logIO` calls rather than threading Logger through effect stacks.
  Rationale: `handleRun` uses five separate `runEff` blocks. Wrapping the entire function
  in a single Logger effect block would require restructuring all sub-blocks to use `raise`
  or nested interpreters. The `logIO` pattern is simpler, self-contained, and sufficient
  since log calls happen in plain IO between effect blocks.
  Date: 2026-03-03


## Outcomes & Retrospective

Both milestones completed in two commits:

1. `c3ff15d` — M1: Logger interpreters + tests (6 files, +160 lines)
2. `d89cdd0` — M2: Wire into CLI with --verbose flag (2 files, +54/-42 lines)

All 439 tests pass. The Logger effect is now fully operational in `handleRun`.
Diagnostic messages (module composition, command traces) route through Logger
and only appear with `--verbose`. Errors and warnings appear at the default
`LogNormal` level. User-facing output (dry-run preview, diff, summary) remains
on stdout via direct `TIO.putStrLn`.

The `logIO` helper pattern works well for incremental adoption — other handlers
(init, install, vars, status, new-module, validate-module) can adopt Logger
by importing `logIO` and the Logger helpers without restructuring their code.

No gaps remain for this plan's scope. Future work: wire Logger into other CLI
handlers, add a `--quiet` flag (mapped to `LogQuiet`), and consider structured
log output (JSON) for machine-parseable diagnostics.


## Context and Orientation

### The Logger effect

The file `seihou-core/src/Seihou/Effect/Logger.hs` defines a four-operation algebraic
effect using the effectful library. An "algebraic effect" in this codebase is a Haskell
data type that describes operations (like `LogInfo :: Text -> Logger m ()`) without
specifying how they execute. Separate "interpreter" modules provide the actual behavior —
one for real IO, one for pure testing.

The four operations are `LogDebug`, `LogInfo`, `LogWarn`, and `LogError`. Each takes a
`Text` message and returns `()`. Helper functions `logDebug`, `logInfo`, `logWarn`,
`logError` wrap each operation in a `send` call. The effect uses `Dynamic` dispatch,
meaning the handler is selected at runtime via the effect stack.

Currently, no interpreter exists. The effect is exposed in
`seihou-core/seihou-core.cabal` at line 35, but importing `logInfo` and calling it would
be a type error because there is no handler to run the effect.

### Interpreter patterns in this codebase

Every effect follows the same two-module pattern. The IO interpreter uses `interpret`
from `Effectful.Dispatch.Dynamic` and requires `(IOE :> es)` in its constraint. The
pure interpreter uses `reinterpret` to compose with a `State` effect, capturing output
in a record type. Both return the result of the effectful computation.

The IO console interpreter at `seihou-core/src/Seihou/Effect/ConsoleInterp.hs` is the
closest analogy. It writes to stdout/stderr via `liftIO` calls. The pure console
interpreter at `seihou-core/src/Seihou/Effect/ConsolePure.hs` uses a `ConsoleState`
record with `consoleInputs`, `consoleOutputs`, and `consoleErrors` fields, manipulated
via `get` and `modify` from `Effectful.State.Static.Local`.

### The CLI handler — `handleRun`

The file `seihou-cli/src/Seihou/CLI/Run.hs` contains `handleRun :: RunOpts -> IO ()`,
the most complex command handler. It runs the full generation pipeline: load modules,
resolve variables, compile plan, compute diff, handle conflicts, execute, update
manifest.

Throughout this function, `TIO.putStrLn` calls emit messages at various conceptual log
levels. The following table categorizes each call site in the current code. "User output"
means it should remain as a direct `TIO.putStrLn` call. "Logger candidate" means it
should be replaced with a Logger call.

Lines 51-54 (module not found error): Logger candidate — `logError`.
Lines 56-58 (circular dependency): Logger candidate — `logError`.
Line 59 (generic error): Logger candidate — `logError` (via `exitError` helper).
Lines 64-65 (composing N modules): Logger candidate — `logInfo`.
Lines 82-84 (variable resolution errors): Logger candidate — `logError`.
Lines 95-97 (plan compilation errors): Logger candidate — `logError`.
Lines 107 (composition warnings): Logger candidate — `logWarn`.
Line 124 (manifest read error): Logger candidate — `logError`.
Lines 136-138 (dry-run preview): User output — keep as-is.
Line 141 (diff report): User output — keep as-is.
Lines 150-152 (conflict error): User output — keep as-is (part of conflict UX).
Lines 201-207 (summary "N new, N modified..."): User output — keep as-is.
Line 291 (command execution trace): Logger candidate — `logDebug`.
Lines 298-300 (command failure): Logger candidate — `logError`.

### Effect stacks in `handleRun`

The function uses several distinct `runEff` blocks, each with its own effect stack:

Line 72: `runEff $ runConfigReader $ runConsole $ do ...` — variable resolution.
Line 116: `runEff $ runFilesystem $ runManifestStore manifestPath $ do ...` — diff.
Lines 145-147: `runEff $ runConsole $ resolveConflicts ...` — conflict resolution.
Line 176: `runEff $ runFilesystem $ runManifestStore manifestPath $ do ...` — execution.
Line 292: `runEff $ runProcessIO $ runProcess ...` — command execution.

To use Logger, each stack that needs logging must include `runLogger <level>` in its
effect composition. However, since most of the Logger calls will replace `TIO.putStrLn`
calls that currently live *outside* any effect block (i.e., in plain `IO`), the simpler
approach is to run one top-level `runLogger` early in `handleRun` and use `liftIO` to
call logger operations from the IO context. Actually, since `handleRun` itself is `IO`,
the cleanest approach is to create a helper `withLogger` that wraps the entire handler
body.

### CLI flag infrastructure

The file `seihou-cli/src/Seihou/CLI/Commands.hs` defines `RunOpts` (line 30) with eight
fields including `runDryRun`, `runForce`, etc. The parser at line 251 uses
optparse-applicative's `switch` combinator for boolean flags. Adding `--verbose` follows
the exact same pattern: add a `runVerbose :: Bool` field to `RunOpts` and a
`switch (long "verbose" ...)` to the parser.


## Plan of Work

### Milestone 1: Logger interpreters and tests

This milestone adds the two interpreter modules and comprehensive tests without touching
any CLI code. At the end, `cabal test seihou-core` passes with new tests that exercise
both interpreters, and the Logger effect can be run in IO or in pure tests.

#### M1-1: Create the IO interpreter

Create `seihou-core/src/Seihou/Effect/LoggerInterp.hs`. This module exports a single
function `runLoggerIO` that interprets the Logger effect by writing messages to stderr.
It accepts a `LogLevel` parameter that controls the minimum severity to print.

The `LogLevel` type will be defined in `Seihou.Core.Types` (see M2-1), but for
Milestone 1 we can use a simple `Int` threshold or define `LogLevel` immediately. Since
the type is small and Types.hs is the canonical location for shared types, we define it
there first.

The interpreter structure:

    module Seihou.Effect.LoggerInterp
      ( runLoggerIO,
      )
    where

    import Data.Text qualified as T
    import Effectful
    import Effectful.Dispatch.Dynamic
    import Seihou.Core.Types (LogLevel (..))
    import Seihou.Effect.Logger (Logger (..))
    import System.IO (hPutStrLn, stderr)

    runLoggerIO :: (IOE :> es) => LogLevel -> Eff (Logger : es) a -> Eff es a
    runLoggerIO level = interpret $ \_ -> \case
      LogDebug msg -> when' LogVerbose $ emit "[debug] " msg
      LogInfo msg  -> when' LogVerbose $ emit "[info]  " msg
      LogWarn msg  -> when' LogNormal  $ emit "[warn]  " msg
      LogError msg -> when' LogQuiet   $ emit "[error] " msg
      where
        when' minLevel action = when (level >= minLevel) action
        emit prefix msg = liftIO $ hPutStrLn stderr (T.unpack (prefix <> msg))

The filtering logic: each message has a minimum `LogLevel` at which it appears.
`LogError` appears at all levels (even `LogQuiet`). `LogWarn` appears at `LogNormal` and
above. `LogInfo` and `LogDebug` appear only at `LogVerbose`. The `LogLevel` ordering is
`LogQuiet < LogNormal < LogVerbose`, using a derived `Ord` instance.

#### M1-2: Create the pure interpreter

Create `seihou-core/src/Seihou/Effect/LoggerPure.hs`. This module exports
`runLoggerPure`, `LoggerState`, and `emptyLoggerState`.

    module Seihou.Effect.LoggerPure
      ( runLoggerPure,
        LoggerState (..),
        emptyLoggerState,
      )
    where

The state type captures all messages regardless of level, organized by severity:

    data LoggerState = LoggerState
      { logDebugMsgs :: [Text],
        logInfoMsgs  :: [Text],
        logWarnMsgs  :: [Text],
        logErrorMsgs :: [Text]
      }
      deriving stock (Eq, Show)

    emptyLoggerState :: LoggerState
    emptyLoggerState = LoggerState [] [] [] []

The interpreter appends each message to its corresponding list:

    runLoggerPure :: Eff (Logger : es) a -> Eff es (a, LoggerState)
    runLoggerPure = reinterpret (runState emptyLoggerState) handler
      where
        handler :: (State LoggerState :> es') => EffectHandler Logger es'
        handler _ = \case
          LogDebug msg -> modify (\s -> s {logDebugMsgs = logDebugMsgs s ++ [msg]})
          LogInfo msg  -> modify (\s -> s {logInfoMsgs = logInfoMsgs s ++ [msg]})
          LogWarn msg  -> modify (\s -> s {logWarnMsgs = logWarnMsgs s ++ [msg]})
          LogError msg -> modify (\s -> s {logErrorMsgs = logErrorMsgs s ++ [msg]})

This captures every message for test assertions, regardless of any filtering. Tests
verify that the right messages go to the right severity bucket.

#### M1-3: Register in cabal and add LogLevel type

Add `Seihou.Effect.LoggerInterp` and `Seihou.Effect.LoggerPure` to the
`exposed-modules` list in `seihou-core/seihou-core.cabal`, alphabetically near the
existing `Seihou.Effect.Logger` entry (around line 35).

Add `LogLevel` to `seihou-core/src/Seihou/Core/Types.hs`:

    data LogLevel = LogQuiet | LogNormal | LogVerbose
      deriving stock (Eq, Ord, Show, Generic)

Place it near the other small enums. Export it from the module header.

#### M1-4: Write tests

Create `seihou-core/test/Seihou/Effect/LoggerSpec.hs` with the standard test pattern.
Register it in `seihou-core/seihou-core.cabal` under `other-modules` and in
`seihou-core/test/Main.hs`.

Tests for the pure interpreter:

1. All four log levels are captured in separate fields.
2. Messages appear in order within each field.
3. Empty input produces empty state.

Tests for the IO interpreter (via captured stderr, or verified indirectly through the
pure interpreter since the filtering logic is what matters):

4. `LogVerbose` level captures all message types (test via pure interpreter with level
   filtering applied manually, or add an optional level parameter to the pure
   interpreter). Actually, since the pure interpreter does not filter, and the IO
   interpreter does, we should test the filtering logic. The cleanest approach: add a
   `runLoggerPureFiltered :: LogLevel -> ...` variant that applies the same filtering as
   the IO interpreter, or simply test the IO interpreter by capturing stderr. Since
   capturing stderr in tests is fragile, the better approach is to keep the pure
   interpreter unfiltered (for test assertions) and test the IO interpreter's filtering
   separately.

   Decision: test filtering via a helper `shouldLog :: LogLevel -> LogLevel -> Bool` that
   is extracted and tested directly. The IO interpreter calls this helper. This keeps the
   tests pure and fast.

5. `shouldLog LogVerbose LogVerbose` returns True.
6. `shouldLog LogNormal LogVerbose` returns False (Info needs Verbose, Normal is not
   enough).
7. `shouldLog LogNormal LogNormal` returns True (Warn at Normal level).
8. `shouldLog LogQuiet LogQuiet` returns True (Error always shows).
9. `shouldLog LogQuiet LogNormal` returns False (Warn needs Normal, Quiet is not enough).

#### M1-5: Build and test

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal build seihou-core
    cabal test seihou-core

Expected: all existing tests pass plus new LoggerSpec tests.

### Milestone 2: Wire Logger into `handleRun`

This milestone modifies the CLI to use the Logger effect. At the end, `seihou run` has a
`--verbose` flag, diagnostic messages go through Logger, and the default output is
quieter.

#### M2-1: Add `--verbose` flag

In `seihou-cli/src/Seihou/CLI/Commands.hs`, add `runVerbose :: Bool` to `RunOpts` (after
`runNamespace`). Add `switch (long "verbose" <> short 'v' <> help "Show detailed progress messages")`
to the parser at line 270.

#### M2-2: Replace diagnostic `TIO.putStrLn` calls with Logger

In `seihou-cli/src/Seihou/CLI/Run.hs`, the following changes are needed. Since most of
the Logger calls happen outside effect blocks (they're in plain `IO` after pattern
matching), the approach is to wrap the body of `handleRun` in a single
`runEff $ runLoggerIO level $ do ...` block. Inside that block, the existing `runEff`
sub-blocks are replaced with `raise`-based composition or, more practically, we call
`liftIO` to bridge between the Logger effect context and the sub-stacks.

Actually, a simpler and less invasive approach: since the effect sub-blocks in
`handleRun` each call `runEff` independently, and Logger calls happen in between these
blocks (in plain IO), the cleanest approach is to create a thin IO wrapper that the
caller passes in. Specifically, define:

    type LogIO = Text -> IO ()

    mkLogDebug, mkLogInfo, mkLogWarn, mkLogError :: LogLevel -> LogIO

These are simple functions that check the level and write to stderr. No effect system
needed for the IO calls — the effect system is for code that composes with other effects.
The `handleRun` function creates these loggers from the verbosity flag and passes them
to helpers.

Wait — this defeats the purpose of having an algebraic effect. The effect system shines
when you want to test code that logs by swapping in a pure interpreter. Since `handleRun`
is fundamentally `IO`, the cleanest integration is:

1. For Logger calls inside existing effect blocks (like `runEff $ runConsole $ ...`), add
   `runLoggerIO level` to the effect stack.
2. For Logger calls outside effect blocks (plain IO), use a small helper that runs a
   one-shot Logger action: `logIO level (logInfo msg)`.

The helper:

    logIO :: LogLevel -> Eff '[Logger, IOE] () -> IO ()
    logIO level action = runEff $ runLoggerIO level action

This lets us write `logIO level (logInfo "Composing 3 modules:")` in plain IO context.

The changes to `handleRun` line by line:

Lines 51-54 (module not found): Replace `TIO.putStrLn` with `logIO level . logError`.
Lines 56-58 (circular dep): Same — `logIO level . logError`.
Line 59: The `exitError` helper already calls `TIO.putStrLn` — modify it to accept a
log function.
Lines 64-65 (composing modules): Replace with `logIO level . logInfo`.
Lines 82-84 (var errors): Replace with `logIO level . logError`.
Lines 95-97 (plan errors): Replace with `logIO level . logError`.
Line 107 (`printWarning`): Modify the helper to use `logIO level . logWarn`.
Line 124 (manifest error): Replace with `logIO level . logError`.
Line 291 (command trace): Replace with `logIO level . logDebug`.
Lines 298-300 (command failure): Replace with `logIO level . logError`.

Compute `level` early:

    let level = if runVerbose runOpts then LogVerbose else LogNormal

#### M2-3: Build and test all

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal build all
    cabal test all

All 432+ existing tests must pass.

#### M2-4: Manual verification

Run `seihou run` with and without `--verbose` and observe the difference:

Without `--verbose`: Only the summary line, dry-run preview, diff report, and
error/warning messages appear. Module composition details and command traces are
suppressed.

With `--verbose`: Module composition details ("Composing 3 modules:"), command execution
traces ("  run  echo hello"), and other informational messages appear on stderr.


## Concrete Steps

### Milestone 1

**Working directory**: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

**Step 1**: Add `LogLevel` type to `seihou-core/src/Seihou/Core/Types.hs`. Add it to the
module's export list.

**Step 2**: Create `seihou-core/src/Seihou/Effect/LoggerInterp.hs` with `runLoggerIO`
and the `shouldLog` helper (exported for testing).

**Step 3**: Create `seihou-core/src/Seihou/Effect/LoggerPure.hs` with `runLoggerPure`,
`LoggerState`, and `emptyLoggerState`.

**Step 4**: Add `Seihou.Effect.LoggerInterp` and `Seihou.Effect.LoggerPure` to
`seihou-core/seihou-core.cabal` exposed-modules.

**Step 5**: Create `seihou-core/test/Seihou/Effect/LoggerSpec.hs`. Add to
`seihou-core/seihou-core.cabal` other-modules and `seihou-core/test/Main.hs`.

**Step 6**: Build and test:

    cabal build seihou-core
    cabal test seihou-core

Expected: all tests pass.

### Milestone 2

**Step 7**: Add `runVerbose :: Bool` to `RunOpts` in
`seihou-cli/src/Seihou/CLI/Commands.hs`. Add the parser entry.

**Step 8**: In `seihou-cli/src/Seihou/CLI/Run.hs`:
- Add imports for `Seihou.Effect.Logger`, `Seihou.Effect.LoggerInterp`, and
  `Seihou.Core.Types (LogLevel (..))`.
- Add `logIO` helper.
- Compute `level` from `runVerbose runOpts`.
- Replace `TIO.putStrLn` diagnostic calls with `logIO level` calls.
- Update `printWarning`, `exitError`, and `executeCommand` helpers to accept and use
  `level`.

**Step 9**: Build and test:

    cabal build all
    cabal test all

Expected: all tests pass.

**Step 10**: Manual verification (see M2-4 above).


## Validation and Acceptance

### Automated

    cabal test all

All tests must pass. The new `Seihou.Effect.Logger` test group should contain tests
covering: pure interpreter captures all four levels, messages appear in order, empty
input produces empty state, and `shouldLog` filtering logic for all level combinations.

### Manual acceptance criteria

1. **Default output is quieter**: Run `seihou run <module> --var project.name=test` (a
   module with multiple composed modules). The composition details ("Composing N
   modules:") should NOT appear. Only the summary line appears.

2. **Verbose output shows details**: Run `seihou run <module> --var project.name=test --verbose`.
   The composition details, command traces, and other info-level messages appear on
   stderr.

3. **Errors still appear at default level**: Provide a non-existent module name. The
   error message still appears without `--verbose`.

4. **Warnings still appear at default level**: Run a composition that produces a warning
   (e.g., file overwritten by a later module). The warning still appears without
   `--verbose`.

5. **Piped output is clean**: Run `seihou run <module> --dry-run 2>/dev/null`. Only the
   dry-run preview appears on stdout. All log messages go to stderr and are suppressed
   by the redirect.


## Idempotence and Recovery

All changes are additive. The new interpreter files do not modify any existing file's
behavior. The Logger calls in `handleRun` replace `TIO.putStrLn` calls one-to-one; if
a call is missed, it remains as direct IO output (which is the current behavior). The
`--verbose` flag defaults to `False`, preserving existing behavior for users who do not
use it.

Building and testing can be repeated freely. If a step fails partway through Milestone 2,
the code can be reverted to the Milestone 1 commit (which only added new files and did
not modify existing ones).


## Interfaces and Dependencies

### New types

In `seihou-core/src/Seihou/Core/Types.hs`:

    data LogLevel = LogQuiet | LogNormal | LogVerbose
      deriving stock (Eq, Ord, Show, Generic)

### New modules

In `seihou-core/src/Seihou/Effect/LoggerInterp.hs`:

    runLoggerIO :: (IOE :> es) => LogLevel -> Eff (Logger : es) a -> Eff es a
    shouldLog :: LogLevel -> LogLevel -> Bool

In `seihou-core/src/Seihou/Effect/LoggerPure.hs`:

    runLoggerPure :: Eff (Logger : es) a -> Eff es (a, LoggerState)

    data LoggerState = LoggerState
      { logDebugMsgs :: [Text],
        logInfoMsgs  :: [Text],
        logWarnMsgs  :: [Text],
        logErrorMsgs :: [Text]
      }

    emptyLoggerState :: LoggerState

### Modified modules

In `seihou-cli/src/Seihou/CLI/Commands.hs`:

    data RunOpts = RunOpts
      { ...existing fields...,
        runVerbose :: Bool
      }

In `seihou-cli/src/Seihou/CLI/Run.hs`:

    logIO :: LogLevel -> Eff '[Logger, IOE] () -> IO ()

### Dependencies

No new library dependencies. Uses:
- `effectful-core` (already a dependency) — for `interpret`, `reinterpret`, `State`
- `System.IO` (base) — for `hPutStrLn stderr`
- `Seihou.Core.Types` — for `LogLevel`
