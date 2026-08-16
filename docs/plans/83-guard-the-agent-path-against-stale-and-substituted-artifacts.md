---
id: 83
slug: guard-the-agent-path-against-stale-and-substituted-artifacts
title: "Guard the agent path against stale and substituted artifacts"
kind: exec-plan
created_at: 2026-08-16T14:16:37Z
intention: "intention_01m05ew4qbef6tn9bnphy4nv2n"
master_plan: "docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md"
---

# Guard the agent path against stale and substituted artifacts

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Seihou refuses to generate files from an artifact that is older than, or came from a
different repository than, what the project's manifest records. That refusal is implemented
in `seihou-cli/src/Seihou/CLI/ManifestGuard.hs` and is consulted by `seihou run`,
`seihou migrate`, `seihou manifest upgrade`, and `seihou status`.

It is not consulted by `seihou agent run` or `seihou agent migrate`. Neither command is
read-only. `seihou agent run` applies the blueprint's baseline modules to the working
directory before the agent session starts — those are ordinary modules generating ordinary
files — and then writes a provenance record into `.seihou/manifest.json`. `seihou agent
migrate` writes a receipt per migration edge, and those receipts suppress future runs of the
edges they name.

So both failures the guard exists to stop are reachable on the agent path. A developer whose
installed blueprint lags behind what the project records regenerates the older baseline and
rewrites the manifest to name the older version — the guard would have refused the same
thing under `seihou run`. And a blueprint resolving to a name installed from a *different*
repository is a different blueprint: its baseline modules are different modules, and on the
migrate path its edges are silently dropped as already-applied.

After this plan, both agent commands consult the same guard, refuse on the same terms, and
accept the same `--allow-downgrade` override that prints what it overrides. A user can see
it directly: install an older copy of a blueprint than the manifest records, run
`seihou agent run`, and the command stops before writing anything instead of quietly
applying the older baseline.

This is a prerequisite for the fan-out work in
`docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md`, where one
command resolves several blueprints from several repositories by bare name and the cost of
resolving the wrong one rises accordingly.


## Progress

- [ ] Read `ManifestGuard`, the `seihou run` guard call, and both agent entry points (orientation, no edits).
- [ ] Generalise `checkAppliedArtifactsFor` so it can check a recorded blueprint as well as recorded modules.
- [ ] Add `allowDowngrade` to `BlueprintRunOpts` and `BlueprintMigrationOpts` and parse `--allow-downgrade` for both agent subcommands.
- [ ] Insert the guard into `seihou agent run` before `applyBaseline`, covering the blueprint and its resolved base modules.
- [ ] Insert the guard into `seihou agent migrate` before planning edges.
- [ ] Keep `--debug` free of any check on both commands.
- [ ] Add tests: refusal leaves the tree byte-identical; override prints and proceeds; debug checks nothing.
- [ ] Update `docs/cli/agent.md`, `docs/user/blueprints.md`, `docs/user/blueprint-migrations.md`, and `docs/user/CHANGELOG.md`.
- [ ] Consider whether ADR 0003 should be amended to name the agent path; record the decision.
- [ ] Mark IR-3 `status: implemented` and update `docs/improvement-requests/log.md`.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: ...
  Rationale: ...
  Date: ...


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

### Dependency on another plan

This plan **cannot be implemented before**
`docs/plans/81-record-artifact-origin-for-agent-applied-artifacts.md`. That plan adds an
`origin :: !ArtifactOrigin` field to `AppliedBlueprint` and `AppliedBlueprintMigration`.
Until it lands, the manifest's agent-path records carry a bare name and there is no recorded
origin to compare a local copy against — the guard could detect the staleness half of the
problem and none of the substitution half. Verify before starting:

```bash
rg -n "origin :: !ArtifactOrigin" seihou-core/src/Seihou/Core/Types.hs
```

You should see it on `AppliedModule`, `AppliedBlueprint`, and `AppliedBlueprintMigration`.
If it is only on `AppliedModule`, stop and implement plan 81 first.

This plan is also easier to exercise if
`docs/plans/82-refuse-to-overwrite-an-installation-from-a-different-source.md` has landed,
because that plan makes the substituted state require a deliberate `--force` rather than
being reachable by accident. It is not a hard requirement.

### What this repository is

Seihou is a project scaffolding system written in Haskell: a two-package Cabal workspace,
`seihou-core` (library, at `seihou-core/`) and `seihou-cli` (at `seihou-cli/`). The CLI
package is split into a library at `seihou-cli/src/` (package `seihou-cli-internal`) and an
executable at `seihou-cli/src-exe/`. New code goes in a library by default; the executable
holds `Main.hs`, command dispatchers, and modules needing `Options.Applicative`,
`Data.FileEmbed`, `GitHash`, or `Paths_seihou_cli`, plus anything transitively importing
one. `nix/check-cli-module-placement.sh` enforces it. Both agent entry points
(`seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`, `seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs`)
are already executable-only because they import `Seihou.CLI.Commands`, which is trapped there
by `Options.Applicative`. `ManifestGuard` lives in the CLI library and stays there.

Records use strict fields, `Generic`, explicit deriving strategies, and are read and written
through `generic-lens` overloaded labels (`opts ^. #allowDowngrade`), never record dot syntax
and never record update syntax. Modules using `#label` import `Data.Generics.Labels ()`.
`nix/check-record-conventions.sh` enforces this.

### Terms used in this plan

**Manifest** — `.seihou/manifest.json`, checked into the project's git repository, recording
what the project has applied.

**Blueprint** — an agent-driven runnable, described by a `blueprint.dhall`. Unlike a module
it produces non-deterministic output: its prompt guides an AI coding agent that decides what
files to write. It cannot be run by `seihou run`; the entry points are `seihou agent run` and
`seihou agent migrate`.

**Baseline modules** — the `baseModules` list on a blueprint. Before rendering the prompt,
`seihou agent run` applies these as ordinary modules, generating ordinary files. This is the
half of a blueprint run that is fully deterministic and is exactly what `seihou run` guards.

**The guard** — `Seihou.CLI.ManifestGuard`. Its pure core is:

```haskell
judgeArtifact ::
  ArtifactOrigin ->   -- recorded origin, from the manifest
  Maybe Text ->       -- recorded version, from the manifest
  ArtifactOrigin ->   -- origin of the copy found on this machine
  Maybe Text ->       -- version of the copy found on this machine
  ArtifactVerdict
```

and its verdicts are `ArtifactOk`, `ArtifactStale`, `ArtifactOriginMismatch`,
`ArtifactUnresolvable`, `ArtifactVersionIncomparable`, and `ArtifactUnverifiableOrigin`.
`blockingChecks` keeps only the three that should stop a command: stale, origin mismatch,
and unresolvable. The other two are reported but never block, because neither is evidence of
a problem — only evidence that seihou cannot prove there isn't one.

The IO shell is:

```haskell
checkAppliedArtifactsFor ::
  FilePath ->              -- absolute project root
  [FilePath] ->            -- search paths, normally defaultSearchPaths
  Maybe (Set ModuleName) -> -- Nothing = every applied module; Just = this subset
  Manifest ->
  IO [ArtifactCheck]
```

Note what it iterates: `manifest ^. #modules`, the applied *modules*. It has no notion of a
recorded blueprint. Extending it is milestone 1.

Rendering is `formatGuardRefusal` (the refusal, ending with the `--allow-downgrade`
instruction) and `formatGuardOverride` (the same blocks under a "proceeding anyway"
lead-in).

### How `seihou run` uses it — the pattern to copy

In `seihou-cli/src-exe/Seihou/CLI/Run.hs` around line 288:

```haskell
  projectRoot <- getCurrentDirectory
  searchPaths <- defaultSearchPaths
  guardChecks <-
    checkAppliedArtifactsFor projectRoot searchPaths (Just composedModuleNames) initialManifest
  enforceArtifactGuard runOpts (blockingChecks guardChecks)
```

and around line 704:

```haskell
enforceArtifactGuard :: RunOpts -> [ArtifactCheck] -> IO ()
enforceArtifactGuard _ [] = pure ()
enforceArtifactGuard runOpts blocking
  | runOpts ^. #allowDowngrade = TIO.putStr (formatGuardOverride blocking)
  | otherwise = do
      TIO.putStr (formatGuardRefusal blocking)
      exitFailure
```

Two properties are load-bearing and must be preserved on the agent path. First, the check
runs *before* anything is written, so a refusal leaves the working tree and manifest
byte-identical. Second, it is scoped to the artifacts this run will actually use — the
`Just composedModuleNames` filter — so a stale artifact unrelated to the command does not
block it.

### The two entry points to change

`seihou-cli/src-exe/Seihou/CLI/AgentRun.hs` — `handleAgentRun`. Around line 175 it decides
whether to apply the baseline:

```haskell
          else applyBaseline level opts (bp ^. #baseModules) cliOverrides resolved
```

and around line 200 it writes the provenance record with `recordAppliedBlueprint`. The
module already imports `detectArtifactOrigin` and already calls `getCurrentDirectory` at
line 297 inside `applyBaseline`. The guard must run before line 175.

`seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs` — `handleAgentMigrate`. The sequence is:
discover the blueprint (line 71), validate it (72), resolve the agent config (80), parse
`--from` and `--to` (87–88), plan the chain (89), read receipts (100), filter out recorded
edges (101), then either print the debug output or launch and record. The guard must run
before planning, so a substituted blueprint is refused rather than having its edges silently
dropped as already-applied.

Both commands take a `debug :: Bool` first argument, which comes from the parent `agent`
command's `--debug`. In debug mode neither contacts a provider, applies a baseline, nor
writes anything. Debug must therefore perform no guard check at all — a developer inspecting
a prompt on a machine that has never installed the artifact should not be refused.

### The command option records

In `seihou-cli/src-exe/Seihou/CLI/Commands.hs`:

```haskell
data BlueprintRunOpts = BlueprintRunOpts
  { name :: !ModuleName, prompt :: !(Maybe Text), vars :: ![(Text, Text)],
    noBaseline :: !Bool, namespace :: !(Maybe Text), context :: !(Maybe Text),
    verbose :: !Bool, force :: !Bool, batch :: !Bool,
    provider :: !(Maybe Text), model :: !(Maybe Text), effort :: !(Maybe Text),
    trace :: !(Maybe Text) }

data BlueprintMigrationOpts = BlueprintMigrationOpts
  { name :: !ModuleName, from :: !Text, to :: !Text, prompt :: !(Maybe Text),
    vars :: ![(Text, Text)], namespace :: !(Maybe Text), context :: !(Maybe Text),
    verbose :: !Bool, rerun :: !Bool,
    provider :: !(Maybe Text), model :: !(Maybe Text), effort :: !(Maybe Text),
    trace :: !(Maybe Text) }
```

Neither has `allowDowngrade`. `RunOpts` does, and its parser uses
`switch (long "allow-downgrade" <> ...)` — see lines 867, 889, and 1321 of the same file for
the three existing spellings, and copy the wording of whichever is closest.

Note that `BlueprintRunOpts` already has a field named `force`, used for something else
(conflict acceptance during baseline application). Do not overload it. Add a distinct
`allowDowngrade` field so the two overrides stay separable, matching `seihou run`, which
also has both.

### Relevant ADRs

- `docs/adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md` — the decision this
  plan extends to a path it does not currently reach. Read it in full. Its argument against
  warn-and-continue is the reason this plan refuses rather than prints, and its scoping rule
  ("scope each refusal to the artifacts the command is about to use") is the reason the
  agent-path check is filtered rather than whole-manifest.
- `docs/adr/0002-artifact-identity-is-origin-url-plus-name.md` — establishes that identity
  is origin plus name, which is what `judgeArtifact` compares.
- `docs/adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md` — background for
  why the manifest records an origin rather than a path.

Consider during implementation whether ADR 0003 should be amended to state that it governs
the agent path too, or whether a short new ADR is warranted. Lean toward amending 0003: the
decision is unchanged, only its reach is, and a second ADR restating the same judgement
would fragment it. Record the choice in the Decision Log either way.

`docs/adr/` is a plain filesystem corpus, not a profile-governed OKF bundle — `mori.dhall`
registers only `docs/improvement-requests`. Keep the `NNNN-slug.md` convention and the
`# ADR NNNN — Title` heading with `Status` and `Date` lines. Do not add OKF frontmatter.

No cross-repository ADR governs this work.

### The Improvement Request this implements

`docs/improvement-requests/guard-the-agent-path-against-stale-and-substituted-artifacts.md`
(IR-3). Read it before starting. It enumerates the four specific changes requested and
explains why `--batch` and the pre-session timing of baseline application make the
human-in-the-loop argument weaker than it first appears.


## Plan of Work

### Milestone 1 — teach the guard about a recorded blueprint

At the end of this milestone `ManifestGuard` can check the manifest's recorded blueprint,
and `seihou status` reports on it. Nothing refuses yet.

`checkAppliedArtifactsFor` currently walks `manifest ^. #modules` and resolves each with
`resolveArtifactOrigin projectRoot searchPaths "module.dhall" recordedOrigin`, then reads
the local version from `module.dhall`. A blueprint differs in exactly two ways: its
descriptor file is `blueprint.dhall`, and its version is read with `evalBlueprintFromFile`
rather than `evalModuleFromFile`.

Add a sibling function rather than generalising the existing one with a flag:

```haskell
-- | Check the manifest's recorded blueprint, if any, against this machine.
-- Returns 'Nothing' when no blueprint has been applied.
checkAppliedBlueprint :: FilePath -> [FilePath] -> Manifest -> IO (Maybe ArtifactCheck)
```

It reads `manifest ^. #blueprint` (a `Maybe AppliedBlueprint`), resolves
`recordedOrigin` with `resolveArtifactOrigin projectRoot searchPaths "blueprint.dhall"`,
detects the local origin with `detectArtifactOrigin`, reads the local version from the
discovered `blueprint.dhall`, and calls the same `judgeArtifact`. Factor the shared body of
`checkOne` out of `checkAppliedArtifactsFor` so both callers use one implementation and one
verdict vocabulary; the only variation is the descriptor filename and the version reader.

`ArtifactCheck` carries `name :: !ModuleName`, and `AppliedBlueprint`'s name is already a
`ModuleName`, so the result type needs no change.

While here, wire the new check into `seihou status`
(`seihou-cli/src-exe/Seihou/CLI/Status.hs`), which already renders
`summarizeCheck` output for modules. A recorded blueprint that is stale or substituted
should appear there for the same reason modules do. This is a small addition and it gives
milestone 1 an observable outcome on its own.

### Milestone 2 — the flag

At the end of this milestone both agent subcommands accept `--allow-downgrade` and carry it
in their options records. It does nothing yet.

In `seihou-cli/src-exe/Seihou/CLI/Commands.hs`, add `allowDowngrade :: !Bool` to
`BlueprintRunOpts` and `BlueprintMigrationOpts`, and add the corresponding `switch` to each
parser. These are positional applicative parsers: the field order in the record and the
combinator order in the parser must match exactly, or the code compiles and assigns the
wrong values. Add the field last in the record and the switch last in the parser, and
re-read both after editing.

Use help text consistent with the existing flag:

```haskell
<*> switch
      ( long "allow-downgrade"
          <> help "Proceed even when the installed artifact is older than, or from a different source than, this project records"
      )
```

Update `seihou-cli/src-exe/Seihou/CLI/Help.hs` if it enumerates agent flags, and add the
flag to the option tables in `docs/cli/agent.md` under `agent run` and `agent migrate`.

### Milestone 3 — guard `seihou agent run`

At the end of this milestone `seihou agent run` refuses on a stale or substituted blueprint,
and on stale or substituted baseline modules, before writing anything.

Insert the check in `handleAgentRun` before the `applyBaseline` call at line ~175 — and
before any other write. Read the manifest first; if there is no manifest, or it records no
blueprint and no relevant modules, there is nothing to check and the run proceeds.

Check two things, per IR-3's points 1 and 2:

1. **The blueprint.** Use `checkAppliedBlueprint` from milestone 1. This catches the
   downgrade scenario: developer A upgrades a blueprint, runs it, commits the regenerated
   baseline output and the manifest; developer B still has the older blueprint installed.
2. **The resolved base modules.** These are ordinary modules that generate ordinary files,
   and a blueprint run is the one path on which they are applied without the `seihou run`
   guard. Build the `Set ModuleName` of the blueprint's `baseModules` names and pass it as
   the filter to `checkAppliedArtifactsFor`, exactly as `seihou run` passes
   `composedModuleNames`. Skip this check entirely when `--no-baseline` was passed or the
   blueprint declares none, since nothing will be applied.

Combine both check lists, run them through `blockingChecks`, and apply the same policy
`seihou run` applies. Write the policy function locally rather than importing `Run.hs`'s —
`enforceArtifactGuard` takes a `RunOpts` and lives in the executable module for `seihou run`.
Either generalise it to take a `Bool` and move it into `Seihou.CLI.ManifestGuard` (preferred:
one implementation, and the module already owns both renderers), or write a two-line local
equivalent. Choose the move, and update `Run.hs` to call the moved version; record the choice
in the Decision Log.

Guard nothing when `debug` is true. Put that condition at the top of the check, not inside
each branch, so it is obvious on reading that debug mode is structurally check-free.

### Milestone 4 — guard `seihou agent migrate`

At the end of this milestone `seihou agent migrate` refuses on a stale or substituted
blueprint before it plans a single edge.

Insert the check in `handleAgentMigrate` after the blueprint is discovered and validated
(after line ~75) and before `planBlueprintMigrationChain` at line ~89. Placing it before
planning is the point: IR-3 observes that on this path the operator otherwise sees *less*
than nothing, because a substituted blueprint's edges are dropped as already-applied and the
command reports success.

Check the recorded blueprint only. Migration mode does not apply `baseModules` — that is
documented in `docs/user/blueprint-migrations.md` — so there are no baseline modules to
check and adding them would refuse for artifacts the command will not touch, violating ADR
0003's scoping rule.

There is a subtlety worth handling deliberately. A project may have a recorded
`AppliedBlueprint` for a *different* blueprint than the one being migrated, or none at all —
`seihou agent migrate` does not require a prior `seihou agent run`. The recorded blueprint
is checked only when its name matches the blueprint being migrated. When there is no matching
record, there is nothing to compare and the command proceeds; the receipts themselves become
the identity record once plan 81 has landed. If the migration receipts for this blueprint
record an origin that differs from the copy being used, that is also a genuine mismatch and
should refuse — decide during implementation whether to check receipts as well as the
`AppliedBlueprint` record, and record the decision. Checking receipts is the more complete
answer, since a project may have migrated a blueprint it never `agent run`.

Guard nothing when `debug` is true.

### Milestone 5 — tests

The CLI test suite is at `seihou-cli/test/`, run with `cabal test seihou-cli-test`. It uses
`tasty` with `hspec` via `Test.Tasty.Hspec.testSpec`; each spec module exports
`tests :: IO TestTree` and is registered in the suite's `Main.hs`.

Two existing files are the models to follow.
`seihou-cli/test/Seihou/CLI/SharedManifestE2ESpec.hs` already asserts the byte-identical
property for `seihou run` — that a refusal leaves the working tree untouched. Read it and
copy its structure. `seihou-cli/test/Seihou/CLI/TwoDeveloperFixture.hs` builds the
two-developer scenario (one developer's newer artifact, another's older copy) and is exactly
the setup this plan needs. `seihou-cli/test/Seihou/CLI/RunBlueprintRefusalSpec.hs` shows how
blueprint-path refusals are tested today.

Add a spec covering:

- `seihou agent run` against a manifest recording a newer blueprint than is installed
  refuses, exits nonzero, and leaves both the working tree and `.seihou/manifest.json`
  byte-identical. Hash the tree before and after.
- The same scenario with `--allow-downgrade` proceeds and prints the override block.
- `seihou agent run` where a *baseline module* is stale refuses, even though the blueprint
  itself is current.
- `seihou agent migrate` against a substituted blueprint refuses rather than reporting "no
  pending migrations" — this is the IR-3 scenario and the most important case in the file.
- `seihou agent --debug run` and `seihou agent --debug migrate` against both scenarios
  succeed and write nothing.

Tests that would launch a provider must use `--debug` or a stubbed provider; check how
`seihou-cli/test/Seihou/CLI/AgentMigrateE2ESpec.hs` handles this and follow it, since a test
must never start an interactive `claude` or `codex` session.

### Milestone 6 — documentation and IR bookkeeping

`docs/cli/agent.md` — add `--allow-downgrade` to the option tables for `agent run` and
`agent migrate`, and add a short "Artifact guard" subsection explaining that both commands
refuse on a stale or substituted artifact and that `--debug` never checks.

`docs/user/blueprints.md` — note the guard in the section describing what `agent run` does
before the session starts, next to where baseline application is described.

`docs/user/blueprint-migrations.md` — add a row to the Troubleshooting table for the refusal
message, and note in "How a migration runs" that the guard runs before planning.

`docs/user/CHANGELOG.md` — an entry. Call out that a developer with an out-of-date install
cache will now be refused where they previously succeeded, and that `seihou upgrade <name>`
is the fix.

`docs/adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md` — amend per the decision
from Context, keeping the existing file convention.

Update `docs/improvement-requests/guard-the-agent-path-against-stale-and-substituted-artifacts.md`:
set `status: implemented` and add a closing section naming this plan. That bundle is a
profile-governed OKF bundle registered in `mori.dhall`; maintain its reserved `log.md` with
`okf log add` and validate:

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
rg -n "checkAppliedArtifactsFor|blockingChecks|enforceArtifactGuard" --glob '*.hs'
rg -n "applyBaseline|recordAppliedBlueprint" seihou-cli/src-exe/Seihou/CLI/AgentRun.hs
rg -n "planBlueprintMigrationChain|pendingBlueprintMigrations" seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs
```

Build and test after each milestone:

```bash
cabal build all
cabal test seihou-cli-test
```

Full checks before committing:

```bash
nix flake check
```

Commit with all three trailers:

```text
feat(agent): guard agent run and agent migrate against stale artifacts

Consult ManifestGuard before applying a blueprint baseline and before
planning migration edges, refusing on the same terms as seihou run with
the same --allow-downgrade override.

MasterPlan: docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md
ExecPlan: docs/plans/83-guard-the-agent-path-against-stale-and-substituted-artifacts.md
Intention: intention_01m05ew4qbef6tn9bnphy4nv2n
```


## Validation and Acceptance

**Automated.** `cabal test seihou-cli-test` passes including the new spec. The decisive
assertions are the byte-identical property on refusal and the `agent migrate` case where a
substituted blueprint refuses instead of reporting no pending migrations.

**By hand — the downgrade scenario.** In a scratch project, install a blueprint at version
`0.2.0`, run it, and commit. Then hand-edit
`~/.config/seihou/installed/<name>/blueprint.dhall` to declare `version = Some "0.1.0"` —
this simulates a colleague's older install without needing two machines. Then:

```bash
seihou agent run <name>
```

Expected (the wording comes from `formatGuardRefusal`, so match it rather than inventing new
text):

```text
✗ Refusing to run: your local copy of '<name>' is older than the
  version this project expects.

  Recorded in .seihou/manifest.json:  0.2.0
  Installed on this machine:          0.1.0

  Update your local copy first:
    seihou upgrade <name>
```

The command exits nonzero. Confirm `git status` is clean — no baseline files were written —
and that `.seihou/manifest.json` is unchanged.

Then:

```bash
seihou agent run <name> --allow-downgrade
```

prints the same blocks under `! Proceeding anyway (--allow-downgrade)` and continues.

**By hand — the substitution scenario on migrate.** With a receipt already recorded for one
edge, replace the installed blueprint with a same-named blueprint from a different
repository (this requires `--force` once
`docs/plans/82-refuse-to-overwrite-an-installation-from-a-different-source.md` has landed),
then:

```bash
seihou agent migrate <name> --from 1.0.0 --to 2.0.0
```

Before this change: `All blueprint migrations in the requested version window already have
receipts.` and exit 0 — work silently skipped. After: a refusal naming both origins and exit
nonzero. That contrast is the acceptance criterion for this plan.

**Debug stays open.** On a machine where the artifact is not installed at all, or is stale:

```bash
seihou agent --debug run <name>
seihou agent --debug migrate <name> --from 1.0.0 --to 2.0.0
```

Both must render their prompts and exit 0, writing nothing.


## Idempotence and Recovery

All edits are to source; rebuilding and re-testing is safe to repeat.

The new runtime behaviour is a refusal, which is non-destructive by construction: it happens
before any write. There is no state migration and nothing to roll back.

For users, the recovery path from a refusal is `seihou upgrade <name>` (for staleness) or
reinstalling from the URL the manifest records (for a substitution) — the refusal message
prints the exact command for each case. `--allow-downgrade` is the escape hatch when the
refusal is understood and deliberate; it pins the project to what is installed locally and
prints what it overrode, so the decision is visible in the terminal even though it will not
be visible in the diff.

If milestone 3 or 4 is interrupted, the worst state is a command that checks but does not
yet enforce, which is harmless. Do not leave a state where the check runs *after*
`applyBaseline`: that is worse than no check, because it refuses after writing. If work must
stop mid-milestone, revert the partial insertion rather than committing it.


## Interfaces and Dependencies

No new library dependencies.

At the end of the plan these must exist.

`seihou-cli/src/Seihou/CLI/ManifestGuard.hs`

```haskell
checkAppliedBlueprint :: FilePath -> [FilePath] -> Manifest -> IO (Maybe ArtifactCheck)

-- moved here from Run.hs and generalised from RunOpts to a Bool
enforceArtifactGuard :: Bool -> [ArtifactCheck] -> IO ()
```

`seihou-cli/src-exe/Seihou/CLI/Commands.hs`

```haskell
data BlueprintRunOpts = BlueprintRunOpts
  { -- ... existing fields ...
    allowDowngrade :: !Bool
  }

data BlueprintMigrationOpts = BlueprintMigrationOpts
  { -- ... existing fields ...
    allowDowngrade :: !Bool
  }
```

Hard dependency: `docs/plans/81-record-artifact-origin-for-agent-applied-artifacts.md` must
be complete first.

Soft dependency: `docs/plans/82-refuse-to-overwrite-an-installation-from-a-different-source.md`
makes the substitution scenario harder to reach accidentally, which makes this plan's manual
validation require deliberate setup.

Nothing depends on this plan. It can land at any point after plan 81 without blocking
`docs/plans/84-add-a-not-applicable-outcome-for-blueprint-migration-edges.md`,
`docs/plans/85-fan-out-a-blueprint-migration-edge-to-entailed-cohort-edges.md`, or
`docs/plans/86-infer-the-blueprint-migration-version-window.md`. Plan 85 does add a
consideration worth revisiting once both have landed: when a migration chain spans several
blueprints, each entailed blueprint is an artifact this command is about to use, so ADR
0003's scoping rule implies each should be guarded. Plan 85 owns that extension; leave a
note in this plan's Outcomes section pointing at it.
