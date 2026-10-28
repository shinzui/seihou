---
type: Improvement Request
title: Resolve recipe variables and prompts before module resolution
description: Honor recipe-level declarations and prompts so a recipe can ask once for an optional feature and pass the answer to every composed module instead of silently using module defaults.
requestId: IR-11
status: proposed
origin: mori://tan/tan-seihou-modules
affects: mori://shinzui/seihou
affectedVersion: 0.11.0.1
generated:
  by: codex-cli/gpt-6.1-sol
  at: "2026-10-28T12:26:05Z"
timestamp: 2026-10-28T12:26:05Z
reviews:
  - kind: model
    reviewer: codex-cli/gpt-6.1-sol
    reviewed_at: 2026-10-28T12:30:01Z
    document_timestamp: 2026-10-28T12:26:05Z
    scope: content-and-metadata
    outcome: approved
    context: Author self-review against current source, installed CLI evidence, and the local profile; not an independent review.
    provider: openai
    model: gpt-6.1-sol
    effort: unspecified
---

# Resolve recipe variables and prompts before module resolution

## Context and observed behavior

The proposed TAN Keiro recipe combines
`mori://shinzui/seihou-modules/templates/git-init`,
`mori://shinzui/seihou-modules/templates/nix-haskell-flake`,
`mori://shinzui/agent-seihou/templates/master-plan`, and
`mori://shinzui/seihou-modules/templates/haskell-keiro-project`.
It must ask whether to create a GitHub repository and whether to enable Redpanda,
while keeping PostgreSQL, process-compose, intention tracking, and TAN Mori
inventory generation enabled. Upstream modules default both optional choices to
false, so their prompts normally do not run.

`Seihou.Composition.Recipe.expandRecipe` returns recipe declarations and prompts,
but `seihou-cli/src-exe/Seihou/CLI/Run.hs` destructures them as `_recipeVars` and
`_recipePrompts` and discards both. Only literal module-entry bindings enter
`recipeOverrides`. A recipe that declares a required boolean without a default
therefore cannot request an explicit decision before module resolution.

Reproduced against installed `seihou v0.11.0.1 (4ade3fb)` on 2026-10-28 using
an isolated XDG configuration and a local recipe/module fixture. The recipe
declared required `probe.enabled` with no default and prompt `Enable the feature?`.
Its module declared the same variable with default false and rendered that value.
With stdin closed, the command incorrectly succeeded:

```text
$ seihou run probe-recipe --dry-run --no-save-prompted </dev/null
Generation Plan (probe-module):
  Variables:
    probe.enabled = false
  Operations:
      [new]  value.txt  (template, probe-module)
```

The fixture uses the ordinary `Recipe.vars`, `Recipe.prompts`, and module
`VarDecl` records. No source modification is needed to reproduce: scaffold a
module and recipe with `seihou new-module` and `seihou new-recipe`, add the
conflicting declarations above, and place them in `.seihou/modules/`.

## Requested behavior and acceptance

Resolve recipe declarations and conditional prompts before resolving the modules.
An unresolved required recipe choice must prompt in a terminal and fail clearly
without a terminal, even when a consuming module has a default. A false answer
must remain false; a true answer must reach every declaring consumer. Explicit
CLI values and normal configuration must avoid unnecessary repeat questions.
Preserve the established precedence of CLI values over recipe-supplied bindings,
and reject invalid answers before writing files or running commands. Preserve
recipes that have no declarations or prompts.

Prove the normal interactive command asks the two TAN decisions exactly once,
without `--confirm-defaults`, and that fully supplied CLI values work without a
terminal. Include conditional prompts such as GitHub owner/name only when GitHub
creation is selected, dry-run without filesystem changes, and the existing recipe
update/saved-input workflow so fixing first use does not introduce new prompts
on ordinary updates. State the supported binary/release in the delivery evidence.

## Ownership and related work

The user will fix Seihou before the TAN recipe is implemented. This request is
an external prerequisite of
`mori://tan/tan-seihou-modules/masterplans/1-bootstrap-tan-keiro-projects-with-a-cross-registry-recipe`.
The `mori://shinzui/seihou-schema` project already declares recipe vars and prompts;
its `Recipe.dhall` is the project-relative schema source (artifact URI pending).
This request does not add an agent workflow or a TAN-specific engine flag.
