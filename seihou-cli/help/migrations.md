MIGRATIONS

A migration is an author-declared sequence of file-system operations that
moves a project's working tree from one module version to another. When a
module is upgraded — say, from haskell-base 1.0.0 to 2.0.0 — the project
that has it applied may need to rename directories, drop files that v2
doesn't ship, or run a one-off command. Migrations let module authors
ship that knowledge inside `module.dhall` so consumers don't have to read
a CHANGELOG and reconcile by hand.

WHEN TO AUTHOR A MIGRATION

  Add a migration when a new version of your module changes the *layout*
  of the files it generates: a directory rename, a file removal, a path
  pattern shift. You do not need a migration for content-only changes;
  re-running `seihou run <module>` already updates file content. Use
  migrations specifically for things that `seihou run` cannot infer on
  its own.

THE MIGRATION RECORD

  Each migration is one record in the `migrations` field of `module.dhall`:

    , migrations =
        [ S.Migration::{ from = "1.0.0"
                       , to = "2.0.0"
                       , ops =
                           [ S.MigrationOp.MoveDir
                               { src = "app", dest = "src" }
                           , S.MigrationOp.DeleteFile
                               { path = "Setup.hs" }
                           ]
                       }
        ]

  - `from` and `to` are dotted versions parsed by `parseVersion`.
  - `ops` is the list of operations applied in order.

OPERATIONS

  Authors compose migrations from five typed operations:

  MoveFile    Rename a single tracked file. The engine rewrites the
              manifest's files-map key from src to dest so subsequent
              `seihou status` and `seihou diff` keep working.

                S.MigrationOp.MoveFile { src = "lib/Old.hs", dest = "src/New.hs" }

  MoveDir     Rename a directory. Every manifest entry whose path lies
              under src/ has its key rewritten with the dest/ prefix.

                S.MigrationOp.MoveDir { src = "app", dest = "src" }

  DeleteFile  Remove a tracked file. Drops the manifest entry.

                S.MigrationOp.DeleteFile { path = "Setup.hs" }

  DeleteDir   Recursively remove a directory and drop every manifest
              entry under that prefix.

                S.MigrationOp.DeleteDir { path = "obsolete" }

  RunCommand  Run a shell command. The escape hatch for changes the
              other ops can't express. The manifest is *not*
              automatically updated; if your command moves files, you
              are responsible for following it with explicit
              MoveFile/DeleteFile ops or living with manifest drift.

                S.MigrationOp.RunCommand
                  { run = "cabal run my-tool -- migrate", workDir = None Text }

CHAIN SEMANTICS

  When a user runs `seihou migrate`, the planner finds a contiguous
  sequence of migrations that spans the project's recorded version up
  to the target. The chain is built greedily:

    installed: 1.0.0    target: 3.0.0
    declared:  1.0.0 → 2.0.0,  2.0.0 → 3.0.0

  picks both, in order. There is no graph search and no skipping. If
  two migrations share the same `from`, that is an ambiguity and the
  planner refuses (`MigrationDuplicateEdge`). If a migration would
  jump past the target (e.g. 1.0.0 → 5.0.0 when target is 2.0.0), that
  is `MigrationOvershoot` and the planner refuses too — the author
  should ship intermediate migrations or the user should pass `--to`.

CONFLICT SEMANTICS

  Mirroring `seihou remove`, the engine classifies each
  file-targeted op into one of three states before touching disk:

    MFSafe     Disk hash matches the manifest's recorded hash. Free
               to move or delete.
    MFConflict Disk hash differs. The user has edited the file since
               it was generated. The engine refuses to overwrite
               unless `--force` is passed.
    MFGone     File is absent on disk. The op is a no-op.

  The conflict check happens up front. With one or more `MFConflict`
  paths and no `--force`, no disk mutation occurs. With `--force`, the
  migration proceeds and the user-edited bytes ride along (a
  MoveFile preserves content; a DeleteFile drops it).

DRY RUN

  `seihou migrate <module> --dry-run` prints the plan and exits. The
  output is identical to a real run, minus the actual disk
  modifications. Use this before any non-trivial migration to see
  what would be touched.

  For a machine-readable form, pass `--json` (works alongside
  `--dry-run`).

UPGRADE INTEGRATION

  `seihou upgrade` updates the central installed copy under
  ~/.config/seihou/installed/<name>/ but does *not* rewrite project
  trees by default. After an upgrade that brings new migrations,
  `seihou upgrade` prints a one-line advisory:

    note: haskell-base has 1 migration(s) pending (1.0.0 → 2.0.0);
          run 'seihou migrate haskell-base'

  Pass `--with-migrations` to skip the advisory and run migrations
  for each upgraded module against the current project in one shot.

STATUS INTEGRATION

  `seihou status` shows a `Pending migrations: …` sub-line under any
  applied module whose installed copy has advanced past the manifest's
  recorded version with a covering chain. The line is informational —
  use `seihou migrate <module>` to apply.

MANIFEST GUARANTEE

  After a successful (non-dry-run) migration, the manifest's files map
  reflects the new paths exactly: a MoveFile rewrites one key, a
  MoveDir rewrites every contained key, deletes drop their entries,
  and the manifest's `genAt` is bumped. The named applied module's
  `moduleVersion` is updated to the chain's target. `seihou diff`
  after a clean migration is empty; `seihou status` shows no pending
  migrations.

SEE ALSO

  seihou migrate --help
  seihou upgrade --help
  docs/user/migrations.md
