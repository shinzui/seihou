# Extract Remaining Executable-Only CLI Helpers Identified by the Audit

MasterPlan: docs/masterplans/2-cli-library-first-convention.md

Intention: intention_01kq63sz0ced98e23qvad7zpnp

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this plan, the two known violations of the library-first convention that
require source-code restructuring (not just cabal edits) are resolved:

1. `Seihou.CLI.AgentLaunch` is split into a library module of the same name
   carrying the pure surface (`AgentContext`, `gatherAgentContext`,
   `agentDirsForSession`, `substitute`, the three tool-list constants, and the
   five `format*` helpers) and a new executable module
   `Seihou.CLI.AgentLaunchExec` carrying `launchAgent` and `launchAgentWith`
   (the two functions that call `findExecutable`, `rawSystem`, and
   `exitWith`/`exitFailure`).
2. `Seihou.CLI.Outdated`'s export list stops re-exporting types whose
   canonical homes are already in the library: `OriginInfo` lives in
   `Seihou.CLI.InstallShared`, and `OutdatedStatus`, `OutdatedEntry`,
   `CheckStats`, and `compareVersions` live in `Seihou.CLI.VersionCompare`.
   Any consumer that currently imports those names from `Seihou.CLI.Outdated`
   is updated to import from the canonical site.

Why this matters: after sibling plan
`docs/plans/19-restructure-cli-cabal-library-first.md` makes the executable
depend on the library, `AgentLaunch`'s pure surface becomes test-reachable
the moment it sits in the library. Today it is in the executable target only,
so the test suite (which depends on `seihou-cli-internal` and not on the
executable) cannot exercise `substitute`, the `format*` helpers, or
`gatherAgentContext` directly. The `Outdated` re-export cleanup removes the
last latent risk of a consumer reaching through the executable to reach a
library type — a circular dependency waiting to happen.

Observable outcome: after this plan ships,

    cabal test seihou-cli-test

includes a new `Seihou.CLI.AgentLaunchSpec` test file that exercises
`substitute` and at least one `format*` helper, demonstrating that helpers
the test suite could not previously reach are now reachable. And

    rg "import Seihou.CLI.Outdated" seihou-cli/

returns only call sites that legitimately need the orchestration entry points
(`handleOutdated`, `checkInstalledModulesForUpdates`, `readOriginWithModule`,
`checkSource`, `moduleNameFromDm`) — not the data types or `compareVersions`,
which are now imported from their canonical sites.


## Progress

- [ ] Confirm the post-EP-2 state: `executable seihou` `build-depends: seihou-cli-internal`; `Seihou.CLI.AgentLaunch` is in the executable's `other-modules` with a placeholder comment; `Seihou.CLI.SchemaVersion` has already moved to the library.
- [ ] Plan the `AgentLaunch` split: identify every export of `Seihou.CLI.AgentLaunch` that uses `findExecutable`/`rawSystem`/`exitWith`/`exitFailure` and confirm they are exactly `launchAgent` and `launchAgentWith`.
- [ ] Edit `seihou-cli/src/Seihou/CLI/AgentLaunch.hs` to remove `launchAgent` and `launchAgentWith`, drop the imports they uniquely needed (`findExecutable`, `rawSystem`, `exitFailure`, `exitWith`), and update the export list.
- [ ] Create `seihou-cli/src/Seihou/CLI/AgentLaunchExec.hs` containing `launchAgent` and `launchAgentWith`, importing `Seihou.CLI.AgentLaunch` for `agentDirsForSession` and `defaultAllowedTools`.
- [ ] Update `seihou-cli/seihou-cli.cabal`: add `Seihou.CLI.AgentLaunch` to the library's `exposed-modules`; add `Seihou.CLI.AgentLaunchExec` to the executable's `other-modules` with the comment "needs System.Process.rawSystem and System.Exit.exitWith for launching the claude binary"; remove the placeholder `Seihou.CLI.AgentLaunch` comment EP-2 left behind.
- [ ] Update consumers (`Assist`, `Bootstrap`, `Setup`, `Main.hs`): change `import Seihou.CLI.AgentLaunch` to import the library names from `Seihou.CLI.AgentLaunch` and the launcher functions from `Seihou.CLI.AgentLaunchExec`. Verify each file compiles.
- [ ] Update `Seihou.CLI.Outdated`'s export list (lines 1-13 of `seihou-cli/src/Seihou/CLI/Outdated.hs`): remove `OriginInfo`, `OutdatedStatus`, `OutdatedEntry`, `CheckStats`, `compareVersions` from the exports. Verify the file still compiles (it imports them; it just stops re-exporting).
- [ ] Find and update every consumer that imports any of those names from `Seihou.CLI.Outdated`: change the import to the canonical site (`InstallShared` for `OriginInfo`; `VersionCompare` for the others).
- [ ] Add `seihou-cli/test/Seihou/CLI/AgentLaunchSpec.hs` exercising `substitute` and at least one `format*` helper. Wire it into `seihou-cli/test/Main.hs` and `seihou-cli/seihou-cli.cabal`'s test-suite `other-modules`.
- [ ] Run `cabal build all && cabal test all`; both succeed.
- [ ] Add a CHANGELOG entry to `docs/user/CHANGELOG.md`.


## Surprises & Discoveries

(None yet. Add to this section as work proceeds. Capture any consumer of the
`Outdated` re-exports the audit did not anticipate.)


## Decision Log

- Decision: Name the new executable launcher module `Seihou.CLI.AgentLaunchExec`,
  not `Seihou.CLI.AgentLauncher` or `Seihou.CLI.Agent.Launcher`.
  Rationale: The `Exec` suffix telegraphs "this is the executable-side
  counterpart of the library module of the same root name." The naming pattern
  matches a future where additional library/executable splits use the same
  suffix (e.g., a hypothetical `Seihou.CLI.HelpExec` carrying
  `Data.FileEmbed` content alongside a library `Seihou.CLI.Help` carrying pure
  rendering helpers). Keeping the suffix consistent makes the convention
  scannable.
  Date: 2026-04-26.

- Decision: Keep `gatherAgentContext` and `agentDirsForSession` in the library
  module `Seihou.CLI.AgentLaunch`, even though they perform IO
  (`getCurrentDirectory`, `doesDirectoryExist`, `discoverAllModules`).
  Rationale: The library already exposes IO-bearing helpers (for example
  `cloneRepo` and `installModuleDir` in `Seihou.CLI.InstallShared`); the
  convention's text in `docs/dev/architecture/overview.md` explicitly states
  that needing IO is not a reason to stay executable-only. Only `launchAgent`
  and `launchAgentWith` use APIs the library would not normally use
  (`findExecutable`, `rawSystem`, `exitWith`, `exitFailure`); those move to
  the executable module.
  Date: 2026-04-26.

- Decision: Do not extract `Migrate.hs`'s pure migration-engine surface in this
  plan.
  Rationale: The masterplan
  (`docs/masterplans/2-cli-library-first-convention.md`) explicitly defers
  this; the audit captured there flagged it as Tier 3 (high effort, requires
  careful effect-boundary design). Extracting it would more than double the
  scope of this plan with no gating benefit for the convention.
  Date: 2026-04-26.


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

This subsection orients a reader who has only this plan and the working tree.

The repository at `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` is a
multi-package Haskell (GHC2024) cabal workspace. The package this plan touches
is `seihou-cli/`, which has three targets in
`seihou-cli/seihou-cli.cabal`:

- `library seihou-cli-internal` — exposes a curated set of CLI helper
  modules; `hs-source-dirs: src`.
- `executable seihou` — the binary; `hs-source-dirs: src`; depends on
  `seihou-cli-internal` (this dependency was added by sibling plan
  `docs/plans/19-restructure-cli-cabal-library-first.md` and must already be
  in place before this plan begins).
- `test-suite seihou-cli-test` — `hs-source-dirs: test`; depends on
  `seihou-cli-internal` and `seihou-core`. Cannot reach modules that live
  only in the executable target.

This plan also assumes the convention is documented in
`docs/dev/architecture/overview.md` section "CLI Module Placement Convention"
(created by sibling plan
`docs/plans/18-document-cli-library-first-convention.md`). When in doubt
about whether a function should move to the library, consult that section.

### The `AgentLaunch` module today

`seihou-cli/src/Seihou/CLI/AgentLaunch.hs` (~230 lines) currently exports
fourteen names from one module:

- `AgentContext` (data type with six fields).
- `gatherAgentContext :: IO AgentContext` — uses `getCurrentDirectory`,
  `doesDirectoryExist`, `doesFileExist`, plus `discoverAllModules` from
  `Seihou.Core.Module`.
- `agentDirsForSession :: IO [FilePath]` — uses `getHomeDirectory`,
  `getCurrentDirectory`, `doesDirectoryExist`, plus `filterM`.
- `launchAgent :: Bool -> Text -> Maybe Text -> IO ()` — calls
  `agentDirsForSession`, then delegates to `launchAgentWith`.
- `launchAgentWith :: [FilePath] -> [String] -> Bool -> Text -> Maybe Text -> IO ()` —
  calls `findExecutable "claude"`, prints to `TIO.putStrLn`, calls
  `exitFailure` on the missing-executable path, otherwise calls `rawSystem`
  and `exitWith` on the success path.
- `defaultAllowedTools :: [String]`, `setupAllowedTools :: [String]`,
  `bootstrapAllowedTools :: [String]` — pure constants.
- `substitute :: [(Text, Text)] -> Text -> Text` — pure templating
  (`{{key}}` substitution).
- `formatSeihouProjectState`, `formatManifestState`, `formatModuleDhallState`,
  `formatLocalModules`, `formatAvailableModules` — pure formatters of
  `AgentContext`.

Two private helpers (`findLocalModuleDirs` and `toModuleInfo`/`sourceLabel`)
support `gatherAgentContext`.

### Consumers of `AgentLaunch`

Three call sites, all in the executable target:

- `seihou-cli/src/Seihou/CLI/Assist.hs` — imports `Seihou.CLI.AgentLaunch`
  (no import list, so it pulls every export). Uses `gatherAgentContext`,
  `agentDirsForSession`, `defaultAllowedTools`, `launchAgentWith`,
  `AgentContext`, `substitute`, and the five `format*` helpers.
- `seihou-cli/src/Seihou/CLI/Bootstrap.hs` — imports
  `Seihou.CLI.AgentLaunch` similarly. Uses
  `bootstrapAllowedTools`, `launchAgentWith`, plus the pure surface.
- `seihou-cli/src/Seihou/CLI/Setup.hs` — imports
  `Seihou.CLI.AgentLaunch` similarly. Uses `setupAllowedTools`,
  `launchAgentWith`, plus the pure surface.

`seihou-cli/src/Main.hs` does not import `AgentLaunch` directly; it
dispatches to `Assist.handleAssist`, `Bootstrap.handleBootstrap`, and
`Setup.handleSetup`.

### `Outdated.hs`'s re-exports

`seihou-cli/src/Seihou/CLI/Outdated.hs` lines 1-13 export:

    module Seihou.CLI.Outdated
      ( handleOutdated,
        OriginInfo (..),
        OutdatedStatus (..),
        OutdatedEntry (..),
        CheckStats (..),
        checkInstalledModulesForUpdates,
        readOriginWithModule,
        moduleNameFromDm,
        compareVersions,
        checkSource,
      )

Lines 22-31 import the same five names from their canonical homes:

    import Seihou.CLI.InstallShared (OriginInfo (..))
    ...
    import Seihou.CLI.VersionCompare
      ( CheckStats (..),
        OutdatedEntry (..),
        OutdatedStatus (..),
        compareVersions,
      )

So the cleanup is purely an export-list edit (delete five lines from the
module's exports) plus updating any consumer that currently goes through
`Outdated` to instead import from the canonical site.

To find consumers:

    rg -l "import Seihou.CLI.Outdated" seihou-cli/

The consumers, as of the audit on 2026-04-26, are limited (Outdated is
mostly a leaf module that `Main.hs` dispatches to and `Status.hs` may use
for `checkInstalledModulesForUpdates`). Verify with the grep when you start.

### Test suite layout

`seihou-cli/test/` contains one Spec.hs file per library module that has
spec coverage:

    seihou-cli/test/Seihou/CLI/BrowseFormatSpec.hs
    seihou-cli/test/Seihou/CLI/CommitMessageSpec.hs
    seihou-cli/test/Seihou/CLI/DiffSpec.hs
    seihou-cli/test/Seihou/CLI/GitSpec.hs
    seihou-cli/test/Seihou/CLI/InitSpec.hs
    seihou-cli/test/Seihou/CLI/InstallHistorySpec.hs
    seihou-cli/test/Seihou/CLI/ListSpec.hs
    seihou-cli/test/Seihou/CLI/MigrateSpec.hs
    seihou-cli/test/Seihou/CLI/PendingMigrationSpec.hs
    seihou-cli/test/Seihou/CLI/Registry/SyncSpec.hs
    seihou-cli/test/Seihou/CLI/RemoteVersionSpec.hs
    seihou-cli/test/Seihou/CLI/SavePromptedSpec.hs
    seihou-cli/test/Seihou/CLI/StatusSpec.hs
    seihou-cli/test/Seihou/CLI/UpgradeSpec.hs

Each Spec.hs exposes a `tests :: IO TestTree` (or `Spec`) that
`seihou-cli/test/Main.hs` aggregates with `Test.Tasty.defaultMain`. Adding a
new spec means: (1) write the Spec.hs file, (2) add the qualified import to
`Main.hs`, (3) append `<NewSpec>.tests` to the list in `main`, and (4) add
the module to `seihou-cli/seihou-cli.cabal`'s test-suite `other-modules`.

`Seihou.CLI.RemoteVersionSpec` is a good shape model for the new
`AgentLaunchSpec`: a small file that asserts pure-function output for
fixture inputs. Read it before writing the new spec.

Key terms:

- **"Pure surface"**: functions and data types that do not perform IO and
  whose behaviour is fully determined by their arguments. `substitute` and
  the `format*` helpers are pure. `gatherAgentContext` is IO-bearing but
  its IO is the kind the library already does (file-system probing,
  `Seihou.Core.Module` discovery), so it stays library-eligible.


## Plan of Work

This plan has three milestones.


### Milestone 1: Split `Seihou.CLI.AgentLaunch`

Scope: separate the pure surface from the launcher. Move the launcher to a
new module `Seihou.CLI.AgentLaunchExec` in the executable target. Update the
three consumers and the cabal file.

What will exist at the end: two modules instead of one. The library has a
new exposed module (`Seihou.CLI.AgentLaunch`); the executable has a new
`other-modules` entry (`Seihou.CLI.AgentLaunchExec`).

Acceptance: `cabal build all` and `cabal test all` both succeed; the
executable still launches a claude session correctly when invoked with
`seihou assist`, `seihou bootstrap`, or `seihou setup`.

Steps:

1. Open `seihou-cli/src/Seihou/CLI/AgentLaunch.hs`. Delete the function
   bodies of `launchAgent` (lines ~73-77) and `launchAgentWith` (lines
   ~80-97). Remove these names from the export list (lines 5-6). Also
   remove any imports that were only needed by those functions:
   `System.Directory.findExecutable`, `System.Exit.exitFailure`,
   `System.Exit.exitWith`, `System.Process.rawSystem`. Keep imports still
   used by the remaining body (`System.Directory.doesDirectoryExist`,
   `doesFileExist`, `getCurrentDirectory`, `getHomeDirectory`).

   The post-edit module should compile in the library target. Verify:

       cabal build seihou-cli-internal

   Expect a clean build.

2. Create `seihou-cli/src/Seihou/CLI/AgentLaunchExec.hs` with the following
   skeleton (preserve the original function bodies you removed in Step 1
   verbatim):

       module Seihou.CLI.AgentLaunchExec
         ( launchAgent,
           launchAgentWith,
         )
       where

       import Data.Text qualified as T
       import Data.Text.IO qualified as TIO
       import Seihou.CLI.AgentLaunch
         ( agentDirsForSession,
           defaultAllowedTools,
         )
       import Seihou.Prelude
       import System.Directory (findExecutable)
       import System.Exit (ExitCode (..), exitFailure, exitWith)
       import System.Process (rawSystem)

       launchAgent :: Bool -> Text -> Maybe Text -> IO ()
       launchAgent debug systemPrompt initialPrompt = do
         addDirs <- agentDirsForSession
         launchAgentWith addDirs defaultAllowedTools debug systemPrompt initialPrompt

       launchAgentWith :: [FilePath] -> [String] -> Bool -> Text -> Maybe Text -> IO ()
       launchAgentWith addDirs tools debug systemPrompt initialPrompt
         | debug = TIO.putStr systemPrompt
         | otherwise = do
             claudePath <- findExecutable "claude"
             case claudePath of
               Nothing -> do
                 TIO.putStrLn "Error: 'claude' CLI (Claude Code) not found on PATH."
                 TIO.putStrLn "Install it from: https://docs.anthropic.com/en/docs/claude-code"
                 exitFailure
               Just _ -> do
                 let args =
                       ["--system-prompt", T.unpack systemPrompt]
                         <> concatMap (\d -> ["--add-dir", d]) addDirs
                         <> concatMap (\t -> ["--allowedTools", t]) tools
                         <> maybe [] (\p -> [T.unpack p]) initialPrompt
                 exitCode <- rawSystem "claude" args
                 exitWith exitCode

3. Edit `seihou-cli/seihou-cli.cabal`:

   - In `library seihou-cli-internal`'s `exposed-modules`, add
     `Seihou.CLI.AgentLaunch` (alphabetised; sits between
     `Seihou.CLI.Init` and `Seihou.CLI.InstallHistory` if a pure
     alphabetisation is followed).
   - In `executable seihou`'s `other-modules`, REPLACE the placeholder
     `Seihou.CLI.AgentLaunch` entry left by EP-2 with
     `Seihou.CLI.AgentLaunchExec`. Add the comment:

         Seihou.CLI.AgentLaunchExec
           -- needs System.Process.rawSystem and System.Exit.exitWith
           --   for launching the claude binary

4. Update `seihou-cli/src/Seihou/CLI/Assist.hs`:

   - Change `import Seihou.CLI.AgentLaunch` to two imports:

         import Seihou.CLI.AgentLaunch
           ( AgentContext,
             agentDirsForSession,
             defaultAllowedTools,
             formatAvailableModules,
             formatLocalModules,
             formatManifestState,
             formatModuleDhallState,
             formatSeihouProjectState,
             gatherAgentContext,
             substitute,
           )
         import Seihou.CLI.AgentLaunchExec (launchAgentWith)

   The body does not change.

5. Update `seihou-cli/src/Seihou/CLI/Bootstrap.hs` analogously: import the
   pure surface and `bootstrapAllowedTools` from `Seihou.CLI.AgentLaunch`,
   import `launchAgentWith` from `Seihou.CLI.AgentLaunchExec`. Confirm
   the body compiles.

6. Update `seihou-cli/src/Seihou/CLI/Setup.hs` analogously: import the
   pure surface and `setupAllowedTools` from `Seihou.CLI.AgentLaunch`,
   import `launchAgentWith` from `Seihou.CLI.AgentLaunchExec`.

7. Search for any other consumer of `launchAgent`/`launchAgentWith` that
   you might have missed:

       rg "launchAgent|launchAgentWith" seihou-cli/

   Expected: only the three files updated in Steps 4-6 plus the new
   `AgentLaunchExec.hs`. If `Main.hs` or another file calls them directly,
   update its imports too.

8. Build and test:

       cabal build all
       cabal test all

   Expected: both succeed.

9. Sanity-check the runtime behaviour:

       cabal run seihou -- assist --debug | head -20

   The `--debug` flag short-circuits before invoking the claude binary,
   so this exercises `launchAgentWith`'s debug path without requiring
   `claude` to be installed. Expect a system prompt printed to stdout.


### Milestone 2: Drop the redundant re-exports from `Seihou.CLI.Outdated`

Scope: shrink the `Seihou.CLI.Outdated` export list to remove the names
that are re-exports of types defined in library modules. Update consumers
to import from the canonical site.

What will exist at the end: `Outdated.hs`'s export list contains only
orchestration entry points (`handleOutdated`,
`checkInstalledModulesForUpdates`, `readOriginWithModule`,
`moduleNameFromDm`, `checkSource`). Every consumer of `OriginInfo`,
`OutdatedStatus`, `OutdatedEntry`, `CheckStats`, or `compareVersions`
imports from `Seihou.CLI.InstallShared` or `Seihou.CLI.VersionCompare`
respectively.

Steps:

1. Find all consumers:

       rg -l "import Seihou.CLI.Outdated" seihou-cli/

   Read each match. For each one that imports any of the five re-exported
   names, change the import to point at the canonical site. The mapping is:

       OriginInfo                 → Seihou.CLI.InstallShared
       OutdatedStatus             → Seihou.CLI.VersionCompare
       OutdatedEntry              → Seihou.CLI.VersionCompare
       CheckStats                 → Seihou.CLI.VersionCompare
       compareVersions            → Seihou.CLI.VersionCompare

   A consumer that imports both an orchestration entry point AND one of
   these names ends up with two imports: one from `Outdated` for the
   entry point, one from the canonical site for the type/function.

2. Edit `seihou-cli/src/Seihou/CLI/Outdated.hs`. Remove these lines from
   the export list (currently lines 3-6 and line 10):

       OriginInfo (..),
       OutdatedStatus (..),
       OutdatedEntry (..),
       CheckStats (..),
       compareVersions,

   The export list now reads:

       module Seihou.CLI.Outdated
         ( handleOutdated,
           checkInstalledModulesForUpdates,
           readOriginWithModule,
           moduleNameFromDm,
           checkSource,
         )

   Do not change the import block (lines 22-31); those imports are still
   used internally by the module body.

3. Build and test:

       cabal build all
       cabal test all

   Expected: both succeed. If a consumer's import you missed in Step 1
   emerges as a "module ... does not export ..." error, update that
   consumer.


### Milestone 3: Add `Seihou.CLI.AgentLaunchSpec`

Scope: add a small test file that exercises at least `substitute` and one
`format*` helper from the now-library-exposed
`Seihou.CLI.AgentLaunch`. The test is a regression check that proves the
extraction enabled testing that was previously impossible.

What will exist at the end: a new file
`seihou-cli/test/Seihou/CLI/AgentLaunchSpec.hs` wired into
`seihou-cli/test/Main.hs` and the cabal test-suite `other-modules`.

Steps:

1. Create `seihou-cli/test/Seihou/CLI/AgentLaunchSpec.hs`:

       module Seihou.CLI.AgentLaunchSpec (tests) where

       import Seihou.CLI.AgentLaunch
         ( AgentContext (..),
           formatSeihouProjectState,
           substitute,
         )
       import Test.Hspec
       import Test.Tasty (TestTree)
       import Test.Tasty.Hspec (testSpec)

       tests :: IO TestTree
       tests = testSpec "Seihou.CLI.AgentLaunch" $ do
         describe "substitute" $ do
           it "replaces a single key" $
             substitute [("name", "Alice")] "Hello {{name}}"
               `shouldBe` "Hello Alice"
           it "replaces multiple keys in order" $
             substitute [("a", "1"), ("b", "2")] "{{a}}-{{b}}"
               `shouldBe` "1-2"
           it "leaves unknown keys untouched" $
             substitute [("a", "1")] "{{a}} and {{c}}"
               `shouldBe` "1 and {{c}}"

         describe "formatSeihouProjectState" $ do
           let baseCtx =
                 AgentContext
                   { cwd = "/tmp/test",
                     seihouInitialized = False,
                     hasManifest = False,
                     localModuleDhall = False,
                     localModules = [],
                     availableModules = []
                   }
           it "names the .seihou directory when initialised" $
             formatSeihouProjectState (baseCtx {seihouInitialized = True})
               `shouldContain` ".seihou"
           it "states 'No .seihou' when not initialised" $
             formatSeihouProjectState baseCtx
               `shouldContain` "No .seihou"

   Adjust the `shouldContain` assertions if your reading of the actual
   `AgentLaunch.hs` source disagrees with the strings above. The intent
   is to demonstrate that the helpers are now reachable; the exact
   assertions are flexible.

2. Wire it into `seihou-cli/test/Main.hs`. Add the import alongside the
   existing ones:

       import Seihou.CLI.AgentLaunchSpec qualified as AgentLaunchSpec

   And add `AgentLaunchSpec.tests,` to the list in `main` (alphabetised
   if the existing list is alphabetised, otherwise just before
   `BrowseFormatSpec.tests,`).

3. Add `Seihou.CLI.AgentLaunchSpec` to `seihou-cli/seihou-cli.cabal`'s
   `test-suite seihou-cli-test`'s `other-modules` (alphabetised, so
   between `Seihou.CLI.BrowseFormatSpec` and `Seihou.CLI.CommitMessageSpec`).

4. Run the tests:

       cabal test seihou-cli-test

   Expected: all existing tests still pass; the new
   `Seihou.CLI.AgentLaunch` group reports several green tests.


## Concrete Steps

The Plan of Work above contains the concrete steps interleaved with
narrative. To execute the plan end-to-end, follow Milestone 1 in order, then
Milestone 2, then Milestone 3, then update the CHANGELOG and commit.

CHANGELOG entry to add to `docs/user/CHANGELOG.md`:

    - 2026-04-26: Split `Seihou.CLI.AgentLaunch` into a library module
      (pure surface plus `AgentContext`) and a new executable module
      `Seihou.CLI.AgentLaunchExec` (process invocation). Removed
      redundant re-exports from `Seihou.CLI.Outdated`; consumers now
      import `OriginInfo` from `Seihou.CLI.InstallShared` and
      `OutdatedStatus`/`OutdatedEntry`/`CheckStats`/`compareVersions`
      from `Seihou.CLI.VersionCompare`.

Commit (single commit, all three milestones together is fine since they
share the same library-first motivation; or split into three commits if
the diff is large):

    git add seihou-cli/seihou-cli.cabal \
            seihou-cli/src/Seihou/CLI/AgentLaunch.hs \
            seihou-cli/src/Seihou/CLI/AgentLaunchExec.hs \
            seihou-cli/src/Seihou/CLI/Assist.hs \
            seihou-cli/src/Seihou/CLI/Bootstrap.hs \
            seihou-cli/src/Seihou/CLI/Setup.hs \
            seihou-cli/src/Seihou/CLI/Outdated.hs \
            seihou-cli/test/Main.hs \
            seihou-cli/test/Seihou/CLI/AgentLaunchSpec.hs \
            docs/user/CHANGELOG.md
    # plus any consumer files updated in Milestone 2
    git commit -m "$(cat <<'EOF'
    refactor(cli): split AgentLaunch and clean up Outdated re-exports

    Splits Seihou.CLI.AgentLaunch into a library module (pure surface plus
    AgentContext, gatherAgentContext, agentDirsForSession, substitute,
    tool-list constants, and the format* helpers) and a new executable
    module Seihou.CLI.AgentLaunchExec (launchAgent and launchAgentWith,
    which call findExecutable, rawSystem, exitWith). Updates Assist,
    Bootstrap, and Setup imports.

    Drops re-exports of OriginInfo, OutdatedStatus, OutdatedEntry,
    CheckStats, and compareVersions from Seihou.CLI.Outdated. Consumers
    now import from the canonical sites (Seihou.CLI.InstallShared and
    Seihou.CLI.VersionCompare).

    Adds Seihou.CLI.AgentLaunchSpec exercising substitute and
    formatSeihouProjectState — tests previously impossible because the
    module was executable-only.

    MasterPlan: docs/masterplans/2-cli-library-first-convention.md
    ExecPlan: docs/plans/20-extract-trapped-cli-helpers.md
    Intention: intention_01kq63sz0ced98e23qvad7zpnp
    EOF
    )"


## Validation and Acceptance

Acceptance is observable through the build, the test suite, and a runtime
sanity check.

Build acceptance:

    cabal build all

Succeeds.

Test acceptance:

    cabal test all

Succeeds; the new `Seihou.CLI.AgentLaunch` test group reports green.

Static-shape acceptance:

    rg "module Seihou.CLI.AgentLaunch " seihou-cli/src/

Returns two matches (the library `AgentLaunch.hs` and the executable
`AgentLaunchExec.hs`).

    rg "OriginInfo|OutdatedStatus|OutdatedEntry|CheckStats|compareVersions" \
       seihou-cli/src/Seihou/CLI/Outdated.hs | rg "^module|^import|^  "

Should show those names ONLY in the import block, not in the export list.

Runtime acceptance: the agent commands still work. The `--debug` flag of
each command short-circuits before invoking `claude`, so:

    cabal run seihou -- assist --debug
    cabal run seihou -- bootstrap --debug
    cabal run seihou -- setup --debug

Each prints a system prompt and exits cleanly.


## Idempotence and Recovery

Each milestone is independently re-runnable. If a milestone is interrupted:

- Milestone 1 partial: if `AgentLaunchExec.hs` exists but `AgentLaunch.hs`
  still has the launcher functions, the build will fail with duplicate
  exports. Resolve by completing Step 1 of Milestone 1 (delete from
  `AgentLaunch.hs`).
- Milestone 2 partial: if `Outdated.hs` no longer re-exports the names but
  some consumer still imports them from `Outdated`, the build fails with
  "module Seihou.CLI.Outdated does not export ...". The fix is to
  complete Step 1 of Milestone 2 (update consumer imports).
- Milestone 3 partial: if `AgentLaunchSpec.hs` exists but is not wired into
  `Main.hs` or the cabal `other-modules`, the test suite either ignores
  the new file or fails to build. The fix is to complete the wiring.

If you need to abort the plan completely, `git checkout --` the touched
files restores the pre-plan state.


## Interfaces and Dependencies

Files edited:

- `seihou-cli/seihou-cli.cabal`: add `Seihou.CLI.AgentLaunch` to library
  exposed-modules; replace placeholder `Seihou.CLI.AgentLaunch` in
  executable other-modules with `Seihou.CLI.AgentLaunchExec` (annotated);
  add `Seihou.CLI.AgentLaunchSpec` to test-suite other-modules.
- `seihou-cli/src/Seihou/CLI/AgentLaunch.hs`: remove launcher functions
  and their dedicated imports; shorten export list.
- `seihou-cli/src/Seihou/CLI/Assist.hs`: split single import into two;
  no body changes.
- `seihou-cli/src/Seihou/CLI/Bootstrap.hs`: split single import into two.
- `seihou-cli/src/Seihou/CLI/Setup.hs`: split single import into two.
- `seihou-cli/src/Seihou/CLI/Outdated.hs`: remove five names from export
  list.
- Zero or more consumer files identified by Milestone 2's grep step.
- `seihou-cli/test/Main.hs`: add one import and one list entry.
- `docs/user/CHANGELOG.md`: prepend one entry.

Files created:

- `seihou-cli/src/Seihou/CLI/AgentLaunchExec.hs` (~30 lines).
- `seihou-cli/test/Seihou/CLI/AgentLaunchSpec.hs` (~40 lines).

No new Haskell-package dependencies.

Library exports added:

    Seihou.CLI.AgentLaunch
      ( AgentContext (..),
        gatherAgentContext,
        agentDirsForSession,
        defaultAllowedTools,
        setupAllowedTools,
        bootstrapAllowedTools,
        substitute,
        formatSeihouProjectState,
        formatManifestState,
        formatModuleDhallState,
        formatLocalModules,
        formatAvailableModules,
      )

Executable-only exports added:

    Seihou.CLI.AgentLaunchExec
      ( launchAgent,
        launchAgentWith,
      )
