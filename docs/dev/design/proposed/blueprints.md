# Blueprints

| Field | Value |
|---|---|
| **Status** | Implemented |
| **Created** | 2026-05-07 |
| **Updated** | 2026-05-08 |
| **Subsystem** | Core — Runnable Artifacts |

## Overview

A blueprint is the third runnable artifact kind in Seihou, alongside modules and recipes. Where a module is a deterministic generator (typed inputs in, exact files out) and a recipe is a named composition of modules with pre-bound variables, a blueprint is a *non-deterministic* artifact authored for an AI coding agent to consume. It bundles a prompt template, an optional baseline of modules to apply before the agent takes over, and an optional `files/` directory of reference snippets the agent may copy or adapt. Blueprints are not directly runnable: `seihou run my-blueprint` refuses with an actionable message and the user runs `seihou agent run my-blueprint [PROMPT]` instead, which optionally applies the baseline and then launches a Claude Code session pre-loaded with the rendered prompt.

## Motivation

The deterministic shape works beautifully for project shapes that vary along small, well-understood axes (project name, license, list of GHC extensions, Nix system tuple, etc.). It fits poorly for project shapes whose variation is inherently open-ended: "scaffold a microservice for $domain", "set up a CI pipeline that mirrors $existingProject's conventions", "wire in observability that matches our team's $existingPattern". Encoding all the relevant axes as typed `VarDecl`s produces modules with dozens of optional variables, brittle template matrices, and far too many `{{#if}}` branches; a human author rapidly hits the limit of what is reasonable to enumerate ahead of time. Blueprints are the escape hatch: an author writes a prompt that explains the conventions, lists the baseline modules to apply for a known-good starting point, and ships reference files; the AI agent then drives the open-ended customisation under the user's supervision. The deterministic surface (modules and recipes) stays uncluttered.

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Naming | "Blueprint" / `blueprint.dhall` / `RunnableBlueprint` | Connotes "a base plan an agent customises" without overloading existing terminology in the codebase ("module", "recipe", "scaffold", "template" are all taken). |
| Namespace | Shared with modules and recipes (`[a-z][a-z0-9-]*`) | A single `discoverRunnable` lookup resolves all three kinds; cross-kind name collisions are validated at registry-validation time. |
| Run command | `seihou agent run BLUEPRINT [PROMPT]` | Co-locates with the existing `seihou agent` namespace (`assist`, `bootstrap`, `setup`); `seihou run BLUEPRINT` refuses with an actionable message directing the user to the agent runner. |
| Discovery priority | module > recipe > blueprint within a single directory | Mirrors the existing module > recipe fall-through; a stray `module.dhall` next to a `blueprint.dhall` silently surfaces the more specific, deterministic artifact. |
| Baseline application | Default on; `--no-baseline` skips | Authors declare base modules so the agent starts from a validated scaffold; `--no-baseline` is a power-user override for cases where the agent should drive every decision from scratch. |
| Migrations | Not supported | Blueprint output is non-deterministic; the manifest's `files` map cannot be authoritatively rewritten by an author-supplied chain. Updating a project from `my-blueprint v0.1.0` to `v0.2.0` is the agent's job, run interactively. |
| Resume support | Deferred to a future plan | The v1 manifest entry records *that* a blueprint was applied with version and timestamp, but not the conversation contents. The schema is designed to be extended; `agentSessionId` is the obvious extension point. |
| Agent backend | Claude Code only (via `launchAgentWith`) | Reuses the existing shell-out path; a pluggable backend (LangGraph, Aider, Cline) is a future initiative. |

## Domain Model

The blueprint type and its supporting constructors live in `seihou-core/src/Seihou/Core/Types.hs` (lines 273–306). The applied-blueprint manifest entry lives at lines 415–437 of the same file.

### Blueprint

    data BlueprintFile = BlueprintFile
      { src :: FilePath,
        description :: Maybe Text
      }
      deriving stock (Eq, Show, Generic)

    data Blueprint = Blueprint
      { name :: ModuleName,
        version :: Maybe Text,
        description :: Maybe Text,
        prompt :: Text,
        vars :: [VarDecl],
        prompts :: [Prompt],
        baseModules :: [Dependency],
        files :: [BlueprintFile],
        allowedTools :: Maybe [Text],
        tags :: [Text]
      }
      deriving stock (Eq, Show, Generic)

`name` reuses `ModuleName` so blueprints share the `[a-z][a-z0-9-]*` namespace with modules and recipes. `prompt` is the rendered Markdown body the agent receives; substitution against `vars` happens at runner time. `baseModules` reuses `Dependency` for its parent-vars binding shape — at validation time each entry must resolve to a *module* or *recipe*, never another blueprint. `files` is typed (rather than a free string list) so the validator can verify each entry exists at validation time. `allowedTools`, when set, overrides the runner's default Claude Code `--allowedTools` allowlist.

### Runnable extension

    data Runnable
      = RunnableModule Module FilePath
      | RunnableRecipe Recipe FilePath
      | RunnableBlueprint Blueprint FilePath
      deriving stock (Show)

The `RunnableBlueprint` constructor was added in EP-29. The codebase compiles with `-Wincomplete-patterns`, so every existing `case` over `Runnable` had to gain a third arm in the same commit (notably the run-refusal arm in `seihou-cli/src-exe/Seihou/CLI/Run.hs` and the formatter sites in `seihou-cli/src/Seihou/CLI/List.hs` and `seihou-cli/src/Seihou/Fzf/Selector/Module.hs`).

### AppliedBlueprint

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

The agent owns file output, so this entry describes the *invocation* (which blueprint, which baseline, the user's prompt) — not the file set the agent produced. `noBaseline` distinguishes "no baseline declared" (`baselineModules = []`, `noBaseline = False`) from "baseline skipped by user" (`baselineModules = []`, `noBaseline = True`). `agentSessionId` is reserved for the deferred resume feature; in v1 it is always `Nothing` and the encoder omits the JSON key in that case.

## Dhall Schema

The canonical Dhall schema for blueprints is in `schema/Blueprint.dhall`, mirrored into the public `seihou-schema` repository:

    let VarDecl = ./VarDecl.dhall
    let Prompt = ./Prompt.dhall
    let Dependency = ./Dependency.dhall

    let BlueprintFile =
          { Type = { src : Text, description : Optional Text }
          , default = { description = None Text }
          }

    in  { Type =
            { name : Text
            , version : Optional Text
            , description : Optional Text
            , prompt : Text
            , vars : List VarDecl.Type
            , prompts : List Prompt.Type
            , baseModules : List Dependency.Type
            , files : List BlueprintFile.Type
            , allowedTools : Optional (List Text)
            , tags : List Text
            }
        , default =
            { version = None Text
            , description = None Text
            , vars = [] : List VarDecl.Type
            , prompts = [] : List Prompt.Type
            , baseModules = [] : List Dependency.Type
            , files = [] : List BlueprintFile.Type
            , allowedTools = None (List Text)
            , tags = [] : List Text
            }
        , BlueprintFile = BlueprintFile
        }

Note that `BlueprintFile` is exported as a nested record under `S.Blueprint.BlueprintFile`, **not** as a top-level `S.BlueprintFile`. Authors writing `[] : List S.Blueprint.BlueprintFile.Type` for an empty `files` list are following the shipped shape; `seihou new-blueprint`'s scaffold uses this form.

The schema URL and integrity hash for `seihou-schema` are pinned in `seihou-cli/src/Seihou/CLI/SchemaVersion.hs`. (`mori.dhall` pins `mori-schema`, a separate schema, and is not involved in seihou-schema bumps.)

## Validation Rules

The validator lives in `seihou-core/src/Seihou/Core/Blueprint.hs`. Calling `validateBlueprint baseDir b` runs all rules and returns either `Right b` or `Left (ValidationError name msgs)` aggregating every failure. The function uses `defaultSearchPaths` internally for resolving base-module references; tests can pin lookup roots via the sibling `validateBlueprintWith :: [FilePath] -> FilePath -> Blueprint -> IO ...`.

The rules, in numeric order matching the source:

1. **Name format.** `name` must match `[a-z][a-z0-9-]*`. Error: `blueprint name must match [a-z][a-z0-9-]*, got: <name>`.
2. **Version, if present, non-empty.** A blueprint may legitimately omit a version during early authoring; the validator only rejects `Just ""`. Error: `blueprint version, if specified, must not be empty`.
3. **Prompt non-empty.** The `prompt` body must contain non-whitespace content. Error: `blueprint prompt must not be empty`.
4. **Unique variable names.** Declared `vars` names must be unique. Error: `duplicate variable name: <name>`.
5. **Prompt references.** Every interactive `Prompt` in `prompts` must reference a declared variable in `vars`. Error: `prompt references undeclared variable: <name>`.
6. **Base modules resolve.** Each `baseModules` entry's `depModule` must be a valid module-name format, its var-binding keys must each match a `[a-z][a-z0-9.-]*` pattern, and the name must resolve via `discoverRunnable` to a `RunnableModule` or `RunnableRecipe`. Errors: `invalid baseModule name: <name>`, `baseModule '<name>' has invalid var binding name: <key>`, `baseModule '<name>' resolves to a blueprint; baseModules must be modules or recipes`, `baseModule '<name>' not found in any search path`, `baseModule '<name>' failed to load`.
7. **Files exist.** For every entry in `files`, the path `baseDir/files/<src>` must exist on disk. Error: `blueprint file not found: <src>`.
8. **Tags non-empty.** Each tag in `tags` must contain non-whitespace content. Error: `tag must not be empty`.
9. **Allowed tools non-empty.** When `allowedTools` is set, each entry must contain non-whitespace content. Error: `allowedTools entry must not be empty`.

Validation errors are aggregated: a single `validateBlueprint` call returns *every* violation, not just the first.

## Discovery

The discovery extension lives in `seihou-core/src/Seihou/Core/Module.hs`. The relevant entry points are:

- `discoverRunnable :: [FilePath] -> ModuleName -> IO (Either ModuleLoadError Runnable)` — name resolution. For each search-path directory, checks `module.dhall`, then `recipe.dhall`, then `blueprint.dhall`. Returns the first match. The priority within a single directory is **module > recipe > blueprint** so a stray `module.dhall` next to a `blueprint.dhall` silently surfaces the module — the more specific, deterministic artifact wins (lines 60–99).
- `discoverBlueprint :: [FilePath] -> ModuleName -> IO (Either ModuleLoadError FilePath)` — kind-specific lookup. Mirrors `discoverModule` for callers that only care about discovering a blueprint by name (lines 106–117).
- `discoverAllRunnables :: [FilePath] -> IO [DiscoveredRunnable]` — full enumeration used by `seihou list` (line 393). Each entry carries a `RunnableKind` discriminator: `KindModule`, `KindRecipe`, or `KindBlueprint`.

The default search paths (`defaultSearchPaths`) are unchanged from modules and recipes:

1. `.seihou/modules/` relative to the current directory.
2. `~/.config/seihou/modules/`.
3. `~/.config/seihou/installed/` (where `seihou install` places cloned artifacts).

## Runner Workflow

The agent runner is `Seihou.CLI.AgentRun.handleAgentRun` in `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`. The handler executes the following steps in order; each step has a one-letter comment in the source so the flow is easy to track.

**(a) Discover and validate.** `defaultSearchPaths` plus `Seihou.Core.Module.discoverRunnable` resolve the user-typed `BLUEPRINT` argument. A `RunnableModule` or `RunnableRecipe` result yields an actionable error suggesting `seihou run NAME` instead; only `RunnableBlueprint` proceeds. The runner does not call `validateBlueprint` directly — discovery already evaluated the Dhall, and any field-level errors surfaced as a `DhallDecodeError` from `evalBlueprintFromFile`. The validator is exercised by `seihou validate-blueprint` for authoring-time feedback (see `seihou-cli/src-exe/Seihou/CLI/ValidateBlueprint.hs`).

**(b) Resolve blueprint variables.** The runner wraps the blueprint's `vars` and `prompts` in a placeholder `Module` so the existing `Seihou.Composition.Resolve.resolveWithPrompts` can run the standard precedence chain: CLI → env → local → namespace → context → global → defaults → interactive prompts. See `docs/dev/design/proposed/variable-resolution.md` for the full chain. The placeholder module has empty `steps`, `commands`, `dependencies`, `migrations`, and `removal` so it never participates in plan compilation; it exists solely to drive variable resolution.

**(c) Apply baseline.** If `--no-baseline` was passed the baseline status is `BaselineSkipped`; if the blueprint declared no baseline, the status is `BaselineEmpty`; otherwise `applyBaseline` runs. The baseline application mirrors `Seihou.CLI.Run.handleRun`: load the composition (`Seihou.Composition.Resolve.loadComposition` for the primary base module plus transitive deps), resolve variables (with the blueprint's resolved vars folded into the CLI override map so the agent's prompt and the base modules see the same values), compile the plan (`compileComposedPlan`), compute the diff, resolve conflicts, execute, and write the manifest. CLI overrides win over blueprint-supplied values — exactly the way `seihou run`'s overrides win.

**(d) Render the user prompt.** `renderUserPrompt` substitutes resolved blueprint variables into `bp.prompt` using the same `Seihou.CLI.AgentLaunch.substitute` helper that the other agent prompts use. Each `{{var.name}}` in the blueprint's prompt body is replaced with the resolved value's text form (booleans become `true`/`false`, lists become comma-joined).

**(e) Render the system prompt.** `renderSystemPrompt` stitches together the embedded system-prompt scaffold at `seihou-cli/data/blueprint-prompt.md` (compiled in via `Data.FileEmbed`) with twelve placeholder fills: working directory, seihou-project state, manifest state, module.dhall state, local modules, available modules, blueprint name, blueprint version, blueprint description, baseline status, reference files, and the rendered user prompt body. The scaffold is the agent's "system message"; the user-typed `[PROMPT]` argument (from `BlueprintRunOpts.runBlueprintPrompt`) becomes Claude's first user turn.

**(f) Add-dirs and tool allowlist.** The session's working directory is mounted via `agentDirsForSession`; the blueprint's `<blueprintDir>/files` is mounted via `--add-dir` when it exists on disk. The `allowedTools` allowlist is `bp.allowedTools` if set, otherwise `Seihou.CLI.AgentLaunch.setupAllowedTools` (the documented default that already governs the `setup`/`bootstrap` commands).

**(g) Launch.** `Seihou.CLI.AgentLaunchExec.launchAgentWith` shells out to the `claude` CLI with the rendered system prompt and the user prompt. It returns the subprocess `ExitCode` so the caller can perform post-launch bookkeeping. (`launchAgentWith` originally called `exitWith` itself; EP-32 refactored it so the manifest write could happen after a successful agent exit.)

**(h) Record provenance.** On a clean `ExitSuccess`, the runner builds an `AppliedBlueprint` via `appliedBlueprintFromOutcome` and calls `Seihou.CLI.AppliedBlueprint.recordAppliedBlueprint` (in the `seihou-cli-internal` library at `seihou-cli/src/Seihou/CLI/AppliedBlueprint.hs`) to merge the entry into `.seihou/manifest.json`. A non-zero exit (Ctrl-C, `claude` failure, user-quit) skips the write — the recorded blueprint always reflects the most recent *successful* application.

The `--debug` flag (parent: `seihou agent --debug run …`) prints the resolved system prompt to stdout instead of launching Claude. The debug path still applies the baseline (so files are written to disk) but does not start an interactive session.

## System-Prompt Scaffold

The embedded scaffold at `seihou-cli/data/blueprint-prompt.md` mirrors the shape of the sibling agent prompts (`assist-prompt.md`, `bootstrap-prompt.md`, `setup-prompt.md`). Twelve `{{key}}` placeholders are filled at runtime:

- `cwd` — working directory.
- `seihou_project_state`, `manifest_state`, `module_dhall_state` — environment context (formatters in `Seihou.CLI.AgentLaunch`).
- `local_modules`, `available_modules` — discoverability hints.
- `blueprint_name`, `blueprint_version`, `blueprint_description` — blueprint identity.
- `baseline_status` — narrative of what (if anything) the runner applied as the baseline.
- `reference_files` — the `<blueprintDir>/files/` listing with each entry's `description`.
- `user_prompt` — the rendered blueprint prompt body (the `bp.prompt` field with vars substituted), followed by the user-typed `[PROMPT]` argument when supplied.

Owning the scaffold in-tree (rather than declaring it in the blueprint itself) keeps every blueprint's environment-context section consistent and lets infrastructure changes (e.g., adding a new `formatXxx` helper) propagate automatically.

## Manifest Behaviour

Manifest changes are owned by `seihou-core/src/Seihou/Manifest/Types.hs`.

- The `Manifest` record gained an optional `blueprint :: Maybe AppliedBlueprint` field next to the existing optional `recipe`.
- `currentManifestVersion` was bumped from 2 to 3. The decoder reads pre-bump (v2) manifests by treating a missing `blueprint` key as `Nothing` (`Aeson..:?` plus `Aeson..!=`), so upgrading seihou does not require any user action.
- The encoder omits the `blueprint` JSON key when `m.blueprint == Nothing`, mirroring the way the existing `recipe` key is omitted.
- `writeAppliedBlueprint :: AppliedBlueprint -> Manifest -> Manifest` overwrites any prior `blueprint` entry — re-running `seihou agent run` replaces the recorded entry, mirroring how `Manifest.recipe` is overwritten when a recipe is re-applied.
- The IO writer `recordAppliedBlueprint :: FilePath -> AppliedBlueprint -> IO (Either Text ())` lives in the `seihou-cli-internal` library at `seihou-cli/src/Seihou/CLI/AppliedBlueprint.hs`. It reads the manifest, applies `writeAppliedBlueprint`, and writes the result back. The file must exist; the runner creates it earlier in the baseline-application path when needed.
- A manifest whose `version` is greater than `currentManifestVersion` is rejected with `manifest was created by a newer version of seihou`. Downgrading to a pre-EP-32 build of seihou after the bump triggers this error, mirroring the v1→v2 precedent.

`seihou status` (handler in `seihou-cli/src-exe/Seihou/CLI/Status.hs`; renderer in `seihou-cli/src/Seihou/CLI/StatusRender.hs`) renders the recorded blueprint above the applied-modules block when present. The header line names the blueprint, optional version, and applied timestamp. The Baseline line lists comma-separated module names, or one of two placeholders (`(none -- --no-baseline)` for `--no-baseline`, `(none declared)` for an empty declared baseline). The Prompt line is omitted when no positional prompt was supplied. Example:

    Blueprint: payments-service v0.3.1 (applied 2026-05-12 14:23 UTC)
      Baseline: nix-flake, haskell-base
      Prompt: "set this up for a payments microservice"

## Registry Integration

Multi-module-repository support for blueprints is owned by EP-33 and lives in `seihou-core/src/Seihou/Core/Registry.hs` plus the registry handlers under `seihou-cli/src-exe/Seihou/CLI/Install.hs`, `Browse.hs`, and `seihou-cli/src/Seihou/CLI/Registry/`.

- The `Registry` record gained `blueprints :: [RegistryEntry]` next to the existing `modules` and `recipes`. The `seihou-registry.dhall` schema gained a parallel `blueprints` list with the same `{name, version, path, description, tags}` shape used by modules and recipes.
- `discoverRepoContents` gained a `SingleBlueprint FilePath` constructor, returned when a cloned repo's root contains `blueprint.dhall` and no `module.dhall`/`recipe.dhall`/`seihou-registry.dhall`. The probe order is **registry > module > recipe > blueprint**, matching the discovery precedence.
- `validateRegistry` checks blueprint entries with the same name-format and path-safety rules used for modules and recipes, plus a name-collision check across all three lists. Cross-kind name collisions (e.g., a module and a blueprint sharing a name in the same registry) are rejected at registry-validation time.
- `seihou install` learns the new `SingleBlueprint` constructor and the registry-listed-blueprint case; `seihou browse` displays blueprints with a `[blueprint]` row label (`Seihou.CLI.BrowseFormat.formatBrowseRegistry` was extended from `[RegistryEntry]` to `[(EntryKind, RegistryEntry)]` to thread the kind through).
- `seihou registry sync-versions` and `seihou registry validate` walk the `blueprints` list alongside `modules` and `recipes`. Sync-version diffs report blueprint-version drift the same way they report module-version drift.

A single-blueprint clone does not feed `seihou outdated` or `seihou upgrade` (those operate on installed modules); the gap is intentional and recorded in EP-33's surprises section.

## Edge Cases

- **A blueprint whose `baseModules` references a name that resolves to another blueprint.** Rejected by validation rule 6 with `baseModule '<name>' resolves to a blueprint; baseModules must be modules or recipes`. Recursive agent launches are out of scope for v1.
- **A blueprint applied while a previous `AppliedBlueprint` entry already exists.** The new entry replaces the old. The behaviour mirrors `Manifest.recipe` overwriting on recipe re-application; `seihou status` reflects only the most recent successful application.
- **A blueprint with an empty `files/` directory or no declared `files`.** Allowed. The runner does not pass `--add-dir <blueprintDir>/files` when the directory does not exist on disk.
- **`seihou run BLUEPRINT` against a discoverable blueprint.** The handler in `seihou-cli/src-exe/Seihou/CLI/Run.hs` matches `RunnableBlueprint` and emits the canonical refusal text via `Seihou.CLI.Shared.formatBlueprintRefusal`:

      '<NAME>' is a blueprint, not a module or recipe.
      Blueprints must be run interactively via:
        seihou agent run <NAME>

  The runtime `Seihou.Effect.Logger.logError` prefixes each call with `[error] `, so the observable output is `[error] '<NAME>' is a blueprint, …`. The refusal name echoes the *user-typed* `NAME`, not the blueprint's declared `name` field — discovery resolves by directory name, and the suggestion must be copy-pasteable.
- **A blueprint applied with `--no-baseline` against a project whose existing manifest already contains the would-have-been-applied base modules.** The manifest's pre-existing `applied modules` list is unchanged; the `AppliedBlueprint` entry records `noBaseline = True` and `baselineModules = []`, capturing the user's choice.
- **A non-zero agent exit (Ctrl-C, `claude` not on PATH, user-quit).** The runner skips the manifest write. The session's intermediate state on disk (any baseline application) is unaffected; the user's project reflects whatever the agent and the user committed before the exit.
- **`claude` not on PATH.** `launchAgentWith` produces the same install-hint message the existing `seihou agent assist`/`bootstrap`/`setup` commands produce.
- **Cross-kind name collisions in a registry.** `validateRegistry` rejects e.g. a module and a blueprint sharing a name with `name collision: '<name>' appears as both a module and a blueprint`.

## Testing Plan

The validator and discovery extension are covered by tests under `seihou-core/test/Seihou/Core/`. The CLI-side surface (parsers, formatters, scaffold helpers) is covered under `seihou-cli/test/Seihou/CLI/`.

| Test surface | Location | Coverage |
|---|---|---|
| Validator rules 1–9 | `seihou-core/test/Seihou/Core/BlueprintSpec.hs` | Each rule has a positive and negative case; aggregation across rules is also exercised. |
| Discovery priority (module > recipe > blueprint) | `seihou-core/test/Seihou/Core/ModuleSpec.hs` | Same-directory fall-through plus cross-search-path resolution. |
| `discoverAllRunnables` enumeration | `seihou-core/test/Seihou/Core/ModuleSpec.hs` | Each `KindBlueprint` entry is reported with the right path. |
| Manifest schema bump (v2→v3) | `seihou-core/test/Seihou/Manifest/TypesSpec.hs` | Round-trip a v3 manifest with a blueprint entry; decode a v2 manifest with no `blueprint` key as `Nothing`; reject a future-version manifest. |
| Registry classifier | `seihou-core/test/Seihou/Core/RegistrySpec.hs` | `SingleBlueprint`, multi-module with blueprints, cross-kind collisions. |
| Registry sync-versions | `seihou-core/test/Seihou/Core/RegistrySyncSpec.hs` | Blueprint-version drift reported alongside module/recipe drift. |
| Scaffold helpers (`blueprintDhall`, `examplePromptMarkdown`) | `seihou-core/test/Seihou/Core/ScaffoldSpec.hs` | Six cases driving the full scaffold → eval → validate pipeline. |
| List formatter | `seihou-cli/test/Seihou/CLI/ListSpec.hs` | Renders blueprint kind label correctly. |
| Browse formatter | `seihou-cli/test/Seihou/CLI/BrowseFormatSpec.hs` | Mixed-kind registry rows include blueprint entries. |
| Status renderer (blueprint section) | `seihou-cli/test/Seihou/CLI/StatusSpec.hs` | Header, baseline, and prompt-line shapes; both no-baseline and empty-baseline placeholders. |
| Refusal text | `seihou-cli/test/Seihou/CLI/RunBlueprintRefusalSpec.hs` | `formatBlueprintRefusal` produces the documented three-line message. |
| Manifest writer (`recordAppliedBlueprint`) | `seihou-cli/test/Seihou/CLI/AppliedBlueprintSpec.hs` | Round-trip on an existing manifest, replace-on-rerun semantics, error path when the manifest is unreadable. |
| Agent-runner formatters | `seihou-cli/test/Seihou/CLI/AgentLaunchSpec.hs` | Reference-file block formatter, baseline-status formatter. |

The handler-level surfaces (`handleAgentRun`, `handleNewBlueprint`, `handleValidateBlueprint`) are not directly unit-tested because the `seihou-cli-test` test suite cannot import from the `executable seihou` target — `Options.Applicative`, `Data.FileEmbed`, and `Paths_seihou_cli` trap their modules in the executable. The constraint matches how `Seihou.CLI.NewModule`, `Seihou.CLI.NewRecipe`, and `Seihou.CLI.Validate` are tested. Library-side helpers are exercised directly; the executable handlers are smoke-tested manually.

## Future Enhancements

The masterplan at `docs/masterplans/3-agent-driven-blueprints.md` deferred the following items as deliberate non-goals for v1. Each is a meaningful, well-bounded extension of the v1 surface.

- **Resume support.** Persist agent conversation transcripts under `.seihou/blueprints/<name>/sessions/` and add `seihou agent run --resume <session-id>` to re-launch the agent with prior context. The `AppliedBlueprint.agentSessionId` field is the obvious extension point.
- **Blueprints depending on other blueprints.** A blueprint listing another blueprint as a base would require recursively launching agent sessions — a meaningfully different feature with its own UX (when does the parent agent take over from the child?), safety considerations, and integration testing burden.
- **Author-declared migrations on blueprints.** Modules use `migrations` to rewrite tracked files when the module's version advances. Blueprints produce non-deterministic output, so the manifest's `files` map cannot be authoritatively rewritten by a blueprint-author-supplied chain. Updating a project from `my-blueprint v0.1.0` to `v0.2.0` is the agent's job, run interactively.
- **Non-Claude agent backends.** The runner uses `launchAgentWith`, which shells out to the `claude` CLI. A pluggable agent backend (LangGraph, Aider, Cline, etc.) is a future initiative; this design does not generalise the launcher.
- **Prompt templating that pulls from base modules' resolved values.** Blueprint prompts may reference top-level `vars` but cannot pull values resolved by a base module's prompt chain. If a blueprint needs `project.name`, the blueprint must declare its own `project.name` `VarDecl` (which then becomes the override that any base module's `project.name` resolves to).

## Cross-References

- [Master Plan: Agent-Driven Blueprints](../../masterplans/3-agent-driven-blueprints.md) — Full initiative decomposition and decision log
- [ExecPlan 29: Domain model and discovery](../../plans/29-blueprint-domain-model-and-discovery.md) — Type definition, schema, validator, run-refusal
- [ExecPlan 30: Authoring and inspection](../../plans/30-blueprint-authoring-and-inspection.md) — `seihou new-blueprint`, `seihou validate-blueprint`, list/vars integration
- [ExecPlan 31: Agent runner](../../plans/31-blueprint-agent-runner.md) — `seihou agent run BLUEPRINT [PROMPT]`
- [ExecPlan 32: Manifest tracking and `seihou status`](../../plans/32-blueprint-manifest-and-status.md) — `AppliedBlueprint`, manifest schema bump, status renderer
- [ExecPlan 33: Registry and install](../../plans/33-blueprint-registry-and-install.md) — Multi-module-repository support
- [Module System](module-system.md) — Module structure, loading, variables, exports
- [Composition and Layering](composition-and-layering.md) — How modules compose (relevant to baseline application)
- [Variable Resolution](variable-resolution.md) — Resolution precedence (the same chain blueprints use)
- [Manifest and Incrementality](manifest-and-incrementality.md) — Manifest format, three-state model
- [Architecture Overview](../../architecture/overview.md) — System-level context
