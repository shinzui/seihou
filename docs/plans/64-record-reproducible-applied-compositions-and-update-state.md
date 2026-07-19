---
id: 64
slug: record-reproducible-applied-compositions-and-update-state
title: "Record reproducible applied compositions and update state"
kind: exec-plan
created_at: 2026-07-19T16:27:05Z
intention: "intention_01kxxjwvf8e2e8r64feyk6r65b"
master_plan: "docs/masterplans/8-make-module-updates-seamless-and-conflict-aware.md"
---

# Record reproducible applied compositions and update state

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, a successful deterministic `seihou run` records enough information to
reproduce the application later. The manifest no longer contains only a flat list of
modules and a flat variable map; it also records which module or recipe the user requested,
the ordered additional roots, every resolved module instance and its values, and stable
slots for generated baselines and successful command receipts.

This is the persistent-state foundation for the project-aware update workflow coordinated
by `docs/masterplans/8-make-module-updates-seamless-and-conflict-aware.md`. It does not add
`seihou update` yet. Its observable result is that running a module or recipe produces a
version-4 manifest with an `applications` entry, while version-1, version-2, and version-3
manifests still decode successfully.

For example, after applying `master-plan`, a contributor can inspect:

```bash
jq '.version, .applications[0]' .seihou/manifest.json
```

and see the requested target, stable application ID, ordered roots, namespace/context, and
per-instance resolved values. Two instances of the same dependency with different
`parentVars` remain distinct.


## Progress

- [x] (2026-07-19 17:41Z) M1: Add the application/update state types and version-4 JSON contract.
- [x] (2026-07-19 17:41Z) M1: Decode manifest versions 1-3 with empty application state and absent baseline ownership.
- [x] (2026-07-19 17:41Z) M1: Update existing constructors and fixtures through named helpers so the repository builds.
- [x] (2026-07-19 17:41Z) M2: Add stable application identity and pure build/replace helpers.
- [x] (2026-07-19 17:41Z) M2: Record successful module and recipe runs with per-instance resolved values and file ownership.
- [x] (2026-07-19 17:41Z) M2: Preserve the legacy flat `variables` map for compatibility while treating applications as authoritative for future updates.
- [x] (2026-07-19 17:41Z) M3: Add manifest, identity, multi-instance, and successful-run regression coverage.
- [x] (2026-07-19 17:41Z) M3: Run focused tests, `cabal test all`, formatting, and module/recipe manifest inspection smoke tests.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- `executePlan` returns records only for operations that physically write a file. An
  unchanged or interactively kept destination would therefore lose application ownership
  if recording used only its result map. The run handler now derives the complete
  destination set from composed file operations and attaches ownership after combining
  written, kept, and prior records.

- Recipe expansion roots cannot participate in stable application identity. They are the
  recipe's versioned contents and may change during an update; including them would turn a
  recipe upgrade into a second application. Only user-supplied ordered `--module` roots are
  stored in `additionalModules` and hashed with the requested recipe target.

- A real non-interactive rerun proved that application replacement and unchanged-file
  ownership work together: the manifest retained one application and the unchanged
  `README.md` retained the same application ID.


## Decision Log

- Decision: Add `Manifest.applications` instead of extending `AppliedModule` with root-level
  invocation data.
  Rationale: `AppliedModule` represents one dependency instance. It cannot express which
  module or recipe the user requested, additional-root order, or the fact that several
  instances belong to one re-runnable composition.
  Date: 2026-07-19.

- Decision: Define an application ID from the requested target and ordered additional
  roots only.
  Rationale: Module versions and resolved values must change in place during an update.
  Including them in identity would create a new application instead of updating the old
  one. Additional-root order is retained because composition layering is order-sensitive.
  Date: 2026-07-19.

- Decision: Store resolved values per `(ModuleName, ParentVars)` instance and serialize
  values as the same canonical `Text` already used by the legacy manifest map.
  Rationale: The live manifest contains multiple `exec-plan` and `link-skill` instances.
  A flat map cannot preserve different values for the same variable name across instances.
  Reusing the existing text encoding avoids inventing another variable serialization
  format.
  Date: 2026-07-19.

- Decision: Make EP-64 define baseline references, per-file application ownership, and
  command receipt records even though EP-65 and EP-67 populate them.
  Rationale: One coordinated schema bump is easier to review and migrate than three
  consecutive persistent-state changes. Later plans consume these fields without changing
  the version-4 JSON shape.
  Date: 2026-07-19.

- Decision: Keep `Manifest.vars` and all existing fields readable and writable.
  Rationale: Status output and external tooling currently consume the flat map. Removing it
  is unrelated to enabling reproducible applications and would make the schema change
  needlessly breaking.
  Date: 2026-07-19.

- Decision: For a recipe application, hash and store only user-supplied additional roots,
  not modules introduced by recipe expansion.
  Rationale: Recipe membership is versioned recipe content. It must be allowed to change
  while the stable application is replaced in place; explicit `--module` roots remain part
  of user-selected composition identity and preserve their order.
  Date: 2026-07-19.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

EP-64 is complete. Manifest schema version 4 now round-trips top-level applications,
per-instance resolved values, baseline references, file application ownership, and command
receipts while versions 1-3 decode with safe defaults. `Seihou.Core.Application` owns
stable identity, record construction, replacement, and ownership attachment. Ordinary
module and recipe runs now retain their requested target and provenance, replace repeated
applications, preserve the legacy flat variable map, and attribute unchanged as well as
written tracked destinations.

Focused tests passed with 949 `seihou-core` tests and 262 `seihou-cli` tests. `cabal test
all` also passed the 16 extension tests, for 1,227 tests total. `nix fmt` completed and
`git diff --check` reported no errors. Disposable module and recipe smoke projects both
wrote version-4 manifests; the module rerun retained one application and ownership on its
unchanged file. Baseline bytes and command receipts remain intentionally unpopulated until
EP-65 and EP-67.


## Context and Orientation

Seihou is a deterministic project scaffolder. A module invocation resolves variables,
renders file and command operations, writes files, and records state in
`.seihou/manifest.json`. A **composition** is the requested root module or recipe, any
additional roots supplied by `-m/--module`, and every transitive dependency loaded for
those roots. A **module instance** is identified by a module's bare name plus the variable
bindings supplied by its parent edge. `docs/dev/design/proposed/module-instance-identity.md`
documents why `(ModuleName, ParentVars)` is the existing identity rule.

The core records live in `seihou-core/src/Seihou/Core/Types.hs`. `Manifest` currently has
schema version, timestamp, `[AppliedModule]`, a flat `Map VarName Text`, a file map, optional
recipe provenance, and optional blueprint provenance. `AppliedModule` already stores
`name`, `parentVars`, source directory, version, timestamp, and removal declaration.
`FileRecord` stores only the last applied hash, one qualified module owner, strategy, and
timestamp.

`seihou-core/src/Seihou/Manifest/Types.hs` owns `currentManifestVersion`, JSON encoding, and
backward decoding. The current version is 3. Version 1 omitted `AppliedModule.parentVars`;
version 2 omitted `Manifest.blueprint`. The decoder accepts both by filling defaults. The
real and pure stores are in `seihou-core/src/Seihou/Effect/ManifestStoreInterp.hs` and
`seihou-core/src/Seihou/Effect/ManifestStorePure.hs`; manifest writes are already atomic at
the single-file level.

`seihou-core/src/Seihou/Composition/Instance.hs` defines `ModuleInstance` and
`qualifiedName`. `seihou-core/src/Seihou/Composition/Resolve.hs` returns resolved values as
`Map ModuleInstance (Map VarName ResolvedVar)`. This is the correctly-scoped value map to
persist. Do not reconstruct per-instance state from the flat union currently written to
`Manifest.vars`.

`seihou-cli/src-exe/Seihou/CLI/Run.hs` is the executable-only run handler. It discovers a
module or recipe, calls `loadComposition`, resolves values, compiles operations, reads the
manifest, computes a diff, writes files, and constructs the new manifest. The current
`updateAllModules` helper refreshes applied modules by `(name,parentVars)`. The handler knows
whether the user requested a recipe through `recipeInfo`, but it discards the requested
target after expansion. This plan must retain that target long enough to build an
`AppliedComposition`.

Tests for the JSON contract are in
`seihou-core/test/Seihou/Manifest/TypesSpec.hs`. Instance identity tests live in
`seihou-core/test/Seihou/Composition/InstanceSpec.hs`; add a new
`seihou-core/test/Seihou/Core/ApplicationSpec.hs` for application identity/build helpers and
register it in `seihou-core/test/Main.hs` and `seihou-core/seihou-core.cabal`.


## Plan of Work

### Milestone 1: establish the version-4 manifest contract

Extend `seihou-core/src/Seihou/Core/Types.hs` with the following domain types. Field names
may be adjusted only to satisfy existing record-selector collisions; their meaning and JSON
shape are fixed by this plan.

```haskell
newtype ApplicationId = ApplicationId { unApplicationId :: Text }
  deriving stock (Eq, Ord, Show, Generic)

data AppliedTarget
  = AppliedModuleTarget ModuleName
  | AppliedRecipeTarget RecipeName
  deriving stock (Eq, Ord, Show, Generic)

newtype BaselineRef = BaselineRef { unBaselineRef :: SHA256 }
  deriving stock (Eq, Ord, Show, Generic)

newtype CommandFingerprint = CommandFingerprint { unCommandFingerprint :: SHA256 }
  deriving stock (Eq, Ord, Show, Generic)

data CommandReceipt = CommandReceipt
  { fingerprint :: CommandFingerprint
  , moduleName :: ModuleName
  , command :: Text
  , workDir :: Maybe FilePath
  , completedAt :: UTCTime
  }

data AppliedInstanceState = AppliedInstanceState
  { name :: ModuleName
  , parentVars :: ParentVars
  , source :: FilePath
  , moduleVersion :: Maybe Text
  , resolvedVars :: Map VarName Text
  }

data AppliedComposition = AppliedComposition
  { applicationId :: ApplicationId
  , target :: AppliedTarget
  , targetSource :: FilePath
  , targetVersion :: Maybe Text
  , additionalModules :: [ModuleName]
  , namespace :: Maybe Text
  , context :: Maybe Text
  , instances :: [AppliedInstanceState]
  , commandReceipts :: Map CommandFingerprint CommandReceipt
  , appliedAt :: UTCTime
  }
```

Add `applications :: [AppliedComposition]` to `Manifest`. Extend `FileRecord` with
`baseline :: Maybe BaselineRef` and `applicationIds :: Set ApplicationId`. Retain
`FileRecord.hash` as the hash of the content actually written to disk; EP-65 will make
`baseline` point to the generated common ancestor. Update `emptyManifest` with an empty
application list and bump `currentManifestVersion` from 3 to 4.

In `seihou-core/src/Seihou/Manifest/Types.hs`, encode targets as a tagged object and maps
using text keys:

```json
{
  "kind": "module",
  "name": "master-plan"
}
```

The recipe form uses `"kind": "recipe"`. Encode `BaselineRef`,
`CommandFingerprint`, `ApplicationId`, `VarName`, and `ModuleName` through their text values.
For manifest versions 1-3, missing `applications` decodes to `[]`; missing file
`baseline` decodes to `Nothing`; missing file `applications` decodes to the empty set. A
version-4 manifest must round-trip exactly. Continue rejecting manifests whose version is
newer than `currentManifestVersion`.

Update all direct `Manifest`, `AppliedModule`, and `FileRecord` constructors across source
and tests. Prefer small named test/build helpers instead of adding positional arguments to
already fragile constructors. The repository must build and all existing manifest fixtures
must remain readable at the end of this milestone.

### Milestone 2: calculate and record reproducible applications

Create `seihou-core/src/Seihou/Core/Application.hs` and expose it from
`seihou-core/seihou-core.cabal`. It owns canonical application identity and pure record
construction. The required public surface is:

```haskell
mkApplicationId :: AppliedTarget -> [ModuleName] -> ApplicationId

buildAppliedComposition
  :: AppliedTarget
  -> FilePath
  -> Maybe Text
  -> [ModuleName]
  -> Maybe Text
  -> Maybe Text
  -> [(ModuleInstance, Module, FilePath)]
  -> Map ModuleInstance (Map VarName ResolvedVar)
  -> UTCTime
  -> AppliedComposition

replaceAppliedComposition
  :: AppliedComposition
  -> [AppliedComposition]
  -> [AppliedComposition]

attachApplication
  :: ApplicationId
  -> Maybe FileRecord
  -> FileRecord
  -> FileRecord
```

`mkApplicationId` hashes a canonical UTF-8 text form containing a target-kind line, target
name line, and one `additional=<name>` line in supplied order. Use the existing
`Seihou.Manifest.Hash.hashContent`; store the full hexadecimal digest, not the eight-character
module-instance display hash. `replaceAppliedComposition` replaces the entry with the same
ID while preserving the relative order of other entries. `attachApplication` unions the
new application ID with any prior IDs for that path and leaves `baseline = Nothing` in this
plan.

Modify `seihou-cli/src-exe/Seihou/CLI/Run.hs` so the discovery/recipe branch retains an
`AppliedTarget`: the typed module name the user requested or the recipe name before
expansion. Also retain the discovered target directory and declared target version. For a
module these are its module directory and `Module.version`; for a recipe they are the recipe
directory and `Recipe.version`. This provenance is required to find `.seihou-origin.json`
and fetch a newer recipe later. After execution succeeds, build the composition from
`modulesInOrder` and the already available `resolved` map. Write it with
`replaceAppliedComposition`. Attribute every tracked destination produced by the successful
composition to the current application using `attachApplication`, including destinations
classified unchanged or kept rather than physically rewritten; files preserved from
unrelated applications retain their IDs. Derive this destination set from the composed
file operations instead of only from `executePlan`'s newly written records. Populate the
legacy flat `Manifest.vars` exactly as today.

Do not change variable resolution precedence in `seihou run`. Saved values are recorded now
and consumed by EP-68's update service. Do not add `--reconfigure` in this plan.

### Milestone 3: prove backward compatibility and multi-instance fidelity

Extend `seihou-core/test/Seihou/Manifest/TypesSpec.hs` with version-3 JSON that lacks every
new field and assert it decodes with empty/default state. Add full version-4 round trips
covering two applications, two instances of the same module with different `parentVars`,
per-instance values, a baseline reference, application ownership on one file, and a command
receipt.

Add `Seihou.Core.ApplicationSpec` covering stable hashes, additional-root order sensitivity,
version/value independence, replace semantics, and `buildAppliedComposition` preservation of
distinct instances. Add the smallest extractable run-side unit test necessary to prove that
a module target and recipe target produce the right record. If testing this would require
driving terminal input, keep the handler thin and test the new pure helper instead.

Finally, use a temporary module fixture or an existing installed module in a clean temporary
project, run it once, and inspect the JSON. Do not run the smoke test in the repository root,
because it would mutate the repository's real `.seihou/manifest.json`.


## Concrete Steps

Run all commands from the repository root:

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
cabal test seihou-core-test
cabal test all
nix fmt
git diff --check
```

For the smoke test, create a disposable project directory with `mktemp -d`, run a known
installed module with every required variable supplied non-interactively, and inspect only
that directory's manifest. The exact module may change with the local installation; record
the chosen command in Progress. The important observation is this shape:

```text
4
{
  "target": {"kind":"module","name":"..."},
  "instances": [...],
  "commandReceipts": {}
}
```

Every commit made while implementing this plan must include:

```text
MasterPlan: docs/masterplans/8-make-module-updates-seamless-and-conflict-aware.md
ExecPlan: docs/plans/64-record-reproducible-applied-compositions-and-update-state.md
Intention: intention_01kxxjwvf8e2e8r64feyk6r65b
```


## Validation and Acceptance

The plan is complete when all existing manifests and tests still work and the following
behaviors are demonstrated:

- decoding a version-3 manifest produces `applications = []`, file `baseline = Nothing`,
  and empty file application ownership without losing modules, variables, files, recipe, or
  blueprint data;
- encoding then decoding a version-4 manifest preserves all new fields exactly;
- application identity is unchanged when target/module versions, source paths, or resolved values change, but
  changes when the target, target kind, additional-root membership, or additional-root
  order changes;
- two dependency instances with the same module name and different `ParentVars` retain two
  separately scoped resolved maps;
- a successful module run and a successful recipe run each record one application with the
  original requested target, not merely the recipe's expanded first module;
- rerunning the same application replaces its state and does not append a duplicate;
- files generated by an application carry its ID while unrelated existing file records are
  preserved;
- `cabal test all` passes and `nix fmt` leaves no unintended changes.


## Idempotence and Recovery

Schema and helper changes are ordinary source edits and are safe to rebuild repeatedly.
Manifest decoding is additive: old JSON remains readable, so an interrupted implementation
must never write a version-4 manifest until the encoder and decoder are both present and
tested. Land the type/codec milestone as one working commit.

Use disposable directories for manual generation. If a smoke run fails, remove only that
explicit temporary directory or create another; never reset or rewrite the repository-root
manifest. If application recording fails after files were generated, the existing atomic
manifest writer leaves either the previous complete manifest or the new complete manifest,
not a partial JSON file. Re-run the same command after fixing the cause.


## Interfaces and Dependencies

This plan has no child-plan dependencies and adds no external package. Use `containers` for
maps/sets, `text`, `time`, `aeson`, and the existing SHA-256 helper already declared in
`seihou-core.cabal`.

EP-65 consumes `BaselineRef`, `FileRecord.baseline`, and file application ownership. EP-66
consumes `ApplicationId` and the same file fields. EP-67 consumes `CommandFingerprint`,
`CommandReceipt`, and `AppliedComposition.commandReceipts`. EP-68 consumes every application
field and `mkApplicationId`; these names and semantics are coordination contracts and must
not be independently redefined downstream.

The version-4 JSON keys are `applications` at manifest level, `baseline` and `applications`
inside each file record, and `commandReceipts` inside an application. Optional/default
fields may be omitted when empty to keep manifests readable, but the decoder must accept
both omitted and explicit-empty forms.

Revision note (2026-07-19): Recorded completed implementation, validation evidence, the
operation-derived ownership requirement, and the recipe identity rule discovered while
implementing EP-64.
