# Bundle Update Log

## 2026-10-28
* **Update**: FRIC-3 resolved: Verified the supported development-shell workflow after the ambient native-library failure.
* **Addition**: FRIC-3 records detour environment friction with mori://shinzui/seihou: Ambient Cabal build lacks zlib

## 2026-10-27
* **Update**: FRIC-2 resolved: Verified upstream releases/bounds and adapter source; native core, CLI and extension suites and bundle build pass.
* **Addition**: FRIC-2 records blocked tooling friction with mori://shinzui/haskell-nix: Native Nix test scope mixes incompatible Hspec releases
* **Update**: FRIC-1 resolved: The same mutable-schema dependency recurred during plan 103 help acceptance; apply the pinned fixture strategy to the audit script too.
* **Update**: FRIC-1 resolved: Use the pinned fixture schema and verify the full CLI suite
* **Addition**: FRIC-1 records detour tooling friction with mori://shinzui/seihou: Checkout tests require a newer schema than the local submodule
* **Adoption**: Adopt the `friction-log` profile (`coordination.frictionLog`) from https://raw.githubusercontent.com/shinzui/okf-profiles/v0.23.0/package.dhall.
