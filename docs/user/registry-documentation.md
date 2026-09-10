# Documenting a registry

A registry repository is a catalogue: `seihou-registry.dhall` at its root lists the modules,
recipes, blueprints, and prompts the repository publishes, and each artifact's own `.dhall`
file says what it does. That is precise, but it is not something you hand to a colleague who
wants to know what is available and what each thing needs from them.

`seihou-okf-extension docs` turns the registry into a browsable documentation set: one
Markdown page per published artifact, plus one describing the registry itself, with links
between them wherever the artifacts reference one another.

```bash
seihou-okf-extension docs --dir . --out okf-docs
```

or, through seihou's extension host, when `seihou-okf-extension` is on your `PATH`:

```bash
seihou extension run okf -- docs --dir . --out okf-docs
```

The output is an **OKF bundle** — a directory of Markdown files in the Open Knowledge Format,
each with a block of YAML metadata at the top. Any OKF tool can read it; the `okf` CLI can
validate it, index it, graph it, and query it.

## The output is derived — regenerate it, never edit it

Every page is generated from the `.dhall` sources. An edit you make by hand disappears the
next time anyone runs the command, so the way to change a page is to change the artifact it
describes. Each page records where it came from in a `resource:` field, for example
`seihou://seihou-modules/modules/haskell/nix-haskell-flake`, so a reader can always find the
source. Regenerating an unchanged registry produces byte-identical output, which makes the
bundle safe to commit and to diff in review.

## What ends up on each page

Every page carries the artifact's name, its description, and the version the registry catalog
records. Beyond that, a page shows what its artifact actually declares — and omits the
sections it declares nothing for.

For a **module** (`module.dhall`):

| Section | Comes from |
| --- | --- |
| Dependencies | `dependencies`, with the variable bindings each edge supplies |
| Variables | `vars` — each declaration's type, requiredness, default, validation rule, description |
| Exports | `exports`, including the alias when one is declared |
| Prompts | `prompts` — the question, its choices, and the condition that gates it |
| Generation steps | `steps` — strategy, source, destination, patch operation, condition |
| Commands | `commands` — the command, its working directory, its condition |
| Removal | `removal` — each removal step and the commands that follow |
| Migrations | `migrations` — each `from → to` edge and the operations it performs |

For a **recipe** (`recipe.dhall`): the modules it composes, with the variable bindings it
preconfigures for each, plus its own variables and prompts.

For a **blueprint** (`blueprint.dhall`): its base modules, the full agent prompt, its
variables and prompts, its reference files, its tool allowlist (`allowedTools`), its agent
launch preferences (`launch`), its version-probe command (`versionProbe`), and its migration
edges with their entailment.

For an **agent prompt** (`prompt.dhall`): the full prompt, its variables and prompts, its
command-derived variables (`commandVars`), its conditional guidance blocks (`guidance`), its
reference files, its tool allowlist, and its launch preferences.

Conditions are shown in the same `when` syntax you wrote them in, for example
``when `Eq nix.treefmt true` ``.

## Entailed migration edges

If a blueprint migration edge declares that crossing it entails crossing an edge of another
blueprint (see [Blueprint migrations](blueprint-migrations.md)), the entailed edge appears
under an `Entails:` heading. When the entailed blueprint is published by the *same* registry,
it is a link to that blueprint's page. When it lives somewhere else — which is the normal
case, and the whole point of entailment — it is shown as labelled text ending in
`(declared outside this registry)`, because there is no page in this bundle to link to.

## Checking the bundle

The generator validates the bundle against the OKF strict authoring rules and against a house
profile — a descriptor saying what a seihou documentation bundle's metadata must carry — and
refuses to write anything if either check fails. It writes that descriptor into the bundle as
`profile.dhall`, so you can re-run the same checks yourself:

```bash
okf validate okf-docs --strict
okf validate okf-docs --strict --profile okf-docs/profile.dhall --profile-enforce
```

Two more that are worth knowing about:

```bash
okf trust okf-docs                              # who produced each page
okf concepts okf-docs --type SeihouBlueprint    # just the blueprints
okf concepts okf-docs --where tags=migration    # anything tagged migration
```

## Recording a generation date

By default no page carries a date, which is what keeps regeneration byte-stable. If you want
one — a CI job stamping a release date, say — pass it explicitly:

```bash
seihou-okf-extension docs --dir . --out okf-docs --generated-at 2026-09-10
```

The value is recorded verbatim. `okf validate` will then note one advisory per page, saying
the date has no `log.md` to date it against; that is a lint, not a failure.

## Options you are unlikely to need

- `--permissive` validates against OKF's permissive conformance rules rather than the strict
  authoring rules.
- `--profile PATH` checks against your own house profile instead of the built-in one.
- `--no-profile` skips the house-profile check entirely.

The full option list is in [`seihou-okf-extension docs`](../cli/okf-docs.md).
