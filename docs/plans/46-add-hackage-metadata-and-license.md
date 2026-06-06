---
id: 46
slug: add-hackage-metadata-and-license
title: "Add Hackage metadata and license"
kind: exec-plan
created_at: 2026-06-05T14:34:22Z
intention: "intention_01ktc3hwwneswaz13bvr1tb6f9"
master_plan: "docs/masterplans/5-first-public-release-readiness.md"
---

# Add Hackage metadata and license

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, both public packages pass `cabal check` for Hackage metadata and the repository has a real license file matching the Cabal package declarations. A user viewing Seihou on Hackage can see the package category, maintainer, homepage, issue tracker, license, and description.

The current packages are rejected by `cabal check` because the `license` field is missing.


## Progress

- [x] Confirm the intended open-source license with the repository owner. Completed 2026-06-06: the owner chose BSD-3-Clause with `Nadeem Bitar` / `nadeem@gmail.com` as the public package identity.
- [x] Add a root `LICENSE` file for the chosen license. Completed 2026-06-06.
- [x] Add package metadata to `seihou-core/seihou-core.cabal`. Completed 2026-06-06.
- [x] Add package metadata and dependency bounds to `seihou-cli/seihou-cli.cabal`. Completed 2026-06-06.
- [x] Run `cabal check` in both package directories and resolve all errors. Completed 2026-06-06: both packages reported no errors or warnings.
- [x] Update `README.md` license text if needed. Completed 2026-06-06.


## Surprises & Discoveries

The audit found no `LICENSE` or `COPYING` file in the repository, while `README.md` says "See LICENSE file."

`cabal check` initially rejected both public packages with `license-none` and warned about missing `category`, `maintainer`, and `description`. `seihou-cli` also warned that the private library target missed upper bounds for `baikai`, `baikai-claude`, `baikai-openai`, `seihou-core`, and `vector`.

Package-local `LICENSE` files are needed alongside the root `LICENSE` because each Cabal source distribution is rooted at its package directory. `cabal sdist all` includes `seihou-core-0.2.0.0/LICENSE` and `seihou-cli-0.2.0.0/LICENSE`, and the package-local copies match the root file byte-for-byte.


## Decision Log

- Decision: Keep license selection as an explicit owner decision.
  Rationale: A license is a legal/publishing decision, not a mechanical coding choice. Implementation should not guess.
  Date: 2026-06-05

- Decision: Use BSD-3-Clause metadata with `Nadeem Bitar` as author/copyright holder and `nadeem@gmail.com` as maintainer.
  Rationale: The repository owner supplied those values after the implementation paused at the legal metadata step.
  Date: 2026-06-06

- Decision: Use package-local `LICENSE` files in `seihou-core` and `seihou-cli`, in addition to the root `LICENSE`.
  Rationale: Cabal sdists are generated per package directory, so package-local license files make each uploaded tarball self-contained while preserving the repository-level license pointer.
  Date: 2026-06-06

- Decision: Bound `baikai`, `baikai-claude`, `baikai-openai`, `seihou-core`, and `vector` with caret bounds based on the versions resolved in the current Cabal plan.
  Rationale: This follows Haskell PVP expectations, removes Hackage metadata warnings, and keeps `seihou-core` on the lockstep `0.2.0.0` release line until the release workflow bumps versions.
  Date: 2026-06-06


## Outcomes & Retrospective

EP-6 added BSD-3-Clause licensing and complete Hackage-facing metadata to both public packages. The root README now points to the real repository license, and each package source distribution includes a matching license file.

Validation passed with:

```text
(cd seihou-core && cabal check)
No errors or warnings could be found in the package.

(cd seihou-cli && cabal check)
No errors or warnings could be found in the package.

cabal sdist all
Wrote tarball sdist to .../dist-newstyle/sdist/seihou-core-0.2.0.0.tar.gz
Wrote tarball sdist to .../dist-newstyle/sdist/seihou-cli-0.2.0.0.tar.gz
```

Tarball inspection confirmed:

```text
seihou-core-0.2.0.0/LICENSE
seihou-cli-0.2.0.0/LICENSE
```


## Context and Orientation

There are two public Cabal packages:

- `seihou-core/seihou-core.cabal`
- `seihou-cli/seihou-cli.cabal`

Both currently have sparse headers with `cabal-version`, `name`, `version`, `synopsis`, and `build-type`, then component stanzas. Hackage expects package-level metadata such as `license`, `license-file`, `author`, `maintainer`, `homepage`, `bug-reports`, `category`, and `description`.

`seihou-cli` depends on `seihou-core`, `baikai`, `baikai-claude`, `baikai-openai`, and `vector` without upper bounds in some components. `cabal check` warns about missing upper bounds because Haskell packages are expected to follow the Package Versioning Policy.


## Plan of Work

Milestone 1 confirms policy metadata. Before editing the license, ask the owner which license to use. Common choices for Haskell CLI tools are MIT, BSD-3-Clause, or Apache-2.0, but the implementation must use the owner's explicit choice. Also confirm the public maintainer email or alias to place in Cabal metadata.

Milestone 2 adds the license file and package headers. Add `LICENSE` at the repository root. In both Cabal files, add fields similar to:

```text
license: BSD-3-Clause
license-file: ../LICENSE
author: <owner name>
maintainer: <maintainer contact>
homepage: https://github.com/shinzui/seihou
bug-reports: https://github.com/shinzui/seihou/issues
category: Development
description:
  Seihou is a composable, type-safe project scaffolding system...
```

Use the exact license identifier required by Cabal for the chosen license. If Cabal rejects `../LICENSE`, use a package-local license file strategy acceptable to Cabal source distributions, such as adding a copy in each package or declaring root packaging appropriately. Validate with `cabal sdist` and `cabal check`.

Milestone 3 adds dependency bounds in `seihou-cli/seihou-cli.cabal`. Add version bounds for `seihou-core`, `baikai`, `baikai-claude`, `baikai-openai`, and `vector` in every component where Cabal warns. For lockstep release, `seihou-core` should be constrained to the shared release version, for example `seihou-core ^>=0.2.0.0` until the release version is bumped. The final release workflow may update this to the new version.

Milestone 4 updates README. Replace the vague "See LICENSE file" with the chosen license name and a pointer to `LICENSE`.


## Concrete Steps

Run the current checks to reproduce:

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou/seihou-core
cabal check
cd ../seihou-cli
cabal check
```

After edits, run:

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
cabal sdist all
(cd seihou-core && cabal check)
(cd seihou-cli && cabal check)
```

Expected output after the fix is no `license-none` rejection. Ideally there are no warnings. If a warning remains intentionally, record why in Surprises & Discoveries.


## Validation and Acceptance

Acceptance requires:

- A root `LICENSE` file exists and matches the Cabal `license` fields.
- `README.md` no longer points to a missing file.
- `cabal check` passes for `seihou-core`.
- `cabal check` passes for `seihou-cli`.
- `cabal sdist all` includes the license file in both relevant source distributions.


## Idempotence and Recovery

Metadata edits are safe to retry. If Cabal rejects the selected `license-file` path, do not remove the license; adjust packaging so each package's source distribution includes it. If the owner has not chosen a license, stop at Milestone 1 and record the blocker rather than inventing one.


## Interfaces and Dependencies

This plan touches `LICENSE`, `README.md`, `seihou-core/seihou-core.cabal`, and `seihou-cli/seihou-cli.cabal`. It has a soft overlap with `docs/plans/41-package-embedded-cli-assets-for-hackage.md` because both edit `seihou-cli.cabal`; preserve any `extra-source-files` entries from that plan.
