# Make `seihou migrate` self-contained (no manual upgrade required)

MasterPlan: docs/masterplans/1-migrations-dx.md
Intention: intention_01kq5pe8hhekrrb9wg4eb1jz74

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, a user who runs `seihou migrate <module>` against a project where the applied module is older than the latest published version gets the migrations applied in a single command — no separate `seihou upgrade` step required.

Today, `seihou migrate` consults only the locally installed copy under `~/.config/seihou/installed/<name>/`. If the user has not run `seihou upgrade` (or if `upgrade` is broken — see EP-1, `docs/plans/14-fix-outdated-version-detection.md`), the installed copy still declares the same version as what's in the manifest, so migrate prints "✓ already at version X.Y.Z; nothing to do." even when migrations are pending against the public repo.

After this plan, `seihou migrate <module>` will:

1. Discover the source URL of the applied module from the manifest plus `~/.config/seihou/installed/<name>/.seihou-origin.json`.
2. Clone the remote (shallow), read the true latest version using the `fetchTrueModuleVersion` primitive from EP-1.
3. If the remote is newer, refresh `~/.config/seihou/installed/<name>/` from the cloned copy (the same step `seihou upgrade` performs).
4. Plan the migration chain from the manifest's recorded version to the new installed version.
5. Apply the chain (or print it under `--dry-run`).
6. Update the manifest's `moduleVersion` for that applied module.

You can see this working by running `seihou migrate master-plan` from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` after EP-1 ships and observing that files under `claude/skills/master-plan/` move to `agents/skills/master-plan/`, the manifest version updates from `0.1.0` to `0.3.0`, and no separate `seihou upgrade` was invoked.


## Progress

- [ ] Reproduce the "migrate says nothing to do despite a public update" bug.
- [ ] Read the current `handleMigrate` implementation; document the points where the installed-copy version is read.
- [ ] Introduce a `migrate --no-fetch` flag that preserves today's behavior for explicit local-only operation.
- [ ] Make the default `migrate <module>` path fetch the remote and refresh the installed copy when newer.
- [ ] Plan and apply the chain against the refreshed installed copy.
- [ ] Update the manifest's `moduleVersion` field after a successful chain.
- [ ] Add regression tests covering both the remote-fetch path and the `--no-fetch` path.
- [ ] End-to-end demonstration on the seihou-project working tree.
- [ ] Update `docs/cli/migrate.md` and `docs/user/migrations.md` and `docs/user/CHANGELOG.md`.


## Surprises & Discoveries

- **Read points in `Migrate.hs` that the fetch path replaces.** In `handleMigrate`,
  the installed `module.dhall` path is computed from `applied.source` at line 138:

      let installedDhall = applied.source </> "module.dhall"

  and parsed at lines 142–146. The "nothing to do" branch is the
  `Right Nothing` arm of `planMigrationChain` at lines 163–172:

      Right Nothing -> do
        ...
        TIO.putStrLn $
          applyColor colorEnabled green "✓"
            <> " "
            <> modName.unModuleName
            <> " is already at version "
            <> renderVersion toV
            <> "; nothing to do."
        exitSuccess

  In `runMigrate`, the analogous reads are at lines 236–248 (computing
  `installedDhall` from the `installedDir` parameter) and the `Right Nothing`
  arm at line 267 returns `MigrateNoOp toV` instead of printing.

  After this plan, the fetch path cleanly replaces the source dir for both
  reads: when fetch is enabled, `runMigrate` is called with the cloned
  module dir as `installedDir` instead of `applied.source`, so the same
  read sites end up looking at the remote's `module.dhall` and `migrations`.

- **Install helpers were executable-only.** `installModuleDir`, `cloneRepo`,
  and `copyDirectoryRecursive` lived in `Seihou.CLI.Install` (executable
  target only). To call them from `Seihou.CLI.Migrate` (library), they were
  extracted into a new library-exposed module
  `seihou-cli/src/Seihou/CLI/InstallShared.hs`. `OriginInfo` (read side of
  `.seihou-origin.json`) was moved there too so `Outdated.hs`,
  `Upgrade.hs`, and the new `Migrate.hs` fetch path all share a single
  definition. `cloneRepo` was changed from `IO ()` (with `exitFailure` on
  failure) to `IO (Either Text ())` so callers — especially the migrate
  fetch path — can recover and fall back to local-only behavior on
  unreachable remotes.


## Decision Log

- Decision: Default `migrate` to fetch-and-refresh; preserve today's local-only behavior under `--no-fetch`.
  Rationale: The current default is a UX trap (silent "nothing to do" when the user expects work). Making fetch the default aligns with what users mean when they type `seihou migrate <module>`. Preserving a flag for local-only operation keeps the testable, hermetic path available for advanced workflows.
  Date: 2026-04-26.

- Decision: Reuse `installModuleDir` from `seihou-cli/src/Seihou/CLI/Install.hs` to refresh the installed copy.
  Rationale: That function already atomically copies a cloned module directory into `~/.config/seihou/installed/<name>/` and is exercised by `seihou upgrade`. Reusing it avoids a parallel implementation.
  Date: 2026-04-26.


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

The migrate command lives at `seihou-cli/src/Seihou/CLI/Migrate.hs`. Its current shape:

- `handleMigrate :: MigrateOpts -> IO ()` — the IO shell invoked by the option parser in `seihou-cli/src/Seihou/CLI/Commands.hs`.
- `runMigrate :: MigrateInputs -> IO MigrateResult` — the testable core.
- `pendingChainFor :: AppliedModule -> Module -> Maybe MigrationChain` — given an applied-module record and the parsed installed `module.dhall`, returns the chain to walk from `appliedModule.moduleVersion` to `module.version`. If the two versions match, returns `Nothing` (i.e., "nothing to do").

The migration types and planner live in `seihou-core`:

- `seihou-core/src/Seihou/Core/Migration.hs` — `Migration`, `MigrationOp`, `MigrationChain`, `planMigrationChain`.
- `seihou-core/src/Seihou/Engine/Migrate.hs` — `executeMigration`, `classifyMigration`.

A "migration chain" here is a list of `Migration` records (`from`, `to`, `ops`) that, applied in order, walk from version A to version B. The planner uses topological reasoning over the `from`/`to` edges declared in `module.dhall`'s `migrations` field. Each `MigrationOp` is one of: `MoveFile { src, dest }`, `MoveDir { src, dest }`, `DeleteFile { path }`, `DeleteDir { path }`, `RunCommand { run, workDir }`.

The manifest is `<project>/.seihou/manifest.json`. The relevant Haskell type:

    data AppliedModule = AppliedModule
      { name :: ModuleName,
        parentVars :: ParentVars,
        source :: FilePath,
        moduleVersion :: Maybe Text,
        appliedAt :: UTCTime,
        removal :: Maybe Removal
      }

The `source` field is the path to the installed copy (e.g., `~/.config/seihou/installed/master-plan`). When the installed copy is refreshed, `source` does not change (path is the same), but its contents (and therefore the `version` you read from `<source>/module.dhall`) do.

The `.seihou-origin.json` file (written by `seihou install`) contains:

    { "sourceUrl": "https://github.com/...", "moduleName": "...", "sourceRevision": "..." }

It lives at `~/.config/seihou/installed/<name>/.seihou-origin.json`. EP-1's `fetchTrueModuleVersion` already operates on a cloned repo path; this plan adds the clone step in front of it.


## Plan of Work

### Milestone 1 — Reproduce the bug

In `seihou-cli/test/Seihou/CLI/MigrateSpec.hs`, add a test that:

1. Sets up an XDG-redirected fake "installed" tree at `~/.config/seihou/installed/demo/` containing `module.dhall` v1.0.0 and a `.seihou-origin.json` pointing at a temp remote.
2. Sets up the temp remote with `module.dhall` v2.0.0 and a single migration `{ from = "1.0.0", to = "2.0.0", ops = [MoveFile { src = "old.txt", dest = "new.txt" }] }`.
3. Sets up a project working tree with a manifest recording demo at v1.0.0 and `old.txt` on disk.
4. Invokes `runMigrate` with the new default behavior (fetch enabled).
5. Asserts: `new.txt` exists on disk, `old.txt` does not, manifest now records demo at v2.0.0.

Acceptance: the new test fails on master and passes after this plan ships.

### Milestone 2 — Read the current implementation

Read `Migrate.hs` end-to-end. In Surprises & Discoveries, append a short note quoting:

- The line where the installed `module.dhall` is parsed.
- The branch in `runMigrate` that returns "nothing to do" when versions match.

This makes the diff in subsequent milestones reviewable.

### Milestone 3 — Add `--no-fetch` flag

In `seihou-cli/src/Seihou/CLI/Commands.hs`, locate the `migrate` option parser. Add a `--no-fetch` boolean flag. Thread it into `MigrateOpts` (defined in `Migrate.hs`).

Default value: `False` (fetch is the new default; explicit `--no-fetch` opts out).

### Milestone 4 — Implement the fetch path

In `runMigrate`, when `migrateNoFetch` is `False`:

1. Read the manifest. Find the `AppliedModule` for the requested module name. If absent, error: `"module 'X' is not applied in this project."` (preserve today's message).
2. Read `<appliedModule.source>/.seihou-origin.json`. If absent, fall back to the local-only path with a warning.
3. Clone the `sourceUrl` shallowly into a temp directory.
4. Call `fetchTrueModuleVersion` (from EP-1) to determine the remote's true version.
5. Compare to the installed copy's current version (read from `<appliedModule.source>/module.dhall`):
   - If equal, fall through to the today's "nothing to do" path; do not refresh.
   - If newer, call `installModuleDir` to refresh the installed copy from the cloned source. (This step is already used by `seihou upgrade`; reuse it.)
6. Re-parse the installed `module.dhall` (now reflecting the new version) and proceed with `pendingChainFor` and chain execution as today.

After successful execution, write the new version into `appliedModule.moduleVersion` and persist the manifest.

### Milestone 5 — Tests

Add three test cases to `MigrateSpec.hs`:

- **Remote newer, fetch default.** Reuse the milestone-1 fixture; assert the chain ran and the manifest updated.
- **Remote equal, fetch default.** Assert "nothing to do" message and no filesystem changes outside the manifest.
- **Local-only with `--no-fetch`.** Even with a newer remote, the command must not clone or refresh; assert today's "nothing to do" or "applies a chain to whatever local says".

### Milestone 6 — End-to-end demonstration

From `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`:

    $ git status   # working tree clean before; record the diff after
    $ cabal run seihou-cli -- migrate master-plan --dry-run
    # expect: "1 migration pending: 0.1.0 -> 0.2.0 (6 operations)"
    $ cabal run seihou-cli -- migrate master-plan
    # expect: SKILL.md and MASTERPLAN.md moved to agents/skills/master-plan/
    # expect: manifest moduleVersion for master-plan updated to 0.3.0 (or whatever the latest is)

### Milestone 7 — Documentation and CHANGELOG

Update `docs/cli/migrate.md`: add a section "Default behavior: fetch first" and document the `--no-fetch` flag. Update `docs/user/migrations.md` to remove any "you must run upgrade first" guidance. Append to `docs/user/CHANGELOG.md`.


## Concrete Steps

From the repo root:

    $ cabal build seihou-cli
    $ cabal test seihou-cli --test-options="--match migrate"

Manual verification (run on a throwaway clone or commit your work first):

    $ cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    $ git diff   # confirm clean
    $ cabal run seihou-cli -- migrate master-plan --dry-run


## Validation and Acceptance

- `cabal test seihou-cli` passes including new tests.
- `seihou migrate master-plan --dry-run` against a project at master-plan 0.1.0 prints a chain (not "nothing to do") when the remote module.dhall is at a higher version.
- After `seihou migrate master-plan` (without `--dry-run`), the migration's file-move operations are applied on disk, and the manifest's `moduleVersion` for master-plan reflects the new version.
- `seihou migrate master-plan --no-fetch` against a project where the locally installed copy is the same version as the manifest still prints "nothing to do" without cloning anything (verifiable by running offline).


## Idempotence and Recovery

`installModuleDir` atomically replaces the installed directory; if interrupted, the old directory remains. The migration engine in `seihou-core/src/Seihou/Engine/Migrate.hs` is best-effort and does not roll back partial chains; in case of a failure mid-chain, the user is left in an intermediate state. This plan does not change that behavior; document it in `docs/user/migrations.md` if not already documented.

`--dry-run` performs no writes (no clone refresh, no chain execution). If `migrateNoFetch` is `True`, the command performs no network IO.


## Interfaces and Dependencies

This plan consumes the EP-1 primitive:

    fetchTrueModuleVersion :: ClonedRepoPath -> ModuleName -> IO (Either FetchError SemVer)

defined in `seihou-cli/src/Seihou/CLI/Outdated.hs` (or `RemoteVersion.hs` if EP-1 extracted it).

This plan reuses:

- `installModuleDir` from `seihou-cli/src/Seihou/CLI/Install.hs` to refresh the installed copy.
- `pendingChainFor`, `runMigrate`, and the existing migration engine in `seihou-core/src/Seihou/Engine/Migrate.hs`.
- The `git clone` helper used by `seihou install` and `seihou upgrade` (search `Seihou.CLI` for `cloneShallow` or similar; reuse).

This plan extends:

    data MigrateOpts = MigrateOpts
      { migrateModule :: ModuleName,
        migrateTo :: Maybe Text,
        migrateDryRun :: Bool,
        migrateForce :: Bool,
        migrateJson :: Bool,
        migrateVerbose :: Bool,
        migrateNoFetch :: Bool   -- new
      }

The integration contract with EP-3 (`docs/plans/16-make-run-migration-aware.md`): EP-3 will call into this plan's "fetch and refresh installed copy" logic during `seihou run --with-migrations`. To make that reuse possible, factor the new fetch-and-refresh step into a small helper:

    refreshInstalledFromRemote
      :: AppliedModule
      -> IO (Either RefreshError InstalledModulePath)

so EP-3 can invoke it without duplicating the clone/refresh dance.
