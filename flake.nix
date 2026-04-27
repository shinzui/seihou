{
  description = "製法 - Seihou";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";

  # Shared Haskell patch management
  inputs.haskell-nix.url = "github:shinzui/haskell-nix";

  # Dhall schema package (non-flake, pinned to commit)
  inputs.seihou-schema-src = {
    url = "github:shinzui/seihou-schema/2b4035b7e720a9b30642a8a27551592175732ee5";
    flake = false;
  };


  outputs = { self, nixpkgs, pre-commit-hooks, flake-utils, treefmt-nix, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ inputs.haskell-nix.overlays.default ];
        };
        ghcVersion = "ghc9122";
        treefmtEval = treefmt-nix.lib.evalModule pkgs (import ./treefmt.nix { inherit pkgs ghcVersion; });
        formatter = treefmtEval.config.build.wrapper;

        gitRev = self.shortRev or "dirty";

        haskellPackages = pkgs.haskell.packages.${ghcVersion}.override {
          overrides = pkgs.lib.composeExtensions
            (inputs.haskell-nix.lib.haskellExtension pkgs.haskell.lib.compose pkgs)
            (import ./nix/haskell-overlay.nix {
              inherit pkgs gitRev;
              seihou-schema-src = inputs.seihou-schema-src;
            });
        };
      in
      {
        formatter = formatter;

        packages = {
          seihou = haskellPackages.seihou-cli;
          default = haskellPackages.seihou-cli;
        };

        checks = {
          formatting = treefmtEval.config.build.check self;
          pre-commit-check = pre-commit-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              treefmt.package = formatter;
              treefmt.enable = true;

              cli-module-placement = {
                enable = true;
                name = "cli-module-placement";
                entry = "${pkgs.bash}/bin/bash ${./nix/check-cli-module-placement.sh}";
                language = "system";
                pass_filenames = false;
              };
            };
          };
          cli-module-placement = pkgs.runCommand "cli-module-placement-check"
            {
              src = self;
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
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = [
            pkgs.zlib
            pkgs.xz
            pkgs.just
            pkgs.cabal-install
            pkgs.haskell.packages."${ghcVersion}".haskell-language-server
            pkgs.haskell.compiler."${ghcVersion}"
            pkgs.pkg-config
          ];
          shellHook = ''
            ${self.checks.${system}.pre-commit-check.shellHook}
          '';
        };
      }
    );
}
