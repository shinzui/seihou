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
  (this matches the `0.1.0.0` / `0.2.0.0` / `0.3.0.0` history where every
  package shares the version).
- While pre-1.0, treat a user-visible breaking change as a `minor` (`C`) bump
  unless cutting a deliberate 1.0; reserve `major` (`A.B`) for 1.0+.
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
2. **Package metadata.** Each `*.cabal` already carries `license`
   (BSD-3-Clause), `license-file`, `author`, `maintainer`, `homepage`,
   `bug-reports`, `category`, `synopsis`, and `description`, and each package
   directory has a `LICENSE` file. `cabal check` (step 6) is the gate that
   confirms nothing regressed — do not upload a package it flags.
3. **Internal dependency bounds.** Every intra-repo dependency currently pins
   `seihou-core ^>=0.3.0.0` across all components. This skill re-pins those
   bounds to the new version as part of the bump (step 4); Hackage requires a
   bound, so never leave one open.

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
  - Note: `docs/user/CHANGELOG.md` is a **doc-review log**, not the release
    changelog. Do **not** touch it here.

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
  CHANGELOG.md
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
- **Honor the Hackage-readiness preconditions.** If the git-pinned `streamly`
  still leaks into a package's Hackage dependency closure, publish the
  packages that resolve (at least `seihou-core`) and stop — do not upload an
  unbuildable package.
- **Conventional Commits** for the release commit (`chore(release): vA.B.C.D`).
- Don't touch `docs/user/CHANGELOG.md` — it's a doc-review log, not the
  release changelog.
