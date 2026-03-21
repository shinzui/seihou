# Publish seihou-schema to a Separate Repository

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, the seihou Dhall schema lives in a standalone public GitHub repository (`seihou-schema`) and modules import it via a pinned HTTPS URL with an integrity hash. This gives modules a verifiable, versioned contract with the seihou schema — Dhall's type checker enforces the schema at evaluation time, not just the Haskell decoder. Module authors can use record completion (`::`) for concise authoring, and `seihou schema-upgrade` can inject the schema import into legacy modules automatically.

The user-visible outcome: after running `seihou new-module my-mod`, the generated `module.dhall` imports the schema from GitHub and uses `::` for concise, type-safe authoring. Running `seihou schema-upgrade` on an old module adds the import and converts it. The seihou binary embeds the "current" schema URL and hash so it always knows which version to inject.

This follows the pattern established by the mori project at `/Users/shinzui/Keikaku/bokuno/mori-project/mori`, which publishes `mori-schema` as a separate GitHub repo, references it as a git submodule in the main repo, and pins it via URL + SHA256 in both user-facing config files and a `Schema.Version` Haskell module.


## Progress

- [x] M0: Push schema files to seihou-schema GitHub repository (2026-03-21)
  - Commit: 6df1496a7ce06a693d8b63bd4cf2c5d4a136670c
  - Hash: sha256:4946704e8c2dd295179003832428b82273fb0a0cff8eae9282b64ae7e18b89f4
- [x] M1: Add git submodule and pin the schema version in Haskell (2026-03-21)
- [x] M2: Update Scaffold.hs to generate modules using URL-based schema imports (2026-03-21)
- [x] M3: Update schema-upgrade to inject schema imports into legacy modules (2026-03-21)
- [x] M4: Update Nix build to handle schema submodule (2026-03-21)
- [x] M5: Create update-seihou-schema skill (2026-03-21)
- [x] M6: Update documentation and agent prompts (2026-03-21)


## Surprises & Discoveries

- The `currentModuleText` test fixture needed updating to include a schema import, since all modules without the import are now flagged by `detectIssues`. This was straightforward.
- The `injectSchemaImport` function uses a simple strategy: prepend the `let S = ...` header and replace `{ name = ...` with `in  S.Module::{ name = ...`. This does not convert sub-records (steps, prompts, etc.) to use `S.Step::{}` syntax — that remains a future enhancement.
- Nix build works correctly with the `prePatch` approach for copying the schema submodule into the sandbox.


## Decision Log

- Decision: Follow the mori pattern — separate public repo, git submodule, URL-based imports with integrity hashes, Schema.Version Haskell module.
  Rationale: Proven pattern in the same ecosystem. Gives modules a verifiable contract, supports independent versioning, and integrates with Dhall's import caching and integrity checking. The mori project at `/Users/shinzui/Keikaku/bokuno/mori-project/mori` demonstrates this works well in practice.
  Date: 2026-03-21

- Decision: Use `https://raw.githubusercontent.com/shinzui/seihou-schema/<commit>/package.dhall` as the import URL format.
  Rationale: GitHub raw content URLs are stable, cacheable, and compatible with Dhall's HTTP import resolver. Pinning to a commit hash (not a branch) ensures reproducibility.
  Date: 2026-03-21

- Decision: Keep the Haskell decoder (`moduleDecoder`) accepting raw records without schema imports for backward compatibility.
  Rationale: The decoder operates on normalized Dhall expressions. After Dhall evaluates `S.Module::{ name = "foo" }`, the result is a plain record — indistinguishable from a hand-written one. The decoder doesn't need to change. Old modules without schema imports continue to work.
  Date: 2026-03-21


## Outcomes & Retrospective

All 7 milestones completed successfully on 2026-03-21.

**Results:**
- `seihou-schema` repo published at `github.com/shinzui/seihou-schema` with commit `6df1496` and integrity hash `sha256:4946704e...`
- `schema/` converted to a git submodule; `SchemaVersion.hs` pins the URL and hash
- `seihou new-module` generates modules with `let S = <url> <hash> in S.Module::{...}` syntax
- `seihou schema-upgrade` detects and injects missing schema imports (idempotent)
- Nix build handles the submodule via the `seihou-schema-src` flake input
- `update-seihou-schema` Claude Code skill created for bumping the pin
- All documentation and agent prompts updated

**Test results:** 601 core tests + 48 CLI tests pass. `nix build .#seihou` succeeds.

**Future work:** Convert sub-records in upgraded modules to use `S.Step::{}`, `S.VarDecl::{}` etc. Currently only the top-level record gets `S.Module::` wrapping.


## Context and Orientation

Seihou is a composable, type-safe project scaffolding system. It is a multi-package Haskell workspace with `seihou-core` (library) and `seihou-cli` (executable), built with GHC 9.12.2 and Nix flakes. Modules are defined by `module.dhall` files — Dhall expressions that the Haskell decoder converts to a `Module` Haskell type.

The schema currently lives at `schema/` in the seihou repository as eight Dhall files organized as a package with `{ Type, default }` records for record completion. This was introduced in the immediately prior work (see `docs/plans/schema-upgrade-command.md`). No module currently imports the schema — it exists but is not referenced by any `module.dhall` file.

The `seihou-schema` GitHub repository already exists at `https://github.com/shinzui/seihou-schema` but is currently empty. The local checkout is at `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema`. The schema files need to be pushed to it as the first milestone.

The mori project provides a working reference implementation of the pattern we are adopting. Key mori files and their seihou equivalents:

    mori-schema (separate repo)           →  seihou-schema (exists at github.com/shinzui/seihou-schema)
    mori/.gitmodules                      →  seihou/.gitmodules (to be created)
    mori/schema/ (submodule)              →  seihou/schema/ (convert to submodule)
    mori-cli/src/Mori/Schema/Version.hs   →  seihou-cli/src/Seihou/CLI/SchemaVersion.hs (to be created)
    mori/flake.nix (schema input)         →  seihou/flake.nix (to be updated)
    mori/nix/haskell-overlay.nix          →  seihou/nix/haskell-overlay.nix (to be updated)

Key files in the seihou codebase that this plan touches:

- `schema/` — currently a plain directory with 8 Dhall files; will become a git submodule
- `seihou-cli/src/Seihou/CLI/SchemaVersion.hs` — new module pinning the schema URL and hash
- `seihou-core/src/Seihou/Core/Scaffold.hs` — generates `module.dhall` for `seihou new-module`; will emit schema-import-based modules
- `seihou-core/src/Seihou/Core/SchemaUpgrade.hs` — text-based module.dhall upgrader; will gain ability to inject schema imports
- `seihou-cli/data/assist-prompt.md`, `bootstrap-prompt.md`, `setup-prompt.md` — agent prompts embedded at compile time
- `flake.nix` — Nix build configuration; needs a new `seihou-schema-src` input
- `nix/haskell-overlay.nix` — Haskell package overlay; needs to copy schema into build environment
- `.claude/skills/update-seihou-schema/` — new skill for bumping the schema pin


## Plan of Work

The work is organized into seven milestones, each independently verifiable.


### Milestone 0: Push schema files to seihou-schema GitHub repository

The `seihou-schema` GitHub repository already exists at `https://github.com/shinzui/seihou-schema` but is currently empty. The local checkout is at `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema`.

At the end of this milestone, the repository contains the 8 Dhall schema files, `https://raw.githubusercontent.com/shinzui/seihou-schema/<commit>/package.dhall` resolves, and `dhall hash` produces a stable integrity hash.

The steps are:

1. Copy the 8 schema files from `schema/` in the seihou repo to the local seihou-schema checkout at `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema`:

        cp schema/*.dhall /Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema/

2. Add a minimal `README.md` explaining that this is the Dhall schema package for seihou modules.

3. Commit and push:

        cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema
        git add .
        git commit -m "Add seihou module schema package"
        git push

4. Record the commit hash and compute the Dhall integrity hash:

        git rev-parse HEAD
        dhall hash < package.dhall

    These values are needed for `SchemaVersion.hs` in Milestone 1 and for the submodule pin.

Verification: `curl -s https://raw.githubusercontent.com/shinzui/seihou-schema/<commit>/package.dhall` returns the package.dhall content.


### Milestone 1: Add git submodule and create SchemaVersion module

This milestone converts the `schema/` directory from a plain directory to a git submodule pointing at the new `seihou-schema` repository, and adds a Haskell module that pins the schema URL and integrity hash.

At the end of this milestone, `schema/` is a submodule, `Seihou.CLI.SchemaVersion` exports the pinned URL and hash, and the project builds successfully.

First, remove the existing `schema/` directory from git tracking (but keep the files on disk for the submodule to replace):

    git rm -r --cached schema/
    git commit -m "Remove schema/ from tracking (preparing for submodule)"

Then add the submodule:

    git submodule add git@github.com:shinzui/seihou-schema.git schema

This creates a `.gitmodules` file and checks out the schema repo at `schema/`.

Next, create `seihou-cli/src/Seihou/CLI/SchemaVersion.hs`:

    module Seihou.CLI.SchemaVersion
      ( schemaUrl,
        schemaHash,
        schemaImportLine,
      )
    where

    import Data.Text (Text)

    schemaUrl :: Text
    schemaUrl = "https://raw.githubusercontent.com/shinzui/seihou-schema/<COMMIT>/package.dhall"

    schemaHash :: Text
    schemaHash = "sha256:<HASH>"

    schemaImportLine :: Text
    schemaImportLine = "let S =\n      " <> schemaUrl <> "\n        " <> schemaHash

Replace `<COMMIT>` and `<HASH>` with the actual values from Milestone 0.

Add `Seihou.CLI.SchemaVersion` to the `other-modules` list in the `executable seihou` section of `seihou-cli/seihou-cli.cabal`.

Verification: `cabal build seihou-cli` compiles. `git submodule status` shows the schema submodule at the expected commit.


### Milestone 2: Update Scaffold to generate schema-import-based modules

This milestone changes `seihou new-module` so the generated `module.dhall` imports the schema via URL and uses record completion.

At the end of this milestone, `seihou new-module foo` produces a `module.dhall` that starts with `let S = https://raw.githubusercontent.com/...` and uses `S.Module::{...}` syntax.

Edit `seihou-core/src/Seihou/Core/Scaffold.hs`. The `moduleDhall` function currently generates inline Dhall with all fields spelled out. Change it to accept the schema URL and hash as parameters and generate a module that imports the schema:

    moduleDhall :: Text -> Text -> Text -> Text

Where the new parameters are the schema URL and schema hash. The generated output will look like:

    let S =
          https://raw.githubusercontent.com/shinzui/seihou-schema/<commit>/package.dhall
            sha256:<hash>

    in  S.Module::{
        , name = "my-module"
        , description = Some "A new seihou module"
        , vars =
          [ S.VarDecl::{
            , name = "project.name"
            , type = "text"
            , description = Some "The name of the project"
            , required = True
            }
          ]
        , prompts =
          [ S.Prompt::{
            , var = "project.name"
            , text = "What is your project name?"
            }
          ]
        , steps =
          [ S.Step::{
            , strategy = "template"
            , src = "README.md.tpl"
            , dest = "README.md"
            }
          ]
        }

The caller in `seihou-cli/src/Seihou/CLI/NewModule.hs` passes the URL and hash from `SchemaVersion`.

Update the scaffold test in `seihou-core/test/Seihou/Core/ScaffoldSpec.hs` to verify the new output format includes the schema import.

Verification: `seihou new-module test-schema-import` produces a `module.dhall` that imports the schema. `dhall type --file test-schema-import/module.dhall` succeeds (requires network for the first evaluation; Dhall caches imports).


### Milestone 3: Update schema-upgrade to inject schema imports

This milestone extends `seihou schema-upgrade` so that it detects modules missing the schema import and adds it. This is the key migration path for existing modules.

At the end of this milestone, running `seihou schema-upgrade` on any module.dhall — old or new — produces output that imports the schema via URL and uses `::` where possible.

This is the most complex milestone. The changes span two files:

In `seihou-core/src/Seihou/Core/SchemaUpgrade.hs`:

- Add a new `UpgradeIssue` constructor: `MissingSchemaImport`.
- Update `detectIssues` to check whether the module text contains a `let S =` or `let Schema =` line with the seihou-schema URL. If not, report `MissingSchemaImport`.
- The `upgradeModuleText` function needs to accept the schema URL and hash as parameters (or they can be passed in a config record).
- When `MissingSchemaImport` is detected, the upgrade produces a module that wraps the existing record in `let S = <url> <hash> in S.Module::{ ... }`. Since the existing record already has all fields (prior upgrade steps ensure this), the `::` operator's defaults are redundant but harmless — Dhall's `Prefer` gives precedence to the user's explicit fields.

For the initial implementation, the simplest approach is: prepend the `let S = ...` line and wrap the record body in `in `. This does NOT convert individual sub-records to use `S.Step::{}` etc. — that is a future enhancement. The critical thing is that the module is type-checked against the schema.

In `seihou-cli/src/Seihou/CLI/SchemaUpgrade.hs`:

- Pass the schema URL and hash from `SchemaVersion` to the core upgrade function.

Verification: Create a module without schema import, run `seihou schema-upgrade`, verify the output starts with `let S =` and evaluates with `dhall type`.


### Milestone 4: Update Nix build to handle schema submodule

This milestone ensures the Nix build can access the schema files at build time. In Nix builds, git submodules are not automatically included — the flake must explicitly provide them.

At the end of this milestone, `nix build .#seihou` succeeds and the built binary embeds the correct schema version.

In `flake.nix`, add a new input:

    inputs.seihou-schema-src = {
      url = "github:shinzui/seihou-schema/<COMMIT>";
      flake = false;
    };

Pass it through to the Haskell overlay:

    (import ./nix/haskell-overlay.nix {
      inherit pkgs gitRev;
      seihou-schema-src = inputs.seihou-schema-src;
    });

In `nix/haskell-overlay.nix`, accept the new parameter and copy the schema into the build environment so that Template Haskell `embedFile` calls referencing `../schema/` still work:

    { pkgs, gitRev, seihou-schema-src ? null }:

    final: prev: {
      seihou-core = ...;  -- unchanged

      seihou-cli = pkgs.haskell.lib.compose.overrideCabal
        (drv: {
          prePatch = (drv.prePatch or "") + (
            if seihou-schema-src != null then ''
              cp -r ${seihou-schema-src} ../schema
            '' else ""
          );
          configureFlags = ...;  -- unchanged
        })
        ...;
    }

Verification: `nix build .#seihou` succeeds. The resulting binary's `seihou --version` outputs correctly.


### Milestone 5: Create update-seihou-schema skill

This milestone creates a Claude Code skill that automates bumping the schema pin when the upstream `seihou-schema` repository changes.

At the end of this milestone, running the skill updates the submodule, recomputes the integrity hash, updates `SchemaVersion.hs`, updates the Nix flake lock, and commits the changes.

Create the skill at `.claude/skills/update-seihou-schema/SKILL.md`. The skill should:

1. Update the git submodule: `git submodule update --remote schema`
2. Get the new commit hash: `git -C schema rev-parse HEAD`
3. Compute the new integrity hash: `dhall hash < schema/package.dhall`
4. Update `seihou-cli/src/Seihou/CLI/SchemaVersion.hs` with the new URL and hash
5. Update the Nix flake input: `nix flake lock --update-input seihou-schema-src`
6. Build and test: `cabal build seihou-cli && cabal test all`
7. Commit: `git add schema .gitmodules seihou-cli/src/Seihou/CLI/SchemaVersion.hs flake.nix flake.lock && git commit -m "Bump seihou-schema to <short-commit>"`

Register the skill in `CLAUDE.md` or the appropriate skills index.

Verification: Make a trivial change to seihou-schema (e.g., add a comment), push it, then run the skill. The seihou repo should update to the new commit with a clean build.


### Milestone 6: Update documentation and agent prompts

This milestone updates all documentation and agent prompts to reflect that modules now import the schema via URL.

Files to update:

- `docs/user/module-authoring.md` — update the module.dhall format section to show the `let S = ...` import pattern as the primary format
- `docs/user/getting-started.md` — update the scaffold output example
- `docs/cli/schema-upgrade.md` — add `MissingSchemaImport` to the list of detected issues
- `seihou-cli/help/modules.md` — update the schema package section
- `seihou-cli/data/assist-prompt.md` — update module schema reference to show URL import
- `seihou-cli/data/bootstrap-prompt.md` — same
- `seihou-cli/data/setup-prompt.md` — same
- `docs/user/CHANGELOG.md` — add entry

Verification: `cabal build seihou-cli` succeeds (prompts are embedded at compile time). `seihou help modules` shows the updated content. `seihou agent assist --debug` shows the updated system prompt.


## Concrete Steps

All commands run from the repository root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

After Milestone 0 (manual, requires GitHub):

    # Verify the schema is accessible
    curl -s https://raw.githubusercontent.com/shinzui/seihou-schema/<COMMIT>/package.dhall | head -5

    # Compute integrity hash
    dhall hash < schema/package.dhall

After Milestone 1:

    cabal build seihou-cli
    git submodule status

Expected: build succeeds, submodule shows the pinned commit.

After Milestone 2:

    cabal run seihou-cli -- new-module /tmp/test-import-module
    head -5 /tmp/test-import-module/module.dhall

Expected: first line is `let S =`, second line is the GitHub URL.

After Milestone 3:

    # Create a legacy module
    echo '{ name = "legacy", version = None Text, ... }' > /tmp/legacy/module.dhall
    cabal run seihou-cli -- schema-upgrade /tmp/legacy --dry-run

Expected: reports `MissingSchemaImport` among the issues.

After Milestone 4:

    nix build .#seihou

Expected: build succeeds.

After Milestone 5:

    # The skill is invoked via Claude Code, not via command line

After Milestone 6:

    cabal build seihou-cli
    cabal run seihou-cli -- help modules

Expected: help output includes the URL import pattern.


## Validation and Acceptance

The change is accepted when:

1. `seihou new-module foo` generates a module.dhall that imports the schema via `https://raw.githubusercontent.com/shinzui/seihou-schema/<commit>/package.dhall sha256:<hash>` and uses `S.Module::{ ... }` syntax.

2. `seihou schema-upgrade` on a legacy module (without schema import) adds the `let S = ...` import line.

3. The upgraded module evaluates with `dhall type --file module.dhall` (Dhall type-checks against the schema).

4. `seihou validate-module` continues to work on both old-format and new-format modules (the Haskell decoder sees the same normalized record either way).

5. `cabal test all` passes.

6. `nix build .#seihou` succeeds.

7. The update-seihou-schema skill can bump the schema pin when the upstream repo changes.


## Idempotence and Recovery

Adding a git submodule is idempotent — if the submodule already exists, `git submodule add` is a no-op. The schema-upgrade command is already idempotent by design; adding schema import detection preserves this. The Nix flake lock update is also idempotent.

If the GitHub repository creation step fails or needs to be redone, the schema files are still present in the seihou repo's git history and can be re-extracted.

If a module's Dhall HTTP import fails (network issue, URL change), the error is clear — Dhall reports the failing URL. Users can fall back to the local submodule path (`./schema/package.dhall`) for development.


## Interfaces and Dependencies

No new external Haskell dependencies are required. The existing `dhall`, `file-embed`, `text`, and `githash` packages suffice.

In `seihou-cli/src/Seihou/CLI/SchemaVersion.hs`, define:

    schemaUrl :: Text
    schemaHash :: Text
    schemaImportLine :: Text

In `seihou-core/src/Seihou/Core/Scaffold.hs`, change the signature of:

    moduleDhall :: Text -> Text -> Text -> Text
    -- Arguments: module name, schema URL, schema hash

In `seihou-core/src/Seihou/Core/SchemaUpgrade.hs`, extend:

    data UpgradeIssue = ... | MissingSchemaImport

    -- upgradeModuleText gains schema URL/hash parameters or a config record
