---
type: Friction Entry
title: "Closure acceptance fixtures depend on the working schema gitlink"
description: "The closure shell harness used record completion from the working schema checkout, so an older preserved gitlink rejected source-bearing edges before exercising the CLI."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-11-01T19:42:17Z"
frictionId: FRIC-10
status: "resolved"
impact: detour
kind: tooling
origin: "mori://shinzui/seihou"
affects: "mori://shinzui/seihou"
plan: "docs/plans/118-extend-recipes-through-a-single-origin-aware-base.md"
workaround: "Build fixture records from schema defaults with explicit overrides so edge-shape tests do not depend on the schema gitlink version."
resolution: "The closure harness now builds source-edge fixture records from defaults with explicit overrides; it passes while preserving the older working schema gitlink."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-11-01T19:45:16Z"
    change: "Resolve fixture/schema coupling after the full closure acceptance passes."
---
# Closure acceptance fixtures depend on the working schema gitlink

## Attempted

bash scripts/test-install-closure.sh <source-built-seihou>

## Encountered

Dhall rejected the fixture Recipe.modules annotation because its Dependency type omitted source.

```text
Expression does not match annotation: modules entries contain source
```

## Workaround

Build fixture records from schema defaults with explicit overrides so edge-shape tests do not depend on the schema gitlink version.
