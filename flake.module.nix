# Project-specific build wiring for seihou. Kept out of the generated ./nix
# modules so it is the one place to evolve seihou's package build and checks.
#
# seihou-cli is built from a ghc9124 Haskell package set extended with two
# overlays: the shared haskell-nix registry (patch management) composed with
# ./nix/haskell-overlay.nix (seihou-core / seihou-cli / seihou-okf-extension via
# callCabal2nix, Baikai packages pinned from baikai-src, the seihou-schema
# submodule staged at ../schema, and the git revision baked into the binary).
#
# The default (`seihou`) package is a symlinkJoin bundling the CLI with the OKF
# extension so a single install exposes both binaries on PATH; the raw CLI and
# extension remain available as `seihou-cli` and `seihou-okf-extension`.
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
            okf-src = inputs.okf-src;
            baikai-src = inputs.baikai-src;
          });
      };
      # Bundle the CLI together with the OKF extension so a single installed
      # package exposes both `seihou` and `seihou-okf-extension` on PATH. The
      # CLI discovers extensions via `findExecutable "seihou-<name>-extension"`
      # (see Seihou.CLI.Extension), so `seihou docs` / `seihou extension run okf`
      # only work when the extension binary is on PATH alongside the CLI.
      seihou-bundle = pkgs.symlinkJoin {
        name = "seihou";
        paths = [
          haskellPackages.seihou-cli
          haskellPackages.seihou-okf-extension
        ];
      };
    in
    {
      packages.seihou = seihou-bundle;
      packages.seihou-cli = haskellPackages.seihou-cli;
      packages.seihou-okf-extension = haskellPackages.seihou-okf-extension;
      packages.default = seihou-bundle;

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
