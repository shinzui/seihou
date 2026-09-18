# ADR 0015 — Diagnostics name things as users do and never fall back to `show`

- Status: Accepted
- Date: 2026-09-18

## Context

BUG-1 (`docs/bug-reports/additive-only-gate-breaks-targeted-update-on-preexisting-manifests.md`)
was first a safety-gate defect, but its cost was multiplied by how `seihou update` talked
about it. Three presentation failures compounded:

- The ownership-closure error named co-owners by their 64-character application id. An
  application id is a SHA-256 of the target and additional modules
  (`Seihou.Core.Application.mkApplicationId`). Nobody recognises it, and `seihou status`
  already named the same applications as `link-skill [skill.name=exec-plan]`.
- `warningText` in `Seihou.CLI.Update.Render` had a dedicated case for one constructor and
  `warningText other = T.pack (show other)` for the rest. `errorMessage` did the same for
  25 of its 32 constructors. A new constructor compiled cleanly and reached the terminal
  as derived `Show`:
  `CrossApplicationLastWriter "…" (ModuleName {unModuleName = "exec-plan"}) …`.
- The remedies were listed in one fixed order for every cause. `--include-shared-owners`
  came before the one operation that repaired the missing fact. It was a remedy for a
  different cause, and following it broadened a one-module update into an eight-file
  rewrite of unrelated applications.

Each was a local shortcut that looked harmless on its own. Together they turned a
recoverable refusal into guidance that made the situation worse.

## Decision

**One display vocabulary.** A recorded application is named in human output through
`Seihou.CLI.ApplicationDisplay`: its target, the root instance's parent variables as sorted
`[key=value, ...]`, and any additional modules as `(with a, b)`. Because target and
additional modules are exactly what the id hashes, the label is unique among recorded
applications by construction. `seihou status` and `seihou update` both render through this
module, so the two cannot drift. A digest appears only as a short prefix, and only for an
owner that a file record names but the manifest does not record as an application. Labels
use only identity context the manifest records verbatim, never resolved variable values.

**Safety algorithms stay renderer-neutral.** Selection and certification carry an
`ApplicationRef` (id, target, parent variables, additional modules), never pre-rendered text.
They pass a structured value and the renderer decides the words, so a wording change cannot
alter a safety decision.

**Every user-facing renderer of a sum type is an exhaustive match with no `show`
fallback.** This holds for warnings and errors alike, in human and JSON output. A new
constructor must fail to compile or fail a test until someone writes its sentence.
`seihou-cli/test/Seihou/CLI/UpdateRenderSpec.hs` holds one value of every `UpdateWarning`
constructor. It asserts that no output contains constructor syntax, `unModuleName`, or a
whole 64-character digest.

**A remedy is specific to its cause and leads the message.** Stable machine codes identify
the cause (`shared_path_requires_applications`, `shared_write_evidence_unavailable`,
`manifest_upgrade_required`). Each message begins with the operation that repairs that
cause. A flag that broadens the work, such as `--include-shared-owners`, is offered only
when broadening actually repairs the cause, and the message says what it broadens.

## Consequences

- Adding a warning or error constructor costs a sentence and a test entry. This is
  deliberate: the sentence is part of the feature.
- Nested error types without their own renderer (module load, migration, reconciliation,
  transaction) have local prose renderers in `Update.Render`. If another command needs the
  same wording, move the renderer next to its type rather than copying it.
- JSON output keeps its string-typed `warnings` and error `message`. Scripts depend on
  `code` and the structured keys, people on the message. Changing a message does not
  version the envelope; changing a key's type or meaning does.
- Other commands still contain `show`-based fallbacks
  (for example `renderTransactionPathError` in `Seihou.Engine.UpdateTransaction`). This
  ADR applies to them as they are touched. It does not require a sweep.

## References

- [ADR 0012](0012-an-additive-co-write-is-not-a-shared-path-conflict.md) — the
  shared-path rule whose three answers these diagnostics explain.
- [ADR 0013](0013-status-is-a-bounded-summary-the-manifest-is-the-record.md) — the
  status output whose application naming update now shares.
- [ADR 0007](0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md) — outcomes
  are distinguished for people as well as for exit codes.
- `docs/masterplans/11-make-manifest-evolution-explicit-and-targeted-updates-upgrade-safe.md`
  and `docs/plans/95-make-shared-owner-diagnostics-actionable-and-verify-upgrades.md` — the
  work that established this.
