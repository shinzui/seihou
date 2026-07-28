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

  Each recorded path is resolved to an artifact on this machine and replaced
  with that artifact's portable origin. Every conversion is printed, because
  recovering an upstream URL from somebody else's absolute path is inference
  and inference belongs on screen, not hidden inside a committed file.

    Reading .seihou/manifest.json (schema version 5)

      haskell-base       /Users/shinzui/.config/seihou/installed/haskell-base
                      →  remote https://github.com/shinzui/seihou-modules.git

    ✓ Upgraded .seihou/manifest.json to schema version 6.
      Review the diff and commit it: git diff .seihou/manifest.json

  Running it on a manifest that is already current reports that there is
  nothing to do and exits zero.

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
