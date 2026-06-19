---
id: 55
slug: integrate-prompts-with-registries-and-discovery-surfaces
title: "Integrate prompts with registries and discovery surfaces"
kind: exec-plan
created_at: 2026-06-19T16:22:21Z
intention: "intention_01kvgax2mfezgsw4rrzsk012qc"
master_plan: "docs/masterplans/6-first-class-prompt-support.md"
---

# Integrate prompts with registries and discovery surfaces

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, prompt artifacts participate in the same ecosystem as modules, recipes, and blueprints. Users can list prompts, browse prompt entries in remote repositories, install prompt entries from registries, validate registry metadata that includes prompts, and keep registry versions synchronized.

This plan makes prompts discoverable and distributable. It does not implement prompt execution; that belongs to `docs/plans/53-add-prompt-cli-workflows.md`.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] Extend registry core types, decoder, rendering, validation, and sync logic with prompt entries.
- [ ] Extend install and browse paths for single-prompt and registry prompt repositories.
- [ ] Extend list filters and display output with prompts.
- [ ] Extend fzf selector, remote version, outdated, and registry validate/sync tests where applicable.
- [ ] Add fixture coverage for name collisions and precedence with `prompt.dhall`.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Prompts share the same name namespace as modules, recipes, and blueprints.
  Rationale: Seihou resolves runnable names from common search paths; allowing a prompt and blueprint with the same name would make install, list, and run guidance ambiguous.
  Date: 2026-06-19


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

Registry core code lives in `seihou-core/src/Seihou/Core/Registry.hs`. The current `Registry` type has `modules`, `recipes`, and `blueprints`. Registry Dhall decoding lives in `seihou-core/src/Seihou/Dhall/Eval.hs` and already uses defaults so old registry files without a `blueprints` field still decode.

Install and browse command handlers live in `seihou-cli/src-exe/Seihou/CLI/Install.hs` and `seihou-cli/src-exe/Seihou/CLI/Browse.hs`. List formatting lives in `seihou-cli/src/Seihou/CLI/List.hs`. Registry sync and validate command helpers live in `seihou-cli/src/Seihou/CLI/Registry/Sync.hs` and `seihou-cli/src/Seihou/CLI/Registry/Validate.hs`.

Prompt discovery from EP-51 must already expose `KindPrompt` and `RunnableAgentPrompt`. This plan uses that core support to update every surface that currently says "modules, recipes, and blueprints".


## Plan of Work

Milestone 1 updates registry data and Dhall decoding. Add `prompts :: [RegistryEntry]` to `Registry`, add `PromptEntry` to `EntryKind`, update `registryDecoder` with a default empty prompt list, update `renderRegistryDhall`, update name-collision checks across all four kinds, and update sync classification so prompt versions can be compared with `prompt.dhall`.

Milestone 2 updates install and browse. Single-artifact repository detection should check `module.dhall`, `recipe.dhall`, `blueprint.dhall`, then `prompt.dhall`. Multi-artifact registries should install selected prompt entries into the same installed directory structure as other artifacts, preserving `prompt.dhall`, `prompt.md`, `files/`, and origin metadata. Browse output should display prompt entries with a prompt kind label.

Milestone 3 updates list and selectors. Extend `ListFilter`, `formatListOutputEntries`, `summaryNoun`, kind suffixes, and CLI `--prompts` filtering. Update `seihou-cli/src/Seihou/Fzf/Selector/Module.hs` so prompts appear distinctly in interactive selection where runnable selection is used.

Milestone 4 updates tests. Extend registry specs for missing `prompts` backward compatibility, valid prompt entries, missing `prompt.dhall`, invalid names, unsafe paths, cross-kind name collisions, sync missing/stale/in-sync/orphan statuses, browse formatting, install selection, list formatting, and remote version/outdated behavior if those surfaces currently reason about blueprint entries.


## Concrete Steps

Run these commands from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`:

```bash
rg -n "blueprints|BlueprintEntry|KindBlueprint|SingleBlueprint|module.dhall.*recipe.dhall.*blueprint.dhall|Available modules, recipes, and blueprints" seihou-core/src seihou-cli/src seihou-cli/src-exe seihou-core/test seihou-cli/test
cabal test seihou-core-test --test-options '--pattern Registry'
cabal test seihou-cli-test --test-options '--pattern List'
```

Then run full suites:

```bash
cabal test seihou-core-test
cabal test seihou-cli-test
```


## Validation and Acceptance

Acceptance is met when a registry like this decodes, validates, syncs, browses, and installs:

```dhall
{ repoName = "team-prompts"
, repoDescription = Some "Shared agent prompts"
, modules = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }
, recipes = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }
, blueprints = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }
, prompts =
  [ { name = "review-changes"
    , version = Some "0.1.0"
    , path = "prompts/review-changes"
    , description = Some "Review current git changes"
    , tags = [ "review" ]
    }
  ]
}
```

`seihou list --prompts` must show prompt entries and exclude modules, recipes, and blueprints.


## Idempotence and Recovery

Registry sync rewrites `seihou-registry.dhall`; this is existing behavior. Tests should use temporary directories. When editing install logic, preserve existing module, recipe, and blueprint behavior first; prompt support should be additive.


## Interfaces and Dependencies

This plan depends on EP-51's `KindPrompt`, `RunnableAgentPrompt`, and `evalAgentPromptFromFile`. It touches these core interfaces:

```haskell
data Registry = Registry { modules, recipes, blueprints, prompts :: [RegistryEntry] }
data EntryKind = ModuleEntry | RecipeEntry | BlueprintEntry | PromptEntry
data RepoContents = ... | SinglePrompt FilePath
```

The registry decoder must remain backward compatible by defaulting missing `prompts` to an empty list.
