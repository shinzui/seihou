---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Friction Entry

- [Checkout tests require a newer schema than the local submodule](1-checkout-tests-require-a-newer-schema-than-the-local-submodule.md) - Checkout acceptance fixtures import a mutable local schema checkout and fail before exercising the command.
- [Native Nix test scope mixes incompatible Hspec releases](2-native-nix-test-scope-mixes-incompatible-hspec-releases.md) - The Seihou Nix package cannot configure hspec-api 2.11.17 against its resolved hspec-core 2.11.18.
- [Ambient Cabal build lacks zlib](3-ambient-cabal-build-lacks-zlib.md) - The ambient GHC 9.10.3 build fails configuring zlib; the Nix development shell supplies the supported toolchain and native libraries.
- [TAN consumer acceptance has no implemented producer artifact](4-tan-consumer-acceptance-has-no-implemented-producer-artifact.md) - The TAN registry is unregistered and contains no recipe, blocking final consumer acceptance.
- [Nix package tests lack Python and copy non-schema Mori imports](5-nix-package-tests-lack-python-and-copy-non-schema-mori-imports.md) - The published native package build failed after source checks because the isolated test environment lacked Python and schema fixtures copied Mori metadata with a remote import.
- [Home Manager also provides the installed Seihou executable](6-home-manager-also-provides-the-installed-seihou-executable.md) - The default-priority release installation collided with the Home Manager profile after removal of the old standalone package.
- [Isolated acceptance HOME hides private registry credentials](7-isolated-acceptance-home-hides-private-registry-credentials.md) - Isolating HOME and XDG settings for empty Seihou caches also hides the GitHub credential helper and gh authentication used by the private TAN registry.
- [Unpublished local registry candidates cannot replay in empty clones](8-unpublished-local-registry-candidates-cannot-replay-in-empty-clones.md) - Local-path and file-URL installs intentionally record no upstream, so a fresh clone with empty caches cannot fetch an unpublished producer candidate.
