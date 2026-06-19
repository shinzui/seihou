---
id: 54
slug: document-first-class-prompts
title: "Document first class prompts"
kind: exec-plan
created_at: 2026-06-19T16:22:12Z
intention: "intention_01kvgax2mfezgsw4rrzsk012qc"
master_plan: "docs/masterplans/6-first-class-prompt-support.md"
---

# Document first class prompts

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, Seihou's user docs, CLI reference, embedded help, and agent-authoring prompts explain first-class prompt artifacts clearly. Users should understand when to choose a module, recipe, blueprint, or prompt; how prompt variables resolve from config and commands; how to publish prompts in registries; and how to run prompts through Codex or Claude.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Add a user guide for first-class prompts.
- [x] Add CLI reference pages for `new-prompt`, `validate-prompt`, and `prompt run`.
- [x] Update getting started, agent assistance, registries, module authoring, list/install/browse docs, and help topics.
- [x] Update embedded assist/bootstrap/setup prompt text so agents recommend prompts for prompt-session use cases.
- [x] Update changelog or release notes material.

- [x] Started EP-54 after EP-55 completion and inspected prompt-related command/help/doc surfaces for stale three-artifact wording.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- Discovery: `seihou-cli-test --test-options '--pattern Help'` currently selects zero tests.
  Evidence: the help acceptance check was covered by directly running `seihou help prompts` after embedding the new `prompts` topic.
  Date: 2026-06-19


## Decision Log

Record every decision made while working on the plan.

- Decision: Documentation should present prompts as peer artifacts to modules, recipes, and blueprints.
  Rationale: The feature is first-class support, not an advanced blueprint option; users need the taxonomy before command details.
  Date: 2026-06-19


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

- Outcome: First-class prompts are documented across the user guide, CLI reference, embedded help, registry/list/install/browse docs, changelog material, and agent prompt templates. The docs now explain prompt layout, config-backed variables, command-derived variables, registry publication, provider launch behavior, and the distinction between prompts and blueprints.
  Date: 2026-06-19


## Context and Orientation

User guides live in `docs/user/`. CLI reference pages live in `docs/cli/`. Embedded help topics for `seihou help TOPIC` live in `seihou-cli/help/` and are embedded by `seihou-cli/src-exe/Seihou/CLI/Help.hs`. Agent prompt templates live in `seihou-cli/data/`; these are the instructions Seihou sends to Claude or Codex for authoring and setup assistance.

Current docs describe three runnable artifact types: modules, recipes, and blueprints. Blueprints are described as agent-driven project starters for open-ended scaffolding. This plan must preserve that meaning and introduce prompts as agent-session templates for reusable interactive workflows.


## Plan of Work

Milestone 1 adds the main prompt guide. Create `docs/user/prompts.md` explaining the prompt directory layout, `prompt.dhall` fields, normal variables, command-derived variables, reference files, provider launch behavior, debug rendering, safety considerations, and the distinction between prompts and blueprints.

Milestone 2 adds CLI references. Create or update pages for `docs/cli/new-prompt.md`, `docs/cli/validate-prompt.md`, and `docs/cli/prompt.md`. Update `docs/cli/list.md`, `docs/cli/install.md`, `docs/cli/browse.md`, and `docs/cli/registry.md` so prompt entries appear wherever modules, recipes, and blueprints currently appear.

Milestone 3 updates embedded help. Add `seihou-cli/help/prompts.md`, add it to `Seihou.CLI.Help`, and update command help text in `Seihou.CLI.Commands` if EP-53 did not already do so. Embedded help should include examples for config-backed variables and command-derived variables.

Milestone 4 updates broader docs and agent templates. Update `docs/user/getting-started.md`, `docs/user/agent-assistance.md`, `docs/user/registries-and-multi-module-repos.md`, `docs/user/module-authoring.md`, and `docs/user/CHANGELOG.md`. Update `seihou-cli/data/assist-prompt.md`, `bootstrap-prompt.md`, and `setup-prompt.md` so agents advise "prompt" for reusable agent-session templates and "blueprint" only for agent-guided scaffolding.

Milestone 5 verifies docs. Run documentation-oriented tests if available, then run `rg` checks to catch stale "modules, recipes, and blueprints" phrases that should include prompts. Leave phrases unchanged only when the context truly excludes prompts.


## Concrete Steps

Run these commands from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`:

```bash
rg -n "modules, recipes, and blueprints|module, recipe, or blueprint|new-blueprint|validate-blueprint|agent-driven blueprint|blueprints" docs seihou-cli/help seihou-cli/data seihou-cli/src-exe/Seihou/CLI/Commands.hs
rg -n "HelpTopic" seihou-cli/src-exe/Seihou/CLI/Help.hs
cabal build seihou
```

After docs are updated, run:

```bash
rg -n "modules, recipes, and blueprints|module, recipe, or blueprint" docs seihou-cli/help seihou-cli/data
cabal test seihou-cli-test --test-options '--pattern Help'
```


## Validation and Acceptance

Acceptance is met when a new user can read `docs/user/prompts.md` and successfully understand:

```bash
seihou new-prompt review-changes
seihou validate-prompt review-changes
seihou prompt run review-changes --debug
seihou prompt run review-changes --provider codex-cli
```

The docs must include one example of a variable supplied by project/global config and one example of a variable supplied by a command. `seihou help prompts` must render without missing embedded files.


## Idempotence and Recovery

Docs edits are safe to repeat. Avoid changing command names in docs unless EP-53 implemented those exact names. If implementation changed syntax from this plan, update this document's examples to match the code rather than preserving stale planned syntax.


## Interfaces and Dependencies

This plan depends on EP-53 and EP-55 so the documented command grammar and registry fields are real. It must update these doc surfaces at minimum:

```text
docs/user/prompts.md
docs/user/getting-started.md
docs/user/agent-assistance.md
docs/user/registries-and-multi-module-repos.md
docs/cli/prompt.md
docs/cli/new-prompt.md
docs/cli/validate-prompt.md
seihou-cli/help/prompts.md
seihou-cli/data/assist-prompt.md
```
