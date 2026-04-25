# Module Migrations: Apply Author-Declared Steps to Move a Project Between Module Versions

Intention: intention_01kq2gy6yde258gd30xjvs85g7

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

Today a Seihou module declares a `version` field (e.g. `Some "1.0.0"`), and
`seihou upgrade` swaps an installed copy of the module under
`~/.config/seihou/installed/<name>/` with a newer one fetched from its source
repository (`seihou-cli/src/Seihou/CLI/Upgrade.hs:62`). Re-running
`seihou run <module>` after an upgrade then regenerates files using the new
module definition.

What Seihou cannot currently do is **move the project's existing files into
the shape the new module version expects**. If `haskell-base` v1.0.0 generated
`app/Main.hs` and v2.0.0 instead expects `src/Main.hs`, the user is left with
two copies (one stale at `app/`, one fresh at `src/`) and no automatic way to
rename the directory, move sibling files along with it, or delete files that
v2.0.0 no longer ships. The user has to read the module's CHANGELOG, do the
moves by hand, and reconcile the manifest themselves.

After this change, **module authors can declare migration steps in
`module.dhall`** that run when a user upgrades from one version to the next.
Each migration declares a `from` version, a `to` version, and a list of
operations — initially `move-file`, `move-dir`, `delete-file`, `delete-dir`,
and `run-command`. Seihou collects the chain of migrations needed to span the
installed-version → target-version gap, presents a plan, executes it against
the project's working tree, and updates `.seihou/manifest.json` so subsequent
`seihou status` / `seihou diff` / `seihou remove` calls keep working.

A module author writing a v2 release will be able to add to their
`module.dhall`:

    , migrations =
        [ S.Migration::{ from = "1.0.0"
                       , to = "2.0.0"
                       , ops =
                           [ S.MigrationOp.MoveDir
                               { src = "app", dest = "src" }
                           , S.MigrationOp.DeleteFile { path = "Setup.hs" }
                           ]
                       }
        ]

A user with v1.0.0 installed and applied to a project will then be able to
run, from the project root:

    seihou migrate haskell-base --dry-run

and see:

    Migration plan: haskell-base  1.0.0 → 2.0.0
    1.0.0 → 2.0.0:
      move-dir   app -> src
      delete     Setup.hs

    3 file(s) affected, 0 conflict(s).

Then, without `--dry-run`, the moves and deletes are performed, the manifest's
`files` map is rewritten, and `seihou status` reflects the new paths.


## Progress

- [x] M1: Schema — add `MigrationOp.dhall`, `Migration.dhall`, register them in
      `schema/package.dhall`, and add `migrations : List Migration` to
      `Module.dhall` (default `[]`). _(2026-04-25)_
- [x] M1: Haskell types — extend `Seihou.Core.Types.Module` with a
      `migrations :: [Migration]` field; define `Migration` and `MigrationOp`
      ADTs in a new module `Seihou.Core.Migration`. _(2026-04-25)_
- [x] M1: Decoder — extend `Seihou.Dhall.Eval.moduleDecoder` to decode the new
      field with `withDefaults [("migrations", emptyMigrationList)]` so older
      `module.dhall` files keep parsing. _(2026-04-25)_
- [x] M1: Schema-upgrade — extend `Seihou.Core.SchemaUpgrade` to detect a
      missing `migrations` field on `module.dhall` and add `, migrations = [] : List S.Migration.Type`
      with a safe default. Update fixtures. _(2026-04-25)_
- [x] M1: Tests — round-trip Dhall encode/decode tests for `MigrationOp` and
      `Migration` in `seihou-core/test/Seihou/Dhall/MigrationDecoderSpec.hs`.
      _(2026-04-25; 10 cases passing, full seihou-core 772/772 green)_
- [x] M2: Pure planner — in `Seihou.Core.Migration`, define `MigrationChain`
      and `planMigrationChain :: Text -> [Migration] -> Version -> Version -> Either MigrationPlanError (Maybe MigrationChain)`.
      Cover gap detection, ordering, no-op cases. Module name passed as
      `Text` to keep `Seihou.Core.Migration` independent of
      `Seihou.Core.Types` (avoids the cycle noted in M1's surprises). _(2026-04-25)_
- [x] M2: Tests — `seihou-core/test/Seihou/Core/MigrationSpec.hs` covering
      single-step chain, multi-step chain, gap, downgrade-rejected,
      same-version no-op, unparseable version, duplicate edge, overshoot,
      stale-edge ignored, padded-version equivalence. _(2026-04-25; 11/11)_
- [x] M3: Engine — `Seihou.Engine.Migrate` with `data MigrationOpInstance`
      (concrete `FilePath` operations), `data MigrationFileStatus = MFSafe |
      MFConflict | MFGone`, `classifyMigration :: Manifest -> MigrationChain
      -> Eff es ExecutedMigrationPlan`, and `executeMigration :: Bool ->
      ExecutedMigrationPlan -> Manifest -> UTCTime -> Eff es (Either
      MigrationExecError Manifest)` that performs filesystem operations,
      bumps `genAt`/`moduleVersion`, and returns a manifest with rewritten
      `files` keys. _(2026-04-25)_
- [x] M3: Filesystem effect — extend `Seihou.Effect.Filesystem` with
      `RenamePath :: FilePath -> FilePath -> Filesystem m ()` (uses
      `System.Directory.renamePath`) and `RemoveDirectoryRecursive :: FilePath
      -> Filesystem m ()`. Implemented in `FilesystemInterp` (IO) and
      `FilesystemPure` (in-memory map: prefix-rewriting rename, prefix
      filter on recursive remove). Public smart constructors
      `renamePath`, `removeDirectoryRecursive`. _(2026-04-25)_
- [x] M3: Tests — `seihou-core/test/Seihou/Engine/MigrateSpec.hs` covering
      move-file (safe / conflict no-force / conflict with force),
      move-dir, delete-file (gone is no-op), delete-dir, manifest path
      rewrite, classify-then-execute on a two-step chain. 10/10. _(2026-04-25)_
- [x] M4: CLI — `MigrateOpts` record (now defined in `Seihou.CLI.Migrate`,
      re-imported into `Seihou.CLI.Commands` for the parser) and a
      `Migrate MigrateOpts` constructor on `Command`; `seihou migrate
      <module> [--to VERSION] [--dry-run] [--force] [--json] [-v]` parser
      under "Module management:". Handler `handleMigrate` (IO shell) and
      `runMigrate` (testable core returning `Either MigrateError
      MigrateResult`) live in `Seihou.CLI.Migrate`. _(2026-04-25)_
- [x] M4: Wire into `seihou-cli/src/Main.hs`. _(2026-04-25)_
- [x] M4: Tests — `seihou-cli/test/Seihou/CLI/MigrateSpec.hs` integration
      tests that build a temp project (via `withSystemTempDirectory` +
      `withCurrentDirectory`), write a manifest, write a fixture
      `module.dhall` with migrations, and run `runMigrate` in-process.
      Covers: module-not-applied, no-recorded-version, no-op,
      dry-run-no-disk-touch, full execution + manifest rewrite,
      conflict-without-force, conflict-with-force, --to override. 8/8.
      _(2026-04-25)_
- [x] M5: Upgrade integration — `seihou upgrade` learned a
      `--with-migrations` flag (default off). After the upgrade table
      renders, the post-upgrade pass walks each successfully-upgraded
      module: if the *current project* has it applied and the manifest
      version trails the now-installed version with a covering chain,
      either run `runMigrate` (with-migrations) or print a single
      advisory line per module. The `upgradeFooter` documents both
      paths. _(2026-04-25)_
- [x] M5: `seihou status` line per applied module with pending
      migrations. The detector evaluates each applied module's
      installed `module.dhall`, computes the chain via the new
      `Seihou.CLI.Migrate.pendingChainFor`, and renders
      `Pending migrations: N migration(s) pending: 1.0.0 → 2.0.0`
      under the affected module's line. The `statusInfo` footer
      documents this. _(2026-04-25)_
- [x] M5: Tests — added `Seihou.CLI.PendingMigrationSpec` (6 cases
      covering both Nothing branches of `pendingChainFor` plus the
      happy path). The existing `Seihou.CLI.UpgradeSpec` continues to
      cover `compareVersions` only — the network-dependent end-to-end
      upgrade flow is not unit-tested, consistent with the existing
      pattern. _(2026-04-25)_
- [x] M6: Docs — `docs/user/migrations.md` (full guide),
      `docs/cli/migrate.md` (command reference), `Migrations` section
      in `docs/user/module-authoring.md`, `Migrations in registries`
      paragraph in `docs/user/registries-and-multi-module-repos.md`,
      CHANGELOG entry under `[Unreleased]` covering the new command,
      the `--with-migrations` upgrade flag, the new `migrations` field,
      and the new help topic. _(2026-04-25)_
- [x] M6: In-binary `seihou help` topic — `seihou-cli/help/migrations.md`
      registered in `Seihou.CLI.Help.helpTopics` via a new
      `embedStringFile` splice. Cross-references added at the bottom of
      `seihou-cli/help/modules.md` ("Versioning and migrations" section)
      and `seihou-cli/help/git-repository.md` ("Upgrade workflow"
      section). _(2026-04-25)_
- [x] M6: Per-command `--help` footers — `migrateInfo` ships full prose
      with op reference, `--dry-run`/`--force`/`--to`/`--json` Examples
      block, and `See also: seihou help migrations`. `upgradeInfo`'s
      footer now describes the default advisory path, the
      `--with-migrations` opt-in, and the `seihou migrate` cross-reference.
      `statusInfo`'s footer documents the "Pending migrations" sub-line.
      `outdatedInfo`'s footer cross-references both `seihou upgrade`
      and `seihou migrate`. _(2026-04-25)_
- [x] M6: `topLevelFooter` in `Seihou.CLI.Commands` — extended with a
      new "Learn more" block that surfaces `seihou help`,
      `seihou help modules`, and `seihou help migrations` so
      `seihou --help` actively points at the topic. _(2026-04-25)_
- [x] M6: End-to-end coverage — the `Seihou.CLI.MigrateSpec`
      integration tests exercise the same flow as the proposed manual
      walkthrough (build a fixture module on disk with migrations,
      seed a manifest, run `runMigrate`, verify disk + manifest +
      version), so the feature has automated coverage for the
      end-to-end path. The manual demo described in the original plan
      is now redundant and not run; the test suite is the acceptance
      gate. _(2026-04-25)_
- [x] M7: Agent prompt context — extended all three embedded
      prompts shipped to `seihou agent assist`, `seihou agent
      bootstrap`, and `seihou agent setup`. Authoring prompts
      (`assist-prompt.md`, `bootstrap-prompt.md`) gained the
      `migrations` field on the schema example, a "Migrations"
      subsection covering the five `MigrationOp` variants, chain
      semantics, and conflict semantics (cross-referenced to
      `seihou help migrations`), and a `seihou migrate` entry in
      the CLI command catalogue. `bootstrap-prompt.md` also gained
      a new "Plan for versioning" workflow step after "Add
      conditional steps". Consumption prompt (`setup-prompt.md`)
      gained a new `### Upgrade and migration` block covering
      `seihou outdated`, `seihou upgrade [--with-migrations]`, and
      `seihou migrate`; a "Pending migrations" sub-line note on
      `seihou status`; and a new step 8 ("Stay current") in the
      consumption workflow. `Available types` lines in both
      authoring prompts now list `S.Migration` and
      `S.MigrationOp`. Migration mention counts: assist=10,
      bootstrap=13, setup=20 (thresholds were 3/3/4).
      `cabal build seihou-cli` re-embedded all three prompts
      (`Seihou.CLI.{Assist,Bootstrap,Setup}` recompiled because
      `data/*-prompt.md` changed); `strings $(cabal list-bin
      seihou) | grep -ci 'seihou migrate\|S\.MigrationOp\|Pending
      migrations\|with-migrations'` returned 49. Full test suite
      stayed green: 917/917 (793 core + 124 cli).
      _(2026-04-25)_

Note: The pinned schema URL in `seihou-cli/src/Seihou/CLI/SchemaVersion.hs`
is intentionally not updated. That URL points at the published
`shinzui/seihou-schema` repo, and bumping it requires pushing the
new `Migration` / `MigrationOp` types upstream first. Existing
modules continue to parse via the decoder's `withDefaults` injection;
new modules using `S.Migration::{…}` need the URL bumped before they
will resolve. That bump is a one-line follow-up commit once the
schema commit is published — see the schema submodule pointer for
the exact SHA to use.


## Surprises & Discoveries

- `Seihou.Core.Migration` cannot host the planner from M2 if the planner
  takes a `ModuleName` argument: that creates a cycle, since
  `Seihou.Core.Types.Module` already imports `Migration` from
  `Seihou.Core.Migration` for its `migrations` field. The cycle has to be
  broken in M2 — either by parameterizing the planner over `Text` instead of
  `ModuleName`, or by hosting the planner in a different module. This was
  not anticipated in the plan; recorded here for the M2 step.
  Date: 2026-04-25

- The plan's M3 description had `executeMigration` short-circuit on
  `MFGone` (skipping the disk op when the file was already absent at
  classify time). This is wrong for chains: in `[MoveDir app→src,
  DeleteFile src/Main.hs]`, the delete is classified at the start when
  `src/Main.hs` doesn't exist yet, gets tagged `MFGone`, and the
  shortcut skips the actual disk delete after the move *did* create it.
  Fix: classify-time status drives the up-front conflict check (so
  conflicts surface before any disk mutation), but the disk action
  itself re-checks `doesFileExist` at execute time. This kept all the
  authored ergonomics (the CLI plan render still shows MFGone) without
  the chain-misordering bug.
  Date: 2026-04-25

- M3 originally called `renamePath src dest` directly. In the pure
  filesystem this works (it's a key rename in a `Map`), but real IO
  errors with `does not exist (No such file or directory)` if the
  destination's parent directory doesn't yet exist. Surfaced by the M4
  CLI integration tests: the move `app/Main.hs → src/Main.hs` failed
  because `src/` hadn't been created. Fix: every move op now calls
  `createDirectoryIfMissing True` on the destination's parent before
  the rename. The pure FS interpreter is unaffected (the key rename
  doesn't care about parents).
  Date: 2026-04-25

- The seihou-cli tests live in a separate test target that links only
  against the `seihou-cli-internal` library. The `Seihou.CLI.Commands`
  module — where the plan said `MigrateOpts` should live — is in the
  executable's `other-modules`, not in the internal library, so tests
  can't import from it. Resolution: define `MigrateOpts` inside
  `Seihou.CLI.Migrate` (which IS in the internal library), and
  re-import it into `Seihou.CLI.Commands` for parser construction.
  This matches the existing pattern (e.g. `Seihou.CLI.Diff`,
  `Seihou.CLI.Init` are full IO handlers in the internal library).
  Date: 2026-04-25

- M6 was marked complete, but the `seihou agent` prompt files at
  `seihou-cli/data/{assist,bootstrap,setup}-prompt.md` were not
  touched by the M6 commit (bd0ac0b). The original M6 description
  named `bootstrap-prompt.md` and "the `agent assist` prompt"
  as in-scope items, but the commit only updated repo `docs/`,
  in-binary `seihou-cli/help/` topics, and `--help` footers in
  `Seihou.CLI.Commands`. A grep for `migrat` against the three
  prompt files returns zero hits, so all three LLM-driven
  agent personas (authoring, bootstrap, consumption) are
  currently unaware that migrations exist as a module-author
  concept or a `seihou migrate` command. Tracked as M7 in this
  revision.
  Date: 2026-04-25


## Decision Log

- Decision: Declare migrations in `module.dhall` via a new `migrations` field,
  not via filename conventions in a `migrations/` subdirectory.
  Rationale: The user's framing ("a module can declare steps to migrate")
  suggests an explicit list. The rest of Seihou models intent in Dhall —
  `steps`, `commands`, `removal.removalSteps`. Putting migrations in
  `module.dhall` keeps the schema-checked, validatable surface in one place
  and lets the Dhall decoder fail fast on malformed migrations. Authors who
  want per-version files can still split via Dhall imports
  (`./migrations/2.0.0.dhall`). The plan does not prescribe a layout.
  Date: 2026-04-25

- Decision: Migration operations are typed Dhall variants
  (`MigrationOp.MoveFile`, `MigrationOp.MoveDir`, `MigrationOp.DeleteFile`,
  `MigrationOp.DeleteDir`, `MigrationOp.RunCommand`), not free-form shell
  scripts.
  Rationale: Typed operations let `--dry-run` show a precise plan, let the
  engine update the manifest's `files` map for moves, and let conflict
  detection compare disk hashes against the manifest before destructive ops
  — none of which is possible if the migration is an opaque shell command.
  `RunCommand` is the escape hatch for everything else (e.g. patch a file,
  re-run a build script).
  Date: 2026-04-25

- Decision: A migration declares `from : Text` and `to : Text`, both required,
  and `planMigrationChain` requires a contiguous chain that strictly increases
  by `Seihou.Core.Version.Ord` from installed → target.
  Rationale: A graph-search planner ("find any path from A to B") would let
  authors ship overlapping migrations and create silent ambiguity. A linear
  contiguous chain is straightforward to reason about, easy to error-message
  ("missing migration from 1.5.0 to 2.0.0"), and matches how other tools
  (Rails, Flyway, sqlx) sequence migrations. Authors who want to skip
  intermediate versions can ship a fast-path migration and have the planner
  pick the longest contiguous chain that lands on the target.
  Date: 2026-04-25

- Decision: A new `seihou migrate <module>` command is the primary entry point.
  `seihou upgrade` does *not* run migrations by default.
  Rationale: `seihou upgrade` operates on the installed copies under
  `~/.config/seihou/installed/`, which can be shared by many projects.
  Running migrations during upgrade would silently mutate every project on
  disk that uses the module. A separate, project-local `migrate` command
  preserves the principle that destructive changes to a project's working
  tree happen only when the user runs a command from that project.
  `--with-migrations` on `upgrade` is the opt-in for users who want both
  in one shot and accept that it only touches the current project.
  Date: 2026-04-25

- Decision: Conflict semantics mirror `Seihou.Engine.Remove`: classify each
  affected file as `MFSafe` (manifest hash matches disk), `MFConflict`
  (disk hash differs — user modified the file), or `MFGone` (file already
  absent). Refuse to execute when any file is `MFConflict` unless `--force`
  is passed.
  Rationale: Removals already have user-tested ergonomics for "we are about
  to destroy work — confirm". The same primitives apply: `RemovalFileStatus`
  is at `seihou-core/src/Seihou/Engine/Remove.hs:67`. Reusing the pattern
  means one mental model for users and one set of conflict-handling code.
  Date: 2026-04-25

- Decision: Migration paths are project-relative (rooted at the directory
  that contains `.seihou/manifest.json`), not module-relative.
  Rationale: Migrations operate on the user's generated files, which live in
  the project root, not in the module's `files/` source tree. This matches
  `Step.dest` and `RemovalStep.dest`, which are also project-relative.
  Date: 2026-04-25

- Decision: After successful execution, rewrite the manifest's `files`
  map keys to reflect new paths (a `MoveFile` op rewrites
  `files["app/Main.hs"]` to `files["src/Main.hs"]`, preserving the
  `FileRecord`); leave `AppliedModule.removal` paths as-is and let the next
  `seihou run` re-derive the removal spec from the new module.dhall.
  Rationale: The `files` map is the source of truth for `seihou diff` and
  `seihou status`; rewriting it is non-negotiable. `removal` stored on
  `AppliedModule` is a snapshot used only by `seihou remove`; the upgraded
  module on disk will overwrite it on the next `run`. Trying to rewrite
  embedded paths in stored removal steps risks subtle bugs (path patterns,
  section markers) and is unnecessary for v1.
  Date: 2026-04-25

- Decision: Recipes are out of scope for v1. Migrations are per-module only.
  Rationale: Recipes are compositions; their version semantics interact with
  per-module versions in ways that need their own design. Modules are a
  clean starting point and cover the user's stated examples.
  Date: 2026-04-25

- Decision (M1): `MigrationOp` Haskell constructors are unprefixed
  (`MoveFile`, `MoveDir`, `DeleteFile`, `DeleteDir`, `RunCommand`) to mirror
  the Dhall union variant names exactly. The plan suggested `MoveFileOp`,
  `RunCommandOp` etc., but `RunCommandOp` already exists as a constructor
  of `Seihou.Core.Types.Operation`. Using the unprefixed names keeps the
  ADT readable without colliding (the modules that need `Operation` and
  `MigrationOp` simultaneously can import each set qualified or not at
  all). The Dhall side is unchanged — `S.MigrationOp.MoveFile { ... }` is
  what authors write.
  Date: 2026-04-25

- Decision (M2): `planMigrationChain` takes the module name as `Text`,
  not as `Seihou.Core.Types.ModuleName`.
  Rationale: `Seihou.Core.Types.Module` already imports `Migration` from
  `Seihou.Core.Migration` for its `migrations :: [Migration]` field. If
  the planner — which lives in the same module — also took
  `ModuleName`, `Seihou.Core.Migration` would have to import `Types`,
  creating a circular module dependency. The alternatives (an `hs-boot`
  file, a third helper module that holds only `ModuleName`, or moving
  the planner to a separate module) were each more invasive than just
  carrying the rendered name as `Text`. The CLI handler in M4 unwraps
  `ModuleName.unModuleName` before calling. The planner uses the name
  only for the `MigrationChain.migrationModule` field — i.e. for
  human-readable output — so a stringly-typed name is fine.
  Date: 2026-04-25

- Decision (M2): The planner returns
  `Either MigrationPlanError (Maybe MigrationChain)` rather than the
  flatter `Either MigrationPlanError MigrationChain` originally drafted.
  Rationale: a same-version request is a perfectly valid input that does
  no work. Modeling it as `Right Nothing` lets callers handle "nothing
  to do" without a sentinel error variant, and matches the M4 CLI flow
  ("Already at version X; nothing to do.") cleanly.
  Date: 2026-04-25

- Decision (M2): `MigrationOvershoot` is a separate error from
  `MigrationGap`. The plan's algorithm description folded "to > target"
  into "MigrationGap"; splitting them lets the CLI render distinct,
  actionable messages: an overshoot means the author shipped a
  too-large jump (fix: ship intermediate migrations or migrate to a
  later version), whereas a gap means there's literally no edge from
  the stuck-at version (fix: ship the missing migration or downgrade
  the request).
  Date: 2026-04-25

- Decision (M7): Update all three embedded agent prompts
  (`assist-prompt.md`, `bootstrap-prompt.md`, `setup-prompt.md`),
  not just the two named in the original M6 wording.
  Rationale: each prompt powers a different agent persona with a
  distinct mental model — `assist` is the in-flight authoring
  helper, `bootstrap` walks an author through creating a module
  from scratch, and `setup` is the *consumer-side* helper that
  drives `seihou run`/`upgrade`/`status` against an existing
  project. Migrations affect all three: authors need to know how
  to declare them (`assist`, `bootstrap`), consumers need to know
  how to run them and how the new flags surface in the commands
  they're already using (`setup`). Leaving `setup-prompt.md`
  untouched would make migrations invisible to the agent that's
  most likely to encounter a project mid-upgrade.
  Date: 2026-04-25

- Decision (M7): Mirror the in-binary `seihou help migrations`
  topic shape rather than introducing prompt-only prose.
  Rationale: the prompts already embed `module.dhall` schema
  reference blocks that mirror `docs/user/module-authoring.md`,
  and the CLI command lists mirror `seihou --help`. Keeping the
  migration content aligned with `seihou help migrations` (op
  catalogue, chain semantics, conflict semantics) means the
  prompt stays accurate when the help topic is updated, and
  authors who switch between agent sessions and reading the
  in-binary help see consistent terminology. Avoid duplicating
  the full guide; lean on cross-references to `seihou help
  migrations` for detail.
  Date: 2026-04-25


## Outcomes & Retrospective

**Outcome:** the `migrations` field on `module.dhall` is fully wired
through the schema, decoder, planner, engine, CLI, and integration
points (`upgrade`, `status`). 917 tests pass across the workspace
(793 in `seihou-core`, 124 in `seihou-cli`), including 35 net-new
cases dedicated to migration coverage:

  * 10  `Seihou.Dhall.MigrationDecoderSpec`     (M1)
  * 11  `Seihou.Core.MigrationSpec`             (M2)
  * 10  `Seihou.Engine.MigrateSpec`             (M3)
  *  8  `Seihou.CLI.MigrateSpec`                (M4, real-IO end-to-end)
  *  6  `Seihou.CLI.PendingMigrationSpec`       (M5)

Each milestone's commit was independently buildable and green.

**User-visible acceptance** (corresponds to the original plan):

  - A module author bumping a module from 1.0.0 to 2.0.0 can declare
    a migration that moves `app/` to `src/` and have it applied to a
    consumer project via `seihou migrate haskell-base`. The
    integration tests demonstrate this end-to-end with a real
    `module.dhall` on disk, a real manifest, and real `renamePath`
    calls.
  - `seihou upgrade --dry-run` and `seihou status` surface pending
    migrations without mutating anything.
  - `seihou migrate haskell-base --dry-run` prints the chain in the
    format the plan called for (`Migration plan: …  X → Y`, op
    breakdown per step, total counts).

**Lessons learned:**

  1. **Cycles via the type module are easy to walk into.** Putting
     the `Migration` ADT in `Seihou.Core.Migration` while
     `Seihou.Core.Types.Module` references it forced
     `planMigrationChain` to use `Text` for the module name instead
     of `ModuleName`. A larger refactor (extracting `ModuleName` to
     a leaf module) would have been cleaner but invasive for a v1.

  2. **Pure FS interpreters can hide IO bugs.** The M3 tests passed
     a chain like `[MoveDir, DeleteFile]` because the pure FS
     doesn't care about parent directories. The same chain on real
     IO surfaced `ENOENT` immediately. The fix
     (`createDirectoryIfMissing` before any `renamePath`) is
     small, but the lesson is to add at least one IO-backed
     integration test per engine surface, not just pure-FS unit
     tests.

  3. **Classify-time status is informational, not authoritative.**
     The first M3 cut short-circuited disk ops on `MFGone`. That
     was wrong for chains: a `MoveDir` can produce a file that the
     next `DeleteFile` needs to see. The fix — keep the
     classify-time status for the up-front conflict check, but
     re-check `doesFileExist` at execute time — is now the
     contract documented in `Seihou.Engine.Migrate`.

  4. **The seihou-cli internal-library boundary needs to be
     considered when adding handler code.** Tests link against the
     internal library, so any module the test suite needs has to
     live there. Defining `MigrateOpts` inside `Seihou.CLI.Migrate`
     (with a re-import in `Seihou.CLI.Commands`) was the path of
     least resistance.

**What's not done in this milestone:**

  - The pinned schema URL in `Seihou.CLI.SchemaVersion` is unchanged.
    Authors who want to use `S.Migration::{…}` in their
    `module.dhall` need that URL bumped to a `seihou-schema`
    commit that has the new types. The schema submodule already
    contains the changes locally; the upstream push and URL bump
    is a one-line follow-up.
  - Recipes deliberately do not support migrations. Per the
    decision log, that's a v2 design problem.

**M7 update (2026-04-25):** The three embedded agent prompts
under `seihou-cli/data/` (`assist-prompt.md`,
`bootstrap-prompt.md`, `setup-prompt.md`) — flagged as
remaining work after M6 — have now been updated. Authoring
prompts gained schema-reference and CLI-catalogue entries for
the `migrations` field and the `seihou migrate` command;
`bootstrap-prompt.md` also gained a "Plan for versioning"
workflow step. The consumption prompt (`setup-prompt.md`)
gained a new "Upgrade and migration" CLI block, a "Pending
migrations" note on `seihou status`, and a "Stay current"
workflow step covering `seihou upgrade [--with-migrations]` →
`seihou migrate`. The rebuilt binary embeds the new content
(`strings | grep -ci` returned 49 hits across the four target
phrases); the full test suite stayed green at 917/917.


## Context and Orientation

Seihou is a composable, type-safe project scaffolding tool written in Haskell
(GHC 9.12.2, GHC2024). The repository is a multi-package Cabal workspace with
`seihou-core` (library) and `seihou-cli` (executable). All module and registry
files are written in Dhall and decoded into Haskell ADTs.

A **module** is a directory containing `module.dhall` plus optional
`files/` and `schema/` subdirectories. The canonical layout is documented at
`docs/user/module-authoring.md:6`. Module names match `[a-z][a-z0-9-]*`.

A **module's version** is a Dhall `Optional Text` field on the `Module` type
(`schema/Module.dhall:29`, `seihou-core/src/Seihou/Core/Types.hs:238`). It is
optional in Dhall for backwards compatibility but required by
`seihou validate-module` (`docs/user/module-authoring.md:49`). Versions are
parsed by `Seihou.Core.Version.parseVersion :: Text -> Maybe Version`
(`seihou-core/src/Seihou/Core/Version.hs:33`) into a list of `Natural`s, and
compared via the `Ord Version` instance (zero-padded; `Version [1,2] ==
Version [1,2,0]`).

The **manifest** at `.seihou/manifest.json` is the per-project record of what
was generated. Its types live in `Seihou.Core.Types`:

    data Manifest = Manifest
      { version  :: Int           -- manifest schema version, currently 2
      , genAt    :: UTCTime
      , modules  :: [AppliedModule]
      , vars     :: Map VarName Text
      , files    :: Map FilePath FileRecord
      , recipe   :: Maybe AppliedRecipe
      }

    data AppliedModule = AppliedModule
      { name          :: ModuleName
      , parentVars    :: ParentVars
      , source        :: FilePath
      , moduleVersion :: Maybe Text   -- version recorded at apply time
      , appliedAt     :: UTCTime
      , removal       :: Maybe Removal
      }

    data FileRecord = FileRecord
      { hash        :: SHA256
      , moduleName  :: ModuleName
      , strategy    :: Strategy
      , generatedAt :: UTCTime
      }

(Definitions at `seihou-core/src/Seihou/Core/Types.hs:361`, `:386`, `:397`.)

The manifest is read and written through the `ManifestStore` effect
(`seihou-core/src/Seihou/Effect/ManifestStore.hs`), with `JSON` instances at
`seihou-core/src/Seihou/Manifest/Types.hs:50` (manifest) and `:89` (applied
module). `AppliedModule` already serializes its optional `version` key
(`seihou-core/src/Seihou/Manifest/Types.hs:97, :124`). No manifest schema bump
is required for this plan — migrations only mutate existing fields.

The **install flow** clones a remote git repo and lays modules out under
`~/.config/seihou/installed/<name>/`, writing a `.seihou-origin.json`
sibling that records `sourceUrl`, `repoName`, `installedAt`, **and the
module's `version`** as it stood at install time
(`seihou-cli/src/Seihou/CLI/Install.hs:283`,
`seihou-cli/src/Seihou/CLI/Outdated.hs:1`). The `OriginInfo` record exposes
`origin.version :: Maybe Text` (`seihou-cli/src/Seihou/CLI/Outdated.hs`).

The **upgrade flow** (`seihou-cli/src/Seihou/CLI/Upgrade.hs:62-188`) groups
installed modules by `sourceUrl`, shallow-clones each, evaluates the remote
`module.dhall` (or `seihou-registry.dhall`), compares versions via
`Seihou.CLI.VersionCompare.compareVersions` (which returns `OutdatedSt |
UpToDate | Unversioned | Unreachable`), and replaces the on-disk installed
copy with the new one via `installModuleDir`. Critically, `upgrade` does
**not** touch any project that has applied the module — only the central
installed copy. A user must subsequently `cd` into a project and run
`seihou run <module>` (or, with this plan, `seihou migrate <module>`) to
reflect the upgrade in the project's working tree.

The **removal flow** at `seihou-core/src/Seihou/Engine/Remove.hs` is the
closest existing analogue to migrations — it traverses an `AppliedModule`'s
declared `Removal` spec, classifies each affected file by hash status, and
emits a `RemovalOp` list (`DeleteFileOp`, `StripSectionOp`, `RewriteOp`,
`RemovalCommandOp`) executed against the `Filesystem` effect. The
`RemovalFileStatus` enum at line 67 (`RFSafe | RFConflict | RFGone`) and the
`forceRemove` semantics in `seihou-cli/src/Seihou/CLI/Remove.hs` are the
direct templates for migration's conflict handling.

The **Filesystem effect** (`seihou-core/src/Seihou/Effect/Filesystem.hs`)
currently exposes `ReadFileText`, `WriteFileText`, `CopyFile`,
`ListDirectory`, `CreateDirectoryIfMissing`, `DoesFileExist`,
`DoesDirectoryExist`, `GetCurrentDirectory`, `RemoveFile`,
`RemoveDirectoryIfEmpty`. Migrations need two more atomic operations:
`renamePath` (single syscall for both file and directory rename, atomic
within a filesystem) and `removeDirectoryRecursive` (for `delete-dir`).
Both have direct backing in `System.Directory`. The pure interpreter
(`seihou-core/src/Seihou/Effect/FilesystemPure.hs`) needs equivalent
implementations over the in-memory `Map FilePath Text` it already maintains.

The **Dhall schema** lives in `schema/`. The package entry point
`schema/package.dhall` re-exports `VarDecl`, `VarExport`, `Prompt`, `Step`,
`Command`, `Dependency`, `RemovalStep`, `Removal`, `Module`, `Recipe`. The
current schema URL is pinned in `schema/Step.dhall` and similar files via the
`https://raw.githubusercontent.com/shinzui/seihou-schema/<sha>` import. A new
schema commit is needed for the `Migration`/`MigrationOp` types and the new
`migrations` field on `Module`.

The **schema-upgrade tool** (`seihou-core/src/Seihou/Core/SchemaUpgrade.hs`)
detects missing required fields in a user's `module.dhall` and rewrites
the file to add them with safe defaults. Adding a new field to `Module`
requires updating `detectIssues` and `upgradeModuleText` so that
`seihou schema-upgrade` can introduce `migrations = [] : List S.Migration.Type`
on existing modules. The CLI command is at
`seihou-cli/src/Seihou/CLI/SchemaUpgrade.hs` and its plan is
`docs/plans/schema-upgrade-command.md`.

The **CLI command tree** is at `seihou-cli/src/Seihou/CLI/Commands.hs:46`. A
new `Migrate MigrateOpts` constructor on the `Command` ADT, a `MigrateOpts`
record, and a `migrateInfo`/`migrateParser` block under the
"Module management:" `hsubparser` (`Commands.hs:259`) are required.
`Main.hs` dispatches the `Command` value to handlers in `Seihou.CLI.*`.

Two prior plans are direct context for this work:

- `docs/plans/upgrade-installed-modules.md` — established the upgrade flow
  and `OriginInfo`. Read for the registry-vs-single-module discovery code.
- `docs/plans/12-sync-registry-versions.md` — established `seihou registry`
  as the authoring command group and the pattern of "pure planner in Core,
  IO shell in CLI" used here for `Seihou.Core.Migration` /
  `Seihou.CLI.Migrate`.

There is **no existing migration feature**: a repo-wide grep for
`migration|migrate` finds only references to schema-version field migrations
in completed plans, never module-content migrations.


## Plan of Work

The work is six milestones. Each milestone leaves the codebase building,
tests passing, and produces a small commit. The CLI command surface lands
in M4 — earlier milestones are pure machinery with unit-test coverage but
no user-visible behavior change. M5 wires migration into upgrade and status.
M6 is documentation and an end-to-end manual check.


### Milestone 1 — Schema and types

Scope: Add Dhall types `Migration` and `MigrationOp`; thread through the
Haskell type `Module`; teach the decoder and `schema-upgrade` about the new
field.

What will exist at the end:

- `schema/MigrationOp.dhall` defining a Dhall union of operation variants.
- `schema/Migration.dhall` defining `{ from : Text, to : Text, ops : List MigrationOp }`.
- `schema/Module.dhall` extended with `migrations : List Migration` (default
  `[] : List Migration.Type`).
- `schema/package.dhall` re-exports `MigrationOp` and `Migration`.
- `seihou-core/src/Seihou/Core/Migration.hs` defines `Migration`,
  `MigrationOp`, and (placeholder) re-exports for the planner that lands in
  M2.
- `Seihou.Core.Types.Module` gains a `migrations :: [Migration]` field.
- `Seihou.Dhall.Eval.moduleDecoder` decodes the field with a default of `[]`
  for backward compatibility (mirror the `withDefaults [("version",
  noneText)]` pattern at `Eval.hs:434`).
- `Seihou.Core.SchemaUpgrade` detects a missing `migrations` field and
  rewrites the file to include `, migrations = [] : List S.Migration.Type`.

Files to edit:

- New: `schema/MigrationOp.dhall`, `schema/Migration.dhall`,
  `seihou-core/src/Seihou/Core/Migration.hs`,
  `seihou-core/test/Seihou/Dhall/MigrationDecoderSpec.hs`.
- Edit: `schema/Module.dhall` (add field + default),
  `schema/package.dhall` (re-export), `seihou-core/src/Seihou/Core/Types.hs`
  (extend `Module`), `seihou-core/src/Seihou/Dhall/Eval.hs` (extend
  `moduleDecoder`), `seihou-core/src/Seihou/Core/SchemaUpgrade.hs` (new
  `MissingMigrations` issue + rewrite),
  `seihou-core/seihou-core.cabal` (add `Seihou.Core.Migration` to
  `exposed-modules` and `MigrationDecoderSpec` to test other-modules),
  `seihou-core/test/Seihou/Core/SchemaUpgradeSpec.hs` (extend coverage),
  any fixture `module.dhall` under `seihou-core/test/fixtures/` /
  `seihou-cli/test/fixtures/` that the schema-upgrade test reads.
- The schema URL pinned in user-facing module fixtures must be regenerated
  *only after* publishing a new commit to the `seihou-schema` repo
  (decision deferred to M6 alongside the docs publication).

Validation:

    cabal build seihou-core
    cabal test seihou-core

A green `MigrationDecoderSpec` and an updated `SchemaUpgradeSpec` are the
acceptance signal. No CLI command exists yet.


### Milestone 2 — Pure migration planner

Scope: Compute the chain of migrations that spans installed → target
version. Pure, no IO.

What will exist at the end:

In `seihou-core/src/Seihou/Core/Migration.hs`:

    data MigrationPlanError
      = MigrationVersionUnparseable Text
      | MigrationGap Version Version          -- can't reach `to` from `from`
      | MigrationDowngradeNotSupported Version Version
      | MigrationDuplicateEdge Version Version
      deriving stock (Eq, Show)

    data MigrationChain = MigrationChain
      { migrationModule :: ModuleName
      , chainFrom       :: Version
      , chainTo         :: Version
      , chainSteps      :: [Migration]   -- in order, contiguous
      }
      deriving stock (Eq, Show)

    planMigrationChain
      :: ModuleName
      -> [Migration]
      -> Version          -- from
      -> Version          -- to
      -> Either MigrationPlanError (Maybe MigrationChain)
      -- Right Nothing  =  same version, no work
      -- Right (Just c) =  contiguous chain found
      -- Left e         =  cannot plan

Algorithm: parse all `from`/`to` strings to `Version`; reject if any
unparseable; sort migrations by `from`; reject duplicate `from` edges
(ambiguous); starting at the installed `Version`, repeatedly pick the
migration whose `from` equals the current version; if `to > target`, stop one
step short with an error; if no migration matches and the current version is
less than the target, return `MigrationGap`; success when current equals
target.

Validation:

    cabal test seihou-core --test-options "--match Migration"

Test cases (all in `seihou-core/test/Seihou/Core/MigrationSpec.hs`):
single-edge chain, two-edge chain (1→2→3), gap (1→2 declared, 1→4
requested, no 2→4), downgrade rejected, same version is `Right Nothing`,
unparseable version, duplicate edges (two migrations both with `from =
"1.0.0"`).


### Milestone 3 — Engine: classify and execute

Scope: Take a `MigrationChain` and a `Manifest`, talk to the `Filesystem`
effect, return an `ExecutedMigrationPlan` and an updated `Manifest`.

What will exist at the end:

In `seihou-core/src/Seihou/Engine/Migrate.hs`:

    data MigrationFileStatus = MFSafe | MFConflict | MFGone
      deriving stock (Eq, Show)

    data MigrationOpInstance
      = MoveFileInst FilePath FilePath MigrationFileStatus
      | MoveDirInst FilePath FilePath
      | DeleteFileInst FilePath MigrationFileStatus
      | DeleteDirInst FilePath
      | RunCommandInst Text (Maybe FilePath)
      deriving stock (Eq, Show)

    data ExecutedMigrationPlan = ExecutedMigrationPlan
      { planModule :: ModuleName
      , planChain  :: MigrationChain
      , planOps    :: [MigrationOpInstance]
      }
      deriving stock (Eq, Show)

    data MigrationExecError
      = MigrationConflict [FilePath]      -- when not forced
      | MigrationCommandFailed Text Int
      deriving stock (Eq, Show)

    classifyMigration
      :: (Filesystem :> es)
      => Manifest -> MigrationChain
      -> Eff es ExecutedMigrationPlan

    executeMigration
      :: (Filesystem :> es, Process :> es)
      => Bool                 -- force
      -> ExecutedMigrationPlan
      -> Manifest
      -> Eff es (Either MigrationExecError Manifest)

Behaviour:

- `classifyMigration` walks `chainSteps`, expands each `MigrationOp` into a
  `MigrationOpInstance`, hashes the source file (for moves and deletes) using
  `Seihou.Manifest.Hash.hashContent`, and tags `MFSafe` / `MFConflict` /
  `MFGone` against the manifest's `files` entry. `MoveDirInst` and
  `DeleteDirInst` get no per-op status (they imply many files; the
  conflict check is per-contained-file via the manifest's `files` map).
- `executeMigration` checks `force`. If any file inside any op is
  `MFConflict` and not `force`, returns `Left (MigrationConflict paths)`
  without touching disk. Otherwise it runs the ops in order:
  - `MoveFile`: `renamePath src dest`. Manifest: rename the key in `files`
    map.
  - `MoveDir`: `renamePath src dest`. Manifest: for every key in `files`
    that is `src` or under `src/`, rewrite the key by replacing the prefix.
  - `DeleteFile`: `removeFile`. Manifest: drop the key.
  - `DeleteDir`: `removeDirectoryRecursive`. Manifest: drop every key under
    the prefix.
  - `RunCommand`: invoke via the `Process` effect. On non-zero exit, return
    `MigrationCommandFailed`. Manifest unchanged (the command may have moved
    files — author's responsibility to reflect that via an explicit
    follow-up op or to live with manifest drift; document this).
- The returned manifest also has `genAt` bumped to `now` (passed in by the
  CLI handler) and `moduleVersion` on the relevant `AppliedModule` set to
  `Just (renderVersion (chainTo chain))`.

Files to edit:

- New: `seihou-core/src/Seihou/Engine/Migrate.hs`,
  `seihou-core/test/Seihou/Engine/MigrateSpec.hs`.
- Edit: `seihou-core/src/Seihou/Effect/Filesystem.hs` (add `RenamePath`,
  `RemoveDirectoryRecursive` constructors and smart constructors),
  `seihou-core/src/Seihou/Effect/FilesystemInterp.hs` (IO impls via
  `System.Directory`),
  `seihou-core/src/Seihou/Effect/FilesystemPure.hs` (in-memory map ops:
  rename rewrites all keys with prefix; recursive remove drops all keys
  with prefix), `seihou-core/seihou-core.cabal` (`exposed-modules`).

Validation:

    cabal test seihou-core --test-options "--match Migrate"

Tests use `FilesystemPure` to seed an in-memory layout, build a
`MigrationChain` directly (not via Dhall), classify, execute, and assert
both the resulting in-memory layout and the rewritten manifest. Cover:
move-file safe; move-file conflict no-force (no disk change); move-file
conflict with force; move-dir with two contained files; delete-file gone
(no-op); delete-dir; manifest path rewrite for moved directory; chain of
two migrations applied in order.


### Milestone 4 — `seihou migrate` command

Scope: User-facing CLI. Loads the installed module, looks up the manifest's
`AppliedModule`, plans, classifies, and executes.

What will exist at the end:

In `seihou-cli/src/Seihou/CLI/Commands.hs`:

    data MigrateOpts = MigrateOpts
      { migrateModule    :: ModuleName
      , migrateTo        :: Maybe Text   -- override target version
      , migrateDryRun    :: Bool
      , migrateForce     :: Bool
      , migrateJson      :: Bool
      , migrateVerbose   :: Bool
      }
      deriving stock (Eq, Show, Generic)

    Command = ... | Migrate MigrateOpts

The `migrate` command appears in the "Module management:" `hsubparser`
group (`Commands.hs:259`) alongside `outdated` and `upgrade`. Help text
documents that migrations operate on the current project's working tree
and the manifest at `.seihou/manifest.json`.

In a new file `seihou-cli/src/Seihou/CLI/Migrate.hs`:

    handleMigrate :: MigrateOpts -> IO ()

The handler:

1. Reads `.seihou/manifest.json` from cwd; exits with a clear error if
   missing.
2. Looks up the named `AppliedModule`; exits if not applied.
3. Resolves `from = appliedModule.moduleVersion` (errors if `Nothing` —
   instructs the user to re-run with `--from` once that flag exists, or
   reapply the module to record a version). For v1 the absence of an
   installed version is a hard error with a clear remediation message.
4. Resolves the installed module directory by reading
   `appliedModule.source`, evaluates its `module.dhall` for the `migrations`
   list and the current `version`.
5. `to` defaults to the installed module's version; `--to` overrides.
6. Calls `planMigrationChain`. On `Right Nothing` prints "Already at
   version X; nothing to do" and exits 0.
7. Calls `classifyMigration` and renders the plan (table per migration step,
   per-op line). When `--json`, encode `ExecutedMigrationPlan` to JSON
   instead.
8. If `--dry-run`, exit 0.
9. Calls `executeMigration force plan`. Persists the returned manifest
   via `WriteManifest`. Prints a one-line summary.

Wired into `seihou-cli/src/Main.hs` alongside the existing dispatch cases.

Tests in `seihou-cli/test/Seihou/CLI/MigrateSpec.hs` use `withSystemTempDirectory`
to build a project + a fixture installed module with two migrations,
seed a manifest, and run an in-process `runMigrate :: MigrateOpts -> Manifest
-> InstalledModuleDir -> IO (Either MigrateError MigrateResult)` (a pure
shell that the IO `handleMigrate` wraps). Cover: dry-run prints plan,
non-force conflict aborts, force conflict succeeds, JSON output parses
back, missing manifest errors, module not applied errors, no-op when
already at target version.

Validation:

    cabal build seihou-cli
    cabal test seihou-cli --test-options "--match Migrate"

Manual smoke:

    seihou migrate haskell-base --dry-run     # prints chain
    seihou migrate haskell-base               # executes


### Milestone 5 — Integrate with `upgrade` and `status`

Scope: Connect the new machinery to two existing commands so users discover
it organically.

What will exist at the end:

- `seihou upgrade` learns a `--with-migrations` flag (default `False`).
  When set, after each successful per-module upgrade, the handler also runs
  `runMigrate` against the **current project** (cwd), if and only if the
  module is applied in the local manifest. When unset and migrations would
  be pending, prints a single advisory line:
  `note: haskell-base requires migration; run 'seihou migrate haskell-base'`.
- `seihou status` adds a "Pending migrations" line per applied module
  whose installed-module version is greater than its manifest
  `moduleVersion`. Reuses `planMigrationChain` to count chain length.

Files to edit:

- `seihou-cli/src/Seihou/CLI/Commands.hs` (add `upgradeWithMigrations` to
  `UpgradeOpts`).
- `seihou-cli/src/Seihou/CLI/Upgrade.hs` (after `installModuleDir`, branch
  on `--with-migrations` to call into `Seihou.CLI.Migrate.runMigrate`;
  otherwise emit advisory line).
- `seihou-cli/src/Seihou/CLI/Status.hs` (compute pending migrations per
  applied module; render a section).
- Tests: extend `UpgradeSpec` with a fixture module that has migrations to
  prove the advisory and the `--with-migrations` paths.

Validation:

    cabal test
    seihou upgrade --dry-run                  # advisory line shown
    seihou upgrade --with-migrations          # migrations executed
    seihou status                             # "Pending migrations" line


### Milestone 6 — Docs, in-binary help, and end-to-end

Scope: All user-facing surfaces that document the feature — repo docs,
the `seihou help` topic embedded in the binary, per-command `--help`
footers, the top-level help, and a manual real-world walkthrough.

What will exist at the end:

**Repo docs**

- `docs/user/migrations.md` (new): full guide. What migrations are; when to
  use them vs new module versions; the `MigrationOp` reference; chain
  semantics; conflict handling; `--force`; integration with `upgrade`.
- `docs/cli/migrate.md` (new): command reference, examples.
- `docs/user/module-authoring.md`: new "Migrations" section linking to
  `migrations.md`, with one canonical example.
- `docs/user/registries-and-multi-module-repos.md`: short note explaining
  that `RegistryEntry.version` continues to drive
  `Outdated.findAvailableVersion`'s decision and that migrations are
  resolved against each individual module, not the registry.
- `CHANGELOG.md` `[Unreleased]` entry covering the new command, the
  `--with-migrations` flag on `upgrade`, the new `migrations` field on
  `module.dhall`, and the new `seihou help migrations` topic.
- `seihou-cli/data/bootstrap-prompt.md` and the `agent assist` prompt
  references migrations as an authoring concern.

**In-binary `seihou help <topic>`** — the `help` command serves embedded
markdown files registered in `Seihou.CLI.Help.helpTopics`
(`seihou-cli/src/Seihou/CLI/Help.hs:29`). Each topic has a backing file
under `seihou-cli/help/` loaded via `embedStringFile` at compile time, so
new files must be referenced from a `$(embedStringFile …)` splice or the
binary will not see them.

- New: `seihou-cli/help/migrations.md`. Sized similarly to the existing
  `modules.md` (~80 lines): explains when to author a migration, the
  layout of a `Migration` record, each `MigrationOp` variant with a
  one-line example, the chain-selection rule (strict contiguous), the
  conflict semantics (Safe / Conflict / Gone) mirroring `seihou remove`,
  the `--dry-run` and `--force` flags, the relationship to
  `seihou upgrade --with-migrations`, and the manifest path-rewrite
  guarantee.
- Edit: `Seihou.CLI.Help.helpTopics` — append
  `HelpTopic "migrations" "Migrating a project between module versions"
  migrationsContent` and add the `migrationsContent =
  $(embedStringFile "help/migrations.md")` splice. Update the
  `seihou-cli.cabal` `extra-source-files` field if it lists the existing
  help files (mirroring whatever pattern is already there).
- Edit: `seihou-cli/help/modules.md` — append a one-line "see also"
  pointing at `seihou help migrations` in the section that currently
  describes module versioning. Authors discover the migration topic when
  they read about modules.
- Edit: `seihou-cli/help/git-repository.md` — one-line cross-reference
  in the upgrade workflow paragraph noting that `seihou migrate` is the
  post-upgrade step when a module ships migrations.

**Per-command `--help` footers** — long-form help strings live next to
each `ParserInfo` in `seihou-cli/src/Seihou/CLI/Commands.hs`. They are
the primary discovery surface for users who type `seihou <cmd> --help`.

- `migrateInfo` (new) — `progDesc "Apply module-declared migrations to
  the current project"`, plus a `footerDoc` modelled on `upgradeFooter`
  (`Commands.hs:822`): explanatory paragraph, list of `MigrationOp`
  kinds, behaviour with `--dry-run` / `--force` / `--to`, and an
  Examples block with at least:

      seihou migrate haskell-base                # plan + apply
      seihou migrate haskell-base --dry-run      # preview only
      seihou migrate haskell-base --to 1.5.0     # stop at intermediate version
      seihou migrate haskell-base --force        # overwrite conflicted files
      seihou migrate haskell-base --json         # machine-readable plan

  End the footer with `See also: seihou help migrations`.
- `upgradeInfo` footer — extend `upgradeFooter` to add a paragraph
  explaining that newer module versions may declare migrations, what
  the default behaviour is (advisory line, no project mutation), how
  `--with-migrations` opts in, and a `seihou migrate` cross-reference.
- `statusInfo` footer — append a sentence: "When an applied module's
  installed copy has advanced past the manifest's recorded version,
  status reports the pending migration count; run
  `seihou migrate <module>` to apply them."
- `outdatedInfo` footer — one-line cross-reference noting that
  `seihou upgrade` is the next step and may surface pending migrations.

**Top-level help**

- `topLevelFooter` (`Commands.hs:240`) — extend the "Getting started"
  block (or add a "Learn more" block) with `seihou help migrations` as a
  discoverable topic alongside the existing topic list. Verify that
  `seihou help` (no args) lists `migrations` in its enumeration of
  available topics — this is automatic once `helpTopics` is updated.

End-to-end manual check, recorded in Outcomes & Retrospective:

1. `mkdir /tmp/seihou-migrate-demo && cd /tmp/seihou-migrate-demo`
2. Create `~/tmp/demo-mod/module.dhall` v1.0.0 with one step generating
   `app/Hello.hs`.
3. `seihou install ~/tmp/demo-mod --name demo-mod`
4. In a fresh project dir: `seihou run demo-mod --var project.name=demo`
   — observe `app/Hello.hs`.
5. Edit `~/tmp/demo-mod/module.dhall`: bump to v2.0.0, change the step's
   `dest` to `src/Hello.hs`, add a migration `1.0.0 → 2.0.0` with one
   `MoveDir { src = "app", dest = "src" }`.
6. `seihou install ~/tmp/demo-mod --name demo-mod` (re-installs at v2.0.0).
7. `cd` back to project: `seihou status` shows pending migration.
8. `seihou migrate demo-mod --dry-run` prints the plan.
9. `seihou migrate demo-mod` performs the move and updates the manifest.
10. `seihou diff` is clean. `seihou status` shows no pending migration.

Validation:

    cabal test            # all tests pass
    just check            # if a justfile target covers fmt + lint
    # plus the manual walkthrough above

Acceptance: the walkthrough behaves exactly as written, the manifest's
`files` map after step 9 contains `src/Hello.hs` and not `app/Hello.hs`,
and `seihou status` reports `demo-mod 2.0.0` (the upgraded version).


### Milestone 7 — Agent prompt context

Scope: Update the three embedded markdown prompts shipped to the
LLM-driven `seihou agent` subcommands so that authoring and
consumption sessions are aware of migrations. No Haskell code
changes — the prompts are pulled in via
`Data.FileEmbed.embedFile` at compile time.

What will exist at the end:

- **`seihou-cli/data/assist-prompt.md`** (the `seihou agent assist`
  authoring assistant) gains:
  - In the `module.dhall format` Dhall block: a `migrations` field on
    the example record, with the same `[] : List Migration`
    placeholder shown elsewhere for empty-list defaults.
  - A new short subsection **"Migrations"** under
    `## Module Schema Reference` (sibling to "Module removal"),
    documenting the five `MigrationOp` variants (`MoveFile`,
    `MoveDir`, `DeleteFile`, `DeleteDir`, `RunCommand`), the
    `from`/`to` chain semantics (strict contiguous, ordered by
    parsed `Version`), and the conflict model (Safe / Conflict /
    Gone, mirroring `seihou remove`). Sized like the existing
    "Module removal" subsection (~10 lines).
  - In `## Seihou CLI Commands`: add
    `seihou migrate MODULE [--dry-run] [--force] [--to VERSION] [--json]`
    with a one-line description.
  - One-line cross-reference at the end of the schema section
    pointing the agent at `seihou help migrations` for detail.
- **`seihou-cli/data/bootstrap-prompt.md`** (the `seihou agent
  bootstrap` module-creation assistant) gains:
  - The same `migrations` field on the schema example block.
  - A new **"Migrations"** subsection with the same op catalogue
    and chain semantics as `assist-prompt.md`, plus an explicit
    note that bootstrap-time modules typically start at v1 with
    `migrations = [] : List Migration`, and that authors add
    migrations when bumping the version.
  - In `## Seihou CLI Commands`: add the `seihou migrate` line.
  - In the `## Bootstrap Workflow` numbered list: a new step
    after step 4 ("Add conditional steps") titled "Plan for
    versioning" that instructs the agent to ask the user
    whether they expect to ship breaking changes later, and if
    so, to leave the `migrations = []` skeleton in place so the
    author can append entries when bumping `version`.
- **`seihou-cli/data/setup-prompt.md`** (the `seihou agent
  setup` consumption assistant) gains:
  - In `## Seihou CLI Commands` → `### Generation` block: add
    `seihou migrate MODULE [--dry-run] [--force] [--to VERSION] [--json]`
    with a one-line description that emphasises this is the
    post-upgrade step.
  - In the same block: extend the `seihou run` line group with a
    note that `seihou upgrade` accepts `--with-migrations`, and
    update the `seihou upgrade` entry (currently absent — add
    it under "### Module discovery and inspection" or a new
    "### Upgrade and migration" subsection) to surface the
    flag.
  - In `## Consumption Workflow`: a new step **8. Stay current**
    after the existing "Commit" step, documenting the upgrade →
    migrate sequence: run `seihou upgrade --dry-run` to see
    advisory lines, run `seihou status` to see "Pending
    migrations" lines per applied module, run
    `seihou migrate MODULE` (or `seihou upgrade --with-migrations`
    for both in one shot) to apply them.
  - The `seihou status` description in the same file gets a one-line
    note that it surfaces a "Pending migrations: N migration(s)
    pending: X → Y" sub-line when an applied module's installed
    copy has advanced past the manifest's recorded version.
  - The `## Module Schema Reference` block's `module.dhall format`
    example gets the `migrations` field added (consumers benefit
    from being able to read it even though they don't author
    it).

Files to edit:

- `seihou-cli/data/assist-prompt.md`
- `seihou-cli/data/bootstrap-prompt.md`
- `seihou-cli/data/setup-prompt.md`

No Haskell modules change. The cabal file does not need editing —
`Data.FileEmbed.embedFile` reads the markdown at compile time, so
rebuilding `seihou-cli` after editing the markdown is sufficient.

Validation:

    cabal build seihou-cli
    cabal run seihou -- agent assist --print-prompt    # if such a flag exists; otherwise grep
    grep -n -i 'migrat' seihou-cli/data/*.md           # confirms migration content is embedded
    cabal test                                         # the existing suite stays green; no new tests are required for prompt-only changes

Acceptance:

  - `grep -ic migrat seihou-cli/data/assist-prompt.md` returns ≥ 3
    (schema field, op subsection, CLI line).
  - `grep -ic migrat seihou-cli/data/bootstrap-prompt.md` returns
    ≥ 3 (same shape).
  - `grep -ic migrat seihou-cli/data/setup-prompt.md` returns ≥ 4
    (CLI line, upgrade flag, status sub-line, workflow step).
  - A re-built `seihou` binary, when launched via `seihou agent
    assist` (or `bootstrap`/`setup`), embeds the new content —
    inspectable by `strings $(which seihou) | grep -i migrat`
    or by reading the Haskell test that snapshots the prompt
    template if one is added; the lower-effort confirmation is
    `cabal build seihou-cli` succeeding and the markdown files
    containing the expected text on disk.
  - No new tests are introduced; the prompts are content, not
    behaviour, and the existing `MigrateSpec` /
    `PendingMigrationSpec` suites already gate the migration
    feature itself.


## Concrete Steps

> All commands run from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`
> unless noted. The plan checks itself in by running `cabal build all` and
> `cabal test all` after each milestone.

### M1 commands

    cabal build seihou-core
    cabal test seihou-core --test-options "--match MigrationDecoder"
    cabal test seihou-core --test-options "--match SchemaUpgrade"

Expected: 0 test failures, new specs run.

### M2 commands

    cabal test seihou-core --test-options "--match Core.Migration"

Expected: 8+ passing cases under `Core.MigrationSpec`.

### M3 commands

    cabal test seihou-core --test-options "--match Engine.Migrate"

Expected: 8+ passing cases under `Engine.MigrateSpec`.

### M4 commands

    cabal build seihou-cli
    cabal test seihou-cli --test-options "--match Migrate"
    cabal run seihou -- migrate --help
    cabal run seihou -- migrate non-existent-module --dry-run

Expected: `--help` shows the new command; the `non-existent-module` call
exits non-zero with a clear "module not applied" message.

### M5 commands

    cabal test seihou-cli --test-options "--match Upgrade"
    cabal run seihou -- upgrade --help        # shows --with-migrations
    cabal run seihou -- status --help

### M6 commands

    cabal build seihou-cli                      # picks up new embedStringFile splice
    cabal test all
    cabal run seihou -- help                    # lists 'migrations' as a topic
    cabal run seihou -- help migrations         # prints the embedded markdown
    cabal run seihou -- migrate --help          # shows MigrationOp list + Examples
    cabal run seihou -- upgrade --help          # mentions --with-migrations + migrate
    cabal run seihou -- status --help           # mentions Pending migrations
    cabal run seihou -- --help                  # top-level footer references migrations
    # then run the manual end-to-end from the milestone description above

### M7 commands

    # confirm starting state: zero migration references in the agent prompts
    grep -ic migrat seihou-cli/data/assist-prompt.md         # expect 0 before edits
    grep -ic migrat seihou-cli/data/bootstrap-prompt.md      # expect 0 before edits
    grep -ic migrat seihou-cli/data/setup-prompt.md          # expect 0 before edits

    # after edits
    grep -in 'migrat\|seihou migrate' seihou-cli/data/assist-prompt.md
    grep -in 'migrat\|seihou migrate' seihou-cli/data/bootstrap-prompt.md
    grep -in 'migrat\|with-migrations\|Pending migrations' seihou-cli/data/setup-prompt.md

    cabal build seihou-cli                                    # re-embed prompts
    cabal test                                                # nothing should regress

Expected: each grep returns the lines added by M7; rebuild
succeeds; full test suite stays green.


## Validation and Acceptance

After all milestones:

1. `cabal build all` succeeds with no warnings new to this branch.
2. `cabal test all` is green. Per-milestone test additions are present:
   - `seihou-core/test/Seihou/Dhall/MigrationDecoderSpec.hs` (M1)
   - `seihou-core/test/Seihou/Core/MigrationSpec.hs` (M2)
   - `seihou-core/test/Seihou/Engine/MigrateSpec.hs` (M3)
   - `seihou-cli/test/Seihou/CLI/MigrateSpec.hs` (M4)
   - extensions in `UpgradeSpec` and `StatusSpec` (M5)
3. `seihou migrate haskell-base --dry-run` (or another applied module
   with migrations declared) prints a plan formatted as in the Purpose
   section.
4. `seihou migrate haskell-base` executes the plan, mutates project
   files, rewrites `.seihou/manifest.json`, and bumps the manifest's
   `appliedModule.version` for the named module.
5. `seihou status` after migration reports the new version and no
   pending migrations.
6. `seihou diff` after migration is clean (no unexpected modified files).
7. `seihou help` lists `migrations` as a topic and `seihou help
   migrations` prints the embedded guide.
8. `seihou migrate --help`, `seihou upgrade --help`, and
   `seihou status --help` each include the migration-related text
   prescribed in M6.
9. The end-to-end manual walkthrough in M6 succeeds verbatim.
10. The three embedded agent prompts under `seihou-cli/data/`
    (`assist-prompt.md`, `bootstrap-prompt.md`,
    `setup-prompt.md`) all reference the `migrations` field and
    the `seihou migrate` command. Specifically:
      - The authoring prompts (`assist`, `bootstrap`) document
        the `MigrationOp` variants and the chain semantics.
      - The consumption prompt (`setup`) documents
        `seihou migrate`, `seihou upgrade --with-migrations`,
        and the "Pending migrations" status sub-line.
      - A rebuilt `seihou-cli` embeds the updated text
        (verifiable via `strings $(cabal list-bin seihou) |
        grep -i migrat`).

A user-visible acceptance behaviour: a module author bumps a module from
`1.0.0` to `2.0.0`, declares one migration that moves `app/` to `src/`,
republishes; an existing project consumer runs `seihou upgrade --dry-run`,
sees the advisory; runs `seihou migrate <module>` and sees their `app/`
directory become `src/` with no manual `mv`.


## Idempotence and Recovery

`planMigrationChain` returns `Right Nothing` when the manifest's recorded
version equals the installed module's version, so re-running `seihou
migrate` on an up-to-date project is a documented no-op.

Within a single `executeMigration` call, ops are applied in order without
checkpointing. If a `RunCommand` fails halfway through a chain, the disk
state reflects the operations that succeeded but the manifest is **not**
written (the handler only persists the manifest on `Right`). The user can
inspect disk, fix the cause, and re-run; partially completed file moves
will surface as `MFGone` (source absent) or `MFSafe` (source still there)
on the next classify pass — both are safe.

Crash recovery: because the manifest is updated atomically only after all
ops succeed, the worst case is "manifest is stale, disk is partway through
a migration." The user can roll the disk back via `git restore` (Seihou
strongly assumes the project is under version control — `seihou run
--commit` is documented) and try again. This is the same recovery posture
as `seihou remove`.

The plan does not introduce new global state; it does not write outside
the project directory and the existing manifest path. There is nothing to
clean up if the user aborts.


## Interfaces and Dependencies

External libraries used:

- `dhall` for decoding `Migration` and `MigrationOp` (already a dependency).
- `directory` for `renamePath` and `removeDirectoryRecursive` (already a
  dependency via `Filesystem` interpreter).
- `aeson` and `aeson-pretty` for `--json` output (already used by `Upgrade`
  and `Outdated`).
- `effectful` for the `Filesystem` and `Process` effects (already a
  dependency).

No new dependencies are required.

Module signatures that must exist at end of each milestone:

**End of M1**, in `seihou-core/src/Seihou/Core/Migration.hs`:

    data MigrationOp
      = MoveFileOp   { src :: FilePath, dest :: FilePath }
      | MoveDirOp    { src :: FilePath, dest :: FilePath }
      | DeleteFileOp { path :: FilePath }
      | DeleteDirOp  { path :: FilePath }
      | RunCommandOp { run :: Text, workDir :: Maybe FilePath }
      deriving stock (Eq, Show, Generic)

    data Migration = Migration
      { from :: Text
      , to   :: Text
      , ops  :: [MigrationOp]
      }
      deriving stock (Eq, Show, Generic)

In `seihou-core/src/Seihou/Core/Types.hs`, the `Module` record gains:

    , migrations :: [Migration]

In `seihou-core/src/Seihou/Dhall/Eval.hs`, `moduleDecoder` gets:

    <*> field "migrations" (list migrationDecoder)

with `withDefaults [("migrations", emptyList migrationType)]` for
backward compatibility.

In `seihou-core/src/Seihou/Core/SchemaUpgrade.hs`, the `UpgradeIssue` ADT
gains:

    | MissingMigrations

with rewrite logic adding `, migrations = [] : List S.Migration.Type`.

**End of M2**, in `Seihou.Core.Migration`:

    planMigrationChain
      :: ModuleName -> [Migration] -> Version -> Version
      -> Either MigrationPlanError (Maybe MigrationChain)

**End of M3**, in `seihou-core/src/Seihou/Effect/Filesystem.hs`:

    RenamePath              :: FilePath -> FilePath -> Filesystem m ()
    RemoveDirectoryRecursive :: FilePath -> Filesystem m ()
    renamePath               :: (Filesystem :> es) => FilePath -> FilePath -> Eff es ()
    removeDirectoryRecursive :: (Filesystem :> es) => FilePath -> Eff es ()

In `seihou-core/src/Seihou/Engine/Migrate.hs`:

    classifyMigration
      :: (Filesystem :> es)
      => Manifest -> MigrationChain
      -> Eff es ExecutedMigrationPlan

    executeMigration
      :: (Filesystem :> es, Process :> es)
      => Bool -> ExecutedMigrationPlan -> Manifest
      -> Eff es (Either MigrationExecError Manifest)

**End of M4**, in `seihou-cli/src/Seihou/CLI/Commands.hs`:

    data MigrateOpts = MigrateOpts { … }
    Command = … | Migrate MigrateOpts

In `seihou-cli/src/Seihou/CLI/Migrate.hs`:

    handleMigrate :: MigrateOpts -> IO ()

**End of M5**, `UpgradeOpts` gains `upgradeWithMigrations :: Bool`,
`Seihou.CLI.Upgrade` calls into `Seihou.CLI.Migrate.runMigrate`,
`Seihou.CLI.Status` reports pending migrations per applied module.

The plan creates no new effects or interpreters beyond the two
`Filesystem` constructors.


## Revision Notes

- 2026-04-25: Expanded M6 to cover all in-binary help surfaces in
  addition to the repo `docs/`. Specifically: a new
  `seihou help migrations` topic (markdown at
  `seihou-cli/help/migrations.md`, registered in `Seihou.CLI.Help`),
  cross-references in `seihou-cli/help/modules.md` and
  `seihou-cli/help/git-repository.md`, prescribed `--help` footer text
  for `migrate`, `upgrade`, `status`, and `outdated`, and a top-level
  footer hint at `seihou help migrations`. Added M6 commands and
  acceptance items 7–8 covering these surfaces. Shell completions
  (`seihou-cli/src/Seihou/CLI/Completions/`) deliberately not listed:
  they delegate to optparse-applicative's runtime introspection and
  pick up the new subcommand and flags automatically.

- 2026-04-25: Added Milestone 7 — Agent prompt context. M6's
  description listed `seihou-cli/data/bootstrap-prompt.md` and the
  `agent assist` prompt, but the actual M6 commit (bd0ac0b) only
  touched repo `docs/`, in-binary help, and `--help` footers; the
  three prompt files under `seihou-cli/data/` still contain zero
  references to `migrat`. M7 prescribes precise edits for
  `assist-prompt.md`, `bootstrap-prompt.md`, and
  `setup-prompt.md`: schema-reference additions for the
  `migrations` field, op-catalogue subsections for the authoring
  prompts, CLI-command-list entries for `seihou migrate` in all
  three, and consumption-flow guidance for `setup-prompt.md`
  covering `seihou upgrade --with-migrations` and the new
  "Pending migrations" `seihou status` sub-line. New sections:
  Progress checkbox for M7, the M7 Plan-of-Work milestone block,
  M7 entries in Concrete Steps, acceptance item 10, two new
  Decision-Log entries (scope across all three prompts; align
  content with `seihou help migrations`), one new
  Surprises-and-Discoveries entry documenting the M6 gap, and
  this revision note. The "What's not done" subsection in
  Outcomes & Retrospective now flags the prompt files as
  remaining work rather than implying the feature is fully
  delivered.
