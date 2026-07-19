---
id: 67
slug: track-generated-commands-and-skip-unchanged-executions
title: "Track generated commands and skip unchanged executions"
kind: exec-plan
created_at: 2026-07-19T16:27:06Z
intention: "intention_01kxxjwvf8e2e8r64feyk6r65b"
master_plan: "docs/masterplans/8-make-module-updates-seamless-and-conflict-aware.md"
---

# Track generated commands and skip unchanged executions

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, rendered module commands have stable ownership and fingerprints, and
Seihou can distinguish commands that have already completed unchanged from commands that
are new or changed. Ordinary `seihou run` remains backward compatible and executes every
rendered command, but records receipts only after successful execution. The later
`seihou update` workflow defaults to executing only commands whose fingerprints are absent
from the recorded application, with explicit run-all and disabled policies.

For the motivating composition, six unchanged symlink/setup commands will be summarized as
skipped instead of run again on every module update. If a command's rendered text, work
directory, owning module instance, or duplicate occurrence changes, it receives a new
fingerprint and runs. Failed commands never receive a success receipt.


## Progress

- [x] (2026-07-19 18:59Z) M1: Preserve qualified module-instance ownership and duplicate occurrence on rendered commands.
- [x] (2026-07-19 18:59Z) M1: Compute stable command fingerprints and update operation/preview tests.
- [x] (2026-07-19 19:03Z) M2: Add command planning policies, summary data, execution results, and receipt finalization.
- [x] (2026-07-19 19:03Z) M2: Prove unchanged, changed, duplicate, removed, failed, run-all, and disabled behavior.
- [x] (2026-07-19 19:12Z) M3: Record successful receipts from ordinary `seihou run` without changing its run-all default.
- [x] (2026-07-19 19:12Z) M3: Ensure failed runs and dry runs do not record receipts.
- [x] (2026-07-19 19:13Z) M3: Run focused/full tests, formatting, and a temporary command-count smoke test.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- The executable's existing command loop printed captured stdout after every successful
  command, while the planned reusable API returned only receipts. The library now offers an
  output callback around the same executor so `seihou run` preserves that observable output
  without duplicating process execution.

- `--no-commands` must plan against the complete unfiltered operation list. Filtering command
  operations first would make the current declaration set invisible and either clear valid
  prior receipts or retain receipts for removed commands. The file preview remains filtered
  for backward compatibility, but receipt finalization sees every rendered command.

- A disposable real CLI fixture confirmed run-all and failure behavior:

  ```text
  after dry-run: manifest absent, counter absent
  after two ordinary runs: counter lines = 2, receipts = 2
  after --no-commands: counter lines = 2, receipts = 2 with unchanged timestamps
  after changing the first command to exit 7: exit = 1, counter lines = 2, receipts = 0
  ```


## Decision Log

- Decision: Fingerprint the fully rendered command, normalized work directory, qualified
  module instance, and occurrence among identical commands.
  Rationale: Inputs that change rendered behavior must cause execution. The occurrence
  distinguishes two intentional identical command declarations without making unrelated
  insertion order invalidate every subsequent command.
  Date: 2026-07-19.

- Decision: Exclude module version and absolute project path from the fingerprint.
  Rationale: An unchanged command should stay unchanged across a module version bump, which
  is the noise this feature removes. Work directories are project-relative by validation;
  including an absolute checkout path would make cloned/moved projects rerun everything.
  Date: 2026-07-19.

- Decision: Keep ordinary `seihou run` on `RunAllCommands` and use
  `RunChangedCommands` only for the new update workflow.
  Rationale: Existing module authors may rely on run commands as an explicit repeated hook.
  Silently changing the established command would be a compatibility break. The new update
  operation can state its incremental policy clearly.
  Date: 2026-07-19.

- Decision: Record receipts only after each command returns success and publish a receipt
  set only when the caller accepts the overall command phase.
  Rationale: A receipt means the exact command completed. Failed or never-started commands
  must be eligible on retry. EP-68 may discard all candidate receipts when rolling back an
  update even if earlier commands succeeded.
  Date: 2026-07-19.

- Decision: Drop receipts for commands no longer present when an application is successfully
  replaced.
  Rationale: The receipt set describes the accepted current command declaration set. Keeping
  removed fingerprints would grow without bound and could incorrectly suppress an identical
  command reintroduced under different surrounding declarations years later.
  Date: 2026-07-19.

- Decision: Module commands participate in fingerprinting; migration `RunCommand` operations
  do not.
  Rationale: A migration is already selected once by its version window and advances the
  manifest version on success. Treating it as a recurring module command would mix two
  independent lifecycle models.
  Date: 2026-07-19.

- Decision: Show a command's qualified owner in ordinary previews only when the same rendered
  command text belongs to more than one module instance in that plan.
  Rationale: Ownership remains available when it disambiguates identical commands, while the
  established single-owner `run` preview stays unchanged.
  Date: 2026-07-19.

- Decision: Publish finalized command receipts before handling `seihou run --commit`.
  Rationale: Staging and committing the pre-command candidate manifest would leave the
  successful receipt update dirty and outside the generated-files commit. Deferring the
  existing commit block until commands and the second atomic manifest write succeed keeps the
  commit self-consistent; failed commands leave generated files uncommitted for inspection.
  Date: 2026-07-19.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

Rendered module commands now carry qualified instance ownership and stable duplicate
occurrences, and `Seihou.Core.CommandFingerprint` hashes the rendered behavior without
coupling it to module versions or checkout locations. `Seihou.CLI.CommandExecution`
provides ordered run-all, changed-only, and disabled plans; structured summaries and
failures; success-only receipts; and finalization that prunes removed declarations.

Ordinary `seihou run` remains run-all. It publishes a receipt-free candidate before enabled
commands, replaces that candidate with finalized receipts only after the whole command phase
succeeds, preserves matching receipts for `--no-commands`, and leaves failed or dry runs
without new evidence. Successful command stdout remains visible, and `--commit` now includes
the finalized receipt-bearing manifest.

Validation passed after formatting: 1,002 core tests, 271 CLI tests, and 16 extension tests
(1,289 total). A disposable real module appended two counter lines across two ordinary runs,
preserved both receipts without execution under `--no-commands`, and cleared candidate
receipts when a changed command failed. Changed-only execution is intentionally not exposed
through `run`; EP-68 consumes it as the default policy for project updates.


## Context and Orientation

This plan depends on EP-64, which defines `CommandFingerprint`, `CommandReceipt`, and the
`commandReceipts` map on `AppliedComposition`. Verify
`docs/plans/64-record-reproducible-applied-compositions-and-update-state.md` is complete and
consume those definitions unchanged.

A module declares `[Command]` in `Seihou.Core.Types`. Each declaration contains shell text,
an optional work directory, and an optional condition. `seihou-core/src/Seihou/Engine/Plan.hs`
evaluates conditions and interpolates variables into `RunCommandOp Text (Maybe FilePath)`.
That operation currently has no owner, so once several module plans are merged there is no
way to attribute a command to its module instance.

`seihou-core/src/Seihou/Composition/Plan.hs` already compiles each module under its qualified
instance name before merging operations. It deliberately keeps every command operation.
This is the correct place to preserve ownership: pass the qualified module name into command
compilation and carry it on the operation.

`seihou-cli/src-exe/Seihou/CLI/Run.hs` filters commands for `--no-commands`, previews them,
writes files and the manifest, then shells out sequentially via its local `executeCommand`.
That helper exits the entire process on failure and is not directly unit-testable from
`seihou-cli-test`. Extract reusable planning/execution into the library at
`seihou-cli/src/Seihou/CLI/CommandExecution.hs`; keep only log rendering and exit conversion
in the executable handler.

`seihou-core/src/Seihou/Engine/Preview.hs`, `Execute.hs`, operation equality tests, and
pattern matches throughout source/tests must be updated when `RunCommandOp` gains metadata.
Use `rg "RunCommandOp"` to find every site. Do not rely on a compilation-error-only sweep,
because comments and expected render output also encode the old shape.


## Plan of Work

### Milestone 1: make rendered commands identifiable

Extend `RunCommandOp` in `seihou-core/src/Seihou/Core/Types.hs`:

```haskell
| RunCommandOp
    { command :: Text
    , workDir :: Maybe FilePath
    , moduleName :: ModuleName
    , occurrence :: Int
    }
```

`moduleName` is the qualified module-instance owner supplied by composition. `occurrence`
is zero-based among previously rendered commands from that same owner with identical
rendered command/work-directory pairs. A module that intentionally declares the identical
command twice therefore gets occurrences 0 and 1. Inserting a different command before
them does not change those values.

Change `compileCommands`/`compileOneCommand` in `Seihou.Engine.Plan` to receive the module
name and assign occurrences after condition evaluation and interpolation. `compilePlan`
passes `modul.name`; `compileComposedPlan` already substitutes the qualified name into the
module before calling it. Update preview, execution filtering, and every constructor/pattern
match.

Create `seihou-core/src/Seihou/Core/CommandFingerprint.hs`:

```haskell
fingerprintCommand :: Operation -> Maybe CommandFingerprint
```

Return `Nothing` for non-command operations. Canonical fingerprint text contains labeled
lines for the qualified owner, command, normalized work directory (`.` for `Nothing`), and
occurrence. Normalize path separators through `System.FilePath.normalise` but do not resolve
against the absolute project directory. Hash with `Seihou.Manifest.Hash.hashContent` and
retain the full digest.

Add `Seihou.Core.CommandFingerprintSpec` plus updates to Plan, Composition.Plan, Preview,
Execute, and Types specs. Acceptance for this milestone is that command ownership survives
composition and fingerprints are stable/different in the intended cases.

### Milestone 2: plan and execute commands with receipts

Create `seihou-cli/src/Seihou/CLI/CommandExecution.hs` in the private library and expose it
from `seihou-cli/seihou-cli.cabal`:

```haskell
data CommandPolicy
  = RunAllCommands
  | RunChangedCommands
  | DisableCommands

data CommandDisposition
  = CommandWillRun
  | CommandSkippedUnchanged
  | CommandSkippedDisabled

data PlannedCommand = PlannedCommand
  { operation :: Operation
  , fingerprint :: CommandFingerprint
  , disposition :: CommandDisposition
  }

data CommandPlan = CommandPlan
  { commands :: [PlannedCommand]
  }

data CommandExecutionError = CommandExecutionError
  { command :: PlannedCommand
  , exitCode :: Int
  , stdout :: Text
  , stderr :: Text
  }

planCommands
  :: CommandPolicy
  -> Map CommandFingerprint CommandReceipt
  -> [Operation]
  -> CommandPlan

executeCommandPlan
  :: (Process :> es)
  => UTCTime
  -> CommandPlan
  -> Eff es (Either CommandExecutionError [CommandReceipt])

finalizeCommandReceipts
  :: CommandPlan
  -> [CommandReceipt]
  -> Map CommandFingerprint CommandReceipt
  -> Map CommandFingerprint CommandReceipt
```

RunAll marks every command to run. RunChanged marks commands whose fingerprint already has a
receipt as skipped unchanged and all others to run. Disable marks every command skipped
disabled. Preserve declaration/composition order for execution and rendering.

`executeCommandPlan` invokes `sh -c` with the rendered work directory and stops at the first
failure, returning a structured error instead of exiting. It returns receipts only for
successful commands it actually ran. Skipped commands do not receive fresh timestamps.
`finalizeCommandReceipts` constructs the receipt map for the current declaration set: use
new receipts for successful executions; retain old receipts for skipped-unchanged commands;
and, for a disabled command, retain an old receipt only when that exact fingerprint is still
declared. New disabled commands receive no receipt, and removed fingerprints are excluded.
This makes `--no-commands` a one-off execution choice without allowing the receipt map to
grow stale or suppress a command that never succeeded.

Add `seihou-cli/test/Seihou/CLI/CommandExecutionSpec.hs` using `ProcessPure` for success,
failure, ordering, skipped commands, duplicate occurrences, changed content, and receipt
finalization.

### Milestone 3: record receipts from ordinary run

Replace the local command loop in `seihou-cli/src-exe/Seihou/CLI/Run.hs` with
`planCommands RunAllCommands` and `executeCommandPlan`. The existing `--no-commands` path
maps to `DisableCommands`; do not add a changed-only flag to `run`.

After all enabled module commands succeed, update the just-recorded `AppliedComposition`
with finalized receipts and write the manifest atomically. The current run handler writes a
candidate manifest before commands. It may retain that compatibility behavior, but it must
perform a second atomic write containing receipts only after success. If a command fails,
the earlier manifest has no success receipt for that command, so retry remains eligible.
Do not record receipts during dry-run or `--diff`.

If `--no-commands` was explicitly supplied, preserve prior receipts for an existing
application rather than clearing them; the user skipped execution for this invocation but
did not declare that the commands ceased to exist. Newly recorded applications have an
empty map.

Update the plan preview to display qualified ownership only when needed and keep ordinary
run output otherwise compatible. Add a temporary module with a command that appends one
line to a counter file. Running `seihou run` twice must still append twice and record one
latest receipt, proving backward compatibility. EP-68 will later demonstrate changed-only
update behavior.


## Concrete Steps

Run from the repository root:

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
rg -n "RunCommandOp" seihou-core seihou-cli -g '*.hs'
cabal test seihou-core-test
cabal test seihou-cli-test
cabal test all
nix fmt
git diff --check
```

The focused planner test should produce an equivalent summary to:

```text
2 command(s): 1 will run, 1 unchanged and skipped
```

The ordinary-run smoke fixture must show its counter has two lines after two runs even
though the receipt fingerprint is the same.

Every implementation commit must include:

```text
MasterPlan: docs/masterplans/8-make-module-updates-seamless-and-conflict-aware.md
ExecPlan: docs/plans/67-track-generated-commands-and-skip-unchanged-executions.md
Intention: intention_01kxxjwvf8e2e8r64feyk6r65b
```


## Validation and Acceptance

The plan is accepted when:

- every composed command carries its qualified module owner and stable identical-command
  occurrence;
- identical rendered commands from different instances have different fingerprints;
- two identical commands from one instance have different fingerprints; inserting a
  different command does not renumber them;
- changing rendered command text or work directory changes the fingerprint; changing module
  version or absolute checkout directory does not;
- RunChanged skips exactly the fingerprints with successful current receipts;
- RunAll executes every command and Disable executes none;
- a failed command yields no receipt for itself or later commands, and the caller can discard
  earlier candidate receipts when rolling back;
- removed commands disappear from a successfully finalized current receipt set;
- ordinary `seihou run` still runs unchanged commands every time and records receipts only
  after success;
- dry-run, diff, and failed commands do not create receipts;
- all tests and formatting gates pass.


## Idempotence and Recovery

Fingerprinting and command planning are pure and repeatable. Command execution is not
generally idempotent; this is precisely why receipts are persisted. A failed command remains
eligible on retry. Never write a success receipt before observing `ExitSuccess`.

Ordinary run retains its existing file/manifest sequencing, so this plan does not promise to
undo command side effects or file generation when a later command fails. EP-68 provides
managed update rollback and explicitly reports that arbitrary command side effects cannot
be reversed. Manual command tests must use disposable directories and benign commands.


## Interfaces and Dependencies

Hard dependency: EP-64. Soft dependency: EP-66 only for shared outcome wording; this plan
must not import reconciliation code.

Use the existing `Process` effect and its pure/real interpreters, `sh -c` behavior already
used by Run, `Seihou.Manifest.Hash`, and EP-64's receipt types. Add no package dependency.

EP-68 consumes `CommandPolicy`, `CommandPlan`, `planCommands`, `executeCommandPlan`, and
`finalizeCommandReceipts`. EP-69 renders command dispositions and maps
`--run-all-commands`/`--no-commands` to policies. The update default is
`RunChangedCommands`; that default belongs at the EP-68/EP-69 boundary, not inside the pure
planner.

Revision note (2026-07-19): Completed all three milestones, recorded the output-preservation
and unfiltered-planning discoveries, and captured focused, full-suite, and disposable CLI
validation evidence.
