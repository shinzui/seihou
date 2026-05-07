---
id: 26
slug: migrate-commit-flag
title: "Add --commit flag to seihou migrate with AI-generated commit messages"
kind: exec-plan
created_at: 2026-04-27T19:16:03Z
intention: "intention_01kq2gy6yde258gd30xjvs85g7"
---


# Add --commit flag to seihou migrate with AI-generated commit messages

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, a user who runs

    seihou migrate haskell-base --commit

will see the project's working tree mutated by the migration (file moves,
deletions, the `.seihou/manifest.json` rewrite) **and** the resulting changes
automatically staged and committed to git in a single command. The commit
message is produced by Claude Code (`claude -p`), seeded with the migration's
chain summary and the staged diff. An optional

    seihou migrate haskell-base --commit-message "chore: bump haskell-base to 1.5.0"

bypasses the AI generator and uses a user-supplied message verbatim.
`--commit-message` implies `--commit`, mirroring the existing behavior on
`seihou run`.

This eliminates the manual "stage every moved file, write a message, commit"
loop after every migration. It is the migrate-side analogue of the `--commit`
flag that already exists on `seihou run` — same shape, same UX.

How to see it working end-to-end after implementation:

1. Have a project where a `seihou migrate <module>` would actually run a
   chain (i.e. the manifest's recorded version trails the installed copy
   and the module declares a reachable migration). The chain must contain
   at least one `MoveFile` or `DeleteFile` op so the working tree
   actually changes.
2. Make the project a git repo and add a clean baseline commit.
3. Run `seihou migrate <module> --commit-message "chore: migrate <module>"`.
4. After the command completes, run `git log -1 --stat`. You should see a
   single new commit titled `chore: migrate <module>` whose stat lists the
   moved/deleted files plus `.seihou/manifest.json`. `git status` should
   report a clean working tree.

If `claude` is on `PATH`, dropping `--commit-message` and re-running with
just `--commit` will produce a similar commit but with an AI-generated
subject line that names the module. If `claude` is not available, the
command falls back to the same template message used by `seihou run`
(`seihou: apply module <name>`), so the commit still happens.


## Progress

The implementation work below is broken into milestones in the **Plan of
Work** section. Each milestone has a self-contained acceptance check; the
checklist below tracks granular progress. Update it on every stopping
point. Add timestamps in `YYYY-MM-DD` form.

- [x] M1 — extend `MigrateOpts` and add the parser switches (2026-04-27)
  - [x] Add `migrateCommit :: Bool` and `migrateCommitMessage :: Maybe Text`
        fields to `MigrateOpts` in `seihou-cli/src/Seihou/CLI/Migrate.hs`
  - [x] Add `--commit` and `--commit-message` to `migrateParser` in
        `seihou-cli/src-exe/Seihou/CLI/Commands.hs`, reusing the exact
        `help` strings from `runParser` so the two flags are documented
        identically across the two commands
  - [x] Update every internal `MigrateOpts { … }` literal so the build
        compiles: `seihou-cli/src-exe/Seihou/CLI/Run.hs` (twice — both
        `applyOneMigration` and `bumpOneBlocked`),
        `seihou-cli/src-exe/Seihou/CLI/Upgrade.hs` (the
        `upgrade --with-migrations` dispatch), and
        `seihou-cli/test/Seihou/CLI/MigrateSpec.hs` (`defaultOpts`).
        Each of these sets `migrateCommit = False, migrateCommitMessage = Nothing`.
  - [x] `cabal build all` succeeds with no warnings beyond pre-existing ones
- [x] M2 — wire commit logic into `handleMigrate` (2026-04-27)
  - [x] In `seihou-cli/src/Seihou/CLI/Migrate.hs`, after the manifest write
        on the `MigrateApplied` and `MigrateAppliedPartial` branches,
        invoke a new `commitMigratedFiles` helper when
        `opts.migrateCommit || isJust opts.migrateCommitMessage` is true.
        The helper drives `isGitRepo`, `gitCheckIgnore`, `gitAdd`,
        `gitDiffCached`, `gitCommit`, and `generateCommitMessage` —
        the same primitives `seihou-cli/src-exe/Seihou/CLI/Run.hs`
        uses today (lines 341–368).
  - [x] Choose the staged path set: union of every `src` and `dest` from
        the plan's `MoveFileInst` / `MoveDirInst` instances, every
        `path` from `DeleteFileInst` / `DeleteDirInst` instances,
        the `RunCommandInst` ops contribute nothing (their effect is
        opaque), and finally `.seihou/manifest.json`.
  - [x] Bump-only path (`MigrateApplied` with empty `planOps`) commits
        only the manifest.
  - [x] Outcomes that did nothing on disk (`MigrateNoOp`, `MigrateBlocked`,
        `MigrateBenignUpgrade`, dry-run variants) **must not** commit
        even when the flags are set; the helper is simply not called on
        those branches.
- [x] M3 — tests (2026-04-27)
  - [x] Add behavioral tests to
        `seihou-cli/test/Seihou/CLI/MigrateSpec.hs` covering:
        a clean apply with `--commit-message "msg"` produces a commit
        whose body is exactly `msg` and whose tree contains the moved
        files; the `.seihou/manifest.json` is part of the staged set;
        outside-of-git is a silent no-op; a dry-run with `--commit`
        produces a `MigrateDryRunOK` result without firing the helper;
        and a `MigrateBlocked` outcome likewise never fires the helper.
  - [~] Skipped: parser unit test. `migrateParser` lives in the
        executable target (`Seihou.CLI.Commands`), which the test
        suite cannot import. The CLI placement convention (CLAUDE.md
        / `nix/check-cli-module-placement.sh`) traps the parser there
        because it depends on `Options.Applicative`. The plan's
        baseline manual check — `cabal run seihou -- migrate --help`
        — is still part of M5 and adequately covers parser shape.
        Recorded under Decision Log.
  - [x] Update `seihou-cli/test/Seihou/CLI/MigrateSpec.hs::defaultOpts`
        as noted under M1 (already done in M1).
- [x] M4 — documentation (2026-04-27)
  - [x] Update `docs/cli/migrate.md` to add `--commit` and
        `--commit-message` rows to the **Options** table, an
        `## Auto-commit` section that mirrors the wording in
        `docs/cli/run.md`, and at least one new example.
  - [x] Cross-link from `docs/cli/run.md` if the run-side commit section
        already names migrate as a sibling; otherwise leave run.md
        alone. (run.md's commit-integration section did not name
        migrate; left untouched per plan.)
  - [x] Add an entry to `docs/user/CHANGELOG.md` under the next
        unreleased heading describing the new flag pair.
- [x] M5 — end-to-end verification (2026-04-27)
  - [x] **Apply + commit-message** — covered by the M3 behavioral
        test "--commit-message stages moved files plus the manifest
        into a single git commit". The fixture mirrors the master
        plan's recipe: a manifest at `1.0.0`, an installed copy at
        `2.0.0` whose `module.dhall` declares a `MoveFile` migration,
        and a real `git init` in the project dir. Verifies the
        post-migrate commit's name-only stat (with `--no-renames`)
        names the moved file's source and destination plus the
        manifest, and the subject equals the supplied message.
  - [~] **Apply + AI commit message** (`--commit` without
        `--commit-message`, with `claude` on `PATH`) is *not*
        exercised in CI. `generateCommitMessage` is structurally
        identical to `seihou run --commit`'s already-shipped path;
        the unit-test suite for the helper itself
        (`Seihou.CLI.CommitMessageSpec`) covers fence-stripping and
        fallback. The branch can be exercised by hand by following
        the "B. Author a tiny one-shot test module" recipe in M5
        below.
  - [x] **Dry-run with `--commit`** — covered by the M3 test
        "--commit on a dry-run path returns a dry-run variant
        (helper is never invoked)". Verifies the `runMigrate` result
        is a `MigrateDryRunOK` variant *and* the project's git ref
        count is unchanged after the call (no new commit landed).
  - [x] **Outside a git repo** — covered by the M3 test "--commit
        outside a git repo is a silent no-op (apply still
        succeeds)". Verifies the helper exits zero and the apply
        still moved files / wrote the manifest.
  - [x] Smoke check on the built binary: `cabal run seihou --
        migrate dummy --commit-message "chore: smoke"` from an empty
        scratch dir confirms the parser accepts the flag and the
        command reaches `handleMigrate`, exiting with the clean
        "no Seihou manifest" error path. Output matches the
        existing handler's error rendering verbatim.


## Surprises & Discoveries

- `git add <src> <dest>` for a moved file correctly stages the move
  (status reports `R src -> dest`), but `git log --name-only` then
  collapses the rename to just the destination. Asserting that the
  source path *also* appears in the commit requires
  `git log --name-only --no-renames`. Without this, a regression
  where the helper fails to stage the source-side deletion would
  silently pass the test.
  (2026-04-27)


## Decision Log

- Decision: Follow the exact shape of `seihou run`'s `--commit` /
  `--commit-message` pair rather than introducing a separate vocabulary
  (e.g. `--auto-commit`).
  Rationale: The two commands together form one workflow ("run and
  migrate the same project as upstream evolves"). Mirroring the flag
  pair makes the user's mental model trivially portable; it also lets
  the existing `Seihou.CLI.Git` and `Seihou.CLI.CommitMessage` helpers
  be reused unchanged.
  Date: 2026-04-27

- Decision: The new fields live on `MigrateOpts` (in the library
  `Seihou.CLI.Migrate` module) but the commit logic itself lives in
  `handleMigrate` (the IO shell), not in `runMigrate` (the
  pure-ish core).
  Rationale: `runMigrate` is also called by `seihou run --with-migrations`
  and `seihou upgrade --with-migrations`, both of which already have
  their own commit policies. Putting the commit logic in `handleMigrate`
  guarantees the new flags only fire when the user invoked `seihou
  migrate` directly. The internal callers initialize the new
  `MigrateOpts` fields to `False`/`Nothing` so the change is
  type-only for them.
  Date: 2026-04-27

- Decision: `RunCommand` migration ops contribute nothing to the
  staged path set; the documentation calls this out explicitly.
  Rationale: A `RunCommand` op runs an arbitrary shell command whose
  filesystem effects are opaque to seihou's manifest. Mirroring this
  into `git add` would either require `git add -A` (sweeping in
  unrelated working-tree changes) or require migrate to diff the disk
  before/after the command (a layering inversion). The migration
  authoring docs already note that `RunCommand` does not auto-update
  the manifest; the same caveat applies to `--commit` here.
  Date: 2026-04-27

- Decision: Bump-only applies (where `planOps` is empty) still commit
  if `--commit` was set — but they only stage `.seihou/manifest.json`.
  Rationale: A `--bump-only` apply *does* mutate the manifest, which
  is itself a tracked artifact. A user who passes both `--bump-only`
  and `--commit` clearly wants the manifest bump captured in git.
  Date: 2026-04-27

- Decision: Whether to add the new behavioral tests to the existing
  `Seihou.CLI.MigrateSpec` or to a new `Seihou.CLI.MigrateCommitSpec`
  is left to implementation time. Default to the existing spec; split
  out only if the file grows unwieldy.
  Rationale: The existing spec already wires up a project-on-disk
  fixture with a real manifest and a real installed copy, which is
  exactly the substrate the new tests need. A second module would
  duplicate that fixture.
  Date: 2026-04-27
  Resolution: Stayed in `MigrateSpec.hs` under a new "EP-26" subsection.

- Decision: Skip the parser unit test for `--commit` /
  `--commit-message`. The plan listed it but the test target cannot
  import the parser without restructuring.
  Rationale: `migrateParser` is in `Seihou.CLI.Commands`, which lives
  in the `seihou` executable target because it depends on
  `Options.Applicative`. The CLI placement convention
  (`nix/check-cli-module-placement.sh`) deliberately traps it there.
  The test suite depends only on `seihou-cli-internal`, so the parser
  is unreachable from tests without lifting it (and `optparse`) into
  the library or duplicating the parser fragment. The behavior under
  test — "do these two flag tokens populate two boolean / Maybe-Text
  fields" — is mechanical optparse glue with no domain logic; the
  full-pipeline behavioral tests, the `migrate --help` smoke check
  in M5, and the existing run-side flag pair already exercise the
  same `switch` / `option (T.pack <$> str)` pattern.
  Date: 2026-04-27

- Decision: When a migration moves a file, the commit's name-only
  output collapses the source and destination to just the
  destination unless rename detection is disabled. The behavioral
  test asserts both endpoints by passing `--no-renames` to
  `git log`.
  Rationale: `git add app/Main.hs src/Main.hs` correctly stages a
  rename (verified out-of-band: status shows
  `R app/Main.hs -> src/Main.hs`), but `git log --name-only` reports
  it as a single rename entry whose name-only flattening is the
  destination. Asserting against the rename-detected name-only
  output would silently miss the case where the helper failed to
  stage one of the two paths. `--no-renames` forces git to report
  the deletion and addition as two distinct entries, which is what
  the test wants to verify. The helper itself does not need any
  change — it always passes both src and dest to `git add`.
  Date: 2026-04-27


## Outcomes & Retrospective

Delivered (2026-04-27, single sitting):

- `seihou-cli/src/Seihou/CLI/Migrate.hs` grew two new fields on
  `MigrateOpts` (`migrateCommit`, `migrateCommitMessage`), a new
  exported helper `commitMigratedFiles`, and a `when (commit ||
  isJust message) commitMigratedFiles` call inserted on each of
  `MigrateApplied`'s three sub-branches plus `MigrateAppliedPartial`.
- The CLI parser (`seihou-cli/src-exe/Seihou/CLI/Commands.hs`) gained
  `--commit` and `--commit-message MSG`, with help strings copied
  verbatim from the run-side parser so help output stays
  symmetric. A new line was added to `migrateFooter`'s Examples
  block.
- Three internal `MigrateOpts` literals were extended to set the
  new fields to `False` / `Nothing`: `Run.applyOneMigration`,
  `Run.bumpOneBlocked`, and
  `Upgrade.runOnePostUpgradeMigration`. The test fixture's
  `defaultOpts` got the same treatment.
- Four behavioral tests landed under `MigrateSpec.hs`'s "EP-26"
  subsection: clean apply with `--commit-message`, outside-of-git
  no-op, dry-run gating, and blocked-outcome gating. Total CLI
  test count grew from 190 to 194.
- Docs: `docs/cli/migrate.md` got the two new flags in its Options
  table, an `## Auto-commit` section that mirrors `docs/cli/run.md`
  including the `RunCommand`-doesn't-stage and bump-only-still-commits
  caveats, and two examples. A CHANGELOG entry was added under the
  topmost unreleased heading.

Compared to original purpose: the user-visible UX described in
"Purpose / Big Picture" is delivered intact —
`seihou migrate <module> --commit-message "msg"` produces exactly
one commit whose subject is `msg` and whose stat names the
moved/deleted files plus `.seihou/manifest.json`. The `--commit`
(AI-message) branch is unchanged from `seihou run`'s — it shells
out to `claude -p` if available and falls back to the template
otherwise; this branch is not exercised in CI but its only new
input is the `[opts.migrateModule]` list passed to
`generateCommitMessage`, which `seihou run` already passes for the
applied modules.

Lessons:

- The CLI placement convention bites tests: parser unit tests for
  flags introduced in `Seihou.CLI.Commands` cannot live in the
  current test target. The plan's parser-test bullet was retired
  with a Decision Log entry. Future work that wants parser tests
  in CI either has to lift the parser combinators into the library
  or add the executable target as a test dep.
- `git log --name-only` collapses renames to the destination path
  unless `--no-renames` is passed. Asserting the staged set of a
  rename op needs `--no-renames`; without it the test would
  silently miss a regression where the helper failed to stage one
  end of the move.
- The local `unless :: Bool -> IO () -> IO ()` shim that previously
  guarded against an unused-import warning was deleted: importing
  `when` alongside `unless` from `Control.Monad` is what M2 needed
  anyway, and now both helpers are real.


## Context and Orientation

A reader who has just cloned this repo and never touched it before
needs the following grounding to follow the rest of the plan.

### What `seihou` is

`seihou` is a composable, type-safe project scaffolding CLI. A user
runs `seihou run <module>` to apply a "module" (a directory full of
templates plus a `module.dhall` manifest) to the current working
directory; the result is recorded in `.seihou/manifest.json` so
subsequent runs know what to refresh. Modules can declare
**migrations** — author-supplied edits to a project's working tree
that move it from version X of the module to version Y. The command
that applies those migrations is `seihou migrate`.

Two extra terms used throughout this plan:

- **Manifest**: `./.seihou/manifest.json`, a JSON record of every
  applied module, every generated file's hash, and every recorded
  variable value. Migrations rewrite parts of it.
- **Installed copy**: `~/.config/seihou/installed/<module-name>/`,
  a clone of the module's source repository. `seihou install`
  populates it; `seihou upgrade` and the default `seihou migrate`
  flow refresh it.

### The CLI library/executable split

The CLI is split into two cabal targets in one package
(`seihou-cli/seihou-cli.cabal`):

- The library `seihou-cli-internal` lives at
  `seihou-cli/src/`. It owns code that does not depend on
  `Options.Applicative`, `Data.FileEmbed`, `GitHash`, or
  `Paths_seihou_cli`.
- The executable target `seihou` lives at `seihou-cli/src-exe/`.
  It owns `Main.hs`, every `optparse-applicative` parser, and any
  module that transitively imports one of those four
  executable-only dependencies.

`docs/dev/architecture/overview.md` describes the convention in full
under the heading "CLI Module Placement Convention". The check is
mechanically enforced by `nix/check-cli-module-placement.sh`. Any
new code added in this plan must respect that split. In practice
this plan only adds fields to existing types and edits already-placed
modules, so no new placement decisions arise.

### Files relevant to this plan

The numbered locations below were taken from the working tree at the
start of this work. Line numbers may drift; use ripgrep to locate
the exact spot each time.

- **`seihou-cli/src/Seihou/CLI/Migrate.hs`** — Library module
  defining `MigrateOpts` (data record at line ~79), `MigrateResult`
  (sum type at line ~147), `handleMigrate` (the IO shell entry
  point at line ~195), and `runMigrate` (the non-IO core at line
  ~396). The `handleMigrate` function dispatches on the
  `MigrateResult` variant returned by `runMigrate` and is where the
  new commit step will be inserted, on the success branches.

- **`seihou-cli/src/Seihou/CLI/Git.hs`** — Already exists. Exposes
  `isGitRepo`, `gitAdd`, `gitCommit`, `gitDiffCached`,
  `gitCheckIgnore`, all parameterized over the `Process` effect.
  No changes required.

- **`seihou-cli/src/Seihou/CLI/CommitMessage.hs`** — Already exists.
  Exposes `generateCommitMessage :: [ModuleName] -> Text -> IO Text`,
  which shells out to `claude -p` and falls back to a template
  message on failure. No changes required.

- **`seihou-cli/src-exe/Seihou/CLI/Commands.hs`** — Optparse
  parsers and `Command` enum. The migrate parser is `migrateParser`
  starting at line ~928 and its `migrateInfo`/`migrateFooter` blocks
  surround it. The `runParser` (lines ~632–668) shows the exact
  pattern the new switches should follow — see the two lines that
  parse `runCommit` and `runCommitMessage`.

- **`seihou-cli/src-exe/Seihou/CLI/Run.hs`** — The IO entry
  `handleRun`. Lines 341–368 implement the existing `--commit` /
  `--commit-message` post-execution logic against the diff
  result. The new migrate-side helper will be a near-clone of
  this block.

- **`seihou-cli/src-exe/Seihou/CLI/Upgrade.hs`** — `seihou upgrade`
  internally constructs a `MigrateOpts` record (line ~378) when
  `--with-migrations` is set. M1 must extend that literal with the
  two new fields.

- **`seihou-cli/test/Seihou/CLI/MigrateSpec.hs`** — Test file with
  `defaultOpts` literal at line ~143 that must be extended in M1.
  Also the appropriate place to add the new behavioral tests in M3,
  unless the per-Decision-Log note about splitting out a separate
  spec is taken.

- **`seihou-cli/test/Seihou/CLI/GitSpec.hs`** — Existing pure-mock
  tests for the git helpers. Provides the testing pattern (process
  mocks via `Seihou.Effect.ProcessPure`) but no changes required;
  the new commit logic is glue and is best tested end-to-end in
  `MigrateSpec.hs`.

- **`docs/cli/migrate.md`** — User-facing reference for the
  command. Documents every option in a table, lists examples, and
  cross-links to `docs/user/migrations.md`. M4 edits this file.

- **`docs/cli/run.md`** — Sibling reference. Already documents
  `--commit` and `--commit-message`. Use it as the prose template
  for the new migrate.md section.

- **`docs/user/CHANGELOG.md`** — User-facing changelog. M4 adds an
  entry under the topmost unreleased heading.

### Key types you will touch

In `seihou-cli/src/Seihou/CLI/Migrate.hs` (current shape, abbreviated):

    data MigrateOpts = MigrateOpts
      { migrateModule       :: ModuleName
      , migrateTo           :: Maybe Text
      , migrateDryRun       :: Bool
      , migrateForce        :: Bool
      , migrateJson         :: Bool
      , migrateVerbose      :: Bool
      , migrateNoFetch      :: Bool
      , migrateBumpOnly     :: Bool
      }

After this plan it will become:

    data MigrateOpts = MigrateOpts
      { migrateModule         :: ModuleName
      , migrateTo             :: Maybe Text
      , migrateDryRun         :: Bool
      , migrateForce          :: Bool
      , migrateJson           :: Bool
      , migrateVerbose        :: Bool
      , migrateNoFetch        :: Bool
      , migrateBumpOnly       :: Bool
      , migrateCommit         :: Bool
      , migrateCommitMessage  :: Maybe Text
      }

In `seihou-core/src/Seihou/Engine/Migrate.hs` (no change here, listed
for reference because the new helper inspects values of these types):

    data MigrationOpInstance
      = MoveFileInst   FilePath FilePath MigrationFileStatus
      | MoveDirInst    FilePath FilePath
      | DeleteFileInst FilePath MigrationFileStatus
      | DeleteDirInst  FilePath
      | RunCommandInst Text (Maybe FilePath)

    data ExecutedMigrationPlan = ExecutedMigrationPlan
      { planModule :: ModuleName
      , planChain  :: MigrationChain
      , planOps    :: [MigrationOpInstance]
      }

The path-extraction logic for the new helper consumes
`plan.planOps` and yields a list of `FilePath`s (see the Plan of
Work for the exact case-by-case mapping).


## Plan of Work

The work splits into five milestones, each independently verifiable.

### Milestone 1 — extend `MigrateOpts` and add the parser switches

Scope: pure data-shape and parser changes plus the cascade of
literal updates the new fields force on internal callers and tests.
What exists at the end: the build compiles with the two new fields
threaded through every `MigrateOpts` construction site, but the
fields are inert (nothing consults them yet). The CLI accepts
`--commit` and `--commit-message MSG` on `seihou migrate` but the
flags do nothing user-visible.

Steps:

1. In `seihou-cli/src/Seihou/CLI/Migrate.hs`, locate the
   `data MigrateOpts = MigrateOpts { … }` block and add two new
   record fields at the end:

       , -- | When 'True', and only on success branches that mutated
         -- the project's working tree, stage the touched files plus
         -- '.seihou/manifest.json' and create a git commit. The
         -- commit message is supplied by 'migrateCommitMessage' if
         -- set, otherwise generated by
         -- 'Seihou.CLI.CommitMessage.generateCommitMessage'. Has no
         -- effect for dry-run, no-op, blocked, or benign-upgrade
         -- outcomes. Has no effect outside a git work tree.
         migrateCommit :: Bool
       , -- | Custom commit message; implies @migrateCommit = True@.
         -- When 'Nothing', the AI-generated message is used.
         migrateCommitMessage :: Maybe Text

   Order matters because every constructor literal in the codebase
   uses positional or named-field syntax — the named-field ones are
   safe but the parser combinator chain in `Commands.hs` (`<*>`)
   relies on positional construction. The combinator chain will be
   updated in step 2 below.

2. In `seihou-cli/src-exe/Seihou/CLI/Commands.hs`, find
   `migrateParser` (currently around line 928–949) and append two
   new combinators in the same order as the new record fields:

       <*> switch
         ( long "commit"
             <> help "Commit migrated files to git after execution (uses AI-generated message)"
         )
       <*> optional
         ( option
             (T.pack <$> str)
             ( long "commit-message"
                 <> metavar "MSG"
                 <> help "Custom commit message (implies --commit)"
             )
         )

   The `help` strings are intentionally identical to the run-side
   ones so help output stays consistent.

3. Add an example to `migrateFooter` (the `Examples:` block, lines
   ~975–982). One new line is enough:

       pretty ("seihou migrate haskell-base --commit         # auto-commit after migrate" :: String)

4. In `seihou-cli/src-exe/Seihou/CLI/Run.hs`, locate the two
   `MigrateOpts { … }` literals — one inside `applyOneMigration`
   (line ~650) and one inside `bumpOneBlocked` (line ~724). Add to
   both:

       , migrateCommit = False
       , migrateCommitMessage = Nothing

   These callers must keep the new fields off because the run-side
   commit logic is already separate.

5. In `seihou-cli/src-exe/Seihou/CLI/Upgrade.hs`, locate the
   `MigrateOpts { … }` literal around line 378 and apply the same
   two-field addition.

6. In `seihou-cli/test/Seihou/CLI/MigrateSpec.hs`, locate
   `defaultOpts :: MigrateOpts` at line ~143 and apply the same
   two-field addition.

Verification:

- Run `cabal build all` from the repo root. Expected: build
  succeeds, no warnings beyond the pre-existing baseline.
- Run `cabal run seihou -- migrate --help` and visually confirm
  the two new flags appear under the option list.

### Milestone 2 — wire commit logic into `handleMigrate`

Scope: implement and integrate the new `commitMigratedFiles`
helper. What exists at the end: a successful `seihou migrate
<module> --commit` invocation in a git repo creates a commit that
contains the moved/deleted/touched paths plus the manifest, with an
AI- or user-supplied message.

Steps:

1. In `seihou-cli/src/Seihou/CLI/Migrate.hs`, add the new helper
   adjacent to the existing `runMigrateLocal`/`runMigrateWithFetch`
   helpers (the file is already long; place the new code near the
   bottom of the file, before the `findApplied` definitions). The
   shape:

       commitMigratedFiles ::
         MigrateOpts ->
         FilePath ->            -- manifest path
         ExecutedMigrationPlan ->
         IO ()
       commitMigratedFiles opts manifestPath plan = do
         let touched = concatMap pathsForOp plan.planOps
             filesToStage = touched ++ [manifestPath]
         inGit <- runEff $ runProcessIO $ isGitRepo
         if not inGit
           then pure ()
           else do
             ignored <- runEff $ runProcessIO $ gitCheckIgnore filesToStage
             let staged = filter (`notElem` ignored) filesToStage
             if null staged
               then pure ()
               else do
                 (addExit, _, addErr) <- runEff $ runProcessIO $ gitAdd staged
                 case addExit of
                   ExitFailure _ -> TIO.hPutStrLn stderr ("git add failed: " <> addErr)
                   ExitSuccess -> do
                     msg <- case opts.migrateCommitMessage of
                       Just m -> pure m
                       Nothing -> do
                         diffText <- runEff $ runProcessIO $ gitDiffCached
                         generateCommitMessage [opts.migrateModule] diffText
                     (cExit, _, cErr) <- runEff $ runProcessIO $ gitCommit msg
                     case cExit of
                       ExitSuccess -> pure ()
                       ExitFailure _ ->
                         TIO.hPutStrLn stderr ("git commit failed: " <> cErr)
         where
           pathsForOp inst = case inst of
             MoveFileInst src dest _ -> [src, dest]
             MoveDirInst src dest    -> [src, dest]
             DeleteFileInst path _   -> [path]
             DeleteDirInst path      -> [path]
             RunCommandInst _ _      -> []

   The exact import additions needed in `Migrate.hs`:

       import Data.Maybe (isJust)            -- already present
       import Seihou.CLI.Git
         (gitAdd, gitCheckIgnore, gitCommit, gitDiffCached, isGitRepo)
       import Seihou.CLI.CommitMessage (generateCommitMessage)
       import Seihou.Effect.ProcessInterp (runProcessIO)   -- already present
       import qualified Data.Text.IO as TIO               -- already present
       import System.IO (stderr)

2. In `handleMigrate`, find the two success branches that write the
   manifest:

   - `MigrateApplied plan manifest'` — three sub-branches (empty
     `planOps` JSON, empty `planOps` non-JSON, and the otherwise
     case). Insert the commit call after the `writeManifest`
     statement on each sub-branch:

         when (opts.migrateCommit || isJust opts.migrateCommitMessage) $
           commitMigratedFiles opts manifestPath plan

   - `MigrateAppliedPartial plan manifest' _ _` — single branch.
     Insert the same call after the `writeManifest` statement.

   The `when` import comes from `Control.Monad`; `isJust` is already
   imported. Add `import Control.Monad (when, unless)` if `when` is
   not already in scope (the file currently imports `unless` only).

3. The dry-run branches (`MigrateDryRunOK`, `MigrateDryRunOKPartial`)
   must remain unchanged — they explicitly do not write the manifest,
   so do not commit.

4. The `MigrateNoOp`, `MigrateBlocked`, and `MigrateBenignUpgrade`
   branches likewise remain unchanged.

5. Confirm by inspection that the new helper is **not** called from
   `runMigrate`, only from `handleMigrate`. This keeps the behavior
   inert for `seihou run --with-migrations` and `seihou upgrade
   --with-migrations`.

Verification:

- `cabal build all`.
- Manual end-to-end: build a scratch repo per the M5 instructions
  (the milestone exists primarily to formalize the manual
  verification; M2's success can be observed by following the M5
  recipe early).

### Milestone 3 — tests

Scope: unit and behavioral coverage for the new flags and the new
helper. What exists at the end: every flag-combination branch is
covered by a test, and the test suite still passes end-to-end.

Steps:

1. Parser unit tests. Add to `seihou-cli/test/` (or the existing
   `MigrateSpec`) a small block that exercises
   `Options.Applicative.execParserPure` against `migrateParser` (or
   the equivalent parser export). Assert:

   - `seihou migrate foo` → `migrateCommit == False`,
     `migrateCommitMessage == Nothing`
   - `seihou migrate foo --commit` → `migrateCommit == True`,
     `migrateCommitMessage == Nothing`
   - `seihou migrate foo --commit-message "x"` →
     `migrateCommitMessage == Just "x"`. (The "implies --commit"
     semantics is enforced at use-site by the
     `migrateCommit || isJust migrateCommitMessage` guard, not by
     the parser.)

2. Behavioral tests. Reuse the project-on-disk fixture in
   `MigrateSpec.hs` (the one that builds a real manifest, a real
   installed copy, and a real working tree under a temp dir). Add
   four cases:

   a. **Custom message commits to git.** Initialize the temp
      project as a git repo, commit a baseline, run
      `runMigrate` with `migrateCommit = True,
      migrateCommitMessage = Just "chore: migrate"` plus
      `migrateNoFetch = True` against the existing fixture, then
      drive `handleMigrate`'s commit step (or, if
      `commitMigratedFiles` is exported from the library module,
      call it directly). Assert the latest git commit subject equals
      `"chore: migrate"` and that the staged path set includes the
      moved file plus `.seihou/manifest.json`.

   b. **Outside a git repo, the flag is a silent no-op.** Same
      fixture but skip the `git init`. Run with `--commit-message
      "msg"`. Assert the manifest still got written (apply succeeded)
      and the helper did not throw.

   c. **Dry-run never commits.** Run with `migrateDryRun = True,
      migrateCommit = True`. Assert no commit was created.

   d. **`MigrateBlocked` outcome never commits.** Engineer the
      manifest version so that the planner returns `MigrateBlocked`
      (manifest at v1.0.0, declared migrations only cover
      v1.1.0 → v1.2.0, installed at v1.2.0). Run with
      `--commit-message "x"`. Assert no commit was created.

   The first test should accommodate the fact that
   `generateCommitMessage` shells out to `claude` when no custom
   message is given; tests with `--commit` (no message) will be
   slow if `claude` is on the test host. Stick to
   `--commit-message "literal"` in CI tests; cover the AI path in
   M5's manual verification.

3. Run the full suite:

       cabal test all

   Expected: all CLI specs pass (current count is `89` per the
   earlier run-commit-flag plan; the new tests will increment that).

Verification:

- `cabal test all` exits zero.
- The parser tests deterministically pass with the literal field
  comparisons.

### Milestone 4 — documentation

Scope: keep `docs/cli/migrate.md`, `docs/user/CHANGELOG.md`, and any
sibling references in sync. What exists at the end: a user reading
the migrate docs sees the new flags documented identically to how
`docs/cli/run.md` documents them on the run side.

Steps:

1. In `docs/cli/migrate.md`, add two rows to the Options table:

   | `--commit` | Stage and commit the files migrated this run plus `.seihou/manifest.json`. The commit message is generated via Claude Code (`claude -p`); on failure or absence of `claude`, falls back to a template message. No-op outside a git work tree. |
   | `--commit-message MSG` | Use `MSG` as the commit message verbatim. Implies `--commit`. |

2. After the existing `### --bump-only` subsection (or anywhere
   in the description block where it reads naturally), add a new
   subsection `## Auto-commit` that mirrors the relevant prose
   from `docs/cli/run.md`. Specifically call out:
   - Only the success branches that touched files commit
     (i.e. full-chain and partial-chain applies, plus
     `--bump-only`); blocked / benign / no-op outcomes do not.
   - `RunCommand` migration ops do not contribute paths to the
     stage set; if a chain includes them, additional working-tree
     changes must be committed separately.
   - Outside a git repo the flags are silent no-ops.

3. Add at least one example to the `## Examples` block:

       # Apply the chain and auto-commit with an AI-generated message
       seihou migrate haskell-base --commit

       # Apply the chain and auto-commit with a custom subject line
       seihou migrate haskell-base --commit-message "chore: migrate haskell-base"

4. Add an entry to `docs/user/CHANGELOG.md`, under the topmost
   unreleased heading (create one if needed):

       - `seihou migrate` now supports `--commit` and
         `--commit-message`, mirroring the existing flags on
         `seihou run`. After a successful migration, the moved /
         deleted files plus `.seihou/manifest.json` are staged and
         committed in one step.

5. If `docs/cli/run.md` already mentions the migrate command in its
   own auto-commit section, add a back-reference there too. If not,
   leave that file alone — the migrate docs link out to run.md, which
   is sufficient.

Verification:

- Open the rendered files in a Markdown viewer (or skim them in a
  terminal) and confirm headings line up.
- Re-read `docs/cli/migrate.md` end-to-end and confirm the new
  prose follows the same voice as the surrounding sections.

### Milestone 5 — end-to-end verification

Scope: prove the feature works against a real filesystem, real git,
and (optionally) real Claude. What exists at the end: a transcript
showing the new flag pair behaving as advertised.

Steps:

The fixture is awkward to spell out exactly because it depends on
the user having a module repo to `seihou install`. Two paths exist;
take whichever is faster.

A. **Reuse a fixture from the existing migrate test suite.** The
   `MigrateSpec` already builds a project + installed copy + manifest
   inside a temp dir. Run that fixture's setup interactively
   (e.g. via `cabal repl seihou-cli-test` and calling the helper
   directly), then run `git init && git add . && git commit -m
   baseline` inside the temp project, then exercise the seihou
   binary against it.

B. **Author a tiny one-shot test module.** Create
   `/tmp/migrate-commit-test/installed-mod/module.dhall` declaring
   one file template and one migration that moves it. Install with
   `seihou install /tmp/migrate-commit-test/installed-mod`, run
   `seihou run` to bootstrap the project at v1.0.0, then bump the
   installed copy's version to v1.1.0 by editing the dhall and
   re-running `seihou install`. The next `seihou migrate <name>`
   will have a real chain to run.

Either way, once the fixture is set up, run:

    cd <project-dir>
    git init && git add . && git commit -m baseline
    cabal run seihou -- migrate <module> --commit-message "chore: migrate"
    git log -1 --stat

Expected: a single new commit, subject line `chore: migrate`, stat
naming the moved/deleted files plus `.seihou/manifest.json`.
`git status` clean.

    git reset --hard HEAD~1                # roll back to baseline
    cabal run seihou -- migrate <module> --dry-run --commit
    git log -1 --oneline                   # still the baseline commit
    git status                             # the dry-run preview was non-destructive

Expected: no new commit; manifest unchanged.

If `claude` is on `PATH`, also try:

    git reset --hard <baseline>
    cabal run seihou -- migrate <module> --commit
    git log -1 --pretty=%B

Expected: a non-empty subject line that mentions the module name.
If `claude` is not available, expect the fallback subject
`seihou: apply module <name>`.

Verification:

- All three transcripts above match the expected outputs.


## Concrete Steps

The exact commands a contributor will run, in order, from the repo
root (`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`).

Setup:

    git switch -c migrate-commit-flag

Build baseline (capture pre-existing warnings so M1's "no new
warnings" check is meaningful):

    cabal build all 2>&1 | tee /tmp/seihou-build-pre.log

M1 — make the data and parser changes (file edits, no commands).
Then:

    cabal build all 2>&1 | tee /tmp/seihou-build-m1.log
    diff /tmp/seihou-build-pre.log /tmp/seihou-build-m1.log

Expected: no new warnings, only the linker / package-coverage lines
that change between builds.

    cabal run seihou -- migrate --help 2>&1 | grep -E "commit|commit-message"

Expected output (lines may wrap):

      --commit                 Commit migrated files to git after execution (uses AI-generated message)
      --commit-message MSG     Custom commit message (implies --commit)

M2 — wire the helper. Re-run:

    cabal build all

Expected: build succeeds.

M3 — tests:

    cabal test all 2>&1 | tee /tmp/seihou-test.log
    grep -E "FAIL|examples|failures" /tmp/seihou-test.log

Expected: zero failures, the new test count is reflected in the
hspec summary.

M4 — docs (file edits, no commands).

M5 — manual verification (see Milestone 5 above for the
project-fixture commands).

Final:

    git add -A
    git status                              # confirm only intended files
    git commit -m "feat(migrate): add --commit and --commit-message flags

    seihou migrate now supports the same auto-commit flags as
    seihou run. After a successful chain apply, the touched paths
    plus .seihou/manifest.json are staged and committed in one step,
    with an AI-generated or user-supplied message.

    ExecPlan: docs/plans/26-migrate-commit-flag.md
    Intention: intention_01kq2gy6yde258gd30xjvs85g7"

(Splitting the work across multiple commits — one per milestone — is
also acceptable. Every commit must include both trailers.)


## Validation and Acceptance

The feature is accepted when **all** of the following hold:

1. `cabal build all` succeeds with no new warnings (compared to the
   baseline captured at the start of the work).

2. `cabal test all` succeeds with zero failures. The new test cases
   under M3 are present in the suite output.

3. `cabal run seihou -- migrate --help` lists `--commit` and
   `--commit-message MSG` under its options block, with help text
   identical to the run-side help text.

4. The M5 transcripts hold:
   - `seihou migrate <module> --commit-message "chore: migrate"`
     produces exactly one new git commit whose subject is
     `chore: migrate` and whose stat names the moved files plus
     `.seihou/manifest.json`.
   - `seihou migrate <module> --commit --dry-run` does not produce
     any new commit and does not modify the manifest.
   - In a non-git directory, `seihou migrate <module> --commit-message
     "x"` exits zero, applies the migration, and creates no commit
     (silent no-op on the git side).

5. `seihou run --with-migrations` and `seihou upgrade
   --with-migrations` continue to behave exactly as they did before
   this change — the new fields are off in their internal
   `MigrateOpts` constructions, so no extra commits appear.

6. `docs/cli/migrate.md` and `docs/user/CHANGELOG.md` are updated as
   described in M4.


## Idempotence and Recovery

All edits in this plan are reversible by `git checkout -- <file>`
or, more bluntly, `git reset --hard <baseline>`. The plan does not
add or remove any external dependency, does not edit any cabal
file, and does not touch `.seihou/manifest.json` at the repository
root (which is not a thing in this repo anyway).

If M2's commit step misbehaves on a real project — e.g. `git add`
trips over a path that no longer exists — rerunning the failing
case is safe: the manifest write happened first, so the chain has
already been applied; the user can manually `git add` and `git
commit` the touched paths to recover, then debug the helper.

If M5 leaves a temp-dir fixture on the filesystem, `rm -rf` it
freely; nothing in the project depends on it.


## Interfaces and Dependencies

No new third-party dependencies. The changes use existing modules:

- `Seihou.CLI.Git` (already exists at
  `seihou-cli/src/Seihou/CLI/Git.hs`) supplies `isGitRepo`,
  `gitAdd`, `gitCommit`, `gitDiffCached`, `gitCheckIgnore`,
  parameterized over the `Process` effect.
- `Seihou.CLI.CommitMessage` (already exists at
  `seihou-cli/src/Seihou/CLI/CommitMessage.hs`) supplies
  `generateCommitMessage :: [ModuleName] -> Text -> IO Text`.
- `Seihou.Effect.ProcessInterp.runProcessIO` is the IO interpreter
  used to discharge the `Process` effect.
- `Seihou.Engine.Migrate` (in `seihou-core`) already exposes
  `ExecutedMigrationPlan` and the `MigrationOpInstance` data
  constructors the new helper pattern-matches on.

After Milestone 1, the `MigrateOpts` record will have the shape
shown in the **Context and Orientation → Key types** section. After
Milestone 2, `seihou-cli/src/Seihou/CLI/Migrate.hs` will export an
additional helper:

    commitMigratedFiles ::
      MigrateOpts ->
      FilePath ->                  -- manifest path
      ExecutedMigrationPlan ->
      IO ()

(Whether to export this helper from the module is a judgment call;
the in-module name is enough for `handleMigrate`. If a test wants
to call it directly, exporting it is fine.)

After Milestone 3, the `seihou-cli` test suite contains parser unit
tests for the new flags and at least four behavioral tests under
`Seihou.CLI.MigrateSpec`. After Milestone 4, the user-facing docs
match the implemented behavior.
