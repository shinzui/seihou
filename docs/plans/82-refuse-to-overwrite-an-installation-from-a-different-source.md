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

- [x] Read `installModuleDir` and every call site (orientation, no edits). — 2026-08-16
- [x] Add an `InstallCollision` result type and origin comparison to `seihou-cli/src/Seihou/CLI/InstallShared.hs`. — 2026-08-16
- [x] Change `installModuleDir` to consult the existing `.seihou-origin.json` before removing the directory. — 2026-08-16
- [x] Add a `force` flag to the `installModuleDir` signature and thread it through all ten call sites. — 2026-08-16
- [x] Add an `installModuleDirInto` variant taking the cache root explicitly, so tests never touch the developer's real cache (see Decision Log). — 2026-08-16
- [x] Add `--force` to `seihou install` in `seihou-cli/src-exe/Seihou/CLI/Commands.hs` and wire it to `InstallOpts`. — 2026-08-16
- [x] Confirm the non-`install` call sites (upgrade, update, migrate refresh) pass the same-source expectation rather than an unconditional override. — 2026-08-16
- [x] Add tests covering same-source, different-source, missing-provenance, and `--force`. — 2026-08-16
- [x] Update `docs/cli/install.md`, `docs/cli/upgrade.md`, `docs/cli/migrate.md`, and `docs/user/CHANGELOG.md`. — 2026-08-16
- [x] Close IR-4 and update `docs/improvement-requests/log.md`. Terminal status is `completed`, not `implemented`. — 2026-08-16
- [x] ADR decision: wrote `docs/adr/0006-the-install-cache-will-not-silently-substitute-an-artifact.md` rather than amending ADR 0003 (see Decision Log). — 2026-08-16


## Surprises & Discoveries

- **The plan's "verbose-level note" for a same-source reinstall is not reachable.**
  `logIO`'s first argument is the *configured* log level, not the message's level, so
  `logIO LogVerbose (logInfo …)` prints unconditionally rather than only under `-v`. And
  `InstallOpts` has no verbosity field at all, so `installModuleDir` has no configured level
  to consult. The same-source case is therefore silent rather than demoted; the calling
  command already prints what it installed on the next line.

- **`normalizeOriginUrl` had already moved, and further than the plan expected.** The plan
  said to export it from `seihou-cli/src/Seihou/CLI/ManifestGuard.hs`, noting that
  `docs/plans/81-record-artifact-origin-for-agent-applied-artifacts.md` needed the same
  export and whichever landed first would perform it. EP-81 landed first and did something
  better: it moved the function into `seihou-core/src/Seihou/Core/ArtifactIdentity.hs`,
  because two of the receipt-ledger call sites are in `seihou-core` and cannot import from
  `seihou-cli`. This plan imports it from there. The coordination note was right about the
  shape of the interaction and wrong about the destination — no conflict either way.

- **The registry batch already had the right structure.** `installRegistryEntry` returns
  `IO Bool` and `installFromRegistry` already counted successes and failures and printed a
  summary. The only thing missing was the exit code: it reported `3 entries installed, 2
  failed.` and exited zero, so a script could not tell a half-applied batch from a complete
  one. Adding `when (failed > 0) exitFailure` also covers pre-existing failure kinds
  (validation errors, unloadable entries) that previously exited zero — see the Decision Log.

- **The `UnknownSource` case was not in IR-4 but has the same shape.** An entry with no
  readable `.seihou-origin.json` — created by hand, or left by a much older seihou — cannot
  be proved to be the same artifact either, and the remedy is identical. It is refused
  alongside `DifferentSource`.


## Decision Log

- Decision: Split the install primitive into `installModuleDir`, which resolves the XDG cache
  root, and `installModuleDirInto`, which takes the root as its first argument. Tests target
  the second.
  Rationale: The plan proposed redirecting `XDG_CONFIG_HOME` in the test sandbox. That does
  work — `getXdgDirectory XdgConfig` honours it on this platform — but an environment
  variable is process-global, and `tasty` runs specs concurrently, so a spec that mutates it
  would silently affect whatever else is running. The plan's own fallback ("extract the root
  as a parameter") is the safe form, and it costs one thin wrapper. No call site outside the
  tests changes.
  Date: 2026-08-16

- Decision: A refused install returns `InstallRefused`; it does not throw. A single-artifact
  install exits non-zero on refusal, a registry batch collects every refusal, reports the
  totals, and exits non-zero at the end.
  Rationale: The plan's choice, for its reason: a user installing twenty entries should see
  all twenty verdicts rather than stopping at the first, and should not be left with a
  half-applied batch and no summary.
  Date: 2026-08-16

- Decision: The batch exits non-zero when *any* entry failed, not only when an entry was
  refused.
  Rationale: Distinguishing refusals from other failures in the counter would be more code
  for a worse outcome — a batch where every entry failed to load would still exit zero.
  A batch install that did not fully succeed should not report success. This changes the exit
  code for pre-existing failure kinds too, which is a behaviour change beyond the refusal
  itself and is called out in `docs/user/CHANGELOG.md` under Changed for that reason.
  Date: 2026-08-16

- Decision: The routine same-source reinstall prints nothing, rather than printing a note at
  verbose level.
  Rationale: See Surprises — the verbose level is not reachable from this command. The plan's
  goal was "a routine upgrade prints nothing at normal verbosity", and removing the warning
  achieves it exactly. The version transition it wanted to show is already visible where it
  matters: `seihou upgrade` prints an old → new table, and `seihou install` prints what it
  installed.
  Date: 2026-08-16

- Decision: Write a new ADR, `docs/adr/0006-the-install-cache-will-not-silently-substitute-an-artifact.md`,
  rather than amending `docs/adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md`.
  Rationale: The plan left this open. ADR 0003's Decision is scoped by its own words to "a
  command that is about to *generate* from an artifact", and its Consequences section draws a
  careful boundary between resolving where an artifact is, deciding whether to generate from
  it, and advisory consumers that never block. Broadening it to cover writes into the cache
  would blur that boundary and give one ADR two override flags. The install-time rule has a
  different subject (what may enter machine-global shared state), a different flag
  (`--force`), and a deliberate exclusion of its own (namespacing the cache by repository)
  worth recording where a future contributor will find it. ADR 0003 gains a cross-reference
  and keeps its scope, which also leaves it the clean home for
  `docs/plans/83-guard-the-agent-path-against-stale-and-substituted-artifacts.md`, whose work
  genuinely is the same generate-time decision extended to the agent path.
  Date: 2026-08-16

- Decision: Refuse `UnknownSource` — an existing installation with no readable
  `.seihou-origin.json` — on the same footing as `DifferentSource`.
  Rationale: IR-4 argues from "seihou cannot prove these are the same artifact". That is
  exactly true of an entry with no provenance, and the consequence of guessing wrong is the
  same: every project on the machine that resolved the name is affected. The message says
  provenance is missing rather than naming a URL, and `--force` overrides it.
  Date: 2026-08-16


## Outcomes & Retrospective

Complete. `seihou install` reads the provenance it is about to destroy and refuses a
different-source or unprovenanced overwrite; `--force` overrides and prints what it overrode.

Against the acceptance criteria in Validation and Acceptance:

- **Automated.** `cabal test seihou-cli-test` passes at 495 tests, 15 of them new in
  `seihou-cli/test/Seihou/CLI/InstallCollisionSpec.hs`. `cabal test seihou-core-test` passes
  at 1056. The decisive assertion is "refuses a different source and leaves the existing
  installation untouched": a marker file written into the existing directory before the call
  still reads back verbatim afterwards, the incoming file is absent, and the provenance file
  still names the original URL.
- **Classification.** Every case the plan lists is covered: absent directory, matching URL
  (including `.git` and trailing-slash spellings), differing URL, missing provenance file,
  and unparseable provenance file.
- **Mechanical checks.** `nix/check-record-conventions.sh` and
  `nix/check-cli-module-placement.sh` both pass. The new code is in the CLI library and the
  flag is in the executable, as the plan required.

The by-hand two-repository walk was not performed. The automated spec drives
`installModuleDirInto` directly against a temporary cache with both repositories' provenance
laid out, which exercises the same classification and the same refusal-before-deletion
ordering without needing two throwaway git repositories; what the walk would add is coverage
of `seihou install`'s clone-and-discover path, which this plan does not change. Worth running
once when a session already has the fixture — `docs/plans/85-fan-out-a-blueprint-migration-edge-to-entailed-cohort-edges.md`
needs two repositories publishing related blueprints and is the natural place.

Lessons worth carrying into the sibling plans:

- **Check what a logging helper's arguments actually mean before planning around them.**
  `logIO LogVerbose` reads like "log at verbose level" and means "the user configured verbose
  level". A plan written against the misreading specified behaviour the command could not
  produce.
- **A plan that says "export this private function" is really saying "these callers must
  agree".** EP-81 satisfied that requirement in a better place than either plan named. When a
  coordination note points at a specific line, check whether the requirement behind it has
  already been met differently before doing what it literally says.
- **Prefer a parameter to an environment variable when a test needs to redirect a global.**
  The env-var route works and is a concurrency hazard; the parameter route costs one wrapper
  and is unconditionally safe.


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
artifact. Import `normalizeOriginUrl` from `Seihou.Core.ArtifactIdentity` rather than writing
a second copy — two normalisers that drift apart would produce a refusal on the install path
and no mismatch on the guard path, or the reverse.

That module is where `docs/plans/81-record-artifact-origin-for-agent-applied-artifacts.md`
put the function; it was previously private to `Seihou.CLI.ManifestGuard`, and moved into
`seihou-core` because the blueprint-migration receipt ledger needs the same comparison and
cannot import from `seihou-cli`.

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
- `SameSource mVersion` — proceed silently. Delete the current warning rather than demoting
  it: `logIO`'s first argument is the *configured* log level, not the message's, so
  `logIO LogVerbose` prints unconditionally, and `InstallOpts` has no verbosity field for
  `installModuleDir` to consult anyway. The goal — a routine reinstall printing nothing at
  normal verbosity — is met by removing the line, and the calling command already reports
  what it installed on the next line.
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

Do **not** redirect `XDG_CONFIG_HOME`. It works, but it is process-global and `tasty` runs
specs concurrently, so mutating it would silently affect whatever else is in flight. Test
`installModuleDirInto`, which takes the cache root as its first argument;
`installModuleDir` is a thin wrapper that resolves the XDG root and delegates, so every
command keeps calling the same function it always did.

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

Update `docs/improvement-requests/refuse-to-overwrite-an-installation-from-a-different-source.md`.
Its terminal status is `status: completed` — the bundle's profile does not accept
`implemented` — and that value requires `completedAt` (RFC-3339 UTC) and recommends
`resolution`. Set those, add
`targetPlan: docs/plans/82-refuse-to-overwrite-an-installation-from-a-different-source.md`,
and add a closing section naming this plan. That bundle is a profile-governed OKF bundle
registered in `mori.dhall`, so maintain its reserved `log.md` with `okf log add` and
validate:

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

formatInstallOverride :: String -> Text -> InstallCollision -> Text

summarizeInstallRefusal :: Text -> InstallCollision -> Text

installedRoot :: IO FilePath

installModuleDir ::
  Bool -> FilePath -> String -> Text -> Maybe Text -> Maybe Text -> [Text] -> IO InstallOutcome

installModuleDirInto ::
  FilePath -> Bool -> FilePath -> String -> Text -> Maybe Text -> Maybe Text -> [Text] -> IO InstallOutcome
```

`normalizeOriginUrl` is imported from `Seihou.Core.ArtifactIdentity`, where
`docs/plans/81-record-artifact-origin-for-agent-applied-artifacts.md` put it. Nothing in
`Seihou.CLI.ManifestGuard` changes.

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
`docs/plans/81-record-artifact-origin-for-agent-applied-artifacts.md` — the location of
`normalizeOriginUrl` — and one soft relationship with
`docs/plans/83-guard-the-agent-path-against-stale-and-substituted-artifacts.md`, which
detects at use time the collision this plan prevents at install time.


## Revision Notes

**2026-08-16 — implementation.** Four things in the plan as written changed on contact with
the code; the sections above have been updated to match what was built, and the reasoning for
each is in the Decision Log.

Milestone 1 said to export `normalizeOriginUrl` from `seihou-cli/src/Seihou/CLI/ManifestGuard.hs`,
with a coordination note that EP-81 needed the same export. EP-81 landed first and moved the
function into `seihou-core/src/Seihou/Core/ArtifactIdentity.hs` instead, because two of its
own call sites are in `seihou-core`. This plan imports it from there and touches
`ManifestGuard` not at all.

Milestone 2 said to replace the overwrite warning with a verbose-level note naming the version
transition. That is not reachable: `logIO`'s first argument is the configured log level rather
than the message's, and `seihou install` has no verbosity flag. The same-source case is silent
instead, which is what "a routine upgrade prints nothing at normal verbosity" asked for.

Milestone 4 said to redirect `XDG_CONFIG_HOME` in the test sandbox, with a fallback of
extracting the cache root as a parameter. The fallback is what shipped, unconditionally:
`tasty` runs specs concurrently and an environment variable is process-global.
`installModuleDirInto` takes the root; `installModuleDir` resolves XDG and delegates.

Milestone 5's `status: implemented` is `status: completed`, the only terminal value the
bundle's profile accepts, and it pulls in `completedAt` and `resolution`.

Two things were added beyond the plan. `UnknownSource` — an existing installation with no
readable provenance — is refused alongside `DifferentSource`, because seihou cannot prove
those are the same artifact either. And a registry batch now exits non-zero when any entry
failed, which the plan implied ("collect and report, then exit nonzero") and which also
changes the exit code for pre-existing failure kinds; that is called out in
`docs/user/CHANGELOG.md`.
