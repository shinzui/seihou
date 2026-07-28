# Upgrading an Older Manifest

Every project seihou generates into carries a `.seihou/manifest.json`. It
records which files seihou wrote, which module wrote each one, and which
version of that module was applied. It is what makes later runs incremental,
and because it describes the project rather than the machine, teams commit it
to git alongside the code it describes.

Manifests written by seihou before schema version 6 recorded one thing that was
never true of the project: the absolute directory each module happened to
occupy on the machine that ran the command, like
`/Users/shinzui/.config/seihou/installed/haskell-base`. That path means nothing
in anybody else's clone. Seihou no longer reads those manifests, because
guessing at what such a path meant is exactly the kind of silent substitution
the manifest exists to prevent.

If you have one, every command tells you so and names the fix:

```text
[error] Error reading manifest: this manifest uses schema version 5, which
records machine-specific absolute paths; run 'seihou manifest upgrade' to
convert it
```

## Converting it

Run this from the project root:

```sh
seihou manifest upgrade
```

Seihou reads each recorded path, works out which artifact it referred to, and
replaces it with a portable *origin* — the git URL the artifact was installed
from, or a path relative to the project root for a module that lives inside the
project at `.seihou/modules/<name>`. Every conversion is printed, because
recovering a URL from somebody else's absolute path takes inference and
inference that happens silently in a committed file is worth nothing:

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

Read that report before committing. The three arrows mean three different
levels of confidence:

| Result | What it means |
|--------|---------------|
| `remote <url>` | Seihou found the artifact installed on this machine and read the upstream URL from its install metadata. This is the strongest result: the manifest now names the repository the module actually comes from. |
| `project <path>` | The artifact lives inside the project, so the path is meaningful in every clone. No inference was involved. |
| `local <name>  (no upstream recorded)` | Seihou could not establish where the artifact came from, and recorded only its name. Commands can still find it by name, but nothing can verify it is the right one. |

Pass `--dry-run` to see the same report and write nothing:

```sh
seihou manifest upgrade --dry-run
```

Running the command on a manifest that is already current reports that there is
nothing to do and exits zero, so it is safe to run twice or to put in a script.

## Install your modules first

The upgrade is only as good as what this machine can see. If a module the
manifest records is not installed here, seihou has no way to recover its URL
and would write `local <name>` into a file you are about to commit — losing the
upstream for everyone. So the upgrade refuses:

```text
✗ Refusing to write .seihou/manifest.json.

  haskell-base: recorded in the manifest but not installed on this machine

Upgrading now would record what this machine can see rather than what
the project uses: an artifact that is missing or stale here converts to
an origin seihou had to guess at, and that guess would be committed.

Install or upgrade the artifacts above and run this again, or re-run
with --force to accept the conversions exactly as shown.
```

Install what it names — `seihou install <url>`, or `seihou upgrade <name>` for
a copy that is merely out of date — and run the upgrade again. The same refusal
appears if your copy of a module is older than the version the manifest
records, for the reason described in
[Migrations](migrations.md#refusing-to-go-backwards).

Use `--force` when you genuinely mean "record what I have here": for instance,
converting a manifest for a project whose modules you deliberately do not keep
installed. The report is printed either way, so a forced upgrade is just as
reviewable.

## Recovering

The upgrade rewrites a file that is checked into git, which is also how you undo
it:

```sh
git checkout -- .seihou/manifest.json
```

The write itself is atomic — seihou writes a complete temporary file and renames
it over the manifest — so an interrupted run cannot leave a truncated one.

## After the upgrade

Once the manifest is at schema version 6, every command reads it again, and it
means the same thing on every machine. Two developers who apply the same module
now produce the same bytes, so a manifest diff in code review shows a real
change rather than a change of laptop.

Commit the upgraded manifest in its own commit if you can — it touches every
recorded artifact at once, and a reviewer can check it against this page rather
than untangling it from a feature change.
