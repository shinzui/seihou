---
id: 97
slug: fetch-a-co-owner-s-recorded-release-to-certify-shared-write-evidence
title: "Fetch a co-owner's recorded release to certify shared-write evidence"
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
      at: 2026-09-18T16:43:19Z
      mode: "implement"
      note: "Implemented milestones 1-4"
---

# Fetch a co-owner's recorded release to certify shared-write evidence

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Seihou records in `.seihou/manifest.json` (the *manifest*) how the owners of each generated
file write it. When two recorded applications both write a file such as `.gitignore`,
a *targeted* update (`seihou update <target>`, which updates only the named applications)
needs to know whether every owner writes that file only through additive patches. If so,
updating one owner cannot disturb the other. When the manifest does not yet know the
answer (`sharedWriteMode: "unknown"`), the update works it out. It compiles each other
owner, called a *co-owner*, from the exact version the manifest records and reads which
operations reach the file.

Today that compilation only looks in the machine's install cache,
`~/.config/seihou/installed/<name>/`. The cache holds one version per name, normally the
newest. So as soon as a user runs `seihou upgrade`, every project that recorded an older
version of a co-owner fails with `shared_write_evidence_unavailable`:

```text
Update failed [shared_write_evidence_unavailable]: Install the recorded version of each
application below, then update again: ... nix-haskell-flake: module nix-haskell-flake is
version 0.24.0 here but the manifest records version 0.13.2 ...
```

This happened in a real project, `mori://tan/mls-service-v2`. An agent had to unpack
`nix-haskell-flake` 0.13.2 from its repository, swap it into the global cache, run the
update, and restore 0.24.0. The failure will recur for every project and every co-owner
whose recorded version trails the cache.

After this plan, the update gets the recorded release itself. When a co-owner's recorded
origin is a remote git repository, seihou clones that repository into the update's
private temporary directory and finds the commit at which the co-owner declares the
recorded version. It compiles the co-owner from there and never touches the install
cache. The same targeted update then succeeds and prints how it obtained the evidence:

```text
Manifest:    .gitignore evidence unknown -> additive-only
             (nix-haskell-flake 0.13.2 read from https://github.com/shinzui/seihou-modules.git at 08191d3)
```

When no commit declares the recorded version, the update still refuses as it does today,
with a message that says what was searched.


## Progress

- [x] (2026-09-18) M1: `Seihou.CLI.RecordedRelease` locates the newest commit at which a repository declares a given artifact at a given version (pure selection plus git plumbing), with tests against a local fixture repository.
- [x] (2026-09-18) M2: `gatherApplicationEvidence` falls back to a fetched recorded release, with an `EvidencePolicy` parameter; update and manifest upgrade pass a session directory.
- [x] (2026-09-18) M2: Evidence provenance reaches the human and JSON update output.
- [x] (2026-09-18) M3: E2E: the BUG-shaped fixture (co-owner installed at a newer version) updates cleanly; the no-matching-commit case refuses with the new message.
- [ ] M4: Docs (`docs/cli/update.md`, `docs/cli/manifest.md`), both changelogs, ADR 0012 amendment, ADR 0003 cross-reference; full validation.


## Surprises & Discoveries

- Candidate revisions cannot be ordered by committer date. Test fixtures make
  several commits within one second, and `git log --no-walk=sorted` then orders
  them arbitrarily, so a removing commit and its parent could swap places.
  Evidence: the plan's step 2 ordering; fixed before the first test run by
  ordering with `git rev-list --all --topo-order`, which puts children before
  parents regardless of timestamps.
- The applied (non-dry-run) JSON output of `seihou update` has no
  `manifestPreparation` object at all; only the plan output does. So
  `evidenceSources` is observable in `--dry-run --json` and in the human plan,
  and M3 asserts it there rather than on the applied output.
- The tasty test groups are named after modules (`Seihou.CLI.Update.Render`,
  `Update end-to-end`), so the patterns `UpdateRender` and `UpdateE2E` in
  Concrete Steps match nothing and report "All 0 tests passed". Use
  `-p Update`, `-p Render`, or `-p end-to-end` instead.
- The existing E2E "reports unavailable evidence distinctly and never expands
  for it" still passes unchanged. Beta's recorded origin in that fixture
  (`CoOwnerAppendsPredatingEvidence`) is a local repository whose only commit
  declares 2.0.0, so the fetch runs and finds no commit declaring 1.0.0; the
  message still begins "module beta 1.0.0 is not installed here".
- A manual run of `locateRecordedRelease` against the real
  `https://github.com/shinzui/seihou-modules.git` found `nix-haskell-flake`
  0.13.2 at `ec6435e` (the last commit before the bump) in about 17 seconds.
  It also exposed two defects that the fixtures did not. First, a second
  lookup in the same session that visited an already checked-out revision
  failed with "already exists", because worktrees were named by visit
  ordinal. They are now keyed by clone and full commit id and reused, and a
  regression test covers it. Second, a version that was never released
  (`0.0.1`) evaluated 93 revisions, because that literal appears in other
  modules' Dhall files. The search is now scoped to the artifact's own
  definition file (and the fallback walk to its directory) whenever the tip
  holds the artifact, which cut that to 40 revisions and about 20 seconds.


## Decision Log

- Decision: Fetch only the exact recorded version, and read it only from the recorded
  remote origin. Never substitute another version, and never write the fetched copy into
  the install cache.
  Rationale: `docs/masterplans/11-make-manifest-evolution-explicit-and-targeted-updates-upgrade-safe.md`
  decided "co-owner remotes are not cloned" because "a remote's current release is not how
  the project was written" (ADR 0003 forbids substitution). That reason applies to the
  *current* release, not to the exact recorded one. The recorded release is precisely how
  the project was written. Keeping the fetched copy in the update's temporary session
  means no other project or command on the machine can observe it (ADR 0006).
  Date: 2026-09-18

- Decision: Identify the recorded release by content, not by tag. Among the commits at
  which the repository contains an artifact of the recorded name declaring the recorded
  version, take the newest.
  Rationale: The main module registry, `mori://shinzui/seihou-modules`, has no git tags.
  Its modules live under registry paths such as `modules/haskell/nix-haskell-flake/`, and
  `git log` shows 34 commits to that module's `module.dhall`. Tags cannot be relied on,
  but the declared `version` is exactly what the manifest records. If several commits
  declare the same version, the newest one is the author's final word on that version.
  The update already warns separately when content changes without a version change.
  Date: 2026-09-18

- Decision: Narrow the candidate commits with git's pickaxe search
  (`git log -S'"<version>"'`) and evaluate at most each result and its parent. Do not walk
  the whole history.
  Rationale: The pickaxe returns only commits where the number of occurrences of the
  version literal changed, meaning the commit that introduced it and the one that
  replaced it. The newest commit declaring the version is the parent of a removing commit
  or, if nothing removed it, the tip of the default branch. So the candidates are every
  result, every result's parent, and the tip, and evaluating them keeps the Dhall
  evaluations to a handful. If the literal is not found at
  all, which happens when a version is computed rather than written literally, fall back
  to walking the commits that touch the artifact's directory, newest first, capped at 200.
  Date: 2026-09-18

- Decision: Use a blobless partial clone (`git clone --filter=blob:none --no-checkout`),
  one per distinct origin URL per session, and read revisions with
  `git -C <clone> worktree add --detach`.
  Rationale: Candidate clones use `--depth 1`, which has no history. A blobless clone has
  full history at low cost and fetches file contents only for the revisions actually
  checked out. A worktree per evaluated revision leaves the clone reusable when two
  co-owners share an origin. `seihou-modules` holds dozens of modules.
  Date: 2026-09-18

- Decision: `seihou manifest upgrade` uses the same fallback, and it has no offline switch
  in this plan.
  Rationale: The command already certifies `unknown` paths across the whole project
  through the same `gatherApplicationEvidence`. Having it fail where `seihou update`
  succeeds would be a new inconsistency. A failed clone is simply one more evidence gap.
  It is reported, and the path stays unknown.
  Date: 2026-09-18

- Decision: Order candidates topologically (`git rev-list --all --topo-order`,
  filtered to the candidate set) instead of `git log --no-walk=sorted`; the
  fallback walk takes the first 200 of the same list. Restrict the pickaxe
  search to `*.dhall` pathspecs. Trigger the fallback walk only when the
  pickaxe finds no commit at all (the tip alone is always a candidate, so
  "the list is empty" could never happen).
  Rationale: Committer dates tie within a second; topological order does not.
  Definition files are Dhall, and limiting the pickaxe to them keeps a
  blobless clone from fetching unrelated blobs.
  Date: 2026-09-18

- Decision: Print the provenance lines once after all certified path lines
  rather than under each path, in both `seihou update` and
  `seihou manifest upgrade`.
  Rationale: Fetched sources belong to the certification round, not to one
  path; one co-owner fetch commonly certifies several paths, and repeating the
  line under each would only add noise.
  Date: 2026-09-18

- Decision: A failed fetch keeps the installed-copy reason and appends the fetch
  reason after "; ". When the recorded origin is a machine-local path, the
  existing repair-origins note (plan 98, already landed) is appended last, and a
  path that does not exist here is reported as "its recorded origin <path> is a
  path on another machine" without attempting a clone.
  Rationale: The user needs both facts (why the cache copy is unusable, why the
  remote did not help), and the remedy belongs at the end.
  Date: 2026-09-18

- Decision: Evaluate the tip first. When it holds the artifact, run the
  pickaxe only on that artifact's definition file, and make the fallback walk
  visit only commits that touch its directory (`rev-list -- <dir>`, capped at
  200). When the tip no longer holds the artifact, search every `*.dhall` file
  and walk all history, as before.
  Rationale: Version literals such as `0.0.1` recur across a registry's
  modules, so an unscoped search evaluates many unrelated commits. An artifact
  that has moved directories since the recorded release is missed by the
  scoped search. That is accepted: the result is a reported gap, never a wrong
  answer.
  Date: 2026-09-18


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Seihou is a Haskell project with three Cabal packages. `seihou-core/` holds domain types
and the engine. `seihou-cli/src/` is the `seihou-cli-internal` library, and
`seihou-cli/src-exe/` is the executable. Build with `cabal build all` and test with
`cabal test all` from the repository root. `nix flake check` also runs
`nix/check-cli-module-placement.sh`: new code goes in `seihou-cli/src/` unless it imports
`Options.Applicative`, `Data.FileEmbed`, `GitHash`, or `Paths_seihou_cli`. It also runs
`nix/check-record-conventions.sh`. Every `data` record field is strict and unprefixed,
records derive `Generic` with an explicit strategy, fields are accessed through
`generic-lens` labels (`x ^. #field`, `x & #field .~ v`), and each module using labels has
`import Data.Generics.Labels ()`.

**Terms.**

- *Artifact origin*: `ArtifactOrigin` in `seihou-core/src/Seihou/Core/Types.hs`. It is
  `RemoteOrigin {originUrl, artifactName, repoName}`, `ProjectOrigin {relativePath}` for
  an artifact inside the project, or `LocalOrigin {artifactName}` when provenance is
  unknown. Every module instance recorded in an application carries one (`origin`), with
  its `moduleVersion`.
- *Application*: a recorded top-level run, `AppliedComposition`, with id, target, and
  instances.
- *Shared-write mode*: `SharedWriteMode` on each file record: `additive-only`,
  `requires-ownership-closure`, or `unknown`.
- *Certification*: turning `unknown` into a known mode by compiling every owner and
  inspecting their operations for the path.
- *Registry repository*: a git repository with a `seihou-registry.dhall` listing entries,
  each with a `name` and a `path` to the artifact's directory. A single-artifact
  repository has `module.dhall` (or `recipe.dhall`) at its root.
  `Seihou.Core.Registry.discoverRepoContents` (in `seihou-core/src/Seihou/Core/Registry.hs`)
  classifies a checked-out repository either way.

**Where evidence is gathered today.** `seihou-cli/src/Seihou/CLI/ManifestCapabilityUpgrade.hs`
defines:

```haskell
data ApplicationEvidence = EvidenceOperations ![Operation] | EvidenceUnavailable !Text

gatherApplicationEvidence ::
  FilePath -> [FilePath] -> Manifest -> Set ApplicationId -> IO (Map ApplicationId ApplicationEvidence)

certifySharedWriteModesIO ::
  FilePath -> [FilePath] -> CertificationScope -> Manifest -> Map ApplicationId [Operation] ->
  IO SharedWriteCertification
```

Inside `gatherApplicationEvidence`, the local function `loadInstance` resolves each
recorded instance with `resolveArtifactOrigin projectRoot searchPaths "module.dhall"
recordedOrigin` (from `Seihou.Core.ArtifactRef`) and evaluates `module.dhall`. It then
rejects three cases with `Left reason`: the module is not installed, it is installed
from a different origin (`judgeArtifact` returns `ArtifactOriginMismatch`), or it
declares a different version. Those reasons become `EvidenceUnavailable`,
`OwnerEvidenceUnavailable`, and finally `SharedWriteEvidenceUnavailable` in the update,
rendered by `renderCertificationGap`. The compiled instances then go through
`resolveWithPromptPermission PromptsForbidden` and `compileComposedPlan`. This plan
changes only where a module's directory comes from, not how it is compiled.

**Callers.** `seihou-cli/src/Seihou/CLI/Update.hs` calls `certifySharedWriteModesIO`
inside the selection's closure loop (around line 305, `CertifyPathsForApplications ids`).
The planner already has a per-invocation temporary `sessionDirectory` (see
`withProjectUpdate` and `planProjectUpdateIn`), removed when planning finishes. That is
where fetched releases go. `seihou-cli/src/Seihou/CLI/ManifestUpgrade.hs` calls it with
`CertifyAllUnknownPaths` (around line 760) and has no session directory; it must create
one with `withSystemTempDirectory`.

**Cloning.** `seihou-cli/src/Seihou/CLI/InstallShared.hs` exports
`cloneRepo :: Text -> FilePath -> IO (Either Text ())`, which runs
`git clone --depth 1`. It is unsuitable for history search, so this plan adds its own
blobless clone. `seihou-cli/src/Seihou/CLI/Update/Source.hs` stages candidate sources
from `--depth 1` clones and shows how a registry repository is read
(`evalRegistryFromFile`, `RegistryEntry` `path`).

**Output.** `seihou-cli/src/Seihou/CLI/Update/Render.hs` renders a plan's
`manifestPreparation` (from `fromSchema`, `toSchema`, and one `{path, from, to}` per
certified path) in human and JSON form. The human form is the `Manifest:` block shown in
Purpose.

**Tests.** `seihou-cli/test/Seihou/CLI/UpdateSpec.hs` exports
`prepareSharedPathFixture :: CoOwnerWriteMode -> FilePath -> IO SharedPathFixture`. It
builds a project where applications `alpha` and `beta` co-own `.gitignore`, with beta's
recorded 1.0.0 release installed at `betaInstalledPath` under a private
`XDG_CONFIG_HOME` (`xdgHome`). Read how the fixture creates beta's source and
`.seihou-origin.json`. This plan needs beta's recorded origin to be a local git
repository, which `git clone` accepts as a URL. That repository must have a history in
which 1.0.0 appears and is later replaced by 1.1.0. `seihou-cli/test/Seihou/CLI/UpdateE2ESpec.hs`
test "reports unavailable evidence distinctly and never expands for it" is the closest
existing E2E. It moves beta aside to make evidence unavailable.
`seihou-cli/test/Seihou/CLI/ManifestCapabilityUpgradeSpec.hs` has `withSharedFixture` for
library-level certification tests.

**ADRs.**

- [ADR 0003](../adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md) rejects
  "fetch the recorded version automatically" for generating commands such as
  `seihou run`, which must stay local and offline. This plan fetches only for
  *evidence*, inside `seihou update`, which already clones candidates over the
  network, and `seihou manifest upgrade`. It generates no file from the fetched copy.
  M4 adds a paragraph to ADR 0003 saying so, so that the two decisions are not read as
  contradicting each other.
- [ADR 0006](../adr/0006-the-install-cache-will-not-silently-substitute-an-artifact.md):
  the install cache is never silently replaced. The fetched release never enters it.
- [ADR 0012](../adr/0012-an-additive-co-write-is-not-a-shared-path-conflict.md) records
  that certification compiles co-owners "only from exact installed versions". M4 amends
  it: the exact recorded version may also come from the recorded remote.
- [ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md):
  the manifest format does not change, so no schema step is needed.

The related plans are `docs/plans/96-add-seihou-agent-upgrade-for-agent-assisted-module-upgrades-that-repair-manifest-state.md`,
whose playbook points at this behavior, and
`docs/plans/98-repair-machine-local-artifact-origins-and-stop-recording-them.md`, which
repairs origins recorded as local paths. A co-owner whose recorded origin is a local
path that exists on this machine still works here, because `git clone` accepts a path.
When the path does not exist, the gap message points at plan 98's command once it exists.


## Plan of Work

### Milestone 1: Find the recorded release in a repository

Create `seihou-cli/src/Seihou/CLI/RecordedRelease.hs` (library; add to
`exposed-modules` of `seihou-cli-internal` in `seihou-cli/seihou-cli.cabal`). It answers
this question: given an origin URL, an artifact name, a definition file (`module.dhall`
or `recipe.dhall`), and a version, return a directory holding that artifact as it was
when it declared that version, or say why not.

The IO steps, all via `System.Process.readProcessWithExitCode` with `git`:

1. `cloneForHistory :: FilePath -> Text -> IO (Either Text FilePath)`. Clone into
   `<session>/recorded-releases/<sha256 of normalized URL>` with
   `git clone --filter=blob:none --no-checkout --quiet <url> <dir>`, unless that
   directory already exists from an earlier call in the same session. Normalize with
   `Seihou.Core.ArtifactIdentity.normalizeOriginUrl`. Some servers, and `file://`
   remotes, ignore partial-clone filters; git then falls back to a full clone, which is
   still correct.
2. `candidateRevisions`. Run `git -C <dir> log --format=%H -S'"<version>"' --all` for
   commits whose count of the quoted version literal changed. For each commit `c`,
   consider `c` and `c^` (skip `c^` for a root commit). Also add the tip of the default
   branch (`git -C <dir> rev-parse HEAD`), which covers a version that is still current.
   Deduplicate them and order them newest first by committer date. Obtain the order with
   `git log --format=%H --no-walk=sorted <revs...>`. If the list is empty, fall back to
   `git -C <dir> log --format=%H -n 200 --all`.
3. For each revision, newest first:
   - Check it out with `git -C <dir> worktree add --detach --quiet <session>/recorded-releases/wt-<short>-<n> <rev>`.
   - Locate the artifact. Run `discoverRepoContents evalRegistryFromFile` on the
     worktree. For a registry, find the entry whose `name` equals the artifact name; its
     directory is `<wt>/<entry path>`. For a single-artifact repository, use the
     worktree root when the definition file's `name` matches.
   - Evaluate the definition file (`evalModuleFromFile` or `evalRecipeFromFile` from
     `Seihou.Dhall.Eval`) and compare its `version` with the recorded one.
   - The first match wins. Return its directory and the short commit id.
   - Leave non-matching worktrees in place. The whole session directory is deleted at
     the end, which is cheaper than removing them one by one.
4. When nothing matches, return
   `RecordedReleaseNotFound url name version searchedCount`.

Separate the pure part so it can be tested without git. Given a list of
`(revision, Maybe declaredVersion)` pairs in newest-first order, choose the first
declaring the version. Also keep the fallback rule pure. Encode each failure as a
constructor of `RecordedReleaseError` with an exhaustive prose renderer
`renderRecordedReleaseError`, with no `show` (ADR 0015).

Write `seihou-cli/test/Seihou/CLI/RecordedReleaseSpec.hs` and register it in
`seihou-cli/test/Main.hs` and the test-suite `other-modules`. In a temporary directory it
builds a git repository with:

- a registry holding `beta` at `modules/beta/` whose `module.dhall` declares `1.0.0`;
- a second commit changing a template without changing the version;
- a third commit declaring `1.1.0`.

Use the fixture's existing `moduleDhall` style (see `seihou-cli/test/Seihou/CLI/TwoDeveloperFixture.hs`
`moduleDhall`) for valid module text. Assertions:

- Asking for `beta 1.0.0` returns the *second* commit's content.
- Asking for `beta 1.1.0` returns the tip.
- Asking for `beta 0.9.0` returns `RecordedReleaseNotFound` with a message naming the URL,
  the name, and the version.
- Asking for `gamma 1.0.0` returns not found.
- A URL that does not exist returns a clone error, not an exception.
- A repository whose version is not a quoted literal is found by the fallback walk. Write
  the version as a computed Dhall expression such as `"1.0" ++ ".0"`, so the literal
  `"1.0.0"` never appears in the file.
- The pure chooser's rules are covered directly.

Acceptance: `cabal test seihou-cli --test-options='-p "RecordedRelease"'` passes.

### Milestone 2: Use it when certifying

Add to `ManifestCapabilityUpgrade.hs`:

```haskell
data EvidencePolicy
  = -- | Only copies installed on this machine (the previous behavior).
    InstalledReleasesOnly
  | -- | Installed copies first; otherwise fetch the recorded release from
    -- the recorded remote into this session directory.
    FetchRecordedReleases !FilePath
  deriving stock (Eq, Show, Generic)
```

Thread the policy through `gatherApplicationEvidence` and `certifySharedWriteModesIO` as a
new first parameter. In `loadInstance`, keep the existing path as the first attempt. When
it yields `Left reason` and the policy is `FetchRecordedReleases session`, the recorded
origin is a `RemoteOrigin url name _`, and the instance records a version, call
`Seihou.CLI.RecordedRelease.locateRecordedRelease session url name "module.dhall" version`:

- On success, use the returned directory exactly as an installed one: evaluate it, and
  still check that the declared version equals the recorded one as a belt-and-braces
  check. Remember the provenance `(name, version, url, shortCommit)`.
- On failure, the reason becomes the installed-copy reason followed by the fetch reason,
  for example `module nix-haskell-flake is version 0.24.0 here but the manifest records
  version 0.13.2; no commit of https://github.com/shinzui/seihou-modules.git declares
  nix-haskell-flake 0.13.2 (searched 6 revisions)`.
- A `LocalOrigin` or `ProjectOrigin` never fetches. Say so in the reason: "its recorded
  origin names no remote to fetch from".
- A `RemoteOrigin` whose URL is a local filesystem path that does not exist gets the reason
  `its recorded origin <path> is a path on another machine`. Plan 98 appends
  "run 'seihou manifest repair-origins'" to that reason when it lands; leave a comment at
  the spot. Add a small helper `isLocalPathUrl :: Text -> Bool` here, or reuse it from
  `Seihou.Core.ArtifactIdentity` if plan 98 has already added it. It is true for text
  starting with `/`, `./`, `../`, or `~`, and for `file://`.

To report provenance, change `ApplicationEvidence`'s success constructor to
`EvidenceOperations ![Operation] ![EvidenceSource]`, with
`data EvidenceSource = EvidenceSource { moduleName :: !ModuleName, version :: !Text,
originUrl :: !Text, revision :: !Text }` for fetched instances only. An empty list means
everything was installed. Add `fetchedSources :: ![EvidenceSource]` to
`SharedWriteCertification`, which carries the union. Fix every construction site the
compiler reports. `Map.map EvidenceOperations supplied` becomes
`Map.map (\ops -> EvidenceOperations ops []) supplied`.

Callers:

- `Update.hs`: pass `FetchRecordedReleases sessionDirectory`. Carry `fetchedSources` into
  the plan's manifest preparation. Find the type behind `manifestPreparation` in
  `seihou-cli/src/Seihou/CLI/Update/Types.hs` and add
  `evidenceSources :: ![EvidenceSource]`.
- `Render.hs`: render the provenance line under each certified path's line in human output,
  as in Purpose. Add an optional `evidenceSources` array
  (`[{module, version, origin, revision}]`) to the JSON `manifestPreparation` object. It is
  additive, so the envelope's `schemaVersion: 1` does not change, following the precedent
  EP-94 set when it added `manifestPreparation`. Update
  `seihou-cli/test/Seihou/CLI/UpdateRenderSpec.hs`.
- `ManifestUpgrade.hs`: wrap the certification call in
  `withSystemTempDirectory "seihou-manifest-upgrade"` and pass
  `FetchRecordedReleases`. Make `formatUpgradeReport` print the same provenance line for
  each certified path.
- Every other caller, including tests, passes `InstalledReleasesOnly` unless it is
  testing the new path.

Acceptance: `cabal build all` succeeds, and the existing
`ManifestCapabilityUpgradeSpec`, `ManifestUpgradeSpec`, `UpdateSpec`, and
`UpdateE2ESpec` pass unchanged. Add a library test in
`ManifestCapabilityUpgradeSpec` in which beta's installed copy is replaced by 1.1.0 and
beta's recorded origin is the M1 fixture repository. Under `FetchRecordedReleases` the path
certifies as `additive-only` with one fetched source; under `InstalledReleasesOnly` it
stays a gap.

### Milestone 3: Prove the reported failure is gone

Extend `seihou-cli/test/Seihou/CLI/UpdateE2ESpec.hs`, reusing `prepareSharedPathFixture`.
Make beta's recorded origin a local git repository with 1.0.0 then 1.1.0 history, and
install 1.1.0 into `betaInstalledPath`: the cache moved ahead, exactly as in the report.
Then:

- `seihou update alpha --json` exits 0 with `"outcome":"applied"`. Its
  `manifestPreparation.evidenceSources` names beta, `1.0.0`, and a revision. Beta's own
  file (`betaFilePath`) is byte-identical, and the installed cache directory is
  byte-identical, which proves nothing was swapped.
- `seihou update alpha --dry-run` in human form shows the `read from ... at <rev>` line.
- With the repository's 1.0.0 history rewritten away (build a second repository whose
  only version is 1.1.0), the update refuses with `shared_write_evidence_unavailable`, and
  the message contains `no commit of` and `declares beta 1.0.0`.
- `seihou manifest upgrade --dry-run` on a schema-7 manifest with the path `unknown`
  reports the path certified with the fetched source.

The existing E2E "reports unavailable evidence distinctly and never expands for it" moves
beta aside, but beta's recorded origin in that fixture may point at the moved directory.
If the new fallback now finds it, update that test to point beta's origin at a path that
does not exist, so it still exercises the refusal. Record what you find in Surprises &
Discoveries.

### Milestone 4: Documentation, ADRs, validation

- `docs/cli/update.md`: rewrite the paragraph that begins "If a co-owner's recorded
  version is not installed on this machine" to say that seihou first fetches the recorded
  release from the recorded remote into a temporary directory, and that the refusal
  remains for co-owners with no remote or no commit declaring the version. Show the
  provenance line. Mention the JSON `evidenceSources` key.
- `docs/cli/manifest.md`: note the same fallback under `manifest upgrade`.
- `docs/user/CHANGELOG.md` and `CHANGELOG.md`, under Unreleased, Changed: targeted updates
  no longer need the recorded co-owner release installed.
- Amend [ADR 0012](../adr/0012-an-additive-co-write-is-not-a-shared-path-conflict.md) with
  a dated amendment paragraph in its existing style. Certification may read the exact
  recorded release from the recorded remote, located by declared version, in a temporary
  session and never the cache. Another version is still never substituted.
- Add a dated paragraph to [ADR 0003](../adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md)'s
  "Rejected: fetch the recorded version automatically" section. The rejection concerns
  generating commands. Evidence-only fetching in network-using commands is allowed, per
  the ADR 0012 amendment.
- Grep `docs/` for `is not installed here`, `Install the recorded version`, and
  `shared_write_evidence_unavailable`, and fix every page that describes the old
  remedy, including `docs/user/manifest-upgrade.md` if it mentions it.
- Run the full validation in Concrete Steps.


## Concrete Steps

From the repository root:

```bash
cabal build all
cabal test seihou-cli --test-options='-p "RecordedRelease"'
cabal test seihou-cli --test-options='-p "ManifestCapabilityUpgrade"'
cabal test seihou-cli --test-options='-p "UpdateE2E"'
```

Before each commit:

```bash
nix fmt -- --fail-on-change
cabal build all
cabal test all
nix flake check
```

A manual check against the reporting project, if it is still in the failing state. Record
the output in Outcomes:

```bash
SEIHOU=$(cabal list-bin seihou)
cd /path/to/mls-service-v2     # the checkout of mori://tan/mls-service-v2
"$SEIHOU" update <skill-target> --dry-run
```

Expected: the plan shows `(nix-haskell-flake 0.13.2 read from https://github.com/shinzui/seihou-modules.git at <rev>)`,
and `~/.config/seihou/installed/nix-haskell-flake/.seihou-origin.json` still says `0.24.0`.

Commit per milestone with Conventional Commits and trailers:

```text
feat(update): certify co-owners from their recorded release when the cache moved on

ExecPlan: docs/plans/97-fetch-a-co-owner-s-recorded-release-to-certify-shared-write-evidence.md
Intention: intention_01m2tanyfae9ftvcqmaygv0960
```


## Validation and Acceptance

1. `cabal test all` passes, including `RecordedReleaseSpec`, the new
   `ManifestCapabilityUpgradeSpec` case, and the new `UpdateE2ESpec` cases.
2. In the E2E fixture where the installed co-owner is newer than recorded, a targeted
   update succeeds without touching the co-owner's files or the install cache, and it
   reports which revision supplied the evidence.
3. When no commit declares the recorded version, the update refuses with
   `shared_write_evidence_unavailable`, and the message says what was searched. It never
   suggests `--include-shared-owners`.
4. `seihou update --json` output for updates that fetch nothing is byte-identical to
   before; `evidenceSources` is omitted when empty.
5. `nix flake check` and `nix fmt -- --fail-on-change` pass.


## Idempotence and Recovery

Fetched releases live only in the planner's temporary session directory, which is deleted
when planning ends, whether it succeeds or fails. Nothing is written to
`~/.config/seihou/installed/` or the project by the fetch, so a retry starts clean. A
dry run fetches as well, because evidence is part of the plan, and still writes nothing to
the project. Code changes are additive until M2's signature change, which is completed in
one commit so the build stays green.


## Interfaces and Dependencies

No new package dependencies. `git` must be on `PATH`, as it already is for candidate
clones. Use `process`, `directory`, `temporary`, `cryptohash`/`Seihou.Manifest.Hash` (for
the directory key; reuse `hashContent` over the normalized URL bytes), and `aeson`.

```haskell
-- seihou-cli/src/Seihou/CLI/RecordedRelease.hs
module Seihou.CLI.RecordedRelease
  ( RecordedRelease (..),
    RecordedReleaseError (..),
    locateRecordedRelease,
    chooseRevision,
    renderRecordedReleaseError,
  )
where

data RecordedRelease = RecordedRelease
  { directory :: !FilePath,
    revision :: !Text -- short commit id
  }
  deriving stock (Eq, Show, Generic)

data RecordedReleaseError
  = RecordedReleaseCloneFailed !Text !Text -- url, git stderr
  | RecordedReleaseNotFound !Text !Text !Text !Int -- url, name, version, revisions searched
  | RecordedReleaseGitFailed !Text !Text -- what, stderr
  deriving stock (Eq, Show, Generic)

locateRecordedRelease ::
  FilePath -> -- session directory
  Text -> -- origin URL
  Text -> -- artifact name
  FilePath -> -- definition file, "module.dhall" or "recipe.dhall"
  Text -> -- recorded version
  IO (Either RecordedReleaseError RecordedRelease)

-- | Pure: the first revision (newest first) that declares the version.
chooseRevision :: Text -> [(Text, Maybe Text)] -> Maybe Text

renderRecordedReleaseError :: RecordedReleaseError -> Text

-- seihou-cli/src/Seihou/CLI/ManifestCapabilityUpgrade.hs
data EvidencePolicy = InstalledReleasesOnly | FetchRecordedReleases !FilePath
data EvidenceSource = EvidenceSource
  { moduleName :: !ModuleName, version :: !Text, originUrl :: !Text, revision :: !Text }
data ApplicationEvidence = EvidenceOperations ![Operation] ![EvidenceSource] | EvidenceUnavailable !Text

gatherApplicationEvidence ::
  EvidencePolicy -> FilePath -> [FilePath] -> Manifest -> Set ApplicationId ->
  IO (Map ApplicationId ApplicationEvidence)

certifySharedWriteModesIO ::
  EvidencePolicy -> FilePath -> [FilePath] -> CertificationScope -> Manifest ->
  Map ApplicationId [Operation] -> IO SharedWriteCertification
-- SharedWriteCertification gains: fetchedSources :: ![EvidenceSource]
```
