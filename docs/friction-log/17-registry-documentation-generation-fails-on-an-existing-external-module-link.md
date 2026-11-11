---
type: Friction Entry
title: "Registry documentation generation fails on an existing external module link"
description: "The producer documentation command refuses the registry because fumadocs-site links to technical-docs outside the generated bundle."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-11-11T22:33:23Z"
frictionId: FRIC-17
status: "accepted"
impact: blocked
kind: tooling
origin: "mori://shinzui/seihou"
affects: "mori://shinzui/seihou"
plan: "docs/plans/112-make-gitignore-line-removal-migrations-predictable-during-managed-updates.md"
resolution: "Use the producer documented scripts/generate-okf-docs.py adapter, which handles external edges and strictly validates output; the exporter defect is already recorded at mori://shinzui/seihou-modules/okf/friction-log/concepts/FRIC-14."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-11-11T22:34:45Z"
    change: "Use the established producer authoring workflow; keep the unrelated external-link exporter defect outside plan 112."
---
# Registry documentation generation fails on an existing external module link

## Attempted

seihou extension run okf -- docs --dir . --out okf-docs --force

## Encountered

recipes/fumadocs-site: link to missing concept: modules/technical-docs; no generated output was written

```text
error: extension okf exited with ExitFailure 1
```
