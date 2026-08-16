---
id: 86
slug: infer-the-blueprint-migration-version-window
title: "Infer the blueprint migration version window"
kind: exec-plan
created_at: 2026-08-16T14:16:43Z
intention: "intention_01m05ew4qbef6tn9bnphy4nv2n"
master_plan: "docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md"
---

# Infer the blueprint migration version window

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

`seihou agent migrate` runs a library's upgrade guidance across a version window, one AI
agent session per declared version edge:

```bash
seihou agent migrate keiro-upgrade --from 2.4.0 --to 3.0.0
```

Both numbers are mandatory and both are typed by hand. `docs/user/blueprint-migrations.md`
states the reason plainly: "Seihou is language-agnostic and does not read Cabal, npm, Cargo,
or Maven files to guess which version you are on or where you are going."

Being language-agnostic is right; making the user do the lookup is not the only way to get
there. The two ends of the window answer different questions, and seihou can answer each
without knowing anything about any package manager.

`--to` asks how far the *dependency* has been bumped in this project. The blueprint's author
knows how to read that — it is one command against a lockfile, a `cabal.project`, a
`package.json` — and only the author knows it. So the blueprint declares a *version probe*:
a shell command whose standard output is the version. Seihou runs it and uses the result.

`--from` asks how far the *source* has already been migrated. Seihou already records that,
precisely, in the migration receipts in `.seihou/manifest.json`. The highest recorded `to`
version for this blueprint is the answer.

After this plan, the ordinary invocation is:

```bash
seihou agent migrate keiro-upgrade
```

and the command reports what it inferred and where each end came from:

```text
Version window: 2.4.0 -> 3.0.0
  --from 2.4.0  [receipt: keiro-upgrade 2.0.0 -> 2.4.0, applied 2026-08-02]
  --to   3.0.0  [probe: nix eval --raw .#keiroVersion]
```

Explicit flags always win, so nothing that works today stops working.


## Progress

- [ ] Verify the prerequisite plan has landed (orientation, no edits).
- [ ] Publish `versionProbe` on `schema/Blueprint.dhall` in the `seihou-schema` submodule; push and re-pin.
- [ ] Decode and validate `versionProbe` in `seihou-core/src/Seihou/Dhall/Eval.hs` and `seihou-core/src/Seihou/Core/Blueprint.hs`.
- [ ] Make `--from` and `--to` optional in `seihou-cli/src-exe/Seihou/CLI/Commands.hs`.
- [ ] Add pure window resolution (source-tracked) in `seihou-cli/src/Seihou/CLI/BlueprintMigration.hs`.
- [ ] Run the probe and derive the receipt-based default in `seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs`.
- [ ] Report both ends and their sources; make errors actionable when neither can be resolved.
- [ ] Add tests for resolution precedence, probe failure, and no-receipt-no-probe.
- [ ] Update `docs/cli/agent.md`, `docs/user/blueprint-migrations.md`, `docs/user/blueprints.md`, `schema/README.md`, and `docs/user/CHANGELOG.md`.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: ...
  Rationale: ...
  Date: ...


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

### Dependencies on other plans

This plan **cannot be implemented before**
`docs/plans/81-record-artifact-origin-for-agent-applied-artifacts.md`. The default `--from`
is derived by selecting the receipts that belong to this blueprint, and "belong to this
blueprint" must mean origin *and* name. Selecting on bare name would pick up a receipt
written by a different repository's identically-named blueprint and start the window at the
wrong version. Verify:

```bash
rg -n "origin :: !ArtifactOrigin" seihou-core/src/Seihou/Core/Types.hs
```

`AppliedBlueprintMigration` must carry an `origin` field.

This plan soft-depends on
`docs/plans/85-fan-out-a-blueprint-migration-edge-to-entailed-cohort-edges.md` in two ways.
First, plan 85 publishes a schema change to `shinzui/seihou-schema` and re-pins this
repository; this plan publishes another. Land plan 85's schema change first and build this
one on top of the resulting pin rather than racing it. Second, plan 85 changes
`BlueprintMigrationPlan`'s `steps` and reshapes the `--debug` and launch output that this
plan extends. If plan 85 has not landed, this plan still works — it just has less output to
extend. Check which state you are in:

```bash
rg -n "BlueprintMigrationStep" seihou-core/src/Seihou/Core/Migration.hs
```

If that type exists, plan 85 has landed; adapt the reporting in milestone 5 to sit alongside
its owner labels rather than duplicating them.

Plan 84's not-applicable outcome interacts with the `--from` derivation and is handled
explicitly in milestone 4.

### What this repository is

Seihou is a project scaffolding system written in Haskell: a two-package Cabal workspace,
`seihou-core` (library, at `seihou-core/`) and `seihou-cli` (at `seihou-cli/`). The CLI
package is split into a library at `seihou-cli/src/` (package `seihou-cli-internal`) and an
executable at `seihou-cli/src-exe/`. New code goes in a library by default; the executable
holds `Main.hs`, command dispatchers, and modules needing `Options.Applicative`,
`Data.FileEmbed`, `GitHash`, or `Paths_seihou_cli`, plus anything transitively importing
one. `nix/check-cli-module-placement.sh` enforces it.

The practical consequence for this plan: the *decision* about which version each end of the
window takes, and where it came from, is pure and belongs in
`seihou-cli/src/Seihou/CLI/BlueprintMigration.hs` (the library module, which already holds
the pure selection and rendering logic for this command). Running the probe process and
reading the manifest are IO and belong in
`seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs`.

Records use strict fields, `Generic`, explicit deriving strategies, and are read and written
through `generic-lens` overloaded labels, never record dot syntax and never record update
syntax. Modules using `#label` import `Data.Generics.Labels ()`.
`nix/check-record-conventions.sh` enforces this.

### The command as it stands

`seihou-cli/src-exe/Seihou/CLI/Commands.hs`:

```haskell
data BlueprintMigrationOpts = BlueprintMigrationOpts
  { name :: !ModuleName,
    from :: !Text,
    to :: !Text,
    prompt :: !(Maybe Text),
    vars :: ![(Text, Text)],
    namespace :: !(Maybe Text),
    context :: !(Maybe Text),
    verbose :: !Bool,
    rerun :: !Bool,
    provider :: !(Maybe Text),
    model :: !(Maybe Text),
    effort :: !(Maybe Text),
    trace :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)
```

`from` and `to` are `Text` and their parser uses required `option`s. In
`seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs`:

```haskell
  current <- parseRequestedVersion level "--from" (opts ^. #from)
  target <- parseRequestedVersion level "--to" (opts ^. #to)

parseRequestedVersion :: LogLevel -> Text -> Text -> IO Version
parseRequestedVersion level flag raw =
  case parseVersion raw of
    Just version -> pure version
    Nothing -> exitErr level (flag <> " value '" <> raw <> "' is not a valid dotted numeric version.")
```

Versions are dotted numeric (`1`, `1.2`, `1.0.0`); prerelease and build syntax such as
`1.0.0-rc1` is rejected. `Seihou.Core.Version` provides `parseVersion`, `renderVersion`, and
an `Ord` instance.

The receipts are read a few lines later:

```haskell
readMigrationReceipts :: LogLevel -> FilePath -> IO [AppliedBlueprintMigration]
```

which returns `manifest ^. #blueprintMigrations`. Today that read happens *after* planning;
this plan needs it *before*, since the plan window now depends on it. Moving the read earlier
is safe — it is a pure manifest read with no side effects — but note that it currently
`exitErr`s on a manifest read failure, and a missing manifest returns an empty list rather
than an error. Both behaviours should be preserved.

### Running a subprocess

`seihou-core/src/Seihou/Effect/Process.hs` defines the effect the repository uses for
subprocesses:

```haskell
data Process :: Effect where
  RunProcess :: Text -> [Text] -> Maybe FilePath -> Process m (ExitCode, Text, Text)

runProcess :: (Process :> es) => Text -> [Text] -> Maybe FilePath -> Eff es (ExitCode, Text, Text)
```

It returns exit code, stdout, and stderr, and takes an optional working directory. There is
an IO interpreter at `seihou-core/src/Seihou/Effect/ProcessInterp.hs` and a pure one at
`ProcessPure.hs` for tests. Use this rather than reaching for `System.Process` directly, and
look at how `RunCommand` migration ops and the `Command` schema execute shell commands
(`seihou-cli/test/Seihou/CLI/CommandExecutionSpec.hs` is a good entry point) so the probe
follows the same conventions for shell invocation and working directory.

### The precedent for a declared shell command

`schema/MigrationOp.dhall` already has `RunCommand : { run : Text, workDir : Optional Text }`
as an escape hatch in module migrations, and `schema/Command.dhall` exists for module
commands. So "the artifact author supplies a shell command" is an established pattern in
this schema, not a new idea. The version probe is the read-only member of that family.

### Relevant ADRs

- `docs/adr/0004-the-manifest-is-the-only-record-of-applied-state.md` — there is no
  lockfile; the manifest is the only record of applied state. This is the reason the
  `--from` default is derived from receipts already in the manifest rather than from any new
  persisted state, and the reason the probe reads the *project's own* dependency declaration
  rather than something seihou caches.
- `docs/adr/0002-artifact-identity-is-origin-url-plus-name.md` — identity is origin plus
  name, which is how receipts are selected for this blueprint.

`docs/adr/` is a plain filesystem corpus, not a profile-governed OKF bundle — `mori.dhall`
registers only `docs/improvement-requests`. Keep the `NNNN-slug.md` convention, the
`# ADR NNNN — Title` heading, and `Status` / `Date` lines. Do not add OKF frontmatter.

No cross-repository ADR governs this work.

There is no Improvement Request behind this plan; it originates from the DX analysis
recorded in `docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md`.


## Plan of Work

### The design, stated once

Resolution precedence for each end of the window:

- `--to`: explicit flag, else the blueprint's declared `versionProbe` output, else error.
- `--from`: explicit flag, else the highest `toVersion` among this blueprint's applied
  receipts, else error.

The two ends deliberately use different sources, and getting this backwards would break the
common workflow. The normal sequence is: bump the dependency in the project, then migrate
the source to match. At the moment the user runs `seihou agent migrate`, the lockfile
already says the *new* version — so the probe reads the target, not the start. If the probe
supplied `--from`, every project that bumped its dependency first would be told there is
nothing to do, which is exactly the workflow this feature is for.

The receipt ledger is the mirror image: it records how far the source has been carried, and
says nothing about what the lockfile now declares.

Both errors must be actionable, naming the flag and, for `--to`, mentioning that the
blueprint can declare a probe.

### Milestone 1 — publish the schema change

At the end of this milestone `versionProbe` is authorable and this repository is pinned to a
schema containing it.

If `docs/plans/85-fan-out-a-blueprint-migration-edge-to-entailed-cohort-edges.md` is in
flight, wait for its schema publication and build on that commit.

Work in the `schema/` submodule, following `.claude/skills/update-seihou-schema/SKILL.md`.
The submodule is a working copy of `shinzui/seihou-schema` and is the only checkout that
matters; the standalone clone at
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema` must not be used for authoring.

```bash
git -C schema fetch origin
git -C schema status --branch --porcelain
```

Add to `schema/Blueprint.dhall`:

```dhall
, versionProbe : Optional Text
```

defaulting to `None Text`, with a comment explaining it:

```dhall
-- `versionProbe` is a shell command seihou runs in the project directory to
-- discover which version of the library this project currently declares. Its
-- standard output, trimmed, must be a dotted numeric version. It supplies the
-- default `--to` for `seihou agent migrate`: the normal workflow is to bump the
-- dependency and then migrate the source up to it, so the version the project
-- now declares is the target. Seihou stays language-agnostic by never guessing
-- the command — only the blueprint's author knows where the version lives.
--
--   versionProbe = Some "jq -r .dependencies.keiro package.json"
--   versionProbe = Some "nix eval --raw .#keiroVersion"
```

Update `schema/README.md`'s type list if it enumerates fields. Type-check and prove the
field is authorable with a scratch file using record completion:

```bash
dhall type --file schema/package.dhall > /dev/null && echo "package.dhall type-checks"
```

Commit and **push inside the submodule** — the pin resolves over HTTPS, so an unpushed
commit cannot be fetched:

```bash
git -C schema add Blueprint.dhall README.md
git -C schema commit -m "feat(schema): add versionProbe to Blueprint"
git -C schema push origin master
```

Then re-pin: bump the submodule pointer, update `schemaUrl` and `schemaHash` in
`seihou-cli/src/Seihou/CLI/SchemaVersion.hs`, and update `flake.lock`.

### Milestone 2 — decode and validate

Add `versionProbe :: !(Maybe Text)` to the `Blueprint` record in
`seihou-core/src/Seihou/Core/Types.hs`, and decode it in `blueprintDecoder`
(`seihou-core/src/Seihou/Dhall/Eval.hs`). Blueprints published before this schema version
have no `versionProbe` key, so extend the existing `withDefaults` list — the decoder already
does this for `migrations` and `launch`:

```haskell
withDefaults [("migrations", emptyMigrationList), ("launch", noneText), ("versionProbe", noneText)]
```

`noneText` is already defined in that module as `Dhall.App Dhall.None Dhall.Text`, which is
exactly the right default here.

In `seihou-core/src/Seihou/Core/Blueprint.hs`, add a validation rule: when `versionProbe` is
`Just`, it must be non-blank. Follow `checkBlueprintLaunch`, which applies the same
"every field the record does set is non-blank" rule and leaves richer interpretation to the
CLI. Do not try to validate the command itself — seihou cannot know whether `jq` is
installed, and validation must not execute anything. Add the rule to the numbered list in
`validateBlueprint`'s Haddock.

### Milestone 3 — optional flags

In `seihou-cli/src-exe/Seihou/CLI/Commands.hs`, change `BlueprintMigrationOpts`:

```haskell
    from :: !(Maybe Text),
    to :: !(Maybe Text),
```

and change both parser entries from required `option`s to `optional (option ...)`. Update
the help text to say what happens when each is omitted:

```haskell
<*> optional
      ( option
          (T.pack <$> str)
          ( long "from"
              <> metavar "VERSION"
              <> help "Version to migrate from (default: the highest version this project has already migrated to)"
          )
      )
<*> optional
      ( option
          (T.pack <$> str)
          ( long "to"
              <> metavar "VERSION"
              <> help "Version to migrate to (default: the blueprint's declared version probe)"
          )
      )
```

This is a positional applicative parser: the record field order and the combinator order
must match exactly or the code compiles and assigns wrong values. Re-read both after
editing.

Check `seihou-cli/src-exe/Seihou/CLI/Help.hs` for an `agent migrate` section and update it,
and check `seihou-cli/src/Seihou/CLI/*` for shell-completion definitions that enumerate
required flags.

### Milestone 4 — pure window resolution

At the end of this milestone the decision about each end of the window is a pure function
with a typed provenance, testable without a filesystem or a subprocess.

In `seihou-cli/src/Seihou/CLI/BlueprintMigration.hs`:

```haskell
-- | Where one end of the migration version window came from. Carried so the
-- command can tell the user what it inferred and why, which matters more here
-- than usual: an inferred window silently off by one release would run the
-- wrong edges.
data VersionSource
  = VersionFromFlag
  | VersionFromProbe !Text          -- ^ the probe command that produced it
  | VersionFromReceipt !Text !Text  -- ^ the receipt edge it was taken from: from, to
  deriving stock (Eq, Show, Generic)

data ResolvedWindow = ResolvedWindow
  { fromVersion :: !Version,
    fromSource :: !VersionSource,
    toVersion :: !Version,
    toSource :: !VersionSource
  }
  deriving stock (Eq, Show, Generic)

-- | The highest version this project has already migrated this blueprint to,
-- with the receipt that says so.
--
-- Only receipts belonging to this blueprint identity are considered — name and
-- origin both, per docs/adr/0002-artifact-identity-is-origin-url-plus-name.md,
-- because a same-named blueprint from another repository records a different
-- project history.
highestMigratedVersion ::
  ArtifactOrigin ->
  ModuleName ->
  [AppliedBlueprintMigration] ->
  Maybe (Version, AppliedBlueprintMigration)
```

Two details in `highestMigratedVersion` need deciding, and both should be recorded:

**Unparseable versions.** A receipt whose `toVersion` does not parse is skipped rather than
failing the command. Receipts are data written by earlier runs and a single malformed one
should not make the command unusable.

**Not-applicable receipts.** If
`docs/plans/84-add-a-not-applicable-outcome-for-blueprint-migration-edges.md` has landed,
receipts carry a `MigrationOutcome`. Count **only** `MigrationApplied` receipts toward the
highest migrated version. A not-applicable receipt records that seihou *considered* an edge
and the project did not need it — it says nothing about how far the source has been carried,
and treating it as progress would skip real edges below it. Guard this with a test; it is
the subtlest correctness point in the plan.

Then the resolver:

```haskell
data WindowResolutionError
  = NoTargetVersion        -- ^ no --to, no probe
  | NoStartVersion         -- ^ no --from, no applied receipt
  | ProbeOutputUnparseable !Text !Text  -- ^ command, raw output
  deriving stock (Eq, Show, Generic)

resolveMigrationWindow ::
  Maybe Version ->                    -- ^ --from, already parsed
  Maybe Version ->                    -- ^ --to, already parsed
  Maybe (Version, Text) ->            -- ^ probe result and the command that produced it
  Maybe (Version, AppliedBlueprintMigration) ->  -- ^ highest applied receipt
  Either WindowResolutionError ResolvedWindow
```

Keeping the probe *result* a parameter rather than running it here is what keeps this pure.
The caller decides whether to run the probe at all — skip it entirely when `--to` was given,
so an explicit invocation never executes a subprocess it does not need.

### Milestone 5 — wiring, reporting, and errors

In `seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs`:

Move the receipt read earlier, before window resolution. Preserve its current behaviour: a
missing manifest yields an empty list, a corrupt one is an error.

Run the probe only when `--to` was not supplied and the blueprint declares one. Run it
through the `Process` effect in the project directory, with a modest timeout so a hung probe
does not hang the command — check whether the effect or its interpreter already supports one
and add it at the call site if not. Trim the output and take the last non-empty line rather
than the whole of stdout: a probe like `nix eval` may print progress to stdout, and the
version is the last thing it says. Document that rule, because an author needs to know it.

A probe that exits nonzero is a warning, not a failure: fall through to requiring `--to`, and
print the command, its exit code, and its stderr so the author can fix it. The user is not at
fault and still has an explicit flag available. A probe that exits zero but prints something
unparseable is the same: report `ProbeOutputUnparseable` with the raw output and fall
through.

Report the resolved window before planning. At normal verbosity, one line; at `--verbose`,
the full provenance:

```text
Version window: 2.4.0 -> 3.0.0
  --from 2.4.0  [receipt: keiro-upgrade 2.0.0 -> 2.4.0, applied 2026-08-02]
  --to   3.0.0  [probe: nix eval --raw .#keiroVersion]
```

Print the provenance whenever *either* end was inferred, even at normal verbosity, in
abbreviated form. An inferred window that is silently wrong runs the wrong agent sessions
against the user's source; that is worth two lines of output.

Make both errors actionable:

```text
✗ Cannot determine the target version for 'keiro-upgrade'.

  Pass --to VERSION, or ask the blueprint's author to declare a versionProbe
  so seihou can read the version this project depends on.
```

```text
✗ Cannot determine the starting version for 'keiro-upgrade'.

  This project has no recorded migration for that blueprint, so seihou does
  not know how far its source has already been migrated.

  Pass --from VERSION.
```

The second is the first-run case and will be common, so its wording matters. It should read
as an explanation, not a complaint.

Under `--debug`, resolve and report the window but note in the output that nothing was run.
The probe *is* executed under `--debug` — it is a read-only command supplied by the
blueprint, and refusing to run it would make debug output diverge from a real run in exactly
the way that matters. Say so in `docs/cli/agent.md`, since `--debug` otherwise promises to
contact nothing.

### Milestone 6 — tests

Core tests at `seihou-core/test/` (`cabal test seihou-core-test`); CLI tests at
`seihou-cli/test/` (`cabal test seihou-cli-test`). Both use `tasty` with `hspec` via
`Test.Tasty.Hspec.testSpec`; each spec module exports `tests :: IO TestTree` and is
registered in the suite's `Main.hs`.

Add to `seihou-cli/test/Seihou/CLI/BlueprintMigrationSpec.hs`:

- `resolveMigrationWindow` prefers explicit flags over probe and receipts, for each end
  independently — flag `--from` with inferred `--to` and the reverse both work;
- with neither flag, it takes `--to` from the probe and `--from` from the receipt;
- missing probe and missing `--to` gives `NoTargetVersion`; missing receipt and missing
  `--from` gives `NoStartVersion`;
- `highestMigratedVersion` ignores receipts belonging to another blueprint name;
- it ignores receipts with the same name but a different origin;
- it ignores receipts with unparseable versions rather than failing;
- it ignores not-applicable receipts and returns the highest *applied* one — construct a
  case where the not-applicable receipt has the numerically highest `to`, so a wrong
  implementation visibly picks it;
- it returns `Nothing` for an empty receipt list.

Add probe-execution tests using the pure `Process` interpreter at
`seihou-core/src/Seihou/Effect/ProcessPure.hs`: a probe printing `3.0.0`, one printing
progress lines followed by the version, one exiting nonzero, and one printing garbage. Assert
that the last two fall through to requiring `--to` rather than aborting.

Extend `seihou-cli/test/Seihou/CLI/AgentMigrateE2ESpec.hs` with a case that runs the command
with no version flags against a fixture blueprint whose probe is a trivial command such as
`echo 3.0.0`, and asserts the reported window. Read that spec first for how it avoids
launching a real provider.

### Milestone 7 — documentation

`docs/cli/agent.md` — `--from` and `--to` are no longer required; document the defaults, the
precedence, and that the probe runs under `--debug`.

`docs/user/blueprint-migrations.md` — this is the file with the sentence this plan makes
obsolete. Under "For consumers / Run the upgrade" it currently says "Supply both versions
explicitly. Seihou is language-agnostic and does not read Cabal, npm, Cargo, or Maven files
to guess which version you are on or where you are going." Rewrite it: seihou still reads no
package manager format, and now the blueprint's author can supply the one command that
reads theirs. Add a "For library authors" subsection on writing a good probe: it must be
read-only, fast, print the version as its last output line, and work from the project root.

`docs/user/blueprints.md` — `versionProbe` in the field reference with worked examples for
two or three ecosystems.

`schema/README.md` — verify it matches milestone 1.

`docs/user/CHANGELOG.md` — a feature entry noting that existing invocations with both flags
are unaffected.


## Concrete Steps

Run everything from the repository root,
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

Confirm the prerequisite and check whether plan 85 has landed:

```bash
rg -n "origin :: !ArtifactOrigin" seihou-core/src/Seihou/Core/Types.hs
rg -n "BlueprintMigrationStep" seihou-core/src/Seihou/Core/Migration.hs
```

Schema work, following `.claude/skills/update-seihou-schema/SKILL.md`:

```bash
git -C schema fetch origin
git -C schema status --branch --porcelain
dhall type --file schema/package.dhall > /dev/null && echo "package.dhall type-checks"
git -C schema push origin master
```

Build and test after each milestone:

```bash
cabal build all
cabal test seihou-core-test
cabal test seihou-cli-test
```

Full checks before committing:

```bash
nix flake check
```

Commit with all three trailers; the schema submodule commit is separate and does not carry
them:

```text
feat(agent): infer the blueprint migration version window

--to defaults to the blueprint's declared versionProbe, which reads the
version this project depends on; --from defaults to the highest version
already recorded in the migration receipts. Explicit flags still win.

MasterPlan: docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md
ExecPlan: docs/plans/86-infer-the-blueprint-migration-version-window.md
Intention: intention_01m05ew4qbef6tn9bnphy4nv2n
```


## Validation and Acceptance

**Automated.** Both suites pass. The decisive assertions are the precedence table and the
not-applicable-receipt exclusion in `highestMigratedVersion`.

**By hand.** Build a throwaway blueprint with two edges, `1.0.0 -> 2.0.0` and
`2.0.0 -> 3.0.0`, and a probe that reads a file so you can move the "installed version"
around:

```dhall
versionProbe = Some "cat .keiro-version"
```

In a scratch project:

```bash
echo "2.0.0" > .keiro-version
seihou agent --debug migrate scratch-upgrade --from 1.0.0
```

Expected — `--to` inferred, `--from` explicit:

```text
Version window: 1.0.0 -> 2.0.0
  --to   2.0.0  [probe: cat .keiro-version]

Blueprint migrations for scratch-upgrade: 1.0.0 -> 2.0.0
===== [1/1] 1.0.0 -> 2.0.0 =====
```

Run it for real so a receipt is written, then bump the file and run with **no flags at all**:

```bash
echo "3.0.0" > .keiro-version
seihou agent --debug migrate scratch-upgrade
```

Expected — both ends inferred, and the window starts where the last run finished:

```text
Version window: 2.0.0 -> 3.0.0
  --from 2.0.0  [receipt: scratch-upgrade 1.0.0 -> 2.0.0, applied 2026-08-16]
  --to   3.0.0  [probe: cat .keiro-version]

Blueprint migrations for scratch-upgrade: 2.0.0 -> 3.0.0
===== [1/1] 2.0.0 -> 3.0.0 =====
```

That is the acceptance criterion: the command a user types is
`seihou agent migrate scratch-upgrade`, and it does the right thing.

**Explicit flags still win.** `seihou agent --debug migrate scratch-upgrade --from 1.0.0
--to 3.0.0` plans both edges regardless of the probe and the receipts, and reports both
sources as `[flag]`.

**Probe failures degrade, not abort.**

```bash
rm .keiro-version
seihou agent --debug migrate scratch-upgrade
```

must print the probe's failure with its stderr and then the `NoTargetVersion` error naming
`--to`, and exit nonzero. Passing `--to 3.0.0` must then succeed despite the broken probe.

**First run with no receipts.** In a fresh project with a working probe and no manifest,
running with no flags must produce the `NoStartVersion` message explaining that seihou does
not know how far the source has been migrated. Confirm the message reads as an explanation.

**Blueprints without a probe are unaffected.** A blueprint published before this change
must still work with both flags supplied, and must give the actionable `NoTargetVersion`
error when `--to` is omitted.


## Idempotence and Recovery

Source edits plus one schema publication. The schema push is not locally reversible, but the
change is purely additive — one new optional field defaulting to `None Text` — so no existing
`blueprint.dhall` stops type-checking. If the field's shape turns out wrong, publish a
corrected version and re-pin rather than force-pushing.

Re-running the build, the tests, and `--debug` planning is safe. Note the one exception to
`--debug`'s usual "contacts nothing" promise: it does execute the probe. Probes are required
to be read-only, and the documentation must say so, but a badly written probe could have side
effects. This is the reason the authoring guidance in milestone 7 states the read-only
requirement explicitly rather than leaving it implied.

For users, every failure mode in this plan has the same escape hatch: pass the flags
explicitly. Nothing here can put a project into a state that requires repair — the worst
outcome is a command that refuses to guess and asks for the numbers it used to require.

If work stops mid-plan, the safe stopping points are the end of milestone 2 (the field
exists, decodes, and validates; nothing reads it) and the end of milestone 4 (the resolver
exists and is tested; nothing calls it). Do not stop after milestone 3 with milestone 5
incomplete: optional flags with no inference means `opts ^. #from` is `Nothing` and the
command has nothing to plan with.


## Interfaces and Dependencies

No new library dependencies. The schema submodule gains one field.

At the end of the plan these must exist.

`schema/Blueprint.dhall` — `versionProbe : Optional Text`, defaulting to `None Text`.

`seihou-core/src/Seihou/Core/Types.hs` — `versionProbe :: !(Maybe Text)` on `Blueprint`.

`seihou-cli/src-exe/Seihou/CLI/Commands.hs`

```haskell
data BlueprintMigrationOpts = BlueprintMigrationOpts
  { name :: !ModuleName,
    from :: !(Maybe Text),
    to :: !(Maybe Text),
    -- ... remaining fields unchanged ...
  }
```

`seihou-cli/src/Seihou/CLI/BlueprintMigration.hs`

```haskell
data VersionSource
  = VersionFromFlag
  | VersionFromProbe !Text
  | VersionFromReceipt !Text !Text
  deriving stock (Eq, Show, Generic)

data ResolvedWindow = ResolvedWindow
  { fromVersion :: !Version,
    fromSource :: !VersionSource,
    toVersion :: !Version,
    toSource :: !VersionSource
  }
  deriving stock (Eq, Show, Generic)

data WindowResolutionError
  = NoTargetVersion
  | NoStartVersion
  | ProbeOutputUnparseable !Text !Text
  deriving stock (Eq, Show, Generic)

highestMigratedVersion ::
  ArtifactOrigin -> ModuleName -> [AppliedBlueprintMigration] ->
  Maybe (Version, AppliedBlueprintMigration)

resolveMigrationWindow ::
  Maybe Version ->
  Maybe Version ->
  Maybe (Version, Text) ->
  Maybe (Version, AppliedBlueprintMigration) ->
  Either WindowResolutionError ResolvedWindow
```

Hard dependency: `docs/plans/81-record-artifact-origin-for-agent-applied-artifacts.md`.

Soft dependencies: `docs/plans/85-fan-out-a-blueprint-migration-edge-to-entailed-cohort-edges.md`
(schema pin ordering and output shape) and
`docs/plans/84-add-a-not-applicable-outcome-for-blueprint-migration-edges.md` (whose outcome
field `highestMigratedVersion` must respect).

Nothing depends on this plan; it is the last of the six and can land whenever its
prerequisites have.
