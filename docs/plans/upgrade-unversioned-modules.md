# Support Upgrading Unversioned Modules

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

When a user runs `seihou upgrade`, modules without version information in their `module.dhall` are skipped with the message "skipped (unversioned)". This is frustrating because many modules — especially early-stage or simple ones — do not carry a version field, yet the user still wants to pull in the latest changes from the source repository.

After this change, unversioned modules will be upgraded by default. When neither the installed copy nor the remote copy has a version, Seihou will treat the module as "always upgradeable" and re-install it from the remote source. The user will see "upgraded" instead of "skipped (unversioned)" in the output table. This makes `seihou upgrade` useful for the common case of modules that evolve without formal versioning.


## Progress

- [x] Add `--skip-unversioned` flag to `UpgradeOpts` and CLI parser (2026-03-21)
- [x] Change `upgradeModule` to upgrade unversioned modules instead of skipping them (2026-03-21)
- [x] Update the footer help text to reflect the new behavior (2026-03-21)
- [x] Extract `compareVersions` and `OutdatedStatus` into `Seihou.CLI.VersionCompare` for testability (2026-03-21)
- [x] Add unit tests for `compareVersions` covering unversioned scenarios (2026-03-21)
- [x] Build and verify all 696 tests pass (56 CLI + 640 core) (2026-03-21)


## Surprises & Discoveries

- `Seihou.CLI.Outdated` was not exposed from the internal library (`seihou-cli-internal`), so tests couldn't import it. Extracted the pure `compareVersions` function and `OutdatedStatus` type into a new `Seihou.CLI.VersionCompare` module, exposed from the internal library. Both `Outdated.hs` and `Upgrade.hs` now re-import from `VersionCompare`. (2026-03-21)
- `doUpgrade` already handles `Nothing` versions correctly — it passes `ver` (which can be `Nothing`) through to `installModuleDir`. No changes were needed to `doUpgrade` or `renderUpgradeTable`. (2026-03-21)


## Decision Log

- Decision: Upgrade unversioned modules by default, add `--skip-unversioned` opt-out flag.
  Rationale: The current behavior of silently skipping unversioned modules is surprising and makes `upgrade` useless for simple modules. Users who want to skip unversioned modules can opt in to the old behavior with `--skip-unversioned`. This follows the principle of least surprise — "upgrade" should upgrade things.
  Date: 2026-03-21

- Decision: Treat "both sides unversioned" as unconditionally upgradeable rather than adding content hashing or git-commit tracking.
  Rationale: Content hashing adds significant complexity (recursive directory hashing, normalization, ignoring metadata files) for marginal benefit. Since modules are small and the install operation is cheap (copy files + write origin metadata), always re-installing is the simplest correct approach. A future enhancement could add content-aware skipping, but that is out of scope here.
  Date: 2026-03-21

- Decision: Introduce a new `OutdatedStatus` constructor `UnversionedChanged` rather than overloading existing constructors.
  Rationale: We want the `outdated` command to clearly distinguish "unversioned" from "up to date." A distinct constructor lets each command (`outdated`, `upgrade`) decide independently how to display unversioned modules without conflating their semantics.
  Date: 2026-03-21


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Seihou is a Haskell project scaffolding tool. Users install modules from remote git repositories via `seihou install <url>`. Each installed module is a directory under `~/.config/seihou/installed/<name>/` containing a `module.dhall` file (which defines the module's metadata including an optional `version` field) and a `.seihou-origin.json` file (which records the source URL, repo name, install timestamp, and the module's version at install time).

The upgrade flow works as follows: `seihou upgrade` discovers all installed modules, reads their `.seihou-origin.json` for origin metadata, groups them by source URL, clones each source repository into a temp directory, and compares the installed version against the available version. If the available version is newer, the module is re-installed from the clone.

The key files involved are:

`seihou-cli/src/Seihou/CLI/Upgrade.hs` — The main upgrade command handler. Contains `handleUpgrade` (entry point), `upgradeModule` (per-module decision logic), `doUpgrade` (performs the actual re-install), and `renderUpgradeTable` (output formatting). The `UpgradeStatus` type has constructors: `Upgraded`, `AlreadyUpToDate`, `Skipped`, `UpgradeFailed Text`, `SourceUnreachable`.

`seihou-cli/src/Seihou/CLI/Outdated.hs` — Shared version comparison logic used by both `outdated` and `upgrade` commands. Contains `compareVersions` (the function that returns `Unversioned` when either version is `Nothing` or unparseable), `findAvailableVersion` (reads version from remote module/registry), `OriginInfo` (type for `.seihou-origin.json` data), and `OutdatedStatus` (type with constructors: `UpToDate`, `OutdatedSt`, `Unversioned`, `Unreachable`).

`seihou-cli/src/Seihou/CLI/Commands.hs` — CLI command definitions using optparse-applicative. Contains `UpgradeOpts` (record with `upgradeModules`, `upgradeDryRun`, `upgradeJson` fields), `upgradeParser` (the optparse parser), and `upgradeFooter` (help text).

`seihou-cli/src/Seihou/CLI/Install.hs` — Module installation. Contains `installModuleDir` which copies module files and writes `.seihou-origin.json` with `OriginMeta`.

`seihou-core/src/Seihou/Core/Version.hs` — The `Version` newtype (a list of `Natural` segments), `parseVersion` (dotted string to `Maybe Version`), and `renderVersion`.

There are currently no tests for the upgrade or outdated commands.


## Plan of Work

The work has two milestones. The first adds the `--skip-unversioned` flag and changes the upgrade behavior so unversioned modules are upgraded by default. The second adds tests.


### Milestone 1: Change Upgrade Behavior for Unversioned Modules

At the end of this milestone, running `seihou upgrade` on a project with unversioned installed modules will re-install them from the remote source instead of skipping them. A `--skip-unversioned` flag will restore the old behavior for users who want it. The `outdated` command will show unversioned modules as "unversioned" (unchanged) since that command is purely informational.

**Step 1: Add `--skip-unversioned` to `UpgradeOpts`.**

In `seihou-cli/src/Seihou/CLI/Commands.hs`, add a `upgradeSkipUnversioned :: Bool` field to the `UpgradeOpts` record (after line 156, before the closing brace). Then in `upgradeParser` (line 641), add a new `<*>` clause with a `switch` for `--skip-unversioned` with help text "Skip modules without version information (default: upgrade them)".

**Step 2: Change `upgradeModule` to upgrade unversioned modules.**

In `seihou-cli/src/Seihou/CLI/Upgrade.hs`, the `upgradeModule` function (line 130) pattern-matches on `compareVersions` result. Currently, the `Unversioned` branch (line 145) returns `Skipped`. Change this to check `uopts.upgradeSkipUnversioned`: if the flag is set, keep the current `Skipped` behavior; otherwise, call `doUpgrade` (or return `Upgraded` for dry-run mode), mirroring the `OutdatedSt` branch logic.

The updated `Unversioned` case should look like:

    Unversioned
      | uopts.upgradeSkipUnversioned ->
          pure UpgradeEntry {moduleName = name, oldVersion = installedVer, newVersion = availableVer, upgradeStatus = Skipped}
      | uopts.upgradeDryRun ->
          pure UpgradeEntry {moduleName = name, oldVersion = installedVer, newVersion = availableVer, upgradeStatus = Upgraded}
      | otherwise ->
          doUpgrade cloneDir contents sourceUrl origin name installedVer availableVer

**Step 3: Update the footer help text.**

In `seihou-cli/src/Seihou/CLI/Commands.hs`, change the `upgradeFooter` text. Replace the line "Modules without version information are skipped." with "Modules without version information are upgraded by default. Use --skip-unversioned to skip them." Add a new example line: `seihou upgrade --skip-unversioned    # skip unversioned modules`.

**Step 4: Update the render table display.**

In `seihou-cli/src/Seihou/CLI/Upgrade.hs`, the `Skipped` display on line 205 currently shows "skipped (unversioned)". This is still correct — when `--skip-unversioned` is used, modules will show as `Skipped`. No change needed here. However, update the summary line at the bottom (line 221-228) to also count upgraded unversioned modules correctly — they will already be counted as `Upgraded`, so no change is needed there either.

Verification: build the project with `cabal build all` from the repo root. Then run `seihou upgrade --help` and confirm the `--skip-unversioned` flag appears.


### Milestone 2: Add Tests

At the end of this milestone, there will be unit tests covering `compareVersions` behavior and the upgrade decision logic for unversioned modules.

**Step 1: Create `seihou-cli/test/Seihou/CLI/UpgradeSpec.hs`.**

Write tests for the following scenarios using Hspec:

1. `compareVersions Nothing Nothing` returns `Unversioned` — this confirms the status detection works.
2. `compareVersions (Just "1.0") Nothing` returns `Unversioned`.
3. `compareVersions Nothing (Just "1.0")` returns `Unversioned`.
4. `compareVersions (Just "1.0") (Just "2.0")` returns `OutdatedSt`.
5. `compareVersions (Just "2.0") (Just "1.0")` returns `UpToDate`.
6. `compareVersions (Just "1.0") (Just "1.0")` returns `UpToDate`.

These are pure function tests and need no IO or file system setup.

**Step 2: Register the new test module.**

In `seihou-cli/test/Main.hs`, import `Seihou.CLI.UpgradeSpec` and add it to the test suite. Also add the test module to the cabal file's test-suite section if modules are listed explicitly.

**Step 3: Run tests.**

Run `cabal test seihou-cli-test` and verify all tests pass.


## Concrete Steps

All commands should be run from the repository root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

Build after Milestone 1:

    cabal build all

Expected: successful compilation with no errors.

Check help text:

    cabal run seihou-cli -- upgrade --help

Expected: the `--skip-unversioned` flag appears in the output, and the footer text reflects the new default behavior.

Run tests after Milestone 2:

    cabal test seihou-cli-test

Expected: all tests pass, including the new `UpgradeSpec` tests.


## Validation and Acceptance

**Acceptance criterion 1:** Running `seihou upgrade` with an unversioned installed module re-installs it from the source repository and displays "upgraded" in the output table, not "skipped (unversioned)".

**Acceptance criterion 2:** Running `seihou upgrade --skip-unversioned` with an unversioned installed module displays "skipped (unversioned)" — the old behavior is preserved behind the flag.

**Acceptance criterion 3:** Running `seihou upgrade --dry-run` with an unversioned installed module displays "upgraded" (indicating it would be upgraded) without actually modifying any files.

**Acceptance criterion 4:** The `compareVersions` unit tests all pass, covering all combinations of versioned and unversioned inputs.

**Acceptance criterion 5:** Running `seihou upgrade --help` shows the `--skip-unversioned` flag with appropriate help text.


## Idempotence and Recovery

All steps are idempotent. The upgrade operation itself is idempotent — re-running `seihou upgrade` on an already-upgraded unversioned module will simply re-install the same files. The `installModuleDir` function (in `seihou-cli/src/Seihou/CLI/Install.hs`) already handles the case where the install directory exists by removing it first and recreating it.

If a build fails partway through, simply fix the issue and run `cabal build all` again. Cabal's incremental compilation handles partial builds correctly.


## Interfaces and Dependencies

No new library dependencies are needed. The changes are entirely within existing modules.

After Milestone 1, the following interfaces will be modified:

In `seihou-cli/src/Seihou/CLI/Commands.hs`:

    data UpgradeOpts = UpgradeOpts
      { upgradeModules :: [Text],
        upgradeDryRun :: Bool,
        upgradeJson :: Bool,
        upgradeSkipUnversioned :: Bool
      }

In `seihou-cli/src/Seihou/CLI/Upgrade.hs`, `upgradeModule` will have the same type signature but different behavior in the `Unversioned` case — it will call `doUpgrade` instead of returning `Skipped` (unless `upgradeSkipUnversioned` is `True`).

After Milestone 2, a new test module will exist:

    seihou-cli/test/Seihou/CLI/UpgradeSpec.hs

    spec :: Spec   -- Hspec test suite for compareVersions
