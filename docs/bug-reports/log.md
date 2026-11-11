# Bundle Update Log

## 2026-11-11
* **Update**: Audit: BUG-1 fixedVersion unreleased -> 0.10.0.0. Fix commits 8671930, d291e41 and ae31c38 (mori://shinzui/seihou/masterplans/11-make-manifest-evolution-explicit-and-targeted-updates-upgrade-safe) are first contained in tag v0.10.0.0, whose changelog lists the BUG-1 fix. Status fixed unchanged.
* **Update**: Audit: BUG-2 status reported -> fixed, fixedVersion 0.12.0.0. Implementation plan docs/plans/113-declare-and-install-cross-registry-recipe-dependencies.md (commit 8ea17ac, first tag v0.12.0.0, 0.12.0.0 changelog) installs the required dependency closure; the original github-repo/repo-dir reproduction was rerun in isolated XDG directories against installed 0.15.0.0 and installed repo-dir as required, and seihou run --dry-run exited 0.

## 2026-10-29
* **Update**: Record current model review metadata: BUG-3 completion evidence, and structural metadata only for BUG-1/BUG-2 without changing their dispositions or claiming historical verification.
* **Update**: BUG-3 fixed in released and installed Seihou 0.13.0.0 with published TAN recipe 0.1.1; verified ordinary owner-policy delivery.
* **Addition**: Add BUG-3: a recipe cannot enforce a variable that global config sets (from mori://tan/tan-platform).

## 2026-10-05
* **Addition**: BUG-2 reported against seihou v0.9.0.0 (`01173c3`) by `mori://shinzui/seihou-modules`.
`seihou install --module github-repo` installs only the named recipe and never its declared
`modules`/`dependencies` closure, so `seihou run github-repo` fails with `Module 'repo-dir' not found`
even though `repo-dir` lives in the same registry. Root cause in
`seihou-cli/src-exe/Seihou/CLI/Install.hs`: `selectModules` (lines 353-374) selects only the names
passed to `--module`, and `installRegistryEntry` (lines 454-494) installs a recipe's `recipe.dhall`
(or a module's `module.dhall`) without resolving its dependency closure the way `seihou run` does.
Severity `degraded`: the workaround is to install each dependency explicitly (`--module repo-dir`) or
install the whole registry with `--all`. Reproduced with `--dry-run`. Status `reported` — not yet
confirmed by seihou.

## 2026-09-18
* **Update**: BUG-1 status reported -\> fixed. Resolved by mori://shinzui/seihou/masterplans/11-make-manifest-evolution-explicit-and-targeted-updates-upgrade-safe: schema 7 sharedWriteMode, targeted in-plan certification of unknown shared paths without updating co-owners, labels instead of application ids, and prose for every update warning. Regression in seihou-cli/test/Seihou/CLI/UpdateE2ESpec.hs.

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
