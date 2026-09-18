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

The command walks one schema version at a time, so the report lists each step
it ran. `seihou manifest upgrade --to 6` stops after the path conversion, if you
want to review that on its own before going further.

## Shared files and targeted updates

Schema 7 also records, for every file two applications share, whether both of
them only append to it. That is what lets `seihou update nix-haskell-flake`
update one owner of `.gitignore` without also updating every other module that
adds a line to it. A manifest upgraded from schema 6 starts with that answer
`unknown` for most shared files, so the upgrade works it out: it compiles each
owner at the exact version the manifest records and looks at how it writes the
file, without writing anything but the manifest. The report shows the result:

```text
  shared-write evidence
  .gitignore  unknown -> additive-only
  flake.nix   unknown (unchanged)
                haskell-base: module haskell-base 1.4.0 is not installed here; no commit of
                https://github.com/shinzui/seihou-modules.git declares haskell-base 1.4.0 (searched 6 revisions)
```

You do not need every owner's recorded version installed. When the installed
copy is a different version, seihou reads the recorded release from the
owner's recorded remote: it finds the commit at which the module declared that
version and uses it, in a temporary directory that is deleted afterwards. The
report adds a line such as
`(nix-haskell-flake 0.13.2 read from https://github.com/shinzui/seihou-modules.git at ec6435e)`
for each release read this way. A file stays `unknown` only when neither an
installed copy nor the remote has the recorded version, as for `flake.nix`
above. Install that version, or make its remote reachable, and run the command
again.

You do not have to run the upgrade before a targeted update. `seihou update
nix-haskell-flake` does the same work for just the shared files that update
touches, records the answer (and the step to schema 7) together with the
update itself, and inspects the other owners without updating any of their
files. It fetches a missing recorded release the same way. If the release
cannot be found there either, the update stops with
`shared_write_evidence_unavailable` and names it, rather than updating
anything it cannot vouch for. The upgrade command is how you settle every
shared file in the project at once, and review the result first.

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

## Origins recorded as a path

A manifest at the current schema can still name a directory on one machine.
Before seihou recorded a local checkout's published remote, `seihou install
~/src/seihou-modules` stored the checkout's path, and the path reached the
manifest as the artifact's origin. It fails the same way the old absolute paths
did, just later. Once the artifact is reinstalled from its real remote, commands
report that it is "installed here from a different origin than recorded", and
the message names the fix:

```sh
seihou manifest repair-origins --dry-run   # show the proposed rewrites
seihou manifest repair-origins             # write them
```

For each recorded path, the command proposes a remote. It uses the path's own
`origin` remote when the checkout is still here, or the remote the installed
copy records. It prints the evidence and rewrites every record under that path
to the same URL:

```text
/Users/alice/Keikaku/bokuno/seihou-modules
  -> https://github.com/shinzui/seihou-modules.git
     evidence: the installed copy of nix-haskell-flake records this remote
     records: modules[nix-haskell-flake], applications[nix-haskell-flake], 2 application instances
```

When nothing on this machine points at a remote, supply it:
`seihou manifest repair-origins --set nix-haskell-flake=https://github.com/shinzui/seihou-modules.git`.
The command needs schema 7, so run `seihou manifest upgrade` first on an older
manifest. See the [command reference](../cli/manifest.md#seihou-manifest-repair-origins)
for the evidence rules and exit codes.

## When you are not sure which repair applies

`seihou agent upgrade <module> --check` reports every manifest-state problem between
your project and a clean `seihou update <module>`: the schema, unknown shared-write
modes, origins recorded as paths, the installed copy, and a dry run of the update. It
changes nothing. `seihou agent upgrade <module>` hands the same findings, with a repair
playbook that uses the commands on this page, to an agent that performs the repairs and
the upgrade. See [Agent assistance](agent-assistance.md#upgrade).

## After the upgrade

Once the manifest is at schema version 6 or later, every command reads it again, and it
means the same thing on every machine. Two developers who apply the same module
now produce the same bytes, so a manifest diff in code review shows a real
change rather than a change of laptop.

Commit the upgraded manifest in its own commit if you can — it touches every
recorded artifact at once, and a reviewer can check it against this page rather
than untangling it from a feature change.
