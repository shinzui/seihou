---
type: Friction Entry
title: "Isolated acceptance HOME hides private registry credentials"
description: "Isolating HOME and XDG settings for empty Seihou caches also hides the GitHub credential helper and gh authentication used by the private TAN registry."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-10-29T03:45:14Z"
frictionId: FRIC-7
status: "resolved"
impact: detour
kind: environment
origin: "mori://shinzui/seihou"
affects: "mori://shinzui/seihou"
plan: "docs/plans/117-let-recipes-enforce-configured-variable-values.md"
workaround: "Read the existing gh token directly into subprocess memory, retain it as GH_TOKEN without printing or writing it, and supply only the gh credential helper through scoped Git environment configuration."
resolution: "The acceptance harness retains current gh credentials only in child-process memory and configures its credential helper while isolating all Seihou state."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-10-29T03:53:45Z"
    change: "Record the working private-registry authentication preparation; no credentials are written into evidence."
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-10-29T04:01:02Z"
    change: "Correct the workaround: retaining Git and gh config paths alone did not preserve macOS keyring authentication under the isolated HOME."
---
# Isolated acceptance HOME hides private registry credentials

## Attempted

Install the real private TAN recipe in an empty isolated HOME/config/cache using seihou install.

## Encountered

git clone could not read Username for https://github.com because the normal XDG git configuration was hidden.

## Workaround

Read the existing gh token directly into subprocess memory, retain it as GH_TOKEN without printing or writing it, and supply only the gh credential helper through scoped Git environment configuration. Retaining config paths alone did not preserve keyring authentication under the isolated HOME.
