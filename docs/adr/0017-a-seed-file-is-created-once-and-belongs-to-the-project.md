# ADR 0017 — A seed file is created once and belongs to the project

- Status: Accepted
- Date: 2026-10-15

## Context

Starting files such as changelogs belong to the project after creation. Tracking their content forever would obscure useful managed-file drift.

## Decision

Step lifecycle is independent of strategy. An omitted lifecycle means `managed`; `seed` declares a whole file to create once and hand to the project. Seeds support copy, template, and dhall-text, with no patch or structured merge. A destination has one lifecycle. Custom removal must not delete a seed.

The declaration and schema-8 receipt foundations are implemented by [plan 99](../plans/99-declare-seed-steps-in-the-module-schema-and-validate-them.md) and [plan 100](../plans/100-record-seed-receipts-in-manifest-schema-8.md). Runtime seed creation and reporting remain the responsibility of [MasterPlan 12](../masterplans/12-seed-files-module-outputs-created-once-and-owned-by-the-project.md); until those changes land, declaring seed does not activate runtime seed behavior.

Schema 8 adds a `seeds` map keyed by project-relative path. A receipt records its module, application owners, first outcome, and settlement time. It carries no hash or baseline. A path cannot be both managed and seeded. Merging owners preserves the first settlement; dropping the last owner drops the receipt without touching disk. Schema 7 upgrades losslessly by adding an empty map. Older binaries ignore the lifecycle field; producers must require a release supporting runtime seed behavior.

## Consequences

The manifest remains the only applied-state record. Later runtime plans must create only absent seeds and never overwrite, merge, report content drift, or delete them. Decoder compatibility does not establish runtime support.

## Rejected Alternatives

A boolean would not express distinct ownership modes. A new generation strategy would conflate ownership with rendering. A project ignore list would duplicate declared module intent.

## References

- [ADR 0004](0004-the-manifest-is-the-only-record-of-applied-state.md)
- [ADR 0014](0014-every-semantic-manifest-change-advances-the-schema-version.md)
