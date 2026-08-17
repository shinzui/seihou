# Bundle Update Log

## 2026-08-17
* **Addition**: IR-6 requests that `seihou agent migrate` work without a trailing PROMPT on the
default claude-cli provider. `claude -p` requires a user message, seihou sends only a system prompt,
and `initialPrompt` is typed and documented as optional — so the invocation every worked example
shows fails on the first edge of every chain, and the error blames the provider. Observed running
keiro-upgrade against mori. The surrounding fail-closed behaviour was correct: no receipt, no source
touched, resumable. Asks for a default instruction, a required argument, or a per-provider fallback.

* **Addition**: IR-5 requests that a blueprint author be able to verify an entailed edge resolves
from the source consumers install from. Observed at the keiro 0.13.0.0 release: an entailment was
correct and the entailed blueprint declared exactly the named edge, but its commit was unpushed, so
every consumer's run would have refused. `validate-blueprint` passes correctly because the question
is not a property of the blueprint being validated, and `--debug migrate` passes because it
resolves the author's own machine — so the preview's reassurance is strongest where it is least
warranted. Asks for resolved-blueprint provenance in the preview, and an opt-in mode that resolves
entailments against their recorded remote.

## 2026-08-16
* **update**: IR-1 is implemented. A blueprint migration receipt now carries an outcome; an edge reports inapplicability through a signal file (interactive providers) or a trailing SEIHOU: not-applicable line (API providers), the chain continues past it, and only an applied receipt suppresses a later run. A dedicated exit code was rejected because an interactive session's exit code is the shell's.
* **Update**: IR-3 is implemented. seihou agent run and seihou agent migrate now consult ManifestGuard before doing any work and refuse a stale or substituted artifact, with a --allow-downgrade override. The blanket --debug exemption applies to agent migrate only, because agent run --debug still applies the baseline and records provenance. ADR 0003 was amended to cover the agent path.
* **Update**: IR-4 is implemented. seihou install classifies the existing installation before removing it and refuses a different-source or unprovenanced overwrite; --force overrides and prints what it overrode. Namespacing the cache by repository stays rejected, now recorded in ADR 0006.
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
