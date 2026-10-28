---
id: 116
slug: record-command-receipts-before-module-commands-can-commit-the-manifest
title: "Record command receipts before module commands can commit the manifest"
kind: exec-plan
created_at: 2026-10-28T16:30:24Z
intention: "intention_01m61nj2meeczthnm1atsrmc15"
provenance:
  created_by:
    model: "claude-fable-5-1"
    harness: "claude-code"
    at: 2026-10-28T16:30:24Z
  revisions:
    - model: "claude-opus-5-5"
      harness: "claude-code"
      at: 2026-10-28T16:55:38Z
      mode: "implement"
      note: "Milestones implemented"
---

# Record command receipts before module commands can commit the manifest

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).


## Purpose / Big Picture

Seihou records a *command receipt* for every shell command a module declares, so that a later
`seihou update` can skip commands that already completed unchanged. Today both `seihou run` and
`seihou update` write those receipts into `.seihou/manifest.json` only after the whole command
phase has finished. A module whose own commands snapshot the project therefore commits a
manifest that has no receipts, and seihou then rewrites the manifest with the receipts a moment
later. The canonical case is the `git-init` module from `mori://shinzui/seihou-modules`: its
commands are `git init -b master`, then `git add -A && git commit -m 'Initial commit'`, then
`gh repo create ... --push`. Right after `seihou run git-init` the working tree shows
` M .seihou/manifest.json`, and the manifest that was committed and pushed says no command has
ever run. A collaborator who clones that repository, or the author after `git checkout .`,
has a manifest whose `git-init` application has no receipts, so a later `seihou update` treats
`git init`, the initial commit and `gh repo create` as never-run commands. `gh repo create` then
fails because the repository already exists. Every recipe that ends with `git-init`
(`github-repo`, `haskell-library-repo`, `haskell-cli-app-repo`) has the same leftover change.

After this change, the manifest a module command can commit already carries the receipts the
run will produce. In a fresh directory, `seihou run git-init` leaves `git status --porcelain`
empty, `git show HEAD:.seihou/manifest.json` contains the application's `commandReceipts`, and
`seihou update` in a fresh clone of that repository prints `Already up to date.` A failed or
interrupted command phase leaves the manifest exactly where it is left today: without the
receipts that phase would have minted. `seihou update` gains the same property through its
existing transaction, so an update whose newly added command commits the project also leaves a
clean tree, and an update whose command fails restores the pre-update manifest byte for byte.

This plan fulfils improvement request IR-9,
`docs/improvement-requests/record-command-receipts-before-commands-can-commit-them.md`, by
implementing the option that request calls "A": write the expected receipts first and withdraw
them on failure.


## Progress

- [x] M1 (2026-10-28): `Seihou.CLI.CommandExecution` exposes the receipt list a fully successful command phase will return, and a unit test proves that `executeCommandPlan` on an all-success plan returns exactly that list. Evidence: `-p "Seihou.CLI.CommandExecution"` passes 17 tests, including the three `expectedCommandReceipts` cases and four `withReceiptWithdrawal` cases (success, `Left`, `UserInterrupt`, failing withdrawal).
- [x] M2 (2026-10-28): `seihou run` writes the expected receipts before the command phase, withdraws them when the phase fails or is interrupted, and skips the redundant final write. An end-to-end test shows a module whose last command commits leaves a clean tree, a committed manifest with that application's receipts, and a fresh clone whose `seihou update demo --dry-run` prints `Already up to date.`; a module whose last command fails leaves the manifest as today's failed run does and prints the withdrawal notice. Evidence: `-p "command receipts end-to-end"` passes 3 tests; against the pre-change `Run.hs` the commit and failure cases fail (` M .seihou/manifest.json`, no withdrawal notice). Full `seihou-cli-test`: 822 passed.
- [x] M3 (2026-10-28): The update transaction journal (version 5) snapshots `.seihou/manifest.json` when a transaction begins and restores it byte for byte on rollback and on crash recovery, with core tests for both paths and for decoding older journals. Evidence: five new "manifest snapshot" cases (version-5 journal with copy, rollback, crash recovery, committed path, version-4 journal) and the unchanged path-validation case pass; `-p "UpdateTransaction"` 34 passed; full `seihou-core-test` passes.
- [x] M4 (2026-10-28): `seihou update` writes the final manifest before the command phase and sets the recovery commit marker only after the phase succeeds. An end-to-end test shows an update whose new command commits leaves a clean tree with the receipt committed, and an update whose command fails restores the pre-update manifest and files with no transaction left behind. Meeting the clean-tree criterion also required setting aside unreferenced baselines before the phase and a self-ignoring `.seihou/transactions/.gitignore` (see Surprises & Discoveries and Decision Log). Evidence: `-p "command receipts end-to-end"` 5 passed; four new "set-aside baselines" core cases pass; full `seihou-core-test` and `seihou-cli-test` (824) pass.
- [ ] M5: `docs/user/module-authoring.md`, `docs/dev/architecture/overview.md`, `docs/user/CHANGELOG.md` and a new ADR describe the new receipt timing; IR-9 is marked completed with evidence; `cabal test all`, `nix/check-record-conventions.sh` and `nix/check-cli-module-placement.sh` pass.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence. Friction with the tools, documents, and processes
used to do the work belongs in the friction log (see FRICTION.md); cite an entry's FRIC-N
handle here only when it also changed the plan.

- (2026-10-28, planning) `okf validate docs/improvement-requests --strict --profile
  docs/improvement-requests/profile.dhall --profile-enforce --log-enforce` already exits 1 at
  commit `02056b3`, before any change from this plan: ten requests lack the profile-recommended
  `reviews` field and IR-10 lacks `resolution`. Without `--profile-enforce` the bundle validates
  (`OK: 13 concepts`). Milestone 5 therefore requires that the enforced run report no deviation
  for IR-9 itself, not that the whole bundle pass; the other deviations are out of scope.

- (2026-10-28, M2) The `--no-commands --force` case cannot assert unchanged manifest bytes, as
  the plan proposed: every run restamps `genAt` and the application's `appliedAt`. The test
  asserts instead that the `demo` application's receipts are identical before and after.
  The fixture also writes a `.gitignore` for the in-project `home/`, `config/` and `cache/`
  directories that `SeedRunE2ESpec.invoke` points the environment at, so `git add -A` in the
  committing command and the `git status --porcelain` assertions see only project files.

- (2026-10-28, M4) The first run of the update commit case left the tree dirty with
  ` D .seihou/transactions/update-*/...` (journal, `backups/`, `service-backups/`,
  `service-journal.json`) and ` D .seihou/baselines/<pre-update blob>`: the committing command
  snapshotted the in-flight transaction and the baseline that `finishCommitted` prunes after
  commit. Neither was anticipated by the plan; both are fixed in this milestone (Decision Log).
  This also means that before this plan any update command that committed the project committed
  the transaction scaffolding too.

- (2026-10-28, M4) A rolled-back update leaves the new baseline blobs that `applyReconciliation`
  wrote as untracked files under `.seihou/baselines/`. This predates the plan (the journal never
  recorded them), is harmless because blobs are content-addressed and pruned by the next
  successful run or update, and is out of scope; the failure case asserts the manifest, the
  managed file and the absence of a transaction directory, not an empty `git status`.


## Decision Log

- Decision: Before update's command phase, move every baseline blob the published manifest no
  longer references from `.seihou/baselines/` into the transaction directory
  (`set-aside-baselines/`), journaling the names in the version-5 journal field
  `setAsideBaselines`. Rollback and crash recovery move them back; completion deletes them.
  Rationale: Milestone 4's clean-tree criterion failed because `finishCommitted` prunes stale
  baselines only after the commit marker, so a committing command captured the pre-update blob
  and the prune then showed as ` D .seihou/baselines/<old>`. Pruning before the marker would lose
  blobs the restored manifest references if the phase failed; setting them aside is the same
  operation made reversible. `seihou run` already prunes before its command phase and needs
  nothing.
  Date: 2026-10-28.

- Decision: `beginSeedUpdateTransaction` writes a self-ignoring `.gitignore` (`*`) in
  `.seihou/transactions/` when absent.
  Rationale: A committing command run during update otherwise commits the transaction in flight
  (journal, backups, service backups), and completion then deletes it from the working tree. The
  transaction directory is per-checkout recovery scaffolding (ADR 0004), never applied state.
  The file persists after the transaction completes and is invisible to git; recovery and
  `pendingUpdateRecovery` already skip non-directory entries.
  Date: 2026-10-28.

- Decision: An exception (such as Ctrl-C) propagating out of update's command phase rolls the
  transaction back on the way out (`abandonUpdate`), best-effort, instead of waiting for the next
  `seihou update` to recover it.
  Rationale: The manifest is now published before the phase, so leaving an interrupted
  transaction in place would leave receipts for commands that did not run visible to every
  other command until the next update. Anything the best-effort rollback cannot finish is still
  recovered at the next update's entry, as before.
  Date: 2026-10-28.

- Decision: Publish the receipts a command phase will produce before the phase runs (IR-9
  option A) instead of adding a schema-level command phase that runs after the receipt write
  (IR-9 option B).
  Rationale: Every receipt's `completedAt` is the run's single `now`, and its fingerprint
  depends only on the rendered command text, the normalized work directory, the owning module
  instance and the occurrence, so the receipt set a successful phase will produce is known byte
  for byte before the first command starts. Option A needs no `seihou-schema` change, no new
  schema hash for every module, and no `git-init` release; every recipe that ends in `git-init`
  is fixed by upgrading seihou alone. Option B could still not record the final-phase commands'
  own receipts in the snapshot they commit, so it would need option A in miniature anyway.
  This revises the EP-67 decision "record receipts only after each command returns success"
  (`docs/plans/67-track-generated-commands-and-skip-unchanged-executions.md`).
  Date: 2026-10-28.

- Decision: When the phase fails or is interrupted, withdraw every receipt the phase would have
  minted, so the on-disk manifest ends exactly where today's failed run leaves it. Do not keep
  receipts for the commands that succeeded before the failure.
  Rationale: `seihou update` already rolls back its whole transaction on a command failure, so
  files and receipts stay one accepted state; giving `seihou run` a different partial rule would
  make the two commands disagree about what a receipt means. Ordinary `seihou run` re-executes
  every command on retry (`RunAllCommands`), so a kept prefix would change nothing for it.
  Keeping a successful prefix remains available as a separate future decision.
  Date: 2026-10-28.

- Decision: Accept that a committing command followed by a failing command leaves a committed
  snapshot that over-claims, and mitigate it with an explicit failure message and documentation
  rather than any rewriting of git history.
  Rationale: Any design that makes the committed manifest complete on success must write
  receipts for commands that have not yet run, and seihou never amends or rewrites commits. The
  withdrawal write corrects the working tree, so the over-claim is visible as a `git status`
  change rather than hidden; `seihou run <module>` re-runs and re-records every command, and
  `seihou update --run-all-commands` ignores receipts entirely. A hard kill (SIGKILL, power
  loss) between the early write and the withdrawal has the same residual and the same remedies.
  Date: 2026-10-28.

- Decision: Snapshot `.seihou/manifest.json` inside the update transaction journal (journal
  version 5) rather than adding it to the transaction's target set or restoring it from memory
  in the abort path.
  Rationale: `validateTransactionPath` in `seihou-core/src/Seihou/Engine/UpdateTransaction.hs`
  deliberately rejects `.seihou/` and `.git/` targets, and a test in
  `seihou-core/test/Seihou/Engine/UpdateTransactionSpec.hs` pins that; the guard should stay.
  An in-memory restore covers a command failure but not a crash: after a hard kill the next
  `seihou update` would roll back the files while leaving a manifest that describes the
  rolled-back state. A journaled byte copy lets both `rollbackUpdateTransaction` and
  `recoverIncompleteTransactions` restore the manifest.
  Date: 2026-10-28.

- Decision: In `seihou update`, set the recovery commit marker (the journal's
  `expectedManifest`) after the command phase succeeds, even though the manifest file itself is
  written before the phase.
  Rationale: Recovery treats a transaction as committed when the on-disk manifest decodes equal
  to the marker. If the marker were set before the phase, a crash during commands would be
  recovered as a commit and the receipts for never-run commands would stand. With the marker set
  afterwards, that crash rolls back files and manifest together, which is what happens today
  when a command fails.
  Date: 2026-10-28.

- Decision: No manifest schema version advance.
  Rationale: ADR 0014 requires an advance for every semantic change to the serialized manifest.
  This plan changes when the same receipts are written, not their shape, their fields' meaning,
  or the interpretation of an absent receipt. The committed manifest of every successful run
  reads exactly as a manifest written by the current release does.
  Date: 2026-10-28.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Cite the friction entries recorded under
this plan by handle with their triage outcome. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

(To be filled during and after implementation.)


## Context and Orientation

The repository is a cabal project with three packages: `seihou-core` (the engine and types),
`seihou-cli` (a library at `seihou-cli/src/` plus the `seihou` executable at
`seihou-cli/src-exe/`) and `seihou-okf-extension`. New code goes in `seihou-cli/src/` unless
it needs one of the executable-only dependencies named in `CLAUDE.md`; `Run.hs` is
executable-only because it imports `Seihou.CLI.Commands`. Records use strict fields, explicit
deriving strategies and `generic-lens` labels (`record ^. #field`, `record & #field .~ value`);
never record update syntax. Both conventions are enforced by `nix/check-record-conventions.sh`
and `nix/check-cli-module-placement.sh`. Haskell and cabal files are formatted by treefmt
(`fourmolu`, `cabal-gild`); run `nix fmt` from the repository root before committing.

### Terms used in this plan

The **manifest** is `.seihou/manifest.json`, the checked-in, machine-independent record of
everything seihou has applied to a project. It is the only such record; there is no lockfile
(ADR 0004, `docs/adr/0004-the-manifest-is-the-only-record-of-applied-state.md`). It is written
atomically by `Seihou.Effect.ManifestStoreInterp.writeManifest`
(`seihou-core/src/Seihou/Effect/ManifestStoreInterp.hs`), which writes
`.seihou/manifest.json.tmp` and renames it over the final path.

An **application** is one top-level module or recipe applied to the project, represented by
`AppliedComposition` in `seihou-core/src/Seihou/Core/Types.hs` and identified by an
`ApplicationId`. Among its fields is `commandReceipts :: Map CommandFingerprint CommandReceipt`.

A **command receipt** (`CommandReceipt`, same file) is evidence that one rendered command
completed: its `fingerprint`, `moduleName`, `command` text, optional `workDir`, and
`completedAt`. A **command fingerprint** is computed by
`Seihou.Core.CommandFingerprint.fingerprintCommand`
(`seihou-core/src/Seihou/Core/CommandFingerprint.hs`) from the rendered command text, the
normalized work directory, the qualified module instance and the occurrence among identical
commands. It does not depend on time, module version or the absolute project path.

A **command plan** (`CommandPlan`) is built by `planCommands` in
`seihou-cli/src/Seihou/CLI/CommandExecution.hs` from a **command policy**, the application's
prior receipts and the composed operations. Each `PlannedCommand` carries its operation,
fingerprint and a disposition: `CommandWillRun`, `CommandSkippedUnchanged` or
`CommandSkippedDisabled`. The policies are `RunAllCommands` (what ordinary `seihou run` uses),
`RunChangedCommands` (the `seihou update` default, which skips commands whose fingerprint has a
prior receipt) and `DisableCommands` (`--no-commands`). `executeCommandPlan now plan` and
`executeCommandPlanWithOutput now onSuccess plan` run the `CommandWillRun` commands in order
with `sh -c` through the `Process` effect, stop at the first failure, and return
`Right [CommandReceipt]` only when the whole phase succeeded; every receipt is stamped with the
`now` the caller passed in, not with the moment each command finished. `finalizeCommandReceipts
plan completed prior` produces the accepted receipt map for the plan's current declaration set:
fresh successes replace old receipts, skipped or disabled commands retain their matching prior
receipt, removed commands are dropped, and a `CommandWillRun` command with no completed receipt
is dropped. For `RunAllCommands`, `finalizeCommandReceipts plan [] prior` is therefore the empty
map.

**Checkout commands** are `RunCommandOp` operations with `lifecycle = CheckoutCommandLifecycle`
(`isCheckoutCommand`). They never receive receipts and are re-run by `seihou sync`. Nothing in
this plan changes them.

The **update transaction** (`seihou-core/src/Seihou/Engine/UpdateTransaction.hs`) is how
`seihou update` makes its file changes recoverable. `beginSeedUpdateTransaction root targets
seedPaths` validates every target path with `validateTransactionPath`, which rejects any path
under `.seihou/` or `.git/`, copies each existing target's bytes into
`.seihou/transactions/update-XXXX/backups/N.txt`, and writes `journal.json` holding a
`JournalMetadata` record: `journalVersion` (2 without seed creations, 4 with them), `createdAt`,
`entries`, `newDirectories`, `indexLinks`, `seedCreations` and `expectedManifest = Nothing`. The
JSON decoder accepts versions 1 through 4. `applyReconciliation` applies the planned file
changes and sets `expectedManifest` to its files-only candidate; orchestrators replace it with
the complete final manifest through `setUpdateTransactionExpectedManifest`. The
`expectedManifest` is the **recovery commit marker**: `recoverIncompleteTransactions`, which
`seihou update` runs at every entry through `recoverAtEntry` in
`seihou-cli/src/Seihou/CLI/Update.hs`, decodes the on-disk manifest and treats the transaction
as committed when it equals the marker (`manifestMatches` compares decoded values, not bytes),
cleaning the transaction directory up; otherwise it calls `rollbackUpdateTransaction`, which
restores every journaled entry and removes directories the transaction created. Nothing in the
journal today refers to the manifest file itself, because the manifest is always written after
the marker. A parallel **service journal** in `seihou-cli/src/Seihou/CLI/Update/Recovery.hs`
backs up install-cache directories that `publishCandidates` will overwrite; `recoverServiceBackups`
uses its own `expectedManifest`, set by `setServiceExpectedManifest`, in the same way.

### The current `seihou run` flow

`handleRun` in `seihou-cli/src-exe/Seihou/CLI/Run.hs` does, in order (line numbers are
approximate for the commit this plan was written against, `02056b3`):

Around lines 337 to 352 it reads `priorCommandReceipts` for the current application from the
manifest, picks `commandPolicy` (`DisableCommands` under `--no-commands`, otherwise
`RunAllCommands`), builds `commandPlan = planCommands commandPolicy priorCommandReceipts ops`,
and computes `candidateCommandReceipts = finalizeCommandReceipts commandPlan []
priorCommandReceipts`, which is empty for an ordinary run.

The generation block around lines 470 to 560 executes file operations, records baselines, builds
`appliedComposition` with `#commandReceipts .~ candidateCommandReceipts`, builds `newManifest`,
applies seeds and checkout links, and writes `seededManifest`. This is the **first manifest
write**, and it carries no receipt for any command about to run.

Around lines 597 to 619 it runs `executeCommandPlanWithOutput now (print stdout) commandPlan`.
On `Left`, it prints the captured output, logs `Command failed (exit N): <command>`, prints a
retry hint, and exits with failure, leaving the first write on disk.

Around lines 621 to 638 it computes `finalCommandReceipts = finalizeCommandReceipts commandPlan
completedReceipts priorCommandReceipts`, sets them on the current application with the local
helper `setApplicationCommandReceipts` (around line 765), and writes `receiptManifest`. This is
the **second manifest write**, and it is the one that dirties the tree after `git-init`'s commit.

Around line 641 the `--commit` / `--commit-message` block stages generated files and the manifest
and commits them; it already runs after the receipt write and stays where it is.

`--dry-run` and `--diff` return before the generation block and write nothing.

### The current `seihou update` flow

`applyAcceptedPlan` in `seihou-cli/src/Seihou/CLI/Update.hs` (around lines 476 to 544) begins
the transaction with `plan ^. #snapshot . #transactionTargets` (computed around line 205 from
reconciliation mutation paths, migration targets, checkout adoptions and checkout link
destinations; the manifest is never among them), prepares service backups, adopts tracked
links, runs migrations, applies reconciliation (`applyReconciliation`, which writes files and
sets the files-only marker), applies checkout links, then runs `executeCommandPlan now (plan ^.
#commandPlan)`. On `Left` it calls `abortUpdate transaction (UpdateCommandFailed err
[ArbitraryCommandSideEffectsMayRemain])`, which restores service backups and rolls the
transaction back. On `Right completedReceipts` it builds `finalManifest = buildFinalManifest now
plan filesManifest completedReceipts` (around line 1154; per application it re-plans the
commands and calls `finalizeCommandReceipts` with the completed list), calls `setCommitMarkers`
(both the core and the service marker), `publishCandidates`, `writeManifestIO`, and finally
`finishCommitted`, which cleans up the transaction and prunes baselines. `seihou update
--commit` commits after `applyProjectUpdate` returns and is unaffected.

### Tests and fixtures to build on

`seihou-cli/test/Seihou/CLI/CommandExecutionSpec.hs` tests the command library purely with
`runProcessPure` mocks (`successMock`, `ProcessMock`), `commandOp`, `receiptFor` and
`fingerprintOf` helpers. `seihou-cli/test/Seihou/CLI/SeedRunE2ESpec.hs` exports `prepare`,
`invoke`, `success` and `readManifest`: `prepare root` builds a project-local module at
`<root>/.seihou/modules/demo` with the pinned schema copied in by
`Seihou.CLI.CheckoutSyncE2ESpec.copyPinnedSchema` from the repository's `schema/` directory,
and `invoke binary root args` runs the real executable with `HOME`, `XDG_CONFIG_HOME` and
`XDG_CACHE_HOME` pointed inside `root`. The pinned schema declares commands as
`S.Command::{action = S.Command.Action.Apply "<shell text>"}` (see `schema/Command.dhall` and
the examples in `CheckoutSyncE2ESpec.hs`). `seihou-cli/test/Seihou/CLI/SeedUpdateE2ESpec.hs`
shows that `seihou update demo` works against such a project-local module and how a fixture is
turned into a git repository (`git init`, `git config user.name`, `git config user.email`,
`git add`, `git commit`). `seihou-cli/test/Seihou/CLI/UpdateSpec.hs` exports
`prepareUpdateFixture root`, which installs module `demo` 1.0.0 under `<root>/xdg`, publishes
2.0.0 in a bare-path git remote at `<root>/remote` using `moduleDhallWithTemplate` (a legacy
`{ run, workDir, when }` command record, still readable), and writes a project manifest that
already holds a receipt for the command `printf should-not-run >> command.log`;
`seihou-cli/test/Seihou/CLI/UpdateE2ESpec.hs` drives it through the binary.
`seihou-core/test/Seihou/Engine/UpdateTransactionSpec.hs` has the crash-recovery tests
("rolls back ...", "keeps committed files when the durable manifest matches the journal", "uses
an orchestrator's complete final manifest as the recovery commit marker") and the path
validation test that pins the `.seihou/manifest.json` rejection.

The executable the end-to-end tests shell out to is located by
`Seihou.CLI.SeihouBinary.seihouBinary` (`seihou-cli/test/Seihou/CLI/SeihouBinary.hs`); it must
be built first with `cabal build seihou-cli:seihou`. New test modules are registered in
`seihou-cli/test/Main.hs` and in the `other-modules` list of `test-suite seihou-cli-test` in
`seihou-cli/seihou-cli.cabal`. The suite is tasty with hspec specs, so
`--test-options='-p "<pattern>"'` selects tests by name.

### Documentation this plan touches

`docs/user/module-authoring.md`, section "Commands" (around lines 322 to 360), currently says
"Run executes both lifecycles. Update uses success receipts for application commands". The
"Stateful Manifest for Incrementality" section of `docs/dev/architecture/overview.md` (around
line 735) lists what the manifest records, and the checkout paragraph (around line 776) notes
"Update's version-2 recovery journal snapshots literal link targets and retains a version-1
decoder". `docs/user/CHANGELOG.md` has an `## [Unreleased]` section. `docs/adr/` is a plain
directory of `NNNN-slug.md` files with a `# ADR NNNN — Title` heading, `Status` and `Date`
bullets, and Context, Decision, Consequences and References sections; it has no OKF profile, so
no frontmatter is added (see `docs/adr/0022-recipe-descriptor-validation-is-independent-of-composition.md`
for the shape). The next number is 0023.

IR-9 lives in the OKF bundle `docs/improvement-requests/`, governed by the
`coordination.improvementRequests` profile pinned in `docs/improvement-requests/profile.dhall`.
Its frontmatter carries `status`, `targetPlan`, and on completion `completedAt` and
`resolution`; `docs/improvement-requests/validate-a-recipe-without-running-its-composition.md`
is a completed example. Every change to the bundle is logged with `okf log add` and validated
with `okf validate ... --strict --profile ... --profile-enforce --log-enforce`. The request was
set to `accepted` with `targetPlan` pointing at this plan when the plan was created.

### Relevant ADRs

- `docs/adr/0004-the-manifest-is-the-only-record-of-applied-state.md`: anything that must be
  true for every developer belongs in the manifest; there is no side file. The transaction
  journal under `.seihou/transactions/` is per-checkout recovery scaffolding, not a record of
  applied state, so snapshotting the manifest there does not conflict with this ADR.
- `docs/adr/0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md`: a receipt that looks
  right but was not earned silently suppresses the run that should happen. This is exactly the
  hazard the withdrawal write and the "marker after commands" ordering guard against, and the
  reason the over-claim residual is documented rather than ignored.
- `docs/adr/0011-a-migration-receipt-asserts-a-claim-about-the-project.md`: a receipt is a
  claim that something need not run again, not proof of how it came to be. Writing command
  receipts before the phase is the same stance: the on-disk manifest during the phase asserts
  the claim the phase is about to make good on, and a failed phase withdraws it.
- `docs/adr/0014-every-semantic-manifest-change-advances-the-schema-version.md`: the reason the
  Decision Log records explicitly that this plan does not change the manifest schema.
- `docs/adr/0018-checkout-outputs-are-observable-portable-declarations.md`: why checkout
  commands are excluded from receipts and from this plan.

No ADR covers command-receipt timing; the decision being revised is in the Decision Log of
`docs/plans/67-track-generated-commands-and-skip-unchanged-executions.md` ("Record receipts
only after each command returns success and publish a receipt set only when the caller accepts
the overall command phase" and "Publish finalized command receipts before handling `seihou run
--commit`"). Milestone 5 promotes the new decision to ADR 0023.

### Cross-repository references

The module that exposes the problem is `mori://shinzui/seihou-modules/templates/git-init`
(file `modules/git/git-init/module.dhall` in that project). Its current commands are `git init
-b {{git.defaultBranch}}`, `git add -A && (git diff --cached --quiet || git -c
commit.gpgsign=false commit -m 'Initial commit')`, one `gh repo create ... --source=.
--remote=origin --push` variant per visibility, and an optional `gh api ... teams ...` grant.
The recipes `github-repo`, `haskell-library-repo` and `haskell-cli-app-repo` in the same
project end with it. None of them needs a change.

Related plans in this repository: `docs/plans/67-track-generated-commands-and-skip-unchanged-executions.md`
introduced receipts; `docs/plans/80-document-and-end-to-end-verify-the-shared-manifest-workflow.md`
is why the committed manifest must be accurate for collaborators;
`docs/plans/105-rebuild-checkout-local-symlinks-from-the-manifest-without-upgrading-artifacts.md`
explicitly left this timing unchanged.


## Plan of Work

The work is five milestones. The first makes the "expected receipt set" a named, tested library
concept. The second applies it to `seihou run`, which is where `git-init` bites. The third gives
the update transaction the one capability it lacks, restoring the manifest. The fourth applies
the same ordering to `seihou update` on top of that. The fifth records the decision for the
project and closes IR-9. Milestones 1 and 2 can be committed and released on their own; 3 and 4
belong together.

### Milestone 1: the expected receipt set is a library function

In `seihou-cli/src/Seihou/CLI/CommandExecution.hs`, add and export

```haskell
-- | The receipts 'executeCommandPlan' returns when every runnable command in
-- the plan succeeds, stamped with @completedAt@. Known before the first
-- command runs, because fingerprints and the stamp do not depend on execution.
expectedCommandReceipts :: UTCTime -> CommandPlan -> [CommandReceipt]
```

It yields one receipt, in plan order, for every `PlannedCommand` whose disposition is
`CommandWillRun`, whose operation is a `RunCommandOp`, and which is not a checkout command.
Factor the receipt construction that `executeCommands` currently performs inline (the
`RunCommandOp {moduleName, command, workDir} -> Just (CommandReceipt ...)` branch) into one
helper, for example `plannedReceipt :: UTCTime -> PlannedCommand -> Maybe CommandReceipt`, and
use it from both `executeCommands` and `expectedCommandReceipts`, so the two cannot drift.

Add tests to `seihou-cli/test/Seihou/CLI/CommandExecutionSpec.hs` under a new `describe
"expectedCommandReceipts"`: a plan of two runnable commands executed under `runProcessPure` with
two `successMock`s returns `Right (expectedCommandReceipts laterTime plan)`; a plan mixing a
skipped-unchanged command, a disabled plan, and a checkout command yields no receipt for any of
them; and `finalizeCommandReceipts plan (expectedCommandReceipts t plan) prior` equals
`finalizeCommandReceipts plan actual prior` where `actual` came from the successful execution.

Acceptance: `cabal test seihou-cli-test --test-options='-p "expectedCommandReceipts"'` passes
and the existing `CommandExecutionSpec` tests still pass.

### Milestone 2: `seihou run` publishes receipts before the phase and withdraws them on failure

In `seihou-cli/src-exe/Seihou/CLI/Run.hs`, next to `candidateCommandReceipts`, compute the
receipt map a successful phase will leave:

```haskell
expectedCommandReceiptMap =
  finalizeCommandReceipts commandPlan (expectedCommandReceipts now commandPlan) priorCommandReceipts
```

`candidateCommandReceipts` keeps its current meaning but becomes the **withdrawal set**: what the
manifest must hold if the phase does not complete (for `RunAllCommands` that is the empty map,
exactly as today's first write; for `DisableCommands` both maps are the retained prior receipts,
so `--no-commands` is unchanged). In the generation block, set `#commandReceipts .~
expectedCommandReceiptMap` on `appliedComposition`, so the first manifest write, the one a module
command can commit, already carries the receipts.

Wrap the command phase so that failure and interruption both withdraw. Run
`executeCommandPlanWithOutput` under a handler that catches `SomeException` (which includes the
`UserInterrupt` the runtime raises on Ctrl-C) and, for either a `Left commandError` result or an
exception, writes `setApplicationCommandReceipts currentApplicationId candidateCommandReceipts
newManifest` through `runManifestStore manifestPath (writeManifest ...)` before continuing with
today's reporting and exit (or rethrowing the exception). Put the reusable part in the library,
not in `Run.hs`: for example

```haskell
-- | Run a command phase whose receipts were published in advance. If the
-- phase returns a failure or throws, run the withdrawal action first, then
-- return the failure or rethrow.
withReceiptWithdrawal :: IO () -> IO (Either CommandExecutionError a) -> IO (Either CommandExecutionError a)
```

in `seihou-cli/src/Seihou/CLI/CommandExecution.hs` (it has no executable-only imports), with a
unit test that an action throwing `UserInterrupt` runs the withdrawal exactly once and
propagates the exception, and that a `Left` result runs it once and is returned unchanged. A
withdrawal write that itself fails must not mask the original error: log it and continue with
the original failure path.

After a successful phase compute `finalCommandReceipts` exactly as today. If it equals
`expectedCommandReceiptMap`, which is the expected case, skip the second manifest write and log
at debug level that the published receipts were confirmed. If it differs, write the manifest
with `finalCommandReceipts` and log at debug level that the published set differed; that would
indicate a bug in `expectedCommandReceipts`, and the end-to-end test below would catch it as a
dirty tree. The `--commit` block stays after this point unchanged.

Extend the failure message printed on a command failure (the branch that today prints "Ordinary
application commands are not retried by sync ...") with one sentence stating that the receipts
for this run were withdrawn from `.seihou/manifest.json`, and that if a command in this run
committed or pushed the manifest, that snapshot records receipts for commands that did not
complete, so the user should rerun `seihou run <module>` after correcting the failure and commit
the result. Keep the existing sentences.

Add `seihou-cli/test/Seihou/CLI/CommandReceiptE2ESpec.hs` (register it in
`seihou-cli/test/Main.hs` and the cabal `other-modules`) with these cases, built on
`SeedRunE2ESpec.prepare`, `invoke`, `success` and `readManifest`, overwriting the demo module's
`module.dhall` with a managed step plus the commands under test:

- **A committing command leaves a clean tree and a complete committed manifest.** Commands:
  `git init -q -b master` and `git add -A && git -c user.name='Seihou Test' -c
  user.email=test@example.com -c commit.gpgsign=false commit -qm 'Initial commit'`. Run
  `seihou run demo` (stdin is not a terminal under the test runner, so no confirmation prompt
  appears). Assert the exit is success; `git -C root status --porcelain` is empty; `git -C root
  show HEAD:.seihou/manifest.json` decodes with `manifestFromJSON` and the `demo` application's
  `commandReceipts` has exactly two entries whose `command` texts are the two commands; and the
  bytes of `.seihou/manifest.json` on disk equal the bytes of that committed blob. Then `git
  clone root clone` and run `seihou update demo --dry-run` in `clone` (use `invoke` with the
  clone as root); assert success and that the output contains `Already up to date.`.
- **A failing command withdraws the receipts.** Commands: the two above plus `exit 7`. Assert
  the exit is `ExitFailure 1`; the on-disk manifest's `demo` application has an empty
  `commandReceipts`; `git status --porcelain` is exactly ` M .seihou/manifest.json`; the
  combined output contains `Command failed (exit 7)` and the new withdrawal sentence; and, to
  keep the accepted residual visible, the committed blob's `demo` application has three receipts.
- **`--no-commands` and `--dry-run` are unchanged.** After the first case, run `seihou run demo
  --no-commands --force` and assert the two receipts are still present and the manifest bytes
  unchanged; run `seihou run demo --dry-run` on a fresh fixture and assert no manifest exists.

Optionally (not required for acceptance), add an interrupt case that starts `seihou run demo`
with `createProcess`, waits for a sentinel file the first command writes before a `sleep`,
sends `SIGINT` to the seihou process with `System.Posix.Signals.signalProcess`, waits for exit,
and asserts the manifest holds no receipts. If it proves timing-sensitive, keep the unit test on
`withReceiptWithdrawal` as the required evidence and record the manual check in Surprises &
Discoveries.

Acceptance: the new end-to-end cases pass, every other `seihou-cli-test` case passes, and the
manual demonstration in Concrete Steps shows an empty `git status` after a run whose last
command commits.

### Milestone 3: the update transaction can restore the manifest

In `seihou-core/src/Seihou/Engine/UpdateTransaction.hs`, add a field `manifestBackup :: !(Maybe
FilePath)` to `JournalMetadata`, holding the bare file name of a byte copy of
`.seihou/manifest.json` stored under the transaction directory's `backups/` folder (for example
`manifest.json`). New journals are written as `journalVersion = 5`. `initializeJournal` copies
the manifest bytes with `BS.readFile`/`BS.writeFile` (not through `Manifest` decoding, so the
copy is byte-exact) when `.seihou/manifest.json` is a regular file, and records `Nothing` when
it is absent. The `FromJSON` instance accepts versions 1 through 5 and defaults `manifestBackup`
to `Nothing` for versions below 5; the `ToJSON` instance always emits it. `validateJournal`
checks the name with the existing `validateBackupName`.

`rollbackUpdateTransaction` restores the manifest when `manifestBackup` is `Just`: write the
backup bytes to `.seihou/manifest.json.tmp` and rename over `.seihou/manifest.json`, after
restoring entries and before cleaning the directory, with the same safety posture as the other
restores (the `.seihou` directory must be a real directory; fail with
`TransactionRollbackFailed` otherwise). `recoverOne` needs no change: a non-matching manifest
already routes to rollback. `completeUpdateTransaction` already deletes the directory and with
it the copy.

Tests in `seihou-core/test/Seihou/Engine/UpdateTransactionSpec.hs`: rollback restores a
manifest whose bytes were deliberately unusual (for example pretty-printed with extra
whitespace) byte for byte after the orchestrator overwrote it; crash recovery (begin, apply a
reconciliation, write a different manifest to disk, do not set a matching marker, call
`recoverIncompleteTransactions`) restores both the file and the manifest; the committed path
leaves the manifest alone; a hand-written version-4 journal without `manifestBackup` decodes
and recovers as before; and the existing path-validation test still rejects
`.seihou/manifest.json` as a target. Update the journal note in
`docs/dev/architecture/overview.md` to mention version 5 and the manifest copy.

Acceptance: `cabal test seihou-core-test --test-options='-p "UpdateTransaction"'` passes along
with the rest of `seihou-core-test`.

### Milestone 4: `seihou update` publishes the manifest before the phase

In `applyAcceptedPlan` in `seihou-cli/src/Seihou/CLI/Update.hs`, after `applyUpdateCheckout`
succeeds, build the final manifest from the expected receipts rather than from executed ones:

```haskell
let expectedReceipts = expectedCommandReceipts now (plan ^. #commandPlan)
    finalManifest = buildFinalManifest now plan filesManifest expectedReceipts
```

Then, in this order: `publishCandidates`, `writeManifestIO (plan ^. #snapshot . #manifestPath)
finalManifest`, `executeCommandPlan now (plan ^. #commandPlan)`. On `Left err` call
`abortUpdate transaction (UpdateCommandFailed err [ArbitraryCommandSideEffectsMayRemain])`
exactly as today; because of milestone 3 the rollback now also restores the manifest. On `Right
completedReceipts`, compare `buildFinalManifest now plan filesManifest completedReceipts` with
`finalManifest`; if they differ (a bug in the expectation, not an expected path), write the
actual one and continue with it. Then `setCommitMarkers transaction finalManifest` and
`finishCommitted`. A failure of `publishCandidates` or of the manifest write still aborts as
today. The service journal's marker is set inside `setCommitMarkers`, so a crash during commands
also restores the install cache: `recoverServiceBackups` finds no marker and restores the byte
backups.

Keep the human and JSON renderers unchanged. The `commandSummary` in the result still counts
what was executed.

Add update cases to `seihou-cli/test/Seihou/CLI/CommandReceiptE2ESpec.hs` built on
`UpdateSpec.prepareUpdateFixture`:

- **An update whose new command commits leaves a clean tree.** After `prepareUpdateFixture
  root`, turn `<root>/project` into a git repository and commit everything. Rewrite the remote's
  `module.dhall` so version 2.0.0 declares the single command `git add -A && git -c
  user.name='Seihou Test' -c user.email=test@example.com -c commit.gpgsign=false commit -qm
  'Adopt demo 2.0.0'` (use the legacy `{ run, workDir, when }` record shape that
  `moduleDhallWithTemplate` uses) and commit the remote. Run `seihou update demo --json`, assert
  success, `"outcome":"applied"`, `git status --porcelain` empty, `git show
  HEAD:.seihou/manifest.json` decodes to a manifest whose `demo` application has one receipt
  for that command and whose module version is `2.0.0`, and the on-disk manifest bytes equal
  the committed blob.
- **An update whose command fails restores the pre-update manifest.** Same fixture, 2.0.0
  declaring `exit 7`. Read the manifest bytes before the update. Run `seihou update demo
  --json`; assert a non-zero exit with `"code":"command_failed"` (or the renderer's exact
  spelling from `Seihou.CLI.Update.Render.errorCode`), the manifest bytes equal the pre-update
  bytes, `README.md` holds the 1.0.0 content again, and `<root>/project/.seihou/transactions`
  is empty or absent.

Acceptance: both cases pass, `UpdateE2ESpec`, `UpdateSpec` and `SeedUpdateE2ESpec` still pass.

### Milestone 5: documentation, ADR, changelog, IR-9

Update the "Commands" section of `docs/user/module-authoring.md`: receipts for a run's
application commands are written to the manifest before the first command starts, so a
module's own command may commit or push `.seihou/manifest.json` and the committed manifest is
complete; a failed or interrupted phase withdraws them; and the one caveat: a commit made by a
command before a later command fails records receipts for commands that did not complete, so
rerun the module (or `seihou update --run-all-commands`) and commit the corrected manifest.
Add a bullet to "Stateful Manifest for Incrementality" in `docs/dev/architecture/overview.md`
describing receipt publication order for run and update, and the journal version 5 note from
milestone 3. Add an entry under `## [Unreleased]` / `### Fixed` in `docs/user/CHANGELOG.md`
stating that modules whose commands commit the project (such as `git-init`) no longer leave
`.seihou/manifest.json` modified and no longer commit a manifest without receipts.

Write `docs/adr/0023-command-receipts-are-published-before-the-command-phase-runs.md` in the
existing ADR shape. Context: receipts written after the phase cannot reach a snapshot a command
takes; the receipt set is determined before execution. Decision: both commands publish the
receipt set a successful phase will produce before the phase; a failed or interrupted phase
withdraws it (run: a second write of the pre-phase receipts; update: transactional rollback
including the journaled manifest copy); update's commit marker is set only after the phase.
Consequences: a receipt in a committed manifest means the run that produced it completed, with
the documented exception of a committing command followed by a failure; no schema change;
`seihou run <module>` and `seihou update --run-all-commands` are the remedies. Reference EP-67,
IR-9, ADR 0004, 0007, 0011, 0014.

Close IR-9: set `status: completed`, `completedAt`, a one-sentence `resolution`, keep
`targetPlan`, add a `reviews` entry in the shape IR-13 uses (the profile recommends one per
revision), rewrite its Status section to name this plan and the evidence, bump `timestamp`,
then run from the repository root:

```bash
okf log add docs/improvement-requests -m "IR-9 is completed by ExecPlan 116: ..." --kind Update
okf validate docs/improvement-requests --strict --profile docs/improvement-requests/profile.dhall --profile-enforce --log-enforce
```

Acceptance: the enforced validation run reports no deviation naming
`record-command-receipts-before-commands-can-commit-them` (other requests' pre-existing
advisory deviations are out of scope; see Surprises & Discoveries), the unenforced run prints
`OK: 13 concepts`, `nix fmt` leaves no changes, `nix/check-record-conventions.sh` and
`nix/check-cli-module-placement.sh` exit 0, and `cabal test all` passes.


## Concrete Steps

All commands run from the repository root, `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`
(or wherever the checkout lives). Build everything once first; the end-to-end tests need the
executable:

```bash
cabal build all
```

Run focused tests while developing, then the whole suites at each milestone boundary:

```bash
cabal test seihou-cli-test --test-options='-p "expectedCommandReceipts"'
cabal test seihou-cli-test --test-options='-p "command receipts"'
cabal test seihou-core-test --test-options='-p "UpdateTransaction"'
cabal test seihou-core-test
cabal test seihou-cli-test
```

A passing focused run ends like this (counts will differ):

```text
All 6 tests passed (2.41s)
Test suite seihou-cli-test: PASS
```

Format and run the convention checks before each commit:

```bash
nix fmt
nix/check-record-conventions.sh
nix/check-cli-module-placement.sh
```

Manual demonstration of milestone 2 without installing `git-init`. Create a throwaway project
with a project-local module whose last command commits, run it, and look at the tree. The
schema directory is the repository's `schema/` folder; `$SCHEMA` below must be an absolute path
to it.

```bash
SCHEMA="$PWD/schema"
DEMO="$(mktemp -d)"
mkdir -p "$DEMO/.seihou/modules/demo/files"
printf 'license\n' > "$DEMO/.seihou/modules/demo/files/license"
cat > "$DEMO/.seihou/modules/demo/module.dhall" <<EOF
let S = $SCHEMA/package.dhall
in S.Module::{ name = "demo", version = Some "1.0.0"
  , steps = [ S.Step::{ strategy = "copy", src = "license", dest = "LICENSE" } ]
  , commands =
    [ S.Command::{ action = S.Command.Action.Apply "git init -q -b master" }
    , S.Command::{ action = S.Command.Action.Apply "git add -A && git -c user.name='Demo' -c user.email=demo@example.com -c commit.gpgsign=false commit -qm 'Initial commit'" }
    ] }
EOF
( cd "$DEMO" && "$(cabal list-bin seihou-cli:seihou)" run demo --force && git status --porcelain && git show HEAD:.seihou/manifest.json | grep -c '"completedAt"' )
```

Before this plan the last two lines print ` M .seihou/manifest.json` and `0`. After milestone 2
`git status --porcelain` prints nothing and the grep prints `2`. Run `seihou update demo
--dry-run` in a `git clone` of `$DEMO` to see `Already up to date.`

Commit at each milestone boundary with Conventional Commits and both trailers, for example:

```text
feat(run): publish command receipts before the command phase

Write the receipts a successful phase will produce into the manifest before
the first command runs, so a module command that commits the project captures
a complete manifest. A failed or interrupted phase withdraws them.

ExecPlan: docs/plans/116-record-command-receipts-before-module-commands-can-commit-the-manifest.md
Intention: intention_01m61nj2meeczthnm1atsrmc15
```


## Validation and Acceptance

The plan is accepted when all of the following hold.

A project-local module whose commands are `git init -q -b master` and a `git add -A && git
commit` leaves, after `seihou run demo`, an empty `git status --porcelain`, a `HEAD`
`.seihou/manifest.json` whose `demo` application holds two `commandReceipts`, on-disk manifest
bytes identical to that blob, and a fresh clone in which `seihou update demo --dry-run` prints
`Already up to date.` (end-to-end test, milestone 2).

The same module with a trailing `exit 7` exits 1, prints `Command failed (exit 7)` and the
withdrawal sentence, leaves the on-disk `demo` application with no receipts, and shows exactly
` M .seihou/manifest.json` in `git status --porcelain` (end-to-end test, milestone 2).

`executeCommandPlan t plan` on an all-success plan equals `Right (expectedCommandReceipts t
plan)`, and `withReceiptWithdrawal` runs its withdrawal exactly once on a thrown
`UserInterrupt` and on a `Left` result (unit tests, milestones 1 and 2).

`rollbackUpdateTransaction` and `recoverIncompleteTransactions` restore a journaled manifest
byte for byte; a version-4 journal still decodes (unit tests, milestone 3).

`seihou update demo --json` against a 2.0.0 whose command commits leaves an empty `git status
--porcelain` and a committed manifest with that receipt; against a 2.0.0 whose command is `exit
7` it exits non-zero with the `command_failed` error, the manifest and `README.md` are byte-
identical to their pre-update state, and no transaction directory remains (end-to-end tests,
milestone 4).

`cabal test all`, `nix/check-record-conventions.sh` and `nix/check-cli-module-placement.sh`
exit 0; the enforced `okf validate` run for `docs/improvement-requests` names no deviation for
IR-9; `nix fmt` is a no-op.

Proposed but not required: the SIGINT end-to-end case in milestone 2, and a real `seihou run
git-init` against an installed `mori://shinzui/seihou-modules` with `git.createGithub=false`,
recorded in Outcomes & Retrospective if performed.


## Idempotence and Recovery

Every milestone is additive and can be re-run. The library function in milestone 1 is pure. The
`Run.hs` change in milestone 2 writes the manifest once on success instead of twice, and the
withdrawal write reproduces today's failure state exactly, so a run interrupted before or after
the change leaves a manifest the current release would also have left; the only new state after
a hard kill is a manifest with receipts for commands that did not run, remedied by `seihou run
<module>` (which re-runs everything) or `seihou update --run-all-commands`. Milestone 3 writes
version-5 journals and keeps decoding versions 1 through 4, so a project with an interrupted
older transaction recovers as before; a version-5 journal read by an older seihou fails
decoding and is quarantined, which is the existing behavior for unknown journals and only
affects a checkout that downgrades mid-transaction. Milestone 4 moves the marker after the
phase, so a crash at any point before `setCommitMarkers` rolls back files, manifest and install
cache together; a crash between `setCommitMarkers` and `finishCommitted` is recovered as a
commit, as today.

If the end-to-end git tests fail in an environment without a global git identity, the fixtures
pass `-c user.name` and `-c user.email` on every commit and set them with `git config` in the
fixture repository; do not rely on the developer's `~/.gitconfig`. If `seihouBinary` reports it
cannot find the executable, run `cabal build seihou-cli:seihou` and rerun.

To back out milestone 2 alone, restore `#commandReceipts .~ candidateCommandReceipts` in the
generation block and the unconditional second write; the library additions can stay. To back
out milestone 4, restore the original order (`executeCommandPlan`, `buildFinalManifest` with
completed receipts, `setCommitMarkers`, `publishCandidates`, `writeManifestIO`); the journal
copy from milestone 3 is harmless when the manifest is written last.


## Interfaces and Dependencies

New in `seihou-cli/src/Seihou/CLI/CommandExecution.hs` (library, no executable-only imports):

```haskell
expectedCommandReceipts :: UTCTime -> CommandPlan -> [CommandReceipt]
withReceiptWithdrawal :: IO () -> IO (Either CommandExecutionError a) -> IO (Either CommandExecutionError a)
```

Both `seihou-cli/src-exe/Seihou/CLI/Run.hs` and `seihou-cli/src/Seihou/CLI/Update.hs` consume
`expectedCommandReceipts`; `Run.hs` consumes `withReceiptWithdrawal`. `buildFinalManifest` in
`Update.hs` keeps its signature `UTCTime -> UpdatePlan -> Manifest -> [CommandReceipt] ->
Manifest` and is simply called with the expected list.

Changed in `seihou-core/src/Seihou/Engine/UpdateTransaction.hs`: `JournalMetadata` gains
`manifestBackup :: !(Maybe FilePath)`; journals are written as version 5; versions 1 through 5
decode; `rollbackUpdateTransaction` restores the manifest when the field is present. The exported
API (`beginUpdateTransaction`, `beginSeedUpdateTransaction`, `applyReconciliation`,
`rollbackUpdateTransaction`, `setUpdateTransactionExpectedManifest`,
`completeUpdateTransaction`, `recoverIncompleteTransactions`) is unchanged in type.

Unchanged and relied upon: `Seihou.Core.CommandFingerprint.fingerprintCommand` and
`isCheckoutCommand`; `Seihou.Effect.ManifestStoreInterp.writeManifest` (atomic write);
`Seihou.CLI.Update.Recovery` service journal and `setServiceExpectedManifest`;
`Seihou.Manifest.Types.manifestFromJSON` and `manifestToJSON`; the `CommandReceipt` JSON codec
in `seihou-core/src/Seihou/Manifest/Types.hs` (no schema version change). Test helpers reused:
`Seihou.CLI.SeedRunE2ESpec` (`prepare`, `invoke`, `success`, `readManifest`),
`Seihou.CLI.CheckoutSyncE2ESpec.copyPinnedSchema`, `Seihou.CLI.UpdateSpec.prepareUpdateFixture`,
`Seihou.CLI.SeihouBinary.seihouBinary`. External tools: `git` 2.28 or newer (for `git init -b`)
on the test machine; `okf` for the improvement-request bundle; `nix` for formatting and the
convention checks.
