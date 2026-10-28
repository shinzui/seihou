UPDATE

`seihou update` reconciles recorded module and recipe applications with newer
source content while preserving project-local edits. It is the routine way to
advance an existing project. `seihou run` remains the initial-generation and
explicit-reconfiguration command; `seihou upgrade` only refreshes the shared
installed cache.

BASIC WORKFLOW

  Preview every recorded application:

    seihou update --dry-run

  Update one recorded module or recipe application:

    seihou update master-plan

  No separate installation is needed for an existing remote-backed application:
  update fetches its remote and dependencies and reuses saved inputs. Review the
  preview and accept it. After adoption, fresh clones restore declared links with:

    seihou sync

  An `Adopt link:` preview means update will stop tracking an unchanged matching
  symlink in Git while keeping the working link. Accepting stages that removal;
  commit it with the manifest. Modified or staged links and regular objects remain
  protected. Dry-run/cancellation leave the index untouched; failed or interrupted
  uncommitted updates recover the adopted entries without replacing unrelated staging.

  Apply every recorded application in manifest order:

    seihou update

  Seihou stages newer source repositories before changing the installed cache,
  reuses the saved inputs for each module instance, plans migrations, renders
  new generated content, reconciles files, and runs new or changed application commands plus selected repeatable checkout
  commands on an actionable update.
  The installed cache and manifest are published only after the managed update
  succeeds.

TARGET SELECTION

  TARGET may name a recorded module or recipe, or a module contained in a
  recorded application. Repeat TARGET to select several applications. With no
  target, every recorded application is selected.

  When a path the selected applications would change is also owned by an
  unselected one, Seihou asks whether every owner reaches that path through an
  additive, non-overlapping patch. `append-line-if-absent` and
  `append-section` occupy disjoint slices of a file, so replaying one owner
  leaves the others' lines untouched and the update proceeds -- the ordinary
  case for `.gitignore`.

  Otherwise the update stops, because regenerating the file for one owner
  would discard another's content. That covers any path an owner writes
  wholesale, and the position-dependent `append-file` / `prepend-file`
  patches.

  The answer is recorded per path as `sharedWriteMode`: `additive-only`,
  `requires-ownership-closure`, or `unknown` for a manifest that predates it.
  A targeted update resolves `unknown` itself: it compiles each co-owner from
  its recorded version, reads how it writes the path, and records the answer
  with the required lossless manifest preparation. It inspects the co-owners
  but never updates their files. `--dry-run` shows any required schema
  transition and writes nothing.

  If a co-owner's recorded version is not installed here, update fetches its
  exact recorded release from its origin for certification. It does not update
  that co-owner. Only if evidence still cannot be obtained does it stop with
  `shared_write_evidence_unavailable`; fix the reported origin/network problem
  or deliberately include the co-owner. Machine-local origins can be repaired
  with `seihou manifest repair-origins --dry-run`, then the apply command.
  A schema-5 or older manifest stops with `manifest_upgrade_required`: run
  `seihou manifest upgrade --dry-run`, review, then `seihou manifest upgrade`.

  When the refusal is genuine (`shared_path_requires_applications`), name the
  required owners as targets, or pass `--include-shared-owners` to expand the
  selection to exactly the owners required, updating their full
  applications. Each added application is reported. Owners are named as
  `seihou status` names them, e.g. `exec-plan [skill.name=exec-plan]`.
  Seihou never broadens a named selection without being asked.

SAVED INPUTS

  An ordinary update reuses the exact accepted value recorded for each module
  instance. Override a value with a repeatable `--var KEY=VALUE`. A newly added
  required variable follows the normal resolution chain and may prompt in an
  interactive terminal.

  `--reconfigure` intentionally ignores saved values and resolves every input
  again. Use it to change configuration, not for routine source updates.

  Recipe applications also reuse recorded recipe inputs before member variables.
  Inputs used only by conditions survive fresh clones. Ordinary preview prepares
  schema 12 as needed and adopts agreeing historical values; conflicting or newly
  required choices need --var KEY=VALUE or --reconfigure. Recipe-only changes are
  recorded even when no generated file changes.

MIGRATIONS

  Applicable module migrations are always included. Declarative moves and
  deletes are staged so `--dry-run` can show the post-migration file plan.
  Migration shell commands are listed but cannot be simulated or rolled back
  outside Seihou's managed paths. There is no skip-migrations flag because new
  templates against an old project layout would be unsafe.

THREE-WAY FILE RECONCILIATION

  For each generated text file, Seihou compares:

    baseline    Content generated by the previous successful application
    current     Content now on disk, including user edits
    generated   Content produced from the candidate source

  If only one side changed, that change wins. Non-overlapping user and module
  changes merge automatically. Overlapping edits become a conflict with diff3
  markers labeled current, baseline, and generated. Interactive runs let the
  user choose generated content, current content, conflict markers, or abort.

  An obsolete generated file is deleted only when it is unchanged. An edited
  orphan can be retained, detached, or explicitly deleted. `--force` accepts
  permitted deterministic conflict choices but retains edited orphans; it does
  not silently delete user data. Binary content that changed on both sides
  remains a conflict.

COMMANDS

  By default, only new or changed application commands run; checkout commands
  repeat during an accepted actionable update, in their original mixed order.
  Their presence alone does not make update actionable. A declaration change does.
  A true no-op executes neither lifecycle; use sync to repeat recorded local setup.
  --run-all-commands explicitly makes command execution actionable; --no-commands
  suppresses both lifecycles while retaining checkout declarations. Those flags
  are mutually exclusive. Only application commands receive success receipts,
  published after the entire phase succeeds.

PREVIEW, AUTOMATION, AND COMMITS

  `--dry-run` prints the complete plan without changing project files, cache,
  baselines, or manifest. `--json` emits one machine-readable JSON document and
  disables prompts. Supply required values and conflict choices in advance for
  non-interactive use.

  `--commit` commits only managed paths from a successful update.
  `--commit-message MSG` supplies the message and implies `--commit`. Neither
  commit option can be combined with `--dry-run`.

TRANSACTION SAFETY

  Before mutation, Seihou checks that the manifest, project files, and staged
  sources still match the accepted plan. Managed migrations, files, baseline
  blobs, installed-cache entries, and the manifest are protected by recovery
  journals. The manifest is the final publication marker.

  External effects from module or migration shell commands cannot be undone.
  A failure reports that limitation instead of claiming a full rollback.

LEGACY PROJECTS

  A manifest without recorded applications needs one explicit TARGET for its
  first update. That successful run seeds application identity, saved inputs,
  ownership, generated baselines, and command receipts. Ambiguous legacy values
  are reported rather than guessed.

SEE ALSO

  seihou update --help
  seihou help modules
  seihou help migrations
  seihou status --help
  docs/cli/update.md

For recorded local setup, use `seihou sync`: it repairs links and executes declared
repeatable commands without producer resolution. Maintainers adopt changed specs
through ordinary update and commit them before teammates sync. A true no-op update
executes neither command lifecycle; --no-commands preserves setup declarations.

PROJECT-OWNED SEEDS

  Update TARGET previews "release to project" when a producer hands managed
  starter files to the project. Normal confirmation preserves bytes or absence
  and removes managed hashes/baselines. New absent seeds are created once;
  receipts preserve later edits and deletion. Commit the manifest for clones.
  Last-claim retirement keeps disk contents. Reverse seed-to-managed adoption
  requires an explicit interactive keep/accept choice; --force/JSON cannot consent.
  Declarative migrations cannot touch seeds. Arbitrary shell is unsandboxed.
