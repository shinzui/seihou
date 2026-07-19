---
id: 69
slug: ship-the-seihou-update-workflow-and-ecosystem-guidance
title: "Ship the seihou update workflow and ecosystem guidance"
kind: exec-plan
created_at: 2026-07-19T16:27:06Z
intention: "intention_01kxxjwvf8e2e8r64feyk6r65b"
master_plan: "docs/masterplans/8-make-module-updates-seamless-and-conflict-aware.md"
---

# Ship the seihou update workflow and ecosystem guidance

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, the staged update service from EP-68 is available as a coherent public
workflow. A user can run `seihou update master-plan`, inspect one grouped plan, resolve any
real three-way merge or edited-orphan conflicts, confirm once, and receive a concise result.
Running `seihou update` updates all recorded applications. The default skips unchanged
commands and preserves non-overlapping user edits; explicit flags support reconfiguration,
run-all or no-command policies, dry-run, JSON automation, and an optional Git commit.

The surrounding CLI teaches one lifecycle consistently. `seihou run` is for first
application or deliberate reconfiguration, `seihou update` reconciles an already-applied
project with newer sources, and `seihou upgrade` only refreshes the shared installed cache.
Status output, pending-migration advice, command help, completion scripts, and user guides
all use those terms. A local Git remote end-to-end fixture demonstrates the promised DX:
install v1, run it, make a user edit, publish v2, update, observe a clean three-way merge,
and see unchanged commands skipped.


## Progress

- [ ] M1: Add `UpdateOpts`, the `update` parser, dispatcher, and thin executable handler.
- [ ] M1: Render stable human and JSON plans/results with stdout/stderr separation.
- [ ] M1: Add interactive file-conflict and edited-orphan resolution plus non-interactive safety.
- [ ] M1: Wire changed-only defaults, command escape hatches, reconfiguration, force, and commit flags.
- [ ] M2: Deduplicate status rows and recommend `seihou update` for recorded applications.
- [ ] M2: Clarify `run`, `migrate`, and cache-only `upgrade` help and diagnostics.
- [ ] M3: Add the update command reference and revise lifecycle, migration, and authoring guides.
- [ ] M3: Cover parser help, completions, renderers, conflict input, JSON, and commit integration.
- [ ] M4: Add the executable local-remote end-to-end scenario, including a successful three-way merge.
- [ ] M4: Run repository formatting, build, test, package, and documentation-link gates.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

- Decision: Expose project reconciliation as a new top-level `update` command.
  Rationale: Extending cache-first `upgrade` would preserve the confusing split workflow and
  could mutate the installed cache before the project succeeds. `update` names the user's
  actual goal and maps directly to EP-68's project transaction.
  Date: 2026-07-19.

- Decision: With no positional targets, update every recorded application in manifest order.
  Rationale: This makes the common whole-project update one command and preserves the
  deterministic layering recorded by EP-64. EP-68 already rejects unsafe legacy ambiguity.
  Date: 2026-07-19.

- Decision: Always include migration planning; do not add `--with-migrations` to `update`.
  Rationale: Updating templates without their declared layout migrations is unsafe. An opt-in
  migration flag would recreate the current two-step footgun.
  Date: 2026-07-19.

- Decision: Default to changed-only commands, while exposing mutually exclusive
  `--run-all-commands` and `--no-commands` flags.
  Rationale: Avoiding repeated setup work is a core DX improvement, and both explicit replay
  and fully declarative automation remain necessary escape hatches.
  Date: 2026-07-19.

- Decision: Resolve every conflict before a single final confirmation.
  Rationale: The user should understand the complete effect of the batch before mutation.
  Interleaving prompts with writes would complicate rollback and make `--dry-run` dishonest.
  Date: 2026-07-19.

- Decision: `--force` accepts new generated content for ordinary file conflicts but never
  silently deletes an edited orphan.
  Rationale: Replacing a tracked generated file is an explicit overwrite policy. Deleting a
  user-edited file that disappeared from the module is materially more destructive; force
  retains it as a tracked unresolved orphan unless the user explicitly chooses deletion.
  Date: 2026-07-19.

- Decision: `--json` is non-interactive and fails if any resolution remains ambiguous.
  Rationale: Machine-readable stdout cannot safely host terminal questions. Automation must
  either use `--force` where applicable or stop with structured unresolved conflicts.
  Date: 2026-07-19.

- Decision: Preserve `upgrade` as cache-only maintenance rather than silently redirecting it.
  Rationale: Scripts may rely on updating installed sources outside a project. Clear help and
  status guidance can remove ambiguity without breaking that legitimate behavior.
  Date: 2026-07-19.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This plan is the public-surface consumer of
`docs/plans/68-build-a-staged-project-update-service.md`. Confirm EP-68 and its hard
dependencies are Complete in
`docs/masterplans/8-make-module-updates-seamless-and-conflict-aware.md` before editing. Use
EP-68's `UpdateRequest`, `UpdatePlan`, `UpdateResult`, and service entry points; do not move
planning, fetching, migration, reconciliation, command, or publication behavior back into
the executable.

`seihou-cli/src-exe/Seihou/CLI/Commands.hs` defines the top-level `Command` sum type, every
`Options.Applicative` parser, and rich help text. Add `Update UpdateOpts` next to the other
project lifecycle commands and export the option record for the handler. The parser registry
is in the same file. `seihou-cli/src-exe/Main.hs` imports handlers and dispatches `Command`;
it should gain one thin branch.

Create `seihou-cli/src-exe/Seihou/CLI/Update.hs` for terminal-only behavior. It converts
`UpdateOpts` to EP-68's structured request, invokes the bracketed update session, renders the
plan, gathers resolutions when permitted, confirms, invokes apply, renders the result, and
optionally commits. Pure rendering and prompt-decision helpers belong in the private library
under `seihou-cli/src/Seihou/CLI/Update/Render.hs` and
`seihou-cli/src/Seihou/CLI/Update/Interaction.hs` so `seihou-cli-test` can exercise them
without launching a subprocess.

When converting options, set EP-68's `promptPolicy` to `ForbidPrompts` for `--json` and when
stdin is not a terminal; otherwise use `AllowPrompts`. `--force` resolves file choices only
and never invents missing variable values. A prompt-forbidden missing-variable error names
the required `--var KEY=VALUE` overrides.

`seihou-cli/src-exe/Seihou/CLI/Status.hs` gathers installed updates and pending migrations.
`seihou-cli/src/Seihou/CLI/StatusRender.hs` currently renders one row per `AppliedModule` and
recommends either `upgrade` or `migrate`; repeated parameterized instances therefore produce
duplicate advice. Render one recommendation per recorded application or, for a legacy
manifest, one per bare module name. If a recorded application has either a newer source or a
pending migration, its primary action is `seihou update <target>`. Standalone legacy/module
maintenance may still recommend `seihou migrate <module>`.

The current executable handlers `seihou-cli/src-exe/Seihou/CLI/Run.hs` and
`seihou-cli/src-exe/Seihou/CLI/Upgrade.hs`, plus
`seihou-cli/src/Seihou/CLI/PendingMigrations.hs`, contain the old split-workflow advice.
Revise wording and help without removing their existing behaviors: `run` remains initial
generation/reconfiguration and may retain `--with-migrations`; `upgrade` remains cache-only
and may retain its compatibility flag; new project-facing advice should point at `update`.

CLI reference pages are under `docs/cli/`, user guides under `docs/user/`, and the command
table is in `README.md`. The existing completion commands render directly from the same
`Options.Applicative` parser, so parser coverage proves Bash/Zsh/Fish can discover `update`;
retain focused completion tests to catch regressions in the generated scripts.


## Plan of Work

### Milestone 1: expose a safe and concise update command

Add this public option record to `Seihou.CLI.Commands`:

```haskell
data UpdateOpts = UpdateOpts
  { updateTargets :: [Text]
  , updateVars :: [(Text, Text)]
  , updateDryRun :: Bool
  , updateJson :: Bool
  , updateReconfigure :: Bool
  , updateForce :: Bool
  , updateRunAllCommands :: Bool
  , updateNoCommands :: Bool
  , updateCommit :: Bool
  , updateCommitMessage :: Maybe Text
  }
```

Register `seihou update [TARGET...]` with these flags:

- repeated positional `TARGET` selects recorded applications by target or contained module;
- repeated `--var KEY=VALUE` overrides saved values, matching `run` syntax;
- `--reconfigure` ignores every saved per-instance input and resolves through the ordinary
  CLI/environment/config/default/prompt chain;
- `--dry-run` plans and renders without project, cache, baseline, or manifest mutation;
- `--json` emits structured output and disables prompts and the final confirmation;
- `--force` accepts newly generated content for merge conflicts, but retains edited orphans
  as tracked unresolved files and reports that choice;
- `--run-all-commands` selects `RunAllCommands`; `--no-commands` selects
  `DisableCommands`; neither flag selects EP-67's default `RunChangedCommands`, and passing
  both is a parser error;
- `--commit` commits the successfully updated managed paths; `--commit-message MSG` implies
  commit and bypasses generated-message selection.

If a named selection shares any tracked path with an unselected application, render
`SharedPathRequiresApplications` before fetching or mutation. Name the path and every
additional target that must be selected, and suggest the no-argument `seihou update` form.
Do not silently broaden a named selection.

Do not expose flags for skipping migrations or publishing the cache early. Reject
`--reconfigure` in a non-interactive context when new required values remain unresolved.
`--dry-run --json` is supported. `--commit` with dry-run is an error because it suggests an
effect that cannot happen.

Define stable rendering data in `Seihou.CLI.Update.Render`, separate from ANSI styling:

```haskell
data UpdateOutput
  = UpdatePlanOutput UpdatePlanView
  | UpdateAppliedOutput UpdateResultView
  | UpdateFailedOutput UpdateErrorView

renderUpdateHuman :: Bool -> UpdateOutput -> Text
encodeUpdateOutput :: UpdateOutput -> ByteString
```

The human plan groups version changes, input reuse, migrations, files, commands, and
warnings. Collapse unchanged files and skipped commands to counts by default; list every
conflict and every migration command caveat. `--json` prints one JSON document to stdout and
never emits color, progress bars, prompts, or informational prose there. Diagnostics and
clone progress go to stderr. Include an explicit schema version, outcome discriminator,
selected application IDs, every reconciliation classification/resolution, command
fingerprints/statuses, warnings, and error code. Golden-test both formats.

If EP-68 returns an identical-candidate no-op, print `Already up to date.` (or the JSON
equivalent), do not prompt, do not invoke apply, and do not request a commit. A changed
artifact with the same declared version is not called up to date: render the
`SameVersionContentChanged` warning next to its target/version before confirmation.

Build `Seihou.CLI.Update.Interaction` around EP-66 resolution types. For each unresolved
three-way conflict, print the path, baseline/current/generated labels, and a bounded diff3
preview, then accept one of: use generated, keep current, write conflict markers, or abort.
For an edited orphan, accept: delete, retain as tracked orphan, detach and keep as unmanaged,
or abort. Do not write during these questions. Return a fully resolved `UpdatePlan` to the
handler, or an abort. A normal TTY run asks one final `Apply? [Y/n]` question after all
resolutions; EOF, an invalid non-interactive input stream, or a negative answer leaves all
managed state unchanged.

Apply `--force` as a deterministic resolution pass before deciding whether interaction is
needed. It maps ordinary merge conflicts to use-generated and edited orphans to
retain-tracked. Binary/unmergeable conflicts follow the same use-generated choice only when
EP-66 marked replacement safe; otherwise they remain unresolved. Without a terminal,
unresolved plans fail before apply with an actionable list and non-zero exit.

After successful apply, use `Seihou.CLI.Git` (including `gitCheckIgnore`) and
`Seihou.CLI.CommitMessage` rather than creating a new Git wrapper. Stage only paths reported
by `UpdateResult`, plus the manifest, reachable baseline blobs, transaction cleanup if
tracked, and installed-cache paths only when they live inside the current repository.
Filter ignored paths consistently with `run` and `migrate`. A generated message must follow
Conventional Commits, for example `chore(seihou): update master-plan to 0.7.0`. A commit
failure reports an error but does not claim the already-successful update was rolled back.

Add parser/handler integration to `Seihou.CLI.Commands` and `Main`. Tests in
`seihou-cli/test/Seihou/CLI/UpdateRenderSpec.hs`, `UpdateInteractionSpec.hs`, and existing
command/parser specs must cover defaults, mutual exclusion, no-target selection, repeated
targets, variable parsing, force rules, declined confirmation, EOF, JSON silence, commit
path filtering, and exit status.

### Milestone 2: make the rest of the CLI teach the same lifecycle

Refactor `Seihou.CLI.StatusRender` so recommendation rows are derived from EP-64
applications. A recipe is displayed and updated by recipe target; its expanded modules do
not each produce identical migration/update actions. A module target with repeated
parameterized dependencies similarly gets one target action. Retain instance detail in the
applied-module section because it is useful diagnostics, but deduplicate the Recommended
Actions section by stable application ID. For schema-v3 legacy state, deduplicate by bare
module name and recommend an explicit one-time `seihou update <module>` seeding command.

When `status --check-updates` sees either an outdated artifact or a pending migration that
belongs to a recorded application, render `Run: seihou update <target>`. When several
applications are affected, also render `Run: seihou update`. Continue to report the exact
pending migration range and operation count; changing the recommended command must not hide
useful detail. Add tests for the current duplicate-instance bug, recipes, one dependency
shared by two applications, legacy manifests, and no pending work.

Update rich help and diagnostics in `Commands.hs`, `Run.hs`, `Upgrade.hs`, and
`PendingMigrations.hs`:

- describe `run` as applying a module for the first time or intentionally reconfiguring it;
- when a recorded application is pending, point at `seihou update <target>` before the
  lower-level migrate/run escape hatches;
- label `upgrade` as refreshing installed cache content without reconciling the current
  project, and point project users at `update`;
- preserve `migrate` as a focused/manual migration tool and document when it is still useful;
- ensure every example distinguishes source/cache version from project-applied version.

Keep old flags working for compatibility. If deprecation is desired after implementation
evidence, record it in this plan and schedule it separately; do not silently change their
semantics here.

### Milestone 3: publish references, mental model, and completion coverage

Add `docs/cli/update.md` as the complete command reference: synopsis, selection, saved input
precedence, automatic migrations, three-way merge model, conflict/orphan choices, command
policies, dry-run/JSON schemas, transaction and arbitrary-command limits, commit behavior,
legacy first update, examples, and exit codes. Link it from the `README.md` command table.

Revise `docs/cli/run.md`, `docs/cli/upgrade.md`, `docs/cli/migrate.md`,
`docs/cli/status.md`, `docs/user/getting-started.md`, `docs/user/migrations.md`, and the
incremental-generation sections of `docs/user/module-authoring.md`. Explain the lifecycle in
one consistent compact sequence:

```text
install source -> run once -> edit project -> update repeatedly
                       \-> migrate manually only for focused recovery
upgrade -> refresh shared cache only
```

Document `.seihou/baselines/` and transaction recovery without encouraging hand edits.
Explain that text merging uses prior generated content as base, current disk content as
ours, and new generated content as theirs. State plainly that binary conflicts require a
choice and arbitrary command side effects cannot be rolled back. Add the user-visible change
to `docs/user/CHANGELOG.md` under the unreleased section.

Update or add a proposed design note under
`docs/dev/design/proposed/project-aware-updates.md` to preserve architectural reasoning:
application identity, manifest v4 compatibility, content-addressed baselines, diff3 backend,
file reconciliation, receipts, staging/publication order, and limits. Once the implementation
ships, follow the repository's convention for moving proposed design notes to accepted
status if such a convention exists at that time; do not invent a new status system.

Exercise generated Bash, Zsh, and Fish completions and assert they contain `update`, its
option descriptions, and positional target completion behavior. Target suggestions should
come from recorded applications when the completion protocol makes the current project
available; otherwise do not add filesystem scanning solely for completion.

### Milestone 4: prove the complete workflow through the executable

Extend EP-68's local Git remote fixture into an executable acceptance spec under
`seihou-cli/test/Seihou/CLI/UpdateE2ESpec.hs`. It must run the built `seihou` executable in
an isolated project and isolated XDG config/cache directories, never the developer's real
installed cache. Publish a v1 module with a generated text file and command, install and run
it, edit a non-overlapping line in the project, publish v2 with a different generated line,
then invoke `seihou update <target>` with accepted confirmation.

Assert the final file contains both the user edit and the v2 generated edit without conflict
markers; the manifest records v2, the merged disk hash, and the v2 baseline; the unchanged
command did not execute again; source publication occurred only after success; and status no
longer recommends an update. Add sibling cases for an overlapping conflict resolved by keep
current, an edited orphan retained by `--force`, JSON dry-run with byte-for-byte unchanged
project/cache/manifest snapshots, failure before publication, and no-target update of two
recorded applications.

Capture one short human transcript matching the MasterPlan's vision. Treat wording and
spacing as a golden interface only where stable; assert semantic fields for dynamic paths,
hashes, and timings.


## Concrete Steps

Run all commands from the repository root
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

After Milestone 1, run focused update and CLI tests:

```bash
cabal test seihou-cli-test --test-options='--match "Update|command parser|completion"'
```

The focused transcript should end with no failures and include renderer, interaction, and
parser examples:

```text
... examples, 0 failures
```

After Milestone 2, run status, pending-migration, upgrade, and update tests:

```bash
cabal test seihou-cli-test --test-options='--match "Status|PendingMigration|Upgrade|Update"'
```

Verify the public help and a non-mutating JSON plan against the isolated fixture created by
the test helper:

```bash
cabal run seihou -- update --help
cabal run seihou -- update master-plan --dry-run --json
```

The help names changed-only commands and automatic migrations. The JSON command prints one
parseable document on stdout; the exact versions depend on the fixture, but its shape begins
like this:

```json
{"schemaVersion":1,"outcome":"plan","applications":["master-plan"]}
```

After Milestones 3 and 4, run the full repository gates already used by this project:

```bash
nix fmt -- --fail-on-change
cabal build all
cabal test all
nix flake check
```

Also run the documentation link checker or equivalent command documented in the repository
at implementation time. If no checker exists, use `rg` to verify every newly referenced
relative documentation path exists and record that limitation in Surprises & Discoveries.

Finally run the isolated executable acceptance spec without a name filter:

```bash
cabal test seihou-cli-test --test-options='--match "Update end-to-end"'
```

Record the successful test counts and the representative update transcript in Progress.


## Validation and Acceptance

The plan is complete only when all of the following behaviors are demonstrated:

- `seihou update <target>` reuses saved per-instance inputs, includes migrations, merges a
  non-overlapping user edit, skips an unchanged command, and publishes application/cache
  state after success.
- `seihou update` updates all recorded applications in manifest order, while repeated target
  arguments select and deduplicate the requested subset.
- An overlapping text edit is never silently overwritten without an explicit resolution or
  applicable `--force`; conflict markers identify baseline/current/generated sides.
- `--force` does not delete an edited orphan, and the result/status keeps that unresolved
  tracked state visible.
- A declined confirmation, EOF, dry-run, unresolved non-interactive conflict, plan error, or
  failed managed apply does not change the project, manifest, baseline store, or installed
  cache.
- Human output is grouped and concise; JSON stdout is one stable parseable document with no
  prompt/progress chatter, and failure has a machine-readable error code.
- an identical candidate exits successfully without confirmation or mutation; a changed
  same-version artifact is planned with a visible warning.
- Changed-only is the default, run-all and no-command are mutually exclusive, and command
  receipts are persisted only after successful execution.
- `--commit-message` stages only reported update paths and creates the requested commit;
  ordinary generated messages use Conventional Commits. Commit failure is reported without
  falsely reporting update rollback.
- Status produces one actionable recommendation per application and points project update
  work at `seihou update`; `upgrade` help unambiguously says cache-only.
- README, CLI references, user guides, changelog, design note, and all three shell completion
  outputs describe the shipped command and its safety limits.
- The full formatting, build, test, and flake gates pass from a clean worktree except for the
  intentional implementation changes.


## Idempotence and Recovery

Parser, renderer, documentation, and tests are safe to edit and rerun. The end-to-end fixture
must create fresh temporary project, remote, and XDG directories for every example and remove
only those known temporary paths through the test framework's cleanup mechanism. It must not
read from or write to the developer's actual installed-module cache.

An accepted `seihou update` inherits EP-66/EP-68 recovery. On startup the handler invokes the
service, which recovers or reports an incomplete `.seihou/transactions/` journal before
planning. A failed managed apply restores protected project/cache/manifest paths. The handler
must not attempt a second independent rollback. It reports any arbitrary command side effects
that could not be reversed and preserves the journal when automatic restoration is
incomplete.

If the update succeeds but optional Git commit creation fails, rerunning `seihou update`
should produce no file changes and skip unchanged commands; the user can commit the already
updated paths manually. If a conflict resolution is aborted, rerun the same command after
editing the file or choose a different resolution. Never instruct recovery by deleting the
manifest, baseline store, or transaction journal.


## Interfaces and Dependencies

No new package dependency is expected. Use the existing `optparse-applicative`, `aeson`,
terminal/style, Git/process, and test dependencies already present in the Cabal files. If an
implementation discovers a missing API, follow the repository's `mori` dependency lookup
rules before changing bounds or adding a package.

EP-68 must expose a bracketed session so candidate temporary directories remain alive across
rendering, interaction, and apply while always being cleaned afterward. The final boundary
may refine names, but must preserve this ownership shape:

```haskell
withProjectUpdate ::
  UpdateRequest ->
  (Either UpdateError UpdatePlan -> IO a) ->
  IO a

resolveUpdatePlan ::
  [ReconciliationResolution] ->
  UpdatePlan ->
  Either UpdateError UpdatePlan

applyProjectUpdate ::
  UpdatePlan ->
  IO (Either UpdateError UpdateResult)
```

`seihou-cli/src/Seihou/CLI/Update/Render.hs` exposes the human/JSON functions defined in
Milestone 1. `Seihou.CLI.Update.Interaction` exposes a pure decision fold plus an IO prompt
adapter, so invalid input and EOF are testable:

```haskell
data InteractionMode
  = Interactive
  | NonInteractive

resolveInteractively ::
  InteractionMode ->
  UpdatePlan ->
  IO (Either InteractionError UpdatePlan)
```

`UpdateResult` must expose the exact managed paths eligible for commit; EP-69 must not infer
them from a whole-worktree diff. `StatusRender` consumes EP-64 application IDs and EP-68-style
target selection rules, but it does not fetch or apply updates. `Commands.hs` owns only
parsing and help. `Main.hs` owns only dispatch. The executable `Update.hs` owns terminal IO,
confirmation, exit status, and optional commit glue; all semantic update work stays in the
private library.
