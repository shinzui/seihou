---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Improvement Request

- [Add a not-applicable outcome for blueprint migration edges](add-a-not-applicable-outcome-for-blueprint-migration-edges.md) - Give a blueprint migration edge a way to report that its precondition is unmet so the edge is left unrecorded, instead of a deliberate no-op returning a receipt indistinguishable from a completed upgrade.
- [Guard the agent path against stale and substituted artifacts](guard-the-agent-path-against-stale-and-substituted-artifacts.md) - Apply the ADR 0003 refusal to seihou agent run and seihou agent migrate, which write baseline files and migration receipts today without ever consulting ManifestGuard, so a substituted or downgraded blueprint is caught on the agent path as it already is on the module path.
- [Record artifact origin for agent-applied artifacts](record-artifact-origin-for-agent-applied-artifacts.md) - Give AppliedBlueprint, AppliedBlueprintMigration, and AppliedRecipe the same ArtifactOrigin the module records already carry, so manifest provenance for agent-run artifacts is an identity ADR 0002 accepts rather than the bare name it explicitly rejects.
- [Refuse to overwrite an installation from a different source](refuse-to-overwrite-an-installation-from-a-different-source.md) - Make seihou install read the origin metadata it is about to delete and refuse when the incoming artifact comes from a different repository, instead of warning and replacing, since the install cache is keyed by bare name and a registry entry has no rename escape hatch.
- [Supply an initial instruction to CLI providers, or require one](supply-an-initial-instruction-to-cli-providers.md) - Make seihou agent migrate work without a trailing PROMPT on the default claude-cli provider, which today fails on its first edge because claude -p requires a user message and seihou sends only a system prompt.
- [Verify an entailed edge is reachable by consumers, not just declared locally](verify-an-entailed-edge-is-reachable-by-consumers.md) - Give a blueprint author a way to check that an entailed blueprint's exact edge resolves from the source consumers install from, since validate-blueprint correctly ignores the question and the --debug preview answers it against the author's own working tree.

