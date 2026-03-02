{ pkgs ? import <nixpkgs> { system = "{{nix.system}}"; } }:
pkgs.mkShell {
  buildInputs = [ pkgs.ghc ];
}
