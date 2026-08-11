# Bundle Update Log

## 2026-08-06
* **Addition**: IR-2 requests an `ArtifactOrigin` on `AppliedBlueprint`, `AppliedBlueprintMigration`,
  and `AppliedRecipe`, so agent-path provenance is the identity ADR 0002 accepts rather than the
  bare name it rejects, and so a migration receipt cannot suppress a different blueprint's edge.

## 2026-07-31
* **Addition**: IR-1 requests a not-applicable outcome for blueprint migration edges, so an edge
  that correctly declines an unmet precondition is not recorded as a completed upgrade and then
  silently skipped on the run that should have applied it.
