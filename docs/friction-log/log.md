# Bundle Update Log

## 2026-10-29
* **Update**: FRIC-7 resolved: Correct the workaround: retaining Git and gh config paths alone did not preserve macOS keyring authentication under the isolated HOME.
* **Update**: FRIC-8 accepted: Retain the origin safety boundary and document the reproducible candidate-test preparation.
* **Update**: FRIC-7 resolved: Record the working private-registry authentication preparation; no credentials are written into evidence.
* **Addition**: FRIC-8 records detour interface friction with mori://shinzui/seihou: Unpublished local registry candidates cannot replay in empty clones
* **Addition**: FRIC-7 records detour environment friction with mori://shinzui/seihou: Isolated acceptance HOME hides private registry credentials

## 2026-10-28
* **Update**: FRIC-6 resolved: Record the successful priority-aware installation without removing Home Manager.
* **Update**: FRIC-5 resolved: The patch release resolves the native packaging gaps and adds the missing publication gate.
* **Addition**: FRIC-6 records detour environment friction with mori://shinzui/seihou: Home Manager also provides the installed Seihou executable
* **Addition**: FRIC-5 records detour tooling friction with mori://shinzui/seihou: Nix package tests lack Python and copy non-schema Mori imports
* **Update**: FRIC-4 accepted: Close Seihou prerequisite work independently of the downstream TAN producer, preserving the observed acceptance boundary.
* **Addition**: FRIC-4 records blocked environment friction with mori://tan/tan-seihou-modules: TAN consumer acceptance has no implemented producer artifact
* **Update**: FRIC-3 resolved: Verified the supported development-shell workflow after the ambient native-library failure.
* **Addition**: FRIC-3 records detour environment friction with mori://shinzui/seihou: Ambient Cabal build lacks zlib

## 2026-10-27
* **Update**: FRIC-2 resolved: Verified upstream releases/bounds and adapter source; native core, CLI and extension suites and bundle build pass.
* **Addition**: FRIC-2 records blocked tooling friction with mori://shinzui/haskell-nix: Native Nix test scope mixes incompatible Hspec releases
* **Update**: FRIC-1 resolved: The same mutable-schema dependency recurred during plan 103 help acceptance; apply the pinned fixture strategy to the audit script too.
* **Update**: FRIC-1 resolved: Use the pinned fixture schema and verify the full CLI suite
* **Addition**: FRIC-1 records detour tooling friction with mori://shinzui/seihou: Checkout tests require a newer schema than the local submodule
* **Adoption**: Adopt the `friction-log` profile (`coordination.frictionLog`) from https://raw.githubusercontent.com/shinzui/okf-profiles/v0.23.0/package.dhall.
