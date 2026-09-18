# seihou manifest

Operations on a project's `.seihou/manifest.json`.

## Usage

```
seihou manifest COMMAND [OPTIONS]
```

## Subcommands

| Command | Description |
|---------|-------------|
| `upgrade` | Upgrade a manifest written by an older seihou, one schema step at a time |

The `manifest` group is designed to extend. Future subcommands (inspection,
repair) will live on this page.

## Description

The manifest records what seihou generated into a project: which files it
wrote, which module wrote each one, and which version was applied. It describes
the project rather than the machine, so it is committed to git alongside the
code it describes and must contain nothing whose meaning depends on the machine
that wrote it — no absolute path, home directory, XDG root, or username.

Run these commands from the project root, the directory holding `.seihou/`.

---

## seihou manifest upgrade

Upgrade a manifest written by an older seihou through each schema version in
turn, and record the shared-write evidence the current schema can express.

### Usage

```
seihou manifest upgrade [OPTIONS]
```

### Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Print every step and conversion but leave the manifest untouched. |
| `--force` | Accept inferred origins even when a converted artifact is missing or stale on this machine. Only the schema 5 to 6 step consults it. |
| `--to VERSION` | Stop at this schema version instead of the current one (7). |

### Description

Every change to what the manifest can say advances its schema version and adds
exactly one upgrade step from the previous version. The command runs those
steps in order, one at a time, and prints each one:

| Step | What it does | Kind |
|------|--------------|------|
| 1 -> 2 through 4 -> 5 | Only the version changes; the fields those schemas added were optional. | lossless |
| 5 -> 6 | Replaces machine-local artifact paths with portable origins (below). | inferred; reviewable |
| 6 -> 7 | Gives every file record an explicit `sharedWriteMode`: an old `additiveOnly: true` becomes `additive-only`, anything else `unknown`. | lossless |

`--to VERSION` stops after the step that reaches that version. A version newer
than this build, or older than the manifest, is refused. The document's
`version` always names the last step that actually ran.

#### Schema 5 to 6: portable origins

Manifests before schema version 6 recorded, for each applied module and each
module instance inside an application, the absolute directory that module
occupied on the machine that ran the command — entries like
`/Users/shinzui/.config/seihou/installed/haskell-base`. That path is meaningless
in any other clone, so seihou refuses to read such a manifest rather than
guessing at what it meant:

```text
[error] Error reading manifest: this manifest uses schema version 5, which
records machine-specific absolute paths; run 'seihou manifest upgrade' to
convert it
```

This command reads each recorded path, works out which artifact it referred to,
and replaces it with that artifact's portable **origin**. Three kinds of origin
exist, and the printed report names which one each conversion produced:

| Result | How it was reached |
|--------|--------------------|
| `remote <url>` | The artifact was found in this machine's search paths and its `.seihou-origin.json` gave the git URL it was installed from. |
| `project <path>` | The recorded path ends in `.seihou/modules/<name>`, so the artifact lives inside the project and the path means the same thing in every clone. No lookup was needed. |
| `local <name>` | Nothing matched, or what matched carries no provenance. Only the name is recorded, and nothing can verify the copy found later is the right one. |

Every conversion is printed because recovering an upstream URL from another
developer's absolute path is inference, and inference that happens silently
inside a committed file is worth nothing:

```text
Reading .seihou/manifest.json (schema version 5)

  5 -> 6  portable artifact origins  (inferred; review before committing)

  haskell-base       /Users/shinzui/.config/seihou/installed/haskell-base
                  →  remote https://github.com/shinzui/seihou-modules.git

  project-lint       /Users/shinzui/work/myproject/.seihou/modules/project-lint
                  →  project .seihou/modules/project-lint

  scratch-helper     /Users/other/.config/seihou/modules/scratch-helper
                  →  local scratch-helper  (no upstream recorded)

  6 -> 7  explicit shared-write evidence

  shared-write evidence
  .gitignore  unknown -> additive-only

✓ Upgraded .seihou/manifest.json to schema version 7.
  Review the diff and commit it: git diff .seihou/manifest.json
```

Fields the upgrade does not convert — resolved variables, file records,
baseline references, command receipts, blueprint migration receipts — survive
untouched. The converted document is decoded with the ordinary manifest decoder
before anything is written, so a conversion that would produce an unreadable
manifest fails without touching the file.

The records written by the agent path and by recipe application — the
`blueprint` entry, each entry in `blueprintMigrations`, and the `recipe` entry —
carry an `origin` of their own, in the same three-way shape as a module's. The
upgrade does not fill it and cannot: a manifest old enough to need converting
never recorded where those artifacts came from, and nothing on this machine can
say retroactively. They read as `local <name>` — the artifact is known by name
only, and its provenance cannot be verified — until the next `seihou agent run`,
`seihou agent migrate`, or recipe application records a real one. See
[Blueprint Migrations](../user/blueprint-migrations.md#which-edge-a-receipt-is-for)
for why a migration receipt's origin is part of which edge it stands for.

#### Shared-write evidence

When two applications own the same file, `seihou update <target>` normally has
to update both, because regenerating the file for one would discard the other's
content. The exception is a file every owner only appends to — the usual case
for `.gitignore` — which is recorded as `additive-only`. A schema-6 manifest
could only say `additiveOnly: true`, so after the 6 -> 7 step most shared paths
read `unknown`, and an unknown path keeps the full ownership rule.

Once the manifest is at schema 7 the command works the answer out. For each
path whose mode is `unknown` it compiles every owner's recorded module
instances — the exact recorded version, parent variables, and saved values —
and inspects the operations without writing anything or running any command.
If every owner only appends, the path becomes `additive-only`; if any owner
writes the whole file, it becomes `requires-ownership-closure` (one such owner
is proof enough on its own). Otherwise, if an owner's recorded module version is
not installed here, or it no longer writes the path, the path stays `unknown` and
the report says why:

```text
  shared-write evidence
  flake.nix  unknown (unchanged)
               haskell-base: module haskell-base 1.4.0 is not installed here
```

Install the named version (`seihou install`, `seihou upgrade`) and run the
command again to fill it in. Nothing turns `unknown` into `additive-only`
without evidence from every owner, and a known answer is never revisited.

A targeted `seihou update` performs the same certification on its own, for the
shared paths it touches, and publishes the result with the update (see
[`seihou update`](update.md)). Running this command first is optional; it settles
every path at once and lets you review the result before any update.

Running the command on a manifest that is already current reports that there
is nothing to do, lists any path that is still `unknown` with its reason, and
exits zero.

### Refusing an upgrade this machine cannot satisfy

The path conversion can only record what this machine can see. An artifact that is
not installed here converts to `local <name>` — a guess that would be committed
and would lose the upstream for everyone who later reads the manifest. So
before writing, seihou checks the converted manifest against what is installed
and refuses if anything is missing or older than the version recorded:

```text
✗ Refusing to write .seihou/manifest.json.

  haskell-base: recorded in the manifest but not installed on this machine

Upgrading now would record what this machine can see rather than what
the project uses: an artifact that is missing or stale here converts to
an origin seihou had to guess at, and that guess would be committed.

Install or upgrade the artifacts above and run this again, or re-run
with --force to accept the conversions exactly as shown.
```

A refused conversion stops the upgrade there: no later step runs and the file
is not touched. Install what it names with `seihou install <url>`, or refresh an out-of-date
copy with `seihou upgrade <name>`, and run the upgrade again. `--dry-run`
prints the same refusal as a warning but still exits 0, because a preview
writes nothing.

Use `--force` when recording what this machine has is what you actually mean —
for instance, converting a manifest for a project whose modules you
deliberately do not keep installed.

### Recovery

The command rewrites a file that is checked into git, which is how you undo it:

```sh
git checkout -- .seihou/manifest.json
```

The write is atomic: a complete temporary file is renamed over the manifest, so
an interrupted run cannot leave a truncated one.

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | The manifest was upgraded, was already current, or `--dry-run` completed. |
| 1 | No manifest here, the manifest could not be read, or the write was refused. |

### Examples

```sh
# See what would change
seihou manifest upgrade --dry-run

# Convert the machine-local paths only, and stop at schema 6
seihou manifest upgrade --to 6

# Convert and commit
seihou manifest upgrade
git add .seihou/manifest.json && git commit -m "chore: upgrade seihou manifest"

# Convert on a machine that deliberately lacks some artifacts
seihou manifest upgrade --force
```

## See also

- [Upgrading an Older Manifest](../user/manifest-upgrade.md) — the user guide.
- [Migrations](../user/migrations.md) — moving a project across module versions,
  and why seihou refuses to go backwards.
- `seihou help manifest` — the same material in the built-in help.
