# seihou sync

Reproduce the module-declared local setup recorded in this checkout's manifest.

```sh
seihou sync [--dry-run] [--json]
```

Run at the Git working-tree root after cloning or receiving project changes.
No installed producer modules or personal configuration are needed. Sync reads the
accepted manifest, restores its ignored directory links, then executes its ordered
repeatable checkout commands. It never fetches producers, upgrades modules,
regenerates managed files, runs migrations, or rewrites the manifest, baselines or
Git index. A producer's shell command may itself use external tools or the network
and runs with your environment and permissions. Review the project's declarations
before explicitly running sync; Seihou installs no automatic hook.

`--dry-run` shows the recorded links and commands without executing commands or
changing anything. `--json` emits one structured document, capturing command output
inside command results. Default output names created, repaired and unchanged links,
and succeeded, failed and not-run commands with application and instance identity.
A refusal or command failure exits nonzero.

A module records checkout commands with `S.Command.Action.Checkout`, and ordinary
application commands with `S.Command.Action.Apply`. Sync runs only the checkout
subset, in recorded dependency/declaration order. Independent applications run in
application-ID order. Repeated sync runs every recorded checkout command again;
success receipts never suppress them. Authors must make these commands repeatable
and keep intended writes outside managed/tracked project state. Seihou cannot
sandbox or undo arbitrary shell effects.

All links and command working directories are checked before changes. Sources and
working directories must already be real project directories with real ancestors.
A regular object collision refuses the whole setup without overwriting it. Link
sources cannot be supplied by a later checkout command. A command's working
directory is checked again immediately before invocation. The first command failure
stops execution; the report retains the completed prefix, captured output, exit code
when available, and unrun tail. Local effects remain. Correct the failure and run
`seihou sync` again to repeat the complete local command phase.

An interrupted update blocks sync, including dry-run. Run `seihou update --dry-run`:
its entry path recovers the interrupted transaction's files and index before
previewing a new update. Then retry sync.

## First-time adoption

An empty declaration set is successful zero work: it means no checkout setup has
been recorded. Sync does not infer setup from command receipts or discover a newer
producer. A maintainer adopts a changed specification through the recorded root:

```sh
seihou update master-plan
```

Review and accept the ordinary preview, then commit generated assets, ignore rules,
baselines and manifest. Update resolves the recorded source and dependencies, reuses
saved inputs, prepares supported older schemas and previews eligible tracked-link
adoption. Teammates receive that commit and run `seihou sync`. `--no-commands` on
run/update suppresses execution while retaining setup declarations for teammates.
An unchanged update executes no commands; use sync to repeat local setup.

Schema 10 records checkout commands; schema 9 links and older supported manifests
remain readable without a schema write during sync. Old runtimes reject schema 10.
Ordinary historical command receipts remain application history and are never
converted into repeatable setup instructions. Updating declarations replaces their
recorded setup; removal stops future execution without inventing inverse commands.
