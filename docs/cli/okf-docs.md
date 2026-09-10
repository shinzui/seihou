# `seihou-okf-extension docs`

`seihou-okf-extension docs` generates an Open Knowledge Format documentation bundle from a
seihou registry repository. The input directory must contain `seihou-registry.dhall`.

```bash
seihou-okf-extension docs --dir /path/to/seihou-modules --out okf-docs
```

The same command can run through the seihou extension host when `seihou-okf-extension` is on
`PATH`:

```bash
seihou extension run okf -- docs --dir /path/to/seihou-modules --out okf-docs
```

Options:

- `--dir PATH`: registry directory. Defaults to `.`.
- `--out PATH`: output bundle directory. Defaults to `okf-docs`.
- `--force`: remove and recreate a non-empty output directory.
- `--generated-at DATE`: an ISO-8601 date or timestamp recorded verbatim as each concept's
  OKF `generated.at`. Omitted by default, so regenerating an unchanged registry produces
  byte-identical output — nothing in the generator reads the clock.
- `--permissive`: validate with OKF permissive conformance instead of the default strict
  authoring rules.
- `--profile PATH`: check the bundle against this house profile descriptor instead of the
  built-in one.
- `--no-profile`: skip house-profile enforcement entirely.

The output is derived documentation. Regenerate it from the registry rather than hand-editing
the Markdown files. Each generated document includes a `resource` frontmatter field pointing
back to the source registry path.

## What the bundle contains

For the current `seihou-modules` registry (7 modules, 2 recipes, 3 blueprints, 0 prompts) the
command writes **13** concepts: one per registry entry, plus one describing the registry
itself.

```text
okf-docs/
  index.md                  bundle root index; declares okf_version: "0.2"
  profile.dhall             the house profile the bundle was checked against
  modules/index.md          section index
  modules/<name>.md         one concept per published module
  recipes/<name>.md
  blueprints/<name>.md
  prompts/<name>.md
  registry/<repo>.md        the registry overview, linking every artifact
```

Every concept carries a `generated` block naming its producer as
`seihou-okf-extension/<version>`, so `okf trust` reports a real trust tier for each one, and
a `status: stable` lifecycle field.

Each document renders what its artifact actually declares. A module document lists its
dependencies, its variables with their declared type, requiredness, default, validation rule
and description, its exports and any aliases, its interactive prompts, its generation steps
(strategy, source, destination, patch operation, condition), its shell commands, its removal
procedure, and each migration edge with the operations it performs. A blueprint document adds
its tool allowlist, agent launch preferences, version-probe command, and migration edges with
their entailment. A prompt document adds its command-derived variables and guidance blocks.
A section the artifact declares nothing for is omitted rather than printed empty.

An entailed migration edge naming a blueprint published by the same registry renders as a
cross-link to that blueprint's document. One naming a blueprint outside the registry renders
as plainly labelled text, because an entailed edge is owned by the blueprint that declares it
and may legitimately live in another repository entirely — see
[ADR 0008](../adr/0008-an-entailed-migration-edge-is-owned-by-the-blueprint-that-declares-it.md).

## Follow-up checks

If the `okf` CLI is available:

```bash
okf validate okf-docs --strict
okf validate okf-docs --strict --profile okf-docs/profile.dhall --profile-enforce
okf trust okf-docs
okf concepts okf-docs --type SeihouBlueprint
okf concepts okf-docs --where tags=migration
okf graph okf-docs --json
```

`okf validate --strict` exits 0 on a freshly generated bundle, and so does the
profile-enforcing form: the generator runs the same profile check on itself, before it writes
anything, so a bundle that would violate the house convention is never written at all.

Passing `--generated-at` makes `okf validate` emit one `log:` advisory per concept — a
generation date with no enclosing `log.md` to date it against. The advisories do not fail
validation unless you also pass `--log-enforce`.
