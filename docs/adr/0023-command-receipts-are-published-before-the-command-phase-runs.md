# ADR 0023 — Command receipts are published before the command phase runs

- Status: Accepted
- Date: 2026-10-28

## Context

A command receipt in `.seihou/manifest.json` tells `seihou update` that an application
command already completed unchanged, so update skips it. Receipts used to be written
only after the whole command phase returned. A module whose own commands snapshot the
project (`git-init` runs `git add -A && git commit` and then `gh repo create --push`)
therefore committed and pushed a manifest with no receipts, and seihou rewrote the
manifest a moment later, leaving `.seihou/manifest.json` modified. Anyone working from
the committed manifest, such as a fresh clone or the author after `git checkout .`, saw
those commands as never run, and update ran them again (`gh repo create` then fails).

The receipt set a successful phase produces is known before the first command runs. A
receipt's fingerprint depends only on the rendered command text, normalized work
directory, owning module instance and occurrence, and every receipt is stamped with
the run's single `now`.

## Decision

Both `seihou run` and `seihou update` publish the receipt set a fully successful
command phase will produce before the phase runs
(`Seihou.CLI.CommandExecution.expectedCommandReceipts`).

- Run writes it with the generation manifest. If the phase fails or throws (including
  an interrupt), it rewrites the manifest with the receipts it held before the phase
  (`withReceiptWithdrawal`), so the manifest ends where a failed run always left it. It
  keeps no receipts for commands that succeeded before the failure, matching update.
- Update writes its final manifest inside the update transaction and sets the recovery
  commit marker only after the phase succeeds. Failure, interrupt or crash rolls back
  files, install cache and manifest together. The version-5 journal holds a byte copy of
  the manifest taken when the transaction began. Baselines the new manifest no longer
  references are set aside into the transaction before the phase, so the snapshot a
  command takes holds exactly the referenced blobs. `.seihou/transactions/` ignores
  itself in git.

The serialized manifest is unchanged, so no schema version advances (ADR 0014).

## Consequences

The manifest a module command commits after a successful phase is complete, and the
working tree is clean afterwards. Every recipe ending in `git-init` is fixed by
upgrading seihou alone. A receipt in a committed manifest means the run that produced it
completed, with one documented exception. If a command commits and a later command
fails, or a hard kill hits run between the early write and the withdrawal, the committed
snapshot claims receipts for commands that did not complete. Seihou never rewrites git
history. The withdrawal shows up as a working-tree change, and the failure message names
the residual. `seihou run MODULE` and `seihou update --run-all-commands` re-run the
commands and record them again.

This revises the EP-67 decision to record receipts only after each command returns
success. Removing the early write restores that behavior. Removing update's journaled
manifest copy is unsafe while update publishes its manifest before the phase.

## References

- [Plan 116](../plans/116-record-command-receipts-before-module-commands-can-commit-the-manifest.md)
- [Plan 67](../plans/67-track-generated-commands-and-skip-unchanged-executions.md)
- [IR-9](../improvement-requests/record-command-receipts-before-commands-can-commit-them.md)
- [ADR 0004](0004-the-manifest-is-the-only-record-of-applied-state.md)
- [ADR 0007](0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md)
- [ADR 0011](0011-a-migration-receipt-asserts-a-claim-about-the-project.md)
- [ADR 0014](0014-every-semantic-manifest-change-advances-the-schema-version.md)
- `mori://shinzui/seihou-modules/templates/git-init`
