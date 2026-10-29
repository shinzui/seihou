---
type: Friction Entry
title: "Strict bug-report validation lacked review metadata in existing reports"
description: "The existing bug-report bundle lacked the reviews field recommended by its profile, so strict validation failed while recording delivery."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-10-29T13:02:51Z"
frictionId: FRIC-9
status: "resolved"
impact: slowdown
kind: documentation
origin: "mori://shinzui/seihou"
affects: "mori://shinzui/seihou"
plan: "docs/plans/117-let-recipes-enforce-configured-variable-values.md"
resolution: "Record the current BUG-3 completion self-review and catalog-metadata comments for BUG-1/BUG-2; preserve their historical dispositions and do not invent prior reviews. Strict profile/log validation now passes."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-10-29T13:03:25Z"
    change: "Reconcile existing review metadata while recording verified BUG-3 delivery."
---
# Strict bug-report validation lacked review metadata in existing reports

## Attempted

Run okf validate docs/bug-reports --strict --profile docs/bug-reports/profile.dhall --profile-enforce --log-enforce after recording BUG-3 delivery.

## Encountered

All three existing reports were missing profile-recommended reviews metadata; catalog review provenance had to be recorded without inventing historical verification.

```text
profile: a-recipe-cannot-enforce-a-variable-that-global-config-sets: missing profile-recommended field: reviews
```
