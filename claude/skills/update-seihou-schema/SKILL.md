# Update Seihou Schema

Bump the seihou-schema submodule to the latest commit and update all version pins.

## Steps

1. Update the git submodule to the latest remote commit:

       git submodule update --remote schema

2. Get the new commit hash:

       git -C schema rev-parse HEAD

3. Compute the new Dhall integrity hash:

       dhall hash < schema/package.dhall

4. Update `seihou-cli/src/Seihou/CLI/SchemaVersion.hs`:
   - Replace the commit hash in `schemaUrl` with the new commit
   - Replace the hash in `schemaHash` with the new integrity hash

5. Update the Nix flake input to point at the new commit. Edit `flake.nix` and change the commit hash in the `seihou-schema-src` input URL, then run:

       nix flake lock --update-input seihou-schema-src

6. Build and test:

       cabal build seihou-cli && cabal test all

7. Commit all changes:

       git add schema .gitmodules seihou-cli/src/Seihou/CLI/SchemaVersion.hs flake.nix flake.lock
       git commit -m "Bump seihou-schema to <short-commit>"

   Replace `<short-commit>` with the first 7 characters of the new commit hash.
