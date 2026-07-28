---
id: 79
slug: upgrade-legacy-absolute-path-manifests-in-place
title: "Upgrade legacy absolute-path manifests in place"
kind: exec-plan
created_at: 2026-07-28T01:48:18Z
intention: "intention_01kyk6fnbyegxss8fqnf3j03tf"
master_plan: "docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md"
---

# Upgrade legacy absolute-path manifests in place

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Seihou records what it generated into `.seihou/manifest.json` inside each project, and
teams check that file into git. Every manifest written by a released version of seihou
records, for each applied module, the absolute filesystem path where that module lived on
the machine that ran the command — for example
`/Users/shinzui/.config/seihou/installed/haskell-base`.

Two earlier plans in this initiative removed that from the format.
`docs/plans/76-record-portable-artifact-origins-in-the-manifest.md` replaced the paths with
a portable `ArtifactOrigin` and bumped the manifest schema version from 5 to 6.
`docs/plans/77-resolve-manifest-artifact-origins-to-local-directories.md` made every command
resolve that origin locally. But those plans deliberately made schema-5-and-earlier
manifests *fail to load*, with a message telling the user to run a command that does not yet
exist.

This plan makes that command exist, and makes it work. After this plan, a developer who
pulls a repository containing an old manifest runs:

```bash
seihou manifest upgrade
```

and gets:

```text
Reading .seihou/manifest.json (schema version 5)

  haskell-base       /Users/shinzui/.config/seihou/installed/haskell-base
                  →  remote https://github.com/shinzui/seihou-modules.git

  project-lint       /Users/shinzui/work/myproject/.seihou/modules/project-lint
                  →  project .seihou/modules/project-lint

  scratch-helper     /Users/other/.config/seihou/modules/scratch-helper
                  →  local scratch-helper  (no upstream recorded)

✓ Upgraded .seihou/manifest.json to schema version 6.
  Review the diff and commit it: git diff .seihou/manifest.json
```

A `--dry-run` flag shows the same report and writes nothing. Every conversion is explained,
because converting another developer's absolute path into a portable identity involves
inference, and inference that happens silently in a checked-in file is exactly what this
initiative is trying to eliminate.

The command is idempotent: running it on an already-upgraded manifest reports that there is
nothing to do and exits zero.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Milestone 1: `LegacyManifest` decoding for schema versions 1 through 5 (2026-07-28)
- [x] Milestone 1: Golden-file tests decoding a real schema-5 manifest without data loss (2026-07-28)
- [x] Milestone 2: `inferOriginFromLegacyPath` with its confidence outcome type (2026-07-28)
- [x] Milestone 2: Unit tests for every inference outcome (2026-07-28)
- [x] Milestone 3: `seihou manifest upgrade` subcommand with `--dry-run` (2026-07-28)
- [x] Milestone 3: Report rendering matches the format in this plan (2026-07-28)
- [x] Milestone 4: Every other command detects a legacy manifest and points at the upgrade (2026-07-28)
- [x] Milestone 4: Refuse to write an upgrade that would immediately trip the downgrade guard (2026-07-28)
- [x] Milestone 5: `docs/user/` documentation and CHANGELOG entry (2026-07-28)
- [x] Milestone 5 (added): `docs/cli/manifest.md` command reference, `seihou help manifest` topic, README index rows (2026-07-28)


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **One legacy decoder really was enough for versions 1 through 5.** The
  Context section predicted this and it held: every field a later schema
  version added is optional with an empty default, and none of them holds a
  path, so `readLegacyManifest` never branches on the version it read. It
  reports the version for the report's header and otherwise treats every
  pre-6 document identically. The four schema-version fixtures in
  `seihou-cli/test/Seihou/CLI/ManifestUpgradeSpec.hs` (`describe "schema
  versions 1 through 5"`) go through the same code path and produce the same
  conversions.

- **An application's target can be a recipe, and a recipe is not discovered by
  `module.dhall`.** The plan's `LegacyRef` sketch carried no definition file,
  so the local lookup in Milestone 2 would have searched for
  `<dir>/haskell-service/module.dhall` for an application whose target is the
  recipe `haskell-service`, never found it, and silently degraded a
  recoverable `RemoteOrigin` to `LocalOrigin`. `LegacyRef` therefore carries a
  `definitionFile`, read from `target.kind` — see the Decision Log.

  Evidence: the golden fixture's second application has
  `"target": {"kind": "recipe", "name": "haskell-service"}`, and the
  `readLegacyManifest` spec asserts that reference resolves with
  `recipe.dhall` while its sibling instances resolve with `module.dhall`.

- **A "no absolute paths remain" assertion cannot be a substring grep for the
  other developer's username.** The first version of the machine-independence
  test grepped the upgraded document for `someone-else` and failed: the
  fixture records a *variable* whose value is `someone-else`, which is project
  data and must survive the upgrade untouched. The assertion is now the actual
  ADR-0001 invariant — no string value beginning with `/`, `~`, `\\`, or a
  Windows drive prefix — which is both correct and what
  `docs/plans/80-document-and-end-to-end-verify-the-shared-manifest-workflow.md`
  will want to generalise.

- **Every manifest reader already surfaces the version guard; one deliberately
  does not.** Milestone 4 asked for an audit of
  `grep -rn "readManifest\|manifestFromJSON"`. All fourteen call sites funnel
  through `Seihou.Effect.ManifestStore.readManifest`, whose `Left` carries the
  decoder's message, and every command-level caller prints it and exits
  non-zero — `Run.hs:271`, `AgentRun.hs:365`, `Status.hs:46`, `Diff.hs:37`,
  `Remove.hs:31`, `Migrate.hs:203`, `AgentMigrate.hs:171`, and
  `Update.hs:977` (as `UpdateManifestUnreadable`). The exception is the
  post-upgrade migration advisory in
  `seihou-cli/src-exe/Seihou/CLI/Upgrade.hs:291`, which reads `Left _ -> pure
  ()`: it is advice layered on an install that already succeeded, and it is
  exactly the advisory-consumer case EP-77's Decision Log carved out. No
  change was needed.

  Evidence: on a legacy manifest, `seihou status` prints
  `[error] Error reading manifest: Error in $: this manifest uses schema
  version 5, … run 'seihou manifest upgrade' to convert it` and exits 1.

- **The interlock's most common trigger is the fresh clone, not the stale
  install.** The plan describes the guard interlock as protection against
  upgrading into a downgrade. In practice the verdict it produces most often
  is `ArtifactUnresolvable`, because a developer who has just pulled a
  repository with a legacy manifest frequently has none of its modules
  installed — and that is the case where inference is *weakest*, since every
  entry degrades to `LocalOrigin` and the upstream URLs are lost for good in a
  file about to be committed. Refusing there is more valuable than refusing a
  downgrade, which makes `--force` load-bearing rather than an afterthought:
  it is the flag for the developer who genuinely means "record what I can see".


## Decision Log

Record every decision made while working on the plan.

- Decision: Conversion is an explicit, reviewable command rather than an automatic upgrade
  on first read.
  Rationale: Converting `/Users/someone/.config/seihou/installed/haskell-base` into
  `RemoteOrigin "https://…" "haskell-base"` requires inferring the URL from the *local*
  machine's install metadata, which may disagree with what the original author had. Doing
  that silently would write an unreviewed guess into a file that is committed to git and
  that later commands trust. An explicit command with a printed report and a `--dry-run`
  keeps the inference visible and the resulting diff reviewable.
  Date: 2026-07-28

- Decision: When the local machine has no information about a recorded artifact, fall back
  to `LocalOrigin <name>` rather than failing the whole upgrade.
  Rationale: A partial upgrade that honestly marks the unknown entries as unverifiable is
  more useful than no upgrade at all, and `LocalOrigin` is precisely the constructor that
  means "provenance unknown". `docs/plans/78-refuse-accidental-module-downgrades-and-origin-mismatches.md`
  already treats `LocalOrigin` as unverifiable rather than trusted, so nothing downstream is
  misled. The report marks these entries clearly so the developer can improve them by
  reinstalling from the real URL.
  Date: 2026-07-28

- Decision: A `LegacyRef`'s `jsonPointer` ends with the key that holds the path
  (`["modules", "0", "source"]`), not with the record that contains it
  (`["modules", "0"]`) as this plan's sketch showed.
  Rationale: The rewriter has to delete one key and insert its portable
  counterpart, so it needs the key's name. Deriving it from the pointer's shape
  — "an index directly under `applications` means `targetSource`" — would encode
  the manifest layout twice, in the collector and again in the rewriter, and the
  two could drift. Ending the pointer at the key states it once.
  Date: 2026-07-28

- Decision: `LegacyRef` carries a `definitionFile`, which is `recipe.dhall` when
  an application's `target.kind` is `recipe` and `module.dhall` everywhere else.
  Rationale: Milestone 2's local lookup asks the resolver to find a directory
  containing the artifact's definition file. Recipes are not discovered by
  `module.dhall`, so without this a recipe target would never resolve locally
  and would silently degrade from a recoverable `RemoteOrigin` to `LocalOrigin`
  — the upgrade would lose exactly the provenance it exists to recover. This
  extends the type sketched in this plan's Interfaces section; the module is
  owned by this plan, and no interface owned by another plan changed.
  Date: 2026-07-28

- Decision: The report deduplicates by artifact name *and* legacy path rather
  than by name alone.
  Rationale: The same module appears up to three times at the same path, and
  collapsing those is the point. But two records naming the same artifact at
  *different* paths mean the manifest was written across a move or a rename,
  which is precisely the sort of thing a developer reviewing an inferred
  conversion should see rather than have hidden.
  Date: 2026-07-28

- Decision: `ManifestUpgradeOpts` and every handler live in the
  `seihou-cli-internal` library (`Seihou.CLI.ManifestUpgrade` and the subcommand
  group `Seihou.CLI.Manifest`), not in `seihou-cli/src-exe/` as this plan's
  Milestone 3 sketched.
  Rationale: `seihou registry` already sets the precedent — `RegistryCommand`
  and `SyncVersionsOpts` live in `src/` and `Seihou.CLI.Commands` imports them,
  rather than the reverse. Following it keeps every line of behaviour testable
  from the test suite (which links the library, not the executable) and leaves
  `src-exe/` holding only the `Options.Applicative` parser, which is what
  `CLAUDE.md`'s module-placement rule asks for.
  Date: 2026-07-28

- Decision: Write the rewritten `Aeson.Value` bytes, but validate them first by
  decoding into a `Manifest`.
  Rationale: Milestone 3 offered two options and each answers a different
  worry. Writing the rewritten `Value` is what guarantees no field is dropped;
  decoding into a `Manifest` is what proves the result is readable by every
  command that will read it. Doing both costs one extra decode and gives both
  guarantees, so a conversion that would produce an unreadable manifest fails
  before anything is written rather than after.
  Date: 2026-07-28

- Decision: Replicate the write-to-temp-then-rename in
  `Seihou.CLI.ManifestUpgrade.writeDocument` rather than routing the write
  through `Seihou.Effect.ManifestStore.writeManifest`.
  Rationale: `writeManifest` encodes a typed `Manifest`, which would drop any
  field this build does not know about — the one thing the upgrade must not do.
  The atomicity it provides is four lines, and this plan needs those four lines
  applied to raw bytes. `docs/plans/44-make-manifest-writes-atomic.md` records
  why atomicity matters; the mechanism is unchanged.
  Date: 2026-07-28

- Decision: `formatUpgradeReport` renders the header and the per-artifact
  blocks only. Whether anything was written is printed by the handler.
  Rationale: The same conversion account is shown for a dry run, a successful
  write, and (from Milestone 4) a refusal. Putting the outcome inside the
  renderer would mean either three renderers or a flag argument, and would make
  the golden report test assert on two unrelated things at once.
  Date: 2026-07-28

- Decision: The interlock renders its own refusal from
  `Seihou.CLI.ManifestGuard.summarizeCheck` rather than calling
  `formatGuardRefusal`, and `--dry-run` shows the refusal as a warning while
  still exiting zero.
  Rationale: `formatGuardRefusal` ends by naming `--allow-downgrade`, which is
  a flag on `seihou run` and `seihou migrate` and not on this command; printing
  it here would send the developer to a flag that does not exist. The verdicts
  are the guard's and are reused unchanged; only the remedy paragraph is this
  command's. Showing the refusal during a dry run costs one guard pass and
  means a developer previewing the conversion learns in the same breath that
  it would not be written — but a preview that writes nothing cannot itself
  fail, so the exit code stays zero.
  Date: 2026-07-28

- Decision: Do not warn when `.seihou/manifest.json` has uncommitted changes.
  Rationale: This plan's Idempotence and Recovery section asked for a decision.
  The value of a warning is that the developer can tell the upgrade's diff from
  their own, and the successful report already ends by inviting exactly that
  (`git diff .seihou/manifest.json`). Against it: `Seihou.CLI.Git` has no
  per-path status helper, so this would mean a new `git status --porcelain`
  call through the `Process` effect for a message that repeats advice already
  on screen, in a command that is safe to run twice and trivially revertible.
  Date: 2026-07-28


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

`seihou manifest upgrade` exists and does what the Purpose section promised: a
developer who pulls a repository containing a schema-5-or-earlier manifest runs
it, sees every conversion explained, and gets a manifest that means the same
thing on every machine. `--dry-run` writes nothing. Running it twice reports
"nothing to do" and exits zero. The whole thing is undone by
`git checkout -- .seihou/manifest.json`.

Two things came out better than the plan asked for and one came out narrower.

**Better: the write is both lossless and validated.** Milestone 3 offered two
mutually exclusive options — walk the `Aeson.Value` so nothing is dropped, or
decode into a `Manifest` so the result is proven readable. Doing both costs one
decode and gives both guarantees, so a conversion that would produce an
unreadable manifest now fails before the file is touched.

**Better: the interlock protects the case that actually happens.** The plan
framed the guard interlock as protection against upgrading into a downgrade.
The verdict it fires on most is `ArtifactUnresolvable`, on a fresh clone where
nothing is installed — the case where inference is weakest and where writing
anyway would erase every upstream URL from a file about to be committed. See
Surprises & Discoveries.

**Narrower: no dirty-manifest warning.** The plan asked for a decision and the
decision was no; the rationale is in the Decision Log.

Scope grew by three documentation surfaces the plan did not name: `docs/cli/`
holds a per-command reference for every command, `seihou help <topic>` holds
twelve embedded topics, and `README.md` indexes both. A command that exists
only because an error message points at it needs to be findable from all three,
so `docs/cli/manifest.md`, `seihou-cli/help/manifest.md`, and two README rows
were added alongside `docs/user/manifest-upgrade.md` and the CHANGELOG entry.

The user-facing "how teams share a manifest" guide and the two-developer
end-to-end test remain with
`docs/plans/80-document-and-end-to-end-verify-the-shared-manifest-workflow.md`,
as the plan intended. That plan should assert on
`Seihou.CLI.ManifestUpgrade.formatUpgradeReport`'s wording rather than on the
handler's stdout, and can reuse `formatUpgradeRefusal` for the refusal path.

No new ADR was needed. This plan implements the conversion that
`docs/adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md`
already anticipates ("Manifests written before schema version 6 cannot be read
directly … refuses them with a message naming the conversion command"), and
introduces no durable constraint that record does not already state. The
question it might have raised — how long legacy manifests remain convertible —
did not come up: the conversion is a self-contained module with no runtime cost
to anything else, so there is no pressure to date its removal, and inventing a
deprecation policy nobody needs would be worse than silence.


## Context and Orientation

This section assumes no prior knowledge of the repository.

**The repository layout.** `seihou` is a Haskell project built with Cabal, targeting GHC
9.12.2 and the `GHC2024` language edition. `cabal.project` defines three packages:
`seihou-core` (types, Dhall loading, generation engine, manifest handling), `seihou-cli`
(a library at `seihou-cli/src/` called `seihou-cli-internal` plus an executable at
`seihou-cli/src-exe/` called `seihou`), and `seihou-okf-extension`.

`CLAUDE.md` at the repository root sets the module-placement rule: new CLI code goes in
`seihou-cli/src/` by default; `seihou-cli/src-exe/` is reserved for `Main.hs`, command
dispatchers, and modules that need `Options.Applicative`, `Data.FileEmbed`, `GitHash`, or
`Paths_seihou_cli`, or that transitively import a module that does — most commonly
`Seihou.CLI.Commands`, which is trapped by `Options.Applicative`. Enforced by
`nix/check-cli-module-placement.sh` in `nix flake check` and the pre-commit hook. For this
plan: the conversion logic goes in `seihou-cli/src/`; only the option parser and the
dispatcher entry go in `seihou-cli/src-exe/`.

**Record conventions**, from `CLAUDE.md` and `docs/dev/architecture/overview.md` under
"Record Conventions", enforced by `nix/check-record-conventions.sh`: every `data` record
field carries `!`; `newtype` fields are exempt; no type-abbreviation prefixes; explicit
`deriving stock (...)` including `Generic`; fields read and written through `generic-lens`
overloaded labels, never record-dot syntax and never record *update* syntax. Every module
using a `#label` adds `import Data.Generics.Labels ()` itself.

**What the old manifest looks like.** Schema version 5 is what every released seihou writes
today. Its encoder is `instance ToJSON Manifest` at
`seihou-core/src/Seihou/Manifest/Types.hs:127`. A representative fragment:

```json
{
  "version": 5,
  "generatedAt": "2026-07-01T12:00:00Z",
  "modules": [
    {
      "name": "haskell-base",
      "source": "/Users/shinzui/.config/seihou/installed/haskell-base",
      "version": "1.4.0",
      "appliedAt": "2026-07-01T12:00:00Z"
    }
  ],
  "variables": {},
  "files": {
    "flake.nix": {
      "hash": "…",
      "module": "haskell-base",
      "strategy": "dhall-text",
      "generatedAt": "2026-07-01T12:00:00Z"
    }
  },
  "applications": [
    {
      "applicationId": "…",
      "target": {"kind": "module", "name": "haskell-base"},
      "targetSource": "/Users/shinzui/.config/seihou/installed/haskell-base",
      "targetVersion": "1.4.0",
      "additionalModules": [],
      "instances": [
        {
          "name": "haskell-base",
          "source": "/Users/shinzui/.config/seihou/installed/haskell-base",
          "version": "1.4.0",
          "resolvedVars": {}
        }
      ],
      "appliedAt": "2026-07-01T12:00:00Z"
    }
  ],
  "blueprintMigrations": []
}
```

Three keys hold machine-specific paths: `"source"` inside each entry of `"modules"`,
`"source"` inside each entry of an application's `"instances"`, and `"targetSource"` on the
application itself. Everything else is already portable — `"files"` is keyed by
project-relative destination paths, and `"blueprintMigrations"`, `"recipe"`, and
`"blueprint"` carry no paths.

Earlier schema versions differ only by absent optional keys. The doc comment on
`currentManifestVersion` in `seihou-core/src/Seihou/Manifest/Types.hs` records the history:
version 2 added `parentVars` to applied modules; version 3 added the optional `blueprint`
field; version 4 added reproducible `applications` and baseline/ownership fields on file
records; version 5 added the `blueprintMigrations` receipt ledger. Every decoder already
treats each of those as optional with an empty default, so a version-1 manifest and a
version-5 manifest go through the same code path. That means this plan needs one legacy
decoder, not five.

**What the earlier plans in this initiative did.**

`docs/plans/76-record-portable-artifact-origins-in-the-manifest.md` added to
`seihou-core/src/Seihou/Core/Types.hs`:

```haskell
data ArtifactOrigin
  = RemoteOrigin { originUrl :: !Text, artifactName :: !Text, repoName :: !(Maybe Text) }
  | ProjectOrigin { relativePath :: !FilePath }
  | LocalOrigin { artifactName :: !Text }
  deriving stock (Eq, Ord, Show, Generic)
```

It bumped `currentManifestVersion` from 5 to 6, made the encoder emit `"origin"` and
`"targetOrigin"` instead of `"source"` and `"targetSource"`, and added a guard in
`instance FromJSON Manifest` at `seihou-core/src/Seihou/Manifest/Types.hs:141` that fails
any manifest with `version < 6` with a message containing
`"run 'seihou manifest upgrade' to convert it"`. It also created
`seihou-core/src/Seihou/Core/ArtifactOriginDetect.hs`:

```haskell
data OriginInfo = OriginInfo
  { sourceUrl :: !Text,
    repoName :: !(Maybe Text),
    version :: !(Maybe Text)
  }
  deriving stock (Eq, Generic, Show)

readOriginInfo :: FilePath -> IO (Maybe OriginInfo)
detectArtifactOrigin :: FilePath -> FilePath -> IO ArtifactOrigin
```

`readOriginInfo` reads `.seihou-origin.json` from an installed-module directory — the file
`seihou install` writes, recording `sourceUrl`, `repoName`, `version`, `installedAt`, and
`tags`. `detectArtifactOrigin projectRoot artifactDir` classifies an absolute directory into
one of the three constructors.

`docs/plans/77-resolve-manifest-artifact-origins-to-local-directories.md` added
`seihou-core/src/Seihou/Core/ArtifactRef.hs`:

```haskell
data ArtifactRefError
  = ArtifactNotFoundLocally !ArtifactOrigin ![FilePath]
  | ProjectArtifactMissing !ArtifactOrigin !FilePath
  deriving stock (Eq, Show, Generic)

resolveArtifactOrigin ::
  FilePath -> [FilePath] -> FilePath -> ArtifactOrigin -> IO (Either ArtifactRefError FilePath)

renderArtifactRefError :: ArtifactRefError -> Text
```

and deleted the `source` and `targetSource` fields from `AppliedModule`,
`AppliedInstanceState`, and `AppliedComposition` in
`seihou-core/src/Seihou/Core/Types.hs`. That deletion is why this plan cannot simply decode
a legacy manifest into the current `Manifest` type — the fields to hold the old paths no
longer exist. This plan therefore introduces a separate legacy representation.

`docs/plans/78-refuse-accidental-module-downgrades-and-origin-mismatches.md` (a soft
dependency — this plan can be implemented before it) added
`seihou-cli/src/Seihou/CLI/ManifestGuard.hs` with `checkAppliedArtifacts`,
`blockingChecks`, and `formatGuardRefusal`, which compare recorded versions and origins
against what is installed locally.

**How module discovery works**, because the inference in Milestone 2 mirrors it.
`seihou-core/src/Seihou/Core/Module.hs:152`:

```haskell
defaultSearchPaths :: IO [FilePath]
defaultSearchPaths = do
  cwd <- getCurrentDirectory
  xdgConfig <- getXdgDirectory XdgConfig "seihou"
  pure
    [ cwd </> ".seihou" </> "modules",
      xdgConfig </> "modules",
      xdgConfig </> "installed"
    ]
```

`getXdgDirectory XdgConfig` honours the `XDG_CONFIG_HOME` environment variable, which is how
the validation scenarios below simulate a second machine.

**How subcommands are registered.** Every command's option parser and its record live in
`seihou-cli/src-exe/Seihou/CLI/Commands.hs`, and the dispatcher that maps a parsed command to
its handler is in `seihou-cli/src-exe/Main.hs` — confirm with
`grep -n "handleMigrate\|handleStatus" seihou-cli/src-exe/Main.hs`. Existing multi-word
commands such as `seihou new-module`, `seihou agent run`, and `seihou registry validate`
show both the flat and the nested pattern; read
`grep -n "registry" seihou-cli/src-exe/Seihou/CLI/Commands.hs` to see how a nested
subcommand group is built, since `manifest upgrade` is the same shape.

**Architecture Decision Records.** Plan 76 creates `docs/adr/` with two records. Read both.
`docs/adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md` is the constraint
this plan retrofits onto existing files;
`docs/adr/0002-artifact-identity-is-origin-url-plus-name.md` explains what a converted entry
must contain. Adjust the filenames to whatever plan 76 allocated, per
`agents/skills/exec-plan/ADR.md`. If this plan's implementation establishes a durable rule
about how long legacy manifests remain convertible, add a third ADR recording it.

**Build and test commands.** From the repository root:

```bash
cabal build all
cabal test all
nix flake check
```


## Plan of Work

Five milestones.

### Milestone 1 — decode the legacy format into a separate type

The current `Manifest` type no longer has fields for absolute paths, so decoding a legacy
manifest into it is impossible. Introduce a parallel, minimal representation that captures
exactly what the upgrade needs, and leave everything else as raw JSON so no data is lost in
the round trip.

Create `seihou-cli/src/Seihou/CLI/ManifestUpgrade.hs` and add
`Seihou.CLI.ManifestUpgrade` to the `exposed-modules` list of the `library` stanza in
`seihou-cli/seihou-cli.cabal`, keeping the list sorted.

```haskell
-- | One legacy artifact reference found in a schema-5-or-earlier manifest.
--
-- @jsonPointer@ locates the reference inside the document so the rewriter
-- can put the converted origin back in the right place, and so the report
-- can say which record it came from. It is a list of object keys and array
-- indices, for example @["modules", "0"]@ or
-- @["applications", "0", "instances", "1"]@.
data LegacyRef = LegacyRef
  { jsonPointer :: ![Text],
    artifactName :: !Text,
    legacyPath :: !FilePath,
    recordedVersion :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)

-- | Every legacy reference in a document, together with the document
-- itself so the rewriter can operate on it directly.
data LegacyManifest = LegacyManifest
  { schemaVersion :: !Int,
    document :: !Aeson.Value,
    refs :: ![LegacyRef]
  }
  deriving stock (Eq, Show, Generic)

-- | Parse a manifest document that has not yet been upgraded.
-- Returns 'Nothing' when the document's @version@ is already at or above
-- the current schema version, so callers can treat "nothing to do" as an
-- ordinary outcome rather than an error.
readLegacyManifest :: LBS.ByteString -> Either String (Maybe LegacyManifest)
```

Work on `Aeson.Value` directly rather than defining mirror records for every legacy type.
That is deliberate: the upgrade only needs to find three keys and replace them, and every
other field — resolved variables, file records, baselines, command receipts, blueprint
migration receipts — must survive byte-for-byte. Walking the `Value` guarantees that;
decoding into typed mirrors and re-encoding would risk dropping a key that a later schema
version added.

Collect refs from three places: each element of `"modules"` (`"source"`, `"name"`,
`"version"`); each element of `"applications"` (`"targetSource"`, the target's `"name"`,
`"targetVersion"`); and each element of each application's `"instances"` (`"source"`,
`"name"`, `"version"`). Note that an application's target name lives at
`target.name` and its kind at `target.kind` — see the `AppliedTarget` encoder at
`seihou-core/src/Seihou/Manifest/Types.hs:158`, which writes
`{"kind": "module"|"recipe", "name": …}`.

Test with a golden file. Create
`seihou-cli/test/fixtures/legacy-manifest-v5.json` containing the full schema-5 example from
Context and Orientation above, extended with a second application, a recipe target, resolved
variables, a file record with a baseline, and a blueprint migration receipt — the point is to
prove nothing is dropped. Add
`seihou-cli/test/Seihou/CLI/ManifestUpgradeSpec.hs`, registered in the test-suite
`other-modules` of `seihou-cli/seihou-cli.cabal` and in `seihou-cli/test/Main.hs` following
the existing pattern. Assert that `readLegacyManifest` on the fixture finds exactly the
expected refs with the expected pointers, and that a schema-6 document yields
`Right Nothing`.

### Milestone 2 — infer an origin from a legacy path

Add to the same module:

```haskell
-- | How confident the upgrade is about a converted origin.
data InferenceOutcome
  = -- | The artifact resolved locally and its install metadata gave a
    -- URL. Strongest result.
    InferredFromLocalInstall !ArtifactOrigin
  | -- | The legacy path is inside this project, so it converts to a
    -- 'ProjectOrigin' by pure path arithmetic with no local lookup.
    InferredFromProjectPath !ArtifactOrigin
  | -- | Nothing local matched; fell back to 'LocalOrigin' carrying only
    -- the recorded name. The developer should reinstall from the real
    -- upstream to improve this.
    InferredAsUnverifiable !ArtifactOrigin
  deriving stock (Eq, Show, Generic)

-- | The converted origin, whatever the confidence.
inferredOrigin :: InferenceOutcome -> ArtifactOrigin

-- | Convert one legacy reference into a portable origin.
--
-- @projectRoot@ is the absolute directory holding @.seihou@.
-- @searchPaths@ is normally 'Seihou.Core.Module.defaultSearchPaths'.
inferOriginFromLegacyPath ::
  FilePath ->
  [FilePath] ->
  LegacyRef ->
  IO InferenceOutcome
```

Inference proceeds in three steps.

First, path arithmetic that needs no local state. If the legacy path, after normalisation,
is inside `projectRoot`, produce `ProjectOrigin` with the relative path and forward slashes
— exactly the form `detectArtifactOrigin` produces. This case is exact rather than inferred,
because the path is meaningful in every clone. Note the caveat and handle it: the legacy path
was written by *another* machine, so the project-root prefix will be that machine's project
directory, not yours. Detect this case by matching the *suffix* instead: a legacy path whose
tail is `.seihou/modules/<name>` is a project origin regardless of what precedes it. Prefer
the suffix test; use the containment test only as a confirmation.

Second, a local lookup. Search `searchPaths` for `<dir>/<artifactName>` containing
`module.dhall`; on a hit, call `detectArtifactOrigin projectRoot foundDir`. If that yields a
`RemoteOrigin`, return `InferredFromLocalInstall`. Reuse
`resolveArtifactOrigin` from `seihou-core/src/Seihou/Core/ArtifactRef.hs` by passing
`LocalOrigin artifactName` as the origin — that constructor's resolution behaviour is exactly
"find the directory named `<artifactName>` in the search paths", which is what is needed
here.

Third, fall back to `LocalOrigin artifactName` and return `InferredAsUnverifiable`.

One useful refinement for the second step: the legacy path's own shape carries a hint. A
path ending in `.config/seihou/installed/<name>` says the original author had it installed
from a URL, so if the local lookup fails, the report should say "was installed from an
upstream on the original machine, but no local copy is available to recover the URL" rather
than a bare "unverifiable". Encode that as extra text in the report, not as another
constructor.

Test each outcome in `seihou-cli/test/Seihou/CLI/ManifestUpgradeSpec.hs` with temporary
directory trees, following the pattern in `seihou-core/test/Seihou/Core/ScaffoldSpec.hs`.
Cover: a legacy path ending `.seihou/modules/demo` under a foreign project root converting to
`ProjectOrigin ".seihou/modules/demo"`; a legacy path under a foreign home directory whose
artifact *is* installed locally with a `.seihou-origin.json` converting to a `RemoteOrigin`
with that URL; the same with no local copy converting to `LocalOrigin`; and a locally
installed copy with no `.seihou-origin.json` converting to `LocalOrigin`.

### Milestone 3 — the `seihou manifest upgrade` command

Add the rewriter and the report to `seihou-cli/src/Seihou/CLI/ManifestUpgrade.hs`:

```haskell
-- | One line of the upgrade report.
data UpgradeReportEntry = UpgradeReportEntry
  { artifactName :: !Text,
    legacyPath :: !FilePath,
    outcome :: !InferenceOutcome
  }
  deriving stock (Eq, Show, Generic)

data UpgradeResult = UpgradeResult
  { fromVersion :: !Int,
    entries :: ![UpgradeReportEntry],
    upgradedDocument :: !Aeson.Value
  }
  deriving stock (Eq, Show, Generic)

-- | Convert a legacy manifest document. Pure given the inferences.
applyUpgrade :: LegacyManifest -> [(LegacyRef, InferenceOutcome)] -> UpgradeResult

-- | Render the report shown in the terminal.
formatUpgradeReport :: UpgradeResult -> Text
```

`applyUpgrade` walks each `LegacyRef`'s `jsonPointer`, deletes the `"source"` or
`"targetSource"` key, inserts `"origin"` or `"targetOrigin"` encoded with the `ToJSON
ArtifactOrigin` instance from `seihou-core/src/Seihou/Manifest/Types.hs`, and finally sets
the top-level `"version"` to `currentManifestVersion`. Deduplicate entries by artifact name
for the report — the same module typically appears three times (in `modules`, in
`targetSource`, and in an instance) and the report should show it once.

Wire up the command. In `seihou-cli/src-exe/Seihou/CLI/Commands.hs`, add a `manifest`
subcommand group with an `upgrade` subcommand, following the shape of the existing
`registry` group (`grep -n "registry" seihou-cli/src-exe/Seihou/CLI/Commands.hs`). Its
options record needs `dryRun :: !Bool` for `--dry-run`. In `seihou-cli/src-exe/Main.hs`, add
the dispatch entry. Create a thin handler at
`seihou-cli/src-exe/Seihou/CLI/ManifestUpgradeCmd.hs` that reads
`.seihou/manifest.json` from the current directory, calls into
`Seihou.CLI.ManifestUpgrade`, prints `formatUpgradeReport`, and — unless `--dry-run` — writes
the result. The handler goes in `src-exe/` only because it imports the options record from
`Seihou.CLI.Commands`; keep all logic in the `src/` module so it stays testable.

Write atomically. `seihou-core/src/Seihou/Effect/ManifestStoreInterp.hs` already performs
atomic manifest writes (see `docs/plans/44-make-manifest-writes-atomic.md` for the
background); reuse `writeManifest` through
`Seihou.Effect.ManifestStore` if the shape allows it. If it does not — because this plan
writes a raw `Aeson.Value` rather than a typed `Manifest` — replicate the write-to-temp-file
then-rename approach and say so in the Decision Log. A better option, if it works: decode the
upgraded `Value` into a real `Manifest` with `manifestFromJSON` and write *that* through the
normal path, which additionally validates the upgrade produced something the current decoder
accepts. Prefer this; it turns the write into a correctness check.

Handle the already-upgraded case: when `readLegacyManifest` returns `Right Nothing`, print
`✓ .seihou/manifest.json is already at schema version 6; nothing to do.` and exit zero.

### Milestone 4 — point every other command at the upgrade, and gate on the guard

Plan 76 left the version guard in `instance FromJSON Manifest` producing a message
containing `run 'seihou manifest upgrade' to convert it`. Now that the command exists,
verify the wording matches the real command name exactly, and check that every command that
reads a manifest surfaces that message rather than swallowing it. Read each manifest-reading
site — `grep -rn "readManifest\|manifestFromJSON" --include='*.hs' seihou-cli seihou-core` —
and confirm the decode error reaches the user.

Then add the safety interlock that makes this plan a soft dependent of
`docs/plans/78-refuse-accidental-module-downgrades-and-origin-mismatches.md`. After
computing the upgraded manifest but before writing it, run
`checkAppliedArtifacts` and `blockingChecks` from
`seihou-cli/src/Seihou/CLI/ManifestGuard.hs` against the result. If any check blocks, print
`formatGuardRefusal` and refuse to write, explaining that upgrading now would produce a
manifest this machine cannot satisfy, and that the fix is to install or upgrade the named
artifacts first and re-run. Add a `--force` flag that writes anyway, for the case where the
developer intends to upgrade the manifest on a machine that does not have every artifact.

If plan 78 is not yet complete when you implement this milestone, skip the interlock, mark
the corresponding Progress entry as remaining with a note, and record in the Decision Log
that it must be added before the parent MasterPlan is marked complete.

### Milestone 5 — documentation

Add a section to `docs/user/getting-started.md` or a more specific document explaining what
to do when `seihou` reports an old manifest — read `ls docs/user/` and place it where the
existing structure suggests; `docs/user/migrations.md` covers module version migrations,
which is a different thing and should not absorb this. Add a CHANGELOG entry to
`docs/user/CHANGELOG.md` following the existing format. Check `seihou-cli/help/` for a topic
file that should mention the command (`ls seihou-cli/help/`); these are embedded into the
binary with `Data.FileEmbed` and shown by `seihou help <topic>`.

The broader "how teams share a manifest" guide belongs to
`docs/plans/80-document-and-end-to-end-verify-the-shared-manifest-workflow.md`; keep this
milestone focused on the upgrade command itself.


## Concrete Steps

All commands run from the repository root,
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

Confirm the two hard prerequisites are complete:

```bash
grep -n "data ArtifactOrigin" seihou-core/src/Seihou/Core/Types.hs
ls seihou-core/src/Seihou/Core/ArtifactRef.hs
grep -n "currentManifestVersion = " seihou-core/src/Seihou/Manifest/Types.hs
grep -n "seihou manifest upgrade" seihou-core/src/Seihou/Manifest/Types.hs
```

Expected: the type exists, the resolver module exists, the version constant reads `6`, and
the guard message referencing this command is present. If any is missing, this plan is
blocked on `docs/plans/76-record-portable-artifact-origins-in-the-manifest.md` or
`docs/plans/77-resolve-manifest-artifact-origins-to-local-directories.md`.

Check whether the soft dependency is available:

```bash
ls seihou-cli/src/Seihou/CLI/ManifestGuard.hs
```

If absent, implement Milestones 1 through 3 and 5, and leave Milestone 4's interlock for
later as described above.

Read how a nested subcommand group is built before adding one:

```bash
grep -n "registry" seihou-cli/src-exe/Seihou/CLI/Commands.hs
grep -n "Registry" seihou-cli/src-exe/Main.hs
```

Capture a real legacy manifest to use as a fixture. If you have a project generated by a
released seihou, copy its manifest; otherwise check out the commit before plan 76 landed,
build, and generate one:

```bash
git log --oneline -- seihou-core/src/Seihou/Manifest/Types.hs | head -20
```

After each milestone:

```bash
cabal build all && cabal test all
```

Before committing:

```bash
nix flake check
```

The scenario in Validation and Acceptance was run as written, with one
substitution: the hand-written `module.dhall` it describes does not evaluate to
a `Module` (it omits `exports`, `prompts`, `commands`, `dependencies`, and
`migrations`, all of which the decoder requires), so
`seihou-core/test/fixtures/prompted-optional` was copied into the fake install
root and renamed to `demo` instead. Transcripts:

```text
$ XDG_CONFIG_HOME=/tmp/seihou-legacy/home seihou status
[error] Error reading manifest: Error in $: this manifest uses schema version 5,
which records machine-specific absolute paths; run 'seihou manifest upgrade' to
convert it
exit status: 1

$ XDG_CONFIG_HOME=/tmp/seihou-legacy/home seihou manifest upgrade --dry-run
Reading .seihou/manifest.json (schema version 5)

  demo      /Users/someone-else/.config/seihou/installed/demo
         →  remote https://example.com/demo-modules.git

--dry-run: nothing was written.
exit status: 0
$ git status --porcelain
(empty)

$ XDG_CONFIG_HOME=/tmp/seihou-legacy/home seihou manifest upgrade
Reading .seihou/manifest.json (schema version 5)

  demo      /Users/someone-else/.config/seihou/installed/demo
         →  remote https://example.com/demo-modules.git

✓ Upgraded .seihou/manifest.json to schema version 6.
  Review the diff and commit it: git diff .seihou/manifest.json

$ grep -c 'someone-else' .seihou/manifest.json
0
$ XDG_CONFIG_HOME=/tmp/seihou-legacy/home seihou status
Seihou Status:

Applied modules:
  demo  v1.0.0    (applied 2026-07-01)
...
exit status: 0

$ XDG_CONFIG_HOME=/tmp/seihou-legacy/home seihou manifest upgrade
✓ .seihou/manifest.json is already at schema version 6; nothing to do.
exit: 0

$ XDG_CONFIG_HOME=/tmp/seihou-legacy/home2 seihou manifest upgrade --dry-run
Reading .seihou/manifest.json (schema version 5)

  demo      /Users/someone-else/.config/seihou/installed/demo
         →  local demo  (no upstream recorded)
            was installed from an upstream on the original machine, but no
            local copy is available here to recover the URL

--dry-run: nothing was written.
```

The interlock, exercised against the empty install root from the last scenario:

```text
$ XDG_CONFIG_HOME=/tmp/seihou-legacy/home2 seihou manifest upgrade
Reading .seihou/manifest.json (schema version 5)

  demo      /Users/someone-else/.config/seihou/installed/demo
         →  local demo  (no upstream recorded)
            was installed from an upstream on the original machine, but no
            local copy is available here to recover the URL

✗ Refusing to write .seihou/manifest.json.

  demo: recorded in the manifest but not installed on this machine

Upgrading now would record what this machine can see rather than what
the project uses: an artifact that is missing or stale here converts to
an origin seihou had to guess at, and that guess would be committed.

Install or upgrade the artifacts above and run this again, or re-run
with --force to accept the conversions exactly as shown.
exit: 1
$ git status --porcelain
(empty)

$ XDG_CONFIG_HOME=/tmp/seihou-legacy/home2 seihou manifest upgrade --force
… ✓ Upgraded .seihou/manifest.json to schema version 6.
exit: 0
$ git status --porcelain
 M .seihou/manifest.json
```

The written manifest records the origin as promised:

```json
{"modules":[{"appliedAt":"2026-07-01T12:00:00Z","name":"demo","origin":{"artifact":"demo","kind":"remote","repo":"demo-modules","url":"https://example.com/demo-modules.git"},"version":"1.0.0"}],"version":6}
```

Commit with all three trailers:

```text
feat(manifest): add 'seihou manifest upgrade' for legacy manifests

Decode schema-5-and-earlier manifests, infer a portable origin for each
recorded absolute path, print a reviewable report of every conversion, and
rewrite the file atomically. --dry-run shows the report without writing.

MasterPlan: docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md
ExecPlan: docs/plans/79-upgrade-legacy-absolute-path-manifests-in-place.md
Intention: intention_01kyk6fnbyegxss8fqnf3j03tf
```


## Validation and Acceptance

Unit acceptance is `cabal test all` green, with the golden-file test proving no data is lost
and the inference tests covering every outcome.

Behavioral acceptance uses a real legacy manifest and a simulated second machine.
`XDG_CONFIG_HOME` redirects `getXdgDirectory XdgConfig`, and therefore both
`~/.config/seihou/modules/` and `~/.config/seihou/installed/`.

Set up:

```bash
rm -rf /tmp/seihou-legacy
mkdir -p /tmp/seihou-legacy/project/.seihou
mkdir -p /tmp/seihou-legacy/home/seihou/installed/demo
cd /tmp/seihou-legacy/project
git init
```

Put a valid `module.dhall` in `/tmp/seihou-legacy/home/seihou/installed/demo/` — copy the
schema import line and required fields from `docs/user/module-authoring.md`, which tracks the
pinned schema URL — declaring `version = "1.0.0"`, plus a `.seihou-origin.json`:

```json
{
  "sourceUrl": "https://example.com/demo-modules.git",
  "repoName": "demo-modules",
  "installedAt": "2026-07-01T00:00:00Z",
  "version": "1.0.0",
  "tags": []
}
```

Write a legacy manifest by hand at `/tmp/seihou-legacy/project/.seihou/manifest.json`,
recording a path from a *different* machine:

```json
{
  "version": 5,
  "generatedAt": "2026-07-01T12:00:00Z",
  "modules": [
    {
      "name": "demo",
      "source": "/Users/someone-else/.config/seihou/installed/demo",
      "version": "1.0.0",
      "appliedAt": "2026-07-01T12:00:00Z"
    }
  ],
  "variables": {},
  "files": {},
  "applications": [],
  "blueprintMigrations": []
}
```

Confirm ordinary commands refuse with the pointer to the upgrade:

```bash
cd /tmp/seihou-legacy/project
XDG_CONFIG_HOME=/tmp/seihou-legacy/home cabal run seihou -- status
echo "exit status: $?"
```

Expected: a message containing
`this manifest uses schema version 5` and `seihou manifest upgrade`, non-zero exit.

Now dry-run the upgrade:

```bash
XDG_CONFIG_HOME=/tmp/seihou-legacy/home cabal run seihou -- manifest upgrade --dry-run
git status --porcelain
```

Expected: the report showing
`demo  /Users/someone-else/.config/seihou/installed/demo → remote https://example.com/demo-modules.git`,
and **empty** `git status --porcelain` — the dry run wrote nothing.

Then upgrade for real:

```bash
XDG_CONFIG_HOME=/tmp/seihou-legacy/home cabal run seihou -- manifest upgrade
grep -n '"origin"' .seihou/manifest.json
grep -c 'someone-else' .seihou/manifest.json
XDG_CONFIG_HOME=/tmp/seihou-legacy/home cabal run seihou -- status
echo "exit status: $?"
```

Expected: the manifest now contains
`"origin": {"kind":"remote","url":"https://example.com/demo-modules.git","artifact":"demo","repo":"demo-modules"}`,
`grep -c 'someone-else'` prints `0`, and `seihou status` now succeeds with exit status `0`.

Confirm idempotence:

```bash
XDG_CONFIG_HOME=/tmp/seihou-legacy/home cabal run seihou -- manifest upgrade
echo "exit status: $?"
```

Expected: `✓ .seihou/manifest.json is already at schema version 6; nothing to do.` and exit
status `0`.

Confirm the unverifiable fallback by repeating the whole scenario with an empty install root:

```bash
rm -rf /tmp/seihou-legacy/home2 && mkdir -p /tmp/seihou-legacy/home2/seihou/installed
git checkout -- .seihou/manifest.json 2>/dev/null || true
XDG_CONFIG_HOME=/tmp/seihou-legacy/home2 cabal run seihou -- manifest upgrade --dry-run
```

Expected: the report shows the entry converting to `local demo  (no upstream recorded)` with
the extra note that it was installed from an upstream on the original machine.

Paste the real transcripts into Concrete Steps as evidence when you run them.


## Idempotence and Recovery

The upgrade command is idempotent by construction: `readLegacyManifest` returns
`Right Nothing` for an already-upgraded document, and the handler reports "nothing to do"
and exits zero. Running it twice is safe and is explicitly tested above.

The command mutates a file that is checked into git, which is the recovery path: if a
developer dislikes the result, `git checkout -- .seihou/manifest.json` restores the previous
version. Say so in the printed report — the last line of a successful upgrade should invite
review with `git diff .seihou/manifest.json`.

The write must be atomic so an interrupted run cannot leave a truncated manifest. Prefer
routing the write through the existing `writeManifest` in
`seihou-core/src/Seihou/Effect/ManifestStoreInterp.hs`, which already writes atomically; if
that is impossible because this plan holds an `Aeson.Value` rather than a typed `Manifest`,
write to a temporary file in the same directory and rename over the target, and record the
choice in the Decision Log.

Consider also refusing to upgrade a manifest with uncommitted changes, or at least warning.
`seihou-cli/src/Seihou/CLI/Git.hs` already has helpers for interrogating git state
(`isGitRepo`, `gitDiffCached`, `gitCheckIgnore`). A warning is sufficient; a refusal would
be unhelpful in a repository where the manifest is legitimately dirty. Decide and record.

All scratch state lives under `/tmp/seihou-legacy`; `rm -rf /tmp/seihou-legacy` resets the
validation entirely, and every invocation sets `XDG_CONFIG_HOME` so the real
`~/.config/seihou/` is never touched.


## Interfaces and Dependencies

No new package dependencies. `seihou-cli-internal` already depends on `aeson`,
`bytestring`, `containers`, `directory`, `filepath`, `generic-lens`, `lens`, `text`, and
`seihou-core`. Working directly on `Aeson.Value` needs
`Data.Aeson.KeyMap` and `Data.Aeson.Key`, both of which ship with `aeson`.

At the end of Milestone 3, these must exist in
`seihou-cli/src/Seihou/CLI/ManifestUpgrade.hs`:

```haskell
data LegacyRef = LegacyRef
  { jsonPointer :: ![Text],
    artifactName :: !Text,
    legacyPath :: !FilePath,
    recordedVersion :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)

data LegacyManifest = LegacyManifest
  { schemaVersion :: !Int,
    document :: !Aeson.Value,
    refs :: ![LegacyRef]
  }
  deriving stock (Eq, Show, Generic)

data InferenceOutcome
  = InferredFromLocalInstall !ArtifactOrigin
  | InferredFromProjectPath !ArtifactOrigin
  | InferredAsUnverifiable !ArtifactOrigin
  deriving stock (Eq, Show, Generic)

readLegacyManifest :: LBS.ByteString -> Either String (Maybe LegacyManifest)
inferOriginFromLegacyPath :: FilePath -> [FilePath] -> LegacyRef -> IO InferenceOutcome
inferredOrigin :: InferenceOutcome -> ArtifactOrigin
applyUpgrade :: LegacyManifest -> [(LegacyRef, InferenceOutcome)] -> UpgradeResult
formatUpgradeReport :: UpgradeResult -> Text
```

This plan consumes, and must not change: the `ArtifactOrigin` type and its `ToJSON`
instance, `currentManifestVersion`, `manifestFromJSON`, `detectArtifactOrigin`, and
`readOriginInfo` — all owned by
`docs/plans/76-record-portable-artifact-origins-in-the-manifest.md`;
`resolveArtifactOrigin` and `renderArtifactRefError` from
`seihou-core/src/Seihou/Core/ArtifactRef.hs`, owned by
`docs/plans/77-resolve-manifest-artifact-origins-to-local-directories.md`; and
`checkAppliedArtifacts`, `blockingChecks`, and `formatGuardRefusal` from
`seihou-cli/src/Seihou/CLI/ManifestGuard.hs`, owned by
`docs/plans/78-refuse-accidental-module-downgrades-and-origin-mismatches.md`. Changing any of
those requires a decision recorded in the parent MasterPlan's Decision Log at
`docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md`.

`docs/plans/80-document-and-end-to-end-verify-the-shared-manifest-workflow.md` consumes the
`seihou manifest upgrade` command and its report format in its end-to-end test.
