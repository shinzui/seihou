---
id: 78
slug: refuse-accidental-module-downgrades-and-origin-mismatches
title: "Refuse accidental module downgrades and origin mismatches"
kind: exec-plan
created_at: 2026-07-28T01:48:18Z
intention: "intention_01kyk6fnbyegxss8fqnf3j03tf"
master_plan: "docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md"
---

# Refuse accidental module downgrades and origin mismatches

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Seihou generates project files from *modules* — directories containing a `module.dhall`
file that declares variables, file-generation steps, and shell commands. Every module
declares a version, and seihou records the version it applied in `.seihou/manifest.json`
inside the project. Teams check that manifest into git.

Nothing currently checks the recorded version against what is installed locally. That
creates a silent regression that is easy to hit and hard to notice.

Developer A upgrades the `haskell-base` module from `1.4.0` to `2.0.0`, runs
`seihou run haskell-base`, and commits the regenerated files together with a manifest that
now says `2.0.0`. Developer B pulls that commit. B never ran `seihou upgrade`, so B still
has `haskell-base` `1.4.0` in `~/.config/seihou/installed/`. When B runs
`seihou run haskell-base` — perhaps just to pick up a variable change — seihou regenerates
every file from the *older* module and rewrites the manifest to say `1.4.0`. The project
quietly reverts to the previous scaffolding, and in code review it looks like an ordinary
diff.

A second, sharper version of the same problem: B has a module named `haskell-base`
installed from a completely different git repository than the one the manifest records.
Same name, different module. Seihou generates from it without comment.

After this plan, seihou refuses both. Before generating, `seihou run`, `seihou update`, and
`seihou migrate` compare what the manifest recorded against what is installed on this
machine. If the local copy is older, or came from a different origin URL, the command stops
before touching a single file:

```text
✗ Refusing to run: your local copy of 'haskell-base' is older than the
  version this project expects.

  Recorded in .seihou/manifest.json:  2.0.0
  Installed on this machine:          1.4.0
  Origin: https://github.com/shinzui/seihou-modules.git

  Update your local copy first:
    seihou upgrade haskell-base

  If you really mean to pin this project back to 1.4.0, re-run with
  --allow-downgrade.
```

An explicit `--allow-downgrade` flag proceeds anyway, for the rare case where pinning back
is deliberate. Nothing is fetched over the network; seihou reports what to run and lets the
developer decide.

You can see it working by checking out a manifest that records a newer version than you
have installed and running `seihou run`. It exits non-zero with the message above, and
`.seihou/manifest.json` and every generated file are untouched.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] Milestone 1: `Seihou.CLI.ManifestGuard` with `checkAppliedArtifacts` and its verdict type
- [ ] Milestone 1: Pure unit tests for every verdict, including unparseable versions and `LocalOrigin`
- [ ] Milestone 2: `--allow-downgrade` flag parsed for `run`, `update`, and `migrate`
- [ ] Milestone 2: `seihou run` refuses before generating; `--allow-downgrade` proceeds
- [ ] Milestone 3: `seihou update` refuses before staging
- [ ] Milestone 3: `seihou migrate` refuses before planning
- [ ] Milestone 4: `seihou status` reports stale and mismatched artifacts without failing
- [ ] Milestone 4: `docs/user/migrations.md` and `seihou-cli/help/` text updated


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: A locally installed artifact older than the manifest-recorded version is a hard
  error with an explicit `--allow-downgrade` override; seihou does not warn-and-continue and
  does not auto-fetch.
  Rationale: The failure this guards against is a *silent* regression that looks like an
  ordinary code-review diff, so a warning would be scrolled past. Auto-fetching would make
  `seihou run` perform network I/O and mutate the developer's global install directory as a
  side effect of a local build command, which is surprising and hard to undo. A hard error
  naming `seihou upgrade` keeps the developer in control. Confirmed with the user before the
  parent MasterPlan was decomposed.
  Date: 2026-07-28

- Decision: A *newer* local copy than the manifest records is allowed and is not even
  warned about at the guard level.
  Rationale: That is the ordinary upgrade path — a developer runs `seihou upgrade`, then
  `seihou run`, and the manifest moves forward. Treating it as a problem would make the
  normal workflow require a flag. Seihou already reports version changes through
  `seihou update`'s version-evidence machinery in `seihou-cli/src/Seihou/CLI/Update.hs`, so
  the information is not lost.
  Date: 2026-07-28

- Decision: An artifact recorded with a `LocalOrigin` (no provenance) is reported as
  unverifiable rather than blocked.
  Rationale: `LocalOrigin` means the module was found in the developer's personal
  `~/.config/seihou/modules/` directory, which carries no metadata. Its version can still be
  compared, because the version comes from `module.dhall` itself, but its *identity* cannot.
  Blocking would make personal modules unusable in a shared project; saying nothing would
  hide a real gap. Reporting it as unverifiable is the honest middle.
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
`seihou-cli/src-exe/` called `seihou`), and `seihou-okf-extension`.

`CLAUDE.md` at the repository root sets the module-placement rule: new CLI code goes in
`seihou-cli/src/` (the library) by default. `seihou-cli/src-exe/` is reserved for `Main.hs`,
command dispatchers, and modules that genuinely need `Options.Applicative`,
`Data.FileEmbed`, `GitHash`, or `Paths_seihou_cli`, or that transitively import a module
which does — most commonly `Seihou.CLI.Commands`, which is trapped by `Options.Applicative`.
The rule is enforced by `nix/check-cli-module-placement.sh`, wired into `nix flake check`
and the pre-commit hook. This matters for this plan: the *guard logic* goes in
`seihou-cli/src/`, while the *flag definition* necessarily goes in
`seihou-cli/src-exe/Seihou/CLI/Commands.hs`, which already owns every option parser.

**Record conventions**, described in `CLAUDE.md` and in
`docs/dev/architecture/overview.md` under "Record Conventions", enforced by
`nix/check-record-conventions.sh`: every `data` record field carries `!`; `newtype` fields
are exempt; no type-abbreviation prefixes on field names; an explicit `deriving stock (...)`
clause including `Generic`; fields read and written through `generic-lens` overloaded labels
(`x ^. #field`, `x & #field .~ v`), never record-dot syntax and never record *update*
syntax. Record construction and record patterns are fine. Every module using a `#label` adds
`import Data.Generics.Labels ()` itself.

**What this plan builds on.** Two plans must be complete first.

`docs/plans/76-record-portable-artifact-origins-in-the-manifest.md` added to
`seihou-core/src/Seihou/Core/Types.hs`:

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
`.seihou/modules/<name>`, path stored relative to the project root. `LocalOrigin` means the
artifact came from the developer's personal `~/.config/seihou/modules/` directory, which has
no provenance metadata.

Plan 76 also added `origin :: !ArtifactOrigin` to `AppliedModule` and
`AppliedInstanceState` and `targetOrigin :: !ArtifactOrigin` to `AppliedComposition`, all in
`seihou-core/src/Seihou/Core/Types.hs`, and it moved the `.seihou-origin.json` reader into
`seihou-core/src/Seihou/Core/ArtifactOriginDetect.hs`:

```haskell
data OriginInfo = OriginInfo
  { sourceUrl :: !Text,
    repoName :: !(Maybe Text),
    version :: !(Maybe Text)
  }
  deriving stock (Eq, Generic, Show)

readOriginInfo :: FilePath -> IO (Maybe OriginInfo)
```

`docs/plans/77-resolve-manifest-artifact-origins-to-local-directories.md` added
`seihou-core/src/Seihou/Core/ArtifactRef.hs`:

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

`resolveArtifactOrigin` takes the project root, the search paths, the definition filename
(`"module.dhall"` for modules), and the recorded origin, and returns the absolute directory
on this machine that holds the artifact. This plan calls it to find the local copy it
compares against.

**The manifest.** `.seihou/manifest.json` decodes into the `Manifest` record at
`seihou-core/src/Seihou/Core/Types.hs:476`. Its `modules :: ![AppliedModule]` field is the
flat list of every module instance ever applied. `AppliedModule` at line 594 carries
`name :: !ModuleName`, `parentVars :: !ParentVars` (the variable bindings on the dependency
edge that produced this instance, used to distinguish two instantiations of the same
module), `moduleVersion :: !(Maybe Text)`, `appliedAt :: !UTCTime`, and — after plan 76 —
`origin :: !ArtifactOrigin`.

**Version comparison already exists.** `seihou-core/src/Seihou/Core/Version.hs` defines:

```haskell
newtype Version = Version {segments :: [Natural]}
parseVersion :: Text -> Maybe Version
renderVersion :: Version -> Text
```

`parseVersion` splits on `.` and requires every segment to be a non-negative integer, so
`"1.4.0"` parses and `"1.4.0-rc1"` does not. The `Ord` instance pads the shorter list with
zeros before comparing, so `1.4` and `1.4.0` compare equal. Reuse this; do not write a
second comparison.

`seihou-cli/src/Seihou/CLI/VersionCompare.hs` builds on it with an `OutdatedStatus` type
(`UpToDate`, `OutdatedSt`, `Unversioned`, `Unreachable`) used by `seihou outdated` and
`seihou status` for *remote* comparison. That is a different question (is a newer version
available upstream?) from the one this plan answers (is my local copy older than what this
project expects?). Do not overload it; a new type is clearer.

**Where the guard must fire.** Three commands regenerate or migrate from a module and must
check first.

`seihou run` is `handleRun` in `seihou-cli/src-exe/Seihou/CLI/Run.hs`. It loads the
composition, resolves variables, compiles a plan, and executes. There is already a precedent
for refusing before doing anything: `seihou-cli/src/Seihou/CLI/PendingMigrations.hs` exports
`detectPendingMigrations` and `formatRefusalMessage`, and `Run.hs` imports both and refuses
when a module has an unapplied migration. Follow that shape exactly — same placement in the
flow, same message style, same exit behaviour.

`seihou update` is `seihou-cli/src/Seihou/CLI/Update.hs`. Its entry point stages the whole
update in a temporary directory before touching the project (see
`materializeStagedProject` and the `withProjectUpdate` machinery, and
`seihou-core/src/Seihou/Engine/UpdateTransaction.hs`). The guard must run before staging
begins, so a refusal costs nothing.

`seihou migrate` is `handleMigrate` in `seihou-cli/src/Seihou/CLI/Migrate.hs`. It reads the
manifest, finds the applied module, and plans a migration chain. The guard runs immediately
after the manifest is read.

**Where the flags live.** Every command's option parser is in
`seihou-cli/src-exe/Seihou/CLI/Commands.hs` — `RunOpts`, `MigrateOpts`, and the update
options are all defined there as records with an `Options.Applicative` parser beside each.
Find them with `grep -n "data RunOpts" -A 30 seihou-cli/src-exe/Seihou/CLI/Commands.hs`.
`MigrateOpts` is re-exported through `seihou-cli/src/Seihou/CLI/Migrate.hs`'s imports, so
adding a field there requires updating its construction sites; `grep -rn "MigrateOpts" --include='*.hs' seihou-cli`
finds them.

**Architecture Decision Records.** Plan 76 creates `docs/adr/`. Read both records before
starting. `docs/adr/0002-artifact-identity-is-origin-url-plus-name.md` is directly relevant:
it records that identity is the git URL plus artifact name, and that a content hash was
rejected precisely because it cannot express "the same module, one version newer" — the
relationship this plan's guard reasons about. Adjust the filename to whatever plan 76
allocated, following `agents/skills/exec-plan/ADR.md`. If this plan's implementation reveals
a durable constraint not covered by those two records — for example, a rule about what
counts as a comparable version — add a third ADR in the same change.

**Build and test commands.** From the repository root:

```bash
cabal build all
cabal test all
nix flake check
```


## Plan of Work

Four milestones.

### Milestone 1 — the guard, as pure logic plus one IO shell

Create `seihou-cli/src/Seihou/CLI/ManifestGuard.hs` and add
`Seihou.CLI.ManifestGuard` to the `exposed-modules` list of the `library` stanza in
`seihou-cli/seihou-cli.cabal`, keeping the list sorted. It goes in `src/`, not `src-exe/`,
because it needs none of the four trapping dependencies.

Separate the comparison (pure, easily tested) from the lookup (IO). The pure core:

```haskell
-- | What the guard concluded about one applied artifact.
data ArtifactVerdict
  = -- | Local copy matches or is newer than what the manifest records,
    -- and the origin agrees. Nothing to say.
    ArtifactOk
  | -- | Local copy is strictly older than the recorded version.
    -- Fields: recorded version, local version.
    ArtifactStale !Text !Text
  | -- | A module of this name is installed, but from a different origin
    -- than the manifest records. Fields: recorded origin, local origin.
    ArtifactOriginMismatch !ArtifactOrigin !ArtifactOrigin
  | -- | The recorded artifact is not installed on this machine at all.
    ArtifactUnresolvable !ArtifactRefError
  | -- | Either side has a version string that 'parseVersion' rejects, so
    -- no ordering can be established. Fields: recorded, local.
    ArtifactVersionIncomparable !(Maybe Text) !(Maybe Text)
  | -- | The recorded origin is a 'LocalOrigin', so identity cannot be
    -- verified. The version was still compared and did not indicate a
    -- downgrade.
    ArtifactUnverifiableOrigin
  deriving stock (Eq, Show, Generic)

-- | One artifact's guard result, ready for rendering.
data ArtifactCheck = ArtifactCheck
  { name :: !ModuleName,
    verdict :: !ArtifactVerdict
  }
  deriving stock (Eq, Show, Generic)

-- | Compare one recorded artifact against what was found locally.
--
-- @recordedOrigin@ and @recordedVersion@ come from the manifest.
-- @localOrigin@ and @localVersion@ come from the artifact actually found
-- on this machine — the origin by reading @.seihou-origin.json@ beside
-- it, the version from its @module.dhall@.
judgeArtifact ::
  ArtifactOrigin ->
  Maybe Text ->
  ArtifactOrigin ->
  Maybe Text ->
  ArtifactVerdict
```

Comparison rules, in order. If the recorded origin is a `RemoteOrigin` and the local origin
is also a `RemoteOrigin` with a different `originUrl`, the verdict is
`ArtifactOriginMismatch` — a differing URL means a different module and the version
comparison is meaningless. Compare URLs after normalising a trailing `.git` and a trailing
slash, because `https://host/repo` and `https://host/repo.git` are the same repository;
`parseModuleName` in `seihou-core/src/Seihou/Core/Install.hs` already strips `.git` and can
guide the normalisation, though you will want a small dedicated helper rather than reusing
that function, since it extracts a name rather than normalising a URL.

If the recorded origin is a `LocalOrigin`, identity cannot be checked; fall through to the
version comparison and, if that is clean, return `ArtifactUnverifiableOrigin`.

If either version is `Nothing` or fails `parseVersion`, return
`ArtifactVersionIncomparable` carrying both raw values. Do not guess an ordering from string
comparison.

Otherwise compare with the `Ord` instance from `seihou-core/src/Seihou/Core/Version.hs`. A
strictly smaller local version is `ArtifactStale`; equal or greater is `ArtifactOk`.

The IO shell, in the same module:

```haskell
-- | Check every module recorded in the manifest against this machine.
--
-- @projectRoot@ is the absolute directory holding @.seihou@.
-- @searchPaths@ is normally 'Seihou.Core.Module.defaultSearchPaths'.
-- Returns one 'ArtifactCheck' per distinct recorded module, in manifest
-- order, deduplicated by module name (two instances of the same module
-- with different parent variables resolve to the same directory).
checkAppliedArtifacts ::
  FilePath ->
  [FilePath] ->
  Manifest ->
  IO [ArtifactCheck]

-- | Whether any verdict is severe enough to stop the command.
-- 'ArtifactStale', 'ArtifactOriginMismatch', and 'ArtifactUnresolvable'
-- block; the others do not.
blockingChecks :: [ArtifactCheck] -> [ArtifactCheck]

-- | Render blocking verdicts as the multi-line refusal message.
formatGuardRefusal :: [ArtifactCheck] -> Text
```

`checkAppliedArtifacts` resolves each recorded origin with
`resolveArtifactOrigin projectRoot searchPaths "module.dhall"`, and on success reads the
local artifact's version by evaluating its `module.dhall` — use
`evalModuleFromFile` from `seihou-core/src/Seihou/Dhall/Eval.hs`, which
`seihou-cli/src/Seihou/CLI/Migrate.hs` already imports, and take `^. #version`. Read the
local origin with `detectArtifactOrigin projectRoot resolvedDir` from
`seihou-core/src/Seihou/Core/ArtifactOriginDetect.hs`. If evaluating `module.dhall` fails,
treat the version as `Nothing`, which yields `ArtifactVersionIncomparable` — a module that
does not evaluate is a separate problem that the generation path reports better than the
guard would.

`formatGuardRefusal` produces the message in Purpose / Big Picture, one block per blocking
artifact, with a trailing paragraph explaining `--allow-downgrade`. For
`ArtifactUnresolvable`, embed `renderArtifactRefError` from
`seihou-core/src/Seihou/Core/ArtifactRef.hs` rather than writing a second version of that
message — plan 77 owns its wording and
`docs/plans/80-document-and-end-to-end-verify-the-shared-manifest-workflow.md` asserts on it.

Test the pure part in a new `seihou-cli/test/Seihou/CLI/ManifestGuardSpec.hs`, registered in
the test-suite `other-modules` of `seihou-cli/seihou-cli.cabal` and in
`seihou-cli/test/Main.hs` following the existing pattern (each spec module exports
`tests :: IO TestTree`). Cover every constructor of `ArtifactVerdict`: recorded `2.0.0`
against local `1.4.0` giving `ArtifactStale`; recorded `1.4.0` against local `2.0.0` giving
`ArtifactOk`; recorded `1.4` against local `1.4.0` giving `ArtifactOk` (the zero-padding
case); differing URLs giving `ArtifactOriginMismatch`; the same URL differing only by a
`.git` suffix giving *not* a mismatch; `Nothing` versions giving
`ArtifactVersionIncomparable`; `"1.0.0-rc1"` giving `ArtifactVersionIncomparable`; and a
recorded `LocalOrigin` with equal versions giving `ArtifactUnverifiableOrigin`. Also assert
that `blockingChecks` selects exactly the three blocking constructors.

### Milestone 2 — the flag, and `seihou run`

Add an `allowDowngrade :: !Bool` field to `RunOpts` in
`seihou-cli/src-exe/Seihou/CLI/Commands.hs` with an `Options.Applicative` `switch` for
`--allow-downgrade`, and a help string reading roughly `proceed even when a module
installed locally is older than the version recorded in .seihou/manifest.json`. Add the same
field and switch to `MigrateOpts` and to the update options record in the same file. Fix
every construction site the compiler flags — `grep -rn "RunOpts\|MigrateOpts" --include='*.hs' seihou-cli`
finds them, including test fixtures.

In `seihou-cli/src-exe/Seihou/CLI/Run.hs`, place the guard immediately beside the existing
pending-migration refusal. Read `seihou-cli/src/Seihou/CLI/PendingMigrations.hs` and the
call site in `Run.hs` first, and mirror it: compute the checks, take `blockingChecks`, and
if the list is non-empty and `not (opts ^. #allowDowngrade)`, print
`formatGuardRefusal` and exit non-zero before any file is written. When
`allowDowngrade` is set, print the same blocks under a "proceeding anyway" heading rather
than suppressing them entirely — a deliberate downgrade should still be visible in the
terminal.

Order matters: run the guard *before* the pending-migration check if both would fire, since
a stale local module is the more fundamental problem and the migration advice would be
misleading. Note the chosen order in the Decision Log.

### Milestone 3 — `seihou update` and `seihou migrate`

In `seihou-cli/src/Seihou/CLI/Update.hs`, run the guard before any staging work begins.
`seihou update` already has an elaborate error type (`UpdateError` in
`seihou-cli/src/Seihou/CLI/Update/Types.hs:194`) and a renderer in
`seihou-cli/src/Seihou/CLI/Update/Render.hs`; add a constructor carrying the blocking
`[ArtifactCheck]` and render it with `formatGuardRefusal`. Because the update path stages
into a temporary directory before touching the project, an early refusal leaves nothing to
clean up.

One subtlety specific to `seihou update`: that command's entire purpose can be to *change*
which version is applied, including deliberately moving to a different one. Check what the
update path already knows — `CandidateArtifact` in
`seihou-cli/src/Seihou/CLI/Update/Types.hs:83` carries the candidate's `version`, and
`versionEvidence` around line 585 already computes `VersionChange` records and calls
`validateVersionChange`. If that existing validation already rejects backwards version
changes, the guard here is redundant for `update` and should be limited to the origin
mismatch and unresolvable cases. Read `validateVersionChange` (just below `versionEvidence`)
before implementing, decide, and record the decision in the Decision Log with the evidence.

In `seihou-cli/src/Seihou/CLI/Migrate.hs`, run the guard in `handleMigrate` right after the
manifest is read and the applied module is found, before `runMigrate` is called. Migrating
with a stale local copy is especially bad, because the migration chain is computed from the
local module's declared migration list — a stale copy produces a chain that stops short of
where the project already is. Extend `MigrateError` with a constructor carrying the blocking
checks and render it through the existing `die` path.

### Milestone 4 — surface it in `seihou status`, and document it

`seihou status` in `seihou-cli/src-exe/Seihou/CLI/Status.hs` reports what is applied and
what updates are available. Add a section — or per-row annotations, matching whatever the
existing rendering in `seihou-cli/src/Seihou/CLI/StatusRender.hs` does — showing every
non-`ArtifactOk` verdict. `seihou status` must never fail because of a verdict; it is a
reporting command. This is what lets a developer discover the problem before a command
refuses.

Update the documentation. `docs/user/migrations.md` already discusses versions and the
migration workflow; add the downgrade refusal and `--allow-downgrade` there. Check
`seihou-cli/help/` for a topic file that covers `run` or versions
(`ls seihou-cli/help/`) and update the relevant one — these are embedded into the binary
with `Data.FileEmbed` and surfaced by `seihou help <topic>`. Add an entry to
`docs/user/CHANGELOG.md` following the existing format.

The broader "how teams share a manifest" document is
`docs/plans/80-document-and-end-to-end-verify-the-shared-manifest-workflow.md`'s job; keep
this milestone's documentation focused on the flag and the refusal.


## Concrete Steps

All commands run from the repository root,
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

Confirm the two prerequisite plans are complete:

```bash
grep -n "data ArtifactOrigin" seihou-core/src/Seihou/Core/Types.hs
ls seihou-core/src/Seihou/Core/ArtifactRef.hs
grep -n "currentManifestVersion = " seihou-core/src/Seihou/Manifest/Types.hs
```

Expected: the type exists, the resolver module exists, and the version constant reads `6`.
If any is missing, this plan is blocked on
`docs/plans/76-record-portable-artifact-origins-in-the-manifest.md` or
`docs/plans/77-resolve-manifest-artifact-origins-to-local-directories.md`.

Read the precedent before writing the guard:

```bash
cat seihou-cli/src/Seihou/CLI/PendingMigrations.hs
grep -n "detectPendingMigrations\|formatRefusalMessage" seihou-cli/src-exe/Seihou/CLI/Run.hs
```

Read the existing update-side version validation before deciding Milestone 3's scope:

```bash
grep -n "validateVersionChange" -A 25 seihou-cli/src/Seihou/CLI/Update.hs
```

Find the option records:

```bash
grep -n "data RunOpts" -A 30 seihou-cli/src-exe/Seihou/CLI/Commands.hs
grep -n "data MigrateOpts" -A 30 seihou-cli/src-exe/Seihou/CLI/Commands.hs
```

After each milestone:

```bash
cabal build all && cabal test all
```

Before committing:

```bash
nix flake check
```

Commit with all three trailers:

```text
feat(run): refuse to generate from a module older than the manifest records

Compare each recorded artifact's version and origin against the copy
installed on this machine before generating, and stop with an actionable
message when the local copy is stale or came from a different origin.
--allow-downgrade proceeds anyway.

MasterPlan: docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md
ExecPlan: docs/plans/78-refuse-accidental-module-downgrades-and-origin-mismatches.md
Intention: intention_01kyk6fnbyegxss8fqnf3j03tf
```


## Validation and Acceptance

Unit acceptance is `cabal test all` green with `ManifestGuardSpec` covering every verdict
constructor.

Behavioral acceptance reproduces the exact scenario this plan exists to prevent, using
`XDG_CONFIG_HOME` to simulate two developers on one machine. `getXdgDirectory XdgConfig`
honours that variable, so setting it redirects both `~/.config/seihou/modules/` and
`~/.config/seihou/installed/`.

Set up the scratch environment:

```bash
rm -rf /tmp/seihou-downgrade
mkdir -p /tmp/seihou-downgrade/project
mkdir -p /tmp/seihou-downgrade/home-a/seihou/installed/demo
mkdir -p /tmp/seihou-downgrade/home-b/seihou/installed/demo
cd /tmp/seihou-downgrade/project
git init
```

Create two versions of the same module. Put a `module.dhall` declaring
`version = "2.0.0"` in `/tmp/seihou-downgrade/home-a/seihou/installed/demo/` and one
declaring `version = "1.4.0"` in `/tmp/seihou-downgrade/home-b/seihou/installed/demo/` —
copy the schema import line and required fields from `docs/user/module-authoring.md`, which
tracks the pinned schema URL. Give both directories the same `.seihou-origin.json`, differing
only in `version`:

```json
{
  "sourceUrl": "https://example.com/demo-modules.git",
  "repoName": "demo-modules",
  "installedAt": "2026-07-28T00:00:00Z",
  "version": "2.0.0",
  "tags": []
}
```

Generate as developer A, who has `2.0.0`:

```bash
cd /tmp/seihou-downgrade/project
XDG_CONFIG_HOME=/tmp/seihou-downgrade/home-a cabal run seihou -- run demo
grep -n '"version"' .seihou/manifest.json
git add -A && git commit -m "generated by developer A"
```

Expected: the manifest records `"version": "2.0.0"` for the `demo` module.

Now run as developer B, who has `1.4.0`:

```bash
XDG_CONFIG_HOME=/tmp/seihou-downgrade/home-b cabal run seihou -- run demo
echo "exit status: $?"
git status --porcelain
```

Expected: the refusal message from Purpose / Big Picture naming `2.0.0` and `1.4.0`, a
non-zero exit status, and **empty** `git status --porcelain` output — nothing was
regenerated and the manifest was not rewritten. That last check is the important one: it
proves the guard fires before any write.

Then confirm the override works:

```bash
XDG_CONFIG_HOME=/tmp/seihou-downgrade/home-b cabal run seihou -- run demo --allow-downgrade
echo "exit status: $?"
grep -n '"version"' .seihou/manifest.json
```

Expected: exit status `0`, the downgrade blocks still printed under a "proceeding anyway"
heading, and the manifest now recording `"version": "1.4.0"`.

Reset and confirm `seihou migrate` refuses the same way:

```bash
git checkout -- . && git clean -fd
XDG_CONFIG_HOME=/tmp/seihou-downgrade/home-b cabal run seihou -- migrate demo
echo "exit status: $?"
```

Expected: the same refusal, non-zero exit.

Confirm the origin-mismatch path by editing
`/tmp/seihou-downgrade/home-b/seihou/installed/demo/.seihou-origin.json` to a different
`sourceUrl`, bumping that copy's `module.dhall` to `version = "2.0.0"` so version is not the
blocker, and re-running:

```bash
XDG_CONFIG_HOME=/tmp/seihou-downgrade/home-b cabal run seihou -- run demo
```

Expected: an origin-mismatch refusal naming both URLs, not a version message.

Finally confirm `seihou status` reports rather than fails:

```bash
XDG_CONFIG_HOME=/tmp/seihou-downgrade/home-b cabal run seihou -- status
echo "exit status: $?"
```

Expected: the stale or mismatched artifact appears in the output, and the exit status is
`0`.

Paste the real transcripts into Concrete Steps as evidence when you run them.


## Idempotence and Recovery

All source edits are revertible with git. The scratch environment under
`/tmp/seihou-downgrade` is disposable — `rm -rf /tmp/seihou-downgrade` resets it — and
nothing in the validation touches the real `~/.config/seihou/`, because every invocation
sets `XDG_CONFIG_HOME`.

The guard itself is designed to be recoverable by construction: it runs before any write, so
a refusal leaves the project byte-identical. The `--allow-downgrade` path is the one that
mutates, and it is exactly as recoverable as an ordinary `seihou run` — `git checkout -- .`
restores the project, including `.seihou/manifest.json`, because the manifest is checked in.

The riskiest implementation step is Milestone 2's flag addition, because adding a field to
`RunOpts` and `MigrateOpts` breaks every construction site including test fixtures. Do that
edit in one pass, let the compiler enumerate the sites, and do not commit until
`cabal build all` is clean.

If Milestone 3's investigation shows that `seihou update`'s existing
`validateVersionChange` already rejects backwards version moves, scope the guard there down
to origin mismatches and unresolvable artifacts rather than duplicating the check. Record
that in the Decision Log with the evidence, and adjust the Progress entry to say what was
actually implemented.


## Interfaces and Dependencies

No new package dependencies. `seihou-cli-internal` already depends on `seihou-core`,
`text`, `containers`, `directory`, `filepath`, `generic-lens`, and `lens`.

At the end of Milestone 1, these must exist in
`seihou-cli/src/Seihou/CLI/ManifestGuard.hs`:

```haskell
data ArtifactVerdict
  = ArtifactOk
  | ArtifactStale !Text !Text
  | ArtifactOriginMismatch !ArtifactOrigin !ArtifactOrigin
  | ArtifactUnresolvable !ArtifactRefError
  | ArtifactVersionIncomparable !(Maybe Text) !(Maybe Text)
  | ArtifactUnverifiableOrigin
  deriving stock (Eq, Show, Generic)

data ArtifactCheck = ArtifactCheck
  { name :: !ModuleName,
    verdict :: !ArtifactVerdict
  }
  deriving stock (Eq, Show, Generic)

judgeArtifact :: ArtifactOrigin -> Maybe Text -> ArtifactOrigin -> Maybe Text -> ArtifactVerdict
checkAppliedArtifacts :: FilePath -> [FilePath] -> Manifest -> IO [ArtifactCheck]
blockingChecks :: [ArtifactCheck] -> [ArtifactCheck]
formatGuardRefusal :: [ArtifactCheck] -> Text
```

This plan consumes, and must not change,
`resolveArtifactOrigin` and `renderArtifactRefError` from
`seihou-core/src/Seihou/Core/ArtifactRef.hs` (owned by
`docs/plans/77-resolve-manifest-artifact-origins-to-local-directories.md`),
`detectArtifactOrigin` and `readOriginInfo` from
`seihou-core/src/Seihou/Core/ArtifactOriginDetect.hs` and the `ArtifactOrigin` type from
`seihou-core/src/Seihou/Core/Types.hs` (owned by
`docs/plans/76-record-portable-artifact-origins-in-the-manifest.md`), and
`parseVersion`, `renderVersion`, and the `Ord Version` instance from
`seihou-core/src/Seihou/Core/Version.hs`. Changing any of those requires a decision recorded
in the parent MasterPlan's Decision Log at
`docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md`.

`docs/plans/80-document-and-end-to-end-verify-the-shared-manifest-workflow.md` consumes this
plan's `formatGuardRefusal` output and the `--allow-downgrade` flag, and asserts on both in
an automated end-to-end test.
