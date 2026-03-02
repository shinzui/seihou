default:
  just --list

build:
  cabal build all

test:
  cabal test all

clean:
  cabal clean

format:
  nix fmt

check:
  nix flake check
