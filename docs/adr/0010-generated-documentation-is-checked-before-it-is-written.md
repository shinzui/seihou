# ADR 0010 — Generated documentation is checked before it is written, and never reads the clock

- Status: Accepted
- Date: 2026-09-10

## Context

`seihou-okf-extension docs` turns a registry repository into an OKF documentation
bundle: one Markdown concept per published module, recipe, blueprint and agent
prompt, plus one describing the registry itself. The output is *derived*. Nobody
edits it; it is regenerated whenever the registry changes, and it is checked into
the registry repository so that a reader can browse it without running anything.

Two properties of derived output are easy to lose, and both were lost or at risk
before this decision was written down.

The first is **that the output satisfies its own format**. The generator
originally validated with okf's `PermissiveConformance` profile, which asks only
that a concept carry a non-empty `type`. A bundle could therefore be written with
no title, no description, and no record of what produced it, and okf would raise
nothing — while `okf validate --strict`, the check a consumer actually runs,
would reject every page. Producing documentation that its own format's strict
checker refuses is a defect the producer can simply not have: the generator
controls every field involved.

The second is **that regenerating unchanged input produces unchanged output**.
The obvious way to record when documentation was generated is to read the clock.
That single call makes every regeneration a diff: a registry author who
regenerates after an unrelated change sees every page as modified, review stops
distinguishing content changes from timestamp churn, and golden-file tests
become untestable.

There is also a third property that is not part of the OKF standard at all: the
house conventions a *seihou* documentation bundle follows, over and above what
OKF requires — that every concept points back at the `.dhall` it was derived
from through a `seihou://` resource, that its `generated.by` is a producer
actor, that modules live under `modules/`, and so on. OKF has a mechanism for
exactly this — a **profile**, a Dhall descriptor checked against a bundle — but
a profile is only useful if something actually runs it.

## Decision

**Generated documentation is validated against the strictest rules its format
offers, and against its own house profile, before a single file is written. A
bundle that fails either check is not written at all.**

Concretely, in `seihou-okf-extension`:

- The default OKF validation profile is `StrictAuthoring`, not
  `PermissiveConformance`. `--permissive` remains available for an operator who
  needs it, but it is an escape hatch, not the default.
- Strict validation requires a non-empty `description`. The generator resolves
  one deterministically rather than failing: the registry catalog entry's
  description, else the artifact's own, else a synthesized sentence naming the
  kind, the artifact and the registry. The same value goes into the frontmatter
  and into the body's opening paragraph, so the two can never disagree.
- A house profile descriptor is authored in the extension
  (`seihou-okf-extension/profile/seihou-registry-docs.dhall`), embedded in the
  executable with `file-embed`, and checked against the rendered concepts in
  process. It is also written to `<out>/profile.dhall`, so a consumer can re-run
  the identical check with `okf validate --profile <bundle>/profile.dhall
  --profile-enforce`.
- Both checks run **before** the output directory is prepared. A failing run
  leaves whatever was already there untouched, rather than clearing it and then
  refusing to write a replacement.

**And: nothing in the generator reads the clock.** A generation date enters the
bundle only when an operator passes `--generated-at DATE`, whose value is
recorded verbatim. With it omitted — the default — two consecutive runs over an
unchanged registry produce byte-identical bytes.

The same rule extends to every other source of incidental ordering. A `Map` is
walked in key order before rendering, never in whatever order it happens to hold.
Two runs that differ is a defect, not a quirk.

## Consequences

`okf validate <bundle> --strict` and
`okf validate <bundle> --strict --profile <bundle>/profile.dhall
--profile-enforce` both exit 0 on any bundle this generator wrote, because the
generator ran the same two checks on itself first. A consumer never has to
discover that generated documentation fails the checks its own producer
advertises.

The generated bundle is safe to commit. A regeneration that changes nothing
produces no diff, so a review of a registry change shows exactly the
documentation that change altered.

The house profile is a real artifact with a real cost: it must be kept in step
with what the generator emits, and a change to either without the other fails
the extension's tests. That is the point — it is the executable statement of
what a seihou documentation bundle is, rather than a convention living only in
the renderer's source.

A profile can only demand what the input can supply. The descriptor marks
`version` **optional** rather than required, because `seihou-registry.dhall`
itself declares `version : Optional Text`; a profile that required it would
refuse a registry that is valid by its own schema. When a house convention and
the input schema disagree, the input schema wins.

Because `--generated-at` is the only way a date enters the bundle, a bundle that
uses it earns one `log:` advisory per concept from `okf validate` — a generation
date with no enclosing `log.md` to date it against. Those are advisories, not
failures, and the trade is deliberate: byte-stability by default is worth more
than a date nobody asked for.

## References

- [ADR 0008](0008-an-entailed-migration-edge-is-owned-by-the-blueprint-that-declares-it.md)
  — why an entailed edge naming a blueprint outside the registry is rendered as
  labelled text rather than as a cross-link: okf reports a link to a concept
  that is not in the bundle as dangling, and this ADR makes that fatal.
- [ADR 0009](0009-seihou-reads-no-package-manager-format-artifacts-declare-the-command.md)
  — why `Blueprint.versionProbe` exists, and therefore why documenting the probe
  command documents a user-visible contract rather than an implementation detail.
- `docs/masterplans/7-generate-okf-documentation-bundles-for-seihou-registries.md`
  — the original delivery of the generator.
- `docs/plans/88-upgrade-seihou-okf-extension-to-okf-core-0-8-0-0-and-render-every-seihou-artifact-feature.md`
  — the plan this decision was distilled from.
- `docs/cli/okf-docs.md` and `docs/user/registry-documentation.md` — the command
  reference and the authoring guide.
