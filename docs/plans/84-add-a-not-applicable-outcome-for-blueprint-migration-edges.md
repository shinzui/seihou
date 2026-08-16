---
id: 84
slug: add-a-not-applicable-outcome-for-blueprint-migration-edges
title: "Add a not-applicable outcome for blueprint migration edges"
kind: exec-plan
created_at: 2026-08-16T14:16:39Z
intention: "intention_01m05ew4qbef6tn9bnphy4nv2n"
master_plan: "docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md"
---

# Add a not-applicable outcome for blueprint migration edges

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

`seihou agent migrate <blueprint> --from X --to Y` runs one AI agent session per declared
version edge and writes a *receipt* into `.seihou/manifest.json` after each session returns.
A later run skips any edge that already has a receipt, which is how an interrupted chain
resumes where it stopped.

Seihou can currently distinguish two outcomes: the provider session returned (receipt
written, edge never runs again) or the provider failed (no receipt, edge resumes). There is
a third outcome that real edges produce and neither box fits.

A well-written edge prompt states its own precondition, and when the project does not meet
it the correct action is to change nothing and say so. That happened while testing the
`adopt-architecture-decisions` blueprint's `0.6.0 -> 0.7.0` edge against
`mori://shinzui/rei`: the edge upgrades an ADR bundle pinned to an older tag, `rei` had
never adopted the bundle at all, and the agent correctly changed no file and reported that a
different command was the right entry point. The session returned successfully, so seihou
recorded:

```json
{
  "appliedAt": "2026-07-31T12:11:00.060261Z",
  "from": "0.6.0",
  "name": "adopt-architecture-decisions",
  "to": "0.7.0",
  "version": "0.7.0"
}
```

That receipt is indistinguishable from one written after a real upgrade. Once `rei` adopts
the bundle — which is exactly what the refusal told the user to do — the edge that *should*
then run is silently skipped, because its receipt already exists. No message, no diff.

After this plan, an edge can report that it was not applicable. Seihou records the attempt
with that outcome, prints the reason, continues the chain to the next edge, and does **not**
treat the edge as done on a later run. A user can see it directly: run a chain where one
edge's precondition is unmet, watch that edge report itself skipped, then satisfy the
precondition and re-run — the edge runs.

This matters to the initiative in
`docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md` because
fan-out makes "this edge does not apply to your project" the common case rather than the
exception. Once one blueprint's edges serve both projects that use a library directly and
projects that only see it through a wrapper, most runs of a given edge legitimately do
nothing.


## Progress

- [x] Read `AppliedBlueprintMigration`, the receipt writer, the skip predicate, and the prompt template (orientation, no edits). — 2026-08-16
- [x] Decide the signalling mechanism and record it in the Decision Log. — 2026-08-16
- [x] Add an outcome field to `AppliedBlueprintMigration` in `seihou-core/src/Seihou/Core/Types.hs`, with JSON encode/decode and a legacy default of "applied". — 2026-08-16
- [x] Narrow the skip predicate in `seihou-cli/src/Seihou/CLI/BlueprintMigration.hs` so only `applied` receipts suppress an edge. — 2026-08-16
- [x] Detect the not-applicable signal in `seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs` and record it, continuing the chain. — 2026-08-16
- [x] Teach the agent how to signal it, in `seihou-cli/data/blueprint-migration-prompt.md`. — 2026-08-16
- [x] Render the outcome in `seihou status` (`seihou-cli/src/Seihou/CLI/StatusRender.hs`). — 2026-08-16
- [x] Add tests for the predicate, the receipt round-trip, the signal parser, and the chain-continues behaviour. — 2026-08-16
- [x] Update `docs/user/blueprint-migrations.md`, `docs/user/blueprints.md`, `docs/cli/agent.md`, `docs/cli/status.md`, and `docs/user/CHANGELOG.md`. — 2026-08-16
- [x] Close IR-1 (`status: completed`) and update `docs/improvement-requests/log.md`. — 2026-08-16
- [x] Record `docs/adr/0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md`. — 2026-08-16


## Surprises & Discoveries

- **`hasAppliedBlueprintMigration` is a third comparison the plan did not name, and it had to
  move.** The plan named two: `writeAppliedBlueprintMigration`'s `sameEdge` (identity, outcome
  excluded) and `pendingBlueprintMigrations`'s `alreadyApplied` (suppression, outcome included).
  There is a third in `seihou-core/src/Seihou/Manifest/Types.hs`, whose Haddock promises it agrees
  with the completion key. It now requires an applied outcome, matching its own name. It has no
  production caller today — only `seihou-core/test/Seihou/Manifest/TypesSpec.hs` — but leaving it
  disagreeing with the predicate it documents itself against would have been a trap for the first
  plan to reach for it. **Consequence for EP-85 and EP-86:** there are three receipt comparisons in
  this codebase, not two, and only one of them ignores the outcome.

- **The plan's rule for the signal file makes an empty file mean "applied", which loses the
  signal.** The plan says to treat the file as a signal only when it "exists and is non-empty".
  Implemented as written, an agent that creates the file but writes nothing to it — a plausible
  tool-call failure mode — has its refusal recorded as a completed upgrade, which is the exact
  defect IR-1 filed. The file's *existence* is the deliberate act: it lives at a path only this
  command names, under `.seihou/`, and is deleted before every edge. So existence is the signal,
  and an empty one records `(no reason given)`.

- **`--debug` needs no special handling here, which is not true of `agent run`.** The MasterPlan's
  Surprises section warns that `agent run --debug` is not a dry run. `handleAgentMigrate`'s debug
  branch genuinely is: it returns before `runBlueprintMigrationsWith`, so nothing this plan added
  runs under it. Verified against the built binary — a debug migrate in a scratch project left
  `.seihou/` containing only `modules/`, with no manifest, no signal file, and no directory
  created. The signal path still renders into the prompt, which is the point: `--debug` is how an
  author checks that the framing prompt reads correctly.

- **`Data.Maybe.listToMaybe`, not `Data.List.find`, is what a "scan the last few lines" parser
  wants.** Trivial, but worth stating because the near-miss is expensive: an early version returned
  `Nothing` for a bare `SEIHOU: not-applicable` line with no reason, because the whole-word check
  read an *empty* remainder as "the token continues". The unit test for the placeholder case is
  what caught it; without that case the bug would have shipped and silently converted a
  reason-less refusal into a completed upgrade.


## Decision Log

- Decision: Record one outcome on the receipt (IR-1's shape 2), reached by two different signalling
  mechanics — a signal file for interactive providers, a `SEIHOU: not-applicable <reason>` marker
  line for API providers. Do not use a dedicated exit code (shape 3).
  Rationale: The three shapes are not alternatives; 2 is about what is recorded and 1 and 3 are
  about how it is signalled. What forces two mechanics is the provider asymmetry: `claude-cli` and
  `codex-cli` are spawned interactively and communicate only through an exit code, so seihou never
  sees a sentinel line in the transcript; `anthropic` and `openai` hand seihou the assistant text
  directly and have no process of the agent's to carry an exit code. A dedicated exit code was
  rejected outright rather than used for the interactive half, because an interactive session's
  exit code is the *shell session's*: a user who types `exit 3`, or whose terminal is killed, would
  forge the signal, and an agent that finishes normally cannot choose it. A file the agent writes
  with its own tools is a deliberate act, carries a reason, and is inspectable afterwards.
  Date: 2026-08-16

- Decision: Put the signal at `.seihou/.migrate-signal`, delete it before every edge and after
  reading it, and create `.seihou/` before the chain starts.
  Rationale: Under `.seihou/` rather than the working tree so a file left by a crashed run never
  appears in `git status`. Deleted before each edge so a stale signal cannot mark the next edge
  inapplicable, and after reading so it is never read twice; also cleared on a provider failure,
  because a failed session's signal is not that edge's answer. One path rather than a unique path
  per edge, since delete-before-launch makes reuse safe and a per-edge path would leave litter to
  clean up. `.seihou/` is created up front because the chain writes a manifest into it anyway, so
  this adds no side effect a run did not already have.
  Date: 2026-08-16

- Decision: Carry the reason inside `MigrationNotApplicable` rather than as a sibling
  `Maybe Text` field on the receipt.
  Rationale: The type then cannot express a reason for an applied edge or a skipped edge with no
  reason. The alternative needs an invariant maintained by every construction site, and this plan
  demonstrated that construction sites are easy to miss — EP-81 found four where it planned for
  three.
  Date: 2026-08-16

- Decision: Decode a missing `outcome` key as `MigrationApplied`; do not bump
  `currentManifestVersion` (it stays at 6).
  Rationale: The same reasoning EP-81 recorded for `origin`, and the MasterPlan's Integration Points
  require it. Every receipt written before this release recorded an edge whose session returned,
  which is exactly what `MigrationApplied` means, so reading it that way preserves its meaning
  rather than inventing one. ADR 0005's explicit-conversion rule exists for conversions that lose
  or relocate information; there is nothing here for a conversion command to recover, because
  nothing on disk distinguishes a completed upgrade from a deliberate no-op after the fact. The
  residual case — a pre-release receipt that was really a no-op stays wrong, with `--rerun` as its
  remedy — is stated in `docs/user/CHANGELOG.md`.
  Date: 2026-08-16

- Decision: Keep the outcome out of `writeAppliedBlueprintMigration`'s upsert key while putting it
  into `pendingBlueprintMigrations`'s suppression predicate and into
  `hasAppliedBlueprintMigration`.
  Rationale: The two comparisons answer different questions. The upsert asks "which receipt is this
  one replacing", and the answer must not depend on what happened, or an edge replanned after
  reporting itself inapplicable would accumulate a second receipt for the same edge and the ledger
  would carry two records disagreeing about one edge. The predicate asks "has this work happened",
  where the outcome is the whole point. This is the one place a receipt comparison deliberately
  ignores the outcome, and both sites now say so.
  Date: 2026-08-16

- Decision: Make the marker parser forgiving about formatting and strict about the marker — scan
  the last five non-empty lines, strip surrounding whitespace, backticks and emphasis, but require
  the line to *begin* with `SEIHOU:` and the token to end a word.
  Rationale: Models wrap things in backticks and bold and follow a signal with a closing sentence,
  so requiring the exact final line would miss real signals. But a false positive silently skips
  real work, which is strictly worse than a false negative here: an agent that meant to signal has
  a second channel (the signal file), while an agent that merely discussed applicability has no way
  to retract. So prose that mentions the words, a mid-sentence occurrence, and `not-applicable-ish`
  are all rejected.
  Date: 2026-08-16

- Decision: Write a new ADR
  (`docs/adr/0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md`) rather than amend an
  existing one.
  Rationale: EP-81 and EP-83 both amended (ADR 0002 and ADR 0003 respectively) because their
  decisions were the existing ones with a wider reach. This one is genuinely new: no existing ADR
  says anything about what a receipt's *outcome* vocabulary should be. ADR 0004 constrains where
  the outcome lives and ADR 0005 constrains how a receipt written before it is read, and 0007 cites
  both, but neither decides the question. The record also states the generalisation, since
  `mori://shinzui/keiro` carries a structurally identical request.
  Date: 2026-08-16


## Outcomes & Retrospective

Delivered as planned, with the deviations recorded in Surprises & Discoveries. All seven milestones
landed; `cabal test seihou-core-test` (1058 tests) and `cabal test seihou-cli-test` (516 tests) pass,
and `nix flake check` is green.

The acceptance criterion the plan names is proven end to end rather than by hand.
`seihou-cli/test/Seihou/CLI/AgentMigrateE2ESpec.hs` drives the real binary against a fake `claude`
on `PATH` that writes the signal file on its first launch only, and asserts the whole IR-1 scenario:
the first edge reports itself not applicable, the chain continues and runs the second, the manifest
records `(not-applicable, applied)`, the signal file is consumed, and the *same command with no
`--rerun`* then replans the first edge alone — which applies, replaces its own receipt in place, and
leaves the ledger at two entries. A third run reports the window settled. Before this change the
first edge would have been skipped forever.

Three things are worth carrying forward.

The provider asymmetry is the design constraint the plan correctly identified and it drove
everything: one recorded vocabulary, two mechanics, and a deliberate refusal to use the mechanism
(an exit code) that would have been forgeable by the user rather than chosen by the agent.

The parser's strictness is asymmetric on purpose, and the asymmetry has a reason that will outlive
this plan: an agent that meant to signal has a second channel, and an agent that merely discussed
applicability has none. Any future loosening should preserve that direction.

`docs/cli/status.md` documented neither the blueprint section nor the blueprint-migrations section
before this plan; both were added, since documenting the new outcome required a section for it to
live in.


## Context and Orientation

### Dependency on another plan

This plan **cannot be implemented before**
`docs/plans/81-record-artifact-origin-for-agent-applied-artifacts.md`. Both plans rewrite
`AppliedBlueprintMigration`, its two JSON instances, and the `alreadyApplied` predicate
inside `pendingBlueprintMigrations`. Landing them in either order works; landing them
concurrently means two plans editing the same predicate. Verify plan 81 is complete:

```bash
rg -n "origin :: !ArtifactOrigin" seihou-core/src/Seihou/Core/Types.hs
```

`AppliedBlueprintMigration` should already carry an `origin` field. If it does not, stop and
implement plan 81 first.

### What this repository is

Seihou is a project scaffolding system written in Haskell: a two-package Cabal workspace,
`seihou-core` (library, at `seihou-core/`) and `seihou-cli` (at `seihou-cli/`). The CLI
package is split into a library at `seihou-cli/src/` (package `seihou-cli-internal`) and an
executable at `seihou-cli/src-exe/`. New code goes in a library by default; the executable
holds `Main.hs`, command dispatchers, and modules needing `Options.Applicative`,
`Data.FileEmbed`, `GitHash`, or `Paths_seihou_cli`, plus anything transitively importing
one. `nix/check-cli-module-placement.sh` enforces this.

That convention matters here. `seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs` is
executable-only because it embeds the prompt template with `Data.FileEmbed`. The pure logic
it uses lives in `seihou-cli/src/Seihou/CLI/BlueprintMigration.hs`, which is deliberately
free of both `Options.Applicative` and `Data.FileEmbed` — that module accepts the template
text as an argument specifically so rendering policy stays testable in the library. Any new
pure logic in this plan (in particular, parsing the agent's signal) belongs in the library
module, not in the executable.

Records use strict fields, `Generic`, explicit deriving strategies, and are read and written
through `generic-lens` overloaded labels (`receipt ^. #outcome`), never record dot syntax
and never record update syntax. Modules using `#label` import `Data.Generics.Labels ()`.
`nix/check-record-conventions.sh` enforces this.

### Terms used in this plan

**Blueprint migration** — an agent-guided upgrade step a library author ships with a
blueprint. Each *edge* is a `(from, to)` version pair with a Markdown prompt describing the
source changes that version transition requires. Declared in `blueprint.dhall` under
`migrations`; see `docs/user/blueprint-migrations.md`.

**Receipt** — one `AppliedBlueprintMigration` value in the manifest's `blueprintMigrations`
list, recording that a specific edge's provider session returned. Its documented meaning,
which this plan preserves, is in `docs/user/blueprint-migrations.md` under "What a receipt
means": it is chain bookkeeping, not proof that the build passes.

**Provider** — the AI backend that runs a session: `claude-cli`, `codex-cli`, `anthropic`,
or `openai`. The first two spawn an interactive local process and communicate their outcome
only through an exit code; the last two are API calls whose assistant text seihou receives
directly. This asymmetry is the central design constraint of this plan.

### The record and the predicate today

After plan 81, in `seihou-core/src/Seihou/Core/Types.hs`:

```haskell
data AppliedBlueprintMigration = AppliedBlueprintMigration
  { name :: !ModuleName,
    origin :: !ArtifactOrigin,
    blueprintVersion :: !(Maybe Text),
    fromVersion :: !Text,
    toVersion :: !Text,
    appliedAt :: !UTCTime,
    agentSessionId :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)
```

In `seihou-cli/src/Seihou/CLI/BlueprintMigration.hs`, the skip predicate:

```haskell
pendingBlueprintMigrations rerun blueprintOrigin blueprintName receipts plan
  | rerun = plan ^. #steps
  | otherwise = filter (not . alreadyApplied) (plan ^. #steps)
  where
    alreadyApplied migration =
      any (\receipt -> sameArtifactIdentity (receipt ^. #origin) blueprintOrigin
              && receipt ^. #name == blueprintName
              && receipt ^. #fromVersion == migration ^. #from
              && receipt ^. #toVersion == migration ^. #to)
          receipts
```

And the chain runner in the same file:

```haskell
data BlueprintMigrationRunResult
  = BlueprintMigrationNoWork
  | BlueprintMigrationComplete [BlueprintMigration]
  | BlueprintMigrationLaunchFailed BlueprintMigration BlueprintMigrationLaunchFailure
  | BlueprintMigrationRecordFailed BlueprintMigration Text
  deriving stock (Eq, Show)

runBlueprintMigrationsWith ::
  (Int -> Int -> BlueprintMigration -> IO (Either BlueprintMigrationLaunchFailure ())) ->
  (BlueprintMigration -> IO (Either Text ())) ->
  [BlueprintMigration] ->
  IO BlueprintMigrationRunResult
```

The launch callback returns `Either failure ()`. There is no room in that type for a third
outcome; widening it is the core of milestone 2.

In `seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs`, `launchMigration` dispatches on provider:

```haskell
    launchInteractive systemPrompt = do
      exitCode <- launchConfiguredAgentAddingDirs ... systemPrompt (opts ^. #prompt)
      pure $ case exitCode of
        ExitSuccess -> Right ()
        failure -> Left (BlueprintMigrationProcessFailure failure)

    launchCompletion systemPrompt = do
      result <- runAgentCompletion (buildAgentCompletionRequestWith traceSink modelConfig systemPrompt (opts ^. #prompt))
      case result of
        Left err -> pure (Left (BlueprintMigrationProviderFailure err))
        Right assistantText -> do
          TIO.putStrLn assistantText
          pure (Right ())
```

Note the asymmetry: `launchCompletion` has the assistant's text; `launchInteractive` has
only an exit code.

### The prompt template

`seihou-cli/data/blueprint-migration-prompt.md` is embedded at compile time with
`Data.FileEmbed.embedFile` and rendered per edge. It already contains a "Workflow" section
telling the agent to inspect real usage before assuming an API exists, to change only what
this edge requires, to preserve unrelated changes, and to summarize before exiting; and a
"Completion Boundary" section explaining that the receipt is not package-manager
verification. This is where the agent must be taught to signal inapplicability — IR-1 is
explicit that the framing guidance should carry it so edge authors do not each invent a
convention.

### Where receipts are displayed

`seihou-cli/src/Seihou/CLI/StatusRender.hs`, `formatBlueprintMigrations`, renders:

```text
Blueprint migrations:
  my-library v0.3.0: 1.0.0 -> 2.0.0 (applied 2026-07-20 15:02 UTC)
```

### Relevant ADRs

- `docs/adr/0004-the-manifest-is-the-only-record-of-applied-state.md` — there is no
  lockfile; the manifest is the single record of what was applied. This is why the outcome
  must be recorded in the manifest rather than in a side file or inferred at read time.
- `docs/adr/0005-legacy-manifests-convert-through-an-explicit-command.md` — legacy manifests
  convert through an explicit command rather than silently. It constrains how a receipt
  written before the outcome field existed is read: see the decision in milestone 1.

`docs/adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md` and
`docs/adr/0002-artifact-identity-is-origin-url-plus-name.md` are background: they explain
why the record is shaped the way it is, but nothing in this plan changes identity.

`docs/adr/` is a plain filesystem corpus, not a profile-governed OKF bundle — `mori.dhall`
registers only `docs/improvement-requests`. Keep the `NNNN-slug.md` convention, the
`# ADR NNNN — Title` heading, and `Status` / `Date` lines. Do not add OKF frontmatter.

No cross-repository ADR governs this work. IR-1 notes that
`mori://shinzui/keiro` has a structurally identical request — an explicit terminal rejection
outcome so an intentional refusal can be finalized without being misreported as success —
but that is a separate system with its own decisions.

### The Improvement Request this implements

`docs/improvement-requests/add-a-not-applicable-outcome-for-blueprint-migration-edges.md`
(IR-1). Read it in full before starting. It lays out three candidate mechanisms and argues
for the second, and it explains why the obvious workarounds — `--rerun`, exiting nonzero,
narrowing the version window — each fail.


## Plan of Work

### Decision required before coding: how an edge signals

IR-1 offers three shapes. Evaluate them against the provider asymmetry described above.

1. **A sentinel line in the agent's output**, for example a final line
   `SEIHOU: not-applicable <reason>`. Works directly for `anthropic` and `openai`, where
   seihou has the assistant text. For `claude-cli` and `codex-cli` seihou spawns an
   interactive process and never sees the transcript, so a sentinel in the conversation is
   invisible to it.
2. **A distinct receipt status.** This is about what is *recorded*, not how it is signalled,
   so it is orthogonal to (1) and (3) rather than an alternative. IR-1 prefers it, and it is
   right: recording the attempt preserves the audit trail, which is better than writing
   nothing.
3. **A dedicated exit code.** Works for the two CLI providers, which is precisely where (1)
   fails, and is meaningless for the two API providers, where the process is seihou itself.

So the answer is **(2) plus both (1) and (3)**: one recorded outcome, reached by whichever
signal the provider can carry.

Decide and record this: a **sentinel file** is the mechanism for interactive providers.
Seihou creates a per-edge scratch path, tells the agent in the prompt to write a one-line
reason into that file if the edge does not apply, and reads it after the process exits. This
beats a dedicated exit code because an interactive agent session's exit code is the *shell
session's* exit code — a user who types `exit 3` or whose terminal is killed would forge the
signal, and an agent that finishes normally cannot choose it. A file the agent writes with
its own tools is a deliberate act by the agent, carries a reason, and is inspectable
afterwards.

For API providers, parse the sentinel line out of the assistant text with the same
vocabulary, so the prompt can describe one convention with two mechanics: "if this edge does
not apply, write the reason to `$SEIHOU_NOT_APPLICABLE_FILE`; if you cannot write files, end
your reply with a line `SEIHOU: not-applicable <reason>`."

Put the scratch file under the project's `.seihou/` directory (for example
`.seihou/.migrate-signal`), delete it before each edge launches so a stale file cannot leak
into the next edge, and delete it after reading. Do not put it in the working tree root
where it would show up in `git status`.

Record all of this in the Decision Log, including the rejected dedicated-exit-code option
and why.

### Milestone 1 — the recorded outcome

At the end of this milestone the manifest can express three outcomes and the skip predicate
respects them. Nothing yet produces the new value.

In `seihou-core/src/Seihou/Core/Types.hs`, add:

```haskell
-- | What actually happened when seihou ran one blueprint migration edge.
--
-- 'MigrationApplied' means the provider interaction returned. As
-- @docs\/user\/blueprint-migrations.md@ states, that is bookkeeping and not
-- proof that the build passes.
--
-- 'MigrationNotApplicable' means the edge reported that its precondition is
-- unmet in this project and it deliberately changed nothing. The attempt is
-- recorded so the audit trail is complete, but it does not suppress a later
-- run: the precondition may be met by then.
data MigrationOutcome
  = MigrationApplied
  | MigrationNotApplicable !Text
  deriving stock (Eq, Show, Generic)
```

Carry the reason inside the constructor rather than as a separate `Maybe Text` field, so the
type makes it impossible to record a reason for an applied edge or omit one for a skipped
edge.

Add `outcome :: !MigrationOutcome` to `AppliedBlueprintMigration`, after `toVersion`.

In `seihou-core/src/Seihou/Manifest/Types.hs`, encode it. Follow the shape `ArtifactOrigin`
already uses — a nested object with a discriminator — rather than a bare string, so the
reason has somewhere to live:

```json
"outcome": { "status": "applied" }
"outcome": { "status": "not-applicable", "reason": "the project has not adopted the bundle" }
```

Decode a missing `outcome` key as `MigrationApplied`, matching plan 81's treatment of a
missing `origin` and every other optional field added to this manifest. Keep
`currentManifestVersion` at whatever plan 81 left it. Record the rationale: every receipt
written before this release *was* an applied receipt as far as seihou knew, so reading it
that way is the honest default and there is nothing a conversion command could recover.
Note the consequence plainly in the changelog — a receipt written for what was really an
inapplicable edge stays wrong, and `--rerun` remains the remedy for those.

In `seihou-cli/src/Seihou/CLI/BlueprintMigration.hs`, narrow `alreadyApplied` so only
`MigrationApplied` receipts suppress an edge:

```haskell
    alreadyApplied migration =
      any
        ( \receipt ->
            receipt ^. #outcome == MigrationApplied
              && sameArtifactIdentity (receipt ^. #origin) blueprintOrigin
              && ...
        )
        receipts
```

Update the function's Haddock so it names the outcome as part of the decision, alongside the
existing sentence about origin and the deliberate exclusion of versions and timestamps.

`writeAppliedBlueprintMigration` in `seihou-core/src/Seihou/Manifest/Types.hs` upserts on
`(origin, name, from, to)`. Leave that key alone: outcome is *not* part of identity, so
re-running an edge that was previously not-applicable replaces the old receipt rather than
appending a second one. That is the desired behaviour and worth a comment saying so, because
it is the one place where outcome is deliberately excluded from a comparison.

### Milestone 2 — carrying the signal through the chain

At the end of this milestone the runner can distinguish three outcomes and continues past a
not-applicable edge.

In `seihou-cli/src/Seihou/CLI/BlueprintMigration.hs`, widen the launch callback's result:

```haskell
-- | What one edge's provider interaction produced.
data BlueprintMigrationLaunchResult
  = BlueprintMigrationSessionReturned
  | BlueprintMigrationSessionNotApplicable !Text
  deriving stock (Eq, Show)

runBlueprintMigrationsWith ::
  (Int -> Int -> BlueprintMigration -> IO (Either BlueprintMigrationLaunchFailure BlueprintMigrationLaunchResult)) ->
  (BlueprintMigration -> MigrationOutcome -> IO (Either Text ())) ->
  [BlueprintMigration] ->
  IO BlueprintMigrationRunResult
```

The record callback now takes the outcome, so the caller writes one receipt shape for both
cases and the runner stays free of manifest knowledge.

Extend `BlueprintMigrationRunResult` so the summary can tell the user what happened. Replace
`BlueprintMigrationComplete [BlueprintMigration]` with a variant carrying each edge and its
outcome, so `handleRunResult` can print, for example:

```text
Completed 3 blueprint migration(s) for 'keiro-upgrade' (1 not applicable).
```

Keep the failure variants as they are: a not-applicable edge is neither a failure nor a
reason to stop, so the chain proceeds to the next edge exactly as it does after a successful
one. This is the behavioural heart of the plan — IR-1 explicitly rejects exiting nonzero
because it "halts a multi-edge chain that should have continued past an inapplicable step".

Add the pure signal parser here too, in the library module where it can be tested:

```haskell
-- | Extract a not-applicable signal from an API provider's assistant text.
-- Recognises a trailing line of the form @SEIHOU: not-applicable <reason>@,
-- tolerating surrounding whitespace and Markdown emphasis the model may add.
parseNotApplicableSignal :: Text -> Maybe Text
```

Be forgiving about formatting and strict about the marker: models wrap things in backticks
and bold. Scan the last few non-empty lines rather than only the final one, strip Markdown
punctuation, and require the literal `SEIHOU:` prefix and the `not-applicable` token. Return
the remainder as the reason, or a fixed placeholder when the reason is empty. Do not attempt
to interpret free-form prose as a refusal; a false positive here silently skips real work.

### Milestone 3 — wiring the two provider paths

At the end of this milestone both interactive and API providers can report a
not-applicable edge, and `seihou agent migrate` records it.

In `seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs`:

Before each edge launches, compute the signal path (`.seihou/.migrate-signal` relative to
the project root) and delete any existing file at it. Pass the absolute path into the prompt
rendering as a new template variable.

`launchInteractive` — after the process exits with `ExitSuccess`, read the signal file. If
it exists and is non-empty, return `BlueprintMigrationSessionNotApplicable` with its trimmed
contents; otherwise return `BlueprintMigrationSessionReturned`. A non-zero exit still means
failure, unchanged. Delete the file after reading, in both cases.

`launchCompletion` — after printing the assistant text, run `parseNotApplicableSignal` over
it. Also check the signal file, since an API provider given tool access might write it.

`recordMigration` — take the `MigrationOutcome` and set the receipt's `outcome` field. When
the outcome is `MigrationNotApplicable`, print the reason before moving to the next edge, so
the user sees it in the terminal and not only in the manifest:

```text
Blueprint migration 1/3: 1.0.0 -> 2.0.0 — not applicable: the project has not adopted the bundle
```

### Milestone 4 — teaching the agent

At the end of this milestone the framing prompt describes the convention, so edge authors do
not have to.

Edit `seihou-cli/data/blueprint-migration-prompt.md`. Add a section after "Workflow" and
before "Completion Boundary", using the same voice as the surrounding text:

```markdown
## If This Edge Does Not Apply

An edge states its own precondition. If this project does not meet it — the library is
not used here, the feature this edge upgrades was never adopted, the change is already
present — the correct action is to change nothing and report that.

Do not make speculative edits to justify the step, and do not exit with an error: an
error means the provider failed, halts the remaining edges, and asks the user to retry.

To report it, write one line explaining why to:

{{not_applicable_signal_path}}

If you cannot write files, end your reply with a line of exactly this form:

    SEIHOU: not-applicable <one-line reason>

Seihou records the attempt with that outcome, prints your reason, and continues to the
next edge. The edge is not marked done, so it will run again once the precondition is met.
```

Then amend "Completion Boundary" so it no longer implies only two outcomes.

`renderBlueprintMigrationSystemPrompt` in `seihou-cli/src/Seihou/CLI/BlueprintMigration.hs`
substitutes template variables through a list of `(name, value)` pairs; add
`not_applicable_signal_path` to that list. Its type gains the path as a parameter — keep it
pure and pass the path in, exactly as the template text itself is passed in rather than
embedded.

### Milestone 5 — visibility in `seihou status`

`formatBlueprintMigrations` in `seihou-cli/src/Seihou/CLI/StatusRender.hs` renders one line
per receipt ending in `(applied <timestamp>)`. Render the not-applicable case distinctly:

```text
Blueprint migrations:
  keiro-upgrade v0.3.0: 1.0.0 -> 2.0.0 (applied 2026-08-16 15:02 UTC)
  keiro-upgrade v0.3.0: 2.5.0 -> 3.0.0 (not applicable 2026-08-16 15:19 UTC — no direct kiroku imports)
```

Truncate a long reason rather than wrapping; `seihou status` is a scannable summary and the
full reason is in the manifest. This is what IR-1 means by "keeps `seihou status` honest".

### Milestone 6 — tests

The CLI test suite is at `seihou-cli/test/`, run with `cabal test seihou-cli-test`, using
`tasty` with `hspec` via `Test.Tasty.Hspec.testSpec`. Each spec module exports
`tests :: IO TestTree` and is registered in the suite's `Main.hs`.

Extend `seihou-cli/test/Seihou/CLI/BlueprintMigrationSpec.hs`:

- a `MigrationApplied` receipt suppresses its edge;
- a `MigrationNotApplicable` receipt for the *same* edge does **not** suppress it — this is
  the defect IR-1 filed, and it is the single most important assertion in the plan;
- `runBlueprintMigrationsWith` continues to the next edge after a not-applicable result, and
  the final result reports both counts. Drive it with pure stub callbacks, which is what the
  existing tests in that file already do.
- `parseNotApplicableSignal` accepts the plain form, a backticked form, a bolded form, and a
  form with trailing whitespace; and rejects prose that merely mentions the words, an empty
  string, and a line missing the `SEIHOU:` prefix.

Extend `seihou-cli/test/Seihou/CLI/AppliedBlueprintMigrationSpec.hs`:

- a not-applicable receipt round-trips through `manifestToJSON` / `manifestFromJSON` with
  its reason intact;
- a receipt with no `outcome` key decodes as `MigrationApplied`;
- re-recording an edge that was not-applicable replaces the receipt in place rather than
  appending a duplicate.

Add an end-to-end case to `seihou-cli/test/Seihou/CLI/AgentMigrateE2ESpec.hs` if that spec
can drive a stubbed provider: a two-edge chain where the first edge writes the signal file
must run the second edge and leave the first unrecorded as applied. Read that spec first to
see how it avoids launching a real provider; a test must never start an interactive `claude`
or `codex` session.

### Milestone 7 — documentation and IR bookkeeping

`docs/user/blueprint-migrations.md` is the main surface. Update:

- "How a migration runs" — the per-edge step now has three outcomes.
- "For library authors / Write an edge prompt" — tell authors to state the edge's
  precondition explicitly, and that seihou's own framing tells the agent how to report an
  unmet one. This is the paragraph that makes the feature usable.
- "What a receipt means" — describe both outcomes and what each implies for a later run.
- "Resume, repeat, and re-run" — a not-applicable edge is re-planned without `--rerun`.
- The Troubleshooting table — add the message a user sees.

`docs/cli/agent.md` — under `agent migrate`, note the third outcome and that it does not
halt the chain.

`docs/cli/status.md` — show the new rendering.

`docs/user/CHANGELOG.md` — an entry. State the one-time caveat: receipts written before this
release are all read as applied, including any that were really deliberate no-ops, and
`--rerun` remains the remedy for those.

Update `docs/improvement-requests/add-a-not-applicable-outcome-for-blueprint-migration-edges.md`:
set `status: implemented` and add a closing section naming this plan and which of its three
proposed shapes was chosen. That bundle is a profile-governed OKF bundle registered in
`mori.dhall`; maintain its reserved `log.md` with `okf log add` and validate:

```bash
okf validate docs/improvement-requests \
  --strict \
  --profile docs/improvement-requests/profile.dhall \
  --profile-enforce \
  --log-enforce
```


## Concrete Steps

Run everything from the repository root,
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

Confirm the prerequisite:

```bash
rg -n "origin :: !ArtifactOrigin" seihou-core/src/Seihou/Core/Types.hs
```

Orient:

```bash
rg -n "pendingBlueprintMigrations|runBlueprintMigrationsWith|BlueprintMigrationRunResult" --glob '*.hs'
rg -n "recordMigration|launchInteractive|launchCompletion" seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs
sed -n '1,40p' seihou-cli/data/blueprint-migration-prompt.md
```

Build and test after each milestone:

```bash
cabal build all
cabal test seihou-cli-test
cabal test seihou-core-test
```

Inspect the rendered prompt without contacting a provider — this is how to check milestone 4
by eye:

```bash
seihou agent --debug migrate <blueprint> --from 1.0.0 --to 2.0.0
```

Full checks before committing:

```bash
nix flake check
```

Commit with all three trailers:

```text
feat(agent): let a migration edge report that it does not apply

Record a third outcome alongside applied and failed, so a deliberate no-op
no longer writes a receipt that suppresses the edge once its precondition
is met. The chain continues past it.

MasterPlan: docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md
ExecPlan: docs/plans/84-add-a-not-applicable-outcome-for-blueprint-migration-edges.md
Intention: intention_01m05ew4qbef6tn9bnphy4nv2n
```


## Validation and Acceptance

**Automated.** Both test suites pass. The decisive assertion: given a plan containing edge
`0.6.0 -> 0.7.0` and a receipt for that exact edge with outcome not-applicable,
`pendingBlueprintMigrations` returns the edge. Given the same receipt with outcome applied,
it does not.

**By hand — the IR-1 scenario, reproduced and fixed.** Author a throwaway blueprint with two
edges. Write the first edge's prompt so its precondition is obviously unmet in a scratch
project — for instance, "if this project has no `docs/adr/` directory, this edge does not
apply" — and follow the convention the framing prompt now describes. Write the second edge
to make a trivial visible change.

```bash
seihou agent migrate scratch-upgrade --from 1.0.0 --to 3.0.0
```

Expected: the first edge reports not applicable with its reason, the chain continues, the
second edge runs. Then:

```bash
cat .seihou/manifest.json | jq '.blueprintMigrations'
```

```json
[
  {
    "name": "scratch-upgrade",
    "origin": { "kind": "remote", "url": "file:///tmp/scratch", "artifact": "scratch-upgrade" },
    "from": "1.0.0",
    "to": "2.0.0",
    "outcome": { "status": "not-applicable", "reason": "no docs/adr directory in this project" },
    "appliedAt": "2026-08-16T15:19:00Z"
  },
  {
    "name": "scratch-upgrade",
    "origin": { "kind": "remote", "url": "file:///tmp/scratch", "artifact": "scratch-upgrade" },
    "from": "2.0.0",
    "to": "3.0.0",
    "outcome": { "status": "applied" },
    "appliedAt": "2026-08-16T15:21:00Z"
  }
]
```

Now satisfy the precondition — `mkdir -p docs/adr` — and re-run the same command **without**
`--rerun`:

```bash
seihou agent migrate scratch-upgrade --from 1.0.0 --to 3.0.0
```

The first edge runs; the second is skipped as already applied. Before this change the first
edge would have been skipped forever. That is the acceptance criterion.

**`seihou status`** shows both receipts with distinguishable outcomes.

**No false positives.** Run an edge whose agent writes a normal summary mentioning the words
"not applicable" in prose without the sentinel. It must be recorded as applied. A parser
that skips real work on prose is worse than no parser.


## Idempotence and Recovery

All source edits; rebuilding and re-testing is safe to repeat.

The runtime change is additive: a chain that produces no not-applicable signals behaves
exactly as before. Existing manifests are readable unchanged, with every receipt read as
applied.

The signal file is transient state and must be treated as such. Delete it before each edge
so a stale file from a crashed run cannot mark the next edge inapplicable, and delete it
after reading. If implementation makes deletion-before-launch awkward, prefer a unique path
per edge over reusing one, but keep it inside `.seihou/` and out of `git status`. Add it to
the repository's generated `.gitignore` guidance if `docs/user/` documents one.

If a not-applicable receipt is recorded and the user disagrees — the agent was wrong, the
edge did apply — the remedy is `--rerun`, unchanged and already documented. If an applied
receipt was recorded for what was really a no-op (any receipt predating this release),
`--rerun` is likewise the remedy; that is the residual case this plan cannot retroactively
fix, and the changelog must say so.

If work stops mid-plan, the safe stopping points are the end of milestone 1 (the field
exists and is respected, nothing produces it) and the end of milestone 2 (the runner handles
it, nothing signals it). Do not stop after milestone 4 with milestone 3 incomplete: a prompt
that tells the agent to write a signal file seihou does not read would silently lose
outcomes.


## Interfaces and Dependencies

No new library dependencies.

At the end of the plan these must exist.

`seihou-core/src/Seihou/Core/Types.hs`

```haskell
data MigrationOutcome
  = MigrationApplied
  | MigrationNotApplicable !Text
  deriving stock (Eq, Show, Generic)

data AppliedBlueprintMigration = AppliedBlueprintMigration
  { name :: !ModuleName,
    origin :: !ArtifactOrigin,
    blueprintVersion :: !(Maybe Text),
    fromVersion :: !Text,
    toVersion :: !Text,
    outcome :: !MigrationOutcome,
    appliedAt :: !UTCTime,
    agentSessionId :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)
```

`seihou-cli/src/Seihou/CLI/BlueprintMigration.hs`

```haskell
data BlueprintMigrationLaunchResult
  = BlueprintMigrationSessionReturned
  | BlueprintMigrationSessionNotApplicable !Text
  deriving stock (Eq, Show)

parseNotApplicableSignal :: Text -> Maybe Text

runBlueprintMigrationsWith ::
  (Int -> Int -> BlueprintMigration -> IO (Either BlueprintMigrationLaunchFailure BlueprintMigrationLaunchResult)) ->
  (BlueprintMigration -> MigrationOutcome -> IO (Either Text ())) ->
  [BlueprintMigration] ->
  IO BlueprintMigrationRunResult

renderBlueprintMigrationSystemPrompt ::
  Text ->        -- embedded template
  FilePath ->    -- absolute path of the not-applicable signal file
  AgentContext ->
  PreparedBlueprintExecution ->
  Int -> Int -> BlueprintMigration -> Text
```

Hard dependency: `docs/plans/81-record-artifact-origin-for-agent-applied-artifacts.md`.

`docs/plans/85-fan-out-a-blueprint-migration-edge-to-entailed-cohort-edges.md` hard-depends
on this plan and consumes these shapes directly: it calls the runner with steps owned by
several different blueprints, and it relies on a not-applicable outcome so an entailed edge
that does not apply to the current project does not write an applied receipt that would then
suppress the same edge when reached from its own blueprint. When implementing plan 85, do
not narrow `runBlueprintMigrationsWith`'s outcome vocabulary.
