---
id: 77
slug: resolve-manifest-artifact-origins-to-local-directories
title: "Resolve manifest artifact origins to local directories"
kind: exec-plan
created_at: 2026-07-28T01:48:18Z
intention: "intention_01kyk6fnbyegxss8fqnf3j03tf"
master_plan: "docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md"
---

# Resolve manifest artifact origins to local directories

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Seihou records what it generated into `.seihou/manifest.json`, a JSON file inside the
project that teams check into git. Several seihou commands need to go back to a module's
source directory afterwards — `seihou migrate` re-reads the module to plan a version
migration, `seihou upgrade` re-reads it to compare versions, `seihou update` re-reads it to
regenerate. Today those commands take a filesystem path straight out of the manifest and
hand it to the Dhall evaluator.

That path was written by whichever machine last ran seihou. On a teammate's machine it does
not exist. The symptom is a confusing failure from deep inside module loading — for example
`seihou migrate haskell-base` reporting `module.dhall not found at installed dir` and naming
a directory under someone else's home directory — or, worse, a silent fallback that operates
on a different module than the manifest describes.

`docs/plans/76-record-portable-artifact-origins-in-the-manifest.md` replaced those paths in
the *serialized* manifest with a portable `ArtifactOrigin`. This plan makes the commands
actually use it. After this plan, every command that needs an artifact's directory asks a
single resolver to find it on *this* machine, using the same search paths that ordinary
module discovery uses. When it cannot be found, the command stops with a message that names
the artifact, names the git URL it came from, lists the directories that were searched, and
gives the exact command to fix it.

You can see it working by taking a manifest written on one machine and running a command on
another. Concretely, in a project whose manifest records `haskell-base` as coming from
`https://github.com/shinzui/seihou-modules.git`, with that module *not* installed locally:

```bash
seihou migrate haskell-base
```

Before this plan, that prints a path from another developer's home directory. After this
plan it prints:

```text
✗ Module 'haskell-base' is recorded in .seihou/manifest.json but is not
  installed on this machine.

  Recorded origin: https://github.com/shinzui/seihou-modules.git

  Searched:
    /home/you/project/.seihou/modules/haskell-base
    /home/you/.config/seihou/modules/haskell-base
    /home/you/.config/seihou/installed/haskell-base

  Install it with:
    seihou install https://github.com/shinzui/seihou-modules.git
```

This plan does not compare versions or refuse downgrades — that is
`docs/plans/78-refuse-accidental-module-downgrades-and-origin-mismatches.md`. It does not
handle manifests written in the old format — that is
`docs/plans/79-upgrade-legacy-absolute-path-manifests-in-place.md`.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] Milestone 1: `Seihou.Core.ArtifactRef` module with `resolveArtifactOrigin` and `ArtifactRefError`
- [ ] Milestone 1: `renderArtifactRefError` produces the user-facing message
- [ ] Milestone 1: Unit tests covering resolution success and every failure shape
- [ ] Milestone 2: `seihou migrate` resolves through the resolver
- [ ] Milestone 2: `seihou upgrade` resolves through the resolver
- [ ] Milestone 2: `seihou remove` resolves through the resolver (or confirmed not to need it)
- [ ] Milestone 3: `seihou update` resolves through the resolver
- [ ] Milestone 3: `seihou status` resolves through the resolver (or confirmed not to need it)
- [ ] Milestone 3: `seihou run`'s post-run migration path resolves through the resolver
- [ ] Milestone 4: `source` and `targetSource` fields deleted from the three manifest records
- [ ] Milestone 4: Full test suite green with no reference to a manifest-recorded path


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Resolution consults the same three search paths as ordinary module discovery
  rather than jumping straight to `~/.config/seihou/installed/<name>` for a `RemoteOrigin`.
  Rationale: A developer may deliberately shadow an installed module with a project-local
  copy under `.seihou/modules/<name>` while working on it. Bypassing the search order would
  make the manifest's recorded origin override that deliberate shadowing in a way that is
  invisible and surprising. Resolution therefore searches in the normal order and *then*
  reports what it found, leaving the question of whether the found artifact matches the
  recorded origin to
  `docs/plans/78-refuse-accidental-module-downgrades-and-origin-mismatches.md`.
  Date: 2026-07-28

- Decision: Resolution failure is a typed error rendered at the call site, not an exception
  and not a bare `Maybe`.
  Rationale: Every call site needs a different surrounding context — `seihou migrate` says
  "cannot plan a migration", `seihou update` says "cannot regenerate" — but the body of the
  message (what was searched, what to install) must be identical everywhere, because
  `docs/plans/80-document-and-end-to-end-verify-the-shared-manifest-workflow.md` asserts on
  its exact wording. A typed error with one shared renderer gives both.
  Date: 2026-07-28


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

(To be filled during and after implementation.)


## Context and Orientation

This section assumes no prior knowledge of the repository.

**The repository layout.** `seihou` is a Haskell project built with Cabal, targeting GHC
9.12.2 and the `GHC2024` language edition. `cabal.project` defines three packages:
`seihou-core` (types, Dhall loading, generation engine, manifest handling), `seihou-cli`
(a library at `seihou-cli/src/` called `seihou-cli-internal` plus an executable at
`seihou-cli/src-exe/` called `seihou`), and `seihou-okf-extension`. `CLAUDE.md` at the
repository root explains that new CLI code belongs in `seihou-cli/src/` unless it needs
`Options.Applicative`, `Data.FileEmbed`, `GitHash`, or `Paths_seihou_cli`, or transitively
imports a module that does — most commonly `Seihou.CLI.Commands`, which is trapped by
`Options.Applicative`. That convention is enforced by `nix/check-cli-module-placement.sh`,
which runs in `nix flake check` and the pre-commit hook.

**Record conventions**, described in `CLAUDE.md` and in
`docs/dev/architecture/overview.md` under "Record Conventions", and enforced by
`nix/check-record-conventions.sh`: every `data` record field carries `!`; `newtype` fields
are exempt because GHC rejects the annotation there; no type-abbreviation prefixes on field
names; an explicit `deriving stock (...)` clause including `Generic`; fields read and
written through `generic-lens` overloaded labels (`x ^. #field`, `x & #field .~ v`), never
record-dot syntax and never record *update* syntax. Record construction and record patterns
are fine. Every module using a `#label` adds `import Data.Generics.Labels ()` itself; that
import must never go in `Seihou.Prelude` because the instance is an orphan.

**What this plan builds on.**
`docs/plans/76-record-portable-artifact-origins-in-the-manifest.md` must be complete before
this plan starts. It added to `seihou-core/src/Seihou/Core/Types.hs`:

```haskell
data ArtifactOrigin
  = RemoteOrigin { originUrl :: !Text, artifactName :: !Text, repoName :: !(Maybe Text) }
  | ProjectOrigin { relativePath :: !FilePath }
  | LocalOrigin { artifactName :: !Text }
  deriving stock (Eq, Ord, Show, Generic)
```

`RemoteOrigin` means the artifact was installed by `seihou install` from a git URL into
`~/.config/seihou/installed/<name>/`, with the URL recorded in `.seihou-origin.json` beside
it. `ProjectOrigin` means the artifact lives inside the project under
`.seihou/modules/<name>`, and the path is stored relative to the project root with forward
slashes. `LocalOrigin` means the artifact was found in the developer's personal
`~/.config/seihou/modules/` directory, which carries no provenance metadata, so only the
name is knowable.

Plan 76 also added `origin :: !ArtifactOrigin` to `AppliedModule` and
`AppliedInstanceState`, `targetOrigin :: !ArtifactOrigin` to `AppliedComposition`, bumped
`currentManifestVersion` in `seihou-core/src/Seihou/Manifest/Types.hs` from 5 to 6, stopped
serializing the old `source` and `targetSource` absolute paths, and moved the
`.seihou-origin.json` reader down into `seihou-core/src/Seihou/Core/ArtifactOriginDetect.hs`:

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

The `source` and `targetSource` fields still exist in the Haskell records after plan 76,
retained deliberately so plan 76 did not have to rewire every consumer. Deleting them is
Milestone 4 of *this* plan.

**How modules are discovered today.** `seihou-core/src/Seihou/Core/Module.hs` defines the
search paths at line 152:

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

The same file defines `discoverModule`, `discoverBlueprint`, and `discoverAgentPrompt`, all
of which walk that list looking for `<dir>/<name>/<something>.dhall` and return the
containing directory or a `ModuleNotFound name searchedDirs` error. `ModuleLoadError` is
defined at `seihou-core/src/Seihou/Core/Types.hs:419`. Because `getXdgDirectory XdgConfig`
honours the `XDG_CONFIG_HOME` environment variable, setting that variable redirects both the
personal-module directory and the install cache — which is how the validation scenario below
simulates a second developer without a second machine.

**The consumers that read a manifest-recorded path.** Each one is a place where this plan
replaces a field read with a resolver call.

`seihou-cli/src/Seihou/CLI/Migrate.hs:187` — `handleMigrate` looks up the applied module and
passes its recorded path into `runMigrate`:

```haskell
result <- runMigrate opts manifest (applied ^. #source)
```

`runMigrate` at line 253 dispatches to `runMigrateLocal` or `runMigrateWithFetch`, both of
which treat that path as the "installed-module directory" holding `module.dhall`.
`runMigrateWithFetch` at line 329 additionally reads `.seihou-origin.json` from it to decide
whether to clone the upstream repository, and falls back to the local copy when the file is
missing.

`seihou-cli/src-exe/Seihou/CLI/Upgrade.hs:301` — builds `am ^. #source </> "module.dhall"`
to evaluate the installed module, and at line 309 passes `am ^. #source` into
`runOnePostUpgradeMigration`.

`seihou-cli/src-exe/Seihou/CLI/Run.hs:746` — the post-run migration path calls
`runMigrate opts manifest (am ^. #source)`.

`seihou-cli/src/Seihou/CLI/Update.hs:589` — `versionEvidence`'s `compareArtifact` helper
hashes the previously applied artifact directory to detect same-version content changes,
using `old ^. #source` and `previous ^. #targetSource`. Line 506's `restoreLegacyVersion`
copies `applied ^. #source` forward into a rebuilt `AppliedInstanceState`.

`seihou-cli/src-exe/Seihou/CLI/Remove.hs` — `findAppliedModule` at line 172 locates the
`AppliedModule`. Removal is driven by the `Removal` steps recorded *in the manifest* rather
than by re-reading the module, so it may not dereference the path at all. Confirm with
`grep -n "source" seihou-cli/src-exe/Seihou/CLI/Remove.hs` before assuming either way.

`seihou-cli/src-exe/Seihou/CLI/Status.hs` and `seihou-cli/src-exe/Seihou/CLI/Outdated.hs` —
these read `.seihou-origin.json` from installed directories to report available updates.
Confirm their exact use with
`grep -n "source\|readOriginInfo" seihou-cli/src-exe/Seihou/CLI/Status.hs seihou-cli/src-exe/Seihou/CLI/Outdated.hs`.

`seihou-cli/src-exe/Seihou/CLI/AgentRun.hs` — records origins (plan 76 changed it) but may
not re-read them; confirm with `grep -n "#source" seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`.

**Architecture Decision Records.** Plan 76 creates `docs/adr/` with two records. Read both
before starting. The first,
`docs/adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md`, records that
`.seihou/manifest.json` is a committed project artifact and must never contain
machine-specific values — that is the constraint this plan enforces at read time. The
second, `docs/adr/0002-artifact-identity-is-origin-url-plus-name.md`, records that identity
is the git URL plus the artifact name, with bare-name and content-hash alternatives
rejected — that explains why resolution is keyed the way it is. Adjust the filenames to
whatever plan 76 actually allocated, following `agents/skills/exec-plan/ADR.md`. If
`docs/adr/` does not exist when you start, plan 76 is not complete and this plan is blocked.

**Build and test commands.** From the repository root:

```bash
cabal build all
cabal test all
nix flake check
```

`Justfile` wraps the first two as `just build` and `just test`, and the third as
`just check`.


## Plan of Work

Four milestones. Each leaves the tree compiling and the suite green.

### Milestone 1 — the resolver

Create `seihou-core/src/Seihou/Core/ArtifactRef.hs` and add `Seihou.Core.ArtifactRef` to the
`exposed-modules` list in the `library` stanza of `seihou-core/seihou-core.cabal`, keeping
the list alphabetically sorted (it belongs immediately after
`Seihou.Core.ArtifactOriginDetect`).

The module exports a resolution function, an error type, and a renderer:

```haskell
-- | Why an origin recorded in the manifest could not be turned into a
-- directory on this machine.
data ArtifactRefError
  = -- | Nothing named by the origin exists in any search path. Carries the
    -- origin and the exact directories that were probed, in order.
    ArtifactNotFoundLocally !ArtifactOrigin ![FilePath]
  | -- | A 'ProjectOrigin' pointed at a path inside the project that does
    -- not exist. Carries the origin and the absolute path that was tried.
    ProjectArtifactMissing !ArtifactOrigin !FilePath
  deriving stock (Eq, Show, Generic)

-- | Turn a recorded origin into the absolute directory on this machine
-- that holds the artifact's definition file.
--
-- @projectRoot@ is the absolute directory containing @.seihou@.
-- @searchPaths@ is normally 'Seihou.Core.Module.defaultSearchPaths'; it is
-- a parameter so tests can supply temporary directories.
-- @definitionFile@ is the file that must be present for a directory to
-- count as the artifact — @"module.dhall"@ for modules,
-- @"recipe.dhall"@ for recipes, @"blueprint.dhall"@ for blueprints.
resolveArtifactOrigin ::
  FilePath ->
  [FilePath] ->
  FilePath ->
  ArtifactOrigin ->
  IO (Either ArtifactRefError FilePath)

-- | Render a resolution failure as the multi-line message the user sees.
renderArtifactRefError :: ArtifactRefError -> Text
```

Resolution behaviour, precisely:

For a `ProjectOrigin path`, the candidate is `projectRoot </> path`, converting the stored
forward-slash path back to native separators first. If `<candidate>/<definitionFile>`
exists, return the candidate; otherwise return `ProjectArtifactMissing`. Do **not** fall
through to the search paths — a project origin that is missing means the repository is
incomplete, and silently substituting a globally installed module of the same name would be
exactly the kind of invisible substitution this initiative exists to eliminate.

For a `RemoteOrigin _ artifact _` or a `LocalOrigin artifact`, walk `searchPaths` in order
and return the first `<dir>/<artifact>` whose `<definitionFile>` exists. If none matches,
return `ArtifactNotFoundLocally` carrying every `<dir>/<artifact>` that was probed, in
order, so the message can list them.

`renderArtifactRefError` produces the message shown in Purpose / Big Picture. For an
`ArtifactNotFoundLocally` on a `RemoteOrigin`, include the recorded URL and the
`seihou install <url>` remedy. For a `LocalOrigin` there is no URL and no install command,
so say instead that the artifact has no recorded upstream and must be placed in one of the
listed directories by hand. For `ProjectArtifactMissing`, say the project is missing a file
that should be committed, and name the path relative to the project root.

Test in a new `seihou-core/test/Seihou/Core/ArtifactRefSpec.hs`, registered in the
test-suite `other-modules` of `seihou-core/seihou-core.cabal` and in
`seihou-core/test/Main.hs` following the existing entries' pattern (each spec module
exports `tests :: IO TestTree` built with `Test.Tasty.Hspec.testSpec`). Build temporary
directory trees in the test — `seihou-core/test/Seihou/Core/ScaffoldSpec.hs` and
`seihou-core/test/Seihou/Core/ModuleSpec.hs` show the established approach in this
repository. Cover: a `RemoteOrigin` resolving from the third search path; a `RemoteOrigin`
shadowed by a project-local directory in the first search path, asserting the first wins; a
`LocalOrigin` resolving from the second search path; a missing artifact returning
`ArtifactNotFoundLocally` with all three probed paths in order; a `ProjectOrigin` resolving
relative to the project root; and a `ProjectOrigin` whose directory is absent returning
`ProjectArtifactMissing` rather than falling through. Also assert that
`renderArtifactRefError` on the not-found case contains the recorded URL, all three probed
directories, and the literal string `seihou install`.

### Milestone 2 — rewire migrate, upgrade, and remove

These are the commands most visibly broken today, and they share a shape: take an
`AppliedModule` out of the manifest, get its directory, evaluate `module.dhall`.

In `seihou-cli/src/Seihou/CLI/Migrate.hs`, `handleMigrate` at line 187 currently does:

```haskell
result <- runMigrate opts manifest (applied ^. #source)
```

Replace it with a resolution step that dies with the rendered error on failure. The file
already has a `die` helper used for the other `MigrateError` cases; extend `MigrateError`
(find it with `grep -n "data MigrateError" -A 20 seihou-cli/src/Seihou/CLI/Migrate.hs`) with
a constructor carrying an `ArtifactRefError`, and extend the error renderer alongside it so
the new case prints `renderArtifactRefError`. For the project root: `handleMigrate` already
assumes the current working directory is the project root, since it builds the manifest path
as `".seihou" </> "manifest.json"`; call `System.Directory.getCurrentDirectory` for the
absolute form and `Seihou.Core.Module.defaultSearchPaths` for the search paths.

Leave `runMigrate`'s own signature alone — it takes a directory and should keep taking a
directory. The change belongs at the boundary where a manifest field becomes a path.

In `seihou-cli/src-exe/Seihou/CLI/Upgrade.hs`, line 301 builds
`am ^. #source </> "module.dhall"` and line 309 passes `am ^. #source` onward. Resolve
`am ^. #origin` once at the top of that function and thread the resolved directory through
both uses, reporting failures through the module's existing error path.

In `seihou-cli/src-exe/Seihou/CLI/Remove.hs`, first confirm whether removal dereferences the
path at all. If it does, resolve; if it does not, mark the Progress entry as "confirmed not
to need it" and record the finding in Surprises & Discoveries with the grep output as
evidence.

Acceptance for this milestone is behavioral and is described in Validation and Acceptance
below: a manifest referencing an uninstalled module makes `seihou migrate` print the new
message and exit non-zero.

### Milestone 3 — rewire update, status, and the run post-migration path

`seihou-cli/src/Seihou/CLI/Update.hs` is the largest consumer, with two distinct uses.

`versionEvidence`'s `compareArtifact` at line 589 hashes the *previously applied* artifact
directory to detect whether a same-version artifact's content changed. It currently takes
`oldSource` and calls `hashArtifactDirectory oldSource` inside a `try @SomeException`,
treating any failure as "changed". Resolve `old ^. #origin` instead of reading
`old ^. #source`; on a resolution error, keep the existing conservative behaviour of
treating the artifact as changed rather than aborting the update, because this code path
produces an advisory warning, not a correctness gate. Add a comment saying so, and note that
`docs/plans/78-refuse-accidental-module-downgrades-and-origin-mismatches.md` is what aborts.

`restoreLegacyVersion` at line 506 rebuilds an `AppliedInstanceState` carrying forward
`applied ^. #source`. Carry forward `applied ^. #origin` instead. Once Milestone 4 deletes
the `source` field this becomes the only remaining form anyway.

`seihou-cli/src-exe/Seihou/CLI/Run.hs:746` calls `runMigrate opts manifest (am ^. #source)`
in the post-run migration path. Apply the same resolution as in Milestone 2's `Migrate.hs`
change; `handleRun` already has the project root available.

`seihou-cli/src-exe/Seihou/CLI/Status.hs` and `seihou-cli/src-exe/Seihou/CLI/Outdated.hs`
read `.seihou-origin.json` to report available updates. Where they locate an installed
directory by name, they can now locate it by resolving the manifest's recorded origin, which
additionally lets `seihou status` say "recorded origin not installed" instead of silently
omitting the row. Make that change only if it is a small edit; if these commands turn out to
enumerate installed modules independently of the manifest, leave them alone, mark the
Progress entry as "confirmed not to need it", and say so in Surprises & Discoveries.

### Milestone 4 — delete the retained absolute-path fields

With every consumer rewired, delete `source` from `AppliedModule` and
`AppliedInstanceState` and `targetSource` from `AppliedComposition`, all in
`seihou-core/src/Seihou/Core/Types.hs`. Delete the now-dead `FilePath` components that plan
76 left in `buildAppliedComposition`'s tuple parameters in
`seihou-core/src/Seihou/Core/Application.hs`, so its signature becomes:

```haskell
buildAppliedComposition ::
  AppliedTarget ->
  ArtifactOrigin ->
  Maybe Text ->
  [ModuleName] ->
  Maybe Text ->
  Maybe Text ->
  [(ModuleInstance, Module, ArtifactOrigin)] ->
  Map ModuleInstance (Map VarName ResolvedVar) ->
  UTCTime ->
  AppliedComposition
```

The compiler will point at every construction site. Fix them all, including test fixtures
under `seihou-core/test/` and `seihou-cli/test/`. Do **not** bump `currentManifestVersion` —
the *serialized* form did not change in this milestone, only the in-memory records, and plan
76 already made 6 the version that has no `source` key.

Then prove the field is really gone from every path:

```bash
grep -rn '#source\b' --include='*.hs' seihou-core seihou-cli
```

Some hits are unrelated and must remain: `ResolvedVar.source` is a `VarSource` describing
where a variable's *value* came from (see `seihou-core/src/Seihou/Core/Types.hs:430`), and
`seihou-cli/src/Seihou/CLI/AgentConfig.hs` has its own `source` field for configuration
precedence. Neither is a filesystem path. Confirm every remaining hit is one of those before
declaring the milestone done.


## Concrete Steps

All commands run from the repository root,
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

Confirm plan 76 is complete before starting:

```bash
ls docs/adr/
grep -n "currentManifestVersion = " seihou-core/src/Seihou/Manifest/Types.hs
grep -n "data ArtifactOrigin" seihou-core/src/Seihou/Core/Types.hs
```

Expected: `docs/adr/` exists with at least two records, the version constant reads
`currentManifestVersion = 6`, and the type exists. If any of those is missing, stop — this
plan is blocked on `docs/plans/76-record-portable-artifact-origins-in-the-manifest.md`.

Enumerate the consumers you must rewire, and re-check the list as you go:

```bash
grep -rn '#source\b\|#targetSource\b' --include='*.hs' seihou-core/src seihou-cli/src seihou-cli/src-exe
```

After each milestone:

```bash
cabal build all && cabal test all
```

Before committing:

```bash
nix flake check
```

Commit at the end of each milestone, with all three trailers:

```text
feat(manifest): resolve recorded artifact origins locally in seihou migrate

Replace the manifest-recorded absolute path with a call into
Seihou.Core.ArtifactRef, so a manifest written on another machine resolves
against this machine's search paths and reports an actionable message when
the module is not installed.

MasterPlan: docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md
ExecPlan: docs/plans/77-resolve-manifest-artifact-origins-to-local-directories.md
Intention: intention_01kyk6fnbyegxss8fqnf3j03tf
```


## Validation and Acceptance

Unit acceptance is `cabal test all` green with the new `ArtifactRefSpec` covering all six
resolution cases named in Milestone 1.

Behavioral acceptance simulates the two-machine scenario without needing two machines, by
pointing seihou at a fake home directory. The `XDG_CONFIG_HOME` environment variable
controls where `getXdgDirectory XdgConfig "seihou"` looks, so setting it redirects both
`~/.config/seihou/modules/` and `~/.config/seihou/installed/`.

Set up a scratch project and two fake install roots:

```bash
rm -rf /tmp/seihou-two-dev
mkdir -p /tmp/seihou-two-dev/project
mkdir -p /tmp/seihou-two-dev/home-a/seihou/installed
mkdir -p /tmp/seihou-two-dev/home-b/seihou/installed
cd /tmp/seihou-two-dev/project
git init
```

Create a module directory at `/tmp/seihou-two-dev/home-a/seihou/installed/demo/` containing
a valid `module.dhall` — copy the schema import line and required fields from
`docs/user/module-authoring.md`, which is kept current with the pinned schema URL — plus a
`.seihou-origin.json`:

```json
{
  "sourceUrl": "https://example.com/demo-modules.git",
  "repoName": "demo-modules",
  "installedAt": "2026-07-28T00:00:00Z",
  "version": "1.0.0",
  "tags": []
}
```

Generate as developer A:

```bash
cd /tmp/seihou-two-dev/project
XDG_CONFIG_HOME=/tmp/seihou-two-dev/home-a cabal run seihou -- run demo
grep -n '"origin"' .seihou/manifest.json
```

Expected: the manifest records
`{"kind":"remote","url":"https://example.com/demo-modules.git","artifact":"demo","repo":"demo-modules"}`
and contains no path under `/tmp/seihou-two-dev/home-a`.

Now act as developer B, whose install root is empty:

```bash
cd /tmp/seihou-two-dev/project
XDG_CONFIG_HOME=/tmp/seihou-two-dev/home-b cabal run seihou -- migrate demo
```

Expected before this plan: a message naming a directory under `home-a`, or a raw
`module.dhall not found at installed dir` failure. Expected after this plan: the message
shown in Purpose / Big Picture, listing the three directories under `home-b` that were
probed, naming `https://example.com/demo-modules.git`, and ending with the `seihou install`
remedy. Exit status is non-zero — check with `echo $?`.

Then give developer B the module and confirm the command proceeds:

```bash
cp -r /tmp/seihou-two-dev/home-a/seihou/installed/demo /tmp/seihou-two-dev/home-b/seihou/installed/demo
XDG_CONFIG_HOME=/tmp/seihou-two-dev/home-b cabal run seihou -- migrate demo
```

Expected: `✓ demo is already at version 1.0.0; nothing to do.`

Paste the real transcript into the Concrete Steps section as evidence when you run it.

The automated form of this scenario belongs to
`docs/plans/80-document-and-end-to-end-verify-the-shared-manifest-workflow.md`; running it
by hand here is what makes this plan verifiable on its own.


## Idempotence and Recovery

All source edits are revertible with git. The scratch project under `/tmp/seihou-two-dev` is
disposable; `rm -rf /tmp/seihou-two-dev` resets the behavioral check completely, and nothing
in the validation steps touches the real `~/.config/seihou/` because every invocation sets
`XDG_CONFIG_HOME`.

Milestone 4 is the only step that feels irreversible, because it deletes fields other code
might still reference. Do it last, and only after
`grep -rn '#source\b' --include='*.hs' seihou-core seihou-cli` shows nothing but the
unrelated `VarSource` and `AgentConfig` hits. If the deletion breaks something you did not
anticipate, the safe intermediate state is to keep the fields but leave them unread — the
serialized form is already correct after plan 76, so portability does not depend on
Milestone 4. Record that in the Decision Log if you take that route, and split the Progress
entry into a done part and a remaining part.

Do not run a locally built `seihou` against a project you care about while
`docs/plans/79-upgrade-legacy-absolute-path-manifests-in-place.md` is still outstanding,
because manifests written before plan 76 are rejected by the schema-version guard. Use
scratch projects. If a real project's manifest is affected,
`git checkout -- .seihou/manifest.json` restores it — which is exactly why the manifest
being checked in matters.


## Interfaces and Dependencies

No new package dependencies. `seihou-core` already depends on `directory`, `filepath`,
`text`, `containers`, `generic-lens`, and `lens`.

At the end of Milestone 1, these must exist in `seihou-core/src/Seihou/Core/ArtifactRef.hs`:

```haskell
data ArtifactRefError
  = ArtifactNotFoundLocally !ArtifactOrigin ![FilePath]
  | ProjectArtifactMissing !ArtifactOrigin !FilePath
  deriving stock (Eq, Show, Generic)

resolveArtifactOrigin ::
  FilePath ->
  [FilePath] ->
  FilePath ->
  ArtifactOrigin ->
  IO (Either ArtifactRefError FilePath)

renderArtifactRefError :: ArtifactRefError -> Text
```

This plan owns those signatures. Two downstream plans consume them:
`docs/plans/78-refuse-accidental-module-downgrades-and-origin-mismatches.md` calls
`resolveArtifactOrigin` to locate the local copy it compares against and embeds
`renderArtifactRefError` output inside its own guard messages;
`docs/plans/79-upgrade-legacy-absolute-path-manifests-in-place.md` uses the same resolver to
work out which artifact a legacy absolute path referred to. Changing either signature
requires a decision recorded in the parent MasterPlan's Decision Log at
`docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md`.

At the end of Milestone 4, `AppliedModule`, `AppliedInstanceState`, and `AppliedComposition`
in `seihou-core/src/Seihou/Core/Types.hs` carry no `FilePath` field describing where an
artifact lives, and `buildAppliedComposition` in
`seihou-core/src/Seihou/Core/Application.hs` takes `ArtifactOrigin` values rather than paths.
