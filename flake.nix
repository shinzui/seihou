{
  description = "製法 - Seihou";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";

  # Shared Haskell patch management
  inputs.haskell-nix.url = "github:shinzui/haskell-nix";
  inputs.haskell-nix.inputs.nixpkgs.follows = "nixpkgs";

  # Dhall schema package (non-flake, pinned to commit)
  inputs.seihou-schema-src = {
    url = "github:shinzui/seihou-schema/a0fba0d17b43b14bfdf6d0bf98f1b7ff7af4ebab";
    flake = false;
  };

  # Baikai provider abstraction packages (non-flake, pinned to commit)
  inputs.baikai-src = {
    url = "github:shinzui/baikai/e47a02ba740945e5aacf545b98c9ce81d2c26c4b";
    flake = false;
  };

  # Baikai provider dependencies (non-flake, pinned to commits)
  inputs.claude-src = {
    url = "github:shinzui/claude-project/60332ebb5686fa0a9ba2aa4ce9e582611cac4463";
    flake = false;
  };
  inputs.openai-src = {
    url = "github:shinzui/openai-project/ffb38dbd714e23bc5a9a11555dd9a34da4ffe5df";
    flake = false;
  };
  inputs.cradle-src = {
    url = "github:garnix-io/cradle/711c441fa8f190a8964c56a3bae864cd5321c5c5";
    flake = false;
  };


  outputs = { self, nixpkgs, pre-commit-hooks, flake-utils, treefmt-nix, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
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
              baikai-src = inputs.baikai-src;
              claude-src = inputs.claude-src;
              openai-src = inputs.openai-src;
              cradle-src = inputs.cradle-src;
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
