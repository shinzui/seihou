---
id: 81
slug: record-artifact-origin-for-agent-applied-artifacts
title: "Record artifact origin for agent-applied artifacts"
kind: exec-plan
created_at: 2026-08-16T14:16:33Z
intention: "intention_01m05ew4qbef6tn9bnphy4nv2n"
master_plan: "docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md"
---

# Record artifact origin for agent-applied artifacts

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Seihou records what a project has applied in a file called the *manifest*,
`.seihou/manifest.json`, which is checked into the project's git repository. For every
module it applies, seihou records not just the module's name but its *origin* — the git URL
it was installed from — because two different repositories can both publish a module called
`haskell-base`, and a name alone cannot tell you which one a project was generated from.

Three kinds of record in that file do not carry an origin: the record written after
`seihou agent run` (`AppliedBlueprint`), the receipt written after each edge of
`seihou agent migrate` (`AppliedBlueprintMigration`), and the record written after a recipe
is applied (`AppliedRecipe`). They carry a bare name.

The sharp consequence is in the migration receipts. `seihou agent migrate` skips any edge
that already has a receipt, and it decides "already has a receipt" by comparing three
things: the blueprint name, the edge's `from` version, and the edge's `to` version. If a
project ran the `0.7.0 -> 0.8.0` edge of a blueprint called `adopt-architecture-decisions`
published by one repository, and later resolves that same name to a *different*
repository's blueprint, that second blueprint's `0.7.0 -> 0.8.0` edge is silently dropped
from the plan. Nothing is printed, because suppressing recorded edges is the feature. The
user sees a normal "no pending migrations" outcome for work that never ran.

After this plan, all three records carry an origin, and the migration skip decision
considers it. A user can see the change directly: apply the same blueprint name from two
different git repositories in two different projects, and `.seihou/manifest.json` will show
distinct `origin` blocks; run a migration edge under one and the other's identically-named
edge still appears in the plan.

This plan is the foundation for the other five plans under
`docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md`, all of which
either extend these records or read this completion key.


## Progress

- [x] Read the current record definitions and JSON instances (orientation, no edits). — 2026-08-16
- [x] Add `origin :: !ArtifactOrigin` to `AppliedBlueprint`, `AppliedBlueprintMigration`, and `AppliedRecipe` in `seihou-core/src/Seihou/Core/Types.hs`. — 2026-08-16
- [x] Update the six JSON instances in `seihou-core/src/Seihou/Manifest/Types.hs` to encode and decode the new field, with a decoder fallback for records written before it existed. — 2026-08-16
- [x] Update `hasAppliedBlueprintMigration` and `writeAppliedBlueprintMigration` in `seihou-core/src/Seihou/Manifest/Types.hs` so the upsert key includes origin. — 2026-08-16
- [x] Add `seihou-core/src/Seihou/Core/ArtifactIdentity.hs` so the three key comparisons share one definition of "same artifact" (see Decision Log). — 2026-08-16
- [x] Fill the field at the write sites. There were **four**, not three: `AgentRun.hs`, `AgentMigrate.hs`, `Run.hs`, and `seihou-cli/src/Seihou/CLI/Update.hs` (see Surprises). — 2026-08-16
- [x] Extend `alreadyApplied` inside `pendingBlueprintMigrations` in `seihou-cli/src/Seihou/CLI/BlueprintMigration.hs` to compare origin. — 2026-08-16
- [x] Add tests: JSON round-trip, legacy decode, and a same-name-different-origin skip test. — 2026-08-16
- [x] Decide and record whether this is a decoder default or a manifest schema bump. — 2026-08-16
- [x] Update `docs/user/blueprint-migrations.md`, `docs/cli/manifest.md`, and `docs/user/CHANGELOG.md`. — 2026-08-16
- [x] Close IR-2 in `docs/improvement-requests/record-artifact-origin-for-agent-applied-artifacts.md` and update `docs/improvement-requests/log.md`. Status is `completed`, not `implemented` (see Surprises). — 2026-08-16
- [x] ADR distillation pass: amended `docs/adr/0002-artifact-identity-is-origin-url-plus-name.md`. — 2026-08-16


## Surprises & Discoveries

- **There is a fourth write site the plan did not name.** `seihou-cli/src/Seihou/CLI/Update.hs`
  rebuilds the whole manifest in `buildFinalManifest` and reconstructs `AppliedRecipe` there,
  so `seihou update` also writes a recipe record. The compiler found it:

  ```text
  src/Seihou/CLI/Update.hs:849:40: error: [GHC-95909]
      • Constructor ‘AppliedRecipe’ does not have the required strict field(s):
          origin :: ArtifactOrigin
  ```

  It needed no new plumbing: the `AppliedComposition` it is folding over already carries
  `targetOrigin`, which on that branch *is* the recipe's origin, because the branch is
  selected by `target` being an `AppliedRecipeTarget`. The same shortcut applies in
  `seihou-cli/src-exe/Seihou/CLI/Run.hs`, where `targetOrigin` is already in scope at the
  construction site. Neither file needed a new `detectArtifactOrigin` call.

- **`normalizeOriginUrl` could not simply be exported from `ManifestGuard`.** The plan proposed
  exporting it from `seihou-cli/src/Seihou/CLI/ManifestGuard.hs` and using it in
  `BlueprintMigration.hs`. That works for the CLI-side predicate but not for
  `writeAppliedBlueprintMigration` and `hasAppliedBlueprintMigration`, which live in
  `seihou-core` and cannot import from `seihou-cli`. The plan itself requires all three to
  agree ("or a receipt could be written as a new entry while being read as a duplicate"), so
  the comparison moved down into core instead. See the Decision Log.

- **The manifest's JSON key for variables is `variables`, not `vars`.** The Haskell field is
  `vars`; the encoder writes `variables`. The first hand-written legacy fixture used the field
  name and failed with `Error in $: key "variables" not found`. Worth knowing for anyone
  hand-authoring a manifest fixture.

- **The IR bundle's profile does not accept `status: implemented`.** The plan said to set that
  value; `okf validate --profile-enforce` rejected it:

  ```text
  profile: record-artifact-origin-for-agent-applied-artifacts: frontmatter value at status
  must be one of [proposed, accepted, in-progress, completed, rejected, withdrawn,
  superseded], found: "implemented"
  ```

  The terminal value is `completed`, and it pulls in a required `completedAt` and a recommended
  `resolution`, both frontmatter fields. Anyone closing IR-1, IR-3, or IR-4 under the sibling
  plans should set all three at once rather than discovering them one validation run at a time.

- **The bundle already fails `--strict` for an unrelated reason.** All four IR documents, including
  the three this plan did not touch, are missing the profile-recommended `reviews` field, so
  `okf validate --strict --profile-enforce --log-enforce` exits 1 both before and after this
  change. That is pre-existing and out of scope here; the only new finding is that closing a
  request does not introduce further failures.


## Decision Log

- Decision: A manifest written before this change decodes a missing `origin` as
  `LocalOrigin <recorded name>`; `currentManifestVersion` stays at 6.
  Rationale: The plan's option 1, chosen for the reason it gives. Where such an artifact
  actually came from is unrecoverable — nothing on disk says which repository a receipt
  written last month was resolved from — so a `seihou manifest upgrade` pass would have
  nothing to write but the same weak value the decoder can supply.
  `docs/adr/0005-legacy-manifests-convert-through-an-explicit-command.md` reserves the
  explicit-command rule for conversions that lose or relocate information; this one loses
  nothing. Implemented as `legacyLocalOrigin` in
  `seihou-core/src/Seihou/Manifest/Types.hs`, shared by all three decoders.
  Date: 2026-08-16

- Decision: Put the "are these the same artifact?" comparison in a new core module,
  `seihou-core/src/Seihou/Core/ArtifactIdentity.hs`, exporting `sameArtifactIdentity`,
  `normalizeOriginUrl`, and `normalizeProjectPath` — rather than exporting
  `normalizeOriginUrl` from `Seihou.CLI.ManifestGuard` as the plan proposed.
  Rationale: Three places have to agree on the answer, and one of them
  (`writeAppliedBlueprintMigration`/`hasAppliedBlueprintMigration` in `seihou-core`) cannot
  import from `seihou-cli`. Exporting from `ManifestGuard` would have left the core upsert
  keyed on structural equality while the CLI's pending filter normalised URLs, so a receipt
  recorded under `https://host/repo.git` would have been appended as a second entry while
  being read as a duplicate — the exact hazard the plan warns about. `ManifestGuard` now
  imports the two normalisers from core and its private copies were deleted; its
  three-way `judgeArtifact`/`originRelation` verdict logic is unchanged and stays in the CLI,
  because "cannot be proved either way" has no meaning for a receipt lookup.
  Date: 2026-08-16

- Decision: `sameArtifactIdentity` compares the artifact *name* inside a `RemoteOrigin` as
  well as the URL.
  Rationale: One repository can publish several artifacts. Two `RemoteOrigin`s that share a
  URL but name different artifacts are different artifacts, and the manifest's identity rule
  in `docs/adr/0002-artifact-identity-is-origin-url-plus-name.md` is origin URL *plus* name.
  Date: 2026-08-16

- Decision: Compute the blueprint origin once per command in `handleAgentMigrate` rather than
  once per edge.
  Rationale: The blueprint cannot move mid-run, and every receipt the command writes belongs
  to the same blueprint identity. One filesystem read is enough, and threading a single value
  through `recordMigration` keeps the recorder honest about which blueprint owns the edge —
  the property `docs/plans/85-fan-out-a-blueprint-migration-edge-to-entailed-cohort-edges.md`
  will need to vary per step.
  Date: 2026-08-16


## Outcomes & Retrospective

Complete. All three agent-path and recipe records carry an `ArtifactOrigin`, the blueprint
migration completion key includes it in all three places that compute it, and manifests written
before the field existed still parse.

What was achieved, against the acceptance criteria in Validation and Acceptance:

- **Automated.** `cabal test seihou-core-test` (1056 tests) and `cabal test seihou-cli-test`
  (480 tests) both pass. The decisive case named in the plan is
  `seihou-cli/test/Seihou/CLI/BlueprintMigrationSpec.hs`, "does not let another repository's
  receipt suppress an identical edge": a receipt under
  `RemoteOrigin "https://github.com/acme/two" "payments" Nothing` no longer suppresses the same
  edge of a blueprint whose origin is `.../acme/one`. Its mirror ("does drop the edge when the
  receipt is from the same repository") guards against a future refactor that stops comparing
  origin. Two further cases cover the `.git` spelling and the legacy `LocalOrigin` reading.
- **Ledger-level.** `seihou-cli/test/Seihou/CLI/AppliedBlueprintMigrationSpec.hs` proves the
  upsert agrees with the filter: same origin replaces in place, different origin appends, and
  a `.git` spelling difference still replaces.
- **Legacy manifests.** Three cases decode hand-written manifests with no `origin` key — one per
  record kind — and assert `LocalOrigin` of the recorded name rather than a parse failure.
- **Mechanical checks.** `nix/check-record-conventions.sh` and
  `nix/check-cli-module-placement.sh` both pass; the new core module is a library module and
  needs no placement justification.

The end-to-end scenario in Validation and Acceptance (two throwaway git repositories publishing
`shared-upgrade`) was not walked by hand. The automated cases assert the same property at the two
layers where it is decided — the completion key and the receipt ledger — and the two-repository
walk exercises `seihou install` and blueprint discovery, which this plan does not change.
`docs/plans/82-refuse-to-overwrite-an-installation-from-a-different-source.md` builds exactly that
two-repository fixture for a change that does affect install, and is the natural place to run the
walk once.

Lessons worth carrying into the sibling plans:

- **Let the compiler enumerate write sites, not the plan.** The plan named three; there were four.
  Adding a strict field to a record and reading the resulting `[GHC-95909]` errors is exhaustive
  in a way that a `rg` sweep during planning was not.
- **Ask where a shared comparison has to live before deciding where to put it.** The plan's
  proposal to export `normalizeOriginUrl` from a `seihou-cli` module was sound for the one caller
  it had in mind and impossible for the two in `seihou-core`. The requirement that "all three must
  agree" is the constraint that decides placement; check it against the package graph first.
  `docs/plans/85-fan-out-a-blueprint-migration-edge-to-entailed-cohort-edges.md` will call
  `pendingBlueprintMigrations` per expanded step with each step's *owning* origin, so it inherits
  the shared definition for free.
- **Close an OKF request's frontmatter in one pass.** `status: completed` implies `completedAt`
  and `resolution`; discovering them one validation run at a time cost three round trips.

Downstream plans can rely on the exact signatures listed in Interfaces and Dependencies, with one
addition: `Seihou.Core.ArtifactIdentity.sameArtifactIdentity` rather than a `BlueprintMigration.hs`
local helper.


## Context and Orientation

### What this repository is

Seihou is a project scaffolding system written in Haskell. It is a two-package Cabal
workspace: `seihou-core` (the library, at `seihou-core/`) and `seihou-cli` (at
`seihou-cli/`). The CLI package is itself split in two — a library at `seihou-cli/src/`
(package name `seihou-cli-internal`) and an executable at `seihou-cli/src-exe/`. New code
goes in a library by default; the executable is reserved for `Main.hs`, command
dispatchers, and modules that need `Options.Applicative`, `Data.FileEmbed`, `GitHash`, or
`Paths_seihou_cli`, plus anything that transitively imports such a module. That convention
is enforced by `nix/check-cli-module-placement.sh`. This plan edits existing modules in
place and adds no new ones, so the convention does not constrain it.

Records in this repository are written with strict fields (a `!` on every field of a `data`
record), no type-abbreviation prefixes on field names, an explicit deriving strategy, and
`Generic` in the derive list. Fields are read and written through `generic-lens` overloaded
labels — `record ^. #field` to read, `record & #field .~ value` to set — never through
record dot syntax and never through record update syntax. Record *construction* and record
patterns are fine; only update syntax is out. Any module using a `#label` must add
`import Data.Generics.Labels ()` itself. These rules are enforced by
`nix/check-record-conventions.sh`. Since `ArtifactOrigin` will be added as a new field to
three existing records, every construction site of those records must be updated to supply
it — the compiler will find them all.

### Terms used in this plan

**Manifest** — `.seihou/manifest.json` inside a project seihou has generated into. It is
checked into version control and shared between developers. Its Haskell type is `Manifest`
in `seihou-core/src/Seihou/Core/Types.hs`; its JSON encoding lives in
`seihou-core/src/Seihou/Manifest/Types.hs`.

**Artifact** — any of the things seihou can apply: a module, a recipe (a named composition
of modules), a blueprint (an agent-driven runnable), or a prompt.

**Origin** — the portable identity of an artifact, modelled by the `ArtifactOrigin` type.
It is a three-constructor sum, defined at `seihou-core/src/Seihou/Core/Types.hs:517`:

```haskell
data ArtifactOrigin
  = RemoteOrigin
      { originUrl :: !Text,
        artifactName :: !Text,
        repoName :: !(Maybe Text)
      }
  | ProjectOrigin
      { relativePath :: !FilePath
      }
  | LocalOrigin
      { artifactName :: !Text
      }
  deriving stock (Eq, Ord, Show, Generic)
```

`RemoteOrigin` is the strong case: the artifact was installed by `seihou install` from a git
URL into `~/.config/seihou/installed/<name>`, and that URL was recorded in a
`.seihou-origin.json` file beside it. `ProjectOrigin` is an artifact committed inside the
project under `.seihou/modules/<name>`, identified by its project-relative path.
`LocalOrigin` is the weak case: an artifact found somewhere with no provenance seihou can
prove, such as a personal artifact in `~/.config/seihou/modules/`.

**Blueprint migration receipt** — one `AppliedBlueprintMigration` value in the manifest's
`blueprintMigrations` list. It records that the provider session for one exact
`(blueprint, from, to)` edge returned successfully. It does *not* prove the build passes;
that contract is documented in `docs/user/blueprint-migrations.md` under "What a receipt
means" and this plan does not change it.

### The three records as they exist today

In `seihou-core/src/Seihou/Core/Types.hs`:

```haskell
data AppliedRecipe = AppliedRecipe
  { name :: !RecipeName,
    recipeVersion :: !(Maybe Text),
    appliedAt :: !UTCTime
  }
  deriving stock (Eq, Show, Generic)

data AppliedBlueprint = AppliedBlueprint
  { name :: !ModuleName,
    blueprintVersion :: !(Maybe Text),
    appliedAt :: !UTCTime,
    baselineModules :: ![ModuleName],
    noBaseline :: !Bool,
    userPrompt :: !(Maybe Text),
    agentSessionId :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)

data AppliedBlueprintMigration = AppliedBlueprintMigration
  { name :: !ModuleName,
    blueprintVersion :: !(Maybe Text),
    fromVersion :: !Text,
    toVersion :: !Text,
    appliedAt :: !UTCTime,
    agentSessionId :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)
```

Compare `AppliedModule` in the same file, which already does the right thing:

```haskell
data AppliedModule = AppliedModule
  { name :: !ModuleName,
    parentVars :: !ParentVars,
    origin :: !ArtifactOrigin,
    moduleVersion :: !(Maybe Text),
    appliedAt :: !UTCTime,
    removal :: !(Maybe Removal)
  }
  deriving stock (Eq, Show, Generic)
```

The JSON encodings mirror the Haskell records. In
`seihou-core/src/Seihou/Manifest/Types.hs` around line 362:

```haskell
instance ToJSON AppliedBlueprintMigration where
  toJSON receipt =
    Aeson.object $
      [ "name" .= (receipt ^. #name . #unModuleName),
        "from" .= (receipt ^. #fromVersion),
        "to" .= (receipt ^. #toVersion),
        "appliedAt" .= (receipt ^. #appliedAt)
      ]
        ++ maybe [] (\version -> ["version" .= version]) (receipt ^. #blueprintVersion)
        ++ maybe [] (\sessionId -> ["agentSessionId" .= sessionId]) (receipt ^. #agentSessionId)
```

`ArtifactOrigin` already has `ToJSON` and `FromJSON` instances in the same file (around
line 205), encoding as an object with a `kind` discriminator of `"remote"`, `"project"`, or
`"local"`. `AppliedModule` writes it under the JSON key `origin`. Use the same key.

### The skip decision this plan fixes

`seihou-cli/src/Seihou/CLI/BlueprintMigration.hs` contains:

```haskell
pendingBlueprintMigrations ::
  Bool ->
  ModuleName ->
  [AppliedBlueprintMigration] ->
  BlueprintMigrationPlan ->
  [BlueprintMigration]
pendingBlueprintMigrations rerun blueprintName receipts plan
  | rerun = plan ^. #steps
  | otherwise = filter (not . alreadyApplied) (plan ^. #steps)
  where
    alreadyApplied migration =
      any
        ( \receipt ->
            receipt ^. #name == blueprintName
              && receipt ^. #fromVersion == migration ^. #from
              && receipt ^. #toVersion == migration ^. #to
        )
        receipts
```

Its comment says "Artifact versions and timestamps are intentionally not part of the
completion key." That is correct and must stay: an edge is the same edge regardless of which
release of the blueprint declared it. Origin is a different case — it is absent rather than
deliberately excluded, and two blueprints from different repositories that share a name and
an edge window are not the same edge.

`seihou-core/src/Seihou/Manifest/Types.hs` has two more places keyed the same way:

```haskell
writeAppliedBlueprintMigration :: AppliedBlueprintMigration -> Manifest -> Manifest
-- ... its inner `sameEdge` compares name, fromVersion, toVersion

hasAppliedBlueprintMigration :: ModuleName -> Text -> Text -> Manifest -> Bool
```

All three must agree, or a receipt could be written as a new entry while being read as a
duplicate, or vice versa.

### How an origin is produced at write time

`Seihou.Core.ArtifactOriginDetect.detectArtifactOrigin` turns an absolute artifact directory
into a portable origin:

```haskell
detectArtifactOrigin :: FilePath -> FilePath -> IO ArtifactOrigin
-- first argument: the absolute project root (the directory containing .seihou)
-- second argument: the absolute directory the artifact was loaded from
```

It reads `.seihou-origin.json` beside an installed artifact to produce a `RemoteOrigin`,
recognises a path under the project root to produce a `ProjectOrigin`, and falls back to
`LocalOrigin` with the directory's last path segment. Every manifest write site funnels its
directory through this function; `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs` already imports
and calls it at line 300 for baseline modules, so the import is present there.

The project root is obtained with `System.Directory.getCurrentDirectory`. Seihou's commands
run from the project root — `manifestPath` is built as `".seihou" </> "manifest.json"` in
both `AgentRun.hs` and `AgentMigrate.hs` — so `getCurrentDirectory` is the correct root and
matches what the existing baseline code does.

### Relevant ADRs

- `docs/adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md` — the manifest is
  checked in and must never record a path meaningful only on the writing machine. This is
  why the new field must be an `ArtifactOrigin` produced by `detectArtifactOrigin`, never a
  raw directory.
- `docs/adr/0002-artifact-identity-is-origin-url-plus-name.md` — decides that an artifact
  reference in the manifest is an `ArtifactOrigin`, and rejects the bare name as an identity
  in exactly the terms this plan addresses. This plan brings three records into line with a
  decision already accepted.
- `docs/adr/0005-legacy-manifests-convert-through-an-explicit-command.md` — decides that
  manifests written by older seihou versions convert through `seihou manifest upgrade`
  rather than silently, and that the compatibility guard has no removal date. This
  constrains how a missing `origin` key is handled: see the Decision required below.

`docs/adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md` is relevant to the
follow-on plan `docs/plans/83-guard-the-agent-path-against-stale-and-substituted-artifacts.md`,
not to this one. This plan makes a mismatch *representable*; acting on it is that plan's job.

No cross-repository ADR governs this work.

### The Improvement Request this implements

`docs/improvement-requests/record-artifact-origin-for-agent-applied-artifacts.md` (IR-2)
is the filed request. Read it: it contains the reasoning for each of the three requested
changes and explicitly proposes decoding a receipt with no `origin` as the weak case rather
than failing.


## Plan of Work

### Decision required before coding

A manifest written by the current release has no `origin` key inside its
`blueprintMigrations` entries, its `blueprint` entry, or its `recipe` entry. There are two
honest ways to read one:

1. **Decoder default.** Decode a missing `origin` as `LocalOrigin <name>` — "an artifact
   with this name, with no provenance seihou can verify". `currentManifestVersion` stays at
   6. This is what IR-2 recommends, and it matches how `ArtifactOrigin`'s `LocalOrigin`
   constructor is already used elsewhere to mean unverifiable provenance. It also matches
   the precedent of every earlier optional field: `parentVars`, `blueprint`, and
   `blueprintMigrations` were all added with decoder defaults.
2. **Schema bump.** Raise `currentManifestVersion` from 6 to 7 and require
   `seihou manifest upgrade` to fill the field.

Choose option 1 and record it in the Decision Log with this rationale: the origin of an
artifact already recorded is genuinely not recoverable — nothing on disk says which
repository a receipt written last month came from — so a conversion command would have
nothing to write but the same weak value the decoder can supply. ADR 0005's explicit-command
rule exists for conversions that lose or relocate information; this one loses nothing.
Option 2 remains available if implementation reveals a reason, in which case record that
reason instead and follow `seihou-cli/src/Seihou/CLI/ManifestUpgrade.hs` for the conversion
pattern.

Note the consequence for the completion key, and state it in the code comment: two legacy
receipts both decoding to `LocalOrigin "kiroku-upgrade"` compare equal to each other, which
is the pre-existing behaviour, and a legacy receipt does not compare equal to a new
`RemoteOrigin` receipt. A user who has already run migrations and then upgrades seihou will
see previously-recorded edges reappear as pending once. That is correct — seihou genuinely
cannot prove they are the same edge — but it must be documented in
`docs/user/CHANGELOG.md` so it does not read as a bug.

### Milestone 1 — the records and their encodings

At the end of this milestone the three records carry an origin, it round-trips through JSON,
and manifests written before the change still parse. Nothing yet writes a meaningful value:
the write sites are updated in milestone 2, so the whole workspace compiles at the end of
milestone 1 only if the write sites are given a placeholder. To avoid a half-built state,
do milestones 1 and 2 as one compile unit and commit them together; they are described
separately only because they are separate concerns.

In `seihou-core/src/Seihou/Core/Types.hs`, add `origin :: !ArtifactOrigin` to
`AppliedRecipe`, `AppliedBlueprint`, and `AppliedBlueprintMigration`. Place it immediately
after `name` in each, matching `AppliedModule`'s field order. Extend each record's Haddock
comment to say what the origin means, mirroring the wording already on `AppliedModule`:
"the artifact's portable identity; turning it back into a directory on the current machine
is `Seihou.Core.ArtifactRef.resolveArtifactOrigin`, and no path is ever recorded here."

In `seihou-core/src/Seihou/Manifest/Types.hs`, update all six instances. For each `ToJSON`,
add `"origin" .= (record ^. #origin)` to the mandatory field list — not the optional
`++ maybe []` tail, because the field is not optional on write. For each `FromJSON`, decode
it as optional with a fallback:

```haskell
    <$> (ModuleName <$> o .: "name")
    <*> (fromMaybe (LocalOrigin nameText) <$> o Aeson..:? "origin")
```

Getting the fallback's name argument requires the decoded name in scope, so restructure each
`parseJSON` from the applicative chain into a `do` block that binds the name first. Write it
explicitly rather than cleverly; these are three small decoders and clarity matters more than
symmetry with the existing style. `Data.Maybe.fromMaybe` may need importing.

Then update the two key-comparing helpers in the same file. `writeAppliedBlueprintMigration`'s
inner `sameEdge` and the standalone `hasAppliedBlueprintMigration` must both include origin.
`hasAppliedBlueprintMigration`'s signature gains a parameter:

```haskell
hasAppliedBlueprintMigration :: ArtifactOrigin -> ModuleName -> Text -> Text -> Manifest -> Bool
```

Find its callers with `rg -n "hasAppliedBlueprintMigration" --glob '*.hs'` and update them.

### Milestone 2 — filling the field at the write sites

At the end of this milestone, running `seihou agent run`, `seihou agent migrate`, and a
recipe application all write a real origin into the manifest.

There are four write sites. Do not take this list on faith — add the field first and let the
compiler enumerate them, because it is exhaustive and a search is not. That is how the fourth
one was found.

`seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs` — the function `recordMigration` near line
255 constructs the receipt. It currently receives `manifestPath` and the `Blueprint`. It
needs the blueprint's origin. `handleAgentMigrate` already has `blueprintDir` in scope from
`discoverMigrationBlueprint` at line 71. Compute the origin once, near the top of
`handleAgentMigrate`, and thread it through:

```haskell
projectRoot <- getCurrentDirectory
blueprintOrigin <- detectArtifactOrigin projectRoot blueprintDir
```

Add the imports `Seihou.Core.ArtifactOriginDetect (detectArtifactOrigin)` and
`System.Directory (getCurrentDirectory)`. Pass `blueprintOrigin` into `recordMigration` as a
new argument and set the record's `origin` field from it. Compute it once per command rather
than once per edge: the blueprint does not move mid-run, and one filesystem read is enough.

`seihou-cli/src-exe/Seihou/CLI/AgentRun.hs` — the pure helper near line 249 with the
signature `Blueprint -> BaselineStatus -> BlueprintRunOpts -> UTCTime -> AppliedBlueprint`
builds the record. Add an `ArtifactOrigin` parameter to it and keep it pure; the caller
around line 200 computes the origin the same way, from the blueprint's discovered directory.
This module already imports `detectArtifactOrigin` (used at line 300 for baseline modules)
and already calls `getCurrentDirectory` at line 297, so reuse rather than duplicate.

`seihou-cli/src-exe/Seihou/CLI/Run.hs` — around line 432, `AppliedRecipe` is constructed
inline inside a larger expression. No new call is needed: `targetOrigin`, computed near line
309 from the discovered artifact directory, *is* the recipe's origin on this branch, because
the branch that produces a `recipeInfo` of `Just` is the same branch that put the recipe's
directory into `targetInfo`. Pass it straight through and say so in a comment.

`seihou-cli/src/Seihou/CLI/Update.hs` — around line 849, `buildFinalManifest`'s `updateRecipe`
reconstructs `AppliedRecipe` when `seihou update` republishes the manifest. The same shortcut
applies for the same reason: it is folding over `AppliedComposition` values, whose
`targetOrigin` on an `AppliedRecipeTarget` branch is the recipe's origin. Note that this file
is in the CLI *library* (`seihou-cli/src/`), not the executable, so it is reachable from tests.

### Milestone 3 — the completion key

At the end of this milestone, a blueprint's edge is skipped only when a receipt from the
*same* blueprint identity records it.

In `seihou-cli/src/Seihou/CLI/BlueprintMigration.hs`, change `pendingBlueprintMigrations` to
take the blueprint's origin as well as its name:

```haskell
pendingBlueprintMigrations ::
  Bool ->
  ArtifactOrigin ->
  ModuleName ->
  [AppliedBlueprintMigration] ->
  BlueprintMigrationPlan ->
  [BlueprintMigration]
```

and extend `alreadyApplied` to compare origins alongside the existing three comparisons. Do
**not** reuse `Seihou.CLI.ManifestGuard.originRelation` here: that function answers a
different question ("can these two be proved to be the same artifact, and if not is that a
mismatch or merely unknowable"), and its `OriginUnverifiable` verdict is a deliberate
non-answer that has no meaning for a receipt lookup. A receipt either records this exact
identity or it does not.

Do not use structural `==` either. Two spellings of the same git URL —
`https://host/repo` and `https://host/repo.git` — compare unequal structurally, so a project
whose manifest was written from one spelling would see its edges reappear after installing
from the other. Use `sameArtifactIdentity`:

```haskell
-- | Whether two recorded origins name the same artifact for the purpose of
-- receipt lookup. Unlike 'Seihou.CLI.ManifestGuard.judgeArtifact' this is a
-- plain equality question with no "unverifiable" middle ground: a receipt
-- either records this identity or it does not.
sameArtifactIdentity :: ArtifactOrigin -> ArtifactOrigin -> Bool
```

That helper lives in a new core module, `seihou-core/src/Seihou/Core/ArtifactIdentity.hs`,
**not** in `BlueprintMigration.hs`, because two of the three places that must give the same
answer — `writeAppliedBlueprintMigration`'s `sameEdge` and `hasAppliedBlueprintMigration` from
milestone 1 — are in `seihou-core` and cannot import from `seihou-cli`. Create it before
milestone 1's key changes and use it in all three. It absorbs `normalizeOriginUrl` and
`normalizeProjectPath`, which were private to `Seihou.CLI.ManifestGuard`; delete them there and
import them from core so there is exactly one definition of URL normalisation in the workspace.
Remember to add the module to `exposed-modules` in `seihou-core/seihou-core.cabal`.

Within a `RemoteOrigin`, compare the artifact name as well as the normalised URL: one
repository can publish several artifacts, and ADR 0002's identity is origin URL *plus* name.
Two `LocalOrigin`s compare equal when their names match, which is what makes two receipts
written before origins existed still match each other.

Update the caller in `seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs` (line 101) to pass the
origin computed in milestone 2.

Update the function's Haddock comment so it states the full key and the exclusions:
"Exact-edge identity is the origin and name of the blueprint that owns the edge together
with its `from` and `to` versions. Artifact versions and timestamps are intentionally not
part of the completion key; origin is, because two blueprints from different repositories
that share a name and an edge window are not the same edge."

### Milestone 4 — tests

The CLI test suite is at `seihou-cli/test/`, run with `cabal test seihou-cli-test`. The core
test suite is at `seihou-core/test/`, run with `cabal test seihou-core-test`. Both use
`tasty` with `hspec` via `Test.Tasty.Hspec.testSpec`; each spec module exports
`tests :: IO TestTree` and is registered in the suite's `Main.hs`.

Extend `seihou-cli/test/Seihou/CLI/AppliedBlueprintMigrationSpec.hs`. Its existing
`mkReceipt` helper constructs an `AppliedBlueprintMigration`; give it an origin parameter.
Add cases proving:

- a receipt round-trips through `manifestToJSON` / `manifestFromJSON` with its origin intact;
- a manifest whose `blueprintMigrations` entry has no `origin` key decodes to
  `LocalOrigin` with the recorded name, and `manifestFromJSON` does not fail;
- `writeAppliedBlueprintMigration` replaces in place when the origin matches and appends
  when it differs, even with identical name, `from`, and `to`.

Extend `seihou-cli/test/Seihou/CLI/BlueprintMigrationSpec.hs` with the behaviour that
motivates the whole plan: given a plan with one edge `0.7.0 -> 0.8.0` and a receipt list
containing a receipt for that same edge under a *different* `RemoteOrigin`,
`pendingBlueprintMigrations` returns the edge rather than dropping it. Add the mirror case —
same origin, edge dropped — so a future refactor that stops comparing origin fails loudly.
Add a case proving `https://host/repo` and `https://host/repo.git` are treated as the same
identity.

Add a case to `seihou-cli/test/Seihou/CLI/AppliedBlueprintSpec.hs` covering
`AppliedBlueprint`'s origin round-trip, and one to `seihou-core/test/Seihou/Manifest/TypesSpec.hs`
covering `AppliedRecipe`'s.

### Milestone 5 — documentation and IR bookkeeping

`docs/cli/manifest.md` documents the manifest's contents; add `origin` to the descriptions
of the blueprint, blueprint-migration, and recipe records, pointing at the existing
description of `AppliedModule`'s origin rather than repeating it.

`docs/user/blueprint-migrations.md` has a section "What a receipt means" and a table under
"How the version window is planned". Update the receipt description to say that a receipt
identifies its edge by the origin and name of the blueprint that owns it, and add a row or
paragraph explaining that a blueprint of the same name installed from a different repository
has its own receipts.

`docs/user/CHANGELOG.md` needs an entry describing the change and the one-time effect on
existing projects: receipts written before this release carry no provenance, so the first
run after upgrading may list a previously-completed edge as pending. Tell the user the
remedy is to re-run it (edges are written to be safe to re-run, and the agent will find
nothing to do) or to skip it deliberately.

Finally, update the Improvement Request in
`docs/improvement-requests/record-artifact-origin-for-agent-applied-artifacts.md`. Its
terminal status is `status: completed` — the bundle's profile does not accept `implemented` —
and that value requires `completedAt` (an RFC-3339 UTC timestamp) and recommends `resolution`
(a summary of the evidence), both in the frontmatter. Set all three at once, add
`targetPlan: docs/plans/81-record-artifact-origin-for-agent-applied-artifacts.md`, and add a
short closing section naming this plan. The bundle is a profile-governed OKF bundle registered
in `mori.dhall`, so its reserved `log.md` must be maintained when a document's timestamp
advances — use `okf log add` and then validate:

```bash
okf validate docs/improvement-requests \
  --strict \
  --profile docs/improvement-requests/profile.dhall \
  --profile-enforce \
  --log-enforce
```

This exits 1 both before and after the change, because all four IR documents are missing the
profile-recommended `reviews` field. That is pre-existing and not this plan's to fix. What to
check is that closing IR-2 adds no *new* line to the output — the only lines that should remain
are one `missing profile-recommended field: reviews` per document.


## Concrete Steps

Run everything from the repository root,
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

Orient first:

```bash
rg -n "AppliedBlueprintMigration|AppliedBlueprint |AppliedRecipe" seihou-core/src/Seihou/Core/Types.hs
rg -n "instance (To|From)JSON (AppliedBlueprint|AppliedBlueprintMigration|AppliedRecipe)" seihou-core/src/Seihou/Manifest/Types.hs
rg -n "hasAppliedBlueprintMigration|writeAppliedBlueprintMigration" --glob '*.hs'
```

Build after each milestone:

```bash
cabal build all
```

The compiler is the tool that finds every construction site of the three records. Expect
errors of this shape, and treat the list as the checklist of write sites:

```text
seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs:264:5: error: [GHC-83006]
    • Constructor ‘AppliedBlueprintMigration’ does not have field ‘origin’
```

Run the test suites:

```bash
cabal test seihou-core-test
cabal test seihou-cli-test
```

Run the repository's mechanical checks before committing. The record-convention and
module-placement checks are wired into both `nix flake check` and the pre-commit hook:

```bash
nix flake check
```

Commit with all three trailers:

```text
feat(manifest): record artifact origin on agent-applied records

Give AppliedBlueprint, AppliedBlueprintMigration, and AppliedRecipe the
ArtifactOrigin the module records already carry, and make the blueprint
migration completion key include it.

MasterPlan: docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md
ExecPlan: docs/plans/81-record-artifact-origin-for-agent-applied-artifacts.md
Intention: intention_01m05ew4qbef6tn9bnphy4nv2n
```


## Validation and Acceptance

**Automated.** `cabal test seihou-core-test` and `cabal test seihou-cli-test` both pass,
including the new cases. The decisive one is in
`seihou-cli/test/Seihou/CLI/BlueprintMigrationSpec.hs`: a receipt recorded under
`RemoteOrigin "https://github.com/acme/one.git" "shared" Nothing` must not suppress the
identical edge of a blueprint whose origin is
`RemoteOrigin "https://github.com/acme/two.git" "shared" Nothing`.

**By hand, end to end.** This is the scenario IR-2 describes, and it is worth walking once.

Create two throwaway git repositories, each publishing a blueprint with the same name
`shared-upgrade` and the same single migration edge `1.0.0 -> 2.0.0`, with visibly different
edge prompts. `seihou new-blueprint shared-upgrade` scaffolds the layout; add a `migrations`
list to each `blueprint.dhall` per `docs/user/blueprint-migrations.md`.

In a scratch project:

```bash
seihou install file:///tmp/repo-one --module shared-upgrade
seihou agent --debug migrate shared-upgrade --from 1.0.0 --to 2.0.0
```

`--debug` renders the prompts and writes nothing, so use it to confirm the right blueprint
resolved. Then run it for real once so a receipt is written, and inspect the manifest:

```bash
cat .seihou/manifest.json | jq '.blueprintMigrations'
```

Expected — note the `origin` block, which is the new part:

```json
[
  {
    "name": "shared-upgrade",
    "origin": {
      "kind": "remote",
      "url": "file:///tmp/repo-one",
      "artifact": "shared-upgrade"
    },
    "from": "1.0.0",
    "to": "2.0.0",
    "appliedAt": "2026-08-16T15:02:00Z"
  }
]
```

Now install the *other* repository's blueprint over the same name and plan again:

```bash
seihou install file:///tmp/repo-two --module shared-upgrade
seihou agent --debug migrate shared-upgrade --from 1.0.0 --to 2.0.0
```

Before this change, that prints nothing to run. After it, the edge is planned and repo-two's
prompt is rendered. That difference is the acceptance criterion.

**Legacy manifest.** Hand-edit a copy of a manifest to remove the `origin` key from a
receipt, then run `seihou status`. It must not fail to parse, and the receipt must still be
listed under "Blueprint migrations:".


## Idempotence and Recovery

Every step is a source edit; re-running the build and tests is safe. Nothing in this plan
mutates a user's manifest or install cache as a side effect of implementation.

The one user-facing irreversibility is the completion-key change: a project whose receipts
predate this release will see those edges become pending again on first run. Re-running an
edge is safe by design — edge prompts are written to inspect real usage first, and
`--rerun` exists precisely for the case where a receipt is known to be meaningless. Nothing
is deleted from the manifest and no rollback is required; downgrading seihou would simply
restore the old behaviour, since the extra `origin` key is ignored by an older decoder.

If milestone 2 is interrupted partway, the workspace will not compile because the three
records demand a field their construction sites do not supply. Finish the site list from the
compiler errors rather than reverting; there are exactly three.


## Interfaces and Dependencies

No new library dependencies. Everything needed already exists in the workspace.

At the end of the plan these signatures must exist:

`seihou-core/src/Seihou/Core/Types.hs`

```haskell
data AppliedRecipe = AppliedRecipe
  { name :: !RecipeName,
    origin :: !ArtifactOrigin,
    recipeVersion :: !(Maybe Text),
    appliedAt :: !UTCTime
  }
  deriving stock (Eq, Show, Generic)

data AppliedBlueprint = AppliedBlueprint
  { name :: !ModuleName,
    origin :: !ArtifactOrigin,
    blueprintVersion :: !(Maybe Text),
    appliedAt :: !UTCTime,
    baselineModules :: ![ModuleName],
    noBaseline :: !Bool,
    userPrompt :: !(Maybe Text),
    agentSessionId :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)

data AppliedBlueprintMigration = AppliedBlueprintMigration
  { name :: !ModuleName,
    origin :: !ArtifactOrigin,
    blueprintVersion :: !(Maybe Text),
    fromVersion :: !Text,
    toVersion :: !Text,
    appliedAt :: !UTCTime,
    agentSessionId :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)
```

`seihou-core/src/Seihou/Manifest/Types.hs`

```haskell
hasAppliedBlueprintMigration ::
  ArtifactOrigin -> ModuleName -> Text -> Text -> Manifest -> Bool
```

`seihou-core/src/Seihou/Core/ArtifactIdentity.hs` — a new module, added to
`exposed-modules` in `seihou-core/seihou-core.cabal`:

```haskell
sameArtifactIdentity :: ArtifactOrigin -> ArtifactOrigin -> Bool
normalizeOriginUrl :: Text -> Text
normalizeProjectPath :: FilePath -> FilePath
```

`seihou-cli/src/Seihou/CLI/ManifestGuard.hs` — its private `normalizeOriginUrl` and
`normalizeProjectPath` are deleted and imported from the module above instead. Its exports
are unchanged; `judgeArtifact` and `originRelation` keep their three-way verdict.

`seihou-cli/src/Seihou/CLI/BlueprintMigration.hs`

```haskell
pendingBlueprintMigrations ::
  Bool ->
  ArtifactOrigin ->
  ModuleName ->
  [AppliedBlueprintMigration] ->
  BlueprintMigrationPlan ->
  [BlueprintMigration]
```

Downstream plans depend on these exact shapes:
`docs/plans/84-add-a-not-applicable-outcome-for-blueprint-migration-edges.md` adds an
outcome field to `AppliedBlueprintMigration` and narrows `alreadyApplied` to applied
receipts; `docs/plans/85-fan-out-a-blueprint-migration-edge-to-entailed-cohort-edges.md`
calls `pendingBlueprintMigrations` once per expanded step with that step's owning blueprint
identity; `docs/plans/86-infer-the-blueprint-migration-version-window.md` selects receipts
by the same identity to derive a default `--from`. All three should compare identities with
`Seihou.Core.ArtifactIdentity.sameArtifactIdentity` rather than structural `==`, so URL
spelling differences do not resurface as duplicated or reappearing edges.


## Revision Notes

**2026-08-16 — implementation.** Three things in the plan as written did not survive contact
with the code, and the sections above have been updated to match what was built.

The plan proposed exporting `normalizeOriginUrl` from `seihou-cli/src/Seihou/CLI/ManifestGuard.hs`
and defining `sameArtifactIdentity` locally in `seihou-cli/src/Seihou/CLI/BlueprintMigration.hs`.
That cannot satisfy the plan's own requirement, stated in Context and Orientation, that the
completion key in `pendingBlueprintMigrations`, `writeAppliedBlueprintMigration`'s `sameEdge`, and
`hasAppliedBlueprintMigration` all agree — the latter two are in `seihou-core`, which cannot import
from `seihou-cli`. The comparison moved into a new core module, `Seihou.Core.ArtifactIdentity`,
which also absorbed `ManifestGuard`'s two private normalisers. Interfaces and Dependencies now
lists that module; Milestone 3's instruction to define the helper locally is superseded by it.

The plan named three write sites for the new field. There are four: `seihou-cli/src/Seihou/CLI/Update.hs`
reconstructs `AppliedRecipe` in `buildFinalManifest` when `seihou update` republishes the manifest.
Milestone 2's site list and the Progress entry now say four. Neither the `Run.hs` nor the
`Update.hs` site needed a new `detectArtifactOrigin` call, because the composition they are
building already carries `targetOrigin`, which on the recipe branch *is* the recipe's origin.

Milestone 5 said to set IR-2's frontmatter to `status: implemented`. The bundle's profile does not
admit that value; the terminal status is `completed`, and it requires `completedAt` and recommends
`resolution`. All three are set. See Surprises & Discoveries for the validator output.

The reason for each change is the same in all three cases: the plan specified a location or a
literal value that the surrounding system rejects, while the *property* it was specifying — one
shared answer to "same artifact", an origin at every write site, a closed request — is unchanged
and is what shipped.
