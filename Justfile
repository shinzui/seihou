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

# `cabal haddock --haddock-for-hackage` nests the HTML of a package whose only
# library is a private sublibrary under <pkg>-<ver>-docs/<sublibrary>/ and names
# the Hoogle file with a colon; Hackage rejects both, and refuses GNU-format
# archives besides. This flattens the directory, renames the Hoogle file, and
# repacks as ustar. seihou-core has a public library and does not need it.
#
# Repack a private-sublibrary Haddock tarball into a form Hackage accepts.
docs-tarball package version:
  #!/usr/bin/env bash
  set -euo pipefail
  pkg='{{package}}'
  ver='{{version}}'
  src="dist-newstyle/${pkg}-${ver}-docs.tar.gz"
  [ -f "$src" ] || { echo "no such tarball: $src" >&2; exit 1; }
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  tar xzf "$src" -C "$work"
  dir="${pkg}-${ver}-docs"
  # The sublibrary directory is the one holding the colon-named Hoogle file.
  # Do not guess by "first subdirectory": a correctly packed tarball also has a
  # src/ directory, and picking that one would corrupt it.
  colon="$(find "$work/$dir" -name "${pkg}:*.txt" -print -quit)"
  [ -n "$colon" ] || { echo "$src is already flat; upload it as-is" >&2; exit 1; }
  sub="$(dirname "$colon")"
  mv "$colon" "$sub/${pkg}.txt"
  mv "$sub"/* "$work/$dir"/
  rmdir "$sub"
  out="dist-newstyle/repacked-docs"
  mkdir -p "$out"
  tar --format=ustar -czf "$out/${dir}.tar.gz" -C "$work" "$dir"
  echo "$out/${dir}.tar.gz"
