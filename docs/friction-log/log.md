# Bundle Update Log

## 2026-10-27
* **Update**: FRIC-1 resolved: The same mutable-schema dependency recurred during plan 103 help acceptance; apply the pinned fixture strategy to the audit script too.
* **Update**: FRIC-1 resolved: Use the pinned fixture schema and verify the full CLI suite
* **Addition**: FRIC-1 records detour tooling friction with mori://shinzui/seihou: Checkout tests require a newer schema than the local submodule
* **Adoption**: Adopt the `friction-log` profile (`coordination.frictionLog`) from https://raw.githubusercontent.com/shinzui/okf-profiles/v0.23.0/package.dhall.
