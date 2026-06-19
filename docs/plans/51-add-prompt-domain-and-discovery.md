---
id: 51
slug: add-prompt-domain-and-discovery
title: "Add prompt domain and discovery"
kind: exec-plan
created_at: 2026-06-19T16:22:12Z
intention: "intention_01kvgax2mfezgsw4rrzsk012qc"
master_plan: "docs/masterplans/6-first-class-prompt-support.md"
---

# Add prompt domain and discovery

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, Seihou can load, validate, and discover `prompt.dhall` artifacts as first-class runnables. A user will be able to put a prompt directory under `.seihou/modules/`, `~/.config/seihou/modules/`, or `~/.config/seihou/installed/` and see it represented as a prompt in core discovery results. The CLI runner is not implemented in this plan; this plan creates the domain layer that makes the runner possible.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] Add `AgentPrompt`, `PromptFile`, and command-variable references to core types.
- [ ] Add Dhall decoding for `prompt.dhall`.
- [ ] Add prompt validation checks and tests.
- [ ] Extend runnable discovery with `RunnableAgentPrompt` and `KindPrompt`.
- [ ] Add fixtures proving module > recipe > blueprint > prompt precedence.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Discovery should prefer `module.dhall`, then `recipe.dhall`, then `blueprint.dhall`, then `prompt.dhall` in one directory.
  Rationale: Existing deterministic artifacts and scaffolding blueprints should keep their current behavior; prompts are the broadest, least-specific runnable kind.
  Date: 2026-06-19


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

The core type definitions live in `seihou-core/src/Seihou/Core/Types.hs`. Existing runnable domain types are `Module`, `Recipe`, and `Blueprint`. `Blueprint` already demonstrates an agent-driven artifact with `prompt :: Text`, `vars`, `prompts`, `baseModules`, `files`, `allowedTools`, and `tags`.

Dhall evaluation and decoding live in `seihou-core/src/Seihou/Dhall/Eval.hs`. It exports `evalModuleFromFile`, `evalRecipeFromFile`, `evalBlueprintFromFile`, and decoders for nested types. The new prompt decoder should follow `blueprintDecoder` and `evalBlueprintFromFile`.

Name-based discovery lives in `seihou-core/src/Seihou/Core/Module.hs`. `discoverRunnable` currently checks `module.dhall`, then `recipe.dhall`, then `blueprint.dhall`. `discoverAllRunnables` enumerates subdirectories and tags each item with `RunnableKind = KindModule | KindRecipe | KindBlueprint`.

Validation for blueprints lives in `seihou-core/src/Seihou/Core/Blueprint.hs`. Create a sibling module, `seihou-core/src/Seihou/Core/AgentPrompt.hs`, for prompt validation so the blueprint meaning remains narrow.


## Plan of Work

Milestone 1 adds domain types. In `Seihou.Core.Types`, add `CommandVar` if EP-52 has not already added it, `PromptFile` or reuse `BlueprintFile` if the name remains general enough, and `AgentPrompt`. The recommended `AgentPrompt` fields are `name :: ModuleName`, `version :: Maybe Text`, `description :: Maybe Text`, `prompt :: Text`, `vars :: [VarDecl]`, `prompts :: [Prompt]`, `commandVars :: [CommandVar]`, `files :: [BlueprintFile]`, `allowedTools :: Maybe [Text]`, and `tags :: [Text]`. Extend `Runnable` with `RunnableAgentPrompt AgentPrompt FilePath`.

Milestone 2 adds Dhall decoding. In `Seihou.Dhall.Eval`, export `evalAgentPromptFromFile`, `agentPromptDecoder`, and `commandVarDecoder`. Force lazy decoder thunks for variable types, prompt conditions, and command-var conditions inside the `try` block, mirroring `evalBlueprintFromFile`.

Milestone 3 adds validation. Create `Seihou.Core.AgentPrompt` with checks for name format, optional version non-empty, non-empty prompt body, unique variable names, prompt references, command-var references, command-var safety, reference file existence, tags, and allowed tools. Command-var safety should check non-empty `run`, safe relative `workDir` when present, declared `name`, and reasonable `maxBytes` when present. Use `validateProjectRelativePath` from `Seihou.Core.Path` for work directories.

Milestone 4 extends discovery. In `Seihou.Core.Module`, update `discoverRunnable`, `discoverAllRunnables`, `RunnableKind`, comments, and `briefLoadError` plumbing to include prompts. Precedence in a single directory is module, recipe, blueprint, prompt. Add tests in `seihou-core/test/Seihou/Core/AgentPromptSpec.hs` or extend `BlueprintSpec` only if a new spec would duplicate too much setup.


## Concrete Steps

Run these commands from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`:

```bash
rg -n "data Blueprint|data Runnable|RunnableKind|evalBlueprintFromFile|blueprintDecoder|discoverRunnable|discoverAllRunnables" seihou-core/src seihou-core/test
cabal test seihou-core-test --test-options '--pattern AgentPrompt'
```

If no focused tests exist yet, use the full core suite:

```bash
cabal test seihou-core-test
```


## Validation and Acceptance

Acceptance is met when a test fixture containing only `prompt.dhall` loads as `RunnableAgentPrompt`, `discoverAllRunnables` returns an entry tagged `KindPrompt`, and a fixture containing both `blueprint.dhall` and `prompt.dhall` resolves as a blueprint. Invalid prompt fixtures must report validation errors instead of crashing.

The core test suite should end with output equivalent to:

```text
All tests passed
Test suite seihou-core-test: PASS
```


## Idempotence and Recovery

All changes are additive. Re-running discovery tests is safe because they use temporary directories and fixtures. If adding `KindPrompt` causes pattern-match warnings or failures in downstream modules, do not stub them with impossible defaults; update each pattern match to render or reject prompts intentionally.


## Interfaces and Dependencies

This plan depends on EP-50's schema field names. It does not depend on Baikai or live agent providers.

Required interfaces at completion:

```haskell
data AgentPrompt = AgentPrompt { ... }
data Runnable = ... | RunnableAgentPrompt AgentPrompt FilePath
data RunnableKind = KindModule | KindRecipe | KindBlueprint | KindPrompt

evalAgentPromptFromFile :: FilePath -> IO (Either ModuleLoadError AgentPrompt)
agentPromptDecoder :: Decoder AgentPrompt
validateAgentPrompt :: FilePath -> AgentPrompt -> IO (Either ModuleLoadError AgentPrompt)
```
