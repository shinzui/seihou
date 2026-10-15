# CLI context and help release audit

Use this before every release. The normal verification command is
`just audit-cli-docs`; it builds the current executable and needs neither
provider credentials nor an interactive agent. Run it again after corrections.
It detects wiring/coverage failures, not incorrect prose. A human-facing semantic
review is required as well.

## Compare guidance with the implementation

Read the last release diff, both changelogs and the current source. Do not rely
on documentation being correct merely because it shipped in a previous release.
Use `rg` to locate affected behavior. For dependency behavior, use `mori registry`
to find its source/docs before making claims; verify registry releases/upstream
tags if changing bounds or compatibility assumptions. Never search /nix/store.
Use canonical mori:// references for durable cross-repository references.

Review these surfaces together:

| Guidance | Implementation to compare |
|----------|---------------------------|
| `seihou-cli/data/module-reference.md` (shared by assist/bootstrap/setup) | `schema/`, core types/decoders/scaffolds, variable resolver, engine planner/execution |
| `data/assist-prompt.md` | `src-exe/Seihou/CLI/Assist.hs`, authoring/validation commands |
| `data/bootstrap-prompt.md` | `Bootstrap.hs`, new-module/recipe/blueprint/prompt, registry commands |
| `data/setup-prompt.md` | `Setup.hs`, run/update/sync/install/status/config workflows |
| `data/blueprint-prompt.md` | `AgentRun.hs`, blueprint execution, baseline/provenance/reference handling |
| `data/blueprint-migration-prompt.md` | `AgentMigrate.hs`, blueprint migrations, entails, receipts/not-applicable handling |
| `data/prompt-run-prompt.md` | `PromptRun.hs`, prompt renderer, command-derived vars/guidance/reference handling |
| `data/upgrade-prompt.md` | `AgentUpgrade.hs`, upgrade diagnosis, update error codes/remedies and recovery |
| `help/*.md`, `src-exe/Seihou/CLI/Help.hs` | actual command parsers/handlers, including agent config/models, effort/trace, kit and extensions |
| `docs/cli/help.md` | registered topics and top-level command coverage table |
| `seihou-cli.cabal` extra-source-files | every embedded help/context asset, including shared references |

Unless fully qualified, data/, help/ and Haskell paths in this table are under
seihou-cli/ (handlers under src-exe/Seihou/CLI/, libraries under src/Seihou/CLI/).

For each changed feature, check schema fields/defaults, accepted values, flags,
precedence, default models, actual side effects and recovery. Validate examples
against source and the current executable; do not preserve an obsolete raw Dhall
record or invent a schema hash. Prefer generated scaffolds and record completion.
Distinguish declared/schema support from implemented runtime behavior. For example,
seed declaration/receipt support does not establish create-once handoff behavior.

## Review every topic for missing or misleading workflows

Compare the full command tree in Commands.hs with the coverage table in
`docs/cli/help.md`. Every top-level command needs an appropriate conceptual topic;
separate topics are not required for every flag/subcommand. Add a topic when a
new workflow would otherwise be hard to discover. Check nested subcommands against
their group's topic too. Register new topics in Help.hs, document the index and
coverage table, and package their Markdown in the Cabal source distribution.

Read **all** help topics and all seven task templates, plus the shared module
reference. Pay particular attention to inherited omissions and contradictions:

- module/recipe/blueprint/prompt distinctions and their actual launch commands;
- supported variable types, saved inputs and separate agent configuration precedence;
- launch declarations, per-command keys, effort, trace and pinned CLI defaults;
- normal `update TARGET` owning source/dependency fetch, migrations and recorded
  inputs, rather than requiring install/upgrade/migrate preparation;
- manifest schema steps, origin repair and fetched recorded-release certification;
- managed versus seed versus checkout behavior, sync in fresh clones/worktrees,
  automatic tracked-link adoption in update's preview, and protected local edits;
- migration gaps/overlaps, inference/probes, entails and receipt outcomes;
- CLI sessions with tools versus one-shot API responses; debug skips providers
  but may execute declared context commands/probes or save an upgrade brief.

## Exercise and retain evidence

`just audit-cli-docs` checks every registered topic and top-level command help,
source-distribution entries, and eight debug renders: assist, bootstrap (single
and repository), setup, blueprint run, blueprint migrate, prompt run and upgrade.
It also validates the shared module/checkout/removal examples through
`validate-module`. The artifact renders use explicit temporary local-schema fixtures with isolated
XDG directories. They contact no provider. This proves embedding/rendering, not
that an arbitrary consumer or published dependency works.

To retain readable evidence outside the checkout, build and run:

```bash
cabal build exe:seihou
python3 scripts/audit-cli-docs.py \
  --executable "$(cabal list-bin exe:seihou)" \
  --report-dir /tmp/seihou-release-context-audit
```

Inspect the output for the features being released, beyond the script's checks.
For changed authoring instructions, evaluate the example against the current
schema and run validate/preview through the ordinary commands. For changed
consumer workflows, exercise a representative real consumer from its actual
pre-change state, counting every prerequisite; include empty caches, older
supported manifests and fresh clones/worktrees where relevant. Do not hide
manual repairs in fixture preparation or substitute debug rendering for adoption.

Inspect `cabal sdist` output for new assets; embedded files must reach the tarball
and rebuild correctly. Record source executable/version, checks and any limits
in the release summary. After publishing, distinguish that build from the
published version and the user's installed binary. Do not claim source edits are
already available through an unchanged installed release.
