# seihou manifest

Operations on a project's `.seihou/manifest.json`.

## Usage

```
seihou manifest COMMAND [OPTIONS]
```

## Subcommands

| Command | Description |
|---------|-------------|
| `upgrade` | Convert a manifest written by an older seihou to the portable format |

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

Convert a manifest written before schema version 6 into the portable format.

### Usage

```
seihou manifest upgrade [OPTIONS]
```

### Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Print every conversion but leave the manifest untouched. |
| `--force` | Write even when a converted artifact is missing or stale on this machine. |

### Description

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

  haskell-base       /Users/shinzui/.config/seihou/installed/haskell-base
                  →  remote https://github.com/shinzui/seihou-modules.git

  project-lint       /Users/shinzui/work/myproject/.seihou/modules/project-lint
                  →  project .seihou/modules/project-lint

  scratch-helper     /Users/other/.config/seihou/modules/scratch-helper
                  →  local scratch-helper  (no upstream recorded)

✓ Upgraded .seihou/manifest.json to schema version 6.
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

Running the command on a manifest that is already at the current schema version
reports that there is nothing to do and exits zero.

### Refusing an upgrade this machine cannot satisfy

The conversion can only record what this machine can see. An artifact that is
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

Install what it names with `seihou install <url>`, or refresh an out-of-date
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
