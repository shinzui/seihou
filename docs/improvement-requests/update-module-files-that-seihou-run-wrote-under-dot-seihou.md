---
type: Improvement Request
title: Let seihou update reconcile module files that seihou run wrote under .seihou
description: >-
  Resolve the disagreement between seihou run, which lets a module generate files under
  .seihou/, and seihou update, which refuses to reconcile any managed path there, so that
  applications of recipes such as fumadocs-site can be updated instead of forcibly reapplied.
generated:
  by: process:claude-code
  at: "2026-11-10T22:29:39Z"
timestamp: 2026-11-11T13:54:44Z
requestId: IR-19
status: accepted
targetPlan: docs/plans/120-let-seihou-update-reconcile-module-owned-files-under-seihou.md
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
      Author check against the Seihou source at fcaa6f4 and repeated updates of a real
      fumadocs-site application. Not an independent approval.
---

# Improvement Request: Let seihou update Reconcile Module Files That seihou run Wrote Under .seihou

## Status

Accepted and planned in [ExecPlan 120](../plans/120-let-seihou-update-reconcile-module-owned-files-under-seihou.md).
Raised from `FRIC-4`
(`mori://shinzui/kotei-docs/okf/friction-log/concepts/FRIC-4`) against Seihou 0.15.0.0.
The plan chooses option 1: a module owns `.seihou/<module-name>/`, which `seihou run` and
`seihou update` both accept, while an explicit reserved list keeps Seihou's own entries
(the manifest, `baselines/`, `transactions/`, `modules/`, configuration, context and trace)
and `.git` unreachable from module output through both commands. Existing applications of
`docs-mori-bootstrap` need no module change. Implementation remains pending.

## Context

`mori://shinzui/kotei-docs` applies the `fumadocs-site` recipe from
`mori://shinzui/seihou-modules`. The recipe includes `docs-mori-bootstrap`, which
generates `.seihou/docs-mori-bootstrap/bootstrap-docs.py`. `seihou run` writes and
records that file without complaint. To take `fumadocs` 0.5.0, the site ran
`seihou update fumadocs --dry-run` and got:

```text
reconciliation_failed for .seihou/docs-mori-bootstrap/bootstrap-docs.py
Path .seihou/docs-mori-bootstrap/bootstrap-docs.py cannot be reconciled: path targets Seihou or Git control data
```

The site then moved to `fumadocs` 0.5.0, 0.6.0 and 0.6.2 by running
`seihou run fumadocs-site --force --with-migrations` with every recorded variable, and
restoring its local edits to managed files by hand each time. The
`relaunch-fumadocs-docs` blueprint now prescribes that procedure for every site.

## Problem

`validateManagedPath` in `seihou-core/src/Seihou/Engine/Reconcile.hs`, and its
counterpart in `UpdateTransaction.hs`, reject every path whose first segment is
`.seihou` or `.git`. Generation applies no such rule, so a module can own a file that
the update engine will never touch again. Every application that includes such a
module can no longer be updated:

- Updates fall back to `--force` reapplication, which overwrites managed files and
  loses the three-way merge that `seihou update` provides.
- A consumer has to know every variable to pass again; a missed one silently resets to
  its default.
- The failure surfaces at update time, in a different project, long after the module
  author made the choice.

## Requested change

Make generation and reconciliation agree. Either of these would do:

1. Allow reconciliation of managed paths under a module-owned part of `.seihou/`, such as
   `.seihou/<module>/`, while still refusing Seihou's own state: the manifest,
   `baselines/` and `transactions/`.
2. Refuse a module that generates into `.seihou/` or `.git/` when it is validated or
   applied, with a message telling the author to choose a project path, so the conflict
   is found by the author, not the consumer.

## Acceptance criteria

- A module that generates a file under its chosen location can be applied with
  `seihou run` and later updated with `seihou update`, with the normal merge and
  conflict handling.
- Seihou's own state under `.seihou/` stays unreachable from module output, through
  `run` and through `update`.
- `seihou update fumadocs` on a `fumadocs-site` application succeeds after the
  corresponding change in `docs-mori-bootstrap`, if option 2 is chosen.

## Scope and design questions

Option 1 needs a precise rule for what in `.seihou/` is Seihou's. Option 2 is smaller,
but requires `docs-mori-bootstrap` in `mori://shinzui/seihou-modules` to move its
generated files, which would itself have to migrate existing applications.

## Related

- `mori://shinzui/kotei-docs/okf/friction-log/concepts/FRIC-4`
- [IR-16](fail-a-non-interactive-update-that-applied-nothing.md), another `seihou update` limit
