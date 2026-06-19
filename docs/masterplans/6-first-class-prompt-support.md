---
id: 6
slug: first-class-prompt-support
title: "First-class prompt support"
kind: master-plan
created_at: 2026-06-19T16:21:58Z
intention: "intention_01kvgax2mfezgsw4rrzsk012qc"
---

# First-class prompt support

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Vision & Scope

After this initiative, Seihou has a fourth first-class runnable artifact: a prompt. A prompt is a reusable agent-session template stored in a directory with `prompt.dhall`, a Markdown body, optional reference files, typed variables, and command-derived variables. Users can create one with `seihou new-prompt`, validate it with `seihou validate-prompt`, list and install it like other runnable artifacts, and launch it through Baikai-backed Claude Code or Codex sessions with `seihou prompt run NAME`.

This is intentionally distinct from a blueprint. A blueprint remains an agent-guided scaffolding artifact: it can apply baseline modules, expects project-writing behavior, and records applied-blueprint provenance in `.seihou/manifest.json`. A prompt is a general interactive agent-session template: code review, release preparation, planning, repository inspection, dependency lookup, or any other workflow where a prompt should be rendered from config and local filesystem context without implying scaffolding.

The scope includes updates to the external `shinzui/seihou-schema` Dhall package, Seihou's local schema mirror, core Haskell domain types and decoders, validation, command-derived variable resolution, CLI commands, registry/install/list/browse surfaces, tests, and user/help documentation. The scope excludes implementing a new non-Baikai provider system, changing deterministic module or recipe generation semantics, and migrating existing blueprints automatically into prompts.


## Decomposition Strategy

The work is split by functional concern rather than by file. Schema primitives come first because every later plan depends on stable Dhall shapes. Core domain and discovery come next because the CLI and registry surfaces need loaded `AgentPrompt` values and a `KindPrompt` tag. Command-derived variables are separate because they introduce process execution, validation, provenance, and security constraints that should be independently tested before the runner depends on them. CLI workflows then compose the domain model, variable resolver, prompt renderer, and Baikai launcher into user-visible commands. Registry and discovery surfaces are separate because installation, browsing, list filtering, sync, and validation have a broad blast radius but do not need to block the core local prompt runner. Documentation closes the loop once the command names and behavior are stable.

An alternative was to extend blueprints with a `purpose = "prompt"` field. That was rejected because the runtime semantics differ: prompts should not apply `baseModules` by default or record applied-blueprint provenance, and users should be able to discover them as prompt/session templates rather than as scaffolding artifacts. Another alternative was a separate CLI outside Seihou. That was rejected because Seihou already owns typed variables, project/global config, Baikai-backed interactive launch, registry installation, and prompt rendering conventions.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| EP-50 | Add prompt schema primitives | docs/plans/50-add-prompt-schema-primitives.md | None | None | Complete |
| EP-51 | Add prompt domain and discovery | docs/plans/51-add-prompt-domain-and-discovery.md | EP-50 | None | Complete |
| EP-52 | Resolve command derived variables | docs/plans/52-resolve-command-derived-variables.md | EP-50 | EP-51 | Not Started |
| EP-53 | Add prompt CLI workflows | docs/plans/53-add-prompt-cli-workflows.md | EP-51, EP-52 | None | Not Started |
| EP-55 | Integrate prompts with registries and discovery surfaces | docs/plans/55-integrate-prompts-with-registries-and-discovery-surfaces.md | EP-51 | EP-53 | Not Started |
| EP-54 | Document first class prompts | docs/plans/54-document-first-class-prompts.md | EP-53, EP-55 | None | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-1, EP-3).


## Dependency Graph

EP-50 is the root because it defines the Dhall schema records that all later code decodes and emits. EP-51 has a hard dependency on EP-50 because the Haskell domain model and Dhall decoder must match the schema names and fields.

EP-52 has a hard dependency on EP-50 because command-derived variable records are part of the schema. It has only a soft dependency on EP-51: the command resolver can be implemented and tested as a library helper using the shared types even if prompt discovery is still in progress, but final integration is easier once `AgentPrompt` exists.

EP-53 depends hard on EP-51 and EP-52 because the prompt runner needs to discover `prompt.dhall` artifacts, resolve normal variables, run command-derived variables, render the prompt body, and launch the configured provider. EP-55 depends hard on EP-51 because registry/list/browse/install surfaces need `KindPrompt`, `RunnablePrompt`, and decoding support. EP-55 has a soft dependency on EP-53 because the ecosystem surfaces can be updated before the runner is complete, but examples and smoke tests are clearer after `seihou prompt run` exists.

EP-54 depends on EP-53 and EP-55 so the docs reflect the actual command grammar, validation checks, registry format, and launch behavior.


## Integration Points

The Dhall schema package is shared by all plans. EP-50 owns `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema` and the local `schema/` mirror in this repository. Later plans must consume the field names defined there rather than inventing alternate Haskell-only shapes.

The Haskell prompt domain model is shared by EP-51, EP-52, EP-53, EP-55, and EP-54. EP-51 owns the core types in `seihou-core/src/Seihou/Core/Types.hs`, the Dhall decoder in `seihou-core/src/Seihou/Dhall/Eval.hs`, validation in a new `Seihou.Core.AgentPrompt` module, and discovery changes in `seihou-core/src/Seihou/Core/Module.hs`.

Command-derived variable resolution is shared by EP-52 and EP-53. EP-52 owns the resolver interface and provenance shape. EP-53 consumes that interface while rendering prompts and must not duplicate process execution logic in the executable handler.

The Baikai interactive launch path is shared by existing agent commands and EP-53. EP-53 should reuse `seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs`, `seihou-cli/src/Seihou/CLI/AgentCompletion.hs`, and `seihou-cli/src/Seihou/CLI/AgentConfig.hs` rather than adding prompt-specific provider parsing.

The registry model is shared by EP-51 and EP-55. EP-51 introduces prompt-aware runnable kinds. EP-55 extends `Seihou.Core.Registry`, `Seihou.Dhall.Eval.registryDecoder`, install, browse, list, sync, and validate surfaces to include prompt entries.


## Progress

Track milestone-level progress across all child plans. Each entry names the child plan
and the milestone. This section provides an at-a-glance view of the entire initiative.

- [x] EP-50: Define external and local schema records for `prompt.dhall`, reference files, launch metadata, and command-derived variables.
- [x] EP-50: Validate schema examples with Dhall and update schema package exports.
- [x] EP-51: Add Haskell prompt types, Dhall decoder, validation module, and search/discovery support.
- [ ] EP-52: Add safe command-derived variable resolution with process-effect tests and provenance.
- [ ] EP-53: Add `seihou new-prompt`, `seihou validate-prompt`, and `seihou prompt run` workflows.
- [ ] EP-55: Add prompts to registries, install, browse, list filters, sync, validation, and related tests.
- [ ] EP-54: Update CLI help, user guides, generated prompt-authoring guidance, and changelog material.


## Surprises & Discoveries

Document cross-plan insights, dependency changes, scope adjustments, or unexpected
interactions between child plans. Provide concise evidence.

- Discovery: The registered `shinzui/seihou-schema` repository currently lists `Module.dhall` and `Recipe.dhall` but not the local Seihou mirror's `Blueprint.dhall`.
  Evidence: `mori registry show shinzui/seihou-schema --full` reports the schema path as `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema`; `rg --files /Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema` shows no `Blueprint.dhall`, while this repository has `schema/Blueprint.dhall`.
  Date: 2026-06-19

- Discovery: Seihou already has a Baikai interactive launcher path for `claude-cli` and `codex-cli`.
  Evidence: `seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs` builds `InteractiveLaunchRequest` values and calls `launchClaudeInteractive` or `launchCodexInteractive`.
  Date: 2026-06-19

- Discovery: EP-50 found the external `seihou-schema` checkout was also missing the local mirror's migration schema exports, not only `Blueprint.dhall`.
  Evidence: before the EP-50 sync, the external package lacked `MigrationOp.dhall` and `Migration.dhall`, and its `Module.dhall` lacked the local mirror's `migrations : List Migration.Type` field. EP-50 synchronized those schema primitives while adding `CommandVar` and `AgentPrompt`.
  Date: 2026-06-19


## Decision Log

Record every decomposition or coordination decision made while working on the master
plan.

- Decision: Model prompt/session templates as a fourth runnable kind instead of as a blueprint classification.
  Rationale: Prompts have different runtime semantics from blueprints: no baseline module application by default, no applied-blueprint manifest record by default, and a broader purpose than scaffolding.
  Date: 2026-06-19

- Decision: Name the Haskell domain type `AgentPrompt` and the on-disk file `prompt.dhall`.
  Rationale: `Prompt` is already the variable-question type in `Seihou.Core.Types`; `AgentPrompt` avoids a Haskell naming collision while keeping the user-facing artifact name concise.
  Date: 2026-06-19

- Decision: Put command-derived variables in a shared schema primitive that prompts and future blueprint revisions can both use.
  Rationale: The motivating use case is prompt-first, but the ability to derive variables from filesystem commands is generally useful and should not be hard-coded into one CLI handler.
  Date: 2026-06-19

- Decision: Treat schema-publication drift discovered during EP-50 as part of the schema primitives plan.
  Rationale: Prompt work depends on a coherent schema package. Synchronizing external blueprint and migration exports with the local mirror before adding `AgentPrompt` keeps later `SchemaVersion.hs` pinning and generated imports unambiguous.
  Date: 2026-06-19


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original vision.

(To be filled during and after implementation.)
