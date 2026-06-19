---
id: 56
slug: make-okf-core-a-buildable-dependency-of-seihou
title: "Make okf-core a buildable dependency of seihou"
kind: exec-plan
created_at: 2026-06-19T17:55:29Z
intention: "intention_01kvgg9k54efytmmeqty43t6y5"
master_plan: "docs/masterplans/7-generate-okf-documentation-bundles-for-seihou-registries.md"
---

# Make okf-core a buildable dependency of seihou

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

This plan is the build foundation for the MasterPlan at
`docs/masterplans/7-generate-okf-documentation-bundles-for-seihou-registries.md`. Read that
file for the overall initiative; this plan stands alone for implementation.

The initiative now adds a `seihou-okf-extension docs` command that generates Open Knowledge
Format (OKF) documentation bundles. When this plan was implemented, OKF was still being
proven as an in-core `seihou docs` feature; EP-60 later moves the consuming dependency and
smoke import into the extension package. OKF is implemented by the `okf-core` Haskell library,
which lives in a separate repository at `/Users/shinzui/Keikaku/bokuno/okf` (package directory
`/Users/shinzui/Keikaku/bokuno/okf/okf-core`). Today `okf-core` is *local-only*: it is not on
Hackage, and the okf repo's flake exposes only a whole-repo `packages.default` named `"okf"`,
not a reusable `okf-core` library output. Seihou therefore cannot yet `import Okf.*`.

This plan makes `okf-core` build inside seihou through the two paths seihou is built with:

- Plain `cabal build` (and HLS in the editor) must resolve `okf-core`. We add a
  `source-repository-package` stanza to `cabal.project` so cabal fetches and builds it from
  the okf git repo at a pinned commit, subdir `okf-core`.
- `nix build` / `nix develop` must provide `okf-core` in the Nix Haskell package set. We add
  the okf repo as a flake input and a `callCabal2nix` entry in seihou's Haskell module so the
  Nix-built package set and dev shell contain `okf-core`.

The observable outcome: after this plan, a tiny smoke-test value in `seihou-cli-internal`
that calls an `okf-core` function compiles and runs under both `cabal build all` and
`nix build`, proving seihou code can use the OKF authoring API. No user-facing behavior
changes yet — that arrives in EP-58/EP-59.


## Progress

- [x] Pin the okf commit (`fb73a013adf7b4c5c65fd55552ea1fa47ed6a165`) and add a `source-repository-package` to `cabal.project` (2026-06-19)
- [x] Add `okf-core` to `seihou-cli-internal`'s `build-depends` (2026-06-19)
- [x] Add the `okf-src` flake input + a `callCabal2nix` `okf-core` entry to `nix/haskell-overlay.nix`, threaded via `flake.module.nix` (2026-06-19)
- [x] Add a smoke-test use of `okf-core` (`Seihou.CLI.Docs.Smoke`) and confirm it compiles (2026-06-19)
- [x] `cabal build all` succeeds (okf-core resolved, smoke compiled, `seihou` exe linked) (2026-06-19)
- [x] okf-core builds in the Nix sandbox and is consumed by the seihou package set; `flake.lock` adds only the `okf-src` node (2026-06-19)
- [ ] Full `nix build` of seihou-cli remains blocked by a **pre-existing** `baikai` version skew unrelated to okf-core (see Surprises). This is tracked as out of scope for EP-56.


## Surprises & Discoveries

- okf-core's package references files at the okf repo *root* — `extra-doc-files: ../CHANGELOG.md`
  and `license-file: ../LICENSE` — which `callCabal2nix` does not stage (it copies only the
  `okf-core/` subdir). Under `cabal build` this is fine (the `source-repository-package` clones
  the whole repo), but the Nix build failed on both in turn. Fixed in `nix/haskell-overlay.nix`
  by `dontCheck` (skip okf-core's own test suite, which we don't need) plus a `prePatch` that
  stages `../CHANGELOG.md` and `../LICENSE` from `okf-src` (mirroring how seihou-core stages
  `../schema`). After that, `okf-core` builds cleanly in Nix. Evidence: the okf-core derivation
  completes and the build proceeds to seihou-cli.

- `seihou`'s full `nix build` fails compiling seihou-cli against `baikai` — **unrelated to
  okf-core**. The cause is an in-progress `baikai` migration already present in the working tree
  (independent of this plan): `seihou-cli/src/Seihou/CLI/AgentCompletion.hs` carries an
  *uncommitted* edit changing `Baikai.userNow` → `Baikai.user` to match a newer baikai. With that
  edit, the seihou-cli **library** compiles, but the **test suite** still uses the pre-migration
  baikai API (`test/Seihou/CLI/AgentCompletionSpec.hs:87` references `Baikai.AssistantPayload`,
  which the resolved baikai no longer exports), so `nix build` (which runs `doCheck`) fails there.
  Evidence and scope:
  - `cabal build all` (the developer/dev-shell path) is fully green, including okf-core and the
    smoke module. `cabal build all` does not compile the test suites, so it does not hit the
    un-migrated test code.
  - On pristine HEAD (all changes *and* the user's WIP stashed via `git stash -u`), `nix build`
    fails even earlier — in the library at `AgentCompletion.hs:127` (`Baikai.userNow` not
    exported) — confirming the baikai migration, not okf-core, is the cause.
  - `git diff flake.lock` shows the only added node is `okf-src`; no dependency (including baikai)
    was bumped by this change.
  Completing the baikai migration (finish migrating the test suite to the new baikai API) is out
  of scope for EP-56, whose job is the okf-core wiring. The user's `AgentCompletion.hs` WIP was
  left untouched.


## Decision Log

- Decision: Use BOTH a `cabal.project` `source-repository-package` and a flake input +
  `callCabal2nix` overlay entry, rather than only one.
  Rationale: Seihou is built two ways; each path resolves dependencies differently. cabal/HLS
  need the package in `cabal.project`; the Nix build needs it in the package set. (Per the
  user's instruction to add a source-repository-package for cabal builds in addition to the
  Nix wiring.)
  Date: 2026-06-19

- Decision: Pin okf by a specific commit SHA, not a moving branch.
  Rationale: Reproducible builds. The okf authoring API is complete (okf MasterPlan 2), so a
  fixed commit is stable; bumping it later is a deliberate one-line change in both
  `cabal.project` (the `tag:`) and `flake.lock` (`nix flake update okf`).
  Date: 2026-06-19

- Decision: In the Nix overlay, build okf-core with `dontCheck` and a `prePatch` that stages
  `../CHANGELOG.md` and `../LICENSE` from `okf-src`.
  Rationale: `callCabal2nix` copies only the `okf-core/` subdir, but the package references
  those two files at the okf repo root. We only need the library, not okf-core's own tests, so
  skipping the test suite and staging the two referenced files is the minimal, faithful fix.
  Date: 2026-06-19

- Decision: Treat the `nix build` seihou-cli failure (stale `baikai`) as out of scope and do
  not fix it in EP-56.
  Rationale: It reproduces on pristine HEAD with all EP-56 changes stashed, so it is
  pre-existing and unrelated to okf-core. Fixing it means aligning the `haskell-nix` registry's
  baikai with the dev-shell baikai — a separate concern. EP-56's deliverable (okf-core wiring)
  is verified via `cabal build all` and the successful okf-core Nix derivation.
  Date: 2026-06-19


## Outcomes & Retrospective

Implemented 2026-06-19. `okf-core` (pinned to `shinzui/okf` commit
`fb73a013adf7b4c5c65fd55552ea1fa47ed6a165`, subdir `okf-core`) is now a buildable dependency of
`seihou-cli-internal` via both paths: a `source-repository-package` in `cabal.project` and an
`okf-src` flake input built through `callCabal2nix` in `nix/haskell-overlay.nix` (threaded from
`flake.module.nix`). `Seihou.CLI.Docs.Smoke` exercises the okf-core authoring API.

Verified: `cabal build all` (inside `nix develop`) succeeds end to end — okf-core compiles, the
smoke module compiles, and the `seihou` executable links. In Nix, the okf-core derivation builds
cleanly after the `dontCheck` + `prePatch` overlay fix, and `flake.lock` gains only the `okf-src`
node.

Gap (out of scope, documented in Surprises): seihou's *full* `nix build` fails compiling
seihou-cli against `baikai` — unrelated to okf-core. It is an in-progress baikai migration in the
working tree (an uncommitted `AgentCompletion.hs` edit migrates the library; the seihou-cli test
suite is not yet migrated and `nix build` runs it via `doCheck`). It should be resolved separately
by finishing the baikai migration. The downstream plans (EP-57/58/59) build and test under the
`cabal`/dev-shell path this plan verified, so they are unblocked.

Lesson: a `callCabal2nix` on a subdir of a multi-package repo must account for package files
referenced outside that subdir (`../CHANGELOG.md`, `../LICENSE`); stage them in `prePatch`.


## Context and Orientation

All paths are relative to the seihou repository root,
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` (the directory containing `flake.nix`,
`cabal.project`, `seihou-core/`, and `seihou-cli/`).

Seihou's build, from prior research:

- Two cabal packages, `cabal-version: 3.0`, version `0.3.0.0`, `default-language: GHC2024`.
  `seihou-core/seihou-core.cabal` (the reusable core library) and
  `seihou-cli/seihou-cli.cabal` (which contains three targets: the private library
  `seihou-cli-internal` with `hs-source-dirs: src`, the `executable seihou` with
  `hs-source-dirs: src-exe`, and `test-suite seihou-cli-test`). `cabal.project` lists the
  package directories.
- The Nix build is flake-parts based on the `haskell-nix-dev` base flake
  (`github:shinzui/haskell-nix-dev`), GHC **9.12.4** (`ghc9124`). The Haskell wiring (the
  package set, the `callCabal2nix` of seihou's own packages, the dev shell) lives in a Nix
  module imported by `flake.nix` — research identified `flake.module.nix` and files under
  `nix/`. Find the file that defines seihou's Haskell package set / `callCabal2nix` calls;
  that is where the `okf-core` entry goes. Read `flake.nix` first to see which module it
  imports and how `inputs` are threaded into it.
- `justfile` provides `just build` (`cabal build all`), `just test` (`cabal test all`),
  `just check` (`nix flake check`).

okf-core, from prior research (treat as fixed; do not modify the okf repo):

- Package `okf-core`, version `0.1.0.0`, `cabal-version: 3.4`, `default-language: GHC2024`,
  also built against GHC **9.12.4** on the same `haskell-nix-dev` base — so the toolchains
  and core dependency versions (lens 5.3, text 2.1, aeson, cmark-gfm 0.2, yaml, …) align.
- Library `build-depends`: `aeson, attoparsec, base, bytestring, cmark-gfm ^>=0.2,
  containers, directory, filepath, frontmatter, generic-lens, lens ^>=5.3, text ^>=2.1,
  vector, yaml`. A consumer needs only `okf-core` in its own `build-depends` (plus `aeson`
  and `text` if it constructs `Value`s directly — relevant in EP-58, not here).
- Exposed modules include `Okf.Document`, `Okf.ConceptId`, `Okf.Bundle`, `Okf.Validation`,
  `Okf.Graph`, `Okf.Index`.

The okf repo is a local git checkout at `/Users/shinzui/Keikaku/bokuno/okf` with a GitHub
remote `shinzui/okf`. For `source-repository-package` you need a commit SHA that contains the
completed authoring API. Get it with:

```bash
git -C /Users/shinzui/Keikaku/bokuno/okf rev-parse HEAD
```

and confirm that commit is pushed to `github.com/shinzui/okf` (so the Nix fetch and a clean
cabal fetch can reach it):

```bash
git -C /Users/shinzui/Keikaku/bokuno/okf log --oneline -1
git -C /Users/shinzui/Keikaku/bokuno/okf branch -r --contains HEAD
```

If HEAD is not yet pushed, push it (or coordinate with the user) before pinning, because both
the cabal `source-repository-package` (when fetched fresh) and the Nix `github:` input
require the commit to exist on the remote. For purely local iteration you may temporarily use
a `path:` input and a local `cabal.project` package path, but the committed plan must pin the
pushed commit for reproducibility — record the chosen SHA in the Decision Log.


## Plan of Work

Single milestone: wire okf-core in both build paths and prove it compiles. Work in this
order so you can detect which path fails.

Step 1 — cabal source-repository-package. Append to `cabal.project` (do not disturb the
existing `packages:` list):

```cabal
source-repository-package
  type: git
  location: https://github.com/shinzui/okf
  tag: <OKF_COMMIT_SHA>
  subdir: okf-core
```

`subdir: okf-core` tells cabal the package lives in the `okf-core/` directory of that repo
(the repo root also contains `okf-cli`, which we do not want). Replace `<OKF_COMMIT_SHA>` with
the SHA from `git rev-parse HEAD` above.

Step 2 — declare the dependency. In `seihou-cli/seihou-cli.cabal`, add `okf-core` to the
`build-depends` of the **`library seihou-cli-internal`** stanza only (not `seihou-core`, per
the MasterPlan's integration point 1; and the `executable seihou` stanza inherits it
transitively through `seihou-cli-internal`):

```cabal
  build-depends:
    ...
    , okf-core
```

Step 3 — Nix input. In `flake.nix`, add the okf repo as an input. Pin the same commit:

```nix
inputs.okf = {
  url = "github:shinzui/okf/<OKF_COMMIT_SHA>";
  # okf is consumed as a source tree we call callCabal2nix on, not as a flake we import:
  flake = false;
};
```

(If `flake.nix` threads `inputs` into its imported module via `specialArgs`/`_module.args` or
a `perSystem` argument, ensure `okf` is passed through. Read how the existing `seihou-schema`
non-flake source `seihou-schema-src` is plumbed — research noted `seihou-schema-src =
github:shinzui/seihou-schema/...` is already handled as a non-flake source, so mirror exactly
that mechanism for `okf`.)

Step 4 — Nix package-set entry. In the Nix module that defines seihou's Haskell package set
(the file with the existing `callCabal2nix` calls for `seihou-core`/`seihou-cli` — likely
`flake.module.nix` or a file under `nix/`), add an `okf-core` package built from the input's
`okf-core` subdirectory. Using the same Haskell package set (`hpkgs`) the rest of seihou
uses, add an override so the set contains `okf-core`:

```nix
# inside the haskellPackages overrides (mirror how seihou-core is added):
okf-core = hpkgs.callCabal2nix "okf-core" (inputs.okf + "/okf-core") { };
```

The exact integration depends on whether seihou uses `callCabal2nix` directly in a devShell
or an overlay/`packageSetConfig`. Match the existing pattern for seihou's own packages: find
the line that does `callCabal2nix "seihou-core" ./seihou-core { }` (or equivalent) and add a
sibling line for `okf-core` pointing at `inputs.okf + "/okf-core"`. Because `okf-core`'s
`build-depends` are all standard Hackage packages already present in the `haskell-nix-dev`
package set at compatible versions, no further overrides should be needed.

Step 5 — smoke test. Create a tiny module that forces `okf-core` to be linked, so the build
genuinely exercises the dependency. Add
`seihou-cli/src/Seihou/CLI/Docs/Smoke.hs`:

```haskell
module Seihou.CLI.Docs.Smoke (okfSmoke) where

import Data.Text (Text)
import Okf.Document (OKFDocument (..), emptyFrontmatter, serializeDocument)

-- | Proof that seihou can call the okf-core authoring API. Returns a serialized
-- empty-frontmatter OKF document. Removed or absorbed by EP-58 once real rendering exists.
okfSmoke :: Text
okfSmoke = serializeDocument (OKFDocument emptyFrontmatter "# smoke\n")
```

Add `Seihou.CLI.Docs.Smoke` to the `exposed-modules` of the `seihou-cli-internal` stanza in
`seihou-cli/seihou-cli.cabal`. (EP-58 will replace this module with the real renderer; it is
intentionally trivial and exists only to make this plan's success observable.)

Step 6 — build both ways and confirm. See Concrete Steps. If cabal cannot resolve a
dependency version (for example a `lens`/`text` bound mismatch), record the exact conflict in
Surprises & Discoveries; because both projects target ghc9124 on the same base flake, a clean
Nix build should not hit this, but a non-Nix `cabal build` outside the dev shell might pull
different versions — always build inside `nix develop`.


## Concrete Steps

From the seihou repository root.

Get and record the okf commit:

```bash
git -C /Users/shinzui/Keikaku/bokuno/okf rev-parse HEAD
```

Build via cabal inside the dev shell (the supported path):

```bash
nix develop
cabal build all
```

Expected: `okf-core` is fetched/built once, then `seihou-cli-internal` compiles including
`Seihou.CLI.Docs.Smoke`. A successful tail looks like:

```text
Building library 'seihou-cli-internal' for seihou-cli-0.3.0.0..
...
Linking ...
```

Build via Nix:

```bash
nix flake lock         # picks up the new okf input -> writes flake.lock
nix build              # builds the seihou package(s) with okf-core in the set
```

Quick REPL confirmation that the symbol is reachable:

```bash
cabal repl seihou-cli-internal
```

```haskell
ghci> import Seihou.CLI.Docs.Smoke
ghci> Data.Text.IO.putStr okfSmoke
---
{}
---

# smoke
```


## Validation and Acceptance

Acceptance is behavioral:

1. `cabal build all` (inside `nix develop`) succeeds with `okf-core` resolved via the
   `source-repository-package`, and `seihou-cli-internal` compiles the smoke module.
2. `nix build` succeeds with `okf-core` provided by the flake input + `callCabal2nix` entry
   (no reliance on cabal fetching during the Nix build).
3. The REPL transcript above reproduces, proving `Okf.Document.serializeDocument` is callable
   from seihou code.
4. `git -C . status` shows changes only to `cabal.project`, `flake.nix`, the Nix Haskell
   module, `seihou-cli/seihou-cli.cabal`, the new `Seihou/CLI/Docs/Smoke.hs`, and
   `flake.lock` — no changes to `seihou-core`.


## Idempotence and Recovery

Re-running the builds is safe and idempotent. If the Nix input fails to fetch (commit not
pushed), the recovery is to push the okf commit to `shinzui/okf` or temporarily switch the
input to `url = "path:/Users/shinzui/Keikaku/bokuno/okf"; flake = false;` and the
`cabal.project` stanza to a local package path for iteration, then restore the pinned
`github:` form before committing (record this in the Decision Log). If a dependency-version
conflict appears under a non-Nix cabal invocation, the fix is to build inside `nix develop`
so the `haskell-nix-dev` package set governs versions. Removing the feature entirely is a
clean revert of the listed files.


## Interfaces and Dependencies

New external dependency: `okf-core` (library), pinned to a commit of `github:shinzui/okf`,
subdir `okf-core`. No new Hackage packages beyond what `okf-core` transitively requires
(already present in the shared `haskell-nix-dev` set).

Artifacts that must exist at the end of this plan:

```text
cabal.project                                   (+ source-repository-package for okf-core)
flake.nix                                        (+ inputs.okf, threaded to the haskell module)
<seihou nix haskell module>                      (+ okf-core = callCabal2nix ... )
seihou-cli/seihou-cli.cabal                       (seihou-cli-internal build-depends: + okf-core; exposed-modules: + Seihou.CLI.Docs.Smoke)
seihou-cli/src/Seihou/CLI/Docs/Smoke.hs           (new smoke module)
flake.lock                                        (updated)
```

Relationship to other plans (see the MasterPlan's Integration Points):

- This plan proves okf-core can be pinned and built. EP-60
  (`docs/plans/60-add-a-seihou-extension-contract-and-okf-extension-package.md`) hard-depends
  on this plan and moves the consuming okf-core dependency from `seihou-cli-internal` into
  `seihou-okf-extension`.
- EP-58 (`docs/plans/58-render-the-seihou-documentation-model-to-an-okf-bundle.md`) depends
  on this plan through EP-60 and implements the real renderer under the
  `Seihou.OKF.Docs.*` namespace.
- EP-57 (`docs/plans/57-load-a-seihou-registry-into-a-documentation-model.md`) does not depend
  on this plan (it imports no okf-core) and can be developed in parallel.


## Revision Notes

- 2026-06-19: Validated EP-56 as part of the MasterPlan review. Replaced the nonstandard
  `[~]` progress marker with an unchecked out-of-scope blocker entry and converted indented
  shell commands to fenced `bash` blocks, preserving the existing implementation status.
- 2026-06-19: Updated relationship notes after the initiative moved to an extension package.
  The smoke module remains historical evidence for EP-56, while EP-60 now owns moving the
  okf-core dependency and smoke import out of `seihou-cli-internal`.
