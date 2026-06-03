# Project-specific build wiring for seihou. Kept out of the generated ./nix
# modules so it is the one place to evolve seihou's package build and checks.
#
# seihou-cli is built from a ghc9124 Haskell package set extended with two
# overlays: the shared haskell-nix registry (patch management) composed with
# ./nix/haskell-overlay.nix (seihou-core / seihou-cli via callCabal2nix, the
# seihou-schema submodule staged at ../schema, and the git revision baked into
# the binary).
{ inputs, ... }:
{
  perSystem = { system, pkgs, ... }:
    let
      gitRev = inputs.self.shortRev or "dirty";

      haskellPackages = pkgs.haskell.packages.ghc9124.override {
        overrides = pkgs.lib.composeExtensions
          (inputs.haskell-nix.lib.haskellExtension pkgs.haskell.lib.compose pkgs)
          (import ./nix/haskell-overlay.nix {
            inherit pkgs gitRev;
            seihou-schema-src = inputs.seihou-schema-src;
          });
      };
    in
    {
      packages.seihou = haskellPackages.seihou-cli;
      packages.default = haskellPackages.seihou-cli;

      # Enforce the CLI library-first module-placement convention as a flake
      # check (mirrors the pre-commit hook in ./nix/pre-commit.nix).
      checks.cli-module-placement = pkgs.runCommand "cli-module-placement-check"
        {
          src = inputs.self;
          nativeBuildInputs = [
            pkgs.bash
            pkgs.coreutils
            pkgs.findutils
            pkgs.gawk
            pkgs.gnugrep
            pkgs.gnused
          ];
        }
        ''
          cp -r $src ./repo
          chmod -R u+w ./repo
          cd ./repo
          bash nix/check-cli-module-placement.sh
          touch $out
        '';
    };
}
