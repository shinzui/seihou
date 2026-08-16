---
id: 82
slug: refuse-to-overwrite-an-installation-from-a-different-source
title: "Refuse to overwrite an installation from a different source"
kind: exec-plan
created_at: 2026-08-16T14:16:35Z
intention: "intention_01m05ew4qbef6tn9bnphy4nv2n"
master_plan: "docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md"
---

# Refuse to overwrite an installation from a different source

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

`seihou install` copies every artifact it installs into
`~/.config/seihou/installed/<name>`, keyed by the artifact's bare name across every git
repository the user has ever installed from. That directory is machine-global: every project
on the machine resolves artifact names through it.

Today, installing an artifact whose name is already taken deletes what was there and prints
one line:

```text
warning: overwriting existing installation of 'adopt-architecture-decisions'
```

That line reads identically whether you are doing the ordinary thing — reinstalling the same
artifact from the same URL to pick up a new version — or the destructive thing — replacing
one repository's artifact with a different repository's artifact that happens to share a
name. The ordinary case is overwhelmingly the common one, which is exactly what trains a
reader to skip the line. When the destructive case happens, every project on the machine
that resolved that name is affected at once, and no project's manifest records that anything
changed.

After this plan, `seihou install` reads the provenance file it is about to destroy and
decides from it. Same source URL: proceed, with a quieter note naming the version
transition. Different source URL, or no provenance at all: refuse, print both sources, and
name the flag that overrides. A user can see the change immediately — installing artifact
`foo` from repository A and then from repository B stops silently and tells them the two
are different artifacts sharing a name.

This matters to the initiative in
`docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md` because a
library cohort means installing several upgrade blueprints from several repositories side by
side. Bare-name collision stops being a hypothetical the moment `kiroku-upgrade` and
`keiro-upgrade` live in different repositories and a third repository publishes something
with an overlapping name.


## Progress

- [ ] Read `installModuleDir` and every call site (orientation, no edits).
- [ ] Add an `InstallCollision` result type and origin comparison to `seihou-cli/src/Seihou/CLI/InstallShared.hs`.
- [ ] Change `installModuleDir` to consult the existing `.seihou-origin.json` before removing the directory.
- [ ] Add a `force` flag to the `installModuleDir` signature and thread it through all ten call sites.
- [ ] Add `--force` to `seihou install` in `seihou-cli/src-exe/Seihou/CLI/Commands.hs` and wire it to `InstallOpts`.
- [ ] Confirm the non-`install` call sites (upgrade, update, migrate refresh) pass the same-source expectation rather than an unconditional override.
- [ ] Add tests covering same-source, different-source, missing-provenance, and `--force`.
- [ ] Update `docs/cli/install.md`, `docs/cli/upgrade.md`, and `docs/user/CHANGELOG.md`.
- [ ] Mark IR-4 `status: implemented` and update `docs/improvement-requests/log.md`.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: ...
  Rationale: ...
  Date: ...


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

### What this repository is

Seihou is a project scaffolding system written in Haskell. It is a two-package Cabal
workspace: `seihou-core` (the library, at `seihou-core/`) and `seihou-cli` (at
`seihou-cli/`). The CLI package is split into a library at `seihou-cli/src/` (package name
`seihou-cli-internal`) and an executable at `seihou-cli/src-exe/`. New code goes in a
library by default; the executable is reserved for `Main.hs`, command dispatchers, and
modules needing `Options.Applicative`, `Data.FileEmbed`, `GitHash`, or `Paths_seihou_cli`,
plus anything transitively importing such a module. `nix/check-cli-module-placement.sh`
enforces this. The work in this plan stays in modules that already exist on the correct
side of that line: the primitive is in the CLI library, the flag parser is in the
executable.

Records use strict fields, `Generic`, explicit deriving strategies, and are read and
written through `generic-lens` overloaded labels (`opts ^. #force`), never record dot
syntax and never record update syntax. Every module using `#label` imports
`Data.Generics.Labels ()` itself. `nix/check-record-conventions.sh` enforces this.

### Terms used in this plan

**Install cache** — `~/.config/seihou/installed/`, one subdirectory per artifact name,
shared by every project on the machine. It is one of three roots seihou searches for
artifacts (`Seihou.Core.Module.defaultSearchPaths`); the other two are the project's own
`.seihou/modules/` and the developer's `~/.config/seihou/modules/`.

**Provenance file** — `.seihou-origin.json`, written beside every installed artifact by
`seihou install`. It records the source URL, the registry repository name, the version, the
install timestamp, and tags. It is the only thing in the cache that says where an artifact
came from.

**Artifact** — a module, recipe, blueprint, or prompt. `installModuleDir` installs all four;
its name is historical.

### The function this plan changes

`seihou-cli/src/Seihou/CLI/InstallShared.hs` holds the shared primitive:

```haskell
installModuleDir :: FilePath -> String -> Text -> Maybe Text -> Maybe Text -> [Text] -> IO ()
installModuleDir moduleDir name source registryName moduleVersion moduleTags = do
  xdgConfig <- getXdgDirectory XdgConfig "seihou"
  let installDir = xdgConfig </> "installed" </> name

  exists <- doesDirectoryExist installDir
  when exists $ do
    logIO LogNormal (logWarn $ "overwriting existing installation of '" <> T.pack name <> "'")
    removeDirectoryRecursive installDir

  createDirectoryIfMissing True installDir
  copyDirectoryRecursive moduleDir installDir

  now <- getCurrentTime
  let origin = OriginMeta source registryName (T.pack (iso8601Show now)) moduleVersion moduleTags
  LBS.writeFile (installDir </> ".seihou-origin.json") (encodePretty origin)
```

The parameters are, in order: the directory to copy from, the artifact name (which becomes
the cache subdirectory), the source URL, the optional registry repository name, the optional
version, and the tags.

The read side of the provenance file already exists and is already imported by this module:

```haskell
-- Seihou.Core.ArtifactOriginDetect, re-exported by Seihou.CLI.InstallShared
data OriginInfo = OriginInfo
  { sourceUrl :: !Text,
    repoName :: !(Maybe Text),
    version :: !(Maybe Text)
  }

readOriginInfo :: FilePath -> IO (Maybe OriginInfo)
```

`readOriginInfo` returns `Nothing` when the file is absent or unparseable. So the
information needed to make this decision is already on disk and already reachable from this
module; nothing new has to be recorded.

### Every call site

Run `rg -n "installModuleDir" --glob '*.hs'` to confirm this list before editing, since it
determines the size of the change:

- `seihou-cli/src-exe/Seihou/CLI/Install.hs` — seven calls: single-module (line ~185),
  single-recipe (~199), single-blueprint (~234), single-prompt (~268), and four registry
  paths (~441, ~448, ~464, ~490). These are the calls `seihou install` makes and the ones
  that must respect the new refusal and the new `--force`.
- `seihou-cli/src-exe/Seihou/CLI/Upgrade.hs` line ~217 — `seihou upgrade` refetching an
  artifact from its recorded origin URL.
- `seihou-cli/src/Seihou/CLI/Update.hs` line ~954 — `seihou update` publishing a fetched
  artifact into the cache.
- `seihou-cli/src/Seihou/CLI/Migrate.hs` line ~500 (`refreshInstalledFromClone`) —
  `seihou migrate` refreshing the installed copy after a successful apply.

The last three all reinstall from the origin URL the artifact already records, so they are
structurally the same-source case. IR-4 is explicit that they should be *checked against
that expectation rather than exempted*: if one of them ever hits a different-source
refusal, that is a real inconsistency worth surfacing, not noise to suppress.

### The relevant ADR

`docs/adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md` decides that a command
about to generate from an artifact refuses when the local copy is older than, or came from
somewhere other than, what the manifest records — and rejects warn-and-continue by name:

> A warning is the natural-looking middle ground and is worse than useless here. The whole
> problem is that the regression is invisible in review; a line of warning text scrolled
> past in a build log does not make it visible.

It also relies on the install cache being machine-global when it rejects auto-fetching:

> it would mutate `~/.config/seihou/installed/`, which is shared by every project on the
> machine, as a side effect.

This plan applies that same reasoning one layer earlier. The ADR governs the generate path;
nothing in it currently governs the install path, which is what *causes* the generate-path
failure. Consider whether the ADR should be amended to say so, or whether that belongs in a
new ADR written when
`docs/plans/83-guard-the-agent-path-against-stale-and-substituted-artifacts.md` lands; record
the decision either way.

`docs/adr/` is a plain filesystem corpus, not a profile-governed OKF bundle — `mori.dhall`
registers only `docs/improvement-requests`. Keep the established convention: one file per
decision named `NNNN-slug.md`, a `# ADR NNNN — Title` heading, and `Status` / `Date` lines.
Do not add OKF frontmatter to an ADR.

No cross-repository ADR governs this work.

### The Improvement Request this implements

`docs/improvement-requests/refuse-to-overwrite-an-installation-from-a-different-source.md`
(IR-4). Read it before starting. It contains the full argument, including the section
"Considered: namespacing the install cache by repository", which explains why the more
principled fix — keying the cache as `installed/<repo>/<name>` — is deliberately *not* what
this plan does. Do not implement that alternative. If it is ever adopted, the refusal added
here stays correct and simply becomes unreachable.


## Plan of Work

### Milestone 1 — decide, in one place, what a collision is

At the end of this milestone `Seihou.CLI.InstallShared` can classify an install into one of
three cases without performing it, and that classification is unit-testable.

Add to `seihou-cli/src/Seihou/CLI/InstallShared.hs`:

```haskell
-- | What the install cache already holds at the name being installed into.
data InstallCollision
  = -- | Nothing is installed under this name.
    NoExistingInstall
  | -- | An artifact from the same source URL is installed. This is the
    -- ordinary upgrade path. Carries the recorded version, if any, for the
    -- transition note.
    SameSource !(Maybe Text)
  | -- | An artifact from a different source URL is installed. Carries the
    -- recorded source URL.
    DifferentSource !Text
  | -- | Something is installed but carries no readable provenance, so
    -- seihou cannot tell whether replacing it is safe.
    UnknownSource
  deriving stock (Eq, Show, Generic)

-- | Classify what is already installed at @installDir@ against the source
-- URL an install is about to write there. Pure decision, IO only to read
-- the provenance file.
classifyInstallCollision :: FilePath -> Text -> IO InstallCollision
```

Compare URLs after normalisation, not literally. `https://host/repo`,
`https://host/repo.git`, and `https://host/repo/` all name the same repository, and a user
who typed one spelling last week and another today must not be told they have a different
artifact. `Seihou.CLI.ManifestGuard` already contains exactly this function:

```haskell
normalizeOriginUrl :: Text -> Text
normalizeOriginUrl = dropTrailingSlashes . dropGitSuffix . dropTrailingSlashes . T.strip
```

It is currently private. Export it from `Seihou.CLI.ManifestGuard` and import it here rather
than writing a second copy — two normalisers that drift apart would produce a refusal on the
install path and no mismatch on the guard path, or the reverse.

Note for coordination: `docs/plans/81-record-artifact-origin-for-agent-applied-artifacts.md`
also needs `normalizeOriginUrl` exported. Whichever plan lands first performs the export;
the second finds it already done. Exporting an existing private function is not a conflict.

Keep the pure classification separate from the destructive act so a test can exercise it
against a temp directory without installing anything.

### Milestone 2 — refuse, and let the user override

At the end of this milestone `installModuleDir` refuses on `DifferentSource` and
`UnknownSource` unless told to proceed, and the ordinary path is quieter than it is today.

Change the signature to take the override explicitly:

```haskell
installModuleDir ::
  -- | Proceed even when the existing installation came from a different source
  Bool ->
  FilePath ->
  String ->
  Text ->
  Maybe Text ->
  Maybe Text ->
  [Text] ->
  IO ()
```

Put the new `Bool` first so the existing six positional arguments keep their order and
call-site diffs stay readable. Prefer this to a record parameter: the function already takes
six positionals and reshaping it is out of scope for this plan.

Behaviour by case:

- `NoExistingInstall` — proceed silently, as today.
- `SameSource mVersion` — proceed. Replace the current warning with a verbose-level note
  naming the transition, for example
  `reinstalling 'haskell-base' (0.4.0 -> 0.5.0) from the same source`. Use
  `logIO LogVerbose` so a routine upgrade prints nothing at normal verbosity. If either
  version is unknown, omit that half rather than printing `(unknown -> 0.5.0)`.
- `DifferentSource recordedUrl` — with `force` false, refuse. With `force` true, proceed and
  print what is being overridden at normal level, mirroring how `--allow-downgrade` behaves
  under ADR 0003: a deliberate override should still be visible.
- `UnknownSource` — same as `DifferentSource`, with a message saying provenance is missing
  rather than naming a URL.

Refusal must happen *before* `removeDirectoryRecursive`, so a refused install leaves the
cache byte-identical.

How to refuse matters. `installModuleDir` returns `IO ()` and has ten call sites in three
commands; making it throw would scatter handling. Return a result instead:

```haskell
data InstallOutcome
  = InstallPerformed
  | InstallRefused !InstallCollision
  deriving stock (Eq, Show, Generic)

installModuleDir :: Bool -> FilePath -> String -> Text -> Maybe Text -> Maybe Text -> [Text] -> IO InstallOutcome
```

Then each caller decides. `seihou install` prints the refusal and exits nonzero; the
registry path, which installs many artifacts in a loop, must decide whether one refusal
aborts the batch or is collected and reported at the end. Choose: collect and report, then
exit nonzero, so a user installing twenty artifacts is not left with a half-applied batch
and no summary. Record that choice in the Decision Log.

Write the refusal message in the shape ADR 0003's refusals already use — the format is
established by `formatGuardRefusal` in `seihou-cli/src/Seihou/CLI/ManifestGuard.hs`, and
matching it means users see one vocabulary for one class of problem:

```text
✗ Refusing to install 'adopt-architecture-decisions': a different artifact
  is already installed under that name.

  Installed on this machine:  https://github.com/shinzui/okf-profiles
  Incoming:                   https://github.com/acme/other-profiles

  These are different artifacts that happen to share a name. Installing
  would replace the first for every project on this machine.

  To replace it anyway, re-run with --force.
```

Put the message-building in a pure function next to `classifyInstallCollision` so it can be
tested without touching the filesystem.

### Milestone 3 — the flag and the call sites

At the end of this milestone `seihou install --force` exists and every caller passes a
deliberate value.

In `seihou-cli/src-exe/Seihou/CLI/Commands.hs`, add a `force :: !Bool` field to
`InstallOpts` (line ~208) and a corresponding `switch` to its parser (line ~929), following
the existing pattern in that file:

```haskell
<*> switch (long "force" <> help "Replace an installation that came from a different source")
```

Keep the field last in the record and the switch last in the parser so the applicative
ordering stays aligned — this is a positional applicative parser and a mismatch compiles
but produces wrong values.

Add a `seihou help` entry if the command's help text enumerates flags; check
`seihou-cli/src-exe/Seihou/CLI/Help.hs` for an install section and update it if present.

Then update the ten call sites:

- The seven in `seihou-cli/src-exe/Seihou/CLI/Install.hs` pass `opts ^. #force`.
- `seihou-cli/src-exe/Seihou/CLI/Upgrade.hs`, `seihou-cli/src/Seihou/CLI/Update.hs`, and
  `refreshInstalledFromClone` in `seihou-cli/src/Seihou/CLI/Migrate.hs` pass `False`, and
  handle a returned `InstallRefused` by reporting it rather than ignoring it. Each of these
  reinstalls from the URL the artifact already records, so a refusal there means the cache
  and the recorded origin disagree — real news. Add a short comment at each site saying so,
  so a future reader does not "fix" it by passing `True`.

### Milestone 4 — tests

The CLI test suite lives at `seihou-cli/test/`, run with `cabal test seihou-cli-test`. It
uses `tasty` with `hspec` through `Test.Tasty.Hspec.testSpec`; each spec module exports
`tests :: IO TestTree` and is registered in the suite's `Main.hs`. Filesystem tests use
`System.IO.Temp.withSystemTempDirectory` — see
`seihou-cli/test/Seihou/CLI/AppliedBlueprintMigrationSpec.hs` for the pattern.

Create `seihou-cli/test/Seihou/CLI/InstallCollisionSpec.hs` and register it. Cover:

- an empty cache directory classifies as `NoExistingInstall`;
- a directory whose `.seihou-origin.json` records the same URL classifies as `SameSource`,
  including when one side is spelled with a trailing `.git` and the other is not;
- a different URL classifies as `DifferentSource` carrying the recorded URL;
- a directory with no `.seihou-origin.json`, and one with an unparseable file, both classify
  as `UnknownSource`;
- `installModuleDir False` against a `DifferentSource` directory returns `InstallRefused`
  **and leaves the existing directory's contents unchanged** — assert on a marker file
  written before the call, because "refuses before deleting" is the property that matters;
- `installModuleDir True` against the same setup returns `InstallPerformed` and the
  directory now holds the incoming content and a `.seihou-origin.json` naming the new URL.

Point `XDG_CONFIG_HOME` at the temp directory so `getXdgDirectory XdgConfig "seihou"`
resolves inside the sandbox and the test never touches the developer's real cache. Verify
that redirection works before writing the rest of the spec — if `installModuleDir` resolves
the cache root internally in a way the environment cannot redirect, extract the root as a
parameter with a `getXdgDirectory`-based default rather than testing against a real home
directory.

Also check `seihou-cli/test/Seihou/CLI/InstallHistorySpec.hs` and `UpgradeSpec.hs` for
existing tests that call the install primitives and will need their expectations updated for
the new signature and the quieter same-source note.

### Milestone 5 — documentation and IR bookkeeping

`docs/cli/install.md` — document `--force` in the options table, and add a short section
describing the refusal with an example transcript. That file currently explains that
`--name` only applies to single-artifact repositories; add the observation that a registry
entry has no rename escape hatch, so `--force` is the only override for a registry-entry
collision.

`docs/cli/upgrade.md` and `docs/cli/migrate.md` — one sentence each noting that these
commands reinstall from the recorded origin and therefore report rather than override a
source mismatch.

`docs/user/CHANGELOG.md` — an entry describing the behaviour change. Call out that the
routine same-source reinstall is now quieter, since a user who relied on seeing the warning
will notice its absence.

Update `docs/improvement-requests/refuse-to-overwrite-an-installation-from-a-different-source.md`:
set `status: implemented` in the frontmatter and add a closing section naming this plan.
That bundle is a profile-governed OKF bundle registered in `mori.dhall`, so maintain its
reserved `log.md` with `okf log add` and validate:

```bash
okf validate docs/improvement-requests \
  --strict \
  --profile docs/improvement-requests/profile.dhall \
  --profile-enforce \
  --log-enforce
```


## Concrete Steps

Run everything from the repository root,
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

Orient:

```bash
rg -n "installModuleDir" --glob '*.hs'
rg -n "normalizeOriginUrl" seihou-cli/src/Seihou/CLI/ManifestGuard.hs
rg -n "data InstallOpts" -A 10 seihou-cli/src-exe/Seihou/CLI/Commands.hs
```

Build and test:

```bash
cabal build all
cabal test seihou-cli-test
```

Full mechanical checks before committing:

```bash
nix flake check
```

Commit with all three trailers:

```text
feat(install): refuse to replace an artifact installed from another source

Read .seihou-origin.json before removing an existing installation and
refuse when the incoming artifact comes from a different repository.
--force overrides and prints what it overrides.

MasterPlan: docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md
ExecPlan: docs/plans/82-refuse-to-overwrite-an-installation-from-a-different-source.md
Intention: intention_01m05ew4qbef6tn9bnphy4nv2n
```


## Validation and Acceptance

**Automated.** `cabal test seihou-cli-test` passes, including the new
`InstallCollisionSpec`. The decisive assertion is that a refused install leaves the existing
cache directory byte-identical.

**By hand.** Create two throwaway git repositories, each publishing a module with the same
name. `seihou new-module shared-thing` scaffolds one; commit it in each repository with a
visibly different template file.

```bash
seihou install file:///tmp/repo-one --module shared-thing
seihou install file:///tmp/repo-two --module shared-thing
```

Before this change the second command prints one warning line and succeeds. After it, the
second command prints the refusal shown in milestone 2 and exits nonzero, and:

```bash
cat ~/.config/seihou/installed/shared-thing/.seihou-origin.json
```

still names `file:///tmp/repo-one`. That difference is the acceptance criterion.

Then:

```bash
seihou install file:///tmp/repo-two --module shared-thing --force
```

succeeds, prints what it overrode, and the provenance file now names `file:///tmp/repo-two`.

**Ordinary path unaffected.** Reinstalling from the same URL must still work and must now be
quiet:

```bash
seihou install file:///tmp/repo-one --module shared-thing --force
seihou install file:///tmp/repo-one --module shared-thing
```

The second command prints nothing at normal verbosity and succeeds. With `-v` it prints the
reinstall note. Confirm `seihou upgrade shared-thing` and `seihou migrate shared-thing`
still complete — these exercise the three non-`install` call sites and are the ones most
likely to regress if the same-source classification is wrong.

**No provenance.** Create `~/.config/seihou/installed/handmade/` by hand with a
`module.dhall` and no `.seihou-origin.json`, then try to install anything under that name.
It must refuse with the missing-provenance message and leave the directory alone.


## Idempotence and Recovery

All edits are to source. Re-running the build and tests is safe.

The runtime behaviour introduced is strictly *less* destructive than what it replaces: the
new code refuses in cases where the old code deleted a directory. There is no migration and
no state to convert. A user who wants the old behaviour has `--force`.

The one recovery path worth stating for users, and worth putting in `docs/cli/install.md`:
if a refusal blocks a legitimate replacement and `--force` feels too blunt, the artifact can
be removed from the cache by hand — `rm -rf ~/.config/seihou/installed/<name>` — after which
the install classifies as `NoExistingInstall` and proceeds silently. Say plainly that this
affects every project on the machine that resolved that name.

If the test sandbox cannot redirect the cache root through `XDG_CONFIG_HOME`, stop and
extract the root as a parameter rather than running tests against the real
`~/.config/seihou/installed/`. A test suite that can delete a developer's installed
artifacts is not acceptable.


## Interfaces and Dependencies

No new library dependencies.

At the end of the plan these must exist in `seihou-cli/src/Seihou/CLI/InstallShared.hs`:

```haskell
data InstallCollision
  = NoExistingInstall
  | SameSource !(Maybe Text)
  | DifferentSource !Text
  | UnknownSource
  deriving stock (Eq, Show, Generic)

data InstallOutcome
  = InstallPerformed
  | InstallRefused !InstallCollision
  deriving stock (Eq, Show, Generic)

classifyInstallCollision :: FilePath -> Text -> IO InstallCollision

formatInstallRefusal :: String -> Text -> InstallCollision -> Text

installModuleDir ::
  Bool -> FilePath -> String -> Text -> Maybe Text -> Maybe Text -> [Text] -> IO InstallOutcome
```

In `seihou-cli/src/Seihou/CLI/ManifestGuard.hs`, `normalizeOriginUrl` added to the export
list.

In `seihou-cli/src-exe/Seihou/CLI/Commands.hs`:

```haskell
data InstallOpts = InstallOpts
  { source :: !(Maybe Text),
    name :: !(Maybe Text),
    modules :: ![Text],
    all :: !Bool,
    force :: !Bool
  }
  deriving stock (Eq, Show, Generic)
```

This plan has no hard dependency on any other child plan and can be implemented first, last,
or in parallel. It shares one line of surface with
`docs/plans/81-record-artifact-origin-for-agent-applied-artifacts.md` — the export of
`normalizeOriginUrl` — and one soft relationship with
`docs/plans/83-guard-the-agent-path-against-stale-and-substituted-artifacts.md`, which
detects at use time the collision this plan prevents at install time.
