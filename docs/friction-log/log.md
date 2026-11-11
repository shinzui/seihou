# Bundle Update Log

## 2026-11-11

* **Update**: FRIC-17 accepted: Use the established producer authoring workflow; keep the unrelated external-link exporter defect outside plan 112.


* **Addition**: FRIC-17 records blocked tooling friction with mori://shinzui/seihou: Registry documentation generation fails on an existing external module link


* **Update**: FRIC-16 resolved: Correct diagnosis after user clarified the local database migration; verified registry access using local connection.


* **Addition**: FRIC-16 records blocked environment friction with mori://shinzui/mori: Mori registry unavailable through database tunnel


* **Addition**: FRIC-15 records slowdown interface friction with mori://shinzui/seihou: Non-interactive seihou update cancels without naming --json


* **Addition**: FRIC-14 records slowdown documentation friction with mori://shinzui/seihou: update-seihou-schema skill describes a superseded flake input


* **Addition**: FRIC-13 records detour tooling friction with mori://shinzui/seihou: seihou-cli-test e2e specs fail unless run from seihou-cli/


* **Update**: FRIC-12 resolved: Resolved by documenting the formatter entry point in the contributing guide under ExecPlan 120.

* **Addition**: FRIC-12 records slowdown documentation friction with mori://shinzui/seihou: Running fourmolu directly fails to parse; only nix fmt formats Haskell sources

## 2026-11-03
* **Update**: FRIC-6 resolved: Supersede the priority 4 install: its standalone entry left seihou stuck at 0.13.0.0 after 0.15.0.0 reached Home Manager.

## 2026-11-01
* **Update**: FRIC-11 accepted: Triage the stale temporary-source registration with an exact-version source recovery workaround.
* **Addition**: FRIC-11 records detour environment friction with mori://haskell/directory: Registered dependency source checkout is empty
* **Update**: FRIC-10 resolved: Resolve fixture/schema coupling after the full closure acceptance passes.
* **Addition**: FRIC-10 records detour tooling friction with mori://shinzui/seihou: Closure acceptance fixtures depend on the working schema gitlink

## 2026-10-29
* **Update**: FRIC-9 resolved: Reconcile existing review metadata while recording verified BUG-3 delivery.
* **Addition**: FRIC-9 records slowdown documentation friction with mori://shinzui/seihou: Strict bug-report validation lacked review metadata in existing reports
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
