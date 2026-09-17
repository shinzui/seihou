# Bundle Update Log

## 2026-09-17
* **Addition**: BUG-1 reported against seihou v0.9.0.0 (`9979f8d`) by `mori://tan/mls-service-v2`.
On a manifest written before the plan 90 / IR-8 `FileRecord.additiveOnly` field existed, every owner
of a co-owned path decodes as `additiveOnly = False` (fail-closed), so a single-module
`seihou update --commit nix-haskell-flake` fails closed on `.gitignore` even though all three owners
(`nix-haskell-flake`, `exec-plan`, `master-plan`) write it with idempotent additive patches. The
`SharedPathRequiresApplications` error (`Update/Render.hs:373-383`) lists three remedies worst-first:
`--include-shared-owners` (offered 2nd) does not record the fact — it expands the closure and
reconciles the co-owners' *entire* applications, ballooning a one-module upgrade into an eight-file
cross-application rewrite (7 unrelated `agents/skills/exec-plan/*` files) and still failing on the
next bare run; "select every owner" prints opaque `applicationId` SHAs that `seihou status` already
shows by name; and the only remedy that records the fact — a whole-project `seihou update` — is
buried last. The `CrossApplicationLastWriter` warning both the flag path and the no-target path emit
renders through the `warningText other = T.pack (show other)` fallthrough at `Update/Render.hs:331`,
leaking derived `Show` (`ModuleName {unModuleName = …}`) to the CLI. Severity `degraded`: the
whole-project `seihou update` is a working workaround that backfills `additiveOnly`, after which
targeted updates work. Reproduced with `--dry-run`. Status `reported` — not yet confirmed by seihou.
