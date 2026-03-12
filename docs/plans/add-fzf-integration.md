# Add fzf Integration for Interactive Selection

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, seihou users can omit the MODULE positional argument from commands like `run` and `vars` and instead get a fuzzy-searchable picker powered by fzf. The `install` command's multi-module selection also upgrades from a numbered-list prompt to fzf. This makes the CLI dramatically more discoverable and pleasant to use: rather than remembering exact module names, users type a few characters and select. When fzf is not installed or the session is non-interactive (piped, CI), the CLI falls back to existing behavior — no breakage.


## Progress

- [x] M1: Core fzf module — `Seihou.Fzf` types, options, process spawning, config detection (2026-03-12)
- [x] M2: Fzf effect — `Seihou.Effect.Fzf` effect definition with effectful, real and pure interpreters (2026-03-12)
- [x] M3: Module selector — `Seihou.Fzf.Selector.Module` for picking from discovered modules (2026-03-12)
- [x] M4: Wire into `run` and `vars` — make MODULE argument optional, fall back to fzf picker (2026-03-12)
- [x] M5: Wire into `install` — replace `promptModuleSelection` with fzf picker for registry modules (2026-03-12)
- [x] M6: Wire into `context set` — pick from available context directories (2026-03-12)
- [ ] M7: Upgrade choice prompts — use fzf for `promptWithChoices` when available (deferred)
- [x] M8: Tests and validation — 16 new tests, all 48 pass (2026-03-12)


## Surprises & Discoveries

- The `seihou-cli` cabal file did not have `TypeFamilies` in its default-extensions, unlike `seihou-core`. This extension is required for `type instance DispatchOf Fzf = Dynamic`. Added it to the library, executable, and test-suite sections.

- Importing `Seihou.Core.Types (Module)` with an explicit import list does not bring `HasField` instances into scope for `OverloadedRecordDot` access. The fix is to use an unqualified import: `import Seihou.Core.Types`. This is because `DuplicateRecordFields` requires the full module to be imported for GHC to resolve ambiguous field names like `name` (shared by `Module`, `VarDecl`, and other types in the same module).


## Decision Log

- Decision: Model fzf as an effectful Effect rather than raw IO.
  Rationale: The rest of seihou uses effectful for all side effects. An `Fzf` effect keeps the architecture consistent, makes handlers testable with a pure interpreter that returns canned selections, and lets us inject `FzfConfig` detection into the effect interpreter rather than threading it through every handler. The reference pattern (raw IO with `FzfConfig` threaded manually) would work but would diverge from the codebase style.
  Date: 2026-03-12

- Decision: Make MODULE a truly optional argument in `run` and `vars` rather than adding a separate `--interactive` flag.
  Rationale: This follows the principle of least surprise. If the user is in a terminal and has fzf, omitting the argument should Just Work. Adding a flag would be redundant friction. When MODULE is omitted and fzf is unavailable, the existing optparse-applicative error message ("Missing: MODULE") still fires, so there is no silent failure.
  Date: 2026-03-12

- Decision: Keep the core fzf process-spawning logic in a plain module (`Seihou.Fzf`) separate from the effect, so the effect interpreter delegates to it. This mirrors how `Seihou.Core.Module` is pure logic and the effects wrap it.
  Rationale: Separation of concerns. The fzf subprocess management is inherently IO but does not need the full effect stack. The effect layer adds testability and integration with the rest of the app.
  Date: 2026-03-12

- Decision: Place all fzf code in `seihou-cli`, not `seihou-core`.
  Rationale: fzf is a CLI-specific interactive concern. The core library should remain UI-agnostic. Module discovery functions already exist in core and can be called from CLI code that then feeds results to fzf.
  Date: 2026-03-12

- Decision: Scope to single-select for v1. Multi-select and expect-key toggling (the reference pattern's view toggle) are deferred.
  Rationale: The immediate UX wins come from single-entity picking (choose a module, choose a context). Multi-select and toggle views add complexity without clear use cases in seihou's current command set. They can be added later by extending `FzfOpts` and `FzfResult`.
  Date: 2026-03-12

- Decision: Defer M7 (upgrade choice prompts) to a follow-up.
  Rationale: `promptWithChoices` lives in `seihou-core` and uses the `Console` effect. Integrating fzf there would either require adding fzf as a core dependency (violating the design principle that core is UI-agnostic) or building a prompt-interception layer at the CLI level. Both approaches are non-trivial and independent of the other milestones. The main UX wins (module/context/registry selection) are already delivered.
  Date: 2026-03-12


## Outcomes & Retrospective

M1-M6 and M8 are complete. M7 (upgrade choice prompts) is deferred — it requires either modifying `seihou-core`'s prompt infrastructure or building an interception layer in the CLI handlers, both of which are non-trivial and can be done independently.

**What was achieved:**
- Core fzf module (`Seihou.Fzf`) with composable options, index-based selection, and subprocess management
- Effectful `Fzf` effect with real IO and pure test interpreters
- Module selector that discovers and formats all available modules for fzf
- `seihou run` and `seihou vars` now accept MODULE as optional — fzf picker when omitted
- `seihou install` uses fzf for registry module selection (with numbered-list fallback)
- `seihou context set` uses fzf for context directory selection
- 16 new tests covering optsToArgs, Monoid laws, pure interpreter, and candidate formatting

**Files created:**
- `seihou-cli/src/Seihou/Fzf.hs`
- `seihou-cli/src/Seihou/Effect/Fzf.hs`
- `seihou-cli/src/Seihou/Effect/FzfInterp.hs`
- `seihou-cli/src/Seihou/Fzf/Selector.hs`
- `seihou-cli/src/Seihou/Fzf/Selector/Module.hs`
- `seihou-cli/test/Seihou/FzfSpec.hs`

**Files modified:**
- `seihou-cli/seihou-cli.cabal` — new modules, TypeFamilies extension, process dep in library
- `seihou-cli/src/Seihou/CLI/Commands.hs` — RunOpts.runModule, VarsOpts.varsModule, ContextSet now use Maybe
- `seihou-cli/src/Seihou/CLI/Run.hs` — fzf module resolution
- `seihou-cli/src/Seihou/CLI/Vars.hs` — fzf module resolution
- `seihou-cli/src/Seihou/CLI/Install.hs` — fzf registry selection
- `seihou-cli/src/Seihou/CLI/Context.hs` — fzf context selection
- `seihou-cli/test/Main.hs` — added FzfSpec


## Context and Orientation

Seihou is a composable, type-safe project scaffolding tool. It is a Haskell project using GHC 9.12.2 with GHC2024, split into two packages: `seihou-core` (library with domain logic, effects, interpreters) and `seihou-cli` (executable with CLI parsing and command handlers).

The project uses the `effectful` library for all side effects. Effects are defined in `seihou-core/src/Seihou/Effect/` as Dynamic dispatch effects (one file per effect, e.g., `Console.hs`, `Filesystem.hs`, `Logger.hs`). Interpreters live alongside them in `*Interp.hs` files. The common pattern is:

    -- Effect definition
    data MyEffect :: Effect where
      SomeOp :: Arg -> MyEffect (Eff es) Result
      type instance DispatchOf MyEffect = Dynamic

    -- Smart constructor
    someOp :: (MyEffect :> es) => Arg -> Eff es Result
    someOp arg = send (SomeOp arg)

    -- Interpreter
    runMyEffect :: (IOE :> es) => Eff (MyEffect : es) a -> Eff es a
    runMyEffect = interpret $ \_ -> \case
      SomeOp arg -> liftIO $ ...

The `Seihou.Prelude` module (at `seihou-core/src/Seihou/Prelude.hs`) re-exports effectful primitives (`Eff`, `runEff`, `(:>)`, `IOE`, `Effect`, `Dynamic`, `send`, `interpret`, `reinterpret`), containers (`Map`, `Set`), `Text`, optics combinators, and `FilePath`/`(</>)`.

CLI commands are parsed in `seihou-cli/src/Seihou/CLI/Commands.hs` using `optparse-applicative`. The `Command` ADT has constructors for each subcommand. Handlers live in separate modules under `Seihou.CLI.*` and are dispatched from `Main.hs`.

Key modules and module discovery:

- `ModuleName` is a `newtype` around `Text` in `seihou-core/src/Seihou/Core/Types.hs`.
- `discoverAllModules :: [FilePath] -> IO [DiscoveredModule]` in `seihou-core/src/Seihou/Core/Module.hs` scans search paths for `module.dhall` files and returns results tagged with their source (`SourceProject`, `SourceUser`, `SourceInstalled`).
- `DiscoveredModule` contains `discoveredResult :: Either ModuleLoadError Module`, `discoveredSource :: ModuleSource`, and `discoveredDir :: FilePath`.
- `defaultSearchPaths` in `seihou-core/src/Seihou/Core/Config.hs` returns `[".seihou/modules/", "~/.config/seihou/modules/", "~/.config/seihou/installed/"]`.
- `Module` has fields `name :: ModuleName` and `description :: Maybe Text`.

The `install` command already has interactive selection via `promptModuleSelection` in `seihou-cli/src/Seihou/CLI/Install.hs` (lines 157-199). It displays a numbered list and reads comma-separated indices. This is the code fzf will replace.

Variable choice prompts use `promptWithChoices` in `seihou-core/src/Seihou/Interaction/Prompt.hs` (lines 125-154), which displays numbered options and reads a selection.

Context directories live at `~/.config/seihou/contexts/<name>/config.dhall`. The `context set` command currently requires the name as a positional argument.

The `seihou-cli` cabal file is at `seihou-cli/seihou-cli.cabal`. It already depends on `process` and `directory`, which are the only system libraries needed for fzf integration.

The reference pattern for fzf integration is documented at `/Users/shinzui/Keikaku/bokuno/haskell-jitsurei/cli/fzf-integration.md`. It describes: composable `FzfOpts` via `Monoid`, index-based candidate selection (hidden indices piped to fzf, parsed back from output), `FzfConfig` for availability detection, `FzfResult` ADTs, and per-entity selector modules. This plan adapts that pattern to seihou's effectful architecture.


## Plan of Work

The work is organized into eight milestones. Each builds on the previous one and leaves the codebase in a compiling, working state.


### Milestone 1: Core fzf Module

This milestone creates the foundational types and process-spawning logic in a new module `Seihou.Fzf` inside `seihou-cli`. At the end, the module compiles and exports all types needed by later milestones, but nothing in the application uses it yet.

Create the file `seihou-cli/src/Seihou/Fzf.hs` with the following contents.

**FzfConfig** — detected once at startup, describes whether fzf is available:

    data FzfConfig = FzfConfig
      { fzfBinary        :: !FilePath
      , fzfAvailable     :: !Bool
      , stdinIsTerminal  :: !Bool
      , ttyAvailable     :: !Bool
      }
      deriving stock (Eq, Show)

    detectFzfConfig :: IO FzfConfig
    -- Uses System.Directory.findExecutable "fzf", System.IO.hIsTerminalDevice stdin,
    -- and a /dev/tty open check.

    isFzfUsable :: FzfConfig -> Bool
    isFzfUsable cfg = fzfAvailable cfg && (stdinIsTerminal cfg || ttyAvailable cfg)

**FzfOpts** — composable options with a `Monoid` instance, following the reference pattern exactly:

    data FzfOpts = FzfOpts
      { fzfPrompt  :: !(Maybe Text)
      , fzfHeader  :: !(Maybe Text)
      , fzfPreview :: !(Maybe Text)
      , fzfHeight  :: !(Maybe Text)
      , fzfAnsi    :: !Bool
      , fzfNoSort  :: !Bool
      }

Smart constructors: `withPrompt`, `withHeader`, `withHeight`, `withAnsi`, `withNoSort`, `withPreview`. The `Semigroup` instance is right-biased for `Maybe` fields and sticky-true for `Bool` fields. The `Monoid` instance returns all-`Nothing`/all-`False`.

An `optsToArgs :: FzfOpts -> [String]` function converts to CLI arguments for the fzf process.

**Candidate** — wraps a display line and a value:

    data Candidate a = Candidate
      { candidateDisplay :: !Text
      , candidateValue   :: !a
      }
      deriving stock (Functor)

**FzfResult** — single-selection result:

    data FzfResult a
      = FzfSelected  !a
      | FzfNoMatch
      | FzfCancelled
      | FzfError     !Text
      deriving stock (Functor)

**runFzf** — the core function that spawns fzf as a subprocess:

    runFzf :: FzfConfig -> FzfOpts -> [Candidate a] -> IO (FzfResult a)

This function implements the index-based selection protocol from the reference pattern: zip candidates with integer indices, build a `Map Int a`, write `"<index>\t<display>"` lines to fzf's stdin, pass `--with-nth=2..` and `-1` (auto-select single candidate), parse the index from fzf's output on success. Exit codes: 0 = success, 1 = no match, 130 = cancelled (Esc/Ctrl-C). Use `delegate_ctlc = True` and `std_err = Inherit`.

Add `Seihou.Fzf` to the `exposed-modules` of the `seihou-cli-internal` library in `seihou-cli/seihou-cli.cabal`. No new cabal dependencies are needed — `process`, `directory`, `containers`, and `text` are already present.

**Acceptance:** The project compiles with `cabal build seihou-cli`. No runtime behavior changes.

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal build seihou-cli


### Milestone 2: Fzf Effect

This milestone wraps the core fzf logic in an effectful `Effect` so it integrates with seihou's effect stack.

Create `seihou-cli/src/Seihou/Effect/Fzf.hs` with a Dynamic dispatch effect:

    data Fzf :: Effect where
      SelectOne :: FzfOpts -> [Candidate a] -> Fzf (Eff es) (FzfResult a)
      IsFzfAvailable :: Fzf (Eff es) Bool
      type instance DispatchOf Fzf = Dynamic

    selectOne :: (Fzf :> es) => FzfOpts -> [Candidate a] -> Eff es (FzfResult a)
    selectOne opts cs = send (SelectOne opts cs)

    isFzfAvailable :: (Fzf :> es) => Eff es Bool
    isFzfAvailable = send IsFzfAvailable

Create `seihou-cli/src/Seihou/Effect/FzfInterp.hs` with the real interpreter:

    runFzfIO :: (IOE :> es) => FzfConfig -> Eff (Fzf : es) a -> Eff es a
    runFzfIO cfg = interpret $ \_ -> \case
      SelectOne opts candidates -> liftIO $ runFzf cfg opts candidates
      IsFzfAvailable -> pure (isFzfUsable cfg)

Create a pure interpreter for testing:

    runFzfPure :: Int -> Eff (Fzf : es) a -> Eff es a
    -- Always selects the candidate at the given index (or FzfNoMatch if out of bounds)

Add both modules to the cabal file.

**Acceptance:** Project compiles. No runtime changes yet.


### Milestone 3: Module Selector

Create `seihou-cli/src/Seihou/Fzf/Selector/Module.hs`. This module provides a function that discovers all available modules and presents them in an fzf picker.

    formatModuleCandidate :: DiscoveredModule -> Maybe (Candidate ModuleName)
    -- Returns Nothing for modules that failed to load.
    -- Display format: "<name>  <description>  [<source>]"
    -- where source is "project", "user", or "installed".
    -- Value is the ModuleName.

    defaultModuleOpts :: FzfOpts
    defaultModuleOpts = withPrompt "module> " <> withHeight "40%" <> withAnsi <> withNoSort

    selectModule :: (Fzf :> es, IOE :> es) => Eff es (FzfResult ModuleName)
    -- Calls discoverAllModules with defaultSearchPaths,
    -- formats candidates, delegates to selectOne.

This function uses `liftIO` for `discoverAllModules` (which is in IO) and the `Fzf` effect for `selectOne`.

Also create `seihou-cli/src/Seihou/Fzf/Selector.hs` as a re-export module:

    module Seihou.Fzf.Selector (module Seihou.Fzf.Selector.Module) where
    import Seihou.Fzf.Selector.Module

Add both modules to the cabal file.

**Acceptance:** Project compiles.


### Milestone 4: Wire into `run` and `vars`

This is the first user-visible milestone. After this, a user can type `seihou run` without arguments and get an fzf picker of available modules.

**Step 4a: Make MODULE optional in the parser.**

In `seihou-cli/src/Seihou/CLI/Commands.hs`, change:

- `RunOpts.runModule :: ModuleName` to `RunOpts.runModule :: Maybe ModuleName`
- In `runParser`, change `argument moduleNameReader (metavar "MODULE")` to `optional (argument moduleNameReader (metavar "MODULE"))`
- Similarly for `VarsOpts.varsModule` and `varsParser`

**Step 4b: Update `handleRun` in `seihou-cli/src/Seihou/CLI/Run.hs`.**

At the top of `handleRun`, before existing logic:

1. Call `detectFzfConfig` (once, at the entry point).
2. If `runModule` is `Nothing` and fzf is usable, call `selectModule` within a `runFzfIO cfg` block. On `FzfSelected name`, proceed with that module. On `FzfCancelled`, exit 0 silently. On `FzfNoMatch`, print "No modules found" and exit 1. On `FzfError msg`, print error and exit 1.
3. If `runModule` is `Nothing` and fzf is not usable, print a usage error ("MODULE is required when fzf is not available") and exit 1.
4. If `runModule` is `Just name`, proceed as before.

**Step 4c: Update `handleVars` in `seihou-cli/src/Seihou/CLI/Vars.hs`.**

Same pattern as `handleRun` — resolve `Maybe ModuleName` to `ModuleName` via fzf or error.

**Acceptance:**

Build and run without arguments:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal build seihou-cli
    cabal run seihou -- run

Expected: fzf picker appears showing available modules (if any exist in search paths and fzf is installed). Selecting one proceeds with the run. Pressing Esc cancels cleanly. Providing a module name as before still works identically.

    cabal run seihou -- run haskell-base --dry-run

Expected: works exactly as before (the `Just` path).

    echo "test" | cabal run seihou -- run

Expected: prints error about MODULE being required (stdin is not a terminal, fzf is not usable).


### Milestone 5: Wire into `install`

Replace the numbered-list `promptModuleSelection` in `seihou-cli/src/Seihou/CLI/Install.hs` with an fzf-based multi-select picker when fzf is available, falling back to the existing numbered prompt otherwise.

Create a new selector function (in `Seihou.Fzf.Selector.Module` or a new `Seihou.Fzf.Selector.Registry` module):

    formatRegistryCandidate :: RegistryEntry -> Candidate RegistryEntry
    -- Display: "<name>  <description>  [<tags>]"

    selectRegistryModules :: (Fzf :> es) => [RegistryEntry] -> Eff es (FzfResult RegistryEntry)
    -- For now, single-select. User can run install multiple times or use --all.

In `handleInstall`, at the point where `promptModuleSelection` is called (when the user provided neither `--module` nor `--all` for a multi-module registry):

1. Detect fzf config.
2. If fzf is usable, use `selectRegistryModules`.
3. Otherwise, fall back to existing `promptModuleSelection`.

**Acceptance:**

    cabal run seihou -- install https://github.com/some/registry.git

Expected: if fzf is available, an fzf picker shows registry modules. Selecting one installs it. Without fzf, the old numbered prompt appears.


### Milestone 6: Wire into `context set`

Make the context name optional in `context set`. When omitted and fzf is available, scan `~/.config/seihou/contexts/` for subdirectories and present them in an fzf picker.

**Step 6a:** In `Commands.hs`, change `ContextSet Text` to `ContextSet (Maybe Text)` and make the argument optional in the parser.

**Step 6b:** In `handleContext` for the `ContextSet` case, resolve `Maybe Text` via fzf or error, similar to M4.

Create a context selector:

    selectContext :: (Fzf :> es, IOE :> es) => Eff es (FzfResult Text)
    -- Lists subdirectories of ~/.config/seihou/contexts/
    -- Each directory name is a candidate

**Acceptance:**

    cabal run seihou -- context set

Expected: fzf picker of available contexts. Selecting one sets it.


### Milestone 7: Upgrade Choice Prompts

In `seihou-core/src/Seihou/Interaction/Prompt.hs`, the `promptWithChoices` function displays a numbered list for variable choice selection. When fzf is available, use it instead.

This milestone is more nuanced because `promptWithChoices` lives in `seihou-core` and uses the `Console` effect, while fzf logic lives in `seihou-cli`. The cleanest approach: add an optional `FzfConfig` parameter (or a callback) to the prompting logic, or handle the fzf path at the CLI layer before falling through to the effectful prompt.

Concretely, in the `handleRun` flow where `resolveWithPrompts` is called, intercept variables with choices and resolve them via fzf before passing to the core resolution. This keeps fzf out of `seihou-core`.

**Acceptance:** When running a module that has a variable with choices and fzf is available, the user sees an fzf picker instead of a numbered list.


### Milestone 8: Tests and Validation

Write tests using the pure fzf interpreter (`runFzfPure`):

1. **Unit tests for `Seihou.Fzf`**: `optsToArgs` produces correct CLI arguments. `Monoid` laws hold for `FzfOpts`. Candidate formatting is correct.

2. **Integration tests for selectors**: Using `runFzfPure 0` (select first item), verify that `selectModule` returns the first discovered module's name. Using `runFzfPure (-1)` (out of bounds), verify `FzfNoMatch`.

3. **Parser tests**: Verify that `run` and `vars` parsers accept both `seihou run module-name` and `seihou run` (no argument).

Add test files under `seihou-cli/test/`.

**Acceptance:**

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal test seihou-cli

Expected: all tests pass.


## Concrete Steps

All commands are run from the repository root:

    /Users/shinzui/Keikaku/bokuno/seihou-project/seihou

After each milestone, verify compilation:

    cabal build seihou-cli

After M4 (first user-visible change), verify interactively:

    cabal run seihou -- run
    # Expected: fzf picker appears (if fzf is installed and modules exist)

    cabal run seihou -- run haskell-base --dry-run
    # Expected: works as before

After M8, run the test suite:

    cabal test seihou-cli


## Validation and Acceptance

The feature is complete when all of the following hold:

1. `seihou run` (no args, terminal, fzf installed) opens an fzf picker showing all available modules with names, descriptions, and source tags. Selecting one proceeds with the normal run flow. Pressing Esc exits cleanly with no error.

2. `seihou run haskell-base` works identically to before — explicit module names bypass fzf entirely.

3. `echo | seihou run` (non-interactive) prints a clear error about MODULE being required.

4. `seihou vars` (no args) behaves the same as `seihou run` regarding fzf selection.

5. `seihou install <url>` for a multi-module registry shows an fzf picker instead of a numbered list (when fzf is available), with fallback to the old numbered prompt otherwise.

6. `seihou context set` (no args) shows available contexts in fzf.

7. `cabal test seihou-cli` passes with tests covering the core fzf logic, selectors, and updated parsers.

8. All changes are in `seihou-cli` — `seihou-core` is unmodified (except possibly `promptWithChoices` in M7, which may stay as-is with the interception approach).


## Idempotence and Recovery

Every milestone is additive — new files are created and existing files are extended. No destructive changes occur until M4 changes the `RunOpts` type, at which point all call sites must be updated in the same commit to maintain compilation. If a milestone is partially completed, the Progress section will reflect what was done and what remains, and work can resume from there.

The fzf integration is purely optional at runtime. If fzf is not installed, all commands work exactly as they do today. This means the feature can be merged at any milestone boundary from M4 onward without breaking existing users.


## Interfaces and Dependencies

**No new cabal dependencies.** The existing `process`, `directory`, `containers`, and `text` packages suffice.

**System dependency:** fzf must be installed on the user's system for interactive selection. The CLI detects its absence gracefully and falls back.

**New modules and key signatures:**

In `seihou-cli/src/Seihou/Fzf.hs`:

    data FzfConfig
    detectFzfConfig :: IO FzfConfig
    isFzfUsable :: FzfConfig -> Bool

    data FzfOpts
    instance Semigroup FzfOpts
    instance Monoid FzfOpts
    withPrompt :: Text -> FzfOpts
    withHeader :: Text -> FzfOpts
    withHeight :: Text -> FzfOpts
    withAnsi :: FzfOpts
    withNoSort :: FzfOpts
    withPreview :: Text -> FzfOpts
    optsToArgs :: FzfOpts -> [String]

    data Candidate a
    data FzfResult a

    runFzf :: FzfConfig -> FzfOpts -> [Candidate a] -> IO (FzfResult a)

In `seihou-cli/src/Seihou/Effect/Fzf.hs`:

    data Fzf :: Effect where
      SelectOne :: FzfOpts -> [Candidate a] -> Fzf (Eff es) (FzfResult a)
      IsFzfAvailable :: Fzf (Eff es) Bool
      type instance DispatchOf Fzf = Dynamic

    selectOne :: (Fzf :> es) => FzfOpts -> [Candidate a] -> Eff es (FzfResult a)
    isFzfAvailable :: (Fzf :> es) => Eff es Bool

In `seihou-cli/src/Seihou/Effect/FzfInterp.hs`:

    runFzfIO :: (IOE :> es) => FzfConfig -> Eff (Fzf : es) a -> Eff es a
    runFzfPure :: Int -> Eff (Fzf : es) a -> Eff es a

In `seihou-cli/src/Seihou/Fzf/Selector/Module.hs`:

    formatModuleCandidate :: DiscoveredModule -> Maybe (Candidate ModuleName)
    defaultModuleOpts :: FzfOpts
    selectModule :: (Fzf :> es, IOE :> es) => Eff es (FzfResult ModuleName)

In `seihou-cli/src/Seihou/Fzf/Selector.hs`:

    -- Re-exports Seihou.Fzf.Selector.Module

**Modified types:**

In `seihou-cli/src/Seihou/CLI/Commands.hs`:

    -- RunOpts.runModule changes from ModuleName to Maybe ModuleName
    -- VarsOpts.varsModule changes from ModuleName to Maybe ModuleName
    -- ContextAction.ContextSet changes from Text to Maybe Text


## Where fzf Helps the UX — Summary

| Command | Current UX | With fzf |
|---------|-----------|----------|
| `seihou run` | Requires MODULE arg; user must know exact name | Fuzzy picker of all available modules |
| `seihou vars` | Requires MODULE arg | Same fuzzy picker |
| `seihou install <url>` (registry) | Numbered list, comma-separated input | Fuzzy search through registry modules |
| `seihou context set` | Requires context NAME arg | Picker of available context directories |
| Variable choice prompts | Numbered list during `run` | Fuzzy picker for choice variables |
| `seihou list` | Static text output | No change needed — already informational. Users who want filtering can pipe to fzf themselves. |
