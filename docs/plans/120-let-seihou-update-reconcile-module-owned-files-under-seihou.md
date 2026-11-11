---
id: 120
slug: let-seihou-update-reconcile-module-owned-files-under-seihou
title: "Let seihou update reconcile module-owned files under .seihou"
kind: exec-plan
created_at: 2026-11-11T13:49:25Z
intention: "intention_01m75dxfcnektbt081rhk1s71v"
provenance:
  created_by:
    model: "claude-opus-5-5"
    harness: "claude-code"
    at: 2026-11-11T13:49:25Z
  revisions:
    - model: "claude-opus-5-5"
      harness: "claude-code"
      at: 2026-11-11T14:03:28Z
      mode: "implement"
      note: "Implement milestones 1-5"
---

# Let seihou update reconcile module-owned files under .seihou

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).

This plan implements [IR-19](../improvement-requests/update-module-files-that-seihou-run-wrote-under-dot-seihou.md),
raised from `mori://shinzui/kotei-docs/okf/friction-log/concepts/FRIC-4` against Seihou 0.15.0.0.


## Purpose / Big Picture

Seihou is a project generator. `seihou run <module>` renders a module's files into a project and
records each one in `.seihou/manifest.json`. `seihou update <module>` later brings a newer
release of that module into the project with a three-way merge: it compares the file Seihou
last generated (the *baseline*, kept under `.seihou/baselines/`), the file as it is on disk now,
and the file the new release would generate, so that a user's local edits survive the update.

Today the two commands disagree about one directory. `seihou run` lets a module write files
under `.seihou/`, and several published modules do exactly that: they keep their helper scripts
and configuration in a directory named after themselves, such as
`.seihou/docs-mori-bootstrap/bootstrap-docs.py`. `seihou update` refuses every managed path whose
first segment is `.seihou`, so once such a module is in an application, that application can
never be updated again:

```text
reconciliation_failed for .seihou/docs-mori-bootstrap/bootstrap-docs.py
Path .seihou/docs-mori-bootstrap/bootstrap-docs.py cannot be reconciled: path targets Seihou or Git control data
```

The only way forward is `seihou run <recipe> --force`, which overwrites managed files, discards
the merge, and silently resets any variable the user forgets to pass again.

After this change, a module owns one directory inside `.seihou/`, named exactly after the
module: `.seihou/<module-name>/`. Files a module generates there are applied by `seihou run`
and merged by `seihou update` like any other managed file. Seihou's own state under `.seihou/`
(the manifest, baselines, update transactions, project-local modules, configuration, context,
trace) stays unreachable from module output, now through `run` as well as through `update`,
where today `run` does not protect it at all. A module that tries to write anywhere else under
`.seihou/` is refused when it is generated, with a message that names the directory it may use,
so the module author finds the problem instead of the consumer.

To see it working, apply a module that writes `.seihou/demo/helper.txt`, edit that file, publish
a new module version that changes another line of it, and run `seihou update demo`: the update
succeeds and the file contains both the user's edit and the new release's change.


## Progress

- [x] Milestone 1: one shared path classifier in `seihou-core/src/Seihou/Core/Path.hs` that
  distinguishes ordinary project paths, a module's state directory, and Seihou or Git control
  paths, with unit tests in `seihou-core/test/Seihou/Core/PathSpec.hs` passing. (2026-11-11:
  16 cases pass under `-p "/project path classification/"`.)
- [x] Milestone 2: reconciliation, the update transaction, and update recovery accept
  `.seihou/<module>/` paths and still refuse control paths; new `ReconcileSpec` and
  `UpdateTransactionSpec` cases pass alongside the existing suite. (2026-11-11: all 1423 core
  tests pass; the stray-copy grep prints nothing; the reserved-list grep prints only reserved
  entries. Recovery has no direct unit test; Milestone 4's end-to-end update covers it.)
- [x] Milestone 3: generation enforces the same rule — load-time refusal of control paths,
  plan-time refusal of `.seihou/` paths outside the module's own directory, a
  `validate-module` check, and control-path refusal for migration and removal paths.
  (2026-11-11: 1435 core tests pass, 12 new in ModuleSpec, PlanSpec, ValidateSpec, MigrateSpec and
  RemoveSpec; the CLI suite's 877 tests still pass.)
- [x] Milestone 4: an end-to-end test through the `seihou` executable shows `run` then `update`
  merging a user edit in `.seihou/demo/helper.txt`, and `run` refusing `.seihou/manifest.json`
  and `.seihou/other/x`. (2026-11-11: 4 cases pass under
  `-p "/module state directory end-to-end/"`, including `validate-module` exiting non-zero with
  "Module state destinations".)
- [ ] Milestone 5: user documentation, changelogs, ADR 0025, and IR-19 updated; full test suite
  and `nix flake check` pass.


## Surprises & Discoveries

Findings made while writing this plan, recorded here because they shaped its design:

- Generation applies no `.seihou` rule at all. `checkSafeDestinations` in
  `seihou-core/src/Seihou/Core/Module.hs` and `validateRenderedDestination` in
  `seihou-core/src/Seihou/Engine/Plan.hs` call only `validateProjectRelativePath`, which rejects
  absolute paths and `..` segments. A module step with `dest = ".seihou/manifest.json"` is
  accepted by `seihou run` today.
- The existing refusal compares the first segment case-sensitively (`firstSegment == ".seihou"`).
  On a case-insensitive filesystem such as the default macOS volume, `.SEIHOU/manifest.json`
  names the manifest but passes the check. The new classifier folds case.
- The module ecosystem already follows a convention. In `mori://shinzui/seihou-modules`,
  `docs-mori-bootstrap`, `openapi-typescript-client-dir`, and `repo-dir` each write only under
  `.seihou/<their own module name>/`. One module, `gcp-kube-env`, writes the single file
  `.seihou/gcp-kube-env.conf` directly under `.seihou/`.
- Seihou itself keeps more under `.seihou/` than the IR names. A search of
  `seihou-core/src`, `seihou-cli/src`, and `seihou-cli/src-exe` for `".seihou"` finds
  `manifest.json` (and its temporary `manifest.json.tmp`), `baselines/`, `transactions/`,
  `transactions-quarantine/`, `modules/` (the project-local module search directory),
  `context`, `config.dhall`, `trace.jsonl`, and `.migrate-signal`. Several of these
  (`baselines`, `transactions`, `modules`, `context`) are also valid module names.
- (Implementation, 2026-11-11.) The plan's focused test commands such as
  `--test-options='-p PathSpec'` select nothing: tasty matches the `testSpec` group title, not the
  Haskell module name, and reports "All 0 tests passed". Use the group title instead, for example
  `--test-options='-p "/project path classification/"'`. Concrete Steps is corrected below.
- (Implementation, 2026-11-11.) `validateProjectRelativePath` accepts `.` segments, so
  `./.seihou/manifest.json` and `.seihou/./manifest.json` name the manifest. The classifier drops
  `.` segments as well as empty ones before looking at the first two.
- (Implementation, 2026-11-11.) The Milestone 4 fixture as first written (`top`, `middle v1`,
  `bottom`, with the user editing `top` and the release editing `middle`) does not merge cleanly:
  diff3, like `git merge`, treats edits to adjacent lines as overlapping, and the update stopped
  with `unresolved_conflicts ... .seihou/demo/helper.txt`. That run is itself evidence the path
  check no longer blocks the update. The test separates the two edits with an unchanged line.
  The pre-Milestone-2 `reconciliation_failed` output was not re-captured; IR-19 already records it.
- (Implementation, 2026-11-11.) A literal step `dest` in Seihou's own state is refused when the
  module loads ("step destination path targets Seihou's own state at .seihou/manifest.json"), so
  `seihou run` stops before planning and the manifest is untouched. The own-directory rule shows up
  at plan time as "step destination .seihou/other/x is outside this module's state directory; a
  module may write under .seihou/ only inside .seihou/demo/".
- Checkout outputs and seed files already refuse `.seihou` and `.git` components anywhere in a
  path, through `validateCanonicalProjectPath` in `seihou-core/src/Seihou/Core/Path.hs`.


## Decision Log

- Decision: Implement IR-19 option 1 (allow reconciliation inside a module-owned part of
  `.seihou/`) rather than option 2 (refuse all module output under `.seihou/`).
  Rationale: Three published modules already use `.seihou/<module-name>/` for helper scripts
  and configuration, and the docs-mori-bootstrap README documents it. Option 2 would break every
  application of those modules and require a migration in each one; option 1 makes their
  existing applications updatable with no module change.
  Date: 2026-11-11

- Decision: A module's state directory is `.seihou/<module-name>/` and the name must equal the
  generating module's own name exactly. Generation refuses a `.seihou/` destination in any
  other directory, including another module's.
  Rationale: Tying the directory to the owner gives authors one unambiguous rule, matches the
  existing convention, and means Seihou never has to guess whether an arbitrary
  `.seihou/<name>` is a module's or its own.
  Date: 2026-11-11

- Decision: Seihou's own entries under `.seihou/` are an explicit reserved list in
  `Seihou.Core.Path`, compared case-insensitively: `manifest.json`, `manifest.json.tmp`,
  `baselines`, `transactions`, `transactions-quarantine`, `modules`, `context`, `config.dhall`,
  `trace.jsonl`, and every name beginning with `.`. Everything under `.git` is a control path too, and the bare `.seihou`
  directory may be created but never written as a file. A module whose name is on the list has no state directory.
  New Seihou state under `.seihou/` must be added to the list and must use a name that is not a
  valid module name (one that does not match `[a-z][a-z0-9-]*`), so it can never collide with a
  module's directory. ADR 0025 records this.
  Rationale: An enumerated list is the only rule that both protects every location Seihou uses
  today and still lets the update engine handle a legacy file such as
  `.seihou/gcp-kube-env.conf` (for example, a migration that moves it into
  `.seihou/gcp-kube-env/`). A purely structural rule ("every non-module-name entry is Seihou's")
  would make that legacy file permanently unmovable by Seihou.
  Date: 2026-11-11

- Decision: Enforce at two strengths. The *control-path* rule (reserved list plus `.git`) is
  enforced everywhere a module-supplied path is validated: module loading, generation,
  reconciliation, the update transaction, update recovery, migrations, and removal. The
  *own-directory* rule is enforced only where a module produces new output: plan-time
  compilation of steps (so both `run` and the desired side of `update`) and `seihou
  validate-module`. It is not enforced at module load.
  Rationale: Load-time refusal of the own-directory rule would make `gcp-kube-env` fail to load,
  which would break `seihou remove` and `seihou status` for existing applications of it. Every
  path `run` accepts is still accepted by `update`, which is the property IR-19 asks for.
  Date: 2026-11-11

- Decision: The bare `.seihou` directory is a permitted *directory* operand (create if
  missing) and a control path as a *file* target. Validators therefore distinguish directory
  operands (`CreateDirOp` values, reconciliation's directory set, the transaction's required and
  new directories) from file targets.
  Rationale: `parentDirs` in `seihou-core/src/Seihou/Engine/Plan.hs` emits
  `CreateDirOp ".seihou"` for any destination `.seihou/demo/x`, and reconciliation's
  `validateInputs` validates those directories. Creating an existing directory is a no-op, and the
  transaction records only directories it actually created, so rollback can never remove
  `.seihou`. Changing `parentDirs` instead would special-case one path in generic code.
  Date: 2026-11-11

- Decision: Update recovery's `resolveTarget` refuses the `.seihou` directory itself, not only
  control paths (the file-target predicate, not the directory predicate the plan first named).
  Migration and removal paths use the same strict predicate.
  Rationale: Recovery restores a directory backup by first deleting the target with
  `removePathForcibly`, and migrations can move or delete whole directories; a `.seihou` target
  there would erase every piece of Seihou state. Creating `.seihou` is harmless, deleting it is not.
  Date: 2026-11-11

- Decision: Command `workDir` values are not restricted by this plan.
  Rationale: A command runs arbitrary shell text and can already touch any file; restricting
  its working directory protects nothing and would break `docs-mori-bootstrap`-style commands
  that run from their state directory.
  Date: 2026-11-11

- Decision: Moving `gcp-kube-env`'s file into `.seihou/gcp-kube-env/` is out of scope; it
  belongs to `mori://shinzui/seihou-modules`. After this plan, `seihou run gcp-kube-env` fails
  with the own-directory message; its existing applications were already un-updatable. The
  user changelog names this, and Milestone 5 files a follow-up in that repository's improvement
  requests or friction log.
  Date: 2026-11-11


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

The repository is a Haskell project with three Cabal packages. `seihou-core/` holds the
domain logic and engine; `seihou-cli/` holds the `seihou` command-line program, split into a
library (`seihou-cli/src/`) and an executable (`seihou-cli/src-exe/`); `schema/` is a Git
submodule holding the Dhall schema modules are written in. Records use strict fields and are
read and updated through `generic-lens` labels such as `step ^. #dest`; see the repository's
`CLAUDE.md` for the full convention, which `nix flake check` enforces.

A *module* is a directory containing `module.dhall`, which declares variables, *steps* (each step
renders one source file from `files/` into a destination path, its `dest`), *commands* (shell
text run after files are written), optional *migrations* (instructions such as move-file or
delete-file run when upgrading between versions), and an optional *removal* section used by
`seihou remove`. Destinations may contain placeholders such as `{{project.name}}` that are filled
from variables. An *application* is one recorded use of a module or recipe in a project's
manifest. A *managed path* is a project file Seihou generated and records in
`.seihou/manifest.json`, together with the hash of its baseline.

The code paths this plan touches, in the order data flows through them:

`seihou-core/src/Seihou/Core/Path.hs` holds the shared path validators.
`validateProjectRelativePath` accepts a non-empty relative path with no `..` segment and returns
it stripped of surrounding whitespace. `validateCanonicalProjectPath` is a stricter variant used
by seed steps and checkout outputs; it rejects `.git` and `.seihou` components anywhere. This is
where the new classifier goes.

`seihou-core/src/Seihou/Core/Module.hs` loads and statically validates a module. Its rule 7,
`checkSafeDestinations`, validates each step's literal `dest`. `isValidModuleName` defines a
valid module name as `[a-z][a-z0-9-]*`. `validateModule` runs these rules whenever a module is
loaded, so a failure here stops every command that loads the module.

`seihou-core/src/Seihou/Engine/Validate.hs` builds the report printed by
`seihou validate-module` (handler in `seihou-cli/src-exe/Seihou/CLI/Validate.hs`). Its
`buildReport` lists `DiagCheck` entries such as `"Safe step destinations"`; adding an entry
there affects only that command.

`seihou-core/src/Seihou/Engine/Plan.hs` compiles one module's steps, after variables are
resolved, into `Operation` values (`WriteFileOp`, `PatchFileOp`, `CreateDirOp`, and others).
`compileStep` has the module's name in scope as `modName`. Each compiled destination passes
through `validateRenderedDestination`. Both `seihou run` and the desired side of
`seihou update` use this compilation.

`seihou-core/src/Seihou/Engine/Reconcile.hs` plans an update: `validateInputs` calls
`validateManagedPath` on every destination and directory, and `validateManagedPath` refuses any
path for which the local `targetsControlPath` holds (first segment `.seihou` or `.git`). This is
the error the IR quotes.

`seihou-core/src/Seihou/Engine/UpdateTransaction.hs` writes an accepted update to disk as a
crash-safe transaction under `.seihou/transactions/`. Its `validateTransactionPath` has a
duplicate `targetsControlPath`. It is also used to validate journal entries during recovery and
seed and checkout targets.

`seihou-cli/src/Seihou/CLI/Update/Recovery.hs` restores backups after an interrupted update.
`resolveTarget` refuses to restore into a path for which its own third copy of
`targetsControlPath` holds.

`seihou-core/src/Seihou/Engine/Migrate.hs` (`validateMigrationPath`) and
`seihou-core/src/Seihou/Engine/Remove.hs` (`validateRemovalPath`) validate migration and removal
paths with `validateProjectRelativePath` only.

Relevant tests: `seihou-core/test/Seihou/Engine/ReconcileSpec.hs` (its case
"rejects control paths before reading or planning" must keep passing),
`seihou-core/test/Seihou/Engine/UpdateTransactionSpec.hs`,
`seihou-core/test/Seihou/Core/ModuleSpec.hs`, `seihou-core/test/Seihou/Engine/PlanSpec.hs`,
`seihou-core/test/Seihou/Engine/ValidateSpec.hs`, `seihou-core/test/Seihou/Engine/MigrateSpec.hs`,
and `seihou-core/test/Seihou/Engine/RemoveSpec.hs`. Core test modules are registered in
`seihou-core/test/Main.hs` and in the `other-modules` of `test-suite seihou-core-test` in
`seihou-core/seihou-core.cabal`. End-to-end tests that run the built `seihou` executable live in
`seihou-cli/test/Seihou/CLI/*E2ESpec.hs`; `seihou-cli/test/Seihou/CLI/SeedRunE2ESpec.hs` exports
helpers (`prepare`, `invoke`, `success`, `readManifest`) that build a project with a
project-local module at `.seihou/modules/demo` and run the executable in it, and
`seihou-cli/test/Seihou/CLI/SeedUpdateE2ESpec.hs` shows the run-then-update pattern. CLI test
modules are registered in `seihou-cli/test/Main.hs` and `test-suite seihou-cli-test` in
`seihou-cli/seihou-cli.cabal`.

ADRs. The repository keeps ADRs as plain numbered files in `docs/adr/` (no OKF profile), so a
new record is `docs/adr/0025-<slug>.md` in the style of its neighbours. Relevant records:

- [ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md): the manifest is
  the only record of applied state. This is why module output must never reach it: a module that
  overwrote `.seihou/manifest.json` would corrupt the record every other command trusts.
- [ADR 0012](../adr/0012-an-additive-co-write-is-not-a-shared-path-conflict.md): shared-path
  rules in reconciliation; unchanged by this plan, but `validateOwner` runs right after the path
  check this plan changes, so module-state paths are subject to the same ownership checks as any
  other path.
- [ADR 0015](../adr/0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md):
  diagnostics name things as users do. New refusal messages must name the path and the allowed
  directory in words, not print a Haskell `show` value.
- [ADR 0017](../adr/0017-a-seed-file-is-created-once-and-belongs-to-the-project.md) and
  [ADR 0018](../adr/0018-checkout-outputs-are-observable-portable-declarations.md): seeds and
  checkout outputs reserve `.git` and `.seihou` components. This plan leaves that stricter rule
  as it is; a seed or checkout output still cannot live under `.seihou/`.

The work in this plan also needs the published module ecosystem only as evidence; no file
outside this repository is changed.


## Plan of Work

The work goes bottom-up: first one classifier, then the update path that consumes it, then the
generation path, then an end-to-end proof, then documentation. Each milestone leaves the test
suite green.

### Milestone 1: one path classifier

Add to `seihou-core/src/Seihou/Core/Path.hs` a classifier that every other site will use, and
delete nothing yet. It takes a path that has already passed `validateProjectRelativePath` and
splits it into segments on `/` and `\`, dropping empty segments (the same splitting the three
existing `pathSegments` helpers use). It returns one of three answers. A path whose first
segment, case-folded, is `.git` is a Git control path. The path `.seihou` alone (any case) is the
Seihou root directory, a separate answer, because it may be created as a directory but never
written as a file (see the Decision Log). A longer path whose first segment, case-folded, is
`.seihou` is a Seihou control path when its second segment, case-folded, is on the reserved list (`manifest.json`, `manifest.json.tmp`, `baselines`,
`transactions`, `transactions-quarantine`, `modules`, `context`, `config.dhall`, `trace.jsonl`)
or begins with `.`. Any other `.seihou` path is in a module state area and the classifier reports
the second segment as written (the area name) and whether the path continues below it. Every
other path is an ordinary project path. Also add two predicates, `isControlFileTarget` (true for
control paths and for the Seihou root) and `isControlDirectory` (true for control paths only),
and a function that
renders the reason for a control path in user words: "path targets Git control data" for `.git`,
and "path targets Seihou's own state at .seihou/<entry>" for the reserved list (naming the entry
as the path spells it).

Add `ownStateDirectoryViolation :: Text -> PathOperand -> FilePath -> Maybe Text` (module
name, whether the path is a file target or a directory operand, the path), used later by
generation. It returns `Nothing` for an ordinary path; for a module-state path whose first
segment is spelled exactly `.seihou`, whose area name is exactly the module name, and which
either continues below the area or is a directory operand; and for the Seihou root as a
directory operand. Otherwise it returns a message such as
"step destination .seihou/other/x is outside this module's state directory; a module may write
under .seihou/ only inside .seihou/demo/". For a control path it returns the control reason. So
`.seihou/demo` is accepted as a directory and refused as a file.

Export the reserved-name list too, so that the test can assert on it and the ADR can point at
one definition.

Create `seihou-core/test/Seihou/Core/PathSpec.hs` and register it in `seihou-core/test/Main.hs`
and `seihou-core/seihou-core.cabal`. Cover at least: `README.md` and `docs/.seihou-notes` are
ordinary; `.git`, `.git/config`, `.GIT/HEAD` are control; `.seihou/manifest.json`,
`.seihou/Manifest.JSON`, `.SEIHOU/manifest.json`, `.seihou/baselines/abc`,
`.seihou/transactions/x/journal.json`, `.seihou/modules/demo/module.dhall`, `.seihou/context`,
`.seihou/config.dhall`, `.seihou/trace.jsonl`, `.seihou/.migrate-signal`, and
`.seihou\\baselines\\abc` are control; `.seihou/docs-mori-bootstrap/bootstrap-docs.py` and
`.seihou/gcp-kube-env.conf` are module-state paths with areas `docs-mori-bootstrap` and
`gcp-kube-env.conf`; `.seihou` and `.SEIHOU` are the Seihou root. For
`ownStateDirectoryViolation "demo"` with file targets: `.seihou/demo/a/b.txt` and `src/x` pass;
`.seihou/demo`, `.seihou`, `.seihou/other/x`, `.Seihou/demo/x`, `.seihou/Demo/x`, and
`.seihou/manifest.json` are refused, the last with the control reason. With directory operands,
`.seihou` and `.seihou/demo` pass and `.seihou/other` and `.seihou/baselines` are refused.

Acceptance: `cabal test seihou-core-test --test-options='-p "/project path classification/"'` passes and lists the new
cases.

### Milestone 2: the update path accepts module state

Replace the local `targetsControlPath` in `seihou-core/src/Seihou/Engine/Reconcile.hs`,
`seihou-core/src/Seihou/Engine/UpdateTransaction.hs`, and
`seihou-cli/src/Seihou/CLI/Update/Recovery.hs` with the shared predicates, and delete the
three local copies and any `pathSegments` helper that becomes unused. File targets use
`isControlFileTarget`; directory operands use `isControlDirectory`. In `Reconcile.hs`,
`validateInputs` already validates the file map and the `CreateDirOp` set in two separate
`traverse_` calls, so give each its own validator. In `UpdateTransaction.hs`,
`validateTransactionPath` serves both kinds: `transactionPreflight` validates
`requiredDirectories` and journal validation checks `newDirectories` (directory operands),
while targets, seed creations, index links, and journal file entries are file targets; add a
directory variant and use it at the directory call sites. In `Recovery.hs`, `resolveTarget`
restores a directory backup, so it uses the directory predicate. In each validator, use the
shared reason text so the error now says which kind of control data a path names. Keep the existing error constructors (`InvalidReconciliationPath`,
`InvalidTransactionPath`) so callers and the CLI rendering of `reconciliation_failed` are
unchanged.

Extend `seihou-core/test/Seihou/Engine/ReconcileSpec.hs` next to
"rejects control paths before reading or planning": a `WriteFileOp` to
`.seihou/demo/helper.txt` owned by `appA` plans successfully, and with a recorded baseline and a
non-overlapping user edit it plans a clean merge exactly as the existing "file.txt" cases do;
`.seihou/baselines/x`, `.SEIHOU/manifest.json`, `.seihou` as a file, and `.git/config` are
refused with `InvalidReconciliationPath`, while the operations `CreateDirOp ".seihou"` and
`CreateDirOp ".seihou/demo"` that accompany the module-state write are accepted. Extend `seihou-core/test/Seihou/Engine/UpdateTransactionSpec.hs`
with a transaction that writes `.seihou/demo/helper.txt` and commits, leaving the file with the
new content, and a case that a transaction target of `.seihou/manifest.json` is refused. If the
Recovery module has no direct test, cover its change through the transaction test or note in
Surprises that it is covered only by the end-to-end test in Milestone 4.

Acceptance: `cabal test seihou-core-test` passes, including the new cases; the old control-path
case still passes.

### Milestone 3: generation enforces the same rule

In `seihou-core/src/Seihou/Core/Module.hs`, extend `checkSafeDestinations` so a literal step
`dest` that classifies as a control path is an error ("step destination path targets Seihou's
own state at .seihou/manifest.json"). Only the control rule applies at load; see the Decision
Log. A `dest` whose first two segments contain a placeholder cannot be judged here and is left to
plan time.

In `seihou-core/src/Seihou/Engine/Plan.hs`, make `validateRenderedDestination` take the module
name, and call `ownStateDirectoryViolation` on every rendered destination (as a file target)
and every `CreateDirOp` it emits (as a directory operand), so a step that renders to `.seihou/other/x` fails with the
own-directory message. Thread `modName` from `compileStep` into `compileCopyStep`,
`compileTemplateStep`, `compileDhallTextStep`, `compileStructuredStep`, and the patch path, and
into `writeFileOps`. Seeds keep their stricter `validateCanonicalProjectPath` check unchanged.

In `seihou-core/src/Seihou/Engine/Validate.hs`, add a `DiagCheck "Module state destinations"
DiagError` that applies `ownStateDirectoryViolation` with the module's own name to each literal
step `dest` (skipping destinations with placeholders in the first two segments), so
`seihou validate-module` on `gcp-kube-env` reports the problem before publication.

In `seihou-core/src/Seihou/Engine/Migrate.hs` (`validateMigrationPath`) and
`seihou-core/src/Seihou/Engine/Remove.hs` (`validateRemovalPath`), refuse control paths with the
shared reason, using each module's existing unsafe-path error (`MigrationUnsafePath`,
`RemovalUnsafePath`). Do not apply the own-directory rule there: a migration must be able to
move a legacy file such as `.seihou/gcp-kube-env.conf` into `.seihou/gcp-kube-env/`.

Tests: in `ModuleSpec`, a module with `dest = ".seihou/manifest.json"` fails to validate and one
with `dest = ".seihou/<its name>/x"` validates; in `PlanSpec`, a module named `demo` whose step
renders `.seihou/demo/x` compiles to `CreateDirOp ".seihou"`, `CreateDirOp ".seihou/demo"`, and
a `WriteFileOp ".seihou/demo/x"`, while a step rendering `.seihou/{{name}}/x` with
`name = other` fails with the own-directory message; in `ValidateSpec`, the new check reports
`.seihou/gcp-kube-env.conf` for a module named `gcp-kube-env`; in `MigrateSpec` and
`RemoveSpec`, a path of `.seihou/baselines/x` is refused.

Acceptance: `cabal test seihou-core-test` passes; `seihou validate-module` on a module with a
`.seihou/other/x` destination exits non-zero and prints the new check.

### Milestone 4: end-to-end proof through the executable

Create `seihou-cli/test/Seihou/CLI/ModuleStateE2ESpec.hs`, registered in
`seihou-cli/test/Main.hs` and `seihou-cli/seihou-cli.cabal`, using the helpers exported by
`seihou-cli/test/Seihou/CLI/SeedRunE2ESpec.hs`. Write a module named `demo` (version 1.0.0)
whose template step writes `.seihou/demo/helper.txt` with three lines, `top`, `middle v1`,
`bottom`. Run `seihou run demo`; edit the file on disk to change `top` to `top edited by user`;
rewrite the module as version 2.0.0 producing `middle v2`; run `seihou update demo --json`. Assert
exit success, `"outcome":"applied"`, and file content `top edited by user`, `middle v2`,
`bottom`. Run `seihou update demo --json` again and assert `"alreadyUpToDate":true`. In
separate cases, assert that `seihou run demo` with a step `dest` of `.seihou/manifest.json`
exits non-zero, mentions `.seihou/manifest.json`, and leaves the manifest byte-identical to its
state before the command; and that a step `dest` of `.seihou/other/x` exits non-zero with the
own-directory message naming `.seihou/demo/`.

Acceptance: `cabal test seihou-cli-test --test-options='-p "/module state directory end-to-end/"'` passes. Before
Milestone 2 the update case fails with `reconciliation_failed` and the IR's message; recording
that failing output once in Surprises & Discoveries is useful evidence.

### Milestone 5: documentation, ADR, and the improvement request

Document the rule for module authors in `docs/user/module-authoring.md`: a module may keep
helper scripts and configuration in `.seihou/<module-name>/`, those files are managed and merged
on update like any other, nothing else under `.seihou/` may be written, and the reserved names.
Mention in `docs/cli/update.md` that managed files in a module's state directory are reconciled,
and in `docs/cli/validate-module.md` the new check. Add entries under `## [Unreleased]` in
`docs/user/CHANGELOG.md` (user-facing: updates now work for modules that keep files in
`.seihou/<module>/`; `run` now refuses module output that targets Seihou's own state or another
directory under `.seihou/`, naming `gcp-kube-env` as a known affected module) and in the root
`CHANGELOG.md` (engineering detail).

Write `docs/adr/0025-a-module-owns-only-its-own-directory-under-seihou.md` in the format of the
existing records, stating the own-directory rule, the reserved list and where it is defined, the
rule for future Seihou state (add it to the list, use a name that is not a valid module name),
and the rejected alternative (IR-19 option 2).

Update [IR-19](../improvement-requests/update-module-files-that-seihou-run-wrote-under-dot-seihou.md)
to `status: completed` with `completedAt` and a `resolution`, and add a `log.md` entry, following
the IR-14 pattern; this plan's creation already set it to `accepted` with `targetPlan`. File the
`gcp-kube-env` follow-up against `mori://shinzui/seihou-modules` as the user directs (a friction
entry or an improvement request in that repository), and cite it in Outcomes & Retrospective.

Acceptance: the full suites and `nix flake check` pass (see Validation).


## Concrete Steps

All commands run from the repository root,
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`, inside the development shell
(`nix develop`, or `direnv` if it is set up).

Build and run the focused tests while developing:

```bash
cabal build all
cabal test seihou-core-test --test-options='-p "/project path classification/"'
cabal test seihou-core-test --test-options='-p "/Seihou.Engine.Reconcile/"'
cabal test seihou-core-test --test-options='-p "/Seihou.Engine.UpdateTransaction/"'
cabal test seihou-cli-test --test-options='-p "/module state directory end-to-end/"'
```

Confirm no stray copy of the old check remains after Milestone 2:

```bash
grep -rn 'firstSegment == ".seihou"\|first == ".seihou"' seihou-core/src seihou-cli/src seihou-cli/src-exe
```

Expected output is empty.

Confirm the reserved list still covers every location Seihou constructs under `.seihou/`
(rerun this when a new path appears; anything printed that is not on the reserved list is a
defect in the list):

```bash
grep -rhoE '"\.seihou" </> "[^"]+"' seihou-core/src seihou-cli/src seihou-cli/src-exe | sort -u
```

Expected output names only reserved entries:

```text
".seihou" </> ".migrate-signal"
".seihou" </> "baselines"
".seihou" </> "config.dhall"
".seihou" </> "context"
".seihou" </> "manifest.json"
".seihou" </> "modules"
".seihou" </> "trace.jsonl"
".seihou" </> "transactions"
".seihou" </> "transactions-quarantine"
```

Run the full suites and repository checks before the final commit:

```bash
cabal test all
nix flake check
```

Commit at each milestone boundary with Conventional Commit messages and both trailers, for
example:

```text
feat(update): reconcile managed files in a module's .seihou directory

Replace the three copies of targetsControlPath with the shared
classifier from Seihou.Core.Path. Paths under .seihou/<module>/ now
reconcile; the manifest, baselines, transactions and .git stay refused.

ExecPlan: docs/plans/120-let-seihou-update-reconcile-module-owned-files-under-seihou.md
Intention: intention_01m75dxfcnektbt081rhk1s71v
```


## Validation and Acceptance

The change is accepted when all of the following hold.

A module that writes a file in its own state directory can be applied and later updated with the
normal merge. The Milestone 4 end-to-end test demonstrates it: after `seihou run demo`, a user
edit to `.seihou/demo/helper.txt`, and a 2.0.0 release that changes a different line,
`seihou update demo --json` exits 0 with `"outcome":"applied"` and the file holds both changes;
a repeated update reports `"alreadyUpToDate":true`. Before this plan the same update fails with
`path targets Seihou or Git control data`.

Seihou's own state stays unreachable from module output through `run` and through `update`.
`seihou run` of a module whose step targets `.seihou/manifest.json` exits non-zero, names the
path, and leaves the manifest unchanged; reconciliation and the update transaction refuse
`.seihou/manifest.json`, `.seihou/baselines/…`, `.seihou/transactions/…`, the case variant
`.SEIHOU/manifest.json`, and `.git/…` (unit tests in `ReconcileSpec`, `UpdateTransactionSpec`,
`PathSpec`).

A module that writes elsewhere under `.seihou/` is refused when generated, with a message that
names the allowed directory: `seihou run demo` with `.seihou/other/x` exits non-zero mentioning
`.seihou/demo/`, and `seihou validate-module` reports the "Module state destinations" check.

The suites pass: `cabal test all` reports no failures, and `nix flake check` passes (it
includes the record-convention and CLI module-placement checks).

Optional real-world check, if a `fumadocs-site` application such as a checkout of
`mori://shinzui/kotei-docs` is available locally: copy it to a scratch directory and run the
development binary's `seihou update fumadocs --dry-run` there. It should no longer print
`reconciliation_failed for .seihou/docs-mori-bootstrap/bootstrap-docs.py`. Use a copy, not the
checkout itself, and do not run without `--dry-run`. IR-19's third acceptance criterion applies
only to option 2 and does not apply to this plan.


## Idempotence and Recovery

Every step is a source edit plus tests; rerunning a build or test changes nothing outside
`dist-newstyle/`. The end-to-end tests run in temporary directories created by
`withSystemTempDirectory` and leave nothing behind. No project data or manifest schema changes:
the manifest format is untouched, so no schema version bump is needed and existing manifests
work unchanged (ADR 0014 requires a bump only for semantic manifest changes). If a milestone
must be abandoned midway, `git restore` the touched files; Milestone 1 is purely additive and can
stay in place on its own.

The one behavior change that can surprise a user is that `seihou run` now refuses module output
that it previously wrote: anything targeting Seihou's reserved entries, and any `.seihou/`
destination outside the module's own directory (known case: `gcp-kube-env`). The changelog entry
from Milestone 5 must say so.


## Interfaces and Dependencies

No new library dependency. The new public interface lives in `seihou-core/src/Seihou/Core/Path.hs`
and is consumed by `Seihou.Core.Module`, `Seihou.Engine.Plan`, `Seihou.Engine.Validate`,
`Seihou.Engine.Reconcile`, `Seihou.Engine.UpdateTransaction`, `Seihou.Engine.Migrate`,
`Seihou.Engine.Remove`, and `Seihou.CLI.Update.Recovery`. A shape that satisfies the plan:

```haskell
-- | What a validated project-relative path names, for module-output rules.
data ProjectPathClass
  = -- | An ordinary project path, outside .seihou and .git.
    OrdinaryProjectPath
  | -- | The .seihou directory itself: creatable as a directory, never a file.
    SeihouRootDirectory
  | -- | Under .seihou/<area>/, where <area> is not Seihou's own. The Bool says
    -- whether the path continues below the area directory.
    ModuleStatePath !Text !Bool
  | -- | Seihou's own state or Git's; the Text is the user-facing reason.
    ControlPath !Text
  deriving stock (Eq, Show, Generic)

-- | Whether a path names a file to write or a directory to create.
data PathOperand = FileTarget | DirectoryOperand
  deriving stock (Eq, Show, Generic)

classifyProjectPath :: FilePath -> ProjectPathClass
isControlFileTarget :: FilePath -> Bool   -- ControlPath or SeihouRootDirectory
isControlDirectory :: FilePath -> Bool    -- ControlPath only
controlPathReason :: FilePath -> Maybe Text
reservedSeihouEntries :: [Text]   -- case-folded names; plus any name starting with "."

-- | Nothing when a module named by the first argument may write or create the path.
ownStateDirectoryViolation :: Text -> PathOperand -> FilePath -> Maybe Text
```

`ProjectPathClass` is a sum type, not a record, so the strict-field and label conventions apply
only to its fields' strictness. `isValidModuleName` stays in `Seihou.Core.Module`; `Seihou.Core.Path`
must not import `Seihou.Core.Module` (that would create an import cycle, since `Module` imports
`Path`), so if the classifier needs the module-name syntax, move `isValidModuleName` into
`Seihou.Core.Path` and re-export it from `Seihou.Core.Module`, keeping existing imports working.
