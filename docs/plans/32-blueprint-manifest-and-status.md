---
id: 32
slug: blueprint-manifest-and-status
title: "Manifest Tracking and `seihou status` Integration for Applied Blueprints"
kind: exec-plan
created_at: 2026-05-07T00:00:00Z
intention: "intention_01kr2q5p3ye30t4vk9fj4q69t1"
---


# Manifest Tracking and `seihou status` Integration for Applied Blueprints

MasterPlan: docs/masterplans/3-agent-driven-blueprints.md
Intention: intention_01kr2q5p3ye30t4vk9fj4q69t1

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

A **Blueprint** is the third runnable artifact in Seihou (after modules and
recipes): a non-deterministic scaffold — a Markdown prompt plus an optional
set of baseline modules and reference files — consumed by an AI coding agent
(Claude Code) through `seihou agent run BLUEPRINT [PROMPT]`. EP-29
introduces the `Blueprint` type, schema, discovery, and the `seihou run`
refusal branch. EP-31 adds the runner that resolves variables, optionally
applies the baseline, renders the prompt, and shells out to `claude`.

This plan, EP-32, closes the persistence loop. After it ships, two things
are true that are not true today:

1. A successful `seihou agent run my-blueprint "set this up for a payments
   microservice"` writes an `AppliedBlueprint` entry into
   `.seihou/manifest.json` immediately before the manifest is flushed. The
   entry records the blueprint name, version, the timestamp, the names of
   baseline modules that were applied (or the fact that `--no-baseline` was
   passed), the user's positional `PROMPT` argument if supplied, and a
   reserved `agentSessionId` field for the deferred "resume" feature.
2. `seihou status` displays a new section under the existing applied-recipe
   block:

       Blueprint: my-blueprint v0.3.1 (applied 2026-05-12 14:23 UTC)
         Baseline: nix-flake, haskell-base
         Prompt: "set this up for a payments microservice"

   When the user passed `--no-baseline`, the Baseline line reads
   `(none -- --no-baseline)`. When the user did not supply a positional
   prompt, the Prompt line is omitted.

The user-visible win is that a contributor returning to a project weeks
later can ask `seihou status` what the project was scaffolded from and learn
the blueprint name, version, and original ask. Tooling-side, the
`AppliedBlueprint` entry is the foundation a future `seihou outdated`
extension uses to flag a newer blueprint version, and the foundation a
future `seihou agent run --resume` uses to re-launch the agent in context.

The plan touches three subsystems and bumps the manifest schema version.
The schema bump is the riskiest piece: a sloppy decoder leaves every
existing user's manifest unreadable. The decoder is therefore strictly
backwards-compatible, mirrors the existing `Maybe AppliedRecipe` precedent,
and a fixture-driven test decodes a pre-bump manifest and asserts
`blueprint = Nothing`.


## Progress

- [ ] Milestone 1: Domain model and JSON serialization. Add `AppliedBlueprint` to `seihou-core/src/Seihou/Core/Types.hs`, extend `Manifest` with `blueprint :: Maybe AppliedBlueprint`, bump `currentManifestVersion` from 2 to 3 in `seihou-core/src/Seihou/Manifest/Types.hs`, add the `ToJSON`/`FromJSON` instances, and add the `writeAppliedBlueprint` helper. All seihou-core tests still pass.
- [ ] Milestone 2: Wire the runner. In EP-31's `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`, after a successful `claude` exit, read the manifest, apply `writeAppliedBlueprint`, and write the manifest back. The runner tests assert the entry is present after a simulated successful exit and absent after a simulated failure.
- [ ] Milestone 3: Status display. Extend `seihou-cli/src/Seihou/CLI/StatusRender.hs` with a `blueprintSection` and wire it into `formatStatus`. Add tests that construct a `Manifest` fixture with a populated `blueprint` and assert the rendered output contains the documented lines.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Represent the applied-blueprint provenance as a single
  `Maybe AppliedBlueprint` field on `Manifest`, not a list.
  Rationale: A project is scaffolded from at most one blueprint in v1 — running
  `seihou agent run my-blueprint` a second time replaces the prior provenance,
  just as `seihou run my-recipe` replaces `Manifest.recipe`. The deferred
  "resume" feature in masterplan
  `docs/masterplans/3-agent-driven-blueprints.md` extends a single
  applied-blueprint entry with session metadata; it does not introduce
  multi-blueprint composition. If a future plan ever does need to track
  multiple blueprints, promoting `Maybe AppliedBlueprint` to
  `[AppliedBlueprint]` is a one-shot manifest schema bump using the same
  backwards-compatible decoder pattern this plan uses.
  Date: 2026-05-07.

- Decision: Capture the user's positional `PROMPT` argument in
  `userPrompt :: Maybe Text` on `AppliedBlueprint`.
  Rationale: When a user returns to a project weeks later, the original ask
  ("set this up for a payments microservice") is the most useful single piece
  of context for understanding what the agent and human built together.
  Storage is trivial (one short string), the data is optional (the user may
  run with no prompt), and surfacing it in `seihou status` directly answers
  the "what was I doing?" question that motivates the status command.
  Date: 2026-05-07.

- Decision: Reserve `agentSessionId :: Maybe Text` on `AppliedBlueprint`,
  always `Nothing` in v1.
  Rationale: The masterplan's Decision Log records "blueprint resume" as a
  deferred feature: a future plan persists conversation transcripts under
  `.seihou/blueprints/<name>/sessions/<id>/` and adds
  `seihou agent run --resume <id>`. The session identifier is the obvious
  join key. Reserving the field now (rather than bumping the manifest schema
  again later) lets the resume feature land as a pure additive change. Always
  `Nothing` means every encoder branch produces no `agentSessionId` JSON key,
  every decoder branch tolerates its absence, and no v1 code path constructs
  a non-`Nothing` value.
  Date: 2026-05-07.

- Decision: Use a backwards-compatible decoder rather than a one-shot
  `seihou schema-upgrade` migration.
  Rationale: The new `blueprint` field is `Maybe AppliedBlueprint` with a
  nullable JSON encoding. A pre-bump manifest (schema version 2) has no
  `blueprint` key; the decoder's `o Aeson..:? "blueprint"` yields `Nothing`
  regardless of whether the version field reads 2 or 3. This is the same
  pattern used when `parentVars` was added in
  `docs/plans/10-parameterized-dep-multi-instantiation.md` and when
  `recipe :: Maybe AppliedRecipe` was added previously. No
  `seihou schema-upgrade` branch is needed.
  Date: 2026-05-07.


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

The Seihou repository at
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` is a multi-package
Haskell workspace. Two packages matter: `seihou-core` (data types and
manifest serialization) and `seihou-cli` (the CLI). The CLI splits along
the library-first convention documented in
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/docs/dev/architecture/overview.md`:
modules that need `Options.Applicative`, `Data.FileEmbed`, `GitHash`, or
`Paths_seihou_cli` live under `seihou-cli/src-exe/`; everything else
lives under `seihou-cli/src/`.

The manifest is a JSON file at `.seihou/manifest.json` inside any
project. The Haskell type is in
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/seihou-core/src/Seihou/Core/Types.hs`
(lines 363-371 for `Manifest`, 373-379 for `AppliedRecipe`, 388-396 for
`AppliedModule`). The JSON instances and the schema version constant are
in
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/seihou-core/src/Seihou/Manifest/Types.hs`.
The current `currentManifestVersion` is `2`; it was bumped from 1 when
`parentVars` was added.

The status renderer at
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/seihou-cli/src/Seihou/CLI/StatusRender.hs`
is a pure module exposing
`formatStatus :: Bool -> Manifest -> [TrackedFile] -> Maybe [OutdatedEntry] -> [(ModuleName, MigrationPlan)] -> Text`.
The recipe display is `recipeSection :: Manifest -> [Text]` at lines
165-173; the new `blueprintSection` is a direct analogue. The handler
that invokes `formatStatus` is at
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/seihou-cli/src-exe/Seihou/CLI/Status.hs`
and needs no changes.

The runner this plan hooks into is EP-31. EP-31 lands
`seihou-cli/src-exe/Seihou/CLI/AgentRun.hs` containing
`handleAgentRun :: BlueprintRunOpts -> IO ()`. The contract: after the
`claude` subprocess exits with code 0, EP-31's handler calls
`writeAppliedBlueprint` (defined here) — a pure function from
`AppliedBlueprint` and the old manifest to the new manifest — then
writes the manifest. This keeps the writer testable as a pure function
and isolates IO to the runner.

The `AppliedRecipe` precedent is the single most important reference.
Read lines 363-379 of `Seihou/Core/Types.hs` and lines 50-87 of
`Seihou/Manifest/Types.hs` before starting; every shape here mirrors
that precedent. The recipe-applied write site at lines 310-326 of
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/seihou-cli/src-exe/Seihou/CLI/Run.hs`
shows how `Manifest.recipe` is populated. The blueprint pipeline is
structurally simpler (the agent owns file output, not the diff engine),
so the writer is called outside the engine effects entirely.


## Plan of Work

The work decomposes into three milestones, each independently verifiable.

### Milestone 1: Domain model and JSON serialization

The goal is that `seihou-core` compiles with the new `AppliedBlueprint`
record, the bumped manifest schema version, the new JSON instances, and
the new `writeAppliedBlueprint` helper, and that the existing test suite
continues to pass. No CLI code changes yet.

The new record is added to `seihou-core/src/Seihou/Core/Types.hs`
adjacent to `AppliedRecipe`:

    data AppliedBlueprint = AppliedBlueprint
      { name :: ModuleName,
        blueprintVersion :: Maybe Text,
        appliedAt :: UTCTime,
        baselineModules :: [ModuleName],
        noBaseline :: Bool,
        userPrompt :: Maybe Text,
        agentSessionId :: Maybe Text
      }
      deriving stock (Eq, Show, Generic)

`name` uses `ModuleName` because blueprints share the
`[a-z][a-z0-9-]*` namespace with modules and recipes. `baselineModules`
records which modules the runner applied as the baseline. `noBaseline`
distinguishes "no baseline declared" (`baselineModules = []`,
`noBaseline = False`) from "baseline skipped by user"
(`baselineModules = []`, `noBaseline = True`). `userPrompt` is the
positional PROMPT argument. `agentSessionId` is reserved for the deferred
resume feature; in v1 it is always `Nothing` and the encoder omits the
JSON key in that case.

`AppliedBlueprint (..)` is added to the module's export list adjacent
to the existing `AppliedRecipe (..)` export. The `Manifest` record
gains `blueprint :: Maybe AppliedBlueprint` appended after the existing
`recipe` field.

In `seihou-core/src/Seihou/Manifest/Types.hs`, bump
`currentManifestVersion` from 2 to 3 with an updated comment explaining
the bump and pointing at this plan. Update `emptyManifest` to set
`blueprint = Nothing`.

The `ToJSON Manifest` instance gains a conditional emit mirroring the
existing `recipe` branch:

    ++ maybe [] (\b -> ["blueprint" .= b]) m.blueprint

The `FromJSON Manifest` instance gains one extra optional field read at
the end of the applicative chain:

    <*> o Aeson..:? "blueprint"

This handles all three cases. Pre-bump manifests with `version: 2` and
no `blueprint` key: the version check passes (2 is not greater than 3),
and the optional read yields `Nothing`. Bumped manifests with
`blueprint: null`: the optional read decodes the explicit `null` to
`Nothing`. Bumped manifests with a populated `blueprint` object: the
optional read invokes `FromJSON AppliedBlueprint`.

The `AppliedBlueprint` JSON instances follow the `AppliedRecipe` shape
at lines 74-87 of `Seihou/Manifest/Types.hs`. The encoder emits required
fields (`name`, `appliedAt`, `baselineModules`, `noBaseline`)
unconditionally and gates the optional fields (`version`, `userPrompt`,
`agentSessionId`) behind `maybe [] (\v -> [...])`. The decoder uses
`o .: "name"` and `o .: "appliedAt"` for required keys, and
`o Aeson..:? "version"`, `o Aeson..:? "userPrompt"`, and
`o Aeson..:? "agentSessionId"` for optional keys. For
`baselineModules` and `noBaseline`, the decoder uses
`o Aeson..:? "..." Aeson..!= <default>` to default a hand-edited or
partial manifest to safe values (`[]` and `False`) rather than failing
the whole `seihou status` invocation.

The exported writer helper:

    writeAppliedBlueprint :: AppliedBlueprint -> Manifest -> Manifest
    writeAppliedBlueprint ab m = m { blueprint = Just ab }

It overwrites any prior entry. Re-applying a blueprint replaces the
recorded provenance — same semantics as `Manifest.recipe`. The helper
lives next to `emptyManifest` in `Seihou.Manifest.Types` and is added
to the module's export list.

Tests live under
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/seihou-core/test/`,
following the existing layout for `Seihou.Core.*` and
`Seihou.Manifest.*` specs. Two tests are required: (1)
`AppliedBlueprint` round-trips through JSON encoding and decoding with
all fields populated; (2) a pre-bump manifest fixture (literal JSON
with `"version": 2`, the required keys, and no `blueprint` key)
decodes successfully with `blueprint = Nothing`.

Acceptance: `cabal test seihou-core` passes; the two new tests are
visible in the report.

### Milestone 2: Runner integration

The goal is that EP-31's `handleAgentRun` writes the `AppliedBlueprint`
entry to the manifest after the `claude` subprocess exits successfully,
and does *not* write it on failure.

EP-31 owns the runner. The contract this plan defines is a small block
added at the end of the success branch of `handleAgentRun`, in
`seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`, immediately after the
call to `launchAgentWith` returns `ExitSuccess`:

    when (exitCode == ExitSuccess) $ do
      now <- getCurrentTime
      let entry = AppliedBlueprint
            { name = blueprintName,
              blueprintVersion = blueprintVer,
              appliedAt = now,
              baselineModules = appliedBaselineNames,
              noBaseline = opts.noBaseline,
              userPrompt = opts.userPrompt,
              agentSessionId = Nothing
            }
      runEff $ runFilesystem $ runManifestStore manifestPath $ do
        mManifest <- readManifest
        case mManifest of
          Right (Just m) -> writeManifest (writeAppliedBlueprint entry m)
          Right Nothing -> writeManifest (writeAppliedBlueprint entry (emptyManifest now))
          Left _ -> pure ()  -- Manifest unreadable; do not overwrite.

`blueprintName` and `blueprintVer` come from the `Blueprint` value the
runner has in scope (loaded via the EP-29 `discoverRunnable`
extension). `appliedBaselineNames :: [ModuleName]` is the runner's
record of which baseline modules were applied; when `opts.noBaseline`
is true this is the empty list. `opts.userPrompt :: Maybe Text`
captures the positional PROMPT argument from `BlueprintRunOpts`.

When the `claude` subprocess exits non-zero, the runner returns early
without touching the manifest: recording an `AppliedBlueprint` for an
aborted agent run would misrepresent reality.

The write step is factored into a helper exposed from the runner module:

    recordAppliedBlueprint :: FilePath -> AppliedBlueprint -> IO ()

This is the seam that lets a unit test exercise the write path without
launching `claude`. The test creates a temporary directory, writes a
baseline manifest (or none), invokes the helper with a synthesised
`AppliedBlueprint`, reads the manifest back, and asserts the
`blueprint` field matches.

The integration test covers `handleAgentRun` end-to-end with a stubbed
agent launcher. EP-31 is expected to expose `launchAgentWith` through
a parameter or a small typeclass; this plan inherits that seam. If
EP-31 did not expose one, this plan adds it as a focused refactor:
extract a `launchAgent :: AgentLaunchOpts -> IO ExitCode` parameter to
`handleAgentRun` and provide a test stub returning `ExitSuccess`
immediately. The test asserts that after `handleAgentRun` returns, the
manifest in the test's temporary directory contains an
`AppliedBlueprint` matching the input. A second variant with the stub
returning a non-zero exit code asserts no `blueprint` entry is written.

Acceptance: `cabal test seihou-cli` passes; both runner tests are
visible.

### Milestone 3: Status display

The goal is that `seihou status` prints the documented blueprint
section when the manifest contains an `AppliedBlueprint` entry, and
prints nothing extra when it does not.

The change is contained to
`seihou-cli/src/Seihou/CLI/StatusRender.hs`. A new
`blueprintSection :: Manifest -> [Text]` mirrors the existing
`recipeSection` at lines 165-173:

    blueprintSection :: Manifest -> [Text]
    blueprintSection manifest = case manifest.blueprint of
      Nothing -> []
      Just ab ->
        let header =
              "Blueprint: "
                <> ab.name.unModuleName
                <> maybe "" (\v -> " v" <> v) ab.blueprintVersion
                <> " (applied "
                <> T.pack (formatTime defaultTimeLocale "%Y-%m-%d %H:%M UTC" ab.appliedAt)
                <> ")"
            baselineLine = "  Baseline: " <> renderBaseline ab
            promptLines = case ab.userPrompt of
              Nothing -> []
              Just p -> ["  Prompt: \"" <> p <> "\""]
         in [header, baselineLine] ++ promptLines ++ [""]

    renderBaseline :: AppliedBlueprint -> Text
    renderBaseline ab
      | ab.noBaseline = "(none -- --no-baseline)"
      | null ab.baselineModules = "(none declared)"
      | otherwise =
          T.intercalate ", " (map (.unModuleName) ab.baselineModules)

The three branches of `renderBaseline` cover the masterplan's
documented cases plus the corner case where the blueprint declared no
base modules at all and the user did not pass `--no-baseline` — rare
but reachable for a pure-prompt blueprint.

The new section is wired into `formatStatus` between `recipeSection`
and `appliedSection`. This places "what was scaffolded" at the top of
the report, before "what modules are applied". The imports at the top
of `StatusRender.hs` gain `AppliedBlueprint (..)` from
`Seihou.Core.Types`. The status handler at
`seihou-cli/src-exe/Seihou/CLI/Status.hs` requires no changes —
`formatStatus` already receives the full `Manifest`.

Four unit tests cover the rendering. (1) A populated fixture (name,
version, two baseline modules, prompt) asserts the output contains, in
order, a line beginning with `Blueprint: my-blueprint v0.3.1 (applied`,
a line `  Baseline: nix-flake, haskell-base`, and a line
`  Prompt: "set this up for a payments microservice"`. (2) A fixture
with `noBaseline = True` asserts the Baseline line reads
`  Baseline: (none -- --no-baseline)`. (3) A fixture with
`userPrompt = Nothing` asserts no `  Prompt:` line appears. (4) A
fixture with `blueprint = Nothing` asserts no `Blueprint: ` line
appears.

Acceptance: `cabal test seihou-cli` passes. Running `seihou status`
in a scratch directory with a hand-written manifest containing the
new field prints the documented lines.


## Concrete Steps

Recommended implementation order; each step commits independently using
Conventional Commits.

1. Edit `seihou-core/src/Seihou/Core/Types.hs`: add
   `AppliedBlueprint (..)` to the export list, the data declaration
   after `AppliedRecipe`, and the `blueprint` field on `Manifest`.
   Commit: `feat(core): add AppliedBlueprint record and Manifest field`.

2. Edit `seihou-core/src/Seihou/Manifest/Types.hs`: bump
   `currentManifestVersion` to 3 with updated comment, update
   `emptyManifest`, extend the `Manifest` JSON instances, add the
   `AppliedBlueprint` JSON instances, add and export
   `writeAppliedBlueprint`. Commit:
   `feat(core): bump manifest schema to v3, add AppliedBlueprint serialization`.

3. Add unit tests under `seihou-core/test/` for the round-trip and the
   v2-fixture decode. Run `cabal test seihou-core`. Commit:
   `test(core): cover AppliedBlueprint JSON round-trip and v2 fixture decode`.

4. Coordinate with EP-31. Amend `handleAgentRun` per Milestone 2.
   Commit:
   `feat(cli): record AppliedBlueprint in manifest on successful agent run`.

5. Add the runner unit test exercising `recordAppliedBlueprint` and
   the stubbed `handleAgentRun` test asserting the success-writes /
   failure-does-not-write contract. Commit:
   `test(cli): cover AppliedBlueprint write path without launching agent`.

6. Edit `seihou-cli/src/Seihou/CLI/StatusRender.hs`: import
   `AppliedBlueprint (..)`, add `blueprintSection` and
   `renderBaseline`, wire into `formatStatus`. Commit:
   `feat(cli): display applied-blueprint provenance in seihou status`.

7. Add the four `blueprintSection` rendering tests. Run
   `cabal test seihou-cli`. Commit:
   `test(cli): cover blueprint section rendering in formatStatus`.

8. Run `cabal test all`; verify no regressions.

9. End-to-end smoke test: hand-construct a `.seihou/manifest.json`
   with a populated `blueprint` object in a scratch directory; run
   `seihou status`; confirm the documented lines. After EP-31 merges,
   run `seihou agent run my-blueprint "test prompt"` end-to-end.

10. Update `docs/user/CHANGELOG.md` with one line describing the
    new status line and the schema bump. Commit:
    `docs(changelog): note manifest v3 schema and blueprint status line`.


## Validation and Acceptance

`cabal test all` passes from the repository root with no regressions
and the new tests visible in the report. New tests: `AppliedBlueprint`
JSON round-trip; v2 manifest fixture decodes with `blueprint = Nothing`;
runner records `AppliedBlueprint` after simulated successful exit;
runner does not record after simulated failure; `formatStatus` renders
the four blueprint-section fixtures correctly.

In a scratch directory containing a `.seihou/manifest.json` with a
populated `blueprint` field, `seihou status` prints output that
includes, in order:

    Blueprint: my-blueprint v0.3.1 (applied 2026-05-12 14:23 UTC)
      Baseline: nix-flake, haskell-base
      Prompt: "set this up for a payments microservice"

In the same scratch directory with `noBaseline: true`, the Baseline
line reads `  Baseline: (none -- --no-baseline)`. With the
`userPrompt` key omitted, the `  Prompt:` line is absent.

A pre-bump manifest fixture (`version: 2`, no `blueprint` key) is read
without error and renders the existing sections unchanged, with no
Blueprint section.

After EP-31 merges and a contributor runs `seihou agent run
my-blueprint "set this up for a payments microservice"` against a real
test blueprint and the agent exits successfully, the
`.seihou/manifest.json` contains a populated `blueprint` object with
the documented field shape. If the agent exits non-zero (Ctrl-C or a
`claude` failure), the manifest does not gain a `blueprint` entry, and
any prior `blueprint` entry is left unchanged.


## Idempotence and Recovery

A `seihou agent run` invocation that succeeds writes one
`AppliedBlueprint` entry. Re-running `seihou agent run` (same blueprint
or different) overwrites the prior entry. There is no log of prior
applications in v1; the manifest records only the most recent successful
agent run. This mirrors `Manifest.recipe`: re-running
`seihou run my-recipe` overwrites the `AppliedRecipe` entry.

A run that fails (agent exits non-zero, user interrupts) does not write
a `blueprint` entry. If a prior entry existed, it is left untouched. The
manifest therefore always reflects the last *successful* application,
never a partial or aborted one.

A `seihou agent run --no-baseline` invocation writes an entry with
`noBaseline = true` and `baselineModules = []`. A subsequent
`seihou agent run` without `--no-baseline` overwrites the entry with
`noBaseline = false` and the populated baseline list. This is correct:
the manifest reflects the most recent agent-driven scaffolding.

The other manifest fields (`modules`, `vars`, `files`, `recipe`) are not
touched by `writeAppliedBlueprint`. If EP-31's runner applies baseline
modules through the existing engine pipeline, those modules update
`Manifest.modules`, `Manifest.vars`, and `Manifest.files` through the
same code path that `seihou run` uses; that pipeline is the
responsibility of EP-31, not this plan.

If a user hand-edits `.seihou/manifest.json` between `seihou agent run`
invocations and corrupts the file, the runner's read step returns `Left
err`, the runner skips the write per the contingency in Milestone 2, and
the user sees an error — same recovery story as `seihou status` and
`seihou run` today.

If a user downgrades to a pre-EP-32 build of seihou after upgrading
their manifest to schema v3, the older build's decoder fails with
"manifest was created by a newer version of seihou". This is the
documented behaviour for any forward schema bump and matches the v1-to-v2
precedent. Recovery is to upgrade seihou or to manually edit the
`version` field down (losing the new `blueprint` key the older build
does not understand anyway).


## Interfaces and Dependencies

This plan is the fourth child of masterplan
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/docs/masterplans/3-agent-driven-blueprints.md`.

Hard dependency: EP-31 (the agent runner). EP-32 cannot ship in
isolation because the writer's only production-code call site is in
EP-31's `handleAgentRun`. The two plans can be developed in parallel —
EP-32 Milestone 1 (the data type and JSON serialization) lands
independently of EP-31, and the unit tests cover everything seihou-core
needs to ship — but Milestones 2 and 3 require EP-31's runner module to
exist. Recommended sequence: EP-32 Milestone 1 lands first or in
parallel; EP-31 lands; then EP-32 Milestones 2 and 3 land in quick
succession.

Soft dependency: EP-29 (the Blueprint domain model). EP-32 does not
import the `Blueprint` type directly — `AppliedBlueprint` is an
independent record — but the test fixtures use `ModuleName` values that
follow the blueprint naming convention, and the end-to-end smoke test
relies on the `seihou agent run` CLI surface that EP-29 defines.

Downstream consumer: EP-34 (documentation). EP-34's design doc at
`docs/dev/design/proposed/blueprints.md` describes the manifest shape
this plan defines and the status-line format this plan specifies. The
doc reflects shipped behaviour, so EP-34 should not land until EP-32 is
merged.

Files this plan modifies (no new source files):

- `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/seihou-core/src/Seihou/Core/Types.hs`
  — data types and exports.
- `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/seihou-core/src/Seihou/Manifest/Types.hs`
  — schema version, `emptyManifest`, JSON instances,
  `writeAppliedBlueprint` helper.
- `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/seihou-cli/src/Seihou/CLI/StatusRender.hs`
  — new `blueprintSection`; wiring into `formatStatus`.
- `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`
  — runner; lines added at the end of the success branch (Milestone 2).
- `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/docs/user/CHANGELOG.md`
  — one-line user-visible entry.

Test files this plan adds (exact locations follow the existing test
layout — discover the conventional location during implementation):

- A spec module under the `seihou-core` test target with the round-trip
  and v2-fixture tests.
- A spec module under the `seihou-cli` test target for the runner writer
  and the four `blueprintSection` fixtures.

External tools and dependencies: none beyond what seihou already depends
on (`aeson`, `time`). The schema bump does not require any change to
the `seihou-schema` Dhall repository or `mori.dhall`, because the
manifest schema is a JSON schema internal to seihou, distinct from the
Dhall schema that describes user-facing module, recipe, and blueprint
Dhall files. EP-29 is the plan that bumps the Dhall schema; this plan
does not touch it.
