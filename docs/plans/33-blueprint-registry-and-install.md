---
id: 33
slug: blueprint-registry-and-install
title: "Registry and Multi-Module-Repository Support for Blueprints"
kind: exec-plan
created_at: 2026-05-07T00:00:00Z
intention: "intention_01kr2q5p3ye30t4vk9fj4q69t1"
---


# Registry and Multi-Module-Repository Support for Blueprints

MasterPlan: docs/masterplans/3-agent-driven-blueprints.md
Intention: intention_01kr2q5p3ye30t4vk9fj4q69t1

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

Seihou today recognises two runnable kinds — modules (`module.dhall`) and
recipes (`recipe.dhall`) — and ships a multi-module-repository system that
makes both shareable through `seihou install`, `seihou browse`, and the
`seihou registry sync-versions` / `seihou registry validate` workflow. The
registry surface is anchored on a `seihou-registry.dhall` file at a git
repo root which lists each module and recipe by name, path, description,
optional version, and tags.

EP-29 (`docs/plans/29-blueprint-domain-model-and-discovery.md`, the
foundation plan of this MasterPlan) introduces a third runnable kind, the
**blueprint** (`blueprint.dhall`). A blueprint is an agent-driven
scaffold that bundles a Markdown prompt, an optional list of base modules
to apply as a baseline, and an optional `files/` reference directory.
EP-29 ships the type, the Dhall decoder, the discovery branch, and a
`seihou run` refusal message; it does not ship registry support, install
support, or browse support.

This plan, EP-33, closes that gap. After it lands:

- A `seihou-registry.dhall` may carry a `blueprints` field alongside
  `modules` and `recipes`. Older registries decode unchanged with
  `blueprints = []`.
- `seihou install <git-url>` recognises a fourth repo shape,
  `SingleBlueprint`: a repository whose root contains only a
  `blueprint.dhall`. Such a repo installs at
  `~/.config/seihou/installed/<name>/`, mirroring `SingleModule` and
  `SingleRecipe`.
- `seihou install <git-url> --module NAME` and `seihou install <git-url>
  --all` against a multi-kind registry treat blueprint entries the same
  way they treat module and recipe entries.
- The interactive picker presents modules, recipes, and blueprints in
  one list with per-row kind labels (`[module]`, `[recipe]`,
  `[blueprint]`).
- `seihou browse` lists blueprints with the `[blueprint]` label and
  respects `--tag` filtering across all three kinds.
- `seihou registry sync-versions` walks `blueprints`, reads each
  `blueprint.dhall` version, and rewrites the registry to match. The
  diff output uses a `blueprints.NAME` prefix.
- `seihou registry validate` validates blueprint entries (path, name
  format, file presence, cross-kind name collisions, version drift) and
  reports a `blueprints.NAME` prefix.

A novice with this plan, the working tree at the time EP-29 has merged,
and the standard build commands must be able to deliver everything above
end-to-end.


## Progress

- [x] M1: Extend `Registry` with `blueprints :: [RegistryEntry]`, add `BlueprintEntry` to `EntryKind`, update `validateRegistry`/`checkNameCollisions`/`computeRegistrySync`/`validateRegistryFull`/`formatValidationIssue`/`validationKindPrefix`/`formatDriftWarning`, and `renderRegistryDhall` in `seihou-core/src/Seihou/Core/Registry.hs`.
- [x] M1: Update `registryDecoder` in `seihou-core/src/Seihou/Dhall/Eval.hs` so it accepts the new `blueprints` field and decodes pre-existing registries (no `blueprints` field) with `blueprints = []`.
- [x] M1: Add `SingleBlueprint FilePath` to `RepoContents` and extend `discoverRepoContents` to detect `blueprint.dhall` after the existing module/recipe probes.
- [x] M1: Add unit tests for the new field decoding, the backwards-compat path, three-way collision detection, sync classification of blueprint entries, validate-full integration, and `renderRegistryDhall` round-trip.
- [ ] M2: Update `handleInstall` in `seihou-cli/src-exe/Seihou/CLI/Install.hs` so `SingleBlueprint` installs the root directory; extend `installFromRegistry`/`selectModules`/`installRegistryEntry` to handle blueprints under `--all`, `--module`, and the interactive picker. Pass kind labels into the picker rows.
- [ ] M2: Update `handleBrowse` in `seihou-cli/src-exe/Seihou/CLI/Browse.hs` and the formatter at `seihou-cli/src/Seihou/CLI/BrowseFormat.hs` to render kind labels per row, filter blueprints by `--tag`, and handle the `SingleBlueprint` repo shape.
- [ ] M2: Add an end-to-end install test that drives `handleInstall` against a fixture multi-kind registry and verifies all three kinds land under a redirected `XDG_CONFIG_HOME`.
- [ ] M3: Update `resolveOnDiskVersions` and `kindPrefix` in `seihou-cli/src/Seihou/CLI/Registry/Sync.hs` to read each blueprint entry's `blueprint.dhall` and emit the `blueprints.NAME` prefix.
- [ ] M3: Update `renderValidationReport` in `seihou-cli/src/Seihou/CLI/Registry/Validate.hs` to count blueprints in the success summary.
- [ ] M3: Add tests covering sync-versions and validate against a registry with a blueprint entry whose on-disk version drifts from the registry's recorded version.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Keep the existing `--module NAME` flag on `seihou install`
  despite it now selecting modules, recipes, and blueprints. Renaming
  the flag (for example to `--entry NAME`) would break shell histories
  and scripts; the `selectModules` helper already treats modules and
  recipes as a single entry list keyed by name. Only the long-help text
  is updated to clarify the flag accepts module, recipe, and blueprint
  names. A future plan may introduce a parallel `--entry NAME` flag.
  Date: 2026-05-07.

- Decision: Precedence for `discoverRepoContents` becomes registry >
  module > recipe > blueprint. The first three already follow that
  order in `seihou-core/src/Seihou/Core/Registry.hs` lines 67-95.
  Blueprint slots in last because a multi-marker repo is overwhelmingly
  more likely to be intentionally registry-shaped than to be a
  blueprint-only repo with a stray module file. Authors of
  blueprint-only repos are expected to keep the root clean.
  Date: 2026-05-07.

- Decision: Backwards-compatibility for registries written before EP-33
  is delivered through `withDefaults` in
  `seihou-core/src/Seihou/Dhall/Eval.hs`, the same mechanism the
  `recipes` field uses today. The new `blueprints` default reuses the
  existing `emptyRegistryEntryList` Dhall expression. The known
  trade-off — a typo like `bluprints =` decodes as `blueprints = []` and
  is silently swallowed — is inherent to `withDefaults` and was
  accepted in the recipe rollout
  (`docs/plans/6-recipe-module-composition.md`).
  Date: 2026-05-07.


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

This plan touches three layers: the pure registry data model and
decoder in `seihou-core`, the install and browse CLI handlers in
`seihou-cli`, and the registry sub-commands (`sync-versions`,
`validate`) under `seihou-cli/src/Seihou/CLI/Registry/`. The
recipe-rollout pattern (every place a `ModuleEntry` case appears, a
`RecipeEntry` case follows immediately) is the mechanical template for
the blueprint additions.

The full file paths a novice must read before editing are
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/seihou-core/src/Seihou/Core/Registry.hs`
(home of `Registry`, `RegistryEntry`, `RepoContents`,
`discoverRepoContents`, `validateRegistry`, `EntryKind`,
`computeRegistrySync`, `formatDriftWarning`, `formatValidationIssue`,
`validateRegistryFull`, `RegistryValidationReport`,
`renderRegistryDhall`);
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/seihou-core/src/Seihou/Dhall/Eval.hs`
(home of `registryDecoder`, `registryEntryDecoder`,
`evalRegistryFromFile`, the `withDefaults` helper, and the
`emptyRegistryEntryList` Dhall expression);
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/seihou-cli/src-exe/Seihou/CLI/Install.hs`
(home of `handleInstall`, `installFromRegistry`, `installRegistryEntry`,
`selectModules`, `fzfModuleSelection`, `promptModuleSelection`);
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/seihou-cli/src/Seihou/CLI/InstallShared.hs`
(home of `installModuleDir`, which copies any directory to
`~/.config/seihou/installed/<name>/` and writes `.seihou-origin.json`,
and is reused unchanged for blueprints);
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/seihou-cli/src-exe/Seihou/CLI/Browse.hs`
and
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/seihou-cli/src/Seihou/CLI/BrowseFormat.hs`;
and
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/seihou-cli/src/Seihou/CLI/Registry/Sync.hs`
and
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/seihou-cli/src/Seihou/CLI/Registry/Validate.hs`.

EP-29 hard-dependencies that must be in place before this plan starts
are `Seihou.Core.Types.Blueprint` (with `version :: Maybe Text`),
`Seihou.Dhall.Eval.evalBlueprintFromFile :: FilePath -> IO (Either
ModuleLoadError Blueprint)`, `Seihou.Core.Blueprint.validateBlueprint`,
and the `RunnableBlueprint` constructor on `Runnable` (consumed
indirectly via pattern-coverage warnings). The soft dependency on EP-30
is fixture-authoring convenience: `seihou validate-blueprint` helps a
contributor vet a fixture by hand, but nothing in this plan calls it
programmatically.


## Plan of Work

The work decomposes into three milestones. Each is independently
verifiable through unit tests; later milestones depend on earlier ones
in source-code terms.

### Milestone 1 — registry data model, decoder, and discovery

This milestone teaches the pure layer about blueprints. After it ships,
unit tests prove that a multi-kind `seihou-registry.dhall` decodes into
a `Registry` with three populated lists; that a registry without a
`blueprints` field decodes with `blueprints = []`; that
`validateRegistry` rejects malformed blueprint entries; that
`checkNameCollisions` is a three-way check; that `computeRegistrySync`
and `validateRegistryFull` cover blueprints; that `discoverRepoContents`
returns `SingleBlueprint repoRoot` for a directory containing only
`blueprint.dhall` and prefers registry/module/recipe roots over a stray
`blueprint.dhall`; and that `renderRegistryDhall` round-trips a registry
containing all three lists. CLI behaviour is unchanged. Gate:
`cabal test seihou-core` green, no regressions.

### Milestone 2 — install and browse handlers

This milestone wires the new shape into user-visible commands. After it
ships, `seihou install <url>` recognises a blueprint-only repo as
`SingleBlueprint` and installs it at
`~/.config/seihou/installed/<name>/`; against a multi-kind registry,
`--all`, `--module NAME`, and the interactive picker each include
blueprint entries; the picker rows carry per-kind labels. `seihou
browse` lists all three kinds with kind labels, supports `--tag`
filtering uniformly, and prints a "Single-blueprint repository" header
for a `SingleBlueprint` clone. Validation includes formatter unit tests
plus an end-to-end test that drives `handleInstall` under a redirected
`XDG_CONFIG_HOME` and asserts the expected directories appear.

### Milestone 3 — registry sync-versions and validate

This milestone makes the registry-authoring sub-commands blueprint-aware.
`seihou registry sync-versions` walks the blueprint list, reads each
`blueprint.dhall` version, and rewrites the registry; the diff uses the
`blueprints.NAME` prefix. Example output:

    Updated seihou-registry.dhall:
      modules.haskell-base:        (none)    -> 1.0.0
      modules.nix-flake:           0.3.0     -> 0.4.0
      recipes.haskell-library:     (none)    -> 0.1.0
      blueprints.payments-service: 0.1.0     -> 0.2.0

    3 entries updated, 1 unchanged.

`seihou registry validate` succeeds with:

    OK: 2 modules, 1 recipe, 1 blueprint, all versions in sync.

and on drift:

    errors:
      blueprints.payments-service: registry version 0.1.0 does not match blueprint.dhall version 0.2.0

    1 error. Run `seihou registry sync-versions` to fix version drift.

Gate: `cabal test seihou-cli` green, plus an end-to-end test that drifts
a blueprint version, asserts a non-zero exit from `seihou registry
validate`, runs `seihou registry sync-versions`, and asserts the
registry file is rewritten.


## Concrete Steps

### Milestone 1

In `seihou-core/src/Seihou/Core/Registry.hs`, add the `blueprints` field
to `Registry` immediately after `recipes`:

    data Registry = Registry
      { repoName :: Text,
        repoDescription :: Maybe Text,
        modules :: [RegistryEntry],
        recipes :: [RegistryEntry],
        blueprints :: [RegistryEntry]
      }

Extend `EntryKind`:

    data EntryKind = ModuleEntry | RecipeEntry | BlueprintEntry
      deriving stock (Eq, Show, Generic)

GHC will surface every non-exhaustive match across the codebase. The
known sites and their new arms are:

- `formatDriftWarning` — `kindWord BlueprintEntry = "blueprint"` and
  `entryFile BlueprintEntry = "blueprint.dhall"`.
- `formatValidationIssue` — `entryFile BlueprintEntry =
  "blueprint.dhall"`.
- `validationKindPrefix` — `validationKindPrefix BlueprintEntry =
  "blueprints."`.
- `seihou-cli/src/Seihou/CLI/Registry/Sync.hs::kindPrefix` — `kindPrefix
  BlueprintEntry = "blueprints."`.

Add `validateBlueprintEntry`, modelled on `validateRecipeEntry`, that
checks the path is relative and `..`-free, the name matches
`[a-z][a-z0-9-]*`, and `<repoRoot>/<entry.path>/blueprint.dhall` exists.
Update `validateRegistry`:

    validateRegistry repoRoot reg = do
      modErrs <- concat <$> mapM (validateModuleEntry repoRoot) reg.modules
      recErrs <- concat <$> mapM (validateRecipeEntry repoRoot) reg.recipes
      bpErrs  <- concat <$> mapM (validateBlueprintEntry repoRoot) reg.blueprints
      let collisionErrs = checkNameCollisions reg.modules reg.recipes reg.blueprints
      pure (modErrs <> recErrs <> bpErrs <> collisionErrs)

Rewrite `checkNameCollisions` as a three-way check. Build a `Map Text
[EntryKind]` keyed by name and report each name that appears in more
than one kind, emitting one message per offending pair. The error
template stays:

    name collision: 'X' appears as both a module and a recipe
    name collision: 'X' appears as both a module and a blueprint
    name collision: 'X' appears as both a recipe and a blueprint

Update `computeRegistrySync`: build `blueprintDiffs = map (classify
BlueprintEntry) reg.blueprints` and concatenate into `syncDiffs`. Apply
the diffs back into `reg.blueprints` with `zipWith applyDiff`.

Add `reportBlueprintCount :: Int` to `RegistryValidationReport` and
populate it from `length reg.blueprints` in `validateRegistryFull`.

Update `renderRegistryDhall` to emit a `, blueprints =` line followed by
`renderEntryList reg.blueprints`. The empty-list rendering already
includes the type annotation.

Add `SingleBlueprint FilePath` to `RepoContents`. Update
`discoverRepoContents` so the precedence chain becomes registry → module
→ recipe → blueprint → empty in both the no-registry and the
registry-fallback (parse failure) branches. Extracting a private helper
`probeSingleArtifact :: FilePath -> IO RepoContents` to encode the
module/recipe/blueprint/empty cascade is the cleanest implementation,
but a literal copy is acceptable.

In `seihou-core/src/Seihou/Dhall/Eval.hs`, extend `registryDecoder`:

    registryDecoder =
      withDefaults
        [ ("recipes", emptyRegistryEntryList),
          ("blueprints", emptyRegistryEntryList)
        ]
        $ record
          ( Registry
              <$> field "repoName" strictText
              <*> field "repoDescription" (maybe strictText)
              <*> field "modules" (list registryEntryDecoder)
              <*> field "recipes" (list registryEntryDecoder)
              <*> field "blueprints" (list registryEntryDecoder)
          )

The Dhall record shape authors will use:

    { repoName : Text
    , repoDescription : Optional Text
    , modules : List RegistryEntry
    , recipes : List RegistryEntry
    , blueprints : List RegistryEntry
    }

A worked example for the test fixture:

    { repoName = "Acme Templates"
    , repoDescription = Some "Modules, recipes, and blueprints"
    , modules =
      [ { name = "haskell-base", version = Some "1.0.0"
        , path = "modules/haskell-base"
        , description = Some "Minimal Haskell project"
        , tags = [ "haskell" ]
        }
      ]
    , recipes =
      [ { name = "haskell-library", version = Some "0.1.0"
        , path = "recipes/haskell-library"
        , description = Some "Library scaffold"
        , tags = [ "haskell" ]
        }
      ]
    , blueprints =
      [ { name = "payments-service", version = Some "0.1.0"
        , path = "blueprints/payments-service"
        , description = Some "Agent-driven payments scaffold"
        , tags = [ "service", "payments" ]
        }
      ]
    }

In `seihou-core/test/Seihou/Core/RegistrySpec.hs`, add tests:
multi-kind decoding; backwards-compat (no `blueprints` field decodes
with `[]`); `validateRegistry` rejecting bad blueprint names and
absolute/`..` paths; `checkNameCollisions` for module/blueprint,
recipe/blueprint, and three-way; `discoverRepoContents` returning
`SingleBlueprint`; `discoverRepoContents` precedence (module beats
blueprint, recipe beats blueprint, registry beats blueprint);
`computeRegistrySync` classifying blueprints; `validateRegistryFull`
populating `reportBlueprintCount`. In
`seihou-core/test/Seihou/Core/RegistryEmitSpec.hs`, add a round-trip
for a registry with all three lists.

Run `cabal test seihou-core`.

### Milestone 2

In `seihou-cli/src-exe/Seihou/CLI/Install.hs`, add a helper modelled on
`installSingleRecipe`:

    installSingleBlueprint :: InstallOpts -> FilePath -> Text -> IO ()
    installSingleBlueprint iopts rootDir source = do
      let name = case iopts.installName of
            Just n  -> T.unpack n
            Nothing -> parseModuleName source
      decoded <- evalBlueprintFromFile (rootDir </> "blueprint.dhall")
      bp <- case decoded of
        Left err -> ...exitFailure with "repository is not a valid seihou blueprint"...
        Right b  -> pure b
      ...validateBlueprint rootDir bp...
      installModuleDir rootDir name source Nothing bp.version []
      TIO.putStrLn $ "Blueprint available as: " <> T.pack name

Add the `SingleBlueprint` arm to `handleInstall`:

    SingleBlueprint rootDir -> do
      when (not (null iopts.installModules) || iopts.installAll) $
        logIO LogNormal (logWarn "--module and --all flags are ignored for single-blueprint repositories.")
      installSingleBlueprint iopts rootDir source

Lift entry concatenation into a local helper `allEntries reg =
registry.modules ++ registry.recipes ++ registry.blueprints` and use it
in `selectModules` (in all three sub-paths: `installAll`,
`installModules`, and the interactive selectors).

Update the picker formatting so each row carries a kind label. Build the
candidate list as `(EntryKind, RegistryEntry)`. Display string:

    [module]    haskell-base   Minimal Haskell project    [haskell, starter]

with `kindLabel`:

    kindLabel ModuleEntry    = "[module]   "
    kindLabel RecipeEntry    = "[recipe]   "
    kindLabel BlueprintEntry = "[blueprint]"

Three eleven-character labels, padded with one trailing space.

Update `installRegistryEntry`. Extend the marker probe so a third branch
checks for `blueprint.dhall`:

    if hasModule then ...module install...
    else if hasRecipe then ...recipe install...
    else if hasBlueprint then do
      decoded <- evalBlueprintFromFile blueprintDhall
      case decoded of
        Left err -> ...failed-to-load...
        Right bp -> do
          let ver = entry.version <|> bp.version
          installModuleDir entryDir name source (Just repoName) ver entry.tags
          TIO.putStrLn $ "    Installed blueprint as: " <> T.pack name
          pure True
    else ...has neither module.dhall, recipe.dhall, nor blueprint.dhall...

Update the `--module` flag's long-help in
`seihou-cli/src-exe/Seihou/CLI/Commands.hs` to read "Module, recipe, or
blueprint name from the registry to install. May be repeated."

In `seihou-cli/src-exe/Seihou/CLI/Browse.hs`, add the `SingleBlueprint`
arm calling a new `formatBrowseSingleBlueprint :: Text -> Text -> Maybe
Text -> Text` modelled on `formatBrowseSingleModule` but with the trailing
line "Single-blueprint repository. Install with:". In the `MultiModule`
branch, change the filtered concatenation to include blueprints. Lift
filtering into a helper that returns `[(EntryKind, RegistryEntry)]`. In
`seihou-cli/src/Seihou/CLI/BrowseFormat.hs`, change
`formatBrowseRegistry`'s signature to accept `[(EntryKind,
RegistryEntry)]` and prefix each row with `kindLabel`. The footer's
"Install with:" hint lines stay unchanged in spirit (they already point
at `--module <name>` and `--all`).

Add tests under `seihou-cli/test/`:

- A `SingleBlueprint` repo installs into the redirected
  `XDG_CONFIG_HOME/seihou/installed/<name>/` with the expected
  `.seihou-origin.json`.
- A multi-kind registry with `--all` lands all three directories.
- `--module my-blueprint` against the same registry installs only the
  blueprint.
- `--module does-not-exist` exits non-zero.
- `formatBrowseRegistry` emits the kind-label column for each row;
  `--tag` filters across all three lists.

### Milestone 3

In `seihou-cli/src/Seihou/CLI/Registry/Sync.hs`, extend
`resolveOnDiskVersions`:

    resolveOnDiskVersions repoRoot reg = do
      modulePairs    <- mapM (loadModule    repoRoot) reg.modules
      recipePairs    <- mapM (loadRecipe    repoRoot) reg.recipes
      blueprintPairs <- mapM (loadBlueprint repoRoot) reg.blueprints
      pure (concat modulePairs <> concat recipePairs <> concat blueprintPairs)
      where
        ...
        loadBlueprint root entry = do
          let path = root </> entry.path </> "blueprint.dhall"
          decoded <- evalBlueprintFromFile path
          case decoded of
            Right bp -> pure [(BlueprintEntry, entry.name, blueprintVersion bp)]
            Left  _  -> pure []

with `blueprintVersion :: Blueprint -> Maybe Text` mirroring
`moduleVersion` and `recipeVersion`.

Extend `kindPrefix`:

    kindPrefix ModuleEntry    = "modules."
    kindPrefix RecipeEntry    = "recipes."
    kindPrefix BlueprintEntry = "blueprints."

The summary line in `summary :: SyncReport -> Text` is unchanged.

In `seihou-cli/src/Seihou/CLI/Registry/Validate.hs`, extend the success
line in `renderValidationReport` to include the blueprint count:

    "OK: " <> show modCount <> " " <> pluralize modCount "module" "modules"
        <> ", " <> show recCount <> " " <> pluralize recCount "recipe" "recipes"
        <> ", " <> show bpCount  <> " " <> pluralize bpCount "blueprint" "blueprints"
        <> ", all versions in sync."

The error path requires no further changes: `formatValidationIssue`
already routes on `EntryKind`, and milestone 1 added the
`BlueprintEntry` arms.

Tests (under whichever test file already exercises `runSync` and
`runValidate`; search with `grep -rn 'handleSyncVersions\|runSync\|runValidate'
seihou-cli/test`):

- `runSync` reads a blueprint's on-disk version into the registry entry
  (write a temp registry with `version = None Text`, place a
  `blueprint.dhall` with `version = Some "0.2.0"`, assert the resulting
  registry's blueprint entry has `Just "0.2.0"`).
- `renderSyncReport` output includes a row beginning
  `blueprints.payments-service:`.
- `runValidate` reports blueprint version drift with the
  `blueprints.NAME` prefix.
- The validate success line includes the blueprint count.

Run `cabal test seihou-cli`.


## Validation and Acceptance

After all three milestones, the following must succeed against a fixture
multi-kind repository (created by the test harness; not committed)
containing:

    seihou-registry.dhall
    modules/haskell-base/module.dhall
    recipes/haskell-library/recipe.dhall
    blueprints/payments-service/blueprint.dhall
    blueprints/payments-service/prompt.md
    blueprints/payments-service/files/example.cabal

With `XDG_CONFIG_HOME` redirected to a temporary directory:

    seihou install file:///tmp/fixture --module payments-service
    test -f $XDG_CONFIG_HOME/seihou/installed/payments-service/blueprint.dhall
    test -f $XDG_CONFIG_HOME/seihou/installed/payments-service/.seihou-origin.json

    seihou install file:///tmp/fixture --all
    test -f $XDG_CONFIG_HOME/seihou/installed/haskell-base/module.dhall
    test -f $XDG_CONFIG_HOME/seihou/installed/haskell-library/recipe.dhall
    test -f $XDG_CONFIG_HOME/seihou/installed/payments-service/blueprint.dhall

    seihou browse file:///tmp/fixture
    # output contains a [blueprint] row for payments-service

    seihou registry sync-versions --dir /tmp/fixture
    # output contains a row beginning "blueprints.payments-service:"

    seihou registry validate --dir /tmp/fixture
    # success: "OK: 1 module, 1 recipe, 1 blueprint, all versions in sync."
    # drift case: "blueprints.payments-service: registry version ... does not match blueprint.dhall version ..."

Both `cabal test seihou-core` and `cabal test seihou-cli` must remain
green. `nix flake check` must remain green;
`nix/check-cli-module-placement.sh` continues to enforce the
library-first convention. All new code in this plan is library code or
edits to existing executable-trapped files (`Install.hs`, `Browse.hs`,
`Commands.hs`); no new module is added to the executable target.


## Idempotence and Recovery

Every change is additive: the `blueprints` field defaults to `[]` for
every registry written before this plan ships, so authors do not need to
edit existing `seihou-registry.dhall` files unless they want to add
blueprint entries; `SingleBlueprint` is unreachable for any clone
without a `blueprint.dhall`, so no pre-existing classification changes;
the picker's new kind labels are presentational, so `--module NAME`
matching is unchanged; all new tests use `withSystemTempDirectory` and
a redirected `XDG_CONFIG_HOME`, so the user's real `~/.config/seihou/`
is never touched. There are no schema-version bumps, no on-disk format
migrations, and no manifest changes. Reverting a milestone is `git
checkout -- <files>` of the affected cluster.


## Interfaces and Dependencies

This plan exports no new top-level modules. Field and function additions
inside existing modules:

- `Seihou.Core.Registry.Registry` gains `blueprints :: [RegistryEntry]`.
- `Seihou.Core.Registry.RepoContents` gains `SingleBlueprint FilePath`.
  Consumers of `RepoContents` after this plan are `handleInstall` and
  `handleBrowse` (handle the new arm explicitly) plus `runSync` and
  `runValidate` (already match `MultiModule` and a wildcard, so the
  wildcard absorbs `SingleBlueprint`; this is the desired behaviour
  because the registry sub-commands operate only on multi-kind
  registries).
- `Seihou.Core.Registry.EntryKind` gains `BlueprintEntry`.
- `Seihou.Core.Registry.RegistryValidationReport` gains
  `reportBlueprintCount :: Int`.
- `Seihou.Core.Registry.checkNameCollisions` signature changes from two
  registry-entry lists to three. The function is only called by
  `validateRegistry`; no external module is affected.
- `Seihou.Core.Registry.renderRegistryDhall` output gains a
  `, blueprints =` line.

Hard dependency on EP-29: `Seihou.Core.Types.Blueprint` (with `version
:: Maybe Text`); `Seihou.Dhall.Eval.evalBlueprintFromFile`;
`Seihou.Core.Blueprint.validateBlueprint`; the `RunnableBlueprint`
constructor on `Runnable` (consumed indirectly through pattern coverage).

Soft dependency on EP-30: `seihou validate-blueprint` is convenient for
authoring fixtures by hand. Not invoked programmatically.

No dependency on EP-31 (agent runner) or EP-32 (manifest tracking). A
blueprint installed by this plan is a first-class artifact: it appears
in `seihou list` and is ready for the agent runner once EP-31 ships.
Before EP-31 ships, `seihou run my-blueprint` produces EP-29's refusal
message regardless of how the blueprint reached the local installation.

Downstream consumer in plan-merge order: EP-34 (documentation) updates
`docs/dev/design/proposed/blueprints.md`, `docs/dev/architecture/overview.md`,
the user CHANGELOG, and the agent-prompt files
(`seihou-cli/data/{assist,bootstrap,setup}-prompt.md`) with the registry
surface this plan ships.

The CLI surface is unchanged at the parser level — no new flags, no new
sub-commands. Only the long-help text for `seihou install --module` is
updated; this does not break any pre-existing scripted use.
