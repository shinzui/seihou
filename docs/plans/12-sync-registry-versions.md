# Sync Module Versions into Registry Metadata

Intention: intention_01kpnncxrfenttm6srv77700g7

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

`seihou-registry.dhall` advertises the modules and recipes a repository offers. The
`version` field on each entry already exists in the schema (see
`seihou-core/src/Seihou/Core/Registry.hs:19` and the decoder at
`seihou-core/src/Seihou/Dhall/Eval.hs:432`), but three things are missing in
practice:

1. Registry authors do not know the field exists — `docs/user/registries-and-multi-module-repos.md`
   documents `name`, `path`, `description`, `tags`, but not `version`.
2. The scaffold/example registries in the docs and bootstrap prompt omit `version`,
   so newly written registries never carry it.
3. There is no tooling that reads each module's `module.dhall`, extracts its
   declared version, and writes the result into the registry. Every registry today
   either has no versions, or the author maintains them by hand and they drift
   silently from the `module.dhall` files.

The downstream cost is that external tooling (including `seihou outdated` and
`seihou browse`) must clone the repo and evaluate every `module.dhall` just to
learn the current version of each module. `Outdated.findAvailableVersion`
(`seihou-cli/src/Seihou/CLI/Outdated.hs:190`) already prefers the registry entry's
version and falls back to evaluating `module.dhall`, so a populated registry would
eliminate N extra Dhall evaluations per browse/outdated invocation.

After this change:

- A new authoring command group `seihou registry` lands with its first
  subcommand `seihou registry sync-versions`. The subcommand reads a local
  repo's `seihou-registry.dhall`, evaluates each entry's `module.dhall` /
  `recipe.dhall`, and rewrites the registry file with current versions
  populated. The grouping reserves space for future operations
  (`registry add`, `registry validate`, `registry publish`) without
  further CLI restructuring.
- `--check` exits non-zero if any registry entry's version is missing or out of
  sync with the underlying module — suitable for CI.
- `--dry-run` prints the change set without writing.
- Documentation explains the `version` field on registry entries, including how
  it lets tooling skip per-module evaluation, and shows
  `registry sync-versions` usage.

A registry author will be able to run, inside a multi-module repository checkout:

    seihou registry sync-versions

and see output like:

    Updated seihou-registry.dhall:
      modules.haskell-base:  (none)    -> 1.0.0
      modules.nix-flake:     0.3.0     -> 0.4.0
      modules.github-ci:     0.2.0     == 0.2.0 (no change)
      recipes.haskell-library: (none)  -> 0.1.0

    2 entries updated, 1 unchanged.

    seihou registry sync-versions --check


## Progress

- [x] M1: Document `version` field on registry entries in
      `docs/user/registries-and-multi-module-repos.md` and update the
      example at `seihou-cli/data/bootstrap-prompt.md` to include versions.
      (2026-04-20)
- [x] M1: Add a Dhall serializer
      (`Seihou.Core.Registry.renderRegistryDhall`) that emits a
      `seihou-registry.dhall`-compatible file from a `Registry` value; unit
      tests cover round-trip (`renderRegistryDhall` ∘ `evalRegistryFromFile`
      is an identity up to whitespace). (2026-04-20)
- [x] M2: Add `Seihou.Core.Registry.SyncReport` and a pure function
      `computeRegistrySync :: Registry -> [(EntryKind, ModuleName, Maybe Text)] -> SyncReport`
      that classifies each registry entry as `Missing | Stale | InSync | Orphan`.
      (2026-04-20)
- [x] M2: Write unit tests for `computeRegistrySync` covering all four classifications
      plus the empty-registry case. (2026-04-20)
- [x] M3: Add `RegistryCommand` sum with constructor `RegistrySyncVersions
      SyncVersionsOpts` and a `Registry RegistryCommand` top-level constructor
      on `Command` in `Seihou.CLI.Commands`. Wire a `registry` subparser under
      the "Authoring:" group whose only nested command (for now) is
      `sync-versions`, with flags `--dir PATH`, `--dry-run`, `--check`.
      (2026-04-20)
- [x] M3: Implement `Seihou.CLI.Registry.Sync.handleSyncVersions` that
      resolves each entry's version from disk, calls `computeRegistrySync`,
      prints the diff table, and writes the updated file (unless `--dry-run`
      or `--check`). Split a pure `runSync` core for testability. (2026-04-20)
- [x] M3: Dispatch the `Registry` branch (and its nested `RegistrySyncVersions`
      case) in `seihou-cli/src/Main.hs`. (2026-04-20)
- [x] M3: Integration test: build a fixture registry repo under a temp dir with
      two module dirs, run `runSync` in-process, verify the rewritten
      `seihou-registry.dhall` parses back to a `Registry` with the expected
      versions. Plus dry-run / check / missing-registry cases. (2026-04-20)
- [x] M4: Add `formatDriftWarning` (pure) in `Seihou.Core.Registry` and
      `checkRegistryVersionDrift` (IO) in `Seihou.CLI.Registry.Sync` (the CLI
      layer, since drift-check requires Dhall evaluation and `Core.Registry`
      is imported by `Seihou.Dhall.Eval`). Surface warnings via `logWarn`
      through `seihou browse` and `seihou install` when a MultiModule
      registry has drift. (2026-04-20)
- [ ] M5: Add a `docs/cli/registry.md` page (covering the `registry` group and
      the `sync-versions` subcommand) and a `CHANGELOG.md` entry under
      Unreleased. Update `docs/user/registries-and-multi-module-repos.md` with
      a "Keeping versions in sync" section pointing at the new command.
- [ ] M5: Manual end-to-end: inside the working tree's fixture
      `seihou-core/test/fixtures/` (or a throwaway tmp repo) create a registry,
      run `cabal run seihou -- registry sync-versions --dir <path> --dry-run`,
      confirm output, then run without `--dry-run` and verify the file is
      rewritten.


## Surprises & Discoveries

- The Progress skeleton listed `computeRegistrySync` with a 4-tuple
  `(EntryKind, ModuleName, Maybe Text, Maybe Text)` lookup entry, but the
  old version is already reachable through the `Registry` argument, so the
  lookup only needs to carry the on-disk version: `(EntryKind, ModuleName,
  Maybe Text)`. That matches the signature in Milestone 2's body text and
  the Interfaces section. Implementation followed the simpler signature.
  (2026-04-20)
- Needed a 3-state helper `OnDiskVersion = OnDiskMissing | OnDiskValue
  (Maybe Text)` internally, because a lookup returning `Nothing` has to
  distinguish \"entry absent from lookup list → SyncOrphan\" from \"entry
  present with version = None → SyncInSync with unversioned module.dhall\".
  (2026-04-20)
- `module.version` / `recipe.version` record-dot access fails in
  `Seihou.CLI.Registry.Sync` under `NoFieldSelectors` + `DuplicateRecordFields`
  — the module already uses `RegistryEntry.version`, so GHC cannot infer a
  `HasField` instance at `m.version`. Worked around by pattern-matching
  accessor helpers (`moduleVersion`, `recipeVersion`). (2026-04-20)
- `checkRegistryVersionDrift` cannot live in `Seihou.Core.Registry` as the
  plan originally suggested — it needs `evalModuleFromFile` /
  `evalRecipeFromFile` from `Seihou.Dhall.Eval`, which itself imports
  `Seihou.Core.Registry`. Moved the drift-check helper up one layer into
  `Seihou.CLI.Registry.Sync` and kept only a pure formatter
  (`formatDriftWarning :: SyncDiff -> Maybe Text`) in Core. (2026-04-20)


## Decision Log

- Decision: Scope "manifest" in the user's request as `seihou-registry.dhall`, not
  the per-project `.seihou/manifest.json`.
  Rationale: The user framed the feature as "enhance registry metadata to capture
  module versions to make it easier on tooling so they don't have to check each
  module for its version." The per-project manifest already records installed
  versions (see `Seihou.Manifest.Types`), and external tooling inspecting a
  git repo only sees `seihou-registry.dhall`. The user confirmed via a follow-up
  message that the ask is a CLI command.
  Date: 2026-04-20

- Decision: Rewrite `seihou-registry.dhall` from the decoded `Registry` value
  rather than patching the source text.
  Rationale: Dhall is a language, not a data format. An AST-preserving editor
  would need to handle imports, let-bindings, record completion, etc. Emitting
  a fresh record keeps the implementation tractable for v1. The cost — losing
  hand-written comments and formatting — is called out in the docs and is
  consistent with how `new-module` and `new-recipe` already emit Dhall.
  Date: 2026-04-20

- Decision: Ship the sync command as `seihou registry sync-versions` rather
  than a flat `seihou sync-registry`, grouped under "Authoring:".
  Rationale: It is strictly an authoring-time command (run against a writable
  checkout of a registry repo, not against an installed module). A nested
  `registry` group reserves space for future subcommands (e.g. `registry add`,
  `registry validate`, `registry publish`) without further CLI restructuring
  and without burning a top-level command slot per operation. The existing
  `kit` and `agent` groups (`Seihou.CLI.Commands.hs:264, 279`) are the
  precedent — both use a top-level constructor that wraps a sum of
  subcommands.
  Date: 2026-04-20

- Decision: `registry sync-versions` defaults to mutating the file in place;
  `--dry-run` and `--check` are opt-in read-only modes.
  Rationale: The name is imperative and the primary use case is "update my
  registry before publishing." A CI-friendly read-only mode is useful, but
  should not be the default, because authors running the command interactively
  want the file rewritten. `--check` exits 1 on drift so it composes with `just`
  / CI steps.
  Date: 2026-04-20

- Decision: Keep the existing `Outdated.findAvailableVersion` fallback that
  reads `module.dhall` when the registry entry omits `version`.
  Rationale: Some registries will remain unversioned for a while after this
  change ships. The fallback makes `sync-registry` an optimization, not a hard
  requirement. Tools continue to work with older registries.
  Date: 2026-04-20


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Seihou is a composable, type-safe project scaffolding tool written in Haskell
(GHC 9.12.2, GHC2024). The repository is a multi-package Cabal workspace with
`seihou-core` (library) and `seihou-cli` (executable). Dhall is used for all
configuration files.

Registry support landed in `docs/plans/registry-metadata-and-multi-module-repos.md`
and module versioning in `docs/plans/module-version-comparison.md`. Both are
checked-in plans; read them first if the registry or versioning background is
unclear.

Key files and current state:

`seihou-core/src/Seihou/Core/Registry.hs` defines:

    data RegistryEntry = RegistryEntry
      { name        :: ModuleName
      , version     :: Maybe Text
      , path        :: FilePath
      , description :: Maybe Text
      , tags        :: [Text]
      }

    data Registry = Registry
      { repoName        :: Text
      , repoDescription :: Maybe Text
      , modules         :: [RegistryEntry]
      , recipes         :: [RegistryEntry]
      }

    data RepoContents = SingleModule FilePath | SingleRecipe FilePath
                      | MultiModule Registry | EmptyRepo

    discoverRepoContents :: (FilePath -> IO (Either ModuleLoadError Registry))
                         -> FilePath -> IO RepoContents
    validateRegistry     :: FilePath -> Registry -> IO [Text]

The `version` field on `RegistryEntry` was added in the
`module-version-comparison.md` plan (M1 item at that plan's line 19) but was
never surfaced in the user documentation.

`seihou-core/src/Seihou/Dhall/Eval.hs:432` defines `registryEntryDecoder` with
`withDefaults [("version", noneText)]`, so registries written before the
`version` field was added still decode.

`seihou-core/src/Seihou/Core/Types.hs:236` defines `Module` with
`version :: Maybe Text`; `validate-module` enforces that `Some v` with non-empty
`v` is provided (see `docs/user/module-authoring.md:49`).

`seihou-core/src/Seihou/Core/Recipe.hs` (to be confirmed during implementation)
defines the `Recipe` record; `Types.hs:260` shows the `version :: Maybe Text`
field there as well.

`seihou-cli/src/Seihou/CLI/Commands.hs` is the `optparse-applicative` command
tree. The "Authoring:" group at line 263–270 currently contains `new-module`,
`new-recipe`, `validate-module`, `vars`, `schema-upgrade`. This is where the
new `sync-registry` entry belongs.

`seihou-cli/src/Seihou/CLI/Outdated.hs:190` already prefers the registry
entry's `version` over evaluating `module.dhall`. After this plan lands, a
populated registry eliminates N Dhall evaluations per `seihou outdated` call on
a multi-module repo — that is the "make it easier on tooling" payoff.

`seihou-core/src/Seihou/Core/Scaffold.hs` is the existing Dhall emitter for
`new-module`. It writes a text template that imports the schema via URL
(`let S = SCHEMA_URL SCHEMA_HASH`) and uses record completion (`S.Module::{…}`).
The new registry emitter in this plan uses the same style — a plain `T.unlines`
template, no schema import (registries do not yet have a published schema type).

`docs/user/registries-and-multi-module-repos.md` documents the registry format
for authors. The "Fields" table at lines 89–95 is where the `version` row must
be added. The full example at lines 51–79 must be updated to include `version`.

`seihou-cli/data/bootstrap-prompt.md:120–143` is the AI agent's reference for
writing a new registry; that example also needs `version`.


## Plan of Work

Five milestones, each independently verifiable.


### Milestone 1: Document the field, add a Dhall emitter

Make the existing `version` field discoverable and give the rest of the plan a
way to write registry files.

Docs changes:

- In `docs/user/registries-and-multi-module-repos.md`, add a `version` row to
  the Fields table (lines 89–95), type `Optional Text`, description: "Declared
  version of the entry, copied from the module's `module.dhall` /
  `recipe.dhall`. Populated by `seihou sync-registry`. Optional but
  recommended — tooling reads this instead of evaluating each module."
- Update the example at lines 51–79 to include `, version = Some "1.0.0"` on
  each entry. Add a note below the example pointing at `sync-registry`.
- In `seihou-cli/data/bootstrap-prompt.md` (lines 120 and 143), update the
  registry snippet the agent produces to include `version`.

Code changes:

- In `seihou-core/src/Seihou/Core/Registry.hs`, add:

        renderRegistryDhall :: Registry -> Text

  The output is a `seihou-registry.dhall`-compatible Dhall record emitted as a
  plain record literal (no schema import). It contains `repoName`,
  `repoDescription`, `modules`, `recipes`, matching the decoder's field set.
  Each entry renders `name`, `version`, `path`, `description`, `tags`.
  `Maybe Text` renders as `Some "…"` or `None Text`. Escape embedded `"` and
  `\` in strings with Dhall's double-single-quote form or backslash escape —
  prefer the latter for simplicity.
- Export `renderRegistryDhall` from `Seihou.Core.Registry`.
- Add a new unit-test module `seihou-core/test/Seihou/Core/RegistryEmitSpec.hs`
  that builds a `Registry` value, pipes it through
  `renderRegistryDhall`, writes the result to a temp file, parses it back via
  `evalRegistryFromFile`, and asserts equality. Include cases with: no recipes,
  multiple modules, a module with `version = Nothing`, and an entry whose
  `description` is `Nothing`.
- Register the new spec in `seihou-core/test/Main.hs` (or whichever aggregator
  imports RegistrySpec) and in `seihou-core.cabal`.

Verification:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal test seihou-core --test-options="--match \"RegistryEmit\""

All new tests pass; existing `cabal test all` is green.


### Milestone 2: Pure sync logic

Classify each registry entry against the on-disk module/recipe version without
any filesystem writes. This keeps the reporting and decision logic in
`seihou-core` and unit-testable.

In `seihou-core/src/Seihou/Core/Registry.hs`, add:

    data EntryKind = ModuleEntry | RecipeEntry
      deriving stock (Eq, Show)

    data SyncStatus
      = SyncMissing      -- registry has Nothing, module has Just v
      | SyncStale Text   -- registry Just old, module Just new, old /= new; Text is the new
      | SyncInSync       -- registry Just v == module Just v (or both Nothing)
      | SyncOrphan       -- registry entry present, module.dhall absent or unreadable
      deriving stock (Eq, Show)

    data SyncDiff = SyncDiff
      { diffKind       :: EntryKind
      , diffName       :: ModuleName
      , diffOld        :: Maybe Text
      , diffNew        :: Maybe Text
      , diffStatus     :: SyncStatus
      }
      deriving stock (Eq, Show)

    data SyncReport = SyncReport
      { syncDiffs    :: [SyncDiff]
      , syncUpdated  :: Registry  -- registry with new versions written in
      }
      deriving stock (Eq, Show)

    -- The IO-free core. Takes already-resolved module versions so it can be
    -- tested without touching the filesystem.
    computeRegistrySync
      :: Registry
      -> [(EntryKind, ModuleName, Maybe Text)]  -- on-disk versions keyed by name
      -> SyncReport

Behavior: for each existing registry entry, look up its `(kind, name)` in the
lookup list; emit a `SyncDiff` with the appropriate `SyncStatus`. Build
`syncUpdated` by replacing each entry's `version` with the on-disk version
(unless `SyncOrphan`, in which case leave it untouched).

Add `seihou-core/test/Seihou/Core/RegistrySyncSpec.hs` covering:

- All four `SyncStatus` classifications.
- Order preservation (diff entries appear in the same order as registry entries).
- `syncUpdated` on an empty registry equals the input.

Register the spec.

Verification:

    cabal test seihou-core --test-options="--match \"RegistrySync\""


### Milestone 3: Wire the CLI command

Introduce the user-facing `seihou registry sync-versions`, structured as a
nested command group so future registry operations can be added without
further restructuring.

In `seihou-cli/src/Seihou/CLI/Commands.hs`:

    data RegistryCommand
      = RegistrySyncVersions SyncVersionsOpts
      deriving stock (Eq, Show, Generic)

    data SyncVersionsOpts = SyncVersionsOpts
      { syncVersionsDir     :: Maybe FilePath  -- defaults to "."
      , syncVersionsDryRun  :: Bool
      , syncVersionsCheck   :: Bool
      }
      deriving stock (Eq, Show, Generic)

    -- Extend Command:
    -- | Registry RegistryCommand

Export `RegistryCommand (..)` and `SyncVersionsOpts (..)` from the module
header.

Add parsers:

- `registryInfo :: ParserInfo Command` wraps an `hsubparser` whose only
  current child is `command "sync-versions" syncVersionsInfo`. This matches
  the pattern used by `Agent` (`agentCommand :: AgentCommand`) and `Kit`
  (`KitCommand` sum) in the same file. Its `progDesc` is
  "Manage seihou-registry.dhall files"; its footer reserves future
  subcommands.
- `syncVersionsInfo :: ParserInfo RegistryCommand` wraps
  `pure RegistrySyncVersions <*> syncVersionsOptsParser`.

Wire `command "registry" registryInfo` into the "Authoring:" `hsubparser`
block alongside `validate-module` at lines 263–271.

Flags on `sync-versions`:

- `--dir PATH` (`strOption`, optional, default `Nothing` → treat as `.`)
- `--dry-run` (`switch`) — compute and print diff, do not write.
- `--check` (`switch`) — exit 1 if any diff is `SyncMissing | SyncStale _ |
  SyncOrphan`; print the report; do not write.

`--dry-run` and `--check` are mutually exclusive; `--check` takes precedence
if both are set (document in the help text).

Create `seihou-cli/src/Seihou/CLI/Registry.hs` as the group dispatcher and
`seihou-cli/src/Seihou/CLI/Registry/Sync.hs` as the `sync-versions` handler:

    module Seihou.CLI.Registry (handleRegistry) where

    handleRegistry :: RegistryCommand -> IO ()
    handleRegistry (RegistrySyncVersions opts) = handleSyncVersions opts

    module Seihou.CLI.Registry.Sync (handleSyncVersions) where

    handleSyncVersions :: SyncVersionsOpts -> IO ()

Flow:

1. Resolve target directory. Abort if it does not exist.
2. Call `discoverRepoContents evalRegistryFromFile targetDir`. Require
   `MultiModule registry`; otherwise print a descriptive error
   ("registry sync-versions requires a seihou-registry.dhall at the target
   directory") and exit 1.
3. For each entry in `registry.modules`, evaluate `<dir>/<entry.path>/module.dhall`
   via `evalModuleFromFile`; map `Right m -> Just m.version` (note: that's
   `Maybe (Maybe Text)`; flatten to `Maybe Text`). On `Left _` emit a
   `SyncOrphan`.
4. For each entry in `registry.recipes`, do the same with `recipe.dhall` and
   `evalRecipeFromFile`. (Confirm function name during implementation; if it
   does not exist, the milestone adds it in `Seihou.Dhall.Eval` as a thin
   wrapper analogous to `evalModuleFromFile`.)
5. Call `computeRegistrySync` with the collected lookup list.
6. Render the diff table to stdout (see Validation section for format).
7. If `--check`: exit 1 when any diff status ≠ `SyncInSync`; else exit 0.
8. Else if `--dry-run`: exit 0 without writing.
9. Else: write `renderRegistryDhall syncUpdated` to `<dir>/seihou-registry.dhall`,
   print a summary, exit 0.

Dispatch the new `Registry` branch wherever `Command` values are handled —
grep for `Install iopts ->` in `seihou-cli/src/` to find the dispatch site.
Add a `Registry rcmd -> handleRegistry rcmd` arm.

Integration test in `seihou-cli/test/Seihou/CLI/Registry/SyncSpec.hs`:

- Build a temp directory containing a `seihou-registry.dhall` plus two module
  subdirs whose `module.dhall` declare `version = Some "2.0.0"`.
- Populate the registry with `version = None Text` on the first entry and
  `version = Some "1.0.0"` on the second.
- Call `handleSyncVersions` via a small harness (since `handleSyncVersions ::
  IO ()` performs stdout printing and exitWith, consider splitting out a pure
  `runSync :: SyncVersionsOpts -> IO (SyncReport, ExitCode)` for testability).
- Assert the rewritten file parses back to a `Registry` with both entries at
  `Some "2.0.0"`.

Register the spec in the seihou-cli test runner (see existing test layout under
`seihou-cli/test/`).

Verification:

    cabal build all
    cabal test seihou-cli --test-options="--match \"Registry.Sync\""
    cabal run seihou -- registry --help
    cabal run seihou -- registry sync-versions --help

The `registry --help` output must list `sync-versions` as a subcommand.
The `registry sync-versions --help` output must list `--dir`, `--dry-run`,
`--check`.


### Milestone 4: Soft-warn on drift during validateRegistry

Let existing entry points (`browse`, `install`) surface a warning when a
registry's versions are stale — without blocking.

In `seihou-core/src/Seihou/Core/Registry.hs`, add a new function:

    checkRegistryVersionDrift
      :: FilePath  -- repo root
      -> Registry
      -> IO [Text]  -- warning strings

It reads each entry's on-disk module/recipe version (same mechanism as M3),
compares to the registry entry, and returns one warning line per non-sync
entry ("module 'haskell-base' registry version 1.0.0 differs from module.dhall
version 1.1.0 — run `seihou sync-registry`"). An empty list means no drift or
all entries have `SyncOrphan` (which `validateRegistry` already flags).

In `seihou-cli/src/Seihou/CLI/Browse.hs`, after a successful
`discoverRepoContents` with `MultiModule registry`, call
`checkRegistryVersionDrift` and print each warning to stderr via
`logWarn`. Do not block the browse.

In `seihou-cli/src/Seihou/CLI/Install.hs`, do the same at the start of the
multi-module install branch.

Test: add one case to `RegistrySyncSpec` verifying
`checkRegistryVersionDrift` produces a warning for a stale entry and no
warnings when everything is in sync.

Verification:

    cabal test seihou-core
    cabal test seihou-cli


### Milestone 5: User-facing docs and CHANGELOG

- Create `docs/cli/registry.md` modeled on the shortest existing per-command
  page under `docs/cli/`. Document the `registry` group and its current
  subcommand `sync-versions` — purpose, flags, examples (`--dry-run`,
  `--check`), CI usage snippet. Note that the group is extension-ready:
  future subcommands will land on the same page.
- Update `docs/user/registries-and-multi-module-repos.md` with a new section
  "Keeping versions in sync" linking to `docs/cli/registry.md` and
  explaining why populated `version` fields matter (fewer Dhall evals for
  tooling, faster `seihou outdated`).
- Append a Changelog entry to `CHANGELOG.md` under the current "Unreleased"
  heading (or create one if absent). Summarize: new `registry` command group
  with `sync-versions`, documented `version` field on registry entries,
  soft-warn on drift during browse/install.
- Manual end-to-end run:

        cd /tmp && rm -rf sync-fixture && mkdir sync-fixture && cd sync-fixture
        git init -q
        seihou new-module alpha
        seihou new-module beta
        # edit alpha/module.dhall and beta/module.dhall to have version "1.0.0"
        # hand-write seihou-registry.dhall with version = None Text on both
        seihou registry sync-versions --dry-run
        seihou registry sync-versions
        cat seihou-registry.dhall

  Verify the file now carries `Some "1.0.0"` on both entries.

Verification:

    cabal test all
    cabal run seihou -- help registry

Help page lists examples.


## Concrete Steps

All commands assume working directory
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

Build:

    cabal build all

Run all tests:

    cabal test all

Run one suite:

    cabal test seihou-core
    cabal test seihou-cli

Run the CLI under development:

    cabal run seihou -- registry --help
    cabal run seihou -- registry sync-versions --help
    cabal run seihou -- registry sync-versions --dir /path/to/registry-repo --dry-run

Commit with the `ExecPlan:` and `Intention:` trailers, following Conventional
Commits:

    git commit -m "$(cat <<'EOF'
    feat(registry): emit registry Dhall from Registry value

    Adds renderRegistryDhall and round-trip tests.

    ExecPlan: docs/plans/12-sync-registry-versions.md
    Intention: intention_01kpnncxrfenttm6srv77700g7
    EOF
    )"


## Validation and Acceptance

The feature is accepted when all of these hold.

1. Given a registry repo where every `module.dhall` declares a version but the
   registry entries have `version = None Text`, running
   `seihou registry sync-versions --dry-run` prints a diff table of the form:

        Updated seihou-registry.dhall:
          modules.alpha: (none) -> 1.0.0
          modules.beta:  (none) -> 1.0.0

        2 entries updated, 0 unchanged.

   and exits 0 without modifying the file.

2. Running `seihou registry sync-versions` in the same state rewrites the
   file so that `evalRegistryFromFile` returns a `Registry` whose entries
   have `version = Just "1.0.0"`. The file is otherwise a valid Dhall record.

3. Running `seihou registry sync-versions --check` on an in-sync registry
   exits 0 with "all entries in sync." Running it on a drifted registry
   exits 1 and prints the same diff table as `--dry-run`.

4. `seihou browse <url-of-drifted-repo>` and
   `seihou install <url-of-drifted-repo> --all` each print a warning per
   drifted entry to stderr but continue their normal behavior.

5. `seihou registry --help` lists `sync-versions` as a subcommand.
   `seihou registry sync-versions --help` shows `--dir`, `--dry-run`,
   `--check` with descriptions and a short usage example.

6. All existing tests continue to pass (`cabal test all`).

7. `docs/user/registries-and-multi-module-repos.md` documents the `version`
   field on registry entries, and `docs/cli/registry.md` exists.


## Idempotence and Recovery

- `sync-registry` is idempotent: running it twice with no changes in between
  is a no-op (the second run reports "0 entries updated").
- `--dry-run` and `--check` are read-only.
- The write is a single `TIO.writeFile` to `seihou-registry.dhall`. On failure
  (permissions, disk full), the original file is left untouched by the OS
  semantics of `writeFile` — but not atomically. If paranoia is warranted,
  write to `seihou-registry.dhall.tmp` and rename; call this out as a
  decision if the implementer chooses the atomic path.
- No network IO: the command only reads the local checkout.
- If `module.dhall`/`recipe.dhall` evaluation fails for an entry, the entry
  is reported `SyncOrphan` and its version is left as-is in the rewritten
  file. This prevents a single broken module from blanking out every
  version.


## Interfaces and Dependencies

New dependencies: none. All work uses existing libraries (`dhall`, `text`,
`directory`, `filepath`, `optparse-applicative`).

In `seihou-core/src/Seihou/Core/Registry.hs`:

    renderRegistryDhall       :: Registry -> Text
    data EntryKind            = ModuleEntry | RecipeEntry
    data SyncStatus           = SyncMissing | SyncStale Text | SyncInSync | SyncOrphan
    data SyncDiff             = SyncDiff { … }
    data SyncReport           = SyncReport { syncDiffs :: [SyncDiff], syncUpdated :: Registry }
    computeRegistrySync       :: Registry -> [(EntryKind, ModuleName, Maybe Text)] -> SyncReport
    checkRegistryVersionDrift :: FilePath -> Registry -> IO [Text]

In `seihou-core/src/Seihou/Dhall/Eval.hs` (only if missing):

    evalRecipeFromFile :: FilePath -> IO (Either ModuleLoadError Recipe)

In `seihou-cli/src/Seihou/CLI/Commands.hs`:

    data RegistryCommand
      = RegistrySyncVersions SyncVersionsOpts

    data SyncVersionsOpts = SyncVersionsOpts
      { syncVersionsDir    :: Maybe FilePath
      , syncVersionsDryRun :: Bool
      , syncVersionsCheck  :: Bool
      }
    -- Command extended with: | Registry RegistryCommand

In `seihou-cli/src/Seihou/CLI/Registry.hs` (new):

    handleRegistry :: RegistryCommand -> IO ()

In `seihou-cli/src/Seihou/CLI/Registry/Sync.hs` (new):

    handleSyncVersions :: SyncVersionsOpts -> IO ()

In `seihou-cli/src/Seihou/CLI/Browse.hs` and `Install.hs`:

    -- After discoverRepoContents yields MultiModule reg:
    warnings <- checkRegistryVersionDrift cloneDir reg
    mapM_ (logIO LogNormal . logWarn) warnings


## Revision Notes

- 2026-04-20 — Reshaped the CLI surface from a flat `seihou sync-registry`
  command to a nested `seihou registry sync-versions` to reserve the
  `registry` namespace for future subcommands (`registry add`,
  `registry validate`, `registry publish`, etc.). Decision Log, Progress,
  Milestone 3, Milestone 5, Validation, Concrete Steps, and Interfaces
  sections all updated to match. Module layout changed from
  `Seihou.CLI.SyncRegistry` to `Seihou.CLI.Registry` +
  `Seihou.CLI.Registry.Sync`.
