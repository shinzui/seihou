---
type: Improvement Request
title: Refresh installed blueprints in seihou upgrade
description: >-
  Make seihou upgrade refresh installed blueprints from their source repositories, as it
  already does for modules and recipes, so that publishing a blueprint fix and running
  seihou upgrade puts the fix in front of the next seihou agent run.
generated:
  by: process:claude-code
  at: "2026-11-10T22:29:39Z"
timestamp: 2026-11-11T15:00:00Z
requestId: IR-17
status: completed
completedAt: "2026-11-11T15:00:00Z"
resolution: >-
  seihou upgrade refreshes installed blueprints and prompts from the source their
  .seihou-origin.json records, each blueprint together with its baseModules closure,
  restaged as seihou install would and published only where content changed. With no
  names every provenanced blueprint and prompt is included; a named one exits 0 with old
  and new versions in text and --json. ADR 0006 refusals and named entries without
  provenance are failed rows that leave the cache untouched, and seihou upgrade exits 1
  when any row failed. seihou outdated lists blueprints and prompts. ADR 0006 is amended;
  unreleased.
targetPlan: docs/plans/121-refresh-installed-blueprints-and-prompts-in-seihou-upgrade.md
origin: mori://shinzui/kotei-docs
reviews:
  - kind: model
    reviewer: process:claude-code
    provider: anthropic
    model: claude-opus-5-5
    effort: unspecified
    reviewed_at: "2026-11-10T22:29:39Z"
    document_timestamp: "2026-11-10T22:29:39Z"
    scope: content-and-metadata
    outcome: commented
    context: >-
      Author check against the Seihou source at fcaa6f4 and the installed 0.15.0.0 (a4fcee6).
      Not an independent approval.
---

# Improvement Request: Refresh Installed Blueprints in seihou upgrade

## Status

Completed in source through
[ExecPlan 121](../plans/121-refresh-installed-blueprints-and-prompts-in-seihou-upgrade.md) and
recorded as an amendment to
[ADR 0006](../adr/0006-the-install-cache-will-not-silently-substitute-an-artifact.md); it ships
with the next release after Seihou 0.15.0.0. `UpgradeRunnablesE2ESpec` drives the real binary
through the FRIC-5 scenario: after a producer bump, `seihou upgrade bp --json` reports
`0.1.0 -> 0.1.1` and `seihou agent --debug run bp` prints `Version: 0.1.1`. Every acceptance
criterion below holds. Prompts are covered as well as blueprints.

Previously accepted. Raised from `FRIC-5`
(`mori://shinzui/kotei-docs/okf/friction-log/concepts/FRIC-5`) against Seihou 0.15.0.0.
Planned on 2026-11-11 in
[ExecPlan 121](../plans/121-refresh-installed-blueprints-and-prompts-in-seihou-upgrade.md).
The plan answers the scope question below by covering prompts as well as blueprints. It
refreshes each blueprint together with its `baseModules` closure, and it extends
`seihou outdated`.

## Context

`mori://shinzui/kotei-docs/plans/15-create-a-seihou-blueprint-that-relaunches-legacy-fumadocs-documentation-sites`
rehearsed the `relaunch-fumadocs-docs` blueprint from `mori://shinzui/seihou-modules`
with unattended `seihou agent run --batch` sessions. After the first rehearsal found a
defect, version 0.1.1 was pushed and `seihou upgrade` was run. The next rehearsal ran for
an hour on 0.1.0. `seihou agent --debug run relaunch-fumadocs-docs` still printed
`Version: 0.1.0`. Only `seihou install https://github.com/shinzui/seihou-modules.git
--module relaunch-fumadocs-docs` replaced the installed copy.

## Problem

`handleUpgrade` in `seihou-cli/src-exe/Seihou/CLI/Upgrade.hs` builds its candidate set
from installed modules and from runnables whose kind is `KindRecipe`:

```haskell
let installed = filter (\dm -> dm ^. #source == SourceInstalled) modules
    recipes = [recipe | recipe <- runnables, recipe ^. #source == SourceInstalled, recipe ^. #kind == KindRecipe]
```

Installed blueprints are never selected. When a blueprint is named explicitly, the
command answers `Module(s) or recipe(s) not found` and exits non-zero. Its help says it
"refreshes installed modules and recipe closures", which is accurate, but a user who has
installed a blueprint the same way, with `seihou install`, expects the same refresh.
`doUpgrade` already recognizes a `SingleBlueprint` repository shape and returns
`Nothing` for it.

The consequence is silent. `seihou agent run` uses the stale copy without warning, and
ADR 0003's guard does not fire, because no manifest records the newer version.

## Requested change

1. Include installed blueprints with origin metadata in `seihou upgrade`, both when no
   names are given and when a blueprint is named. Refresh them from their source
   repository the way modules are refreshed, honouring ADR 0006's same-source rule.
2. Report each upgraded blueprint with its old and new versions, in text and in `--json`.
3. Have `seihou outdated` list installed blueprints whose source has a newer version.

## Acceptance criteria

- After a newer blueprint version is pushed to its source, `seihou upgrade` replaces the
  installed copy, and `seihou agent --debug run <name>` shows the new version.
- `seihou upgrade <blueprint-name>` upgrades that blueprint and exits 0.
- A blueprint installed from a different source, or without provenance, is refused as
  ADR 0006 requires.
- `docs/cli/upgrade.md` and the command help mention blueprints.

## Scope and design questions

Prompts installed through `seihou install` may have the same gap, since `SinglePrompt`
is handled the same way. Covering every installable kind at once may be simpler than
adding blueprints alone.

## Related

- `mori://shinzui/kotei-docs/okf/friction-log/concepts/FRIC-5`
- [ADR 0006](../adr/0006-the-install-cache-will-not-silently-substitute-an-artifact.md)
- [IR-18](fail-a-batch-blueprint-run-whose-agent-was-refused-tools.md), the other half of FRIC-5
- [ExecPlan 121](../plans/121-refresh-installed-blueprints-and-prompts-in-seihou-upgrade.md), the implementation plan
