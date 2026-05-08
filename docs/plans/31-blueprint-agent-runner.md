---
id: 31
slug: blueprint-agent-runner
title: "Agent Runner for Blueprints (seihou agent run BLUEPRINT)"
kind: exec-plan
created_at: 2026-05-07T00:00:00Z
intention: "intention_01kr2q5p3ye30t4vk9fj4q69t1"
---


# Agent Runner for Blueprints (`seihou agent run BLUEPRINT`)

MasterPlan: docs/masterplans/3-agent-driven-blueprints.md
Intention: intention_01kr2q5p3ye30t4vk9fj4q69t1

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this plan ships, a user inside a project directory can run

    seihou agent run my-blueprint "set this up for a payments microservice"

and the CLI will: locate `my-blueprint` (a `blueprint.dhall` artifact
discovered through the same search paths used for modules and
recipes); resolve every variable the blueprint declares (CLI overrides
> env > local config > namespace > context > global > defaults >
interactive prompts); apply the modules listed in the blueprint's
`baseModules` field as a starting scaffold; render the blueprint's
prompt template into a Markdown body with `{{var}}` substitutions;
wrap that body inside a system-prompt scaffold that explains the
project's current state and lists the reference files in the
blueprint's `files/` directory; and launch Claude Code via the
existing `launchAgentWith` helper with the right `--add-dir` and
`--allowedTools` flags so the agent has read access to the references
and write access to the project.

A "blueprint" in this codebase is a third runnable type — alongside
modules (`module.dhall`) and recipes (`recipe.dhall`) — that
deliberately produces *non-deterministic* output: the human author
captures intent and conventions in a Markdown prompt, and an AI
coding agent translates that intent into concrete project files in
collaboration with the user. The masterplan at
`docs/masterplans/3-agent-driven-blueprints.md` describes the full
shape; this plan owns the runner.

This plan does not introduce the `Blueprint` Haskell type, the Dhall
schema, the discovery extension, or the `seihou run` refusal branch —
those are EP-29 (`docs/plans/29-blueprint-domain-model-and-discovery.md`).
It does not introduce `seihou new-blueprint` or `seihou
validate-blueprint` — those are EP-30
(`docs/plans/30-blueprint-authoring-and-inspection.md`). It does not
write the manifest entry for an applied blueprint — that is EP-32
(`docs/plans/32-blueprint-manifest-and-status.md`); see Decision Log
for the contract. EP-31 hard-depends on EP-29; soft-depends on EP-30
(test fixtures benefit from `seihou validate-blueprint`).

Observable acceptance: `seihou agent run my-blueprint --debug` prints a
fully-substituted system prompt with blueprint identity, applied
baseline summary, reference file list, the rendered user prompt, and
explicit workflow guidance. The same invocation without `--debug`
spawns Claude Code with the right cwd, `--add-dir`s, and tool
allowlist.


## Progress

- [x] Milestone 1 — CLI parsing: add `AgentRun BlueprintRunOpts` constructor, the `BlueprintRunOpts` record, and the `agent run` subcommand parser. *(2026-05-08: parser, footer, and help text wired; `cabal run seihou -- agent run --help` renders correctly. Stub handler exits 1 with a "not yet implemented" message.)*
- [x] Milestone 2 — Handler skeleton + prompt scaffold: create `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs` and `seihou-cli/data/blueprint-prompt.md`. Implement discovery, var resolution, and prompt rendering. The `--no-baseline` path is fully wired; the baseline-application path returns a stub status. *(2026-05-08: combined with M3 in a single commit — see surprise note below.)*
- [x] Milestone 3 — Baseline application: implement `applyBaseline` calling `loadComposition`, `resolveWithPrompts`, `compileComposedPlan`, `executePlan` directly. Base modules' manifest entries are written via the existing `updateAllModules` path; the *blueprint manifest entry* is left as a TODO for EP-32. *(2026-05-08: smoke-tested with `--no-baseline --debug` against `sample-blueprint`; var substitution and missing-required-var failure both correct. Acceptance 3 (with-baseline + write) is verified by the M4 integration tests.)*
- [ ] Milestone 4 — Tests: integration tests under `seihou-cli/test/Seihou/CLI/AgentRunSpec.hs` covering `--debug`, `--no-baseline`, `--var` overrides, and missing-required-var failure. Pure-formatter unit tests added to `seihou-cli/test/Seihou/CLI/AgentLaunchSpec.hs`. CHANGELOG entry under `docs/user/CHANGELOG.md`.


## Surprises & Discoveries

- 2026-05-08 — `OverloadedRecordDot` against `ModuleInstance.instanceModule`
  / `instanceParentVars` requires importing the constructor (`ModuleInstance (..)`),
  not just the type alias `ModuleInstance`. With the type-only import,
  GHC fails the field selection with "No instance for HasField …
  ModuleInstance ModuleName". `Seihou.CLI.Run` already imports `(..)`;
  this plan's first attempt didn't and hit the error. EP-32 (which will
  add a writer that consumes `BlueprintRunOutcome` and likely touches
  module instances) and EP-33 (registry classifier) should both import
  `ModuleInstance (..)` from `Seihou.Composition.Instance`.

- 2026-05-08 — Combined milestones M2 (handler skeleton + prompt scaffold)
  and M3 (baseline application) into a single commit. The plan split
  them so each milestone could be reviewed independently; in a single
  session that gain is illusory and the M2 stub for the baseline path
  ("(baseline application not yet implemented in this milestone — see
  Milestone 3)") would have required a temporary `BaselineStatus`
  constructor that M3 then deletes — pure churn. Recorded so a later
  reader of the master plan understands why the EP-31 commit log shows
  M2+M3 as one step.

- 2026-05-08 — `BlueprintFile` exposes `src :: FilePath`, not `path`.
  EP-31's plan text mentioned a `path` field; the runner uses `src` to
  match EP-29's actual schema. EP-33's registry classifier and EP-34's
  doc snippets must use `src` as well.


## Decision Log

- Decision: Apply the baseline by calling `loadComposition`,
  `resolveWithPrompts`, `compileComposedPlan`, and `executePlan`
  directly from inside the runner rather than shelling out to `seihou
  run`.
  Rationale: A direct call avoids spawning a child `seihou` process
  (which would re-read configs and re-evaluate Dhall only to throw
  the result away after a manifest write). It also makes the variable
  resolution path *shared* between the baseline and the blueprint's
  own vars: both call the same `resolveWithPrompts` against the same
  precedence chain, so a project with `project.name = "foo"` in
  `.seihou/config.dhall` sees `foo` everywhere — once for the base
  modules and once for the blueprint's prompt template — without
  duplication. Direct calls are also easier to test (the integration
  test passes a `--var` map and asserts on the captured argv without
  a subprocess harness). The cost is a handful of extra imports in
  `Seihou.CLI.AgentRun` (`Seihou.Composition.*`, `Seihou.Engine.Execute`);
  all are already imported by `Seihou.CLI.Run`.
  Date: 2026-05-07.

- Decision: Defer the blueprint manifest entry to EP-32. EP-31 exposes
  a `BlueprintRunOutcome` record (name, version, baseline status,
  applied-at timestamp) at the call site, marked with a `TODO(EP-32):
  write AppliedBlueprint ...` comment. The runner *does* write the
  base modules' manifest entries (existing `updateAllModules` path)
  but does not fabricate an `AppliedBlueprint` record.
  Rationale: Integration Point #5 names EP-32 as the owner of the
  manifest schema bump. Designing the writer here would commit EP-31
  to a wire format EP-32 may want to revise (for example, adding a
  `sessionId` placeholder for a future "resume" feature; see
  masterplan Decision Log). Writing a *partial* entry now would force
  EP-31 to bump the schema version half-way, which makes the diff
  harder to review.
  Date: 2026-05-07.

- Decision: Place `formatBlueprintIdentity`, `formatBaselineStatus`,
  `formatReferenceFiles` in the library at
  `seihou-cli/src/Seihou/CLI/AgentLaunch.hs`.
  Rationale: The CLI placement convention (see
  `docs/dev/architecture/overview.md` "CLI Module Placement
  Convention") states that pure helpers go in the library by
  default; `src-exe/` is reserved for modules that need
  `Options.Applicative`, `Data.FileEmbed`, `GitHash`,
  `Paths_seihou_cli`, or transitively another trapped module. The
  new formatters need none of those — they take a `Blueprint` (or
  `BaselineStatus`) and return `Text`.
  Date: 2026-05-07.

- Decision: The handler module `Seihou.CLI.AgentRun` lives in
  `src-exe/`, alongside `Seihou.CLI.Assist`, `Bootstrap`, `Setup`.
  Rationale: it imports `Seihou.CLI.Commands` (for `BlueprintRunOpts`),
  `Data.FileEmbed` (for `data/blueprint-prompt.md`), and
  `Seihou.CLI.AgentLaunchExec.launchAgentWith`. Each is a "trapping"
  import per the convention.
  Date: 2026-05-07.

- Decision: The blueprint runner's default tool allowlist is
  `setupAllowedTools` (the broader allowlist), not
  `defaultAllowedTools`.
  Rationale: a blueprint agent must write project files, run shell
  utilities, and use git the same way the setup agent does. The
  assist agent's narrower allowlist exists for template *authoring*,
  not project scaffolding. Authors who want tighter restrictions can
  set `allowedTools` on the `Blueprint` record (overrides the default).
  Date: 2026-05-07.


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

The seihou-cli is a multi-package Haskell workspace. The relevant files:

`seihou-cli/src/Seihou/CLI/AgentLaunch.hs` is the *library* module
holding pure helpers and Claude Code launch helpers that don't need
the executable's trapped dependencies. It exports `AgentContext`,
`gatherAgentContext`, `agentDirsForSession`, `defaultAllowedTools`,
`setupAllowedTools`, `bootstrapAllowedTools`, `substitute`, and
context formatters like `formatSeihouProjectState`. EP-31 *adds*
`formatBlueprintIdentity`, `formatBaselineStatus`,
`formatReferenceFiles`, and the `BaselineStatus` data type.

`seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs` is the
*executable*-side launcher. It exports `launchAgentWith :: [FilePath]
-> [String] -> Bool -> Text -> Maybe Text -> IO ()` which, in debug
mode, prints the system prompt; otherwise it shells out to `claude`
with `--system-prompt`, `--add-dir`, `--allowedTools`, and the
optional initial-prompt argv. EP-31 consumes this verbatim.

`seihou-cli/src-exe/Seihou/CLI/Assist.hs`, `Bootstrap.hs`, `Setup.hs`
are the three existing agent handlers — each is short: gather the
`AgentContext`, render the embedded prompt template, call
`launchAgentWith`. EP-31's new `Seihou.CLI.AgentRun.hs` is the fourth
in this family, the longest because it adds variable resolution and
baseline application.

`seihou-cli/src-exe/Seihou/CLI/Run.hs` is the canonical reference for
how variable resolution composes with the manifest read, plan
compilation, and plan execution. EP-31's `applyBaseline` reuses this
pipeline (`loadComposition` → `resolveWithPrompts` →
`compileComposedPlan` → `executePlan`); read lines 96-330 of that
file as a recipe.

`seihou-cli/src-exe/Seihou/CLI/Commands.hs` is the central
`optparse-applicative` definition. The existing `AgentCommand` ADT
has `AgentAssist`, `AgentBootstrap`, `AgentSetup`. EP-31 adds
`AgentRun BlueprintRunOpts` and the matching parser block (mirroring
`agentAssistInfo` / `agentAssistParser`).

`seihou-cli/data/{assist,bootstrap,setup}-prompt.md` are the three
existing system-prompt templates, embedded at compile time via
`Data.FileEmbed.embedFile`. Each uses `{{key}}` placeholders filled
at runtime by `substitute`. EP-31 adds the fourth file:
`seihou-cli/data/blueprint-prompt.md`.

`seihou-core/src/Seihou/Composition/Resolve.hs` exports
`loadComposition` (load primary + additional + transitive deps in
topological order, returning `[(ModuleInstance, Module, FilePath)]`)
and `resolveWithPrompts` (resolve every module's vars against the
precedence chain, prompting interactively for missing required
vars). EP-31 calls both directly.

`seihou-core/src/Seihou/Composition/Plan.hs` exports
`compileComposedPlan :: [(ModuleInstance, Module, FilePath, Map
VarName VarValue)] -> IO (Either [Text] ([Operation],
[CompositionWarning], Map FilePath ModuleName))`.

`seihou-core/src/Seihou/Engine/Execute.hs` exports `executePlan`,
which writes operations to disk and returns a `Map FilePath
FileRecord`.

`seihou-core/src/Seihou/Core/Types.hs` will hold the `Blueprint`
record (introduced by EP-29). Per masterplan Integration Point #1, it
contains at minimum: `name :: ModuleName`, `version :: Maybe Text`,
`description :: Maybe Text`, `prompt :: Text`, `vars :: [VarDecl]`,
`prompts :: [Prompt]`, `baseModules :: [Dependency]`, `files ::
[BlueprintFile]`, `allowedTools :: Maybe [Text]`, `tags :: [Text]`.
The `BlueprintFile` helper has `path :: FilePath` and `description ::
Maybe Text`. EP-29's `discoverRunnable` extends to return `Right
(RunnableBlueprint Blueprint FilePath)` for `blueprint.dhall`
artifacts. If EP-29 ships a different field set, consult the EP-29
plan and adjust EP-31's call sites accordingly; the masterplan's
Integration Points section is the source of truth for any revision.


## Plan of Work

### Milestone 1 — CLI parsing

By the end of this milestone, `seihou agent run --help` prints help
text, `seihou agent run my-blueprint` parses successfully (and routes
to a stub handler that exits with "not yet implemented"), and the
`optparse-applicative` parsing tests pass.

Add to `seihou-cli/src-exe/Seihou/CLI/Commands.hs`, next to
`AssistOpts`:

    data BlueprintRunOpts = BlueprintRunOpts
      { runBlueprintName       :: ModuleName
      , runBlueprintPrompt     :: Maybe Text
      , runBlueprintVars       :: [(Text, Text)]
      , runBlueprintNoBaseline :: Bool
      , runBlueprintNamespace  :: Maybe Text
      , runBlueprintContext    :: Maybe Text
      , runBlueprintVerbose    :: Bool
      , runBlueprintForce      :: Bool
      }
      deriving stock (Eq, Show, Generic)

Extend `AgentCommand` with `AgentRun BlueprintRunOpts`. Export
`BlueprintRunOpts (..)`. Add `agentRunInfo`, `agentRunParser`,
`agentRunFooter` mirroring the assist/setup pair, and add `command
"run" agentRunInfo` to `agentCommandParser`. The parser:

    agentRunParser :: Parser AgentCommand
    agentRunParser =
      fmap AgentRun $
        BlueprintRunOpts
          <$> argument moduleNameReader (metavar "BLUEPRINT" <> help "Name of the blueprint to run")
          <*> optional (argument (T.pack <$> str) (metavar "PROMPT" <> help "Optional initial user prompt"))
          <*> many (option varPair (long "var" <> metavar "KEY=VALUE" <> help "Variable override (repeatable)"))
          <*> switch (long "no-baseline" <> help "Skip applying the blueprint's baseModules before launching the agent")
          <*> optional (option (T.pack <$> str) (long "namespace" <> metavar "NS" <> help "Override namespace for config lookup"))
          <*> optional (option (T.pack <$> str) (long "context" <> short 'c' <> metavar "CTX" <> help "Override context for config lookup"))
          <*> switch (long "verbose" <> short 'v' <> help "Show detailed progress messages")
          <*> switch (long "force" <> help "Auto-resolve baseline conflicts (accept new files)")

The footer documents the workflow and three example invocations
(plain, with `--var`, with `--no-baseline`, with `--debug`).

In `seihou-cli/src-exe/Main.hs` (search for `AgentSetup` to find the
case-split), add the branch `AgentRun bro -> handleAgentRun debug
bro` and the import.

Verify by running `cabal run seihou -- agent run --help` and
observing the help text.

### Milestone 2 — Handler skeleton + prompt scaffold

By the end of this milestone, `seihou agent run my-blueprint --debug`
prints the rendered system prompt with every `{{var}}` placeholder
substituted. The `--no-baseline` flag is fully wired and renders
"(no baseline applied — `--no-baseline` was passed)" in the
"Baseline" section. The non-`--no-baseline` path is *not yet* live
and shows "(baseline application not yet implemented in this
milestone — see Milestone 3)".

Create `seihou-cli/data/blueprint-prompt.md` (full text in Concrete
Steps section below).

Create `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`. The skeleton:

    {-# LANGUAGE TemplateHaskell #-}
    module Seihou.CLI.AgentRun (handleAgentRun, BlueprintRunOutcome (..)) where

    -- imports listed under Interfaces and Dependencies

    promptTemplate :: Text
    promptTemplate = TE.decodeUtf8 $(embedFile "data/blueprint-prompt.md")

    handleAgentRun :: Bool -> BlueprintRunOpts -> IO ()
    handleAgentRun debug opts = do
      -- (a) discover & validate via discoverRunnable
      -- (b) resolve blueprint vars via resolveWithPrompts
      -- (c) apply baseline (or skip if --no-baseline)
      -- (d) render user prompt (substitute resolved vars into bp.prompt)
      -- (e) render system prompt (substitute context+identity+baseline+files+user)
      -- (f) determine add-dirs (session + blueprint files/) and allowedTools
      -- (g) launchAgentWith
      -- (h) TODO(EP-32): write AppliedBlueprint manifest entry
      ...

Add to `seihou-cli/src/Seihou/CLI/AgentLaunch.hs`:

    data BaselineStatus
      = BaselineSkipped
      | BaselineEmpty
      | BaselineApplied [(ModuleName, Maybe Text)]
      deriving (Eq, Show)

    formatBlueprintIdentity :: Blueprint -> Text
    formatBlueprintIdentity bp = T.intercalate "\n"
      [ "Name: " <> bp.name.unModuleName
      , "Version: " <> fromMaybe "(unspecified)" bp.version
      , "Description: " <> fromMaybe "(no description)" bp.description
      ]

    formatBaselineStatus :: BaselineStatus -> Text
    formatBaselineStatus BaselineSkipped =
      "(no baseline applied — `--no-baseline` was passed)"
    formatBaselineStatus BaselineEmpty =
      "(this blueprint declares no base modules)"
    formatBaselineStatus (BaselineApplied entries) =
      T.intercalate "\n" (map render entries)
      where
        render (n, Just v)  = "  - " <> n.unModuleName <> " (v" <> v <> ")"
        render (n, Nothing) = "  - " <> n.unModuleName <> " (unversioned)"

    formatReferenceFiles :: [BlueprintFile] -> Text
    formatReferenceFiles [] = "(no reference files)"
    formatReferenceFiles bfs = T.intercalate "\n" (map render bfs)
      where
        render bf = case bf.description of
          Just d  -> "  - " <> T.pack bf.path <> " — " <> d
          Nothing -> "  - " <> T.pack bf.path

Add `BaselineStatus (..)`, `formatBlueprintIdentity`,
`formatBaselineStatus`, `formatReferenceFiles` to the module's export
list. Add `Blueprint (..)`, `BlueprintFile (..)` imports from
`Seihou.Core.Types`.

The system-prompt renderer in `Seihou.CLI.AgentRun`:

    renderSystemPrompt :: AgentContext -> Blueprint -> BaselineStatus -> Text -> Text
    renderSystemPrompt ctx bp baseline userPrompt =
      substitute
        [ ("cwd", ctx.cwd)
        , ("seihou_project_state", formatSeihouProjectState ctx)
        , ("manifest_state",       formatManifestState ctx)
        , ("module_dhall_state",   formatModuleDhallState ctx)
        , ("local_modules",        formatLocalModules ctx)
        , ("available_modules",    formatAvailableModules ctx)
        , ("blueprint_name",       bp.name.unModuleName)
        , ("blueprint_version",    fromMaybe "(unspecified)" bp.version)
        , ("blueprint_description", fromMaybe "(no description)" bp.description)
        , ("baseline_status",      formatBaselineStatus baseline)
        , ("reference_files",      formatReferenceFiles bp.files)
        , ("user_prompt",          userPrompt)
        ]
        promptTemplate

The user-prompt rendering substitutes the resolved blueprint
variables into `bp.prompt`:

    renderUserPrompt :: Map VarName ResolvedVar -> Text -> Text
    renderUserPrompt resolved tpl =
      substitute [(vn.unVarName, varValueToText rv.value)
                 | (vn, rv) <- Map.toList resolved] tpl

`varValueToText` is currently private to `Seihou.CLI.Run`. EP-31
copies it (3-line function) with a comment linking to the source;
EP-32 (or a later cleanup) can promote it to a shared module once
the duplication grows.

Verify: `seihou agent run my-blueprint --debug` prints a substituted
prompt with the Milestone-3 stub message in the Baseline section;
`seihou agent run my-blueprint --no-baseline --debug` prints the
"(no baseline applied …)" message instead.

### Milestone 3 — Baseline application

By the end of this milestone, the non-`--no-baseline` path applies
every module declared in `bp.baseModules` to the cwd before
launching the agent. The base modules' manifest entries are written
via the existing `updateAllModules` path; the *blueprint* entry
remains a TODO for EP-32.

Implement `applyBaseline :: LogLevel -> [Dependency] -> ModuleName ->
Map VarName Text -> Map VarName ResolvedVar -> Maybe Text -> Maybe
Text -> Bool -> IO BaselineStatus` in `Seihou.CLI.AgentRun`. The
body mirrors `Seihou.CLI.Run.handleRun` lines 96-330 with these
adaptations:

The "primary module" is the *first* `Dependency` in `baseModules`;
the rest become `additional`. If `baseModules` is empty, the caller
(`handleAgentRun`) returns `BaselineEmpty` without calling
`applyBaseline`.

The blueprint's resolved vars (passed in as `Map VarName ResolvedVar`)
are flattened to `Map VarName Text` and unioned with the user's
`--var` overrides. They become the `cliOverrides` argument to
`resolveWithPrompts` for the base modules. This propagation is
explicit because the masterplan's Decision Log forbids the *opposite*
direction (a blueprint reading a base module's resolved vars) but
allows blueprint-vars-as-overrides for base modules — the natural
behaviour and the user expectation.

The manifest path is `.seihou/manifest.json`. Read with
`readManifest`; if absent, use `emptyManifest now`. Compile the plan
with `compileComposedPlan`; compute the diff with `computeDiff`;
resolve conflicts with `resolveConflicts force`; execute with
`executePlan`; write the updated manifest with `writeManifest`. The
new manifest contains `updateAllModules`-merged base-module entries,
the merged variable values, and the merged files. The `recipe` field
is left as `manifest.recipe`. Do not reference a `blueprint` field:
EP-32 adds it.

On any failure (composition load error, var-resolution failure,
plan-compilation failure, conflict without `--force`, execution
failure), print an actionable error message and call `exitFailure`.
The runner does *not* launch the agent if the baseline failed.

On success, return `BaselineApplied [(m.name, m.version) | (_, m, _)
<- modulesInOrder]` so the formatter renders the bullet list.

Cross-reference `Seihou.CLI.Run.handleRun` line by line; the
structure is identical except (1) blueprint discovery is already
done by the caller, (2) no recipe/blueprint manifest write here, (3)
no `--dry-run` / `--diff` / `--commit` / `--with-migrations` /
`--bump-blocked` flags. Keep `applyBaseline`'s body under ~150 lines
by factoring out a helper for the conflict-resolution block if
needed.

Verify: with a blueprint whose `baseModules = [{ module =
"haskell-base", vars = [] }]` and `haskell-base` discoverable in the
search paths, `seihou agent run my-blueprint --debug` writes
`haskell-base`'s files into cwd before printing the prompt; the
"Baseline" section reads `  - haskell-base (v<X.Y.Z>)`. Re-running is
idempotent (the diff classifies every file as `unchanged`).

### Milestone 4 — Tests + CHANGELOG

By the end of this milestone, `cabal test seihou-cli-test` passes
with the four new integration tests and the seven new formatter unit
tests, and `docs/user/CHANGELOG.md` has an entry for `seihou agent
run BLUEPRINT`.

Fixture: `seihou-cli/test/fixtures/blueprints/my-blueprint/` with
`blueprint.dhall` (name = `"my-blueprint"`, vars = `[{ name =
"service.name", type = "text", required = True, ... }]`,
`baseModules = []`, `prompt = "Set up a service called
{{service.name}}."`), and one file under `files/example.txt`. Use
EP-30's `seihou validate-blueprint` during fixture authoring to
confirm correctness.

Spec: `seihou-cli/test/Seihou/CLI/AgentRunSpec.hs` uses `temporary`
to create a temp working directory, points config at a temp
`~/.config/seihou`, copies the fixture to a discoverable location
(probably `$TMP/.seihou/blueprints/`), and invokes `handleAgentRun
True opts` from inside the test. Capture stdout via `silently` /
`hCapture`. Assert on the rendered prompt's content. Add
`Seihou.CLI.AgentRunSpec` to the test-suite's cabal `other-modules`.

Add the formatter unit tests to
`seihou-cli/test/Seihou/CLI/AgentLaunchSpec.hs` (it already imports
the relevant module).

CHANGELOG entry under "Unreleased":

    - `seihou agent run BLUEPRINT [PROMPT]` — run a blueprint: resolve
      its variables, optionally apply its baseModules, render the
      prompt, and launch Claude Code. Pass `--no-baseline` to skip
      baseline application; `--debug` to print the resolved system
      prompt without launching.


## Concrete Steps

**Step 1.** Edit `seihou-cli/src-exe/Seihou/CLI/Commands.hs` per
Milestone 1: add `BlueprintRunOpts`, the `AgentRun` constructor, the
parser block, and the `command "run"` entry.

**Step 2.** Edit `seihou-cli/src-exe/Main.hs`: add the `AgentRun bro
-> handleAgentRun debug bro` branch and the import.

**Step 3.** Create `seihou-cli/data/blueprint-prompt.md` with this
content:

    You are running a Seihou blueprint to scaffold a project. A blueprint is a
    human-authored, agent-driven runnable type. Unlike a Seihou module (which
    produces deterministic output from a fixed list of variables), a blueprint
    captures the author's intent in a Markdown prompt and asks you, the agent,
    to translate that intent into concrete project files in collaboration with
    the user.

    Your job: read the references, examine the baseline (if applied), understand
    the user's task below, and produce the requested files. Iterate with the
    user until they are satisfied. Validate your work with `seihou` and `git`
    commands as you go.


    ## Current Environment

    Working directory: {{cwd}}
    {{seihou_project_state}}
    {{manifest_state}}
    {{module_dhall_state}}
    {{local_modules}}
    {{available_modules}}


    ## Blueprint Identity

    Name: {{blueprint_name}}
    Version: {{blueprint_version}}
    Description: {{blueprint_description}}


    ## Baseline

    {{baseline_status}}


    ## Reference Files

    The blueprint includes the following reference files in its `files/`
    subdirectory. You have read access to them via `--add-dir`. You may copy,
    adapt, or learn from them — but the user's project files are written in
    the working directory above, not in the references directory.

    {{reference_files}}


    ## Your Task

    {{user_prompt}}


    ## Workflow

    1. **Read the references.** Use `Read` on each file under the blueprint's
       `files/` directory (paths in the Reference Files section above).
       Understand what each file demonstrates before deciding what to copy or
       adapt.

    2. **Examine the baseline.** If the Baseline section above lists applied
       modules, the project already contains files generated from them. Run
       `seihou status` and `git status` to see what's there. Read the key
       files (README, primary source files, build config) before extending
       them.

    3. **Draft.** Use `Write` for new files and `Edit` for modifications.
       Prefer additive changes — leave the baseline files in place and extend
       them, rather than rewriting them, unless the user specifically asks
       otherwise.

    4. **Validate.** Run `seihou status` and `seihou diff` to check that
       manifest state and disk state are consistent. Run any project-specific
       checks (e.g. `cabal build`, `nix flake check`) the references or
       baseline imply.

    5. **Commit.** Use `git add` and `git commit` to record the work.
       Reference the blueprint name in the commit message:
       "Apply blueprint {{blueprint_name}} for <user-supplied summary>".


    ## Tool Guidelines

    - Use `Read` to examine baseline and reference files before editing.
    - Use `Edit` for surgical changes to existing files; `Write` for new files.
    - Use `Bash` for `seihou`, `git`, `mkdir`, `ls`, and other shell commands.
    - Run `seihou validate-module` if you create or modify any `module.dhall`
      file (the user may want to package the result as a reusable module
      after the session).
    - When in doubt about the user's intent, ask. A blueprint is an
      *interactive* session, not a one-shot generator.

**Step 4.** Edit `seihou-cli/seihou-cli.cabal`. Add
`Seihou.CLI.AgentRun` to `executable seihou`'s `other-modules` (after
`Seihou.CLI.Assist`). Add `data/blueprint-prompt.md` to
`extra-source-files` (or the field where the existing
`{assist,bootstrap,setup}-prompt.md` files are listed; check by
searching for `assist-prompt` in the cabal file).

**Step 5.** Edit `seihou-cli/src/Seihou/CLI/AgentLaunch.hs`. Add
`BaselineStatus` data type, the three formatters, the imports, and
the export-list entries. Add `Blueprint`/`BlueprintFile` imports
from `Seihou.Core.Types`.

**Step 6.** Create `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`. The
full module body:

    {-# LANGUAGE TemplateHaskell #-}
    module Seihou.CLI.AgentRun
      ( handleAgentRun
      , BlueprintRunOutcome (..)
      ) where

    -- (imports listed in "Interfaces and Dependencies")

    promptTemplate :: Text
    promptTemplate = TE.decodeUtf8 $(embedFile "data/blueprint-prompt.md")

    handleAgentRun :: Bool -> BlueprintRunOpts -> IO ()
    handleAgentRun debug opts = do
      let level = if opts.runBlueprintVerbose then LogVerbose else LogNormal

      -- (a) discover & validate
      searchPaths <- defaultSearchPaths
      runnableResult <- discoverRunnable searchPaths opts.runBlueprintName
      (bp, blueprintDir) <- case runnableResult of
        Right (RunnableBlueprint b dir) -> pure (b, dir)
        Right (RunnableModule _ _) ->
          exitErr level
            ( "'" <> opts.runBlueprintName.unModuleName
              <> "' is a module, not a blueprint. Did you mean 'seihou run "
              <> opts.runBlueprintName.unModuleName <> "'?" )
        Right (RunnableRecipe _ _) ->
          exitErr level
            ( "'" <> opts.runBlueprintName.unModuleName
              <> "' is a recipe, not a blueprint. Did you mean 'seihou run "
              <> opts.runBlueprintName.unModuleName <> "'?" )
        Left err -> exitErr level (renderModuleLoadError err)

      -- (b) resolve blueprint vars by wrapping them in a placeholder Module
      --     so resolveWithPrompts can reuse the standard precedence chain.
      --     The placeholder has empty steps/commands/dependencies; nothing
      --     is generated by it. The blueprint's prompts list flows through
      --     verbatim, so interactive prompts work identically to a module's.
      let placeholderModule = Module
            { name = bp.name, version = bp.version
            , description = bp.description
            , vars = bp.vars, exports = []
            , prompts = bp.prompts
            , steps = [], commands = [], dependencies = []
            , removal = Nothing, migrations = []
            }
          placeholderInst = primaryInstance bp.name
          placeholderTriple = (placeholderInst, placeholderModule, blueprintDir)

      envPairs <- getEnvironment
      let cliOverrides = Map.fromList [(VarName k, v) | (k, v) <- opts.runBlueprintVars]
          envVars = Map.fromList [(T.pack k, T.pack v) | (k, v) <- envPairs]
          namespace = fromMaybe (deriveNamespace bp.name) opts.runBlueprintNamespace
      context <- resolveContext opts.runBlueprintContext envVars
      let contextName = fromMaybe "" context

      resolveResult <- runEff $ runConfigReader $ runConsole $ do
        localCfg <- readLocalConfig    >>= unwrapConfig level
        nsCfg    <- readNamespaceConfig namespace >>= unwrapConfig level
        ctxCfg   <- readContextConfig   contextName >>= unwrapConfig level
        gCfg     <- readGlobalConfig    >>= unwrapConfig level
        resolveWithPrompts [placeholderTriple] cliOverrides envVars
          namespace contextName
          (toVarNameMap localCfg) (toVarNameMap nsCfg)
          (toVarNameMap ctxCfg)   (toVarNameMap gCfg)

      resolved <- case resolveResult of
        Left errs -> do
          logIO level (logError "Error resolving blueprint variables:")
          mapM_ (logIO level . logError . ("  " <>) . formatVarError) errs
          exitFailure
        Right r -> pure (Map.findWithDefault Map.empty placeholderInst r)

      -- (c) baseline
      baseline <-
        if opts.runBlueprintNoBaseline then pure BaselineSkipped
        else if null bp.baseModules    then pure BaselineEmpty
        else applyBaseline level bp.baseModules bp.name
                cliOverrides resolved
                opts.runBlueprintNamespace opts.runBlueprintContext
                opts.runBlueprintForce

      -- (d) render user prompt
      let renderedUser = renderUserPrompt resolved bp.prompt

      -- (e) render system prompt
      ctx <- gatherAgentContext
      let systemPrompt = renderSystemPrompt ctx bp baseline renderedUser

      -- (f) add-dirs and tools
      sessionDirs <- agentDirsForSession
      let filesDir = blueprintDir </> "files"
      filesDirExists <- doesDirectoryExist filesDir
      let addDirs = sessionDirs ++ [filesDir | filesDirExists]
          tools = case bp.allowedTools of
                    Just custom -> map T.unpack custom
                    Nothing     -> setupAllowedTools

      -- (g) launch
      launchAgentWith addDirs tools debug systemPrompt opts.runBlueprintPrompt

      -- (h) TODO(EP-32): write AppliedBlueprint{name = bp.name,
      --     version = bp.version, baseline = baseline,
      --     appliedAt = now} to .seihou/manifest.json. EP-32 owns the
      --     manifest schema bump and the writer.
      pure ()

The `applyBaseline` function follows the structure of
`Seihou.CLI.Run.handleRun` with the adaptations described in
Milestone 3. `renderSystemPrompt`, `renderUserPrompt`,
`varValueToText`, `exitErr`, `renderModuleLoadError` are local
helpers as defined in Milestone 2. `BlueprintRunOutcome` is exposed
for EP-32 (see Interfaces and Dependencies).

**Step 7.** Add the integration spec at
`seihou-cli/test/Seihou/CLI/AgentRunSpec.hs`, the fixture under
`seihou-cli/test/fixtures/blueprints/my-blueprint/`, and the
formatter unit tests in
`seihou-cli/test/Seihou/CLI/AgentLaunchSpec.hs`. Add
`Seihou.CLI.AgentRunSpec` to the test-suite cabal `other-modules`.

**Step 8.** Add the CHANGELOG entry to `docs/user/CHANGELOG.md` per
Milestone 4.


## Validation and Acceptance

**Acceptance 1 (parsing).** `cabal run seihou -- agent run --help`
prints help text including the BLUEPRINT positional, the optional
PROMPT positional, and every flag from `BlueprintRunOpts`. `cabal run
seihou -- agent run` (no argument) fails with the standard
"Missing: BLUEPRINT" message.

**Acceptance 2 (debug rendering with --no-baseline).** Inside a
fixture directory containing the test blueprint `my-blueprint`,

    cabal run seihou -- agent run my-blueprint \
      "set up a billing service" \
      --var service.name=billing --no-baseline --debug

prints the rendered system prompt to stdout. The test asserts:

- `## Blueprint Identity` followed by `Name: my-blueprint`,
  `Version: <version-or-(unspecified)>`, `Description: ...`.
- `## Baseline` followed by ``(no baseline applied — `--no-baseline`
  was passed)``.
- `## Reference Files` followed by `  - example.txt — <description>`
  (the fixture's `files/` has one entry).
- `## Your Task` followed by `Set up a service called billing.`
  (substituting `service.name` from the `--var`).
- Exit code 0.

**Acceptance 3 (debug rendering with baseline).** With a fixture
blueprint whose `baseModules = [{ module = "haskell-base", vars = []
}]` and `haskell-base` discoverable under
`~/.config/seihou/installed/`, `cabal run seihou -- agent run
my-blueprint --debug` prints a system prompt where `## Baseline` is
followed by `  - haskell-base (v0.1.0)` (or the actual installed
version). The cwd contains the haskell-base output files (because
debug mode prints the prompt and exits — but the baseline ran first).

**Acceptance 4 (var resolution failure, non-interactive).**

    echo "" | cabal run seihou -- agent run my-blueprint --no-baseline --debug

(no `--var` and no config providing `service.name`, stdin not a tty)
exits with code 1 and prints `Error resolving blueprint variables:`
followed by `  Required variable 'service.name' is not set` (or the
text produced by `formatVarError` for `MissingRequiredVar`). The
agent is *not* launched.

**Acceptance 5 (claude argv).** A test using `process` and a stub
`claude` script that records its argv: invoke the runner without
`--debug`, with the stub on PATH. The captured argv contains
`--system-prompt <prompt>`, `--add-dir <session-dir>` (if any),
`--add-dir <blueprint-files-dir>`, one `--allowedTools` per entry in
`setupAllowedTools` (or the blueprint's override), and the user's
positional `[PROMPT]` if supplied.

**Acceptance 6 (formatter unit tests).**

    formatBaselineStatus BaselineSkipped
      `shouldBe` "(no baseline applied — `--no-baseline` was passed)"
    formatBaselineStatus BaselineEmpty
      `shouldBe` "(this blueprint declares no base modules)"
    formatBaselineStatus (BaselineApplied [(ModuleName "foo", Just "1.0.0")])
      `shouldBe` "  - foo (v1.0.0)"
    formatBaselineStatus (BaselineApplied [(ModuleName "foo", Nothing)])
      `shouldBe` "  - foo (unversioned)"
    formatReferenceFiles []
      `shouldBe` "(no reference files)"
    formatReferenceFiles [BlueprintFile { path = "x.txt", description = Just "an example" }]
      `shouldBe` "  - x.txt — an example"
    formatBlueprintIdentity (Blueprint { name = ModuleName "bp", version = Just "0.1", description = Just "a thing", ... })
      `shouldBe` "Name: bp\nVersion: 0.1\nDescription: a thing"

**Acceptance 7 (full suite).** `cabal test seihou-cli-test` and
`nix flake check` both pass; the latter exercises
`nix/check-cli-module-placement.sh` which would fail if
`Seihou.CLI.AgentRun` were placed in `src/` rather than `src-exe/`,
or vice versa for the formatters.


## Idempotence and Recovery

Re-running `seihou agent run my-blueprint` is safe:

- **Variable resolution** is pure with respect to the project's
  config files and CLI overrides. Identical inputs produce identical
  outputs.
- **Baseline application** delegates to the same composition pipeline
  `seihou run` uses. The diff path classifies every file as `new`,
  `modified`, `unchanged`, or `conflict`; only `new` and (with
  conflict resolution) `modified` files are written. A second
  invocation with no input changes hits the `unchanged` branch for
  every base-module file and writes nothing.
- **Manifest write** uses the same `writeManifest` call `seihou run`
  uses. Re-running does not duplicate manifest entries
  (`updateAllModules` keys by `(name, parentVars)`).
- **Agent launch** is the only non-idempotent step: launching Claude
  Code starts an interactive session. EP-31 does not record session
  state — every invocation starts a fresh Claude session.

**Recovery from a failed baseline.** If `applyBaseline` fails, the
runner exits before launching the agent and prints an actionable
error. The user fixes the issue (installs the missing module, sets
the missing variable, edits the conflicting file, or passes `--force`
/ `--no-baseline`) and re-runs. The manifest write is the last step
of `applyBaseline`, so a failure earlier in the pipeline produces no
manifest write at all. Files written before the failure (if any) are
left on disk — matching `seihou run`'s behaviour when `executePlan`
fails partway. `git status` shows what was written.

**Recovery from a failed agent launch.** If `claude` is not on PATH,
`launchAgentWith` prints an installation hint and exits with code 1
(existing behaviour). The baseline has already been applied at this
point (step f follows step c), so project files are still on disk and
the manifest is updated for the base modules. Installing Claude and
re-running goes straight to the agent launch (the second baseline
application classifies every file as `unchanged`).


## Interfaces and Dependencies

### `Seihou.CLI.AgentRun` (new, at `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`)

Imports:

    import Control.Monad (when)
    import Data.FileEmbed (embedFile)
    import Data.Map.Strict qualified as Map
    import Data.Maybe (fromMaybe)
    import Data.Text qualified as T
    import Data.Text.Encoding qualified as TE
    import Data.Time (UTCTime)
    import Data.Time.Clock (getCurrentTime)
    import Seihou.CLI.AgentLaunch
      ( AgentContext (..), BaselineStatus (..)
      , agentDirsForSession
      , formatAvailableModules, formatBaselineStatus
      , formatBlueprintIdentity, formatLocalModules
      , formatManifestState, formatModuleDhallState
      , formatReferenceFiles, formatSeihouProjectState
      , gatherAgentContext, setupAllowedTools, substitute
      )
    import Seihou.CLI.AgentLaunchExec (launchAgentWith)
    import Seihou.CLI.Commands (BlueprintRunOpts (..))
    import Seihou.CLI.Shared
      ( deriveNamespace, formatVarError, logIO
      , toVarNameMap, unwrapConfig
      )
    import Seihou.Composition.Instance (ModuleInstance (..), primaryInstance)
    import Seihou.Composition.Plan (compileComposedPlan)
    import Seihou.Composition.Resolve (loadComposition, resolveWithPrompts)
    import Seihou.Core.Context (resolveContext)
    import Seihou.Core.Module (defaultSearchPaths, discoverRunnable)
    import Seihou.Core.Types
    import Seihou.Effect.ConfigReader
      (readContextConfig, readGlobalConfig, readLocalConfig, readNamespaceConfig)
    import Seihou.Effect.ConfigReaderInterp (runConfigReader)
    import Seihou.Effect.ConsoleInterp (runConsole)
    import Seihou.Effect.Filesystem (createDirectoryIfMissing)
    import Seihou.Effect.FilesystemInterp (runFilesystem)
    import Seihou.Effect.Logger (logError, logInfo)
    import Seihou.Effect.ManifestStore (readManifest, writeManifest)
    import Seihou.Effect.ManifestStoreInterp (runManifestStore)
    import Seihou.Engine.Conflict (resolveConflicts)
    import Seihou.Engine.Diff (computeDiff)
    import Seihou.Engine.Execute (executePlan)
    import Seihou.Manifest.Types (currentManifestVersion, emptyManifest)
    import Seihou.Prelude
    import System.Directory (doesDirectoryExist)
    import System.Environment (getEnvironment)
    import System.Exit (exitFailure)
    import System.FilePath ((</>), takeDirectory)

Exports and signatures:

    handleAgentRun :: Bool -> BlueprintRunOpts -> IO ()

    data BlueprintRunOutcome = BlueprintRunOutcome
      { outcomeBlueprintName    :: ModuleName
      , outcomeBlueprintVersion :: Maybe Text
      , outcomeBaseline         :: BaselineStatus
      , outcomeAppliedAt        :: UTCTime
      }
      -- Returned at the call site for EP-32's manifest writer to consume.

Internal helpers:

    applyBaseline       :: LogLevel -> [Dependency] -> ModuleName
                        -> Map VarName Text -> Map VarName ResolvedVar
                        -> Maybe Text -> Maybe Text -> Bool
                        -> IO BaselineStatus
    renderSystemPrompt  :: AgentContext -> Blueprint -> BaselineStatus -> Text -> Text
    renderUserPrompt    :: Map VarName ResolvedVar -> Text -> Text
    varValueToText      :: VarValue -> Text
    exitErr             :: LogLevel -> Text -> IO a
    renderModuleLoadError :: ModuleLoadError -> Text

### `Seihou.CLI.AgentLaunch` (modified, at `seihou-cli/src/Seihou/CLI/AgentLaunch.hs`)

Adds imports:

    import Seihou.Core.Types (Blueprint (..), BlueprintFile (..), ModuleName (..))

Adds exports:

    BaselineStatus (..)
    formatBlueprintIdentity :: Blueprint -> Text
    formatBaselineStatus    :: BaselineStatus -> Text
    formatReferenceFiles    :: [BlueprintFile] -> Text

Implementations are listed under Milestone 2.

### `Seihou.CLI.Commands` (modified, at `seihou-cli/src-exe/Seihou/CLI/Commands.hs`)

Adds the `BlueprintRunOpts` record, the `AgentRun BlueprintRunOpts`
constructor, the parser block (`agentRunInfo`, `agentRunParser`,
`agentRunFooter`), and the `command "run" agentRunInfo` entry in
`agentCommandParser`. Exports `BlueprintRunOpts (..)`.

### `Main.hs` (modified, at `seihou-cli/src-exe/Main.hs`)

Adds an import of `Seihou.CLI.AgentRun` and the case branch
`AgentRun bro -> handleAgentRun debug bro` in the `AgentCommand`
case-split.

### `seihou-cli/seihou-cli.cabal` (modified)

Adds `Seihou.CLI.AgentRun` to `executable seihou`'s `other-modules`.
Adds `data/blueprint-prompt.md` to whichever cabal field embeds the
existing `{assist,bootstrap,setup}-prompt.md` files. Adds
`Seihou.CLI.AgentRunSpec` to the `seihou-cli-test` test-suite's
`other-modules`.

### `seihou-cli/data/blueprint-prompt.md` (new)

Full text in Step 3 of Concrete Steps.

### Test fixture (new)

`seihou-cli/test/fixtures/blueprints/my-blueprint/blueprint.dhall`
and `seihou-cli/test/fixtures/blueprints/my-blueprint/files/example.txt`.
The exact Dhall syntax is defined by EP-29's schema; adjust during
implementation to match.

### `Seihou.CLI.AgentRunSpec` (new test, at `seihou-cli/test/Seihou/CLI/AgentRunSpec.hs`)

Imports `Seihou.CLI.AgentRun`, `Seihou.CLI.Commands`, `temporary`,
hspec/tasty machinery, and a stdout-capture helper (`silently` /
`hCapture` from `Test.Hspec` or `System.IO.Silently`). Each test
captures stdout, invokes `handleAgentRun True opts`, and asserts on
the captured text.

### Cross-plan contracts

*To EP-29:* this plan assumes `discoverRunnable` returns `Right
(RunnableBlueprint Blueprint FilePath)` for `blueprint.dhall`
artifacts, with the `Blueprint` field set listed under "Context and
Orientation" above. Adjust pattern matches if EP-29 ships a different
shape.

*To EP-30:* the test fixture is vetted with `seihou validate-blueprint`
during development. The runner does *not* invoke `validate-blueprint`
at runtime — it relies on EP-29's `validateBlueprint` performed as
part of `discoverRunnable`.

*From EP-32:* EP-32 reads `BlueprintRunOutcome` (or revises its
shape) and writes the `AppliedBlueprint` manifest entry. The
`TODO(EP-32)` comment in `handleAgentRun` step (h) is the hand-off
point. EP-32 also bumps `currentManifestVersion`; EP-31 imports the
constant but does not bump it.

### Dependencies

EP-31 introduces no new cabal dependencies. Every import is already
present in the executable's or the internal library's
`build-depends`: `directory`, `filepath`, `text`, `time`,
`containers`, `effectful-core`, `process`, `bytestring`,
`file-embed`, `optparse-applicative`, `seihou-core`,
`seihou-cli-internal`. The test suite already has `hspec`, `tasty`,
`tasty-hspec`, `temporary`, `directory`, `filepath`, `process`.


## Revision History

(None yet.)
