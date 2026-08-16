# Bundle Update Log

## 2026-08-16
* **Update**: IR-2 is implemented. AppliedBlueprint, AppliedBlueprintMigration, and AppliedRecipe now carry an ArtifactOrigin, the blueprint migration completion key includes it, and a record written without one decodes as unverifiable provenance rather than failing.

## 2026-08-06
* **Addition**: IR-2 requests an `ArtifactOrigin` on `AppliedBlueprint`, `AppliedBlueprintMigration`,
and `AppliedRecipe`, so agent-path provenance is the identity ADR 0002 accepts rather than the
bare name it rejects, and so a migration receipt cannot suppress a different blueprint's edge.
* **Addition**: IR-3 requests that `seihou agent run` and `seihou agent migrate` consult
`ManifestGuard`, extending the ADR 0003 refusal to the one path that applies baselines and writes
receipts without it.
* **Addition**: IR-4 requests that `seihou install` read the origin metadata it is about to delete
and refuse a different-source overwrite, since the install cache is keyed by bare name and a
registry entry has no rename escape hatch.

## 2026-07-31
* **Addition**: IR-1 requests a not-applicable outcome for blueprint migration edges, so an edge
that correctly declines an unmet precondition is not recorded as a completed upgrade and then
silently skipped on the run that should have applied it.
