---
type: Improvement Request
title: Validate a recipe without running its composition
description: Provide a discoverable recipe validation command that checks recipe declarations and prompts without generating files, executing module commands, or requiring answers to project configuration questions.
requestId: IR-13
status: proposed
targetPlan: docs/plans/115-validate-recipes-without-running-their-composition.md
origin: mori://tan/tan-seihou-modules
affects: mori://shinzui/seihou
affectedVersion: 0.11.0.1
generated:
  by: codex-cli/gpt-6.1-sol
  at: "2026-10-28T12:27:03Z"
timestamp: 2026-10-28T14:25:14Z
reviews:
  - kind: model
    reviewer: codex-cli/gpt-6.1-sol
    reviewed_at: 2026-10-28T12:30:01Z
    document_timestamp: 2026-10-28T12:27:03Z
    scope: content-and-metadata
    outcome: approved
    context: Author self-review against current source, installed CLI evidence, and the local profile; not an independent review.
    provider: openai
    model: gpt-6.1-sol
    effort: unspecified
---

# Validate a recipe without running its composition

## Implementation

Implemented by [ExecPlan 115](../plans/115-validate-recipes-without-running-their-composition.md).
The plan records implementation, verification, and published/installed delivery evidence.

## Observed authoring gap

The installed `seihou v0.11.0.1 (4ade3fb)` exposes `new-recipe` and validates
modules, blueprints, and prompts, but rejects the corresponding recipe command:

```text
$ seihou validate-recipe --help
Invalid argument `validate-recipe'
```

The recipe validator already exists as `Seihou.Core.Recipe.validateRecipe` in
`seihou-core/src/Seihou/Core/Recipe.hs`. `seihou registry validate` checks entry
paths, names, collisions, and versions, but is not a dedicated semantic recipe
validation workflow. `seihou run RECIPE --dry-run` expands the composition and
resolves every required project input, so it is not a convenient substitute for
authoring and CI checks.

This gap was encountered while planning
`mori://tan/tan-seihou-modules/masterplans/1-bootstrap-tan-keiro-projects-with-a-cross-registry-recipe`.
Its recipe will own conditional GitHub and Redpanda prompts, which should be
checkable before anyone runs a bootstrap.

## Requested behavior and acceptance

Expose `seihou validate-recipe PATH`, or an equally discoverable unified validation
command, alongside the existing artifact validators. Evaluate the Dhall and report
semantic errors in declarations, prompt references, conditions, bindings, and the
nonempty member list supported by the recipe contract. Reuse the shared validator
rather than inventing a second meaning of a valid recipe.

A valid recipe must pass without a terminal or any project variable answers,
without generating files, executing commands, or installing dependencies. An
invalid recipe must exit nonzero and identify the recipe field or member that
needs correction. Include invalid Dhall, an empty module list, a prompt naming an
undeclared variable, and a valid recipe whose modules require interactive inputs.
Keep pure descriptor validation distinct from any explicit dependency-availability
check, so a valid unpublished recipe can be authored offline.

Document the public help and exact CI command, and prove the installed delivery
binary supports them. [IR-11](resolve-recipe-variables-and-prompts-before-module-resolution.md)
owns prompt execution; this request owns authoring-time validation. The user will
handle the upstream fix before TAN recipe implementation.
