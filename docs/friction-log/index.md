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
