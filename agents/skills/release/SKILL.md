---
name: release
description: Cut a release of the seihou packages and publish them to Hackage following the Haskell PVP. Updates cabal versions, internal dependency bounds, and the changelog; runs the format/build/test/check gates; commits, tags, pushes; uploads to Hackage in dependency order (seihou-core, then seihou-cli and seihou-okf-extension); and creates the GitHub release.
argument-hint: "[major|minor|patch]"
disable-model-invocation: true
allowed-tools: Read, Bash, Edit, Glob, Grep, Write, AskUserQuestion
---

# Release (Hackage)

Cut a release of this repository's Haskell packages and publish them to
[Hackage](https://hackage.haskell.org/) following the Haskell **PVP**
(`A.B.C.D`).

**Project:** seihou — composable, type-safe project scaffolding.

This is a multi-package release. All three packages are published to Hackage
and **share a single version number**, in lockstep, in dependency order.

## Packages

Published to Hackage, **in dependency order** (publish dependencies first):

1. **`seihou-core`** — `seihou-core/` — core library. No intra-repo
   dependencies; **publish this first**.
2. **`seihou-cli`** — `seihou-cli/` — the `seihou` CLI. Ships a private
   internal sublibrary (`seihou-cli-internal`), the `seihou` executable, and
   a test suite. **Depends on `seihou-core`**; publish after `seihou-core` is
   live on Hackage.
3. **`seihou-okf-extension`** — `seihou-okf-extension/` — external Seihou
   extension for generating OKF documentation bundles from registries. Ships
   a private internal sublibrary (`seihou-okf-extension-internal`), the
   `seihou-okf-extension` executable, and a test suite. **Depends on
   `seihou-core`**; publish after `seihou-core` is live on Hackage.

`seihou-cli` and `seihou-okf-extension` both depend only on `seihou-core`
(not on each other), so once `seihou-core` is live they can be published in
either order.

Not separately released: there are no example/benchmark/test-only *packages*
in this repo. Each package's test suite is a component that ships inside its
own tarball, and the `*-internal` sublibraries are published as part of their
parent package, not on their own.

## Versioning strategy (PVP)

Versions are `A.B.C.D`:

| Segment | Name in `[major\|minor\|patch]` arg | Bump when |
|---------|-------------------------------------|-----------|
| `A.B`   | **major** | Breaking API change (removed/changed exports, behavior changes). |
| `C`     | **minor** | Backwards-compatible additions (new exports, new modules/flags). |
| `D`     | **patch** | No API change (bug fixes, internal refactors, doc/metadata). |

- All three packages move **together** to the same `A.B.C.D`. Even if only one
  package changed, bump all of them so the shared version stays consistent
  (every release from `0.1.0.0` to `0.7.0.0` shares one version across all
  three packages).
- **A breaking release bumps `B`, pre-1.0 included.** Every release so far —
  `0.1.0.0` through `0.7.0.0` — has bumped the `B` segment, and the breaking
  ones are no exception: `0.5.0.0 → 0.6.0.0` dropped manifest keys, and
  `0.6.0.0 → 0.7.0.0` changed `seihou-core` record types and made previously
  working commands refuse. Do **not** talk yourself into a `C` bump for a
  breaking pre-1.0 release on general PVP grounds; this repo's history is the
  authority, and departing from it needs the user's explicit say-so.
- Reserve `D` for a release with no API change at all, and `C` for
  backwards-compatible additions only.
- When the user passes `major`, `minor`, or `patch` as the argument, honor it.
  Otherwise infer the level from the changes and confirm with the user.

## Hackage-readiness preconditions (gate before any upload)

**Before the first real publish, verify these and stop if any are unmet** —
do not upload a package that won't resolve or build for downstream users:

1. **Git-pinned dependency.** `cabal.project` pins `streamly` via a
   `source-repository-package` (git). A package whose dependency closure needs
   that pin cannot be built from Hackage by others. Confirm that the
   dependencies of `seihou-cli` and `seihou-okf-extension` (e.g. `baikai`,
   `baikai-claude`, `baikai-openai`, and their `streamly` requirement) resolve
   against **Hackage releases**, not the git pin. If a package still needs the
   git `streamly`, do **not** upload it — publish the packages that do resolve
   (at least `seihou-core`) and stop.

   As checked at `0.7.0.0`: `baikai` requires `streamly >=0.11 && <0.13` and
   `streamly-core >=0.3 && <0.5`, and Hackage carries `streamly 0.11.1` and
   `streamly-core 0.3.1`, both in range. So a Hackage-only *resolution* exists
   and the git pin is a build-level workaround (GHC 9.12 compatibility) rather
   than a resolution blocker. Note the distinction honestly when reporting:
   this shows the closure resolves, not that it builds from Hackage. Re-check
   the bounds whenever `build-depends` changes; if nothing in any `build-depends`
   moved since the last release, the picture is unchanged from a release that
   already published successfully.
2. **Package metadata.** Each `*.cabal` already carries `license`
   (BSD-3-Clause), `license-file`, `author`, `maintainer`, `homepage`,
   `bug-reports`, `category`, `synopsis`, and `description`, and each package
   directory has a `LICENSE` file. `cabal check` (step 6) is the gate that
   confirms nothing regressed — do not upload a package it flags.
3. **Internal dependency bounds.** Every intra-repo dependency pins
   `seihou-core ^>=<current version>` across all components — five occurrences
   in total, three in `seihou-cli` and two in `seihou-okf-extension`. This
   skill re-pins those bounds to the new version as part of the bump (step 4);
   Hackage requires a bound, so never leave one open. After the bump, grep for
   the *old* version across the three cabal files to confirm nothing was
   missed.

Surface any unmet precondition to the user and let them decide whether to fix
it now or publish the resolvable packages alone. Never silently skip them.

## Steps

### 1. Pre-flight

```bash
git status --porcelain          # working tree must be clean
git rev-parse --abbrev-ref HEAD # expect master
git tag --list | sort -V | tail -5
gh auth status                  # gh must be authenticated (GitHub release)
cabal --version
```

Also confirm Hackage upload credentials are available (a
`~/.config/cabal/config` / `~/.cabal/config` with a username, or
`cabal upload` will prompt). If the working tree is dirty, stop and ask the
user to commit or stash.

### 2. Determine changes since the last release

```bash
LAST_TAG=$(git tag --list 'v*' | sort -V | tail -1)   # e.g. v0.3.0.0
git log --oneline "$LAST_TAG"..HEAD
git diff --stat "$LAST_TAG"..HEAD
```

Read the `[Unreleased]` section of `CHANGELOG.md`. If there are no commits
since `$LAST_TAG` and nothing under `[Unreleased]`, there is nothing to
release — tell the user and stop. Categorize the changes (Added / Changed /
Fixed / breaking) to drive the bump.

### 3. Compute the PVP bump

Current version (all packages share it):

```bash
grep '^version:' \
  seihou-core/seihou-core.cabal \
  seihou-cli/seihou-cli.cabal \
  seihou-okf-extension/seihou-okf-extension.cabal
```

If the user passed `major|minor|patch`, apply that to the current `A.B.C.D`.
Otherwise infer the level from step 2 (see the PVP table). Present the proposed
`OLD → NEW` version with a short rationale and the change summary, and ask the
user to confirm or override before editing anything.

### 4. Update versions, internal bounds, and changelog

With the confirmed `NEW = A.B.C.D`:

- Edit `version:` in **all three** cabal files to `A.B.C.D`:
  `seihou-core/seihou-core.cabal`, `seihou-cli/seihou-cli.cabal`, and
  `seihou-okf-extension/seihou-okf-extension.cabal`.
- Re-pin the internal `seihou-core` bound to the new version, e.g.
  `seihou-core ^>=A.B.C.D`, in **every** component that depends on it:
  - `seihou-cli`: the `seihou-cli-internal` library, the `seihou` executable,
    and the test suite.
  - `seihou-okf-extension`: the `seihou-okf-extension-internal` library and
    the test suite.
- Update `CHANGELOG.md` (repo root, Keep-a-Changelog format): move the
  `[Unreleased]` items into a new `## [A.B.C.D] - YYYY-MM-DD` section (today's
  date), leave a fresh empty `[Unreleased]`, and refresh the compare links at
  the bottom (`[Unreleased]: …compare/vA.B.C.D...HEAD` and
  `[A.B.C.D]: …compare/v<prev>...vA.B.C.D`).
- **Cut `docs/user/CHANGELOG.md` the same way.** It is a second, curated
  *user-facing* changelog — same `## [A.B.C.D] - YYYY-MM-DD` sections, same
  compare links at the foot — written in plain prose with worked examples,
  while the root file is the engineering log. Move its `## Unreleased` entries
  into a new version section and refresh its links too.
  - The two files are written for different readers. Do not copy one into the
    other: the root file names ExecPlans, modules, and type signatures; the
    user file explains what changed for someone running the CLI. Entries are
    normally written as the work lands, so at release time the section usually
    just needs cutting, not authoring.
  - Historical note: this skill used to describe `docs/user/CHANGELOG.md` as a
    "doc-review log — do not touch", which was wrong. Because of that, no
    release commit cut it between `0.3.0.0` and `0.7.0.0`, and its `Unreleased`
    heading silently accumulated three releases' worth of entries before being
    split back out at `0.7.0.0`. If you find it drifting again, split by
    reading the file as it stood at each tag
    (`git show vX:docs/user/CHANGELOG.md`) — entries present at tag *N* but not
    at *N-1* shipped in *N*.

Show the diff and get the user's confirmation of the bump + changelog before
committing.

### 5. Format, build, test, check (gates — do not skip)

```bash
just format    # nix fmt via treefmt (fourmolu + cabal-gild + nixpkgs-fmt)
just build     # cabal build all
just test      # cabal test all
just check     # nix flake check (includes CLI module-placement check)
```

If any gate fails, **stop** and report — do not proceed to commit or publish.

### 6. cabal check each package

```bash
( cd seihou-core          && cabal check )
( cd seihou-cli           && cabal check )
( cd seihou-okf-extension && cabal check )
```

Resolve any warnings/errors. Do not upload a package that fails `cabal check`.

### 7. Commit, tag, push

Use a Conventional Commits message (this repo requires it):

```bash
git add \
  seihou-core/seihou-core.cabal \
  seihou-cli/seihou-cli.cabal \
  seihou-okf-extension/seihou-okf-extension.cabal \
  CHANGELOG.md \
  docs/user/CHANGELOG.md
git commit -m "chore(release): vA.B.C.D"
git tag -a vA.B.C.D -m "Release vA.B.C.D"    # annotated, v-prefixed
git push && git push --tags
```

### 8. Publish to Hackage — in dependency order

Publish **`seihou-core` first**, then `seihou-cli` and
`seihou-okf-extension`. After each `--publish` upload the version is permanent
and cannot be changed. **If the `seihou-core` upload fails, stop — do not
upload the dependents.**

`seihou-core` (first):

```bash
( cd seihou-core
  cabal sdist
  cabal upload --publish dist-newstyle/sdist/seihou-core-A.B.C.D.tar.gz
  cabal haddock --haddock-for-hackage
  cabal upload --documentation --publish dist-newstyle/seihou-core-A.B.C.D-docs.tar.gz )
```

Wait until `seihou-core A.B.C.D` is **live** on Hackage (so the dependents'
`seihou-core ^>=A.B.C.D` bound resolves), then publish the two dependents (in
either order):

```bash
( cd seihou-cli
  cabal sdist
  cabal upload --publish dist-newstyle/sdist/seihou-cli-A.B.C.D.tar.gz
  cabal haddock --haddock-for-hackage
  cabal upload --documentation --publish dist-newstyle/seihou-cli-A.B.C.D-docs.tar.gz )

( cd seihou-okf-extension
  cabal sdist
  cabal upload --publish dist-newstyle/sdist/seihou-okf-extension-A.B.C.D.tar.gz
  cabal haddock --haddock-for-hackage
  cabal upload --documentation --publish dist-newstyle/seihou-okf-extension-A.B.C.D-docs.tar.gz )
```

Tip: run a candidate first (`cabal upload <tarball>` **without** `--publish`)
to sanity-check the Hackage page before the irreversible `--publish`.

**Expect the two documentation uploads to fail.** Only `seihou-core` can
publish Haddocks. For `seihou-cli` and `seihou-okf-extension`,
`cabal upload --documentation` returns:

```text
http code 400
Error: Invalid documentation tarball
Invalid windows file name in tar archive:
"seihou-cli-0.7.0.0-docs\\seihou-cli-internal\\seihou-cli:seihou-cli-internal.txt"
```

This is **not a regression and not a release blocker** — it has failed for
every release, and no version of either package has docs on Hackage. Both
ship a private sublibrary and no public library, which breaks the tarball two
ways at once: Haddock names the sublibrary's interface file with a colon
(which Hackage rejects), and it nests the HTML under
`<pkg>-<ver>-docs/<sublibrary>/` instead of directly under `<pkg>-<ver>-docs/`.
Fixing the filename alone is not enough.

Run the two `cabal upload --documentation` commands anyway, note the failure,
and carry on to the GitHub release. Repacking the tarball (flatten the
sublibrary directory, drop the colon file) would satisfy Hackage but would
publish a *private* sublibrary's API as the package's documentation — raise it
with the user rather than doing it silently. Unlike a package version,
documentation can be re-uploaded at any time, so there is no rush.

### 9. GitHub release

```bash
gh release create vA.B.C.D --title "vA.B.C.D" --notes "$(cat <<'EOF'
## Added
- ...
## Changed
- ...
## Fixed
- ...
EOF
)"
```

Notes should be a concise, user-facing summary derived from the changelog
section — no internal implementation detail.

## Important

- **Confirm the bump and changelog with the user before committing.** Don't
  edit versions until the `OLD → NEW` is ratified.
- **Always publish in dependency order** — `seihou-core` before `seihou-cli`
  and `seihou-okf-extension`. Never upload a dependent after its upstream
  upload failed.
- **Never skip the gates** (`just format`/`build`/`test`/`check` and
  `cabal check`). Stop on the first failure; do not commit or publish past it.
- **`--publish` is irreversible.** Prefer a non-published candidate upload
  first. A wrong upload can only be fixed by a new version.
- **All three packages share the version**; bump and tag them together.
- **A breaking release bumps `B`, pre-1.0 included** — that is what every
  release in this repo has done. Don't reason your way to a `C` bump from
  generic PVP advice.
- **Honor the Hackage-readiness preconditions.** If the git-pinned `streamly`
  still leaks into a package's Hackage dependency closure, publish the
  packages that resolve (at least `seihou-core`) and stop — do not upload an
  unbuildable package.
- **Conventional Commits** for the release commit (`chore(release): vA.B.C.D`).
- **Cut both changelogs** — the root `CHANGELOG.md` (engineering) *and*
  `docs/user/CHANGELOG.md` (curated, user-facing). Both carry version sections
  and compare links; both belong in the release commit.
- **The two doc uploads for `seihou-cli` and `seihou-okf-extension` will
  fail**, as they always have. Note it and continue — the packages themselves
  publish fine.
