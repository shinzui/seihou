---
name: update-seihou-schema
description: Author or pull seihou-schema Dhall changes and re-pin them in this repository — bumps the schema submodule, the emitted URL/hash in SchemaVersion.hs, and flake.lock.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# Update Seihou Schema

Bump the `seihou-schema` Dhall schema this repository consumes, and update every pin that
references it.

## Which checkout is canonical

The canonical schema is the GitHub repository `shinzui/seihou-schema`, branch `master`. Every
local directory is just a working copy of it, and there are normally **two** on this machine:

- `schema/` — a git submodule of this repository. **This is the one that matters here.** Author
  schema changes in it. `flake.nix` sources the schema from it
  (`seihou-schema-src = { url = "git+file:./schema"; flake = false; }`),
  `nix/haskell-overlay.nix` copies it to `../schema` so Dhall-importing tests can resolve it, and
  `seihou-core/test/Seihou/Core/ScaffoldSpec.hs` resolves the local schema path from it.
- `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema` — a standalone clone that Mori's
  registry points at for dependency lookup. Nothing in this repository builds against it. It
  drifts easily: committing schema work there instead of in the submodule creates a second,
  unpushed lineage. Do not author schema changes there. If you need it current,
  `git -C <that path> pull --ff-only`.

Verify before you start:

    git -C schema fetch origin
    git -C schema status --branch --porcelain   # expect: ## master...origin/master, clean

## Authoring a new schema change

Do this when the schema itself needs a new type or field. Skip to "Pulling an existing change" if
someone else already pushed it.

1. Edit the `.dhall` files inside `schema/`, and update `schema/package.dhall` (export any new
   top-level record) and `schema/README.md` (its type list).

2. Type-check the package and prove the new field is authorable:

       dhall type --file schema/package.dhall > /dev/null && echo "package.dhall type-checks"

   For a new field, write a scratch file that uses it via record completion (`::`) and type-check
   that too, importing the schema by local path.

3. Commit **and push inside the submodule**. Pushing is mandatory, not optional: the pin in
   `SchemaVersion.hs` resolves over HTTPS from `raw.githubusercontent.com`, so an unpushed commit
   cannot be fetched by anyone — including this repository's own generated modules.

       git -C schema add <files>
       git -C schema commit -m "feat(schema): <what changed>"
       git -C schema push origin master

   The submodule is a separate repository: its commit does not carry this repository's
   `ExecPlan:` / `Intention:` trailers.

4. Continue with "Re-pin in this repository" below, starting at step 2 (the submodule is already
   at the commit you want).

## Pulling an existing change

1. Move the submodule to the latest remote commit on its tracked branch:

       git submodule update --remote schema

## Re-pin in this repository

2. Read the commit now checked out and compute the new Dhall integrity hash:

       git -C schema rev-parse HEAD
       dhall hash < schema/package.dhall

   The hash covers the fully resolved package including its imports, so it changes whenever any
   file in the schema changes.

3. Update `seihou-cli/src/Seihou/CLI/SchemaVersion.hs`:
   - Replace the commit hash inside `schemaUrl` with the new commit.
   - Replace the `sha256:...` value in `schemaHash` with the new integrity hash.

   Both must correspond to the same commit. A mismatch surfaces as a Dhall import failure
   complaining about the hash.

4. Refresh the flake lock. `flake.nix` follows the submodule by path
   (`git+file:./schema`), so there is **no URL or commit hash to edit there** — only the lock
   entry needs updating:

       nix flake update seihou-schema-src
       # older Nix: nix flake lock --update-input seihou-schema-src

5. Build and test:

       cabal build all && cabal test all

   `cabal test seihou-core` is the fast signal that the schema itself is sound: `ScaffoldSpec`
   decodes a generated `blueprint.dhall` against the local schema path.

6. Run the full gate, which also proves the submodule pointer, `flake.lock`, and
   `SchemaVersion.hs` agree:

       nix flake check

7. Commit, using Conventional Commits per this repository's `CLAUDE.md`:

       git add schema seihou-cli/src/Seihou/CLI/SchemaVersion.hs flake.lock
       git commit -m "chore(schema): bump seihou-schema to <short-commit>"

   Replace `<short-commit>` with the first 7 characters of the new commit hash. Add `.gitmodules`
   to the `git add` list only if the submodule's URL or branch actually changed; `flake.nix` is no
   longer part of this change.

   When the bump belongs to an ExecPlan, append that plan's `ExecPlan:` (and `Intention:`)
   trailers to the commit body.

## Never rewrite a published pin

Every `blueprint.dhall`, `module.dhall`, and `prompt.dhall` already authored in the wild embeds a
schema URL **and** its integrity hash. Force-pushing or rewriting a commit that has been used as a
pin breaks those files' imports permanently. If a pushed schema commit is wrong, fix it forward
with a new commit and re-pin. Recovery from a mistake that has **not** been pushed is
`git -C schema reset --hard origin/master`.
