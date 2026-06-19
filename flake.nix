{
  description = "製法 - Seihou";

  inputs = {
    haskell-nix-dev.url = "github:shinzui/haskell-nix-dev";
    nixpkgs.follows = "haskell-nix-dev/nixpkgs";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    treefmt-nix.follows = "haskell-nix-dev/treefmt-nix";

    pre-commit-hooks.url = "github:cachix/git-hooks.nix";
    pre-commit-hooks.inputs.nixpkgs.follows = "nixpkgs";

    # Shared Haskell patch management (registry overlay), grafted onto the
    # haskell-nix-dev nixpkgs in flake.module.nix for the package build.
    haskell-nix.url = "github:shinzui/haskell-nix";
    haskell-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Dhall schema package (non-flake), sourced from the checked-in schema
    # submodule so Nix builds use the same schema revision as the repository.
    seihou-schema-src = {
      url = "git+file:./schema";
      flake = false;
    };

    # OKF core library source (non-flake, pinned to commit). Built via
    # callCabal2nix in ./nix/haskell-overlay.nix and consumed by `seihou docs`.
    # Keep this commit in sync with the okf-core source-repository-package in
    # cabal.project.
    okf-src = {
      url = "github:shinzui/okf/fb73a013adf7b4c5c65fd55552ea1fa47ed6a165";
      flake = false;
    };
  };

  nixConfig = {
    extra-substituters = [ ];
    extra-trusted-public-keys = [ ];
  };

  # Thin flake-parts shell. The dev toolchain comes from the haskell-nix-dev base
  # flake (GHC 9.12.4 / cabal / HLS via mkDevShell); project wiring lives in the
  # imported ./nix modules; the seihou package build and the cli-module-placement
  # check live in ./flake.module.nix.
  outputs = inputs@{ flake-parts, nixpkgs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.systems.flakeExposed;

      imports =
        [
          ./nix/haskell.nix
          ./nix/treefmt.nix
          ./nix/pre-commit.nix
        ]
        ++ nixpkgs.lib.optional (builtins.pathExists ./flake.module.nix) ./flake.module.nix;
    };
}
