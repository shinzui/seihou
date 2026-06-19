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

The output is derived documentation. Regenerate it from the registry rather than hand-editing
the Markdown files. Each generated document includes a `resource` frontmatter field pointing
back to the source registry path.

For the current `seihou-modules` registry, the command writes 8 concepts. If the `okf` CLI is
available, useful follow-up checks are:

```bash
okf validate okf-docs
okf index okf-docs --write
okf graph okf-docs --json
```
