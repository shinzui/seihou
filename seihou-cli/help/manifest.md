MANIFEST

Every project seihou generates into carries a .seihou/manifest.json recording
which files were written, which module wrote each one, and which version was
applied. It describes the project rather than the machine, so it is committed
to git alongside the code it describes.

WHAT IT MAY NOT CONTAIN

  No absolute path, home directory, XDG root, or username. Every location the
  manifest names is either relative to the project root or expressed as an
  artifact origin:

    remote    a git URL plus the artifact's name — a module installed from
              somewhere, e.g. https://github.com/user/seihou-modules.git
    project   a path relative to the project root, for an artifact that lives
              inside the project at .seihou/modules/<name>
    local     only a name, for an artifact discovered in your personal
              ~/.config/seihou/modules/ with no recorded upstream

  A "local" origin is deliberately weak. Commands can still find the artifact
  by name, but nothing can verify it is the one the project was generated
  from, and seihou says so rather than pretending otherwise.

OLDER MANIFESTS

  Manifests written before schema version 6 recorded the absolute directory
  each module occupied on the machine that ran the command. That path means
  nothing in another clone, so seihou refuses to read such a manifest instead
  of guessing:

    [error] Error reading manifest: this manifest uses schema version 5, which
    records machine-specific absolute paths; run 'seihou manifest upgrade' to
    convert it

  Convert it from the project root:

    seihou manifest upgrade
    seihou manifest upgrade --dry-run    # show the report, write nothing
    seihou manifest upgrade --to 6       # stop after a given schema version

  The command runs one schema step at a time and prints each one. Only the
  5 -> 6 step infers anything; the others are mechanical.

  Each recorded path is resolved to an artifact on this machine and replaced
  with that artifact's portable origin. Every conversion is printed, because
  recovering an upstream URL from somebody else's absolute path is inference
  and inference belongs on screen, not hidden inside a committed file.

    Reading .seihou/manifest.json (schema version 5)

      5 -> 6  portable artifact origins  (inferred; review before committing)

      haskell-base       /Users/shinzui/.config/seihou/installed/haskell-base
                      →  remote https://github.com/shinzui/seihou-modules.git

      6 -> 7  explicit shared-write evidence

      shared-write evidence
      .gitignore  unknown -> additive-only

    ✓ Upgraded .seihou/manifest.json to schema version 7.
      Review the diff and commit it: git diff .seihou/manifest.json

  Running it on a manifest that is already current reports that there is
  nothing to do and exits zero.

SHARED-WRITE EVIDENCE

  Schema 7 records, for every file, whether all of its owners only append to
  it (additive-only), whether one rewrites it (requires-ownership-closure), or
  that nobody has established either yet (unknown). A targeted
  seihou update can leave a co-owner out only for an additive-only file.

  After reaching schema 7 the upgrade compiles each unknown file's owners from
  their recorded module versions and saved values, writes nothing but the
  manifest, and records what it finds. An owner whose recorded version is not
  installed here leaves the file unknown, and the report names it.

  seihou update <target> performs the same certification for just the shared
  paths it touches and records it with the update, so running this first is
  optional. It inspects co-owners; it never updates their files.

ORIGINS RECORDED AS A PATH

  Installing from a local checkout used to record the checkout's path as the
  artifact's origin, and the path reached the manifest. Current seihou records
  the checkout's published remote instead, or an unknown (local) origin when
  the installed commit is not pushed. Repair a manifest that still names a
  path:

    seihou manifest repair-origins --dry-run    # proposed rewrites + evidence
    seihou manifest repair-origins              # write them
    seihou manifest repair-origins --set NAME=URL   # when seihou finds no remote

  Evidence comes from the path's own 'origin' remote, if the checkout is here,
  and from the installed copy of each artifact recorded under the path. Every
  record under one path is rewritten to the same URL. The command exits 1 while
  any path is unresolved or conflicting.

INSTALL FIRST

  The upgrade can only record what this machine can see. If an artifact the
  manifest names is missing here — or the copy here is older than the version
  recorded — the conversion would have to guess, so the command refuses and
  names what to install or upgrade first.

    seihou install <url>       # for one that is not here at all
    seihou upgrade <name>      # for one that is merely out of date

  Pass --force to write anyway, when recording what this machine has is what
  you actually mean.

RECOVERING

  The upgrade rewrites a file that is in git, which is how you undo it:

    git checkout -- .seihou/manifest.json

  The write is atomic: a complete temporary file is renamed over the manifest,
  so an interrupted run cannot leave a truncated one.

SEE ALSO

  seihou help migrations       moving a project between module versions
  seihou manifest upgrade -h   the full flag reference
  seihou manifest repair-origins -h
