# Fix `outdated` and `upgrade` to detect true module versions

MasterPlan: docs/masterplans/1-migrations-dx.md
Intention: intention_01kq5pe8hhekrrb9wg4eb1jz74

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, `seihou outdated` and `seihou upgrade` will correctly identify outdated installed modules even when the remote source repository's `seihou-registry.dhall` is stale relative to the modules it indexes. Today, `seihou outdated` reads the `version` field declared in the registry entry and compares it to the installed copy's `module.dhall` version. When a module author forgets to run `seihou registry sync` (or hasn't yet), the registry says, for example, `0.1.0` while the actual `modules/<name>/module.dhall` says `0.3.0`, and `seihou outdated` falsely reports "up to date".

The fix is to read the true version from the cloned `module.dhall` (which is the artifact `seihou run`, `seihou migrate`, and `seihou install` actually evaluate at apply time), not from the registry's static metadata.

You can see this working by setting up a project with master-plan v0.1.0 applied against a remote whose `seihou-registry.dhall` declares 0.1.0 but whose `modules/master-plan/module.dhall` declares 0.3.0; before the change, `seihou outdated` reports "up to date"; after the change, it reports `0.1.0 -> 0.3.0 outdated`.


## Progress

- [x] Reproduce the bug with a deterministic test fixture.
      Done in `seihou-cli/test/Seihou/CLI/RemoteVersionSpec.hs` ("returns the
      module.dhall version even when the registry says otherwise"); the
      fixture mirrors the agent-seihou stale-registry setup.
- [x] Trace today's version-comparison logic in `seihou-cli/src/Seihou/CLI/Outdated.hs` and `seihou-cli/src/Seihou/CLI/Upgrade.hs` and document it in this plan.
      See Surprises & Discoveries: bug site identified in
      `findAvailableVersion` (Outdated.hs:191–213); Upgrade.hs reused the
      same function.
- [x] Introduce a `fetchTrueModuleVersion` primitive that reads the cloned `module.dhall`.
      `seihou-cli/src/Seihou/CLI/RemoteVersion.hs`. Exposed by the
      `seihou-cli-internal` library and listed in the executable's
      `other-modules`.
- [x] Switch `seihou outdated` to use the primitive.
      `compareModule` and `checkSource` no longer take `RepoContents`;
      version is fetched per module via `fetchTrueModuleVersion`. The old
      `findAvailableVersion` is removed.
- [x] Switch `seihou upgrade`'s detection step to use the primitive.
      `upgradeModule` now calls `fetchAvailable` (a thin wrapper around the
      primitive). `doUpgrade`'s post-install version recording flips to
      prefer `modul.version <|> entry.version`, so the version stamped in
      `~/.config/seihou/installed/<name>/.seihou-origin.json` is the
      truthful one.
- [x] Add a regression test exercising a stale-registry remote.
      Covered by `RemoteVersionSpec` (5 cases: stale-registry,
      unversioned, entry-not-found, missing-module-dhall, single-module,
      empty-repo). UpgradeSpec was intentionally left as a unit-only spec
      for `compareVersions` since the comparison input is the changed
      surface and the primitive is fully covered.
- [x] End-to-end demonstration in the agent-seihou test bed.
      Verified by running the rebuilt `seihou outdated` against the live
      installed modules sourced from
      `https://github.com/shinzui/agent-seihou.git`. Both `master-plan` and
      `exec-plan` were flagged outdated (`0.1.0 → 0.3.0` and
      `0.1.3 → 0.3.0`), exactly the modules whose registry `version` field
      lags behind their `modules/<name>/module.dhall`. The remaining four
      modules (`claude-skill-link`, `update-docs`, `claude-gitignore`,
      `nix-haskell-flake`) correctly stayed `up to date`. Before the fix
      this same invocation reported `0 outdated`.
- [x] Update `docs/cli/upgrade.md` and `docs/cli/outdated.md` and `docs/user/CHANGELOG.md`.


## Surprises & Discoveries

- **The bug site is `findAvailableVersion` in `Outdated.hs`, lines 191–213.** The function's
  body short-circuits on `entry.version` from the registry:

      MultiModule registry -> do
        let matchingEntries = filter (\e -> e.name.unModuleName == name) registry.modules
        case matchingEntries of
          (entry : _) -> do
            -- Try registry entry version first, then module.dhall version
            case entry.version of
              Just v -> pure (Just v)            -- bug: trusts stale metadata
              Nothing -> do
                let dhallFile = cloneDir </> entry.path </> "module.dhall"
                ...

  When the registry says `version = Some "0.1.0"` but the cloned `modules/<name>/module.dhall`
  declares `version = Some "0.3.0"`, the registry entry wins and the comparison reports "up to
  date". `Upgrade.hs` reuses the same function (`Outdated.findAvailableVersion`) at line 154,
  so both commands share the bug.

- **`Seihou.CLI.Outdated` is in the executable, not the library.** The cabal file's
  `seihou-cli-internal` library exposes `Seihou.CLI.Migrate`, `Seihou.CLI.VersionCompare`,
  etc., but `Outdated.hs` is listed only under the `executable seihou` `other-modules`. To make
  the primitive testable we extract it into a new module `Seihou.CLI.RemoteVersion` that is
  exposed from the library. `Outdated.hs` and `Upgrade.hs` (still in the executable) import
  the primitive from the library.

- **Existing `compareVersions` operates on `Maybe Text`, not `SemVer`.** The plan's tentative
  signature returned `Either FetchError SemVer`, but the rest of the code path (especially
  `Seihou.CLI.VersionCompare.compareVersions :: Maybe Text -> Maybe Text -> OutdatedStatus`)
  consumes `Maybe Text`. The existing `Seihou.Core.Version.parseVersion` converts text to a
  numeric tuple internally during comparison. We finalize the primitive's return type as
  `IO (Either FetchError (Maybe Text))`. `Right Nothing` represents an unversioned module
  (preserves today's "unversioned" status), and `Right (Just v)` is the truthful version
  string. We drop the `MissingVersionField` constructor proposed in the plan, since
  `Right Nothing` already carries that meaning without conflating it with an error.


## Decision Log

- Decision: Read true version from the cloned `module.dhall` rather than from the registry entry.
  Rationale: The registry is metadata maintained by hand (or by `seihou registry sync`); the module.dhall is the source of truth that the rest of the CLI already evaluates. Trusting two sources creates drift; trusting one eliminates it.
  Date: 2026-04-26.

- Decision: Place the primitive in a new `Seihou.CLI.RemoteVersion` module exposed from
  `seihou-cli-internal`, rather than extending `Seihou.CLI.Outdated`.
  Rationale: `Outdated.hs` lives in the executable and is not visible to the test suite. EP-2
  and EP-4 also need the primitive (per the master plan's integration points), so a dedicated
  module owned by the library is the cleanest seam. The existing `findAvailableVersion`
  becomes a thin caller of the new primitive.
  Date: 2026-04-26.

- Decision: Primitive returns `IO (Either FetchError (Maybe Text))`, not
  `IO (Either FetchError SemVer)`.
  Rationale: The downstream `compareVersions` consumes `Maybe Text` and there is no `SemVer`
  type in the codebase; the closest is `Seihou.Core.Version.Version`, which is constructed
  during comparison. Returning `Maybe Text` keeps the primitive close to what callers already
  use, preserves the "unversioned" display for modules whose `module.dhall` declares
  `version = None Text`, and avoids forcing every caller to re-render the version when it
  needs to print it. Errors remain a closed `FetchError` sum so the primitive is honest about
  failure modes (registry/module file missing, parse failure, etc.).
  Date: 2026-04-26.


## Outcomes & Retrospective

EP-1 closed on 2026-04-26 with the demonstrable behavior the masterplan
called for: `seihou outdated` and `seihou upgrade` now read the truthful
`version` field from the cloned `module.dhall` and treat the registry's
static `version` field as informational only. The bug originally reported
in the masterplan ("0 outdated" against agent-seihou) is gone.

What landed:

- New `Seihou.CLI.RemoteVersion` module exposing
  `fetchTrueModuleVersion :: FilePath -> ModuleName -> IO (Either FetchError (Maybe Text))`
  and a `FetchError` sum (`RegistryNotFound`, `EntryNotFound`,
  `ModuleDhallNotFound`, `ParseFailed`). This is the integration contract
  the masterplan (§Integration Points #1) reserved; EP-2 and EP-4 will
  import this same function.
- `Outdated.hs` and `Upgrade.hs` rewritten to call the primitive. The
  obsolete `findAvailableVersion` is removed; `compareModule` and
  `checkSource` no longer take `RepoContents`. `Upgrade.doUpgrade` also
  flips the post-install version recording so the manifest stamps the
  truthful `module.dhall` version (`modul.version <|> entry.version`).
- Six new unit tests in `RemoteVersionSpec.hs` cover the stale-registry
  case, unversioned modules, missing entries, missing module.dhall files,
  single-module repos, and empty repos. The full suite (130 tests) passes.
- Live verification on the agent-seihou test bed: `master-plan` 0.1.0 and
  `exec-plan` 0.1.3 correctly report as outdated against the upstream
  0.3.0 module.dhall declarations; previously both showed `up to date`.

Lessons:

- The plan's tentative `IO (Either FetchError SemVer)` signature was
  deliberately replaced with `IO (Either FetchError (Maybe Text))`
  because the codebase has no `SemVer` type and the comparison path
  already operates on `Maybe Text`; the change preserved the existing
  "unversioned" rendering with no constructor for it.
- `Outdated.hs` lives in the executable target only, not the library.
  Putting the new primitive in a dedicated `Seihou.CLI.RemoteVersion`
  module exposed by `seihou-cli-internal` was the right call — both for
  testability and for the EP-2/EP-4 consumers that will follow.
- The post-install version recording (`doUpgrade`) had the same
  bias-toward-registry as the comparison, and was easy to miss while
  reading the plan; the fix is a one-line `<|>` flip but it matters
  because otherwise a project's manifest would still record the stale
  registry version after `seihou upgrade` succeeds.

Carry-overs to other EPs:

- EP-2 should import `fetchTrueModuleVersion` directly rather than
  re-cloning to do its own version read; the primitive does its own
  `discoverRepoContents` and works for both single- and multi-module
  layouts.
- EP-4's `seihou status --check-updates` will inherit the bug fix
  automatically once it routes through `checkInstalledModulesForUpdates`,
  but EP-4 should add its own assertion that a fresh manifest+stale-
  registry combination is rendered correctly in the status table.


## Context and Orientation

The Seihou CLI is a Haskell program in this repository whose entry points live under `seihou-cli/src/Seihou/CLI/`. The two commands this plan changes are:

- `seihou outdated` — handler in `seihou-cli/src/Seihou/CLI/Outdated.hs` (≈ 278 lines as of this writing).
- `seihou upgrade` — handler in `seihou-cli/src/Seihou/CLI/Upgrade.hs` (≈ 372 lines).

Both commands today work by:

1. Discovering the set of installed modules under `~/.config/seihou/installed/<name>/`.
2. Reading each module's `.seihou-origin.json` to recover the source URL and module name from the time of install.
3. Cloning each unique source URL into a temporary directory.
4. Reading the cloned repo's `seihou-registry.dhall` (for multi-module repos) or its single `module.dhall` (for single-module repos).
5. Comparing the registry-declared version (a `Optional Text`) to the installed copy's version.

The bug surfaces in step 5: the registry-declared version is read from the registry's static metadata. For a repo whose registry has not been synced, that string is wrong. The cloned working tree already contains the true `module.dhall` at `<clone>/<entry.path>/module.dhall`; we should read that file instead.

A "registry" here is a `seihou-registry.dhall` file at the root of a multi-module repo declaring `{ modules : List { name, version, path, description, tags } }`. A "module" is a directory containing `module.dhall` whose schema lives in `schema/Module.dhall`. The truthful `version` is the `version : Optional Text` field of that `module.dhall`.

Other relevant files:

- `seihou-core/src/Seihou/Dhall/ModuleDecoder.hs` — already evaluates a `module.dhall` to a Haskell record. The new primitive should reuse this; do not write a parallel parser.
- `seihou-core/src/Seihou/Core/Types.hs` — defines `ModuleName`, `Manifest`, `AppliedModule`, etc. The `AppliedModule.moduleVersion :: Maybe Text` is the recorded "what is currently applied" version; this plan does not modify it.
- `seihou-cli/src/Seihou/CLI/Install.hs` — when an `install` succeeds, it writes `.seihou-origin.json` with `{ sourceUrl, moduleName, sourceRevision }`. This is the input that step 2 above consumes.

A "stale registry" means the case where `seihou-registry.dhall`'s `modules[i].version` does not equal the `version` field of the actual `modules[i].path/module.dhall`. The project's `seihou registry sync` command (added in `docs/plans/12-sync-registry-versions.md`) is intended to keep these in agreement, but nothing in the upgrade flow assumes it has been run.


## Plan of Work

### Milestone 1 — Reproduce the bug

What will exist at the end: a regression test that fails before the fix and passes after.

In `seihou-cli/test/Seihou/CLI/OutdatedSpec.hs`, add a fixture-based integration test that:

1. Creates a temp directory representing a fake "remote" multi-module repo with two files:
   - `seihou-registry.dhall` declaring a single module entry `{ name = "demo", version = Some "1.0.0", path = "modules/demo", ... }`.
   - `modules/demo/module.dhall` declaring `version = Some "2.0.0"` (intentionally newer than the registry says).
2. Initializes a fake "installed" directory at `~/.config/seihou/installed/demo/` (use a redirected `XDG_CONFIG_HOME` env var) containing the `module.dhall` from version `1.0.0` and a `.seihou-origin.json` pointing at the temp remote (using `file://` scheme so `git clone` works locally).
3. Invokes `runOutdated` (the testable entry, equivalent to `handleOutdated` minus IO setup; introduce one if it doesn't yet exist).
4. Asserts that the result includes `demo` with installed=`1.0.0`, available=`2.0.0`, and status `Outdated`.

Acceptance: `cabal test seihou-cli` includes the new test and it fails on master with a message like "expected Outdated, got UpToDate".

### Milestone 2 — Trace and document current logic

Read `seihou-cli/src/Seihou/CLI/Outdated.hs` end-to-end. Append a Surprises & Discoveries entry quoting the lines where the registry version is read and the comparison is performed. The purpose is to make the diff in milestone 3 reviewable without re-reading the file.

### Milestone 3 — Introduce `fetchTrueModuleVersion`

Add a function in `seihou-cli/src/Seihou/CLI/Outdated.hs` (or a new `seihou-cli/src/Seihou/CLI/RemoteVersion.hs` if the function is reused by EP-2 in a way that warrants a dedicated home — the integration point in the master plan permits either):

    fetchTrueModuleVersion
      :: ClonedRepoPath
      -> ModuleName
      -> IO (Either FetchError SemVer)

where:

- `ClonedRepoPath` is a newtype around `FilePath` representing a directory we have already `git clone`d.
- `SemVer` is the existing semver type the codebase uses (look in `seihou-core` for `parseSemVer` or similar; reuse it).
- `FetchError` enumerates: `RegistryNotFound`, `EntryNotFound ModuleName`, `ModuleDhallNotFound FilePath`, `ParseFailed Text`, `MissingVersionField`.

The implementation:

1. If `<clone>/seihou-registry.dhall` exists, evaluate it, look up the entry by name, and resolve the path to `<clone>/<entry.path>/module.dhall`.
2. Otherwise (single-module repo), use `<clone>/module.dhall`.
3. Evaluate the chosen `module.dhall` using the existing `Seihou.Dhall.ModuleDecoder` machinery.
4. Return its `version` field, parsing it through the existing semver parser.

Add unit tests in `seihou-cli/test/Seihou/CLI/RemoteVersionSpec.hs` covering each `FetchError` variant.

### Milestone 4 — Switch `outdated` to the new primitive

In `Outdated.hs`, replace the registry-version read with a call to `fetchTrueModuleVersion`. Keep the existing comparison logic (semver compare) unchanged. The diff should be small and localized: only the source of the "available" version changes.

Run the milestone-1 regression test; it should now pass.

### Milestone 5 — Switch `upgrade` to the new primitive

In `seihou-cli/src/Seihou/CLI/Upgrade.hs`, the function that decides whether a module is outdated (around the function that prints the "Old / New / Status" table) reads from the same registry source. Replace that with `fetchTrueModuleVersion`.

Important: the `installModuleDir` step further down (which actually copies the new module copy into `~/.config/seihou/installed/`) does not need to change; it already operates on the cloned directory.

Add a regression test in `seihou-cli/test/Seihou/CLI/UpgradeSpec.hs` that mirrors the milestone-1 fixture and asserts `seihou upgrade` reports `1.0.0 -> 2.0.0 upgraded` (not "up to date").

### Milestone 6 — End-to-end demonstration in the agent-seihou test bed

The repo at `/Users/shinzui/Keikaku/bokuno/agent-seihou` is the canonical "stale registry" case. Verify by running, from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`:

    $ cabal run seihou-cli -- outdated

Expected output (showing `master-plan` and `exec-plan` as outdated, since the registry says 0.1.0/0.1.3 but the modules say 0.3.0):

    Module       Installed  Available  Status
    master-plan  0.1.0      0.3.0      outdated
    exec-plan    0.1.3      0.3.0      outdated
    ...

### Milestone 7 — Documentation and CHANGELOG

Create `docs/cli/upgrade.md` if it does not already exist; add a section "How outdated detection works" that explains the new behavior. Add or update `docs/cli/outdated.md` similarly. Append to `docs/user/CHANGELOG.md` an entry under today's date describing the fix.


## Concrete Steps

From the repo root:

    $ cabal build seihou-cli
    $ cabal test seihou-cli --test-options="--match outdated"
    $ cabal test seihou-cli --test-options="--match upgrade"

Manual verification:

    $ cd /Users/shinzui/Keikaku/bokuno/agent-seihou
    $ git status   # confirm we are not modifying this repo
    $ cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    $ cabal run seihou-cli -- outdated
    # expect master-plan and exec-plan to show as outdated (0.1.x -> 0.3.0)


## Validation and Acceptance

- `cabal test seihou-cli` passes including the new tests.
- In the seihou-project working tree, `seihou outdated` reports `master-plan` and `exec-plan` as outdated with `0.1.x -> 0.3.0`.
- In the seihou-project working tree, `seihou upgrade` upgrades both modules and updates the manifest's `moduleVersion` for each.
- `seihou status --check-updates` in the same project shows the same outdated/upgraded entries (this depends only on the corrected detection; status surface improvements are EP-4).


## Idempotence and Recovery

The change is read-only on detection (no filesystem writes). The upgrade step continues to use the existing `installModuleDir` which atomically replaces `~/.config/seihou/installed/<name>/`. Repeated invocations of `seihou outdated` are safe; repeated invocations of `seihou upgrade` are safe (already idempotent in the existing implementation).

If the `module.dhall` parse fails, return a `FetchError` and propagate as a non-fatal warning to the user (e.g., "could not determine remote version for X: <reason>"); do not crash the whole `outdated` command. Other modules' detection should still complete.


## Interfaces and Dependencies

In `seihou-cli/src/Seihou/CLI/Outdated.hs` (or `seihou-cli/src/Seihou/CLI/RemoteVersion.hs` if extracted), define:

    data FetchError
      = RegistryNotFound FilePath
      | EntryNotFound ModuleName
      | ModuleDhallNotFound FilePath
      | ParseFailed Text
      | MissingVersionField ModuleName
      deriving (Show, Eq)

    fetchTrueModuleVersion
      :: ClonedRepoPath
      -> ModuleName
      -> IO (Either FetchError SemVer)

Reuse the existing semver type (search for `SemVer`, `parseSemVer`, or `Version` in `seihou-core`). Reuse `Seihou.Dhall.ModuleDecoder` for parsing. Do not introduce a new Dhall evaluation pathway.

This primitive is the integration contract for the master plan; EP-2 and EP-4 will import it.
