---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Friction Entry

- [Checkout tests require a newer schema than the local submodule](1-checkout-tests-require-a-newer-schema-than-the-local-submodule.md) - Checkout acceptance fixtures import a mutable local schema checkout and fail before exercising the command.
- [Closure acceptance fixtures depend on the working schema gitlink](10-closure-acceptance-fixtures-depend-on-the-working-schema-gitlink.md) - The closure shell harness used record completion from the working schema checkout, so an older preserved gitlink rejected source-bearing edges before exercising the CLI.
- [Registered dependency source checkout is empty](11-registered-dependency-source-checkout-is-empty.md) - Mori resolves the directory dependency to an empty temporary checkout, so source inspection requires recovering the exact released package separately.
- [Running fourmolu directly fails to parse; only nix fmt formats Haskell sources](12-running-fourmolu-directly-fails-to-parse-only-nix-fmt-formats-haskell-sources.md) - The contributor docs never name the formatter entry point, and invoking fourmolu on a source file fails on ImportQualifiedPost, so formatting before commit took a detour through nix fmt.
- [seihou-cli-test e2e specs fail unless run from seihou-cli/](13-seihou-cli-test-e2e-specs-fail-unless-run-from-seihou-cli.md) - The seihou-cli test binary resolves the schema submodule relative to its working directory, so running it from the repository root fails about 90 end-to-end specs with a misleading git error, and cabal test --test-options cannot carry a -p pattern with spaces or ||.
- [update-seihou-schema skill describes a superseded flake input](14-update-seihou-schema-skill-describes-a-superseded-flake-input.md) - The update-seihou-schema skill says flake.nix follows the schema submodule by git+file path with nothing to edit, but flake.nix now pins seihou-schema-src by GitHub revision, so following the skill leaves the flake on the old schema.
- [Non-interactive seihou update cancels without naming --json](15-non-interactive-seihou-update-cancels-without-naming-json.md) - seihou update run without a terminal declines its own confirmation and prints only 'Update cancelled; no managed state was changed.', without saying that --json is the noninteractive way to apply it.
- [Mori registry unavailable through database tunnel](16-mori-registry-unavailable-through-database-tunnel.md) - Required registry discovery fails because the sungkyung PostgreSQL tunnel cannot connect.
- [Native Nix test scope mixes incompatible Hspec releases](2-native-nix-test-scope-mixes-incompatible-hspec-releases.md) - The Seihou Nix package cannot configure hspec-api 2.11.17 against its resolved hspec-core 2.11.18.
- [Ambient Cabal build lacks zlib](3-ambient-cabal-build-lacks-zlib.md) - The ambient GHC 9.10.3 build fails configuring zlib; the Nix development shell supplies the supported toolchain and native libraries.
- [TAN consumer acceptance has no implemented producer artifact](4-tan-consumer-acceptance-has-no-implemented-producer-artifact.md) - The TAN registry is unregistered and contains no recipe, blocking final consumer acceptance.
- [Nix package tests lack Python and copy non-schema Mori imports](5-nix-package-tests-lack-python-and-copy-non-schema-mori-imports.md) - The published native package build failed after source checks because the isolated test environment lacked Python and schema fixtures copied Mori metadata with a remote import.
- [Home Manager also provides the installed Seihou executable](6-home-manager-also-provides-the-installed-seihou-executable.md) - The default-priority release installation collided with the Home Manager profile after removal of the old standalone package.
- [Isolated acceptance HOME hides private registry credentials](7-isolated-acceptance-home-hides-private-registry-credentials.md) - Isolating HOME and XDG settings for empty Seihou caches also hides the GitHub credential helper and gh authentication used by the private TAN registry.
- [Unpublished local registry candidates cannot replay in empty clones](8-unpublished-local-registry-candidates-cannot-replay-in-empty-clones.md) - Local-path and file-URL installs intentionally record no upstream, so a fresh clone with empty caches cannot fetch an unpublished producer candidate.
- [Strict bug-report validation lacked review metadata in existing reports](9-strict-bug-report-validation-lacked-review-metadata-in-existing-reports.md) - The existing bug-report bundle lacked the reviews field recommended by its profile, so strict validation failed while recording delivery.
