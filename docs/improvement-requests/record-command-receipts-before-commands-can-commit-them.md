---
type: Improvement Request
title: Record command receipts in a manifest that a module command can commit
description: >-
  Stop seihou from writing command receipts only after every module command has finished, which
  leaves .seihou/manifest.json modified immediately after any module whose own commands commit
  or push the project (git-init), and makes the committed and pushed manifest claim that no
  command has ever run.
generated:
  by: process:claude-code
  at: "2026-10-02T21:01:33Z"
timestamp: 2026-10-02T21:01:33Z
requestId: IR-9
status: proposed
origin: mori://shinzui/okf-profiles
---

# Improvement Request: Record Command Receipts in a Manifest a Module Command Can Commit

## Context

EP-67 (`docs/plans/67-track-generated-commands-and-skip-unchanged-executions.md`) gave every
rendered module command a fingerprint and a `CommandReceipt` stored on its application in
`.seihou/manifest.json`. `seihou update` runs on `RunChangedCommands` and skips any command whose
fingerprint already has a receipt. The plan records the deliberate choice:

> Record receipts only after each command returns success and publish a receipt set only when the
> caller accepts the overall command phase.

The manifest is meant to be committed; the shared-manifest workflow (EP-80) depends on it.

## Problem

`seihou run` writes the manifest twice:

1. `seihou-cli/src-exe/Seihou/CLI/Run.hs` (`writeManifest newManifest`, ~line 476) writes the
   generated files' manifest, carrying only *prior* receipts.
2. Every module command runs (`executeCommandPlanWithOutput`, ~line 523).
3. Only then is the manifest rewritten with the new receipts (`receiptManifest`, ~lines 543–554).

Any module command that snapshots the project, such as a commit or a push, therefore runs between steps 1 and
3 and can never include the receipts. `mori://shinzui/seihou-modules/templates/git-init` is the
canonical case. Its commands are `git init -b master`, then
`git add -A && git commit -m 'Initial commit'`, then
`gh repo create <owner>/<repo> --source=. --remote=origin --push`. Observed on 2026-10-02 when
creating a fresh repository through the `github-repo` recipe
(`mori://shinzui/seihou-modules/templates/repo-dir`, which runs `seihou run git-init` in the new
directory):

```text
$ git status -sb
## master...origin/master
 M .seihou/manifest.json
```

The only difference is the application's `commandReceipts` map gaining the three receipts. Every
recipe that ends with `git-init` (`haskell-library-repo`, `haskell-cli-app-repo`) has the same
leftover change.

The dirty working tree is the visible symptom. The larger issue is that **the manifest that was
committed and pushed says no command has ever run**. A collaborator who clones that repository, or the
author after a `git checkout .`, has a manifest whose `git-init` application has no receipts, so a
later `seihou update` that re-renders the application treats `git init`, the initial commit, and
`gh repo create` as never-run commands. `gh repo create` then fails because the repository already
exists, and it would have created a duplicate if the owner or name had been re-resolved differently.

`seihou update` (`seihou-cli/src/Seihou/CLI/Update.hs`, ~lines 480–500) follows the same order,
running commands and then writing `finalManifest`, so the problem is not specific to `run`.

## Why a module cannot work around it

- The receipts are written after the last command, so no command a module can declare, however
  late, sees them.
- `seihou run --commit` already runs after the receipt write (`Run.hs` ~line 561) and is
  receipt-correct. But it is a CLI flag, not something a module or recipe can declare. It also cannot
  serve `git-init`, whose push has to follow a commit.
- A module command that runs `seihou` again to amend the commit after the outer run has finished
  is not possible, for the same reason as the first point.

## Observation that makes a fix cheap

Every receipt's `completedAt` is the run's `now` (`executeCommandPlanWithOutput now …` in `run`,
`executeCommandPlan now …` in `update`), not the time each command actually finished. The fingerprint
depends only on the rendered command, work directory, owning instance and occurrence. So **the
exact receipt set a fully successful phase will produce is known before the first command runs**,
byte for byte.

## Options

The author has not chosen yet; both are recorded here so the trade-off is not re-derived.

### A. Write the expected receipts first and roll back on failure

Write the manifest with the receipts the phase *will* produce before running commands. On success,
the final write is identical, or can be skipped, so the committed manifest is already correct
and the tree stays clean. On failure, rewrite the manifest so it keeps only the receipts of commands
that actually succeeded, or drops all new ones to match today's "only when the phase is accepted" rule.

- No schema change. `git-init` and every existing recipe are fixed without edits.
- Reverses the EP-67 decision quoted above, so it needs a new Decision Log/ADR entry.
- Crash safety: SIGINT/SIGTERM can be caught and rolled back. A hard kill (SIGKILL, power loss) between the
  write and the rollback leaves receipts for commands that never ran. `update` would then skip them
  until the user forces `RunAllCommands`. The `update` transaction/commit-marker machinery may
  already provide a recovery point for this.

### B. Add a final command phase that runs after receipts are written

Add a field to the schema's `Command`, for example a `phase` or `afterReceipts : Bool`, and run those
commands after the receipt write. This generalises what `--commit` already does. `git-init` would
move its commit and push into that phase.

- Keeps "a receipt means the command completed" for ordinary commands.
- Needs a `seihou-schema` change, so every module gets a new schema hash, plus a `git-init` release.
- Final-phase commands still cannot record their *own* receipts in the snapshot they commit, so
  `update` needs a separate rule for them: never re-run, re-run when the phase above them
  changes, or record them optimistically, which is option A in miniature.

## Scope

Module command receipts in `seihou run` and `seihou update`. Migration `RunCommand` operations are
out of scope, since EP-67 already excludes them from fingerprinting. Either option should come with a test that
runs a module whose last command is `git add -A && git commit` and asserts a clean `git status`
and a committed manifest that already contains that application's receipts.

## Related

- `docs/plans/67-track-generated-commands-and-skip-unchanged-executions.md`: receipt design and
  the decision this request revisits.
- `docs/plans/80-document-and-end-to-end-verify-the-shared-manifest-workflow.md`: why the
  committed manifest has to be accurate for collaborators.
- `mori://shinzui/seihou-modules/templates/git-init`: the module that exposes the problem.
