---
id: 98
slug: repair-machine-local-artifact-origins-and-stop-recording-them
title: "Repair machine-local artifact origins and stop recording them"
kind: exec-plan
created_at: 2026-09-18T14:19:24Z
intention: "intention_01m2tanyfae9ftvcqmaygv0960"
provenance:
  created_by:
    model: "claude-opus-5[1m]"
    harness: "claude-code"
    at: 2026-09-18T14:19:24Z
  revisions:
    - model: "claude-opus-5[1m]"
      harness: "claude-code"
      at: 2026-09-18T14:32:33Z
      mode: "implement"
      note: "Implement M1-M5"
---

# Repair machine-local artifact origins and stop recording them

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Seihou's manifest, `.seihou/manifest.json`, is committed to git and must mean the same
thing on every machine (ADR 0001). For every module, recipe, and blueprint it applied, it
records an *origin*: where the artifact came from, normally a git URL such as
`https://github.com/shinzui/seihou-modules.git`.

A real project, `mori://tan/mls-service-v2`, had `nix-haskell-flake`'s origin recorded as
a directory on one developer's machine (`…/bokuno/seihou-modules`). The module had been
installed with `seihou install <path-to-a-local-checkout>`. `seihou install` stores its
argument verbatim as the installed copy's `sourceUrl`, and every command that records
applied state copies that `sourceUrl` into the manifest. Later the module was reinstalled
from GitHub. From then on, the installed copy's origin disagreed with the manifest, and
certifying a shared `.gitignore` failed with "installed here from a different origin than
recorded". An agent had to hand-edit the manifest to fix it.

After this plan, three things are true:

1. **The state cannot be created again.** `seihou install <local path>` records the
   checkout's own published remote when the installed commit is on that remote. When it
   cannot vouch for a remote, the manifest records the artifact's origin as unknown
   (`LocalOrigin`) instead of a path, because no path ever reaches the manifest.
2. **Existing damage has a command.** `seihou manifest repair-origins` finds every origin
   recorded as a machine-local path, proposes a remote URL with the evidence for it,
   prints the report, and rewrites the manifest. `--dry-run` shows the report without
   writing, and `--set NAME=URL` supplies a URL seihou could not work out:

   ```text
   $ seihou manifest repair-origins --dry-run
   /Users/alice/Keikaku/bokuno/seihou-modules
     -> https://github.com/shinzui/seihou-modules.git
        evidence: the installed copy of nix-haskell-flake records this remote
        records: modules[nix-haskell-flake], 2 application instances
   --dry-run: nothing was written.
   ```

3. **Failures point at the command.** When a guard or certification message is caused by
   a machine-local recorded origin, it says to run `seihou manifest repair-origins`.


## Progress

- [x] M1: `isMachineLocalOriginUrl` in `Seihou.Core.ArtifactIdentity`; `detectArtifactOrigin` maps a machine-local `sourceUrl` to `LocalOrigin`; tests. (2026-09-18: new `seihou-core/test/Seihou/Core/ArtifactIdentitySpec.hs`; `cabal test seihou-core` 1154 passed.)
- [x] M2: `seihou install <local path>` records the checkout's remote when the installed commit is published there; otherwise warns; tests. (2026-09-18: `resolveRecordedSource` in `InstallShared`; `InstallSourceSpec` (6 cases) and the two install cases of `RepairOriginsE2ESpec` pass, including a same-source reinstall from the recorded remote.)
- [x] M3: `seihou manifest repair-origins [--dry-run] [--set NAME=URL]` in `Seihou.CLI.ManifestRepairOrigins`; unit and E2E tests. (2026-09-18: `ManifestRepairOriginsSpec` 20 cases; `RepairOriginsE2ESpec` reproduces the reported certification failure, repairs it, and shows the targeted update succeeding; `cabal test seihou-cli` 677 passed.)
- [x] M4: Guard, certification-gap, and status messages point at the command for machine-local origins. (2026-09-18: `machineLocalOriginNote` in `ManifestGuard`; asserted in `ManifestGuardSpec`, `StatusSpec`, and the `RepairOriginsE2ESpec` update output; `cabal test seihou-cli` 682 passed.)
- [ ] M5: Docs (`docs/cli/manifest.md`, `docs/cli/install.md`, `docs/user/manifest-upgrade.md`), both changelogs, ADR 0001 and ADR 0005 amendments; full validation.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Every write of an origin into the manifest goes through `detectArtifactOrigin`.
  That function now turns a `sourceUrl` that is a machine-local path into
  `LocalOrigin <name>` rather than `RemoteOrigin <path>`.
  Rationale: `detectArtifactOrigin` (`seihou-core/src/Seihou/Core/ArtifactOriginDetect.hs`)
  is already documented as the single funnel for manifest origins. `LocalOrigin` is the
  existing constructor for "provenance unknown". `ManifestGuard.originRelation` treats it
  as unverifiable rather than a mismatch, and update and certification resolve it by name,
  so nothing downstream breaks and nothing is invented. A path means nothing on another
  machine and turns into a false mismatch on this one once the artifact is reinstalled
  from its real remote. That is exactly the failure reported.
  Date: 2026-09-18

- Decision: When installing from a local checkout, record the checkout's `origin` remote
  only if the installed commit is reachable from a remote-tracking branch. Otherwise keep
  the path in the machine-local `.seihou-origin.json`, as today, and print a warning.
  Rationale: `seihou install` clones the checkout's committed `HEAD`. If that commit is
  published, the remote genuinely holds the installed content, and recording it is true.
  If it is not published (the module author iterating locally), claiming the remote would
  be false provenance. The install cache is machine-local by design, so a path there is
  fine. M1 keeps it out of the manifest.
  Date: 2026-09-18

- Decision: `repair-origins` rewrites origins by URL, not by record. Every origin whose
  URL equals a machine-local path (compared after normalization) is rewritten to the same
  new URL, across all six origin-bearing record kinds.
  Rationale: Blueprint migration receipts use the origin as part of their identity
  (ADR 0002, ADR 0008). Rewriting some records for a URL and not others would split one
  artifact into two identities. A URL-level mapping keeps every identity consistent and
  makes the report short.
  Date: 2026-09-18

- Decision: `repair-origins` is an explicit, reporting command and never runs
  automatically. It requires a manifest at the current schema and refuses an older one,
  naming `seihou manifest upgrade`.
  Rationale: Choosing a remote for a recorded path is inference, which ADR 0005 keeps
  explicit and reviewable. Requiring the current schema lets the command work on the
  decoded `Manifest` with typed traversals instead of raw JSON paths. The schema 6→7
  step is lossless and cheap to run first.
  Date: 2026-09-18

- Decision: Evidence for a proposed URL, in priority order:
  1. the recorded path exists here and its git `origin` remote is a non-local URL;
  2. an installed copy of an artifact recorded under that URL has a non-local `sourceUrl`
     and the same `repoName`;
  3. `--set NAME=URL` from the user.
  If two artifacts recorded under the same path suggest different remotes, report a
  conflict and write nothing for that path.
  Rationale: Each source is something this machine can observe. A conflict means one
  local checkout fed two unrelated repositories, and choosing between them would be a guess.
  Date: 2026-09-18

- Decision: `resolveRecordedSource` asks only whether HEAD is on an `origin/*`
  remote-tracking branch (`git branch -r --contains HEAD --list 'origin/*'`), not on any
  remote's branch, and adds a fourth `RecordLocalPath` reason: "its origin remote <url> is
  itself a local path". It also accepts `file://` and `file:` arguments by stripping the
  scheme before calling `git -C`.
  Rationale: The URL recorded is `origin`'s. A commit that is only on `upstream/main` is
  not proven to be at `origin`, so recording `origin` for it would be false provenance. A
  checkout cloned from another local directory has a path as its remote, which is no more
  portable than the checkout's own path.
  Date: 2026-09-18

- Decision: The single-artifact install paths still derive a default install name from
  the argument as given (`parseModuleName source`); only the recorded URL changes.
  Rationale: Changing the install name for local installs would silently move where an
  artifact lands in the cache. That is out of scope and unrelated to provenance.
  Date: 2026-09-18

- Decision: The E2E tests reach the fake `https://example.invalid/...` remote through
  git's environment configuration (`GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_0`/`GIT_CONFIG_VALUE_0`
  setting `url.<dir>.insteadOf`), so commands that clone the recorded remote run offline.
  Rationale: A bare repository's path would itself count as machine-local, and a network
  URL is unavailable in tests. `insteadOf` lets the manifest record an https URL while git
  reads a local directory.
  Date: 2026-09-18


- Decision: Evidence agrees when the URLs name the same repository regardless of
  transport (`sameRepository`: `git@github.com:o/r.git`, `ssh://git@github.com/o/r` and
  `https://github.com/o/r.git` agree). When they agree, the URL written is the installed
  copy's spelling if there is one, otherwise the checkout remote's.
  Rationale: The reported case is exactly a local checkout with an ssh remote and a
  GitHub install over https. Comparing normalized URLs would call that a conflict and
  write nothing. The guard compares the manifest with the installed copy through
  `normalizeOriginUrl`, so writing the installed copy's spelling is what makes the guard
  pass on this machine; the checkout remote's spelling would reproduce the mismatch.
  Date: 2026-09-18

- Decision: `OriginSite` carries three fields beyond the interface sketched below: `kind`
  (which of the six record kinds), `recordedUrl` (the URL before normalization), and
  `definitionFile` (`module.dhall`, `recipe.dhall`, or `blueprint.dhall`). `RepairOutcome`
  gains `RepairUnwritten` for a real run in which no path had a remote.
  Rationale: `kind` lets the report count instances and migration receipts instead of
  listing each. `recordedUrl` is the path evidence (a) must inspect, since normalization
  strips a trailing `.git`. `definitionFile` lets evidence (b) find the installed copy with
  the same `resolveArtifactOrigin` lookup the guard uses. Printing
  "--dry-run: nothing was written." for a run that was not a dry run would be wrong.
  Date: 2026-09-18

- Decision: `--set NAME=URL` for a name recorded under no local path is refused up front,
  like a machine-local URL.
  Rationale: Such an override would silently do nothing, and it is almost always a typo.
  Date: 2026-09-18


- Decision: The repair sentence is appended to every guard block and one-line summary
  whose recorded origin is a path, not only to origin mismatches, and a mismatch against a
  recorded path no longer suggests `seihou install <path>`. `seihou status` gets the
  sentence through `summarizeCheck` rather than through `StatusRender.adviceCommand`.
  Rationale: A recorded path also explains an unresolvable or unverifiable verdict, and
  installing another machine's path is never the remedy. `adviceCommand` only renders
  advice derived from outdated-module checks and has no hook for artifact checks;
  `formatArtifactChecks` already prints each `summarizeCheck` line. Plan 97 has not
  landed, so its "path on another machine" reason does not exist yet; 97 should call
  `machineLocalOriginNote` when it adds that reason.
  Date: 2026-09-18


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Seihou is a Haskell project with three Cabal packages. `seihou-core/` holds domain types
and the engine. `seihou-cli/src/` is the `seihou-cli-internal` library, and
`seihou-cli/src-exe/` is the executable. Build with `cabal build all` and test with
`cabal test all` from the repository root. `nix flake check` also runs two checkers:

- `nix/check-cli-module-placement.sh`: library first. A module belongs in `src-exe/` only
  if it imports `Options.Applicative`, `Data.FileEmbed`, `GitHash`, `Paths_seihou_cli`, or
  another executable-only module.
- `nix/check-record-conventions.sh`: strict, unprefixed record fields; `Generic` with an
  explicit deriving strategy; access only through `generic-lens` labels
  (`x ^. #field`, `x & #field .~ v`); and `import Data.Generics.Labels ()` in each module
  that uses labels.

**Origins.** `ArtifactOrigin` (`seihou-core/src/Seihou/Core/Types.hs`) is
`RemoteOrigin {originUrl, artifactName, repoName}`, `ProjectOrigin {relativePath}` for
artifacts inside the project, or `LocalOrigin {artifactName}` for unknown provenance.
Six manifest record types carry one:

- `AppliedModule.origin`, in `Manifest.modules`;
- `AppliedComposition.targetOrigin`, in `Manifest.applications`;
- `AppliedInstanceState.origin`, inside each application's `instances`;
- `AppliedRecipe.origin`, in `Manifest.recipe`;
- `AppliedBlueprint.origin`, in `Manifest.blueprint`;
- `AppliedBlueprintMigration.origin`, in `Manifest.blueprintMigrations`.

`seihou-core/src/Seihou/Core/ArtifactIdentity.hs` exports `sameArtifactIdentity`,
`normalizeOriginUrl`, and `normalizeProjectPath`. Every origin comparison uses them.

**How an origin is recorded.** `seihou-core/src/Seihou/Core/ArtifactOriginDetect.hs`
exports `detectArtifactOrigin :: FilePath -> FilePath -> IO ArtifactOrigin`. Given the
project root and an artifact's absolute directory, it returns `ProjectOrigin` if the
directory is inside the project. Otherwise it returns `RemoteOrigin` with the `sourceUrl`
from the directory's `.seihou-origin.json`, or `LocalOrigin` if there is none. It also
exports `readOriginInfo` and `OriginInfo {sourceUrl, repoName, version}`. The existing
spec is `seihou-core/test/Seihou/Core/ArtifactOriginDetectSpec.hs`.

**How install records `sourceUrl`.** `seihou-cli/src-exe/Seihou/CLI/Install.hs` takes the
`GIT-URL` argument (or a history pick) as `source` and clones it with `cloneRepo`
(`seihou-cli/src/Seihou/CLI/InstallShared.hs`, `git clone --depth 1`). `git clone`
accepts a local path, so `seihou install ~/src/seihou-modules` works today. The source is
passed down to `installModuleDir`, and from there to `installRegistryEntry` for
registries. `InstallShared` writes `OriginMeta {sourceUrl = source, ...}` into
`.seihou-origin.json`. `classifyInstallCollision` compares an incoming URL with the
recorded one to refuse a different-source overwrite (ADR 0006). Also note
`recordUrl source` (`Seihou.CLI.InstallHistory`), which saves the argument to install
history. That record is machine-local and is left alone.

**Where the mismatch surfaces.** `seihou-cli/src/Seihou/CLI/ManifestGuard.hs`:
`originRelation` returns `OriginDiffers` for two remote URLs that differ, and
`OriginUnverifiable` for a recorded `LocalOrigin`. `judgeArtifact` then yields
`ArtifactOriginMismatch`, which `formatGuardRefusal` and `summarizeCheck` render.
`seihou-cli/src/Seihou/CLI/ManifestCapabilityUpgrade.hs` `gatherApplicationEvidence`
turns the same mismatch into the reason "module X is installed here from a different
origin than recorded". `seihou-cli/src/Seihou/CLI/StatusRender.hs` renders artifact checks
in `seihou status` (`formatArtifactChecks`).

**The manifest command group.** `seihou-cli/src/Seihou/CLI/Manifest.hs` defines
`data ManifestCommand = ManifestUpgrade ManifestUpgradeOpts` and `handleManifest`. The
parser is `manifestCommandParser` in `seihou-cli/src-exe/Seihou/CLI/Commands.hs` (around
line 1476). `seihou-cli/src/Seihou/CLI/ManifestUpgrade.hs` shows the conventions for an
explicit, reporting manifest rewrite: a testable `run…` function returning an outcome
type, a separate handler that prints and sets the exit code, and an atomic write (see its
`writeDocument`). Read and write the decoded manifest with `manifestFromJSON` and
`manifestToJSON` from `seihou-core/src/Seihou/Manifest/Types.hs`, and check
`version == currentManifestVersion` (7).

**Tests.** `seihou-cli/test/Seihou/CLI/UpdateSpec.hs` exports `prepareSharedPathFixture`,
which builds a two-application project with a private `XDG_CONFIG_HOME`.
`seihou-cli/test/Seihou/CLI/ManifestUpgradeSpec.hs` and
`seihou-cli/test/Seihou/CLI/InstallCollisionSpec.hs` show fixture styles for manifest and
install tests. `seihou-cli/test/Seihou/CLI/SeihouBinary.hs` locates the binary for E2E tests.

**ADRs.**

- [ADR 0001](../adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md): the
  manifest may not record a path meaningful only on the machine that wrote it. A
  `RemoteOrigin` whose URL is a local path violates it; this plan closes that hole.
- [ADR 0002](../adr/0002-artifact-identity-is-origin-url-plus-name.md): identity is origin
  URL plus name. This is why the repair is URL-level and uniform.
- [ADR 0003](../adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md): the guard
  that reports the mismatch. The guard is unchanged; only its message gains a pointer.
- [ADR 0005](../adr/0005-legacy-manifests-convert-through-an-explicit-command.md): inference
  about origins goes through an explicit, reporting command. `repair-origins` follows it.
- [ADR 0006](../adr/0006-the-install-cache-will-not-silently-substitute-an-artifact.md):
  install refuses a different-source overwrite. Recording the remote for a local install
  means a later `seihou install <that remote>` becomes a same-source reinstall rather
  than a refusal. That is the intended effect, and M2 tests it.

Related plans: `docs/plans/97-fetch-a-co-owner-s-recorded-release-to-certify-shared-write-evidence.md`
leaves a comment where a machine-local origin blocks fetching evidence. M4 adds the
`repair-origins` pointer there if 97 has landed; otherwise 97 picks it up.
`docs/plans/96-add-seihou-agent-upgrade-for-agent-assisted-module-upgrades-that-repair-manifest-state.md`
uses this command in its diagnosis and playbook.


## Plan of Work

### Milestone 1: No path reaches the manifest

Add `isMachineLocalOriginUrl :: Text -> Bool` to
`seihou-core/src/Seihou/Core/ArtifactIdentity.hs`. It is true when the stripped text starts
with `/`, `./`, `../`, `~`, or `file:`, or is a Windows drive path (`C:\` or `C:/`). It
is false for URLs with a scheme (`https://`, `ssh://`, `git://`) and for scp-style
`user@host:path`. Put a table of cases in a new or existing spec in
`seihou-core/test/Seihou/Core/` (check for an `ArtifactIdentitySpec`; create it if absent
and register it in `seihou-core/test/Main.hs` and the cabal file).

In `detectArtifactOrigin`, when `.seihou-origin.json` exists but its `sourceUrl` satisfies
`isMachineLocalOriginUrl`, return `LocalOrigin name` instead of `RemoteOrigin`. Update the
function's Haddock ordered list to say so and why. Add a case to
`ArtifactOriginDetectSpec`: a directory whose origin file says
`"sourceUrl": "/Users/someone/src/modules"` detects as `LocalOrigin`.

Acceptance: `cabal test seihou-core` passes. Running any module installed from a local
path (E2E in M2) produces a manifest with no `/`-leading `originUrl`.

### Milestone 2: Install records a publishable remote

In `seihou-cli/src-exe/Seihou/CLI/Install.hs`, before cloning, resolve the provenance to
record. Put the logic in the library so it can be tested: a new function in
`seihou-cli/src/Seihou/CLI/InstallShared.hs`,

```haskell
data RecordedSource
  = -- | Record this URL; the clone reads from the argument as given.
    RecordSource !Text
  | -- | A local checkout whose installed commit is published at this remote.
    RecordPublishedRemote !Text !Text -- remote url, local path
  | -- | A local path with no remote that holds the installed commit.
    RecordLocalPath !Text !Text -- path as given, why no remote
  deriving stock (Eq, Show, Generic)

resolveRecordedSource :: Text -> IO RecordedSource
```

For an argument that is not machine-local, the result is `RecordSource arg`. For a
machine-local path, expand `~`, then run:

- `git -C <path> rev-parse HEAD`
- `git -C <path> remote get-url origin`
- `git -C <path> branch -r --contains HEAD`

If the remote exists, is not itself machine-local, and the last command prints at least
one line, the result is `RecordPublishedRemote remote path`. Otherwise it is
`RecordLocalPath` with the reason: "no origin remote", "HEAD is not on any remote
branch; push it first", or "not a git repository".

The clone still reads from the argument. Pass the URL to record down to where
`OriginMeta` is built, instead of `source`. Thread it through `installModuleDir` and
`installRegistryEntry`; the compiler lists the call sites. Use the same recorded URL for
`classifyInstallCollision`, so that reinstalling from GitHub after a local install whose
remote was recorded is a same-source upgrade. Print:

- for `RecordPublishedRemote`:
  `note: recording origin <remote> (the 'origin' remote of <path>, which contains the installed commit)`
- for `RecordLocalPath`:
  `warning: <path> is recorded as a local path (<reason>); projects generated from it record its origin as unknown`

Library tests in `seihou-cli/test/Seihou/CLI/InstallCollisionSpec.hs`, or a new
`InstallSourceSpec`, cover all three outcomes. Build a bare repository to act as the
"remote", clone it, and commit:

- a clone with pushed HEAD gives `RecordPublishedRemote`. A bare repository's path or
  `file://` URL counts as machine-local by design, so the test cannot use it as the
  remote. Instead, after cloning, set the clone's remote URL to a fake
  `https://example.invalid/r.git` with `git remote set-url origin`, and create the
  remote-tracking ref with `git update-ref refs/remotes/origin/main HEAD`. This
  exercises the logic without network, and the expected result is
  `RecordPublishedRemote "https://example.invalid/r.git" <path>`.
- an extra unpushed commit gives `RecordLocalPath` with the push reason.
- no remote gives `RecordLocalPath` with "no origin remote".

Add one E2E in a new `seihou-cli/test/Seihou/CLI/RepairOriginsE2ESpec.hs` (shared with
M3). Install from a local path with a published HEAD, then run a module. The manifest
records the fake https remote. `.seihou-origin.json` says the same.

### Milestone 3: `seihou manifest repair-origins`

Create `seihou-cli/src/Seihou/CLI/ManifestRepairOrigins.hs` (library). The core is pure
over a decoded `Manifest` plus gathered evidence. The IO wrapper gathers evidence and
writes.

1. `localOriginUrls :: Manifest -> Map Text [OriginSite]` walks all six origin fields and
   groups every `RemoteOrigin` whose `originUrl` satisfies `isMachineLocalOriginUrl`,
   keyed by normalized URL. An `OriginSite` records which record it is (for the report
   line `records: modules[nix-haskell-flake], 2 application instances`) and the artifact
   name and `repoName`. Write it as a traversal with lenses over each list. Do not use
   `show` for the report text.
2. `gatherOriginEvidence :: FilePath -> [FilePath] -> Map Text [OriginSite] -> IO (Map Text [OriginEvidence])`,
   for each local URL:
   - (a) If the path exists and `git -C <path> remote get-url origin` returns a
     non-local URL, add `FromCheckoutRemote url`.
   - (b) For each site's artifact name, find its installed directory in the search paths
     (`Seihou.Core.Module.defaultSearchPaths`; reuse whatever lookup
     `ManifestGuard.checkRecordedArtifact` uses). If `readOriginInfo` gives a non-local
     `sourceUrl` whose `repoName` equals the site's `repoName` (or the site has none),
     add `FromInstalledCopy name url`.
3. `planRepair :: Map Text [OriginSite] -> Map Text [OriginEvidence] -> [(Text, Text)] -> [RepairDecision]`,
   where the third argument is the `--set` overrides as `(artifact name, URL)` pairs. An
   override applies to the local URL under which that artifact is recorded. Each local URL becomes:
   - `Rewrite old new evidence sites` when an override applies, or when all evidence
     agrees on one normalized URL;
   - `Conflicting old [(url, evidence)]` when the evidence disagrees and there is no
     override;
   - `Unresolved old sites` when there is no evidence.
   An override whose URL is machine-local is rejected up front with a message.
4. `applyRepair :: [RepairDecision] -> Manifest -> Manifest` rewrites every
   `RemoteOrigin` whose normalized URL is an `old` of a `Rewrite`. It sets `originUrl` to
   the new URL and keeps `artifactName`, and sets `repoName` from the installed copy's
   origin info when that evidence supplied it, otherwise keeps it. It is pure and total.
5. `runRepairOrigins :: RepairOriginsOpts -> IO RepairOutcome` reads the manifest from the
   current directory. It returns `RepairFailed` with a message naming
   `seihou manifest upgrade` for a non-current schema or an undecodable document. It
   returns `RepairNotNeeded` when there are no local URLs. Otherwise it plans, and unless
   `dryRun` is set and there is at least one `Rewrite`, it writes `applyRepair`'s result
   with `manifestToJSON` atomically (write a temporary file beside the manifest, then
   rename). Then it returns `RepairWritten decisions` or `RepairWouldWrite decisions`.
6. `renderRepairOutcome :: RepairOutcome -> Text`. The report format is shown in Purpose.
   Unresolved and conflicting entries end with the remedy
   `pass --set <name>=<url> for the artifact recorded under this path`. The handler exits
   1 if any decision is `Unresolved` or `Conflicting`, even when others were written,
   because the user still has work to do. It exits 0 otherwise.

Wire it up:

- Add `ManifestRepairOrigins RepairOriginsOpts` to `ManifestCommand` in
  `seihou-cli/src/Seihou/CLI/Manifest.hs`.
- Add a `repair-origins` command to `manifestCommandParser` in `Commands.hs`, with
  `--dry-run` and a repeatable `--set NAME=URL` parsed into `(Text, Text)` pairs, reusing
  the `--var` parser style. Include help text.
- Run `cabal build` and follow the completion protocol tests if any enumerate manifest
  subcommands.

Tests:

- `seihou-cli/test/Seihou/CLI/ManifestRepairOriginsSpec.hs` (pure) covers:
  - grouping across all six record kinds;
  - uniform rewrite of every site sharing one URL;
  - agreement between checkout and installed evidence;
  - a conflict;
  - an unresolved URL;
  - an override winning over evidence;
  - a local override rejected;
  - `repoName` preservation;
  - blueprint migration receipts rewritten together with the blueprint, so that
    `sameArtifactIdentity` still pairs them.
- `RepairOriginsE2ESpec` (binary) uses `prepareSharedPathFixture`. It rewrites beta's
  origins in the manifest to `/nonexistent/seihou-modules`, and gives beta's installed
  `.seihou-origin.json` the fake https remote with a matching `repoName`. Then:
  - `manifest repair-origins --dry-run` exits 0, prints the rewrite with
    `evidence: the installed copy of beta`, and leaves the manifest byte-identical.
  - Without `--dry-run`, it rewrites. A following `seihou update alpha --dry-run` no
    longer reports an origin mismatch for beta.
  - With the installed origin file removed, the result is unresolved and exits 1; with
    `--set beta=https://example.invalid/r.git` it writes and exits 0.

### Milestone 4: Point failures at the repair

Where a message comes from a recorded `RemoteOrigin` whose URL satisfies
`isMachineLocalOriginUrl`, append the sentence
`The manifest records <path>, a path on the machine that wrote it; run 'seihou manifest repair-origins'.`
Do this in:

- `ManifestGuard` (`formatGuardRefusal`'s block for `ArtifactOriginMismatch`, and
  `summarizeCheck`);
- the `loadInstance` reasons in `ManifestCapabilityUpgrade.gatherApplicationEvidence`
  (the "different origin than recorded" reason, and plan 97's "path on another machine"
  reason if it exists);
- `seihou status` advice through `StatusRender.adviceCommand`, if it has a place for a
  command.

Assert the sentence in `ManifestGuardSpec`, `UpdateRenderSpec` (if the text flows
there), and one `StatusSpec` case. Messages for remote-URL mismatches stay unchanged.

### Milestone 5: Documentation, ADRs, validation

- `docs/cli/manifest.md`: a `## seihou manifest repair-origins` section: usage, options,
  evidence order, report format, exit codes, and why it is explicit (ADR 0005). Update the
  subcommand table.
- `docs/cli/install.md`: a paragraph on installing from a local path. It records the
  checkout's remote when the commit is pushed; otherwise it warns, and generated projects
  record the origin as unknown.
- `docs/user/manifest-upgrade.md`: a short section on repairing path origins.
- `docs/user/CHANGELOG.md` and `CHANGELOG.md` (Unreleased): Added `repair-origins`;
  Changed install provenance for local paths; Fixed machine-local paths reaching the
  manifest.
- Amend [ADR 0001](../adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md)
  with a dated paragraph. A `sourceUrl` that is a path is recorded as `LocalOrigin`;
  install records a published remote for a local checkout; `repair-origins` repairs older
  manifests.
- Add a dated line to [ADR 0005](../adr/0005-legacy-manifests-convert-through-an-explicit-command.md)
  naming `repair-origins` as a second explicit, inference-bearing command under the same
  rule.
- Grep `docs/` for `different origin than recorded`, `sourceUrl`, and `seihou install` with
  a path, and update any page describing the old behavior.
- Full validation per Concrete Steps.


## Concrete Steps

From the repository root:

```bash
cabal build all
cabal test seihou-core
cabal test seihou-cli --test-options='-p "RepairOrigins"'
cabal test seihou-cli --test-options='-p "InstallCollision"'
```

Before each commit:

```bash
nix fmt -- --fail-on-change
cabal build all
cabal test all
nix flake check
```

Manual check against the reporting project, if it still records a path. Record the output
in Outcomes:

```bash
SEIHOU=$(cabal list-bin seihou)
cd /path/to/mls-service-v2       # checkout of mori://tan/mls-service-v2
"$SEIHOU" manifest repair-origins --dry-run
git diff --stat                  # expect: nothing
```

Expected: one rewrite from the local seihou-modules path to
`https://github.com/shinzui/seihou-modules.git`, with evidence from the installed copy.

Commit per milestone with trailers:

```text
feat(manifest): add repair-origins for origins recorded as local paths

ExecPlan: docs/plans/98-repair-machine-local-artifact-origins-and-stop-recording-them.md
Intention: intention_01m2tanyfae9ftvcqmaygv0960
```


## Validation and Acceptance

1. `cabal test all` passes with the new and extended specs.
2. After installing from a local checkout whose HEAD is pushed, and running a module, the
   manifest records the remote URL. With an unpushed HEAD, it records `LocalOrigin`.
   Neither manifest contains a `/`-leading `originUrl`.
3. On a manifest that records a path, `seihou manifest repair-origins --dry-run` prints
   the proposed rewrite and its evidence and changes nothing. Without `--dry-run` it
   rewrites every affected record consistently. Afterwards, the update that previously
   failed on an origin mismatch no longer does.
4. Unresolved paths exit 1 with the `--set` remedy, and `--set` resolves them.
5. The guard's mismatch message for a path origin names `seihou manifest repair-origins`.
6. `nix flake check` and `nix fmt -- --fail-on-change` pass.


## Idempotence and Recovery

`repair-origins` is idempotent. After a successful run there are no machine-local URLs
left, and a second run reports `nothing to repair`. The write is atomic (temporary file
plus rename), and the manifest is in git, so `git checkout -- .seihou/manifest.json`
undoes it. `--dry-run` never writes. The install change affects only new installs.
Existing `.seihou-origin.json` files are not rewritten; `repair-origins` evidence (b)
simply does not find a remote in them. M1's write-side mapping applies from the next
command that records applied state, and it never rewrites existing records by itself.


## Interfaces and Dependencies

No new package dependencies. `git` must be on `PATH`.

```haskell
-- seihou-core/src/Seihou/Core/ArtifactIdentity.hs
isMachineLocalOriginUrl :: Text -> Bool

-- seihou-cli/src/Seihou/CLI/InstallShared.hs
data RecordedSource = RecordSource !Text | RecordPublishedRemote !Text !Text | RecordLocalPath !Text !Text
resolveRecordedSource :: Text -> IO RecordedSource
recordedSourceUrl :: RecordedSource -> Text

-- seihou-cli/src/Seihou/CLI/ManifestRepairOrigins.hs
data RepairOriginsOpts = RepairOriginsOpts
  { dryRun :: !Bool,
    overrides :: ![(Text, Text)] -- artifact name, URL
  }
  deriving stock (Eq, Show, Generic)

data OriginSite = OriginSite
  { location :: !Text, -- e.g. "modules[nix-haskell-flake]"
    artifactName :: !Text,
    repoName :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)

data OriginEvidence
  = FromCheckoutRemote !Text
  | FromInstalledCopy !Text !Text !(Maybe Text) -- artifact name, url, repoName
  | FromOverride !Text !Text -- artifact name, url
  deriving stock (Eq, Show, Generic)

data RepairDecision
  = Rewrite !Text !Text ![OriginEvidence] ![OriginSite] -- old, new
  | Conflicting !Text ![OriginEvidence] ![OriginSite]
  | Unresolved !Text ![OriginSite]
  deriving stock (Eq, Show, Generic)

data RepairOutcome
  = RepairNotNeeded
  | RepairWouldWrite ![RepairDecision]
  | RepairWritten ![RepairDecision]
  | RepairFailed !Text
  deriving stock (Eq, Show, Generic)

localOriginUrls :: Manifest -> Map Text [OriginSite]
planRepair :: Map Text [OriginSite] -> Map Text [OriginEvidence] -> [(Text, Text)] -> [RepairDecision]
applyRepair :: [RepairDecision] -> Manifest -> Manifest
runRepairOrigins :: RepairOriginsOpts -> IO RepairOutcome
renderRepairOutcome :: RepairOutcome -> Text
handleRepairOrigins :: RepairOriginsOpts -> IO ()

-- seihou-cli/src/Seihou/CLI/Manifest.hs
-- ManifestCommand gains: | ManifestRepairOrigins RepairOriginsOpts
```
