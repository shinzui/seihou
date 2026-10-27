# adopt-seed-lifecycle

Help module authors adopt the seed ownership introduced in Seihou 0.11.0.0.
The agent inspects actual steps, templates, documentation and other writers,
adds `lifecycle = Some "seed"` to clear project-owned starters, and validates
the changes. It preserves managed policy and checkout outputs and reports
ambiguous ownership. It has no baseline modules or variable prompts.

Use Seihou 0.11.0.0 or newer and a configured agent provider able to inspect
and edit the author repository; the CLI providers support this workflow.
Seihou 0.11.0.1 also corrects command help.

Install once from the Seihou repository:

```bash
seihou install https://github.com/shinzui/seihou.git --module adopt-seed-lifecycle
```

Then, from the root of the repository containing your authored modules:

```bash
seihou agent run adopt-seed-lifecycle
```

This is the normal path for old modules regardless of their version or whether
they have previously recorded a blueprint migration. Review the resulting
ownership table, source changes, version bumps, validation and unresolved
decisions. Publication is a separate action; the blueprint does not commit,
push or publish by default. Repeating it verifies existing seeds without
adding duplicate fields or bumping unchanged modules again.

For authors using recorded release migration edges, the equivalent edge is:

```bash
seihou agent migrate adopt-seed-lifecycle --from 0.10.1.0 --to 0.11.0.0
```

These numbers identify the Seihou authoring release transition, not your
module version. No version probe is declared: the installed executable's
version cannot establish which authoring conventions your sources adopted.

Preview the migration prompt without contacting a provider or changing the
project manifest:

```bash
seihou agent --debug migrate adopt-seed-lifecycle --from 0.10.1.0 --to 0.11.0.0
```

After publishing the changed producer modules, existing consumers adopt with
`seihou update TARGET`, review `release to project`, accept once and commit
`.seihou/manifest.json`. Update preserves their edits and intentional deletion.
See [the bundled reference](files/seed-lifecycle.md) and
[module authoring](../../docs/user/module-authoring.md#step-lifecycle).
