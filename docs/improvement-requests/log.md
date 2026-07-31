# Bundle Update Log

## 2026-07-31
* **Addition**: IR-1 requests a not-applicable outcome for blueprint migration edges, so an edge
  that correctly declines an unmet precondition is not recorded as a completed upgrade and then
  silently skipped on the run that should have applied it.
