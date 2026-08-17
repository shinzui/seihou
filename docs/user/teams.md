# Sharing a Seihou Project Across a Team

Seihou records what it generated into `.seihou/manifest.json` inside your
project. That file describes the project, not the machine that ran the command,
so it belongs in git alongside the code it describes. This guide covers what a
team commits, what each developer needs installed, and what happens when
somebody is out of date.

## What to commit

| Path | Commit it? | Why |
|------|-----------|-----|
| `.seihou/manifest.json` | **Yes** | It records which modules were applied, at which versions and from which repositories, and which files each one generated. It is what makes the next run incremental, and it is what tells a reviewer which module version produced a generated file. |
| `.seihou/baselines/` | **Yes** | Content-addressed copies of exactly what seihou generated, keyed by SHA-256. They are what lets seihou three-way merge your edits against a new version instead of clobbering them. A manifest that references a baseline whose bytes are not in the repository is not reproducible in another checkout, so the two travel together — `seihou update --commit` stages them together for the same reason. |
| `.seihou/modules/` | **Yes**, if you use it | Project-local modules. The manifest records them as a path relative to the project root, so they must be present in every clone or the artifact cannot be resolved. |
| `.seihou/manifest.json.tmp` | No | A transient file that exists only during an atomic manifest write. It should never survive a completed command, but ignore it so an interrupted run cannot be committed by accident. |

A `.gitignore` covering the last row:

```gitignore
.seihou/*.tmp
```

Nothing else under `.seihou/` needs excluding. Nothing seihou writes there
depends on the machine that wrote it.

One thing to expect in review: **every `seihou run` rewrites the manifest even
when nothing changed**, because each run stamps a fresh `generatedAt` and
`appliedAt`. A diff limited to those timestamp fields means the run was a no-op.

## What each developer needs

Each developer needs the modules the manifest records, installed locally at the
recorded version or newer. Seihou never fetches them on their behalf during a
run — it tells them what to install.

`seihou status` is how to find out where you stand. It never fails on a
verdict, so it is safe to run first:

```text
$ seihou status
Seihou Status:

Applied modules:
  demo  v2.0.0    (applied 2026-07-28)

Tracked files: 1
  README.md   demo   unchanged

Variables: 1 resolved

Artifacts that differ from what this project records:
  demo: this project expects 2.0.0 but 1.0.0 is installed here (run 'seihou upgrade demo')
```

The remedies:

```sh
seihou install https://github.com/your-org/your-modules.git   # not installed at all
seihou upgrade demo                                            # installed, but out of date
```

## What happens when someone is out of date

Before they plan or write anything, `seihou run`, `seihou migrate`,
`seihou agent run`, and `seihou agent migrate` compare the version the manifest
records for each artifact they are about to use against the copy installed on
your machine. If yours is older, the command stops without touching a file:

```text
✗ Refusing to run: your local copy of 'demo' is older than the
  version this project expects.

  Recorded in .seihou/manifest.json:  2.0.0
  Installed on this machine:          1.0.0
  Origin: /tmp/seihou-teams/demo-modules

  Update your local copy first:
    seihou upgrade demo

To proceed anyway — pinning this project to what is installed here —
re-run with --allow-downgrade.
```

Reading it:

- **Recorded** is what the project says it was generated from. It came from the
  committed manifest, so it is the team's shared answer.
- **Installed on this machine** is what you have. It is per-machine state and
  carries no authority over the project.
- **Origin** is the repository the manifest records the module coming from —
  the same string every developer sees, which is what makes it useful in a
  review.

This is the failure the guide exists to prevent. Without the refusal, your run
would regenerate every file from the older module and rewrite the manifest to
say so. The project would silently revert, and the revert would look like an
ordinary diff in code review.

The refusal costs you nothing: it happens before the plan is computed, so your
working tree is byte-identical afterwards.

`seihou update` reaches the same outcome by a different route — it refuses a
candidate older than the recorded version as a `candidate_downgrade` rather
than through this message — so a backwards move is refused there too.

### When `--allow-downgrade` is right

Pass `--allow-downgrade` to `run`, `migrate`, `update`, `agent run`, or
`agent migrate` when pinning the
project back is what you actually mean: reverting a module upgrade that broke
something, or reproducing an old state to debug it. The command proceeds and
still prints what it is overriding, under a `! Proceeding anyway` heading —
a deliberate downgrade should be visible in the terminal and in the diff.

It is not the right answer to "I do not want to run `seihou upgrade` right
now". Using it there commits a manifest saying the project is on the older
version, and the next developer inherits that as the shared truth.

## What an origin mismatch means

Two different modules can share a name. If a module with the recorded name is
installed from a different repository than the manifest records, it is a
different module, and seihou says so instead of generating from it:

```text
✗ Refusing to run: 'demo' is installed from a different source
  than this project records.

  Recorded in .seihou/manifest.json:  https://github.com/your-org/your-modules.git
  Installed on this machine:          https://github.com/someone-else/modules.git

  These are different artifacts that happen to share a name.
  Install the one this project records:
    seihou install https://github.com/your-org/your-modules.git
```

The fix is in the message: install from the URL the manifest records.

A module you keep in your personal `~/.config/seihou/modules/` has no recorded
upstream, so seihou cannot confirm or refute its identity. It reports that
honestly — "no recorded provenance, so its identity cannot be verified" — and
does not block, because a developer who deliberately shadows a module should
not be told they have the wrong one.

## Adopting seihou in an existing project

If the project's manifest predates schema version 6, every command refuses to
read it, because its only record of each module's source is another developer's
absolute path:

```text
[error] Error reading manifest: this manifest uses schema version 5, which
records machine-specific absolute paths; run 'seihou manifest upgrade' to
convert it
```

Run `seihou manifest upgrade` once, review the printed conversions, and commit
the result. See [Upgrading an Older Manifest](manifest-upgrade.md) for the full
procedure, including what to do when the report says an artifact's upstream
could not be recovered.

## A worked two-developer walkthrough

This is the whole workflow in one sitting. It runs entirely on your machine —
nothing is fetched from the network, and `XDG_CONFIG_HOME` stands in for two
developers' seihou configuration roots so you can play both parts. Ana and Ben
share one checkout, which is what a git clone amounts to here.

Set up a module repository and a project:

```sh
mkdir -p /tmp/seihou-teams/demo-modules/files /tmp/seihou-teams/ana \
         /tmp/seihou-teams/ben /tmp/seihou-teams/project
cd /tmp/seihou-teams/demo-modules

# Publishing a version of the module is going to happen twice, so make it a
# function. It writes the module definition and the template it generates from.
write_demo() {
  cat > module.dhall <<EOF
{ name = "demo"
, version = Some "$1"
, description = None Text
, vars = [{ name = "project.name", type = "text", default = Some "shared", description = None Text, required = False, validation = None Text }]
, exports = [] : List { var : Text, alias : Optional Text }
, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }
, steps = [{ strategy = "template", src = "README.tmpl", dest = "README.md", when = None Text, patch = None Text }]
, commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }
, dependencies = [] : List Text
, removal = None { steps : List { action : Text, dest : Text, src : Optional Text }, commands : List { run : Text, workDir : Optional Text, when : Optional Text } }
}
EOF
  printf '# {{project.name}}\n\ngenerated by demo %s\n' "$1" > files/README.tmpl
}

write_demo 1.0.0
git init -q && git add -A && git commit -qm "demo 1.0.0"
```

Both developers install version 1.0.0:

```sh
XDG_CONFIG_HOME=/tmp/seihou-teams/ana seihou install /tmp/seihou-teams/demo-modules --name demo
XDG_CONFIG_HOME=/tmp/seihou-teams/ben seihou install /tmp/seihou-teams/demo-modules --name demo
```

Ana scaffolds the project and commits:

```sh
cd /tmp/seihou-teams/project && git init -q
XDG_CONFIG_HOME=/tmp/seihou-teams/ana seihou run demo
git add -A && git commit -qm "feat: scaffold with demo 1.0.0"
```

Look at what she committed. The module's origin is a URL and an artifact name,
not a directory on Ana's laptop:

```json
"origin": {"artifact": "demo", "kind": "remote", "url": "/tmp/seihou-teams/demo-modules"}
```

The module publishes 2.0.0:

```sh
cd /tmp/seihou-teams/demo-modules
write_demo 2.0.0
git add -A && git commit -qm "demo 2.0.0"
```

Ana upgrades her copy and reconciles the project. `seihou upgrade` refreshes the
installed module; `seihou update` is what carries the project forward to it,
including any migrations the module declares:

```sh
cd /tmp/seihou-teams/project
XDG_CONFIG_HOME=/tmp/seihou-teams/ana seihou upgrade demo
XDG_CONFIG_HOME=/tmp/seihou-teams/ana seihou update demo    # asks for confirmation
git add -A && git commit -qm "chore: update demo to 2.0.0"
```

Ben pulls that commit. He still has 1.0.0, and seihou stops him:

```text
$ XDG_CONFIG_HOME=/tmp/seihou-teams/ben seihou run demo
✗ Refusing to run: your local copy of 'demo' is older than the
  version this project expects.

  Recorded in .seihou/manifest.json:  2.0.0
  Installed on this machine:          1.0.0
  Origin: /tmp/seihou-teams/demo-modules

  Update your local copy first:
    seihou upgrade demo

To proceed anyway — pinning this project to what is installed here —
re-run with --allow-downgrade.

$ git status --porcelain
$
```

The empty `git status` is the point: Ben's checkout is untouched. Without the
refusal, `README.md` would now say `generated by demo 1.0.0` again and the
manifest would agree with it.

Ben does what the message says, and the ordinary run succeeds:

```sh
XDG_CONFIG_HOME=/tmp/seihou-teams/ben seihou upgrade demo
XDG_CONFIG_HOME=/tmp/seihou-teams/ben seihou run demo
```

`README.md` still reads `generated by demo 2.0.0` — regenerating from the same
version with the same inputs changes nothing, and the only path git reports is
the manifest's refreshed timestamps.

Clean up:

```sh
rm -rf /tmp/seihou-teams
```

## Related reading

- [Upgrading an Older Manifest](manifest-upgrade.md) — converting a
  `.seihou/manifest.json` written before schema version 6.
- [Migrations](migrations.md) — moving a project across module versions, and
  the mechanics behind the refusal above.
- [`seihou update` reference](../cli/update.md) — merge choices, JSON
  automation, and recovery.
- `seihou help manifest` — what the manifest may and may not contain.
