# Add `seihou registry validate` Subcommand

Intention: intention_01kq6cyx1ze8nt897kgbq2mtas

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

A registry author maintains a multi-module repository whose root contains a file
called `seihou-registry.dhall`. That file is a hand-written list ("entries") of
the modules and recipes the repo offers, along with metadata: a name, a relative
path, a description, tags, and — crucially — a `version` field. Each module
sub-directory has its own `module.dhall` (or `recipe.dhall`) that *also*
declares a `version`. The two are supposed to agree. Today nothing forces them
to agree, and any of the following silently break the registry without any
single command surfacing the failure:

1. The registry entry's `version` is `None Text` while the module declares
   `Some "1.2.0"` (the registry forgot to advertise the module's version).
2. The registry entry's `version` is `Some "1.0.0"` while the module declares
   `Some "1.2.0"` (the module bumped, the registry was never updated).
3. The registry entry's `path` points at a directory that has no
   `module.dhall` (renamed or deleted module).
4. A registry entry's `name` does not match the lowercase pattern Seihou
   requires (`[a-z][a-z0-9-]*`), or the same name appears under both
   `modules` and `recipes`.
5. A registry entry's `path` is absolute or contains `..` (unsafe).

Pieces of this are already detected, but in fragmented places:

- `Seihou.Core.Registry.validateRegistry`
  (`seihou-core/src/Seihou/Core/Registry.hs:96`) covers cases 3, 4, and 5 and
  is invoked only as a side-check inside `seihou install`
  (`seihou-cli/src-exe/Seihou/CLI/Install.hs:67`).
- `Seihou.CLI.Registry.Sync.checkRegistryVersionDrift`
  (`seihou-cli/src/Seihou/CLI/Registry/Sync.hs:248`) covers cases 1 and 2 but
  emits *warnings* through `seihou browse` and `seihou install`. There is no
  command an author can run to confirm "my registry is healthy" before they
  push.

This plan adds `seihou registry validate`, a single command that runs against
a writable checkout of a multi-module repository and reports every entry-level
problem in one pass. Registry version drift is treated as an *error* here (the
command exits non-zero) rather than the soft warning that `browse` and
`install` emit, because the explicit user-facing purpose of `registry validate`
is to enforce that registry entries match their underlying modules.

After this change, an author standing in the root of a multi-module checkout
can run:

    seihou registry validate

and see something like:

    Validating seihou-registry.dhall (./)

    errors:
      modules.haskell-base: registry version (none) does not match module.dhall version 1.2.0
      modules.nix-flake:    registry version 0.3.0 does not match module.dhall version 0.4.0
      recipes.web-app:      registry recipe entry 'web-app' points to missing recipe.dhall at recipes/web-app

    3 errors, 0 warnings. Run `seihou registry sync-versions` to fix version drift.

with exit code 1. When everything is in order:

    Validating seihou-registry.dhall (./)

    OK: 4 modules, 1 recipe, all versions in sync.

with exit code 0. CI hooks can call `seihou registry validate` directly and
get a non-zero exit on any of the five failure modes above; this is stricter
than `seihou registry sync-versions --check`, which only catches version drift.

The command is also wired into `nix flake check`-style flows the author may
already run, by virtue of being a single shell invocation with a meaningful
exit code.


## Progress

- [x] M1: Pure core. Combine the existing `validateRegistry` (structural
      checks) and the existing `computeRegistrySync` classification (version
      checks) into a single pure function in `Seihou.Core.Registry` that
      returns a structured `RegistryValidationReport`. Add unit tests covering
      every failure mode plus the fully-clean case. (2026-04-27)
- [x] M2: CLI subcommand. Add `RegistryValidate ValidateRegistryOpts` to
      `RegistryCommand`. Implement
      `Seihou.CLI.Registry.Validate.handleValidate` (in
      `seihou-cli/src/Seihou/CLI/Registry/Validate.hs`, the *library*
      half of `seihou-cli`). Wire the parser in
      `seihou-cli/src-exe/Seihou/CLI/Commands.hs` and the dispatcher in
      `seihou-cli/src/Seihou/CLI/Registry.hs`. (2026-04-27)
- [x] M3: Tests for the CLI handler. Mirror the temp-dir fixture style of
      `seihou-cli/test/Seihou/CLI/Registry/SyncSpec.hs` and assert exit
      decisions and report contents for the success path, the version-drift
      path, and the missing-`module.dhall` path. Register the new spec module
      in `seihou-cli/test/Main.hs` and the cabal test stanza. (2026-04-27)
- [ ] M4: Documentation. Extend `docs/cli/registry.md` with a `seihou registry
      validate` section, add a CHANGELOG entry under Unreleased, and add a
      "Validating the registry" cross-reference to
      `docs/user/registries-and-multi-module-repos.md`. Update the "Current
      subcommands" footer in `Seihou.CLI.Commands.registryInfo`.
- [ ] M5: Manual end-to-end. In a throwaway temp directory, hand-construct a
      registry that exhibits each of the five failure modes, run `seihou
      registry validate`, observe the report, fix the entries, and confirm
      the command exits 0.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Treat registry version drift as an *error* in `validate`, not a
  warning.
  Rationale: The user phrased the request as "ensures that the entries
  especially the versions in the manifest match the module". A non-zero exit
  is the only way `validate` can serve a CI/pre-push role, and the existing
  `sync-versions --check` already covers the lighter "is sync needed?"
  signal. `browse`/`install` retain their soft-warning behavior unchanged.
  Date: 2026-04-26

- Decision: Place new code in `seihou-cli/src/Seihou/CLI/Registry/Validate.hs`
  (the library half of `seihou-cli`) rather than `src-exe/`.
  Rationale: The handler does not need `Options.Applicative`, `FileEmbed`,
  `GitHash`, or `Paths_seihou_cli`, and the existing
  `Seihou.CLI.Registry.Sync` precedent (also in `src/`) demonstrates that
  registry handlers belong in the library. Per the project CLAUDE.md and
  `nix/check-cli-module-placement.sh`, modules without a "trapping" import go
  in the library. The `Options.Applicative` parser fragment that *introduces*
  the new constructor stays in `src-exe/Seihou/CLI/Commands.hs` alongside the
  existing `syncVersionsParser`.
  Date: 2026-04-26

- Decision: Add the pure validation core to `Seihou.Core.Registry` rather
  than a new module.
  Rationale: `validateRegistry` and the `computeRegistrySync` classification
  already live there. Co-locating the unified report with the data type and
  the existing checks avoids two near-duplicate import lists at call sites
  and keeps the rule "structural rules + version rules together" obvious.
  Date: 2026-04-26


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

This section names everything a reader who has never opened the repository
will need to find on disk to follow the rest of the plan. All paths are
relative to the repository root.

### What a "registry" is in Seihou

Seihou is a project scaffolding tool: an end-user runs `seihou run <module>`
to lay down templated files. Modules can be installed individually or
discovered through a *registry* — a multi-module repository whose root
contains `seihou-registry.dhall`. That Dhall file is a record literal of the
form:

    { repoName = "Test"
    , repoDescription = None Text
    , modules =
      [ { name = "haskell-base"
        , version = Some "1.2.0"
        , path = "modules/haskell-base"
        , description = None Text
        , tags = [] : List Text
        }
      ]
    , recipes = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }
    }

Each entry's `path` is interpreted as a sub-directory of the repo root that
contains a `module.dhall` (for `modules`) or a `recipe.dhall` (for
`recipes`). Both files declare their own `version`, which should equal the
registry entry's `version`.

The Dhall side of the schema for these entries is decoded in
`seihou-core/src/Seihou/Dhall/Eval.hs` (search for `registryDecoder`). The
Haskell side is in `seihou-core/src/Seihou/Core/Registry.hs`.

### Existing related code

`seihou-core/src/Seihou/Core/Registry.hs` already contains:

- The `Registry`, `RegistryEntry`, `RepoContents` types
  (lines 24, 35, 44).
- `discoverRepoContents`, which classifies a repo as `MultiModule Registry`,
  `SingleModule`, `SingleRecipe`, or `EmptyRepo` (line 58).
- `validateRegistry :: FilePath -> Registry -> IO [Text]`, which today
  returns one `Text` per error covering: invalid module name, unsafe path,
  missing `module.dhall`/`recipe.dhall`, and module/recipe name collisions
  (line 96).
- The pure `computeRegistrySync` and `SyncDiff`/`SyncStatus` types that
  classify each entry's version against on-disk modules into `SyncInSync`,
  `SyncMissing`, `SyncStale Text`, or `SyncOrphan` (line 211).
- `formatDriftWarning :: SyncDiff -> Maybe Text`, which formats a
  `SyncMissing` or `SyncStale` row as a one-line message recommending
  `seihou registry sync-versions` (line 269).

`seihou-cli/src/Seihou/CLI/Registry/Sync.hs` already contains:

- `runSync` (line 73), the IO core of `seihou registry sync-versions`. It
  resolves on-disk versions and feeds `computeRegistrySync`. The plan reuses
  its private helper `resolveOnDiskVersions` (line 109), which reads each
  entry's `module.dhall`/`recipe.dhall` and pairs the result with `(kind,
  name)`.
- `checkRegistryVersionDrift :: FilePath -> Registry -> IO [Text]`
  (line 248), which is the same pipeline returning the formatted drift
  warnings used by `seihou browse` and `seihou install`.

`seihou-cli/src/Seihou/CLI/Registry.hs` is the CLI dispatcher for the
`registry` group:

    data RegistryCommand
      = RegistrySyncVersions SyncVersionsOpts
      deriving stock (Eq, Show, Generic)

    handleRegistry :: RegistryCommand -> IO ()
    handleRegistry (RegistrySyncVersions opts) = handleSyncVersions opts

It explicitly reserves space for `registry validate` in the comment at line
11–12. This plan adds the second constructor.

### How CLI commands are wired

`seihou-cli/src-exe/Seihou/CLI/Commands.hs` defines the top-level `Command`
sum (line 48) and the optparse-applicative parser. The `registry` subcommand
group is parsed by `registryCommandParser` (line 1045):

    registryCommandParser :: Parser RegistryCommand
    registryCommandParser =
      hsubparser
        (command "sync-versions" syncVersionsInfo)

`seihou-cli/src-exe/Main.hs` dispatches the parsed `Command` (line 71):

    Registry registryCmd ->
      handleRegistry registryCmd

So a new `registry` subcommand requires three edits:

1. New constructor on `RegistryCommand` in
   `seihou-cli/src/Seihou/CLI/Registry.hs`.
2. New parser fragment + `command "validate" ...` in
   `seihou-cli/src-exe/Seihou/CLI/Commands.hs`.
3. New handler module — chosen below to live in
   `seihou-cli/src/Seihou/CLI/Registry/Validate.hs`.

### Library-first module placement

The repository enforces a convention (see `CLAUDE.md` at the repo root and
`docs/dev/architecture/overview.md`, section "CLI Module Placement
Convention"): modules go in `seihou-cli/src/` (the `seihou-cli-internal`
library) by default. They only move to `seihou-cli/src-exe/` when they
genuinely import one of `Options.Applicative`, `Data.FileEmbed`, `GitHash`,
or `Paths_seihou_cli`, or when they import another `src-exe`-only module
(transitively trapped). The check is mechanically enforced by
`nix/check-cli-module-placement.sh` and runs in both `nix flake check` and
the pre-commit hook.

The new `Seihou.CLI.Registry.Validate` module needs none of those, exactly
like its sibling `Seihou.CLI.Registry.Sync`, so it goes under
`seihou-cli/src/`. The cabal stanza to add is described in M2 below.

### How `sync-versions` is tested

`seihou-cli/test/Seihou/CLI/Registry/SyncSpec.hs` is the existing model. It:

- Builds a temporary registry repo under `withSystemTempDirectory` with two
  module subdirectories.
- Calls `runSync` directly (not through the executable).
- Pattern-matches the `SyncOutcome` and compares the resulting `SyncDiff`
  list / re-parsed registry to expectations.

The plan follows the exact same shape for the new spec.


## Plan of Work

The work is laid out as five milestones M1–M5. Each is independently
buildable and testable. Build commands at the bottom of the plan use
`cabal build all` and `cabal test all` from the repo root, which builds
both `seihou-core` and `seihou-cli`.


### M1 — Pure validation core in `Seihou.Core.Registry`

After this milestone, `seihou-core` exports a pure-IO function

    validateRegistryFull :: FilePath -> Registry -> [(EntryKind, ModuleName, Maybe Text)] -> IO RegistryValidationReport

that returns a structured report combining the existing `validateRegistry`
checks with the version-drift classifications from `computeRegistrySync`.
The split between "look up on-disk versions" (IO) and "decide pass/fail"
(pure) mirrors the `Sync.runSync` / `computeRegistrySync` split and lets
unit tests construct lookup lists by hand.

`Seihou.Core.Registry` cannot import `Seihou.Dhall.Eval` (it is imported
*by* the eval module to break a cycle, see the comment at line 161 of
`Registry.hs`). So the same trick used in `Sync.runSync` applies: the
*caller* (the CLI handler in M2) loads each entry's `module.dhall` /
`recipe.dhall` and supplies the `[(EntryKind, ModuleName, Maybe Text)]`
lookup list. This module's job is purely to combine those signals.

In `seihou-core/src/Seihou/Core/Registry.hs`, add:

    -- | One row of the unified validation report. Either reuses an existing
    -- structural error message (path/name/file-existence/collisions) or
    -- carries a version-mismatch row classified by 'SyncStatus'.
    data RegistryValidationIssue
      = StructuralError Text
      | VersionMismatch SyncDiff   -- only SyncMissing or SyncStale; others filtered out
      deriving stock (Eq, Show, Generic)

    -- | Whole-registry validation outcome.
    data RegistryValidationReport = RegistryValidationReport
      { reportIssues :: [RegistryValidationIssue],
        reportModuleCount :: Int,
        reportRecipeCount :: Int
      }
      deriving stock (Eq, Show, Generic)

    -- | True iff the report has at least one issue.
    reportHasIssues :: RegistryValidationReport -> Bool
    reportHasIssues r = not (null r.reportIssues)

    -- | Combine the existing structural checks with version classification.
    -- The third argument is the same shape 'computeRegistrySync' takes —
    -- the caller loads each entry's @module.dhall@/@recipe.dhall@ once and
    -- passes a lookup list keyed by (kind, name).
    validateRegistryFull ::
      FilePath ->
      Registry ->
      [(EntryKind, ModuleName, Maybe Text)] ->
      IO RegistryValidationReport
    validateRegistryFull repoRoot reg lookups = do
      structuralErrs <- validateRegistry repoRoot reg
      let report = computeRegistrySync reg lookups
          versionIssues =
            [ VersionMismatch d
            | d <- report.syncDiffs,
              case d.diffStatus of
                SyncMissing -> True
                SyncStale _ -> True
                _ -> False
            ]
      pure
        RegistryValidationReport
          { reportIssues = map StructuralError structuralErrs <> versionIssues,
            reportModuleCount = length reg.modules,
            reportRecipeCount = length reg.recipes
          }

Add the new symbols to the module export list at the top of `Registry.hs`.

Also add a pure formatter for issues so the CLI handler stays small:

    -- | Render a single 'RegistryValidationIssue' as a one-line human-readable
    -- string. 'VersionMismatch' rows reuse the same wording as
    -- 'formatDriftWarning' but without the trailing "run `seihou registry
    -- sync-versions`" suggestion (the validate handler prints a single
    -- aggregated suggestion at the bottom).
    formatValidationIssue :: RegistryValidationIssue -> Text

Implementation note: `formatValidationIssue (VersionMismatch d)` should
produce text such as

    modules.haskell-base: registry version (none) does not match module.dhall version 1.2.0

for `SyncMissing` and

    modules.nix-flake: registry version 0.3.0 does not match module.dhall version 0.4.0

for `SyncStale`. Use `kindPrefix` and `renderVersion` semantics consistent
with `Seihou.CLI.Registry.Sync.renderSyncReport` (mirror the wording but
keep this formatter in `Core.Registry` since it does no IO).

#### Tests for M1

`seihou-core/test/Seihou/Core/RegistrySpec.hs` already contains a
`describe "validateRegistry"` block. Add a parallel `describe
"validateRegistryFull"` block in the same file with these cases:

1. Fully clean registry (all entries valid + versions match) returns
   `reportIssues = []` and the right counts.
2. One entry whose registry version is `Nothing` while the lookup gives
   `Just "1.0.0"` produces a single `VersionMismatch` with `SyncMissing`
   status.
3. One entry whose registry version is `Just "1.0.0"` while the lookup
   gives `Just "2.0.0"` produces a single `VersionMismatch` with
   `SyncStale "2.0.0"`.
4. An invalid module name (uppercase) produces a single `StructuralError`.
5. A path with `..` produces a single `StructuralError`.
6. Multiple kinds of issues coexist: build a registry with one valid entry,
   one missing-file entry (no `module.dhall` written under the path), and
   one stale-version entry; assert the report has the three issues, in that
   order (structural first, then version).

Each test constructs the registry value directly and supplies the lookup
list inline (no Dhall round-trip needed for unit tests at this layer).


### M2 — CLI subcommand wiring and handler

After this milestone, `seihou registry validate` parses, runs, prints a
report, and exits 0/1 appropriately. Three files change.

#### `seihou-cli/src/Seihou/CLI/Registry.hs`

Replace the existing module body with:

    module Seihou.CLI.Registry
      ( RegistryCommand (..),
        handleRegistry,
      )
    where

    import GHC.Generics (Generic)
    import Seihou.CLI.Registry.Sync (SyncVersionsOpts, handleSyncVersions)
    import Seihou.CLI.Registry.Validate
      ( ValidateRegistryOpts,
        handleValidate,
      )

    data RegistryCommand
      = RegistrySyncVersions SyncVersionsOpts
      | RegistryValidate ValidateRegistryOpts
      deriving stock (Eq, Show, Generic)

    handleRegistry :: RegistryCommand -> IO ()
    handleRegistry (RegistrySyncVersions opts) = handleSyncVersions opts
    handleRegistry (RegistryValidate opts) = handleValidate opts

Update the doc comment that previously said "registry validate" was a
future operation: now mention `registry add` and `registry publish` as the
remaining future operations.

#### `seihou-cli/src/Seihou/CLI/Registry/Validate.hs` (new file)

This is the IO core of the new subcommand. Skeleton:

    module Seihou.CLI.Registry.Validate
      ( ValidateRegistryOpts (..),
        ValidateOutcome (..),
        runValidate,
        handleValidate,
        renderValidationReport,
      )
    where

    import Data.Text qualified as T
    import Data.Text.IO qualified as TIO
    import GHC.Generics (Generic)
    import Seihou.Core.Registry
      ( Registry (..),
        RegistryValidationReport (..),
        RegistryValidationIssue (..),
        RepoContents (..),
        discoverRepoContents,
        formatValidationIssue,
        reportHasIssues,
        validateRegistryFull,
      )
    import Seihou.CLI.Registry.Sync
      ( -- exposed by adding this symbol to the export list of Sync.hs
        resolveOnDiskVersionsExported,
      )
    import Seihou.Dhall.Eval (evalRegistryFromFile)
    import Seihou.Prelude
    import System.Directory (doesDirectoryExist)
    import System.Exit (ExitCode (..), exitWith)
    import System.IO (hPutStrLn, stderr)

    data ValidateRegistryOpts = ValidateRegistryOpts
      { validateRegistryDir :: Maybe FilePath
      }
      deriving stock (Eq, Show, Generic)

    data ValidateOutcome
      = -- | Report ran. Contains the structured report; caller decides
        -- exit code based on 'reportHasIssues'.
        ValidateOk RegistryValidationReport
      | -- | Couldn't even start (no registry at target dir, etc.).
        ValidateFailed Text
      deriving stock (Eq, Show, Generic)

    runValidate :: ValidateRegistryOpts -> IO ValidateOutcome
    runValidate opts = do
      let target = maybe "." id opts.validateRegistryDir
      ok <- doesDirectoryExist target
      if not ok
        then pure (ValidateFailed ("target directory does not exist: " <> T.pack target))
        else do
          contents <- discoverRepoContents evalRegistryFromFile target
          case contents of
            MultiModule reg -> do
              lookups <- resolveOnDiskVersionsExported target reg
              report <- validateRegistryFull target reg lookups
              pure (ValidateOk report)
            _ ->
              pure (ValidateFailed
                "registry validate requires a seihou-registry.dhall at the target directory")

    handleValidate :: ValidateRegistryOpts -> IO ()
    handleValidate opts = do
      outcome <- runValidate opts
      case outcome of
        ValidateFailed msg -> do
          hPutStrLn stderr ("error: " <> T.unpack msg)
          exitWith (ExitFailure 1)
        ValidateOk report -> do
          TIO.putStr (renderValidationReport report)
          if reportHasIssues report
            then exitWith (ExitFailure 1)
            else exitWith ExitSuccess

    renderValidationReport :: RegistryValidationReport -> Text
    renderValidationReport r
      | null r.reportIssues =
          T.unlines
            [ "OK: "
                <> T.pack (show r.reportModuleCount)
                <> " "
                <> pluralize r.reportModuleCount "module" "modules"
                <> ", "
                <> T.pack (show r.reportRecipeCount)
                <> " "
                <> pluralize r.reportRecipeCount "recipe" "recipes"
                <> ", all versions in sync."
            ]
      | otherwise =
          T.unlines $
            ["errors:"]
              <> map (("  " <>) . formatValidationIssue) r.reportIssues
              <> [""]
              <> [summary r]

    summary :: RegistryValidationReport -> Text
    summary r =
      let n = length r.reportIssues
          versionMismatches = [() | VersionMismatch _ <- r.reportIssues]
          base = T.pack (show n) <> " " <> pluralize n "error" "errors"
          tail =
            if null versionMismatches
              then "."
              else ". Run `seihou registry sync-versions` to fix version drift."
       in base <> tail

    pluralize :: Int -> Text -> Text -> Text
    pluralize 1 s _ = s
    pluralize _ _ p = p

Note the import `resolveOnDiskVersionsExported` — `Seihou.CLI.Registry.Sync`
currently keeps `resolveOnDiskVersions` private. As part of M2, add it to
the export list of `seihou-cli/src/Seihou/CLI/Registry/Sync.hs` (rename to
the same name; no `Exported` suffix is necessary — that suffix above is
purely a placeholder for the planning skeleton). Concretely, edit the
header of `Sync.hs`:

    module Seihou.CLI.Registry.Sync
      ( SyncVersionsOpts (..),
        SyncAction (..),
        SyncOutcome (..),
        runSync,
        handleSyncVersions,
        renderSyncReport,
        checkRegistryVersionDrift,
        resolveOnDiskVersions,
      )
    where

so the new module reuses the existing helper instead of duplicating it.

#### `seihou-cli/seihou-cli.cabal`

Add the new library module to `library seihou-cli-internal`'s
`exposed-modules` list (the order is alphabetical-ish; place it adjacent to
`Seihou.CLI.Registry.Sync`):

    Seihou.CLI.Registry.Sync
    Seihou.CLI.Registry.Validate

#### `seihou-cli/src-exe/Seihou/CLI/Commands.hs`

Two edits:

1. Re-export the new `ValidateRegistryOpts` type. Add it to the module
   export list so `Main.hs` and other consumers can pattern-match if
   needed:

       module Seihou.CLI.Commands
         ( ...
           SyncVersionsOpts (..),
           ValidateRegistryOpts (..),
           ...

   And add the import:

       import Seihou.CLI.Registry.Validate (ValidateRegistryOpts (..))

2. Extend the `registryCommandParser` (line 1045 in the current file) to
   include the new subcommand. Replace its body with:

       registryCommandParser :: Parser RegistryCommand
       registryCommandParser =
         hsubparser
           ( command "sync-versions" syncVersionsInfo
               <> command "validate" validateRegistryInfo
           )

   And add new helpers below `syncVersionsParser`:

       validateRegistryInfo :: ParserInfo RegistryCommand
       validateRegistryInfo =
         info
           (validateRegistryParser <**> helper)
           ( fullDesc
               <> progDesc "Check that registry entries match their on-disk modules"
               <> footerDoc
                 ( Just $
                     vsep
                       [ pretty ("Validates a multi-module repository's seihou-registry.dhall:" :: String),
                         indent 2 $
                           vsep
                             [ pretty ("- every entry path resolves to a module.dhall / recipe.dhall" :: String),
                               pretty ("- entry names match [a-z][a-z0-9-]*" :: String),
                               pretty ("- no name collisions between modules and recipes" :: String),
                               pretty ("- entry paths are relative and contain no '..'" :: String),
                               pretty ("- each entry's `version` matches the underlying module/recipe" :: String)
                             ],
                         line,
                         pretty ("Exits 1 on any failure. Run from a writable checkout of the registry repo." :: String)
                       ]
                 )
           )

       validateRegistryParser :: Parser RegistryCommand
       validateRegistryParser =
         fmap RegistryValidate $
           ValidateRegistryOpts
             <$> optional
               ( option
                   str
                   ( long "dir"
                       <> metavar "PATH"
                       <> help "Registry repo root (default: current directory)"
                   )
               )

3. Update the `registryInfo` footer "Current subcommands:" block to list
   both subcommands:

       indent 2 $
         vsep
           [ pretty ("sync-versions   Copy each module's declared version into the registry" :: String),
             pretty ("validate        Check that registry entries match their on-disk modules" :: String)
           ],

No edit to `seihou-cli/src-exe/Main.hs` is required — `handleRegistry`
already dispatches by constructor.


### M3 — Tests for the CLI handler

After this milestone, the test suite covers the success path, the
version-drift path, the missing-file path, and the missing-registry path.

Create `seihou-cli/test/Seihou/CLI/Registry/ValidateSpec.hs`:

    {-# LANGUAGE OverloadedStrings #-}

    module Seihou.CLI.Registry.ValidateSpec (tests) where

    import Data.Text (Text)
    import Data.Text qualified as T
    import Data.Text.IO qualified as TIO
    import Seihou.CLI.Registry.Validate
      ( ValidateOutcome (..),
        ValidateRegistryOpts (..),
        runValidate,
      )
    import Seihou.Core.Registry
      ( RegistryValidationIssue (..),
        RegistryValidationReport (..),
        SyncStatus (..),
        SyncDiff (..),
      )
    import System.Directory (createDirectoryIfMissing)
    import System.FilePath ((</>))
    import System.IO.Temp (withSystemTempDirectory)
    import Test.Hspec
    import Test.Tasty
    import Test.Tasty.Hspec (testSpec)

    tests :: IO TestTree
    tests = testSpec "Seihou.CLI.Registry.Validate" spec

    spec :: Spec
    spec = do
      describe "runValidate" $ do
        it "succeeds with no issues for a clean registry" $ do
          withCleanFixture $ \dir -> do
            outcome <- runValidate (ValidateRegistryOpts (Just dir))
            case outcome of
              ValidateOk r -> do
                r.reportIssues `shouldBe` []
                r.reportModuleCount `shouldBe` 2
                r.reportRecipeCount `shouldBe` 0
              other -> expectationFailure ("expected ValidateOk, got " <> show other)

        it "flags both stale and missing version entries" $ do
          withDriftedFixture $ \dir -> do
            outcome <- runValidate (ValidateRegistryOpts (Just dir))
            case outcome of
              ValidateOk r -> do
                let statuses =
                      [ d.diffStatus
                      | VersionMismatch d <- r.reportIssues
                      ]
                statuses `shouldBe` [SyncMissing, SyncStale "2.0.0"]
              other -> expectationFailure ("unexpected outcome: " <> show other)

        it "flags structural issues alongside version issues" $ do
          withMissingFileFixture $ \dir -> do
            outcome <- runValidate (ValidateRegistryOpts (Just dir))
            case outcome of
              ValidateOk r -> do
                let structurals =
                      [ msg
                      | StructuralError msg <- r.reportIssues
                      ]
                any ("missing module.dhall" `T.isInfixOf`) structurals
                  `shouldBe` True
              other -> expectationFailure ("unexpected outcome: " <> show other)

        it "fails when there is no registry at the target directory" $ do
          withSystemTempDirectory "seihou-validate-empty" $ \dir -> do
            outcome <- runValidate (ValidateRegistryOpts (Just dir))
            case outcome of
              ValidateFailed _ -> pure ()
              ValidateOk _ ->
                expectationFailure "expected ValidateFailed for empty directory"

The three fixtures (`withCleanFixture`, `withDriftedFixture`,
`withMissingFileFixture`) follow the same shape as `withFixture` in
`SyncSpec.hs`. Reuse the helpers `writeModuleDhall` and `registryDhall`
from that file by importing them, or duplicate them locally — duplication
is acceptable here because `SyncSpec.hs` does not currently expose its
helpers and a refactor is out of scope. The clean fixture writes both
modules at version `1.0.0` *and* lists them at version `1.0.0` in the
registry.

Register the new spec module in two places:

1. `seihou-cli/seihou-cli.cabal` — add to the `test-suite seihou-cli-test`
   `other-modules` list:

       Seihou.CLI.Registry.SyncSpec
       Seihou.CLI.Registry.ValidateSpec

2. `seihou-cli/test/Main.hs` — import and include in the test list:

       import Seihou.CLI.Registry.ValidateSpec qualified as RegistryValidateSpec
       ...
       sequence
         [ ...
         , RegistrySyncSpec.tests
         , RegistryValidateSpec.tests
         , ...
         ]

Run `cabal test seihou-cli-test --test-show-details=direct` from the repo
root and confirm the new four test cases pass.


### M4 — Documentation

After this milestone, every place that documents `seihou registry`
mentions `validate`.

#### `docs/cli/registry.md`

Add a third-level section after the existing `## seihou registry
sync-versions` section:

    ---

    ## seihou registry validate

    Check that a multi-module repository's `seihou-registry.dhall` is
    well-formed and that every entry's `version` field agrees with the
    underlying `module.dhall` or `recipe.dhall`.

    ### Usage

    ```
    seihou registry validate [OPTIONS]
    ```

    ### Options

    | Option | Description |
    |--------|-------------|
    | `--dir PATH` | Registry repo root. Defaults to the current directory. |

    ### Description

    Combines two existing checks into a single command:

    1. **Structural** — every entry's `path` resolves to a `module.dhall`
       or `recipe.dhall`, every `name` matches `[a-z][a-z0-9-]*`, no
       module name collides with a recipe name, no path is absolute or
       contains `..`.
    2. **Version** — every entry's `version` field equals the `version`
       declared in the on-disk `module.dhall` / `recipe.dhall`. A missing
       registry version (where the module declares one) and a stale
       registry version both fail validation.

    Exits 0 on a clean registry and 1 on any failure. Suitable for CI
    pre-merge checks. Unlike `seihou registry sync-versions --check`,
    this also catches structural problems (renamed modules, illegal
    paths, name collisions).

    ### Examples

    ```sh
    seihou registry validate
    seihou registry validate --dir ./my-templates
    ```

    ### CI usage

    ```yaml
    - run: seihou registry validate
    ```

Update the subcommands table at the top of the file:

    | Command | Description |
    |---------|-------------|
    | `sync-versions` | Copy each module's declared version into the registry |
    | `validate`      | Check that entries and versions match their modules |

And update the "Future subcommands" mention to drop `validate` from the
list (leaving `add` and `publish`).

#### `docs/user/registries-and-multi-module-repos.md`

Find the existing "Keeping versions in sync" section (added by ExecPlan
12) and append a paragraph:

    For a single one-shot check that catches both version drift *and*
    structural issues like a renamed module directory or an illegal
    path, run `seihou registry validate`. The command exits non-zero on
    any problem and is suitable for CI. See `docs/cli/registry.md` for
    the full option reference.

#### `CHANGELOG.md`

Add under the existing "## Unreleased" section (or create one):

    ### Added
    - `seihou registry validate`: check that registry entries match their
      on-disk modules, including a strict `version` equality check. Exits
      non-zero on any failure (structural or version drift). See
      `docs/cli/registry.md`.


### M5 — Manual end-to-end

After this milestone, the implementor has watched the command surface
each failure mode and the clean case at least once.

From the repo root, run the following recipe in a throwaway temp dir:

    REPO=$(mktemp -d -t seihou-validate-XXXX)
    cd "$REPO"

    # Create two modules
    cabal run seihou-cli:seihou -- new-module alpha
    cabal run seihou-cli:seihou -- new-module beta

    # Hand-write a registry that exercises every failure mode at once:
    #   - version drift on alpha (registry says 0.0.1 but module says 0.1.0)
    #   - missing version on beta (registry says None Text)
    #   - bogus entry "missing-mod" pointing nowhere
    #   - illegal name "Bad_Name" pointing at alpha
    #   - illegal path "../escape" on a fifth entry
    cat > seihou-registry.dhall <<'EOF'
    { repoName = "Demo"
    , repoDescription = None Text
    , modules =
      [ { name = "alpha"
        , version = Some "0.0.1"
        , path = "alpha"
        , description = None Text
        , tags = [] : List Text
        }
      , { name = "beta"
        , version = None Text
        , path = "beta"
        , description = None Text
        , tags = [] : List Text
        }
      , { name = "missing-mod"
        , version = None Text
        , path = "no-such-dir"
        , description = None Text
        , tags = [] : List Text
        }
      , { name = "Bad_Name"
        , version = None Text
        , path = "alpha"
        , description = None Text
        , tags = [] : List Text
        }
      , { name = "escape"
        , version = None Text
        , path = "../escape"
        , description = None Text
        , tags = [] : List Text
        }
      ]
    , recipes = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }
    }
    EOF

    cabal run seihou-cli:seihou -- registry validate

The expected output is a non-zero exit and a report listing five issues:
two `StructuralError` rows for the missing dir / bad name / unsafe path
(some merge into one row depending on which checks `validateRegistry`
emits), and two `VersionMismatch` rows for `alpha` and `beta`.

Then:

    # Delete the bad entries, sync versions, re-run validate
    cabal run seihou-cli:seihou -- registry sync-versions --dir "$REPO"
    # also hand-edit seihou-registry.dhall to remove the three bad entries
    cabal run seihou-cli:seihou -- registry validate

The second invocation should print

    OK: 2 modules, 0 recipes, all versions in sync.

and exit 0.

Record the observed report content in the Surprises & Discoveries
section if anything diverges from the predicted text.


## Concrete Steps

The commands below are run from the repo root unless noted otherwise.
Each step is idempotent: re-running has no destructive effect.

### Build

    cabal build all

Expected: both `seihou-core` and `seihou-cli` build cleanly. After M2 the
new module compiles; after M3 the test suite picks up the new spec.

### Test

    cabal test all --test-show-details=direct

Expected: every existing spec passes plus the four new cases in
`Seihou.CLI.Registry.Validate`. The first time you run after adding the
new module, you may need to run `cabal build` once first to update the
build plan.

### Lint / format

    just fmt
    just check

(See `Justfile` for what these wrap. `check` runs `nix flake check`
which in turn invokes `nix/check-cli-module-placement.sh` — that script
will fail if `Seihou.CLI.Registry.Validate` accidentally lands under
`other-modules` of `executable seihou` instead of `library
seihou-cli-internal`'s `exposed-modules`.)

### Run

    cabal run seihou-cli:seihou -- registry validate --help

Expected output: a short `progDesc`, the `--dir PATH` option line, and
the footer block listing the five validation rules.

### Demo (M5)

See M5 above for the full recipe.


## Validation and Acceptance

Acceptance is observable behavior, not "the code compiles":

1. **`seihou registry validate --help` prints the new help text.** Run
   the command above and confirm the description mentions every one of
   the five rules.

2. **A clean registry validates with exit 0 and the OK summary.** From
   M3's clean fixture, run `runValidate` in `cabal repl` or via the test
   suite and observe `ValidateOk r` with `reportIssues = []`. From M5's
   clean state, run the binary and observe stdout begins with `OK: ...`
   and `$? = 0`.

3. **A drifted registry exits 1 with one row per drift.** From M3's
   drifted fixture, observe `[VersionMismatch d, VersionMismatch d']`
   with statuses `SyncMissing` and `SyncStale "2.0.0"`. From M5,
   confirm the binary's exit code is 1 and that the printed text
   mentions `(none) does not match` and `does not match` with the
   expected version pair.

4. **A registry with a missing module directory exits 1 with the
   structural error reported.** From M3's missing-file fixture, observe
   at least one `StructuralError msg` with `"missing module.dhall"
   isInfixOf msg`.

5. **A directory without `seihou-registry.dhall` fails fast with a
   clear stderr message.** Run

        cabal run seihou-cli:seihou -- registry validate --dir /tmp

   and observe stderr mentioning "registry validate requires a
   seihou-registry.dhall" and exit code 1.

6. **`nix/check-cli-module-placement.sh` accepts the new module.** Run
   `just check` and confirm the script does not flag
   `Seihou.CLI.Registry.Validate`.

A failure of any of (1)–(6) is a regression and must be addressed before
the plan is marked complete.


## Idempotence and Recovery

The new command is read-only: it never writes `seihou-registry.dhall`,
never touches `module.dhall` files, and never alters any project state.
Running it any number of times is safe.

The implementation steps themselves are all additive (new types, new
module, new parser branch). Recovery from a partial implementation is
either to delete the new file/branch or to commit and continue — there
is no schema migration, no on-disk format change, and no data hazard.

If `cabal test` fails after adding the new spec, the most likely cause
is forgetting to add the spec to **both** `seihou-cli/seihou-cli.cabal`
(`other-modules`) and `seihou-cli/test/Main.hs` (the `import` and the
`sequence` list). Re-check both.

If `nix/check-cli-module-placement.sh` fails, confirm the new module is
listed under `library seihou-cli-internal`'s `exposed-modules` and not
under `executable seihou`'s `other-modules`.


## Interfaces and Dependencies

This plan adds no new third-party dependencies. Every required import
is already available transitively through `seihou-core` and the
existing `seihou-cli-internal` library.

After the work is complete, the following symbols and signatures must
exist:

In `seihou-core/src/Seihou/Core/Registry.hs`:

    data RegistryValidationIssue
      = StructuralError Text
      | VersionMismatch SyncDiff
      deriving stock (Eq, Show, Generic)

    data RegistryValidationReport = RegistryValidationReport
      { reportIssues :: [RegistryValidationIssue],
        reportModuleCount :: Int,
        reportRecipeCount :: Int
      }
      deriving stock (Eq, Show, Generic)

    reportHasIssues :: RegistryValidationReport -> Bool

    validateRegistryFull ::
      FilePath ->
      Registry ->
      [(EntryKind, ModuleName, Maybe Text)] ->
      IO RegistryValidationReport

    formatValidationIssue :: RegistryValidationIssue -> Text

In `seihou-cli/src/Seihou/CLI/Registry/Sync.hs`, the previously private
helper is exported:

    resolveOnDiskVersions ::
      FilePath ->
      Registry ->
      IO [(EntryKind, ModuleName, Maybe Text)]

In `seihou-cli/src/Seihou/CLI/Registry/Validate.hs` (new file):

    data ValidateRegistryOpts = ValidateRegistryOpts
      { validateRegistryDir :: Maybe FilePath
      }
      deriving stock (Eq, Show, Generic)

    data ValidateOutcome
      = ValidateOk RegistryValidationReport
      | ValidateFailed Text
      deriving stock (Eq, Show, Generic)

    runValidate :: ValidateRegistryOpts -> IO ValidateOutcome
    handleValidate :: ValidateRegistryOpts -> IO ()
    renderValidationReport :: RegistryValidationReport -> Text

In `seihou-cli/src/Seihou/CLI/Registry.hs`:

    data RegistryCommand
      = RegistrySyncVersions SyncVersionsOpts
      | RegistryValidate ValidateRegistryOpts
      deriving stock (Eq, Show, Generic)

    handleRegistry :: RegistryCommand -> IO ()

The `ValidateRegistryOpts` type is also re-exported from
`Seihou.CLI.Commands` so that `Main.hs` and downstream tooling can
pattern-match on it without an extra import (matching the existing
re-export of `SyncVersionsOpts`).
